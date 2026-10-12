[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$Path,
    [Parameter(Mandatory)][string]$RepositoryRoot,
    [Parameter(Mandatory)][string]$WorkItemId,
    [Parameter(Mandatory)][string]$RequestedAt,
    [Parameter(Mandatory)][string]$ExpectedRevision,
    [Parameter(Mandatory)][string]$Description,
    [Parameter(Mandatory)][string]$RespondentId
)
$ErrorActionPreference = 'Stop'
if ([string]::IsNullOrWhiteSpace($Description) -or $Description -notmatch '\S') { throw 'A nonempty human response is required.' }
if ($RespondentId -notmatch '^[a-z0-9][a-z0-9_-]{0,127}$') { throw 'RespondentId does not match the WorkItem actor contract.' }
$requested = [DateTimeOffset]::MinValue
if (-not [DateTimeOffset]::TryParse($RequestedAt, [Globalization.CultureInfo]::InvariantCulture, [Globalization.DateTimeStyles]::RoundtripKind, [ref]$requested) -or $requested.Offset -ne [TimeSpan]::Zero) { throw 'RequestedAt must be the exact UTC request timestamp.' }
Import-Module (Join-Path $PSScriptRoot 'WorkItemStore.psm1') -Force
$snapshot = Get-WorkItemStoreResult -Path $Path -RepositoryRoot $RepositoryRoot
$items = @($snapshot.Document.items | Where-Object { $_.id -ceq $WorkItemId })
if ($items.Count -ne 1) { throw 'WorkItem missing or ambiguous.' }
$item = $items[0]
if ($item.status -cne 'blocked' -or $null -eq $item.humanInteraction -or $item.humanInteraction.requestedAt -cne $RequestedAt) { throw 'Human response is not bound to this current blocked request.' }
if ($null -ne $item.humanInteraction.response) {
    $old = $item.humanInteraction.response
    if ($old.description -ceq $Description -and $old.respondentId -ceq $RespondentId) { return [pscustomobject]@{ persisted=$true; unchanged=$true; revision=$snapshot.Revision; workItemId=$WorkItemId } }
    throw 'A response is already persisted; it cannot be overwritten.'
}
$now = [DateTime]::UtcNow.ToString('yyyy-MM-ddTHH:mm:ss.fffffffZ')
$item.humanInteraction.response = [pscustomobject]@{ description=$Description; respondedAt=$now; respondentId=$RespondentId }
$item.updatedAt = $now
$writeResult = Set-WorkItemStoreEntry -Path $Path -Id $WorkItemId -Item $item -ExpectedRevision $ExpectedRevision -RepositoryRoot $RepositoryRoot
[pscustomobject]@{ persisted=$true; unchanged=$false; revision=$writeResult.Revision; workItemId=$WorkItemId; requestedAt=$RequestedAt; respondedAt=$now }
