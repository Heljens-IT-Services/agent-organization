[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$StorePath,
    [Parameter(Mandatory)][string]$WorkItemId,
    [Parameter(Mandatory)][string]$RepositoryRoot,
    [Parameter(Mandatory)][string]$ExpectedRevision,
    [Parameter(Mandatory)][string]$MeasurementId,
    [Parameter(Mandatory)][string]$Metric,
    [Parameter(Mandatory)][string]$Unit,
    [Parameter(Mandatory)][string]$Value,
    [Parameter(Mandatory)][string]$MeasuredAt,
    [Parameter(Mandatory)][string]$Source,
    [Parameter(Mandatory)][string]$Definition,
    [Parameter(Mandatory)][string]$Period
)
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'AccountingEvidence.psm1') -Force
foreach ($text in @($MeasurementId,$Metric,$Unit,$Value,$Source,$Definition,$Period)) { $null = Get-Text $text }
$measured = Get-UtcTime $MeasuredAt
Import-Module (Join-Path $RepositoryRoot 'scripts/workitems/WorkItemStore.psm1') -Force
$snapshot = Get-WorkItemStoreResult -Path $StorePath -RepositoryRoot $RepositoryRoot
if (-not $snapshot.Exists -or $snapshot.Revision -cne $ExpectedRevision) { throw 'Missing store or revision conflict.' }
$matches = @($snapshot.Document.items | Where-Object { $_.id -ceq $WorkItemId })
if ($matches.Count -ne 1) { throw 'WorkItem missing or ambiguous.' }
$item = $matches[0]
if ($item.status -in @('accepted','cancelled')) { throw 'Terminal WorkItem cannot be changed.' }
if ($Metric -cne $item.goal.metric) { throw 'Metric must exactly match goal.metric.' }
if ($null -eq $item.result) { throw 'Substantive result required before appending an observation.' }
$measurement = [pscustomobject][ordered]@{
    version=1; workItemId=$WorkItemId; measurementId=$MeasurementId
    metric=$Metric; target=$item.goal.target; unit=$Unit; value=$Value
    measuredAt=$measured.ToString('o'); source=$Source; definition=$Definition; period=$Period
}
$same = @()
foreach ($entry in @($item.result.evidence)) {
    if ($entry -isnot [string] -or -not $entry.StartsWith('workitem-goal-measurement/v1:',[StringComparison]::Ordinal)) { continue }
    # Malformed existing evidence is never silently ignored or repaired by this writer.
    $existing = Get-EvidenceJson $entry 'workitem-goal-measurement/v1:'
    if ((Get-Field $existing 'measurementId') -ceq $MeasurementId) { $same += @($existing) }
}
if ($same.Count -gt 0) {
    if (@($same | Where-Object { (Get-CanonicalJson $_) -cne (Get-CanonicalJson $measurement) }).Count -gt 0) { throw 'Conflicting measurement ID; evidence retained.' }
    return [pscustomobject]@{Changed=$false; Revision=$snapshot.Revision; MeasurementId=$MeasurementId}
}
$line = 'workitem-goal-measurement/v1:'+(ConvertTo-Json -InputObject $measurement -Compress -Depth 10)
$item.result.evidence = @($item.result.evidence)+@($line)
$item.updatedAt = [DateTime]::UtcNow.ToString('o')
# Uses the established store lock/revision path; observation changes neither
# status, implementedAt, acceptedAt, reviewer decisions nor textual goal target.
$written = Set-WorkItemStoreEntry -Path $StorePath -Id $WorkItemId -Item $item -IsNew:$false -ExpectedRevision $ExpectedRevision -RepositoryRoot $RepositoryRoot
[pscustomobject]@{Changed=$written.Changed; Revision=$written.Revision; MeasurementId=$MeasurementId}
