[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$TaskId,
    [Parameter(Mandatory)][string]$AccountingDirectory,
    [Parameter(Mandatory)][string]$RepositoryRoot,
    [Parameter(Mandatory)][string]$ArchiveDirectory,
    [string]$StorePath, [string]$WorkItemId,
    [string[]]$ExpectedJobArtifacts=@(), [string[]]$ExpectedTaskSources=@(),
    [string[]]$ImportRolloutPaths=@(), [string[]]$NativeRolloutPaths=@(),
    [string[]]$NativeEventLogPaths=@(), $OriginalInput
)
$ErrorActionPreference='Stop'
Import-Module (Join-Path $PSScriptRoot 'AccountingEvidence.psm1')
Import-Module (Join-Path $PSScriptRoot 'OriginalUsageAccountingHandoff.psm1')
if ([bool]$WorkItemId -xor [bool]$StorePath) { throw 'WorkItem/store must be supplied together.' }
$selected=New-Object System.Collections.Hashtable ([StringComparer]::Ordinal)
if ($WorkItemId) {
    $storeBefore=Get-UsageSourceHash ([IO.File]::ReadAllBytes($StorePath))
    Import-Module (Join-Path $RepositoryRoot 'scripts/workitems/WorkItemStore.psm1')
    $snapshot=Get-WorkItemStoreResult -Path $StorePath -RepositoryRoot $RepositoryRoot
    if (-not $snapshot.Exists -or @($snapshot.Document.items | Where-Object id -ceq $WorkItemId).Count -ne 1) { throw 'Requested WorkItem missing.' }
    $selected[$WorkItemId]=$true
    do {
        $changed=$false
        foreach ($item in $snapshot.Document.items) {
            if ($null -ne $item.parentId -and $selected.ContainsKey($item.parentId) -and -not $selected.ContainsKey($item.id)) {
                $selected[$item.id]=$true; $changed=$true
            }
        }
    } while ($changed)
    if ((Get-UsageSourceHash ([IO.File]::ReadAllBytes($StorePath))) -cne $storeBefore) { throw 'Store changed during scope selection.' }
}
$captures=@(Read-OriginalUsageCaptures $AccountingDirectory)
$bindings=@($captures | ForEach-Object binding)+@(Read-OriginalUsageTurnExpectations $AccountingDirectory)
$executions=Read-ExecutionEvidence $AccountingDirectory @(Read-UsageEntries $AccountingDirectory)
foreach ($execution in $executions.Values) {
    if ($execution.conflicts.Count -eq 0 -and $execution.artifactCount -gt 0) { $bindings+=@(New-AccountingBinding $execution $execution.sources) }
}
$jobs=@($ExpectedJobArtifacts | Select-Object -Unique)
foreach ($path in $jobs) {
    $document=Get-Content -LiteralPath $path -Raw -Encoding UTF8 | ConvertFrom-Json
    $bindings+=@(New-AccountingBinding $document @($path))
}
$imports=@(); $gaps=@()
# Never discover sessions. Only caller-selected original rollout files are read.
# Ordinary internal rollouts go to the existing importer; explicitly ordinal
# public native sources go separately to the retention/native reader.
foreach ($path in @($ImportRolloutPaths | Select-Object -Unique)) {
    $file=Get-Item -LiteralPath $path
    if ($file.PSIsContainer -or $file.Name -notmatch '^rollout-\d{4}-\d{2}-\d{2}T\d{2}-\d{2}-\d{2}-([0-9a-fA-F-]{36})\.jsonl$') { throw 'Explicit rollout filename identity required.' }
    $thread=Get-CanonicalId $Matches[1]
    $threadBindings=@($bindings | Where-Object { $_.threadId -ceq $thread -and $null -ne $_.taskId -and
        (-not $WorkItemId -or ($_.storePath -ceq (Get-CanonicalPath $StorePath) -and $null -ne $_.workItemId -and $selected.ContainsKey($_.workItemId))) })
    $turns=@(); $completionRecords=@{}; $ownSession=$false
    $stream=[IO.File]::Open($file.FullName,[IO.FileMode]::Open,[IO.FileAccess]::Read,[IO.FileShare]::ReadWrite)
    $reader=[IO.StreamReader]::new($stream,[Text.UTF8Encoding]::new($false,$true),$false)
    try {
        while ($null -ne ($line=$reader.ReadLine())) {
            $record=$line | ConvertFrom-Json
            if ($record.type -ceq 'session_meta') {
                $ownSession=((Get-CanonicalId (Get-Field $record.payload 'id')) -ceq $thread)
            }
            if ($ownSession -and $record.type -ceq 'event_msg' -and (Get-Field $record.payload 'type') -ceq 'task_complete') {
                $eventThread=Get-CanonicalId (Get-Field $record.payload 'thread_id') -Optional
                if ($null -ne $eventThread -and $eventThread -cne $thread) { continue }
                $completedTurn=Get-CanonicalId (Get-Field $record.payload 'turn_id')
                $turns+=@($completedTurn); $completionRecords[$completedTurn]=$line
            }
        }
    } finally { $reader.Dispose() }
    foreach ($turn in @($turns | Select-Object -Unique)) {
        # A resumed thread can contain turns of OTHER executions/WorkItems.
        # Only an exact independent turn binding permits attribution/import.
        $exact=@($threadBindings | Where-Object turnId -ceq $turn)
        $resolved=Resolve-AccountingBindings $exact
        $scopeKeys=@($resolved.rows | ForEach-Object { ConvertTo-Json -Compress -InputObject @($_.taskId,$_.executionId,$_.workItemId,$_.storePath) } | Select-Object -Unique)
        if ($resolved.conflicts.Count -gt 0 -or $scopeKeys.Count -ne 1) {
            $gaps+=@([pscustomobject]@{source=$file.FullName;threadId=$thread;turnId=$turn;reason='exact_turn_scope_binding_missing_or_conflicting'})
            continue
        }
        $binding=$resolved.rows[0]
        $roles=@(@($captures | Where-Object { $_.binding.taskId -ceq $binding.taskId } | ForEach-Object role)+
            @(foreach ($jobPath in $jobs) {
                $job=Get-Content -LiteralPath $jobPath -Raw -Encoding UTF8 | ConvertFrom-Json
                if ((Get-CanonicalId (Get-PairedField $job 'task_id' 'taskId') -Optional) -ceq $binding.taskId) { Get-Field $job 'role' }
            }) | Where-Object { $_ } | Select-Object -Unique)
        if ($roles.Count -ne 1) {
            $gaps+=@([pscustomobject]@{source=$file.FullName;threadId=$thread;turnId=$turn;reason='historical_assigned_role_missing_or_conflicting'})
            continue
        }
        $jobs+=@(Save-OriginalUsageTurnExpectation -AccountingDirectory $AccountingDirectory -Binding $binding -TurnId $turn -Role $roles[0] -SourcePath $file.FullName -CompletedRecord $completionRecords[$turn])
        $arguments=@{RolloutPath=$file.FullName;ThreadId=$thread;TurnId=$turn;Role=$roles[0];TaskId=$binding.taskId;AccountingDirectory=$AccountingDirectory}
        if ($null -ne $binding.workItemId) {
            $arguments.WorkItemId=$binding.workItemId; $arguments.ExecutionId=$binding.executionId; $arguments.StorePath=$binding.storePath
        }
        try { $imports+=@(& (Join-Path $PSScriptRoot 'Import-RolloutTaskUsage.ps1') @arguments) }
        catch { $gaps+=@([pscustomobject]@{source=$file.FullName;threadId=$thread;turnId=$turn;reason=$_.Exception.Message}) }
    }
}
$arguments=@{TaskId=$TaskId;AccountingDirectory=$AccountingDirectory;RepositoryRoot=$RepositoryRoot;ArchiveDirectory=$ArchiveDirectory;
    ExpectedJobArtifacts=$jobs;ExpectedTaskSources=$ExpectedTaskSources;NativeRolloutPaths=$NativeRolloutPaths;NativeEventLogPaths=$NativeEventLogPaths}
if ($WorkItemId) { $arguments.StorePath=$StorePath; $arguments.WorkItemId=$WorkItemId; $arguments.BoundWorkItemIds=[string[]]@($selected.Keys) }
if ($null -ne $OriginalInput) { $arguments.OriginalInput=$OriginalInput }
if ($WorkItemId -and (Get-UsageSourceHash ([IO.File]::ReadAllBytes($StorePath))) -cne $storeBefore) { throw 'Store changed during imports; preserve ledger, reject joint projection.' }
$projection=Invoke-OriginalUsageAccountingHandoff @arguments
[pscustomobject]@{imports=$imports;importGaps=$gaps;projection=$projection;familyCompletenessProven=$false;ownerAuthentication='not_asserted'}
