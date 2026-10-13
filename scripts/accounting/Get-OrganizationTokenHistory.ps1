[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$AccountingDirectory,
    [Parameter(Mandatory)][string]$RepositoryRoot,
    [string]$StorePath,
    [string]$WorkItemId
)
$ErrorActionPreference='Stop'
$readStarted=[DateTime]::UtcNow
Import-Module (Join-Path $PSScriptRoot 'AccountingEvidence.psm1') -Force
Import-Module (Join-Path $PSScriptRoot 'TokenHistory.psm1') -Force
$familyRequested=$PSBoundParameters.ContainsKey('WorkItemId')
if ($familyRequested -ne $PSBoundParameters.ContainsKey('StorePath')) { throw 'StorePath and WorkItemId must be supplied together.' }
# All native dedup/conflicts and artifact correlation precede scope selection.
$evidence=Read-UsageEntries $AccountingDirectory -HistoryDiagnostics
$entries=@($evidence.entries); $sourcePaths=@($evidence.sourcePaths)
$scope=[ordered]@{
    kind='organization_observed'; accountingDirectory=[IO.Path]::GetFullPath($AccountingDirectory)
    sourcePatterns=@($evidence.sourcePatterns); expectedSetComplete=$false
    inventoryCompleteness='unknown'; originalRootCapture='not_proven'; unboundTasksIncluded=$true
}
$storeRevision=$null
if ($familyRequested) {
    if ([string]::IsNullOrWhiteSpace($WorkItemId) -or [string]::IsNullOrWhiteSpace($StorePath)) { throw 'Explicit family selection required.' }
    Import-Module (Join-Path $RepositoryRoot 'scripts/workitems/WorkItemStore.psm1') -Force
    $snapshot=Get-WorkItemStoreResult -Path $StorePath -RepositoryRoot $RepositoryRoot
    if (-not $snapshot.Exists) { throw 'WorkItem store unavailable.' }
    $store=Get-CanonicalPath $StorePath; $storeRevision=$snapshot.Revision
    $items=@($snapshot.Document.items)
    if (@($items | Where-Object { $_.id -ceq $WorkItemId }).Count -ne 1) { throw 'Requested WorkItem not unique.' }
    $selected=New-Object System.Collections.Hashtable ([StringComparer]::Ordinal)
    $selected[$WorkItemId]=$true
    do {
        $changed=$false
        foreach ($item in $items) {
            if ($null -ne $item.parentId -and $selected.ContainsKey($item.parentId) -and -not $selected.ContainsKey($item.id)) { $selected[$item.id]=$true; $changed=$true }
        }
    } while ($changed)
    $entries=@($entries | Where-Object { $_.familyEligible -and $_.identity.storePath -ceq $store -and $selected.ContainsKey($_.identity.workItemId) })
    $scope.kind='workitem_family'; $scope['workItemId']=$WorkItemId; $scope['storePath']=$store
    $scope['includedWorkItemIds']=@($selected.Keys | Sort-Object); $scope.unboundTasksIncluded=$false
    $sourcePaths+=@([IO.Path]::GetFullPath($StorePath))
}
$coverage=[pscustomobject]@{
    status='known_partial'; inventoryCompleteness='unknown'; expectedSetComplete=$false
    familyCompletenessProven=$false; familyCompletenessReason='Observed accounting is not a complete expected task/turn inventory.'
    diagnostics=@($evidence.diagnostics)
    # Global diagnostics deliberately survive every scope/series filter.
    bindingGaps=@($evidence.diagnostics | Where-Object { $_.reason -ceq 'family_binding_unresolved' })
    parentBindingGaps=@($evidence.diagnostics | Where-Object { $_.reason -ceq 'parent_binding_unregistered' })
    nativeConflicts=@($evidence.diagnostics | Where-Object { $_.reason -ceq 'native_task_or_counter_conflict' })
    sourceFailures=@($evidence.diagnostics | Where-Object { $_.reason -cin @('source_unavailable','invalid_record') })
    expectedMissingCount=$null; originalRootCapture='not_proven'
}
$history=Get-TokenHistoryProjection $entries @($evidence.eligibleNativeKeys) $coverage
$history | Add-Member -NotePropertyName scope -NotePropertyValue ([pscustomobject]$scope)
$history | Add-Member -NotePropertyName readWindow -NotePropertyValue ([pscustomobject]@{
    startedAt=$readStarted.ToString('o'); endedAt=[DateTime]::UtcNow.ToString('o')
    sourcePaths=@($sourcePaths | Sort-Object -Unique); consistency='Sequential source reads; not an atomic inventory snapshot.'
})
# Revision follows attributed content and diagnostics, excluding volatile times.
$text=$history.records,$history.excluded,$history.coverage,$history.scope,$storeRevision | ConvertTo-Json -Depth 60 -Compress
$hasher=[Security.Cryptography.SHA256]::Create()
try { $revision=([BitConverter]::ToString($hasher.ComputeHash([Text.Encoding]::UTF8.GetBytes($text)))).Replace('-','').ToLowerInvariant() }
finally { $hasher.Dispose() }
$history | Add-Member -NotePropertyName projectionRevision -NotePropertyValue $revision
$history | Add-Member -NotePropertyName projectionGeneratedAtUTC -NotePropertyValue ([DateTime]::UtcNow.ToString('o'))
[pscustomobject]@{tokenHistory=$history;storeRevision=$storeRevision;readWindow=$history.readWindow}
