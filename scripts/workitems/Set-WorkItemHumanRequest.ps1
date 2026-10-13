[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$Path,
    [Parameter(Mandatory)][string]$RepositoryRoot,
    [Parameter(Mandatory)][string]$WorkItemId,
    [Parameter(Mandatory)][string]$ExpectedRevision,
    [Parameter(Mandatory)][ValidateSet('clarification','approval','action')][string]$Kind,
    [Parameter(Mandatory)][string]$Description,
    [Parameter(Mandatory)][string]$HumanId,
    [string]$ProposalReference,
    [string]$ProposalPath,
    [string]$PreviousRequestId
)
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'HumanInteraction.ps1')
Import-Module (Join-Path $PSScriptRoot 'WorkItemStore.psm1') -Force
$snapshot=Get-WorkItemStoreResult -Path $Path -RepositoryRoot $RepositoryRoot
if ($snapshot.Revision -cne $ExpectedRevision) { throw 'RevisionConflict: reload before requesting human input.' }
$items=@($snapshot.Document.items | Where-Object { $_.id -ceq $WorkItemId })
if ($items.Count -ne 1) { throw 'WorkItem missing or ambiguous.' }
$item=$items[0]
if ($item.status -cin @('accepted','cancelled')) { throw 'Terminal WorkItems are immutable; plan a new WorkItem.' }
$proposal=$null
if ($Kind -ceq 'approval' -or $ProposalReference -or $ProposalPath) {
    if ([string]::IsNullOrWhiteSpace($ProposalReference) -or [string]::IsNullOrWhiteSpace($ProposalPath)) { throw 'Proposal reference and actual proposal file are both required.' }
    $proposal=[pscustomobject]@{reference=$ProposalReference; sha256=(Get-HIHash ([IO.File]::ReadAllBytes([IO.Path]::GetFullPath($ProposalPath)))); path=[IO.Path]::GetFullPath($ProposalPath)}
}
$nowTime=[DateTime]::UtcNow; $previousTime=[DateTimeOffset]::Parse($item.updatedAt).UtcDateTime
if ($nowTime -le $previousTime) { $nowTime=$previousTime.AddTicks(1) }
if ($null -ne $item.humanInteraction) {
    if ($PreviousRequestId -cne (Get-HIRequestId $item)) { throw 'Explicit predecessor request ID required for renewal/migration.' }
    $history=@(Get-HIValue $item 'humanInteractionHistory' @()) + @($item.humanInteraction)
    $item | Add-Member -NotePropertyName humanInteractionHistory -NotePropertyValue $history -Force
} elseif ($PreviousRequestId) { throw 'No predecessor exists.' }
$now=$nowTime.ToString('yyyy-MM-ddTHH:mm:ss.fffffffZ')
# Only the exact prior human response marker is replaced by a renewed request.
# Any other block reason remains an independent obstacle.
if ($null -ne $item.blockReason -and $item.blockReason -ceq (Get-HIResponseBlockReason $item.humanInteraction)) { $item.blockReason=$null }
$item.humanInteraction=New-HIRequest $Kind $Description $HumanId $proposal $now
$item.status='blocked'; $item.updatedAt=$now
$write=Set-WorkItemStoreEntry -Path $Path -Id $WorkItemId -Item $item -ExpectedRevision $ExpectedRevision -RepositoryRoot $RepositoryRoot
[pscustomobject]@{persisted=$true; revision=$write.Revision; workItemId=$WorkItemId; requestId=$item.humanInteraction.requestId; requestedAt=$now; proposal=$proposal}
