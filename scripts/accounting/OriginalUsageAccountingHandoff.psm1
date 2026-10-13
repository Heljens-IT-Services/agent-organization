Set-StrictMode -Version Latest
Import-Module (Join-Path $PSScriptRoot 'AccountingEvidence.psm1')

function Write-UsageImmutableDocument {
    param([string]$Path, $Document)
    $bytes=[Text.UTF8Encoding]::new($false).GetBytes(($Document | ConvertTo-Json -Depth 60 -Compress)+"`n")
    [void][IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($Path))
    if ([IO.File]::Exists($Path)) {
        $prior=[IO.File]::ReadAllBytes($Path)
        if ((Get-UsageSourceHash $prior) -cne (Get-UsageSourceHash $bytes)) { throw 'ImmutableUsageDocumentConflict; preserve existing source' }
        return $Path
    }
    $temporary=$Path+'.'+[guid]::NewGuid().ToString('N')+'.writing'
    try {
        [IO.File]::WriteAllBytes($temporary,$bytes)
        try { [IO.File]::Move($temporary,$Path) }
        catch {
            if (-not [IO.File]::Exists($Path) -or (Get-UsageSourceHash ([IO.File]::ReadAllBytes($Path))) -cne (Get-UsageSourceHash $bytes)) { throw }
        }
    } finally { if ([IO.File]::Exists($temporary)) { [IO.File]::Delete($temporary) } }
    return $Path
}

function Save-OriginalUsageAccountingCapture {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$JobPath,
        [Parameter(Mandatory)][string]$NativeAckPath,
        [Parameter(Mandatory)]$TurnStartReply,
        [Parameter(Mandatory)][string]$CurrentTurnMeasurementBasis)
    $jobBytes=[IO.File]::ReadAllBytes($JobPath)
    $job=[Text.UTF8Encoding]::new($false,$true).GetString($jobBytes) | ConvertFrom-Json
    $ackBytes=[IO.File]::ReadAllBytes($NativeAckPath)
    $ack=[Text.UTF8Encoding]::new($false,$true).GetString($ackBytes) | ConvertFrom-Json
    $task=Get-CanonicalId $job.task_id
    $thread=Get-CanonicalId $ack.threadId
    $turn=Get-CanonicalId $TurnStartReply.turn.id
    if ((Get-CanonicalId $ack.taskId) -cne $task -or (Get-CanonicalId $ack.reply.thread.id) -cne $thread) { throw 'OriginalCaptureThreadACKConflict' }
    # The runner owns this actual thread ACK and turn/start response.
    # This binds the selected turn, not all births of an external original root.
    $directory=[IO.Path]::GetFullPath($job.accounting_directory)
    $key=$task+'.'+$thread+'.'+$turn
    $turnAckPath=Join-Path $directory ($key+'.turn-ack.json')
    [void](Write-UsageImmutableDocument $turnAckPath $TurnStartReply)
    $record=[ordered]@{
        schema='original-usage-capture/v1'; task_id=$job.task_id; parent_task_id=$job.parent_task_id
        thread_id=$ack.threadId; turn_id=$TurnStartReply.turn.id
        parent_thread_id=$job.parent_thread_id; parent_turn_id=$job.parent_turn_id
        work_item_id=$job.work_item_id; execution_id=$job.execution_id; store_path=$job.work_item_store_path
        role=$job.role; provider=$ack.origin; generation=$ack.generation
        captureOwner=('starter-process:'+ [string]$PID)
        jobPath=[IO.Path]::GetFullPath($JobPath); jobSha256=(Get-UsageSourceHash $jobBytes)
        nativeAckPath=[IO.Path]::GetFullPath($NativeAckPath); nativeAckSha256=(Get-UsageSourceHash $ackBytes)
        turnAckPath=$turnAckPath; turnAckSha256=(Get-UsageSourceHash ([IO.File]::ReadAllBytes($turnAckPath)))
        captureBasis='owned_thread_turn_start_ack'; currentTurnMeasurementBasis=$CurrentTurnMeasurementBasis
        initial_execution_turn=$true
        familyComplete=$false; ownerAuthentication='not_asserted'
    }
    return Write-UsageImmutableDocument (Join-Path $directory ($key+'.capture.json')) $record
}

function Publish-OriginalUsageLedger {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$AccountingDirectory, [Parameter(Mandatory)]$Record)
    $identity=Get-UsageIdentity $Record
    $directory=[IO.Path]::GetFullPath($AccountingDirectory)
    [void][IO.Directory]::CreateDirectory($directory)
    # Shares the import lock: an automatic publication cannot race a reimport.
    $lock=[IO.File]::Open((Join-Path $directory 'accounting-import.lock'),[IO.FileMode]::OpenOrCreate,[IO.FileAccess]::ReadWrite,[IO.FileShare]::None)
    try {
        foreach ($entry in @(Read-UsageEntries $directory)) {
            if ($entry.AliasTaskIds -ccontains $identity.taskId -and (Get-TaskBindingSignature $entry.identity) -cne (Get-TaskBindingSignature $identity)) { throw 'OriginalLedgerTaskBindingConflict' }
            if ($entry.native_key -ceq ($identity.threadId+'/'+$identity.turnId)) {
                if ((Get-NativeSignature $entry.identity) -cne (Get-NativeSignature $identity)) { throw 'OriginalLedgerNativeConflict; preserve original final or unknown' }
                if ($entry.AliasTaskIds -ccontains $identity.taskId) { return $entry.paths[0] }
            }
        }
        $key=$identity.taskId
        if ($null -ne $identity.threadId -and $null -ne $identity.turnId) { $key+='.'+$identity.threadId+'.'+$identity.turnId }
        # Missing/current-turn-unproven observations are durable evidence, not
        # competing final ledger identities. A later genuine import can publish
        # the measured final while this original observation remains preserved.
        $suffix=if ($identity.final -and $null -ne $identity.tokenUsage) { '.usage.json' } else { '.pending-usage.json' }
        return Write-UsageImmutableDocument (Join-Path $directory ($key+$suffix)) $Record
    } finally { $lock.Dispose() }
}

function Invoke-OriginalUsageAccountingHandoff {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$TaskId,
        [Parameter(Mandatory)][string]$AccountingDirectory,
        [Parameter(Mandatory)][string]$RepositoryRoot,
        [Parameter(Mandatory)][string]$ArchiveDirectory,
        [string[]]$ExpectedJobArtifacts=@(), [string[]]$ExpectedTaskSources=@(),
        [string[]]$NativeRolloutPaths=@(), [string[]]$NativeEventLogPaths=@(),
        [string]$StorePath, [string]$WorkItemId, [string[]]$BoundWorkItemIds,
        $OriginalInput)
    # OriginalInput is the existing producer's pinned byte-range contract.
    # No enrollment/admission operation, fabricated receipt or auth assertion.
    $handoff=$null
    if ($null -ne $OriginalInput) {
        Import-Module (Join-Path $PSScriptRoot 'CoordinatorHandoffProducer.psm1')
        $handoff=Invoke-CoordinatorHandoffProducer -Operation ArchiveAndProject -InputRecord $OriginalInput -ArchiveDirectory (Join-Path $ArchiveDirectory 'original-handoff')
    }
    Import-Module (Join-Path $PSScriptRoot 'OriginalUsageAccountingCaller.psm1')
    $arguments=@{TaskId=$TaskId;AccountingDirectory=$AccountingDirectory;ArchiveDirectory=$ArchiveDirectory;
        AccountingScriptsDirectory=$PSScriptRoot;ExpectedJobArtifacts=$ExpectedJobArtifacts;
        ExpectedTaskSources=$ExpectedTaskSources;NativeRolloutPaths=$NativeRolloutPaths;
        NativeEventLogPaths=$NativeEventLogPaths;IncludeOwnRecords=$true}
    if ($WorkItemId) {
        $arguments.WorkItemId=$WorkItemId; $arguments.RepositoryRoot=$RepositoryRoot
        $arguments.BoundStorePath=$StorePath; $arguments.BoundWorkItemIds=$BoundWorkItemIds
    }
    $result=Invoke-OriginalUsageAccountingCaller @arguments
    return [pscustomobject]@{accounting=$result;originalHandoff=$handoff;ownerAuthentication='not_asserted';familyClosure='not_asserted'}
}

function New-OwnedUsageHandoffInput {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$CapturePath,
        [Parameter(Mandatory)][string]$LedgerPath,
        [Parameter(Mandatory)][string]$AccountingDirectory)
    $capture=@(Read-OriginalUsageCaptures $AccountingDirectory | Where-Object { $_.path -ceq $CapturePath })
    if ($capture.Count -ne 1) { throw 'Selected owned capture missing or ambiguous.' }
    $record=$capture[0].record; $binding=$capture[0].binding
    $bytes=[IO.File]::ReadAllBytes($LedgerPath)
    $ledger=[Text.UTF8Encoding]::new($false,$true).GetString($bytes) | ConvertFrom-Json
    $identity=Get-UsageIdentity $ledger
    foreach ($field in @('taskId','threadId','turnId','executionId','workItemId','storePath')) {
        if ($binding.$field -cne $identity.$field) { throw 'Owned handoff capture/ledger binding conflict.' }
    }
    # This is an actual producer for ONE owned native turn. Expected identity
    # comes from the prior ACK capture, never from the measurement directory.
    # Its root is this task only; it is not the external coordinator root.
    $hash=Get-UsageSourceHash $bytes
    $tuple=[ordered]@{provider=$record.provider;generation=$record.generation;threadId=$record.thread_id;turnId=$record.turn_id}
    $measurement=[ordered]@{}
    foreach ($key in $tuple.Keys) { $measurement[$key]=$tuple[$key] }
    $measurement.sourcePath=[IO.Path]::GetFullPath($LedgerPath);$measurement.byteOffset=0L;$measurement.byteLength=[long]$bytes.Length
    $measurement.sourceSha256=$hash;$measurement.sha256=$hash;$measurement.archiveSha256=$hash;$measurement.rootGeneration=$record.generation
    $input=[ordered]@{rootId=$record.task_id;owner=$record.captureOwner;version='owned-turn-capture/v1';rootGeneration=$record.generation;
        captureBoundary=[ordered]@{id=(Get-UsageSourceHash ([IO.File]::ReadAllBytes($CapturePath)))};
        expectedTurns=@([pscustomobject]$tuple);originalMeasurements=@([pscustomobject]$measurement);
        scope='one_owned_turn';expectedSource=[IO.Path]::GetFullPath($CapturePath);familyComplete=$false;ownerAuthentication='not_asserted'}
    $inputBytes=[Text.UTF8Encoding]::new($false).GetBytes(($input | ConvertTo-Json -Depth 60 -Compress)+"`n")
    $inputHash=Get-UsageSourceHash $inputBytes
    $path=Join-Path $AccountingDirectory ('owned-handoff-inputs/'+$inputHash+'.json')
    [void](Write-UsageImmutableDocument $path $input)
    return [pscustomobject]@{originalInput=[pscustomobject]@{path=[IO.Path]::GetFullPath($path);byteOffset=0L;byteLength=[long]$inputBytes.Length;sha256=$inputHash;sourceSha256=$inputHash}}
}
function Save-OriginalUsageTurnExpectation {
    [CmdletBinding()]
    param([string]$AccountingDirectory,$Binding,[string]$TurnId,[string]$Role,
        [string]$SourcePath,[string]$CompletedRecord)
    $observed=$CompletedRecord | ConvertFrom-Json
    $turn=Get-CanonicalId $TurnId
    if ($observed.type -cne 'event_msg' -or $observed.payload.type -cne 'task_complete' -or
        (Get-CanonicalId $observed.payload.turn_id) -cne $turn) { throw 'Expected turn needs actual completion observation.' }
    # Persist expectation before import, so a rejected/missing measurement is
    # still visible on subsequent reads. This is not an inventory closure.
    $sourceHash=Get-UsageSourceHash ([Text.UTF8Encoding]::new($false).GetBytes($CompletedRecord))
    $record=[ordered]@{schema='observed-usage-turn/v1';task_id=$Binding.taskId;parent_task_id=$Binding.parentTaskId;
        thread_id=$Binding.threadId;turn_id=$turn;parent_thread_id=$Binding.parentThreadId;parent_turn_id=$Binding.parentTurnId;
        execution_id=$Binding.executionId;work_item_id=$Binding.workItemId;store_path=$Binding.storePath;role=$Role;
        sourcePath=[IO.Path]::GetFullPath($SourcePath);completionRecordTextSha256=$sourceHash;
        observationBasis='explicit rollout completion line; text hash, not raw byte range';familyComplete=$false}
    $name=$Binding.taskId+'.'+$Binding.threadId+'.'+$turn+'.'+$sourceHash+'.turn-expectation.json'
    return Write-UsageImmutableDocument (Join-Path $AccountingDirectory $name) $record
}
Export-ModuleMember -Function Save-OriginalUsageAccountingCapture,Publish-OriginalUsageLedger,New-OwnedUsageHandoffInput,Save-OriginalUsageTurnExpectation,Invoke-OriginalUsageAccountingHandoff
