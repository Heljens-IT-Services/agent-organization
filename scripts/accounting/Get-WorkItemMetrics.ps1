[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$StorePath,
    [Parameter(Mandatory)][string]$WorkItemId,
    [Parameter(Mandatory)][string]$AccountingDirectory,
    [Parameter(Mandatory)][string]$RepositoryRoot,
    [string[]]$ExpectedTaskSources,
    [string[]]$ExpectedJobArtifacts,
    [string[]]$NativeRolloutPaths,
    [string[]]$NativeEventLogPaths
)
$ErrorActionPreference = 'Stop'
$readStarted = [DateTime]::UtcNow
Import-Module (Join-Path $PSScriptRoot 'AccountingEvidence.psm1') -Force
Import-Module (Join-Path $PSScriptRoot 'TokenHistory.psm1') -Force
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
# Read real reservation/transfer bindings before native projection. No writes.
$preNativeExecutions=Read-ExecutionEvidence $AccountingDirectory $entries
$executionBindings=@(foreach ($execution in $preNativeExecutions.Values) {
    if ($execution.initialTurns.Count -eq 0) { New-AccountingBinding $execution $execution.sources }
    else { foreach ($turn in $execution.initialTurns) { $binding=New-AccountingBinding $execution $execution.sources; $binding.turnId=$turn; $binding } }
})
$captures=@(Read-OriginalUsageCaptures $AccountingDirectory)
$turnExpectations=@(Read-OriginalUsageTurnExpectations $AccountingDirectory)
$supplementalBindings=@($family.tasks)+@($captures | ForEach-Object binding)+@($turnExpectations)+@($entries | ForEach-Object { New-AccountingBinding $_.identity $_.paths })+@($executionBindings)
$observedFamily = Read-ObservedAccountingFamily @($ExpectedJobArtifacts) @($NativeRolloutPaths) @() @($NativeEventLogPaths) $supplementalBindings
$nativeMerge = Merge-NativeAccountingMeasurements $entries $observedFamily.measurements
$entries = @($nativeMerge.entries)
$family.tasks = @($observedFamily.tasks | Where-Object { $null -ne $_.taskId })
$family.sources = @($family.sources) + @($observedFamily.sources)
# Includes every bound usage-only execution before subtree selection, preventing
# a reused execution ID outside the selected subtree from escaping correlation.
$executions = Read-ExecutionEvidence $AccountingDirectory $entries
$expected = @($executions.Values | Where-Object {
    @($_.scopeClaims | Where-Object { $_.storePath -ceq $store -and ($null -ne $_.workItemId -and $selected.ContainsKey($_.workItemId)) }).Count -gt 0
})
$unknownItems = @($selected.Keys | Where-Object {
    $id = $_
    @($expected | Where-Object { @($_.scopeClaims | Where-Object { $_.storePath -ceq $store -and $_.workItemId -ceq $id }).Count -gt 0 }).Count -eq 0
})
$selectedEntries = @($entries | Where-Object { $_.identity.storePath -ceq $store -and ($null -ne $_.identity.workItemId -and $selected.ContainsKey($_.identity.workItemId)) })
$expectedFamilyTasks = @($family.tasks | Where-Object { $_.storePath -ceq $store -and ($null -ne $_.workItemId -and $selected.ContainsKey($_.workItemId)) })
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
# The same scope expectations feed known finals, missing closure and own.
$scopedExpectations=@(Get-AccountingScopeExpectations $expectedFamilyTasks $observedFamily.nativeTurns)
foreach ($execution in $expected) {
    foreach ($turn in $execution.initialTurns) {
        $binding=New-AccountingBinding $execution $execution.sources; $binding.turnId=$turn
        $scopedExpectations+=@($binding)
    }
}
$allNativeConflicts=@($observedFamily.conflicts)+@($nativeMerge.conflicts)+@($family.conflicts)+@($conflicts)
$closure=Get-AccountingExpectedClosure $scopedExpectations $selectedEntries $allNativeConflicts
$nativeConflictKeys=@($closure.mask.nativeKeys)
$nativeConflictEntries=@($selectedEntries | Where-Object { $nativeConflictKeys -ccontains $_.native_key })
$missingNativeTurns=@($closure.missing | Where-Object { $null -ne $_.threadId -and $null -ne $_.turnId })
# Presence-only legacy gap calculations above remain diagnostics. Replace their
# closure result with final/conflict-aware gaps, then add execution inventory gaps.
$expectedMissing=@($closure.missing | ForEach-Object {
    [pscustomobject]@{workItemId=$_.workItemId;executionId=$_.executionId;taskId=$_.taskId;threadId=$_.threadId;turnId=$_.turnId;reason='expected_final_usage_missing_or_conflicted';sources=$_.sources}
})
foreach ($execution in $expected) {
    if ($execution.initialTurns.Count -eq 0 -and $execution.usageEntries.Count -eq 0) {
        $expectedMissing+=@([pscustomobject]@{workItemId=$execution.workItemId;executionId=$execution.executionId;taskId=$execution.taskId;threadId=$execution.threadId;turnId=$null;reason='expected_execution_final_closure_unknown';sources=$execution.sources})
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
$known=@($closure.known)
$missingUsage=@($selectedEntries | Where-Object { $_.identity.final -and $null -eq $_.identity.tokenUsage }).Count
$provisional=@($selectedEntries | Where-Object { -not $_.identity.final }).Count
$partial=Get-UsageSum $known
$ownEntries=@($selectedEntries | Where-Object { $_.identity.workItemId -ceq $WorkItemId })
$ownScope=@($scopedExpectations | Where-Object { $_.workItemId -ceq $WorkItemId -and $_.storePath -ceq $store })
$ownClosure=Get-AccountingExpectedClosure $ownScope $ownEntries $allNativeConflicts
$ownKnown=@($ownClosure.known); $ownPartial=Get-UsageSum $ownKnown
$rootExpected=@($expected | Where-Object { @($_.scopeClaims | Where-Object { $_.storePath -ceq $store -and $_.workItemId -ceq $WorkItemId }).Count -gt 0 })
$rootConflicts=@($rootExpected | ForEach-Object conflicts)
$rootGaps=@($bindingGaps | Where-Object workItemId -ceq $WorkItemId)
$rootMissing=@($expectedMissing | Where-Object workItemId -ceq $WorkItemId)
$rootIncomplete=@($incompleteTransfers | Where-Object workItemId -ceq $WorkItemId)
$ownMissingNativeTurns=@($ownClosure.missing)
$ownCoverageComplete=($ownClosure.complete -and $ownKnown.Count -gt 0 -and $rootConflicts.Count -eq 0 -and
    $rootGaps.Count -eq 0 -and $rootMissing.Count -eq 0 -and $rootIncomplete.Count -eq 0 -and
    @($ownEntries | Where-Object { -not $_.identity.final -or $null -eq $_.identity.tokenUsage -or $nativeConflictKeys -ccontains $_.native_key }).Count -eq 0)
$tokenCoverageComplete = $false
# A per-node projection follows every WorkItem edge, independently of task
# depth. Every subtree sum uses deduplicated own native entries directly;
# inclusive child projections are never inputs to another parent's sum.
$nodeTokens=@(foreach ($id in @($selected.Keys | Sort-Object)) {
    $nodeIds=New-Object System.Collections.Hashtable ([StringComparer]::Ordinal)
    $nodeIds[$id]=$true
    do {
        $expanded=$false
        foreach ($item in $items) {
            if ($null -ne $item.parentId -and $nodeIds.ContainsKey($item.parentId) -and -not $nodeIds.ContainsKey($item.id)) {
                $nodeIds[$item.id]=$true; $expanded=$true
            }
        }
    } while ($expanded)
    $nodeEntries=@($selectedEntries | Where-Object { $nodeIds.ContainsKey($_.identity.workItemId) })
    $nodeScope=@($scopedExpectations | Where-Object { $null -ne $_.workItemId -and $nodeIds.ContainsKey($_.workItemId) })
    $nodeClosure=Get-AccountingExpectedClosure $nodeScope $nodeEntries $allNativeConflicts
    $nodeOwnEntries=@($nodeEntries | Where-Object { $_.identity.workItemId -ceq $id })
    $nodeOwnScope=@($nodeScope | Where-Object { $_.workItemId -ceq $id })
    $nodeOwnClosure=Get-AccountingExpectedClosure $nodeOwnScope $nodeOwnEntries $allNativeConflicts
    $nodeOwnPartial=Get-UsageSum @($nodeOwnClosure.known)
    $nodeOwnComplete=($nodeOwnClosure.complete -and $nodeOwnClosure.known.Count -gt 0 -and
        @($bindingGaps | Where-Object workItemId -ceq $id).Count -eq 0 -and
        @($conflicts | Where-Object { $_.executionId -in @($expected | Where-Object workItemId -ceq $id | ForEach-Object executionId) }).Count -eq 0 -and
        @($incompleteTransfers | Where-Object workItemId -ceq $id).Count -eq 0 -and
        @($expectedMissing | Where-Object workItemId -ceq $id).Count -eq 0 -and
        @($nodeOwnEntries | Where-Object { -not $_.identity.final -or $null -eq $_.identity.tokenUsage -or $nativeConflictKeys -ccontains $_.native_key }).Count -eq 0)
    [pscustomobject]@{workItemId=$id;includedWorkItemIds=@($nodeIds.Keys | Sort-Object);
        own=$(if ($nodeOwnComplete) { $nodeOwnPartial } else { $null });ownKnownPartial=$nodeOwnPartial;
        ownCoverageComplete=$nodeOwnComplete;inclusive=$null;known_partial=(Get-UsageSum @($nodeClosure.known));
        descendantOwnKnownPartial=(Get-UsageSum @($nodeClosure.known | Where-Object { $_.identity.workItemId -cne $id }));
        expectedNativeTurns=@($nodeScope);missingExpectedNativeTurns=@($nodeClosure.missing);
        familyCompletenessProven=$false;familyCompletenessReason=$observedFamily.completenessReason}
})
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
    $history = Get-EntryTokenHistory $_
    [pscustomobject]@{
        task_id=$_.identity.taskId; AliasTaskIds=@($_.AliasTaskIds); native_key=$_.native_key
        parent_task_id=$_.identity.parentTaskId; parent_thread_id=$_.identity.parentThreadId; parent_turn_id=$_.identity.parentTurnId
        thread_id=$_.identity.threadId; turn_id=$_.identity.turnId; work_item_id=$_.identity.workItemId
        execution_id=$_.identity.executionId; work_item_store_path=$_.identity.storePath
        token_usage=$_.identity.tokenUsage; final=$_.identity.final; paths=@($_.paths)
        correlationValid=($executions[$_.identity.executionId].conflicts.Count -eq 0)
        roleId=$history.roleId; modelId=$history.modelId; reasoningEffort=$history.reasoningEffort
        measurementUTC=$history.measurementUTC; importedAtUTC=$history.importedAtUTC
        metadataSources=$history.metadataSources; metadataConflicts=$history.metadataConflicts; missingMetadata=$history.missingMetadata
    }
})
$sourcePaths = @($StorePath) + @($entries | ForEach-Object { $_.paths }) + @($executions.Values | ForEach-Object { $_.sources }) + @($family.sources) + @($observedFamily.sources)
$historyEligible=@($known | Where-Object { $executions[$_.identity.executionId].conflicts.Count -eq 0 } | ForEach-Object native_key)
$historyCoverage=[pscustomobject]@{
    familyCompletenessProven=$false; familyCompletenessReason=$observedFamily.completenessReason
    missingExpectedExecutions=$expectedMissing; missingExpectedNativeTurns=$missingNativeTurns
    executionSetUnknownWorkItemIds=$unknownItems; bindingGaps=$bindingGaps; parentBindingGaps=$parentGaps
    correlationConflicts=$conflicts; nativeConflicts=$allNativeConflicts; incompleteTransfers=$incompleteTransfers
}
$tokenHistory=Get-TokenHistoryProjection $selectedEntries $historyEligible $historyCoverage
$tokenHistory | Add-Member -NotePropertyName scope -NotePropertyValue ([pscustomobject]@{
    kind='workitem_family'; workItemId=$WorkItemId; includedWorkItemIds=@($selected.Keys | Sort-Object)
    storePath=$store; accountingDirectory=[IO.Path]::GetFullPath($AccountingDirectory)
    expectedNativeKeys=@($scopedExpectations | Where-Object { $_.storePath -ceq $store -and $null -ne $_.workItemId -and $selected.ContainsKey($_.workItemId) -and $null -ne $_.threadId -and $null -ne $_.turnId } | ForEach-Object { $_.threadId+'/'+$_.turnId } | Sort-Object -Unique)
    expectedSetComplete=$false; unboundTasksIncluded=$false
})
# Revision includes actual attributed content/coverage, not only store revision.
$historyText=$tokenHistory | ConvertTo-Json -Depth 60 -Compress
$historyHasher=[Security.Cryptography.SHA256]::Create()
try { $historyRevision=([BitConverter]::ToString($historyHasher.ComputeHash([Text.Encoding]::UTF8.GetBytes($historyText)))).Replace('-','').ToLowerInvariant() }
finally { $historyHasher.Dispose() }
$tokenHistory | Add-Member -NotePropertyName projectionRevision -NotePropertyValue $historyRevision
$tokenHistory | Add-Member -NotePropertyName projectionGeneratedAtUTC -NotePropertyValue ([DateTime]::UtcNow.ToString('o'))
[pscustomobject][ordered]@{
    workItemId=$WorkItemId; includedWorkItemIds=@($selected.Keys | Sort-Object); storePath=[IO.Path]::GetFullPath($StorePath); storeRevision=$snapshot.Revision
    accountingDirectory=[IO.Path]::GetFullPath($AccountingDirectory)
    tokenHistory=$tokenHistory
    readWindow=[pscustomobject]@{startedAt=$readStarted.ToString('o'); endedAt=[DateTime]::UtcNow.ToString('o'); sourcePaths=@($sourcePaths | Select-Object -Unique); consistency='Fixed store revision; sequential ledger/binding reads, not an atomic snapshot.'}
    tokenUsage=[pscustomobject]@{
        own=$(if ($ownCoverageComplete) { $ownPartial } else { $null }); ownKnownPartial=$ownPartial; ownCoverageComplete=$ownCoverageComplete
        inclusive=$null; known_partial=$partial
        perWorkItem=$nodeTokens
        missingExpectedExecutions=$expectedMissing; missingUsageRecords=$missingUsage; provisionalUsageRecords=$provisional
        familyCompletenessProven=$false; familyCompletenessReason=$observedFamily.completenessReason; familyConflicts=@($family.conflicts)+@($observedFamily.conflicts)+@($nativeMerge.conflicts); accountingDiagnostics=@($observedFamily.diagnostics)+@($nativeMerge.diagnostics); expectedFamilyTasks=$expectedFamilyTasks; missingExpectedNativeTurns=$missingNativeTurns
        incompleteTransfers=$incompleteTransfers; bindingGaps=$bindingGaps; parentBindingGaps=$parentGaps
        knownRecordCount=$known.Count; nativeConflictMeasurementCount=$nativeConflictEntries.Count; observedNativeTurns=$observedFamily.nativeTurns; taskCount=@($selectedEntries | ForEach-Object { $_.AliasTaskIds } | Select-Object -Unique).Count
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
