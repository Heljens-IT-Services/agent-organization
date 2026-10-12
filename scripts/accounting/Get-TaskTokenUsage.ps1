[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$TaskId,
    [Parameter(Mandatory)][string]$AccountingDirectory,
    [string[]]$RootTaskIds,
    [switch]$ExactRootTasks,
    [string[]]$BoundWorkItemIds,
    [string]$BoundStorePath,
    [string[]]$ExpectedTaskSources,
    [string[]]$ExpectedJobArtifacts,
    [string[]]$NativeRolloutPaths,
    [string[]]$NativeEventLogPaths,
    [switch]$IncludeOwnRecords
)
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'AccountingEvidence.psm1') -Force
if (($BoundWorkItemIds -and -not $BoundStorePath) -or ($BoundStorePath -and -not $BoundWorkItemIds)) { throw 'Bound filters must be supplied together.' }
$rootId = Get-CanonicalId $TaskId
$roots = if ($RootTaskIds -and $RootTaskIds.Count) { @($RootTaskIds | ForEach-Object { Get-CanonicalId $_ } | Select-Object -Unique) } else { @($rootId) }
$entries = @(Read-UsageEntries $AccountingDirectory)
$family = Read-ExpectedTaskFamily @($ExpectedTaskSources)
$supplementalBindings=@($family.tasks)+@($entries | ForEach-Object { New-AccountingBinding $_.identity $_.paths })
$observedFamily = Read-ObservedAccountingFamily @($ExpectedJobArtifacts) @($NativeRolloutPaths) $roots @($NativeEventLogPaths) $supplementalBindings
$nativeMerge = Merge-NativeAccountingMeasurements $entries $observedFamily.measurements
$entries = @($nativeMerge.entries)
$family.tasks = @($observedFamily.tasks | Where-Object { $null -ne $_.taskId })
$family.sources = @($family.sources) + @($observedFamily.sources)
$expectedFamilyTasks = @($family.tasks | Where-Object {
    (-not $BoundWorkItemIds -or ($_.storePath -ceq (Get-CanonicalPath $BoundStorePath) -and $BoundWorkItemIds -ccontains $_.workItemId))
})
$familyMatchesRoots = (@($family.coverage | Where-Object { (Compare-Object @($_.roots | Sort-Object) @($roots | Sort-Object) -SyncWindow 0) -eq $null -and $_.scope -ceq 'task' }).Count -gt 0)
$expectedById = @{}
foreach ($expectedTask in $family.tasks) { if (-not $expectedById.ContainsKey($expectedTask.taskId)) { $expectedById[$expectedTask.taskId] = @() }; $expectedById[$expectedTask.taskId] += @($expectedTask) }
$selectedTasks = @{}
$queue = New-Object 'System.Collections.Generic.Queue[string]'
foreach ($root in $roots) { $queue.Enqueue($root) }
while ($queue.Count -gt 0) {
    $id = $queue.Dequeue()
    if ($selectedTasks.ContainsKey($id)) { continue }
    $selectedTasks[$id] = $true

    # Expected jobs are authoritative task membership even before a usage file exists.
    foreach ($child in $expectedFamilyTasks) {
        if (-not $ExactRootTasks -and $child.parentTaskId -ceq $id -and -not $selectedTasks.ContainsKey($child.taskId)) { $queue.Enqueue($child.taskId) }
    }

    # A native thread/turn is the evidence for task-ID equivalence. Resolve every
    # alias of a reached measurement before following local parent-task references.
    foreach ($entry in $entries) {
        if ($entry.AliasTaskIds -ccontains $id) {
            foreach ($alias in $entry.AliasTaskIds) {
                if (-not $selectedTasks.ContainsKey($alias)) { $queue.Enqueue($alias) }
            }
        }
    }

    # Exact roots resolve native aliases but never add children. Bound WorkItem
    # selection is independently constrained by its explicit store/scope filter.
    if (-not $ExactRootTasks -and -not $BoundWorkItemIds) {
        foreach ($entry in $entries) {
            if ($null -ne $entry.identity.parentTaskId -and $entry.identity.parentTaskId -ceq $id) {
                foreach ($alias in $entry.AliasTaskIds) {
                    if (-not $selectedTasks.ContainsKey($alias)) { $queue.Enqueue($alias) }
                }
            }
        }
    }
}
$boundStore = if ($BoundStorePath) { Get-CanonicalPath $BoundStorePath } else { $null }
$candidate = @()
foreach ($entry in $entries) {
    $taskMatch = @($entry.AliasTaskIds | Where-Object { $selectedTasks.ContainsKey($_) }).Count -gt 0
    $scopeMatch = ($BoundWorkItemIds -and $BoundWorkItemIds -ccontains $entry.identity.workItemId -and $entry.identity.storePath -ceq $boundStore -and $null -ne $entry.identity.executionId)
    if ($BoundWorkItemIds) {
        if ($scopeMatch) { $candidate += @($entry) }
    } elseif ($taskMatch) { $candidate += @($entry) }
}
# Expectations and eligible finals share the exact selected scope.
$scopedBindings=@($expectedFamilyTasks | Where-Object { $selectedTasks.ContainsKey($_.taskId) })
$scopedExpectations=@(Get-AccountingScopeExpectations $scopedBindings $observedFamily.nativeTurns)
$allNativeConflicts=@($observedFamily.conflicts)+@($nativeMerge.conflicts)+@($family.conflicts)
$closure=Get-AccountingExpectedClosure $scopedExpectations $candidate $allNativeConflicts
$known=@($closure.known)
$nativeConflictKeys=@($closure.mask.nativeKeys)
$nativeConflictEntries=@($candidate | Where-Object { $nativeConflictKeys -ccontains $_.native_key })
$missingNativeTurns=@($closure.missing | Where-Object { $null -ne $_.threadId -and $null -ne $_.turnId })
$missingTaskIds=@(@($closure.missing | ForEach-Object taskId | Where-Object { $null -ne $_ })+@($selectedTasks.Keys | Where-Object {
    $id=$_; @($scopedExpectations | Where-Object taskId -ceq $id).Count -eq 0 -and @($known | Where-Object { $_.AliasTaskIds -ccontains $id }).Count -eq 0
}) | Select-Object -Unique)
$unmappedMissingNativeTurnCount=@($closure.missing | Where-Object { $null -eq $_.taskId }).Count
$provisional=@($candidate | Where-Object { -not $_.identity.final }).Count
# Count deduplicated expectation gaps; do not add overlapping task and turn gaps.
$missing=$closure.missing.Count+@($selectedTasks.Keys | Where-Object {
    $id=$_; @($scopedExpectations | Where-Object taskId -ceq $id).Count -eq 0 -and @($known | Where-Object { $_.AliasTaskIds -ccontains $id }).Count -eq 0
}).Count
$totals=Get-UsageSum $known
$ownCandidate=@($candidate | Where-Object { $_.AliasTaskIds -ccontains $rootId })
# Explicit loop avoids nested pipeline $_ confusion for unresolved thread claims.
$ownScope=@($scopedExpectations | Where-Object taskId -ceq $rootId)
foreach ($expectation in $scopedExpectations | Where-Object { $null -eq $_.taskId }) {
    if (@($scopedBindings | Where-Object { $_.taskId -ceq $rootId -and $_.threadId -ceq $expectation.threadId }).Count -gt 0) { $ownScope+=@($expectation) }
}
$ownClosure=Get-AccountingExpectedClosure $ownScope $ownCandidate $allNativeConflicts
$ownKnown=@($ownClosure.known); $ownTotals=Get-UsageSum $ownKnown
$ownExpectedTurns=@($ownClosure.missing)
$ownExpectedTaskMissing=$missingTaskIds -ccontains $rootId
$ownComplete=($ownClosure.complete -and $ownKnown.Count -gt 0 -and -not $ownExpectedTaskMissing -and
    @($ownCandidate | Where-Object { -not $_.identity.final -or $null -eq $_.identity.tokenUsage -or $nativeConflictKeys -ccontains $_.native_key }).Count -eq 0)
$unknownReasons = @()
if (-not $family.familyComplete -or -not $observedFamily.familyComplete) { $unknownReasons += $observedFamily.completenessReason }
if (-not $familyMatchesRoots) { $unknownReasons += 'family_completeness_unproven_or_wrong_roots' }
foreach ($conflict in @($family.conflicts) + @($observedFamily.conflicts) + @($nativeMerge.conflicts)) { $unknownReasons += $conflict.reason }
if ($missingTaskIds.Count -gt 0) { $unknownReasons += 'expected_task_or_final_usage_missing' }
if ($provisional -gt 0) { $unknownReasons += 'provisional_usage_not_final' }
if ($closure.missing.Count -gt 0) { $unknownReasons += 'expected_native_final_closure_missing' }
$result = [pscustomobject][ordered]@{
    task_id=$rootId
    own=$(if ($ownComplete) { $ownTotals } else { $null })
    own_known_partial=$ownTotals
    inclusive=$null
    known_partial=$totals; missing_count=$missing; missing_task_ids=$missingTaskIds; missing_expected_native_turns=$missingNativeTurns; observed_native_turns=$observedFamily.nativeTurns
    unknown_reasons=@($unknownReasons | Select-Object -Unique); accounting_conflicts=@($observedFamily.conflicts)+@($nativeMerge.conflicts); accounting_diagnostics=@($observedFamily.diagnostics)+@($nativeMerge.diagnostics); expected_family_task_ids=@($family.tasks | ForEach-Object taskId)
    provisional_count=$provisional; distinct_known_usage_count=$known.Count; task_count=$selectedTasks.Count
}
if ($IncludeOwnRecords) {
    $details = @($candidate | ForEach-Object {
        [pscustomobject]@{
            task_id=$_.identity.taskId; AliasTaskIds=@($_.AliasTaskIds)
            parent_task_id=$_.identity.parentTaskId; parent_thread_id=$_.identity.parentThreadId; parent_turn_id=$_.identity.parentTurnId
            thread_id=$_.identity.threadId; turn_id=$_.identity.turnId
            path=$_.paths[0]; paths=@($_.paths); native_key=$_.native_key
            work_item_id=$_.identity.workItemId; execution_id=$_.identity.executionId; work_item_store_path=$_.identity.storePath
            token_usage=$_.identity.tokenUsage; final=$_.identity.final
        }
    })
    $result | Add-Member -NotePropertyName record_details -NotePropertyValue $details
    $result | Add-Member -NotePropertyName own_records -NotePropertyValue @($known | ForEach-Object { $_.records[0] })
    $result | Add-Member -NotePropertyName duplicate_records -NotePropertyValue @($candidate | Where-Object { $_.paths.Count -gt 1 } | ForEach-Object {
        [pscustomobject]@{ nativeIdentity=$_.native_key; AliasTaskIds=@($_.AliasTaskIds); paths=@($_.paths) }
    })
}
$result
