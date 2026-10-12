[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$TaskId,
    [Parameter(Mandatory)][string]$AccountingDirectory,
    [string[]]$RootTaskIds,
    [switch]$ExactRootTasks,
    [string[]]$BoundWorkItemIds,
    [string]$BoundStorePath,
    [switch]$IncludeOwnRecords
)
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'AccountingEvidence.psm1') -Force
if (($BoundWorkItemIds -and -not $BoundStorePath) -or ($BoundStorePath -and -not $BoundWorkItemIds)) { throw 'Bound filters must be supplied together.' }
$rootId = Get-CanonicalId $TaskId
$roots = if ($RootTaskIds -and $RootTaskIds.Count) { @($RootTaskIds | ForEach-Object { Get-CanonicalId $_ } | Select-Object -Unique) } else { @($rootId) }
$entries = @(Read-UsageEntries $AccountingDirectory)
$selectedTasks = @{}
$queue = New-Object 'System.Collections.Generic.Queue[string]'
foreach ($root in $roots) { $queue.Enqueue($root) }
while ($queue.Count -gt 0) {
    $id = $queue.Dequeue()
    if ($selectedTasks.ContainsKey($id)) { continue }
    $selectedTasks[$id] = $true

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
# One selection feeds sums, coverage, own and details. No broad fallback candidates.
$missingTaskIds = @($selectedTasks.Keys | Where-Object {
    $id = $_
    @($candidate | Where-Object { $_.AliasTaskIds -ccontains $id }).Count -eq 0
})
$known = @($candidate | Where-Object { $_.identity.final -and $null -ne $_.identity.tokenUsage })
$provisional = @($candidate | Where-Object { -not $_.identity.final }).Count
$missing = $missingTaskIds.Count + @($candidate | Where-Object { $_.identity.final -and $null -eq $_.identity.tokenUsage }).Count
$totals = Get-UsageSum $known
$ownCandidate = @($candidate | Where-Object { $_.AliasTaskIds -ccontains $rootId })
$ownKnown = @($known | Where-Object { $_.AliasTaskIds -ccontains $rootId })
$ownTotals = Get-UsageSum $ownKnown
$ownComplete = ($ownCandidate.Count -gt 0 -and @($ownCandidate | Where-Object { -not $_.identity.final -or $null -eq $_.identity.tokenUsage }).Count -eq 0)
$result = [pscustomobject][ordered]@{
    task_id=$rootId
    own=$(if ($ownComplete) { $ownTotals } else { $null })
    own_known_partial=$ownTotals
    inclusive=$(if ($missing -eq 0 -and $provisional -eq 0) { $totals } else { $null })
    known_partial=$totals; missing_count=$missing; missing_task_ids=$missingTaskIds
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
