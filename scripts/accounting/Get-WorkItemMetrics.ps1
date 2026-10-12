[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$StorePath,
    [Parameter(Mandatory)][string]$WorkItemId,
    [Parameter(Mandatory)][string]$AccountingDirectory,
    [Parameter(Mandatory)][string]$RepositoryRoot,
    [string[]]$ExpectedTaskSources
)
$ErrorActionPreference = 'Stop'
$readStarted = [DateTime]::UtcNow
Import-Module (Join-Path $PSScriptRoot 'AccountingEvidence.psm1') -Force
Import-Module (Join-Path $PSScriptRoot 'WorkItemMetricEvidence.psm1') -Force
Import-Module (Join-Path $RepositoryRoot 'scripts/workitems/WorkItemStore.psm1') -Force
# Designed production use of the existing revision/validation boundary, never
# invoked during this architecture task.
$snapshot = Get-WorkItemStoreResult -Path $StorePath -RepositoryRoot $RepositoryRoot
if (-not $snapshot.Exists) { throw 'WorkItem store missing.' }
$store = Get-CanonicalPath $StorePath
$items = @($snapshot.Document.items)
$byId = New-Object System.Collections.Hashtable ([StringComparer]::Ordinal)
foreach ($item in $items) {
    if ($byId.ContainsKey($item.id)) { throw 'Duplicate WorkItem ID.' }
    $byId[$item.id] = $item
}
if (-not $byId.ContainsKey($WorkItemId)) { throw 'Requested WorkItem missing.' }
$selected = New-Object System.Collections.Hashtable ([StringComparer]::Ordinal)
$selected[$WorkItemId] = $true
do {
    $changed = $false
    foreach ($item in $items) {
        if ($null -ne $item.parentId -and $selected.ContainsKey($item.parentId) -and -not $selected.ContainsKey($item.id)) {
            $selected[$item.id] = $true
            $changed = $true
        }
    }
} while ($changed)
$entries = @(Read-UsageEntries $AccountingDirectory)
$family = Read-ExpectedTaskFamily @($ExpectedTaskSources)
# Includes every bound usage-only execution before subtree selection, preventing
# a reused execution ID outside the selected subtree from escaping correlation.
$executions = Read-ExecutionEvidence $AccountingDirectory $entries
$expected = @($executions.Values | Where-Object {
    @($_.scopeClaims | Where-Object { $_.storePath -ceq $store -and $selected.ContainsKey($_.workItemId) }).Count -gt 0
})
$unknownItems = @($selected.Keys | Where-Object {
    $id = $_
    @($expected | Where-Object { @($_.scopeClaims | Where-Object { $_.storePath -ceq $store -and $_.workItemId -ceq $id }).Count -gt 0 }).Count -eq 0
})
$selectedEntries = @($entries | Where-Object { $_.identity.storePath -ceq $store -and $selected.ContainsKey($_.identity.workItemId) })
$expectedFamilyTasks = @($family.tasks | Where-Object { $_.storePath -ceq $store -and $selected.ContainsKey($_.workItemId) })
$conflicts = @($expected | ForEach-Object { $_.conflicts })
$bindingGaps = @(); $expectedMissing = @(); $parentGaps = @(); $incompleteTransfers = @()
foreach ($execution in $expected) {
    if ($null -eq $execution.taskId -or $null -eq $execution.threadId) {
        $bindingGaps += @([pscustomobject]@{workItemId=$execution.workItemId; executionId=$execution.executionId; reason='expected_task_or_native_thread_missing'; sources=$execution.sources})
    }
    if ($execution.incompleteTransfers.Count -gt 0) {
        $incompleteTransfers += @([pscustomobject]@{workItemId=$execution.workItemId; executionId=$execution.executionId; sources=$execution.incompleteTransfers; reason='transfer_not_complete'})
    }
    if ($execution.usageEntries.Count -eq 0) {
        $expectedMissing += @([pscustomobject]@{workItemId=$execution.workItemId; executionId=$execution.executionId; reason='expected_execution_usage_missing'; sources=$execution.sources})
    }
    if ($execution.artifactCount -gt 0 -and $execution.initialTurns.Count -eq 0) {
        $bindingGaps += @([pscustomobject]@{workItemId=$execution.workItemId; executionId=$execution.executionId; reason='reservation_transfer_initial_turn_unknown'; sources=$execution.sources})
    }
    foreach ($turn in $execution.initialTurns) {
        $initial = @($execution.usageEntries | Where-Object {
            $_.identity.threadId -ceq $execution.threadId -and $_.identity.turnId -ceq $turn
        })
        if ($initial.Count -eq 0) {
            $expectedMissing += @([pscustomobject]@{workItemId=$execution.workItemId; executionId=$execution.executionId; threadId=$execution.threadId; turnId=$turn; reason='expected_initial_turn_usage_missing'; sources=$execution.sources})
        }
    }
}
foreach ($expectedTask in $expectedFamilyTasks) {
    $observed = @($selectedEntries | Where-Object {
        $_.AliasTaskIds -ccontains $expectedTask.taskId -and $_.identity.parentTaskId -ceq $expectedTask.parentTaskId -and $_.identity.threadId -ceq $expectedTask.threadId -and $_.identity.turnId -ceq $expectedTask.turnId -and $_.identity.executionId -ceq $expectedTask.executionId -and $_.identity.storePath -ceq $expectedTask.storePath -and $_.identity.workItemId -ceq $expectedTask.workItemId
    })
    if ($observed.Count -eq 0) {
        $expectedMissing += @([pscustomobject]@{workItemId=$expectedTask.workItemId; executionId=$expectedTask.executionId; taskId=$expectedTask.taskId; threadId=$expectedTask.threadId; turnId=$expectedTask.turnId; reason='expected_family_task_usage_missing'; sources=$expectedTask.sources})
    }
    if ($null -eq $expectedTask.executionId -or $null -eq $expectedTask.threadId -or $null -eq $expectedTask.turnId) {
        $bindingGaps += @([pscustomobject]@{workItemId=$expectedTask.workItemId; executionId=$expectedTask.executionId; taskId=$expectedTask.taskId; reason='expected_family_native_binding_incomplete'; sources=$expectedTask.sources})
    }
}
foreach ($entry in $selectedEntries) {
    $identity = $entry.identity
    $parent = $identity.parentTaskId
    if ($null -eq $parent -and @($family.coverage | Where-Object { $_.scope -ceq 'workitem' -and $_.storePath -ceq $store -and $_.workItemIds -ccontains $identity.workItemId -and $_.roots -contains $identity.taskId }).Count -eq 0) {
        $parentGaps += @([pscustomobject]@{taskId=$identity.taskId; workItemId=$identity.workItemId; reason='parent_task_binding_missing'; sources=$entry.paths})
    } elseif ($null -ne $parent) {
        $parentEntries = @($entries | Where-Object { $_.AliasTaskIds -ccontains $parent })
        if ($parentEntries.Count -eq 0) {
            $parentGaps += @([pscustomobject]@{taskId=$identity.taskId; parentTaskId=$parent; workItemId=$identity.workItemId; reason='parent_record_not_observed'; sources=$entry.paths})
        } elseif ($null -ne $identity.parentThreadId -and $null -ne $identity.parentTurnId -and @($parentEntries | Where-Object {
            $_.identity.threadId -ceq $identity.parentThreadId -and $_.identity.turnId -ceq $identity.parentTurnId
        }).Count -eq 0) {
            $parentGaps += @([pscustomobject]@{taskId=$identity.taskId; parentTaskId=$parent; workItemId=$identity.workItemId; reason='parent_native_record_not_observed'; sources=$entry.paths})
        }
    }
    if (($null -eq $identity.parentThreadId -or $null -eq $identity.parentTurnId) -and $null -ne $identity.parentTaskId) {
        $parentGaps += @([pscustomobject]@{taskId=$identity.taskId; workItemId=$identity.workItemId; reason='parent_native_binding_incomplete'; sources=$entry.paths})
    }
}
# Same selected entries feed sums, missing/provisional counts, own and details.
# Contradictory executions do not contribute a purportedly trustworthy partial sum.
$usable = @($selectedEntries | Where-Object { $executions[$_.identity.executionId].conflicts.Count -eq 0 })
$known = @($usable | Where-Object { $_.identity.final -and $null -ne $_.identity.tokenUsage })
$missingUsage = @($selectedEntries | Where-Object { $_.identity.final -and $null -eq $_.identity.tokenUsage }).Count
$provisional = @($selectedEntries | Where-Object { -not $_.identity.final }).Count
$partial = Get-UsageSum $known
$ownEntries = @($selectedEntries | Where-Object { $_.identity.workItemId -ceq $WorkItemId })
$ownKnown = @($known | Where-Object { $_.identity.workItemId -ceq $WorkItemId })
$ownPartial = Get-UsageSum $ownKnown
$rootExpected = @($expected | Where-Object { @($_.scopeClaims | Where-Object { $_.storePath -ceq $store -and $_.workItemId -ceq $WorkItemId }).Count -gt 0 })
$rootConflicts = @($rootExpected | ForEach-Object { $_.conflicts })
$rootGaps = @($bindingGaps | Where-Object { $_.workItemId -ceq $WorkItemId })
$rootMissing = @($expectedMissing | Where-Object { $_.workItemId -ceq $WorkItemId })
$rootIncomplete = @($incompleteTransfers | Where-Object { $_.workItemId -ceq $WorkItemId })
$ownCoverageComplete = ($rootExpected.Count -gt 0 -and $rootConflicts.Count -eq 0 -and $rootGaps.Count -eq 0 -and $rootMissing.Count -eq 0 -and $rootIncomplete.Count -eq 0 -and
    @($ownEntries | Where-Object { -not $_.identity.final -or $null -eq $_.identity.tokenUsage }).Count -eq 0)
$tokenCoverageComplete = $false
$lifecycle = @(); $measurements = @(); $goalDecisions = @(); $measurementGaps = @(); $criterionDecisions = @(); $measurementConflicts = @()
foreach ($item in $items) {
    if (-not $selected.ContainsKey($item.id)) { continue }
    $versionSnapshots = @($executions.Values | Where-Object { $_.conflicts.Count -eq 0 } | ForEach-Object { $_.versionSnapshots } | Where-Object {
        $_.storePath -ceq $store -and $_.workItemId -ceq $item.id
    })
    $projection = Get-WorkItemEvidenceProjection $item ($StorePath+'@revision='+$snapshot.Revision) $versionSnapshots
    $lifecycle += @($projection.lifecycle)
    $measurements += @($projection.measurements)
    $goalDecisions += @($projection.goalDecisions)
    $measurementGaps += @($projection.gaps)
    $criterionDecisions += @($projection.criterionDecisions)
    $measurementConflicts += @($projection.measurementConflictIds | ForEach-Object { [pscustomobject]@{workItemId=$item.id; measurementId=$_} })
}
$rootLifecycle = @($lifecycle | Where-Object { $_.id -ceq $WorkItemId })[0]
$classified = @($lifecycle | Where-Object { $null -ne $_.firstAcceptance })
$firstAccepted = @($classified | Where-Object { $_.firstAcceptance }).Count
$details = @($selectedEntries | ForEach-Object {
    [pscustomobject]@{
        task_id=$_.identity.taskId; AliasTaskIds=@($_.AliasTaskIds); native_key=$_.native_key
        parent_task_id=$_.identity.parentTaskId; parent_thread_id=$_.identity.parentThreadId; parent_turn_id=$_.identity.parentTurnId
        thread_id=$_.identity.threadId; turn_id=$_.identity.turnId; work_item_id=$_.identity.workItemId
        execution_id=$_.identity.executionId; work_item_store_path=$_.identity.storePath
        token_usage=$_.identity.tokenUsage; final=$_.identity.final; paths=@($_.paths)
        correlationValid=($executions[$_.identity.executionId].conflicts.Count -eq 0)
    }
})
$sourcePaths = @($StorePath) + @($entries | ForEach-Object { $_.paths }) + @($executions.Values | ForEach-Object { $_.sources }) + @($family.sources)
[pscustomobject][ordered]@{
    workItemId=$WorkItemId; includedWorkItemIds=@($selected.Keys | Sort-Object); storePath=[IO.Path]::GetFullPath($StorePath); storeRevision=$snapshot.Revision
    accountingDirectory=[IO.Path]::GetFullPath($AccountingDirectory)
    readWindow=[pscustomobject]@{startedAt=$readStarted.ToString('o'); endedAt=[DateTime]::UtcNow.ToString('o'); sourcePaths=@($sourcePaths | Select-Object -Unique); consistency='Fixed store revision; sequential ledger/binding reads, not an atomic snapshot.'}
    tokenUsage=[pscustomobject]@{
        own=$(if ($ownCoverageComplete) { $ownPartial } else { $null }); ownKnownPartial=$ownPartial; ownCoverageComplete=$ownCoverageComplete
        inclusive=$null; known_partial=$partial
        missingExpectedExecutions=$expectedMissing; missingUsageRecords=$missingUsage; provisionalUsageRecords=$provisional
        familyCompletenessProven=$false; familyCompletenessReason='family_inventory_verification_unavailable'; familyConflicts=$family.conflicts; expectedFamilyTasks=$expectedFamilyTasks
        incompleteTransfers=$incompleteTransfers; bindingGaps=$bindingGaps; parentBindingGaps=$parentGaps
        knownRecordCount=$known.Count; taskCount=@($selectedEntries | ForEach-Object { $_.AliasTaskIds } | Select-Object -Unique).Count
        records=$details; deduplicationDuplicates=@($selectedEntries | Where-Object { $_.paths.Count -gt 1 } | ForEach-Object { [pscustomobject]@{nativeIdentity=$_.native_key; AliasTaskIds=@($_.AliasTaskIds); paths=@($_.paths)} })
        correlationConflicts=$conflicts
    }
    executionCorrelation=[pscustomobject]@{
        expectedExecutionCount=$expected.Count; expectedRootExecutionCount=$rootExpected.Count
        executionSetUnknownWorkItemIds=$unknownItems; observedExecutionCoverageComplete=$tokenCoverageComplete
        executionHistoryCompleteness='unknown_expected_history_not_proven'; rootExecutionSetObserved=($rootExpected.Count -gt 0)
        rootExecutionSetCompleteness='unknown_without_complete_history_source'; bindings=$expected; correlationConflicts=$conflicts
    }
    lifecycle=$lifecycle; criterionDecisions=$criterionDecisions; goalMeasurements=$measurements; goalDecisions=$goalDecisions
    measurementGaps=$measurementGaps; measurementConflicts=$measurementConflicts
    goalAchievement=$rootLifecycle.goal.achievement; goalAchievementBasis=$rootLifecycle.goal.basis
    firstAcceptanceRate=[pscustomobject]@{numerator=$firstAccepted; denominator=$classified.Count; unknownCount=($lifecycle.Count-$classified.Count); value=$(if ($classified.Count -gt 0) { [double]$firstAccepted/$classified.Count } else { $null }); context='Selected WorkItem subtree, source-bound first review attempts.'}
    scopeLimit='Same-store explicit WorkItem executions, root and canonical descendants; unbound CLI tasks and coordinator goal meter excluded. Parent gaps separate from direct WorkItem measurement. Observed coverage is not proof of complete execution history.'
}
