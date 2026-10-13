[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$Path,
    [Parameter(Mandatory)][string]$RepositoryRoot,
    [Parameter(Mandatory)][string]$WorkItemId,
    [Parameter(Mandatory)][string]$RequestedAt,
    [Parameter(Mandatory)][string]$ExpectedRevision,
    [Parameter(Mandatory)][string]$Description,
    [Parameter(Mandatory)][string]$RespondentId,
    [Parameter(Mandatory)][string]$Evidence,
    [ValidateSet('provided','approved','rejected','insufficient')][string]$Decision = 'provided',
    [string]$RequestId,
    [string]$ProposalSha256,
    [string]$ProposalPath
)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'HumanInteraction.ps1')
# Existing execution marker separates the human input command from agent results.
if ($env:AGENT_ORG_PARENT_JOB_FILE) { throw 'Delegated agent execution cannot submit its own human response; use the human input channel.' }
if ([string]::IsNullOrWhiteSpace($Description) -or [string]::IsNullOrWhiteSpace($Evidence)) { throw 'Human response text and original input evidence are required.' }
if ($RespondentId -cnotmatch '^[a-z0-9][a-z0-9_-]{0,127}$') { throw 'RespondentId does not match the human actor contract.' }
$requested = [DateTimeOffset]::MinValue
if (-not [DateTimeOffset]::TryParse($RequestedAt, [Globalization.CultureInfo]::InvariantCulture, [Globalization.DateTimeStyles]::RoundtripKind, [ref]$requested) -or $requested.Offset -ne [TimeSpan]::Zero) { throw 'RequestedAt must be the exact UTC request timestamp.' }
Import-Module (Join-Path $PSScriptRoot 'WorkItemStore.psm1') -Force
$snapshot = Get-WorkItemStoreResult -Path $Path -RepositoryRoot $RepositoryRoot
if ($snapshot.Revision -cne $ExpectedRevision) { throw 'RevisionConflict: reload the current request before answering.' }
$items = @($snapshot.Document.items | Where-Object { $_.id -ceq $WorkItemId })
if ($items.Count -ne 1) { throw 'WorkItem missing or ambiguous.' }
$item = $items[0]; $human = $item.humanInteraction
if ($null -eq $human -or $human.requestedAt -cne $RequestedAt) { throw 'Human response is not bound to the current request.' }
$currentId = Get-HIRequestId $item
if ((Get-HIValue $human 'requestId') -and [string]::IsNullOrWhiteSpace($RequestId)) { throw 'The current request ID must be supplied explicitly.' }
if ($RequestId -and $RequestId -cne $currentId) { throw 'Human request ID mismatch.' }
$owner = Get-HIValue $human 'humanId'
if (-not $owner -and $item.owner.type -ceq 'human') { $owner = $item.owner.id }
if ($owner -and $owner -cne $RespondentId) { throw 'The respondent is not the responsible human.' }
$proposal = Get-HIValue $human 'proposal'
if ($human.kind -ceq 'approval' -and $null -eq $proposal) { throw 'Legacy approval needs an explicit renewed request with concrete proposal bytes; no historical answer is upgraded to approval.' }
if ($proposal) {
    Assert-HIProposal $proposal
    Assert-HIProposalCurrent $human
    if ($ProposalSha256 -cne $proposal.sha256 -or [string]::IsNullOrWhiteSpace($ProposalPath)) { throw 'Supply the exact proposal hash and the file containing the submitted proposal bytes.' }
    if ((Get-HIHash ([IO.File]::ReadAllBytes([IO.Path]::GetFullPath($ProposalPath)))) -cne $proposal.sha256) { throw 'Proposal bytes changed; request a new human answer.' }
} elseif ($ProposalSha256 -or $ProposalPath) { throw 'This request has no proposal binding.' }
if (($human.kind -ceq 'approval' -and $Decision -ceq 'provided') -or ($human.kind -cne 'approval' -and $Decision -ceq 'approved')) { throw 'Decision does not match the request.' }
if ($null -ne $human.response) {
    $old = $human.response
    if ($old.description -ceq $Description -and $old.respondentId -ceq $RespondentId -and (Get-HIValue $old 'decision') -ceq $Decision -and (Get-HIValue $old 'evidence') -ceq $Evidence -and [string](Get-HIValue $old 'proposalSha256') -ceq $ProposalSha256) { return [pscustomobject]@{persisted=$true; unchanged=$true; revision=$snapshot.Revision; workItemId=$WorkItemId; requestId=$currentId} }
    throw 'A response is already persisted; it cannot be overwritten.'
}
if ($item.status -cne 'blocked') { throw 'Only a currently blocked open request can receive a new answer.' }
$nowTime = [DateTime]::UtcNow
$previousTime = [DateTimeOffset]::Parse($item.updatedAt).UtcDateTime
if ($nowTime -le $previousTime) { $nowTime=$previousTime.AddTicks(1) }
$now = $nowTime.ToString('yyyy-MM-ddTHH:mm:ss.fffffffZ')
# Additive migration for old open informational/action requests, using real input.
foreach ($field in @('requestId','required','humanId','proposal','resolution')) {
    if (-not $human.PSObject.Properties[$field]) { $human | Add-Member -NotePropertyName $field -NotePropertyValue $null }
}
$human.requestId=$currentId; $human.required=$true; $human.humanId=$RespondentId
$human.response=[pscustomobject][ordered]@{description=$Description; respondedAt=$now; respondentId=$RespondentId; requestId=$currentId; decision=$Decision; evidence=$Evidence; proposalSha256=$(if($proposal){$proposal.sha256}else{$null})}
$human.resolution=if ($Decision -cin @('rejected','insufficient')) { $Decision } else { 'satisfied' }
$item.updatedAt=$now
# Persistent blocked remains until the coordinator's separate resume assessment.
if ($null -eq $item.blockReason) { $item.blockReason=Get-HIResponseBlockReason $human }
$writeResult=Set-WorkItemStoreEntry -Path $Path -Id $WorkItemId -Item $item -ExpectedRevision $ExpectedRevision -RepositoryRoot $RepositoryRoot -HumanResponseWrite
# The same CAS wrote a recoverable outbox intent; coordinator import emits the event.
[pscustomobject]@{persisted=$true; unchanged=$false; revision=$writeResult.Revision; workItemId=$WorkItemId; requestId=$currentId; requestedAt=$RequestedAt; respondedAt=$now; resolution=$human.resolution; eventState='outbox-persisted'}
