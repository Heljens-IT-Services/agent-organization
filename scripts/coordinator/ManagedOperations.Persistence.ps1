# Local host operations only. This ledger does not certify provider exclusivity.
function Invoke-ManagedOperationLock([string]$Directory,[scriptblock]$Action) {
    $mutex=[Threading.Mutex]::new($false,'Global\AgentOrganizationCoordinatorExecutions')
    if(-not $mutex.WaitOne(10000)){$mutex.Dispose();throw 'ManagedOperationRegistryBusy'}
    try {
        $path=Join-Path $Directory 'executions.json'
        $entries=@(Read-AdmissionJson $path)
        & $Action $path $entries
    } finally {$mutex.ReleaseMutex();$mutex.Dispose()}
}
function Begin-ManagedOperation([string]$Directory,[string]$TaskId,[string]$OperationId,[string]$Method,$Parameters) {
    if(-not $OperationId -or $Method -notin @('runtime/start','thread/start','thread/resume','thread/fork','turn/start')){throw 'ManagedOperationIdentityRequired'}
    $hash=Get-AdmissionObjectHash ([ordered]@{method=$Method;parameters=$Parameters})
    Invoke-ManagedOperationLock $Directory {
        param($path,$entries)
        $matches=@($entries|Where-Object{(Get-AdmissionGuid $_.taskId) -ceq (Get-AdmissionGuid $TaskId)})
        if($matches.Count -ne 1){throw 'ManagedOperationReservationRequired'}
        $entry=$matches[0]
        if((Get-AdmissionField $entry.admission 'kind') -cne 'managed-local-v1' -or $entry.state -notin @('reserved','active') -or (Get-AdmissionField $entry 'releaseWake')){throw 'ManagedOperationReservationClosed'}
        $jobPath=[string](Get-AdmissionField $entry 'jobPath' ($entry.resultPath+'.job.json'))
        if(-not $jobPath){$jobPath=$entry.resultPath+'.job.json'}
        $job=Read-AdmissionJson $jobPath
        if((Get-AdmissionGuid $job.task_id) -cne (Get-AdmissionGuid $TaskId) -or $job.payload_hash -cne $entry.payloadHash){throw 'ManagedCallerJobBindingMismatch'}
        if($entry.role -ceq 'koordinator'){
            $session=Read-AdmissionJson (Join-Path $Directory 'session.json')
            if($session.OwnerPid -ne $PID -or $session.RootTaskId -cne $job.task_id -or $session.CoordinatorJobPath -cne $jobPath){throw 'ManagedHostCallerMismatch'}
        }else{
            $go=Read-AdmissionJson ($entry.resultPath+'.go.json')
            if($go.runner_pid -ne $PID -or $go.task_id -cne $job.task_id){throw 'ManagedRunnerCallerMismatch'}
        }
        if($Method -in @('thread/start','thread/fork') -and (Get-AdmissionField $entry 'nativeThreadId')){throw 'ManagedBirthRequiresSeparateReservation'}
        if($Method -ceq 'thread/resume'){
            $conflicts=@($entries|Where-Object{(Get-AdmissionGuid $_.taskId) -cne (Get-AdmissionGuid $TaskId) -and (Get-AdmissionField $_ 'nativeThreadId') -ceq $Parameters.threadId -and -not (Test-AdmissionTerminalRelease $_)})
            if($conflicts.Count){throw 'ManagedResumeThreadAlreadyBound'}
        }
        $operations=@(Get-AdmissionField $entry 'managedOperations' @())
        if(@($operations|Where-Object{$_.method -ceq 'turn/start' -and -not (Get-AdmissionField $_ 'terminalReceipt')}).Count){throw 'ManagedPriorTurnUnresolved'}
        if($Method -ceq 'runtime/start'){
            foreach($previous in @($operations|Where-Object{$_.method -ceq 'runtime/start' -and $_.state -ceq 'Acknowledged'})){
                try{$old=[Diagnostics.Process]::GetProcessById([int]$previous.receipt.processId)}catch [ArgumentException]{$old=$null}
                if($old){try{if(-not $old.HasExited -and $old.StartTime.ToUniversalTime().ToString('o') -ceq $previous.receipt.processStartedUtc){throw 'ManagedRuntimeAlreadyAlive'}}finally{$old.Dispose()}}
            }
        }
        $prior=@($operations|Where-Object{$_.operationId -ceq $OperationId})
        if($prior.Count){throw 'ManagedOperationAlreadyConsumed; receipt-only recovery required'}
        # A missing response blocks this execution, while its bounded slot stays counted.
        if(@($operations|Where-Object{$_.state -ceq 'Consumed'}).Count){throw 'ManagedOperationOutcomeUnknown'}
        $process=[Diagnostics.Process]::GetProcessById($PID)
        try{$started=$process.StartTime.ToUniversalTime().ToString('o')}finally{$process.Dispose()}
        $operation=[pscustomobject]@{operationId=$OperationId;method=$Method;parametersHash=$hash;jobPath=$jobPath;jobPayloadHash=$entry.payloadHash;state='Consumed';callerPid=$PID;callerStartedUtc=$started;consumedAtUtc=[DateTime]::UtcNow.ToString('o');receipt=$null;receiptHash=$null}
        $entry|Add-Member -NotePropertyName managedOperations -NotePropertyValue @($operations+$operation) -Force
        [void](Write-AdmissionJson $path @($entries))
        return $operation
    }
}
function Complete-ManagedOperation([string]$Directory,[string]$TaskId,[string]$OperationId,$Receipt,[switch]$Recover) {
    if(-not $Receipt){throw 'ManagedOperationActualReceiptRequired'}
    Invoke-ManagedOperationLock $Directory {
        param($path,$entries)
        $matches=@($entries|Where-Object{(Get-AdmissionGuid $_.taskId) -ceq (Get-AdmissionGuid $TaskId)})
        if($matches.Count -ne 1){throw 'ManagedOperationReservationRequired'}
        $entry=$matches[0];$operations=@(Get-AdmissionField $entry 'managedOperations' @())
        $found=@($operations|Where-Object{$_.operationId -ceq $OperationId})
        if($found.Count -ne 1 -or $entry.state -notin @('reserved','active')){throw 'ManagedOperationClaimRequired'}
        $operation=$found[0];$hash=Get-AdmissionObjectHash $Receipt
        if($operation.state -ceq 'Acknowledged'){
            if($operation.receiptHash -cne $hash){throw 'ManagedOperationReceiptConflict'}
            return
        }
        if($operation.callerPid -ne $PID){
            if(-not $Recover){throw 'ManagedOperationCallerConflict'}
            try{$old=[Diagnostics.Process]::GetProcessById([int]$operation.callerPid)}catch [ArgumentException]{$old=$null}
            if($old){try{if(-not $old.HasExited -and $old.StartTime.ToUniversalTime().ToString('o') -ceq $operation.callerStartedUtc){throw 'ManagedRecoveryCallerStillAlive'}}finally{$old.Dispose()}}
        }
        if($operation.method -ceq 'runtime/start'){
            if(-not $Receipt.processId -or -not $Receipt.processStartedUtc){throw 'ManagedRuntimeReceiptRequired'}
        } else {
            if($Receipt.method -cne $operation.method -or -not $Receipt.requestBase64 -or -not $Receipt.replyBase64){throw 'ManagedRpcBytesRequired'}
            $requestBytes=[Convert]::FromBase64String($Receipt.requestBase64)
            $replyBytes=[Convert]::FromBase64String($Receipt.replyBase64)
            if((Get-AdmissionHash $requestBytes) -cne $Receipt.requestBytesHash -or (Get-AdmissionHash $replyBytes) -cne $Receipt.replyBytesHash){throw 'ManagedRpcReceiptHashMismatch'}
            $request=ConvertFrom-Json -InputObject ([Text.Encoding]::UTF8.GetString($requestBytes)) -ErrorAction Stop
            $reply=ConvertFrom-Json -InputObject ([Text.Encoding]::UTF8.GetString($replyBytes)) -ErrorAction Stop
            if((Get-AdmissionObjectHash ([ordered]@{method=$request.method;parameters=$request.params})) -cne $operation.parametersHash -or $request.id -ne $reply.id -or (Get-AdmissionField $reply 'error') -or -not $reply.PSObject.Properties['result']){throw 'ManagedRpcReceiptBindingMismatch'}
        }
        $operation.receipt=$Receipt;$operation.receiptHash=$hash;$operation.state='Acknowledged'
        [void](Write-AdmissionJson $path @($entries))
    }
}
function Assert-ManagedRelease($Entry,[string]$TaskId) {
    if((Get-AdmissionField $Entry.admission 'kind') -cne 'managed-local-v1'){return}
    $operations=@(Get-AdmissionField $Entry 'managedOperations' @())
    if(@($operations|Where-Object{$_.state -cne 'Acknowledged'}).Count){throw 'ManagedOutcomeUnknown; reservation retained'}
    if(@($operations|Where-Object{$_.method -ceq 'turn/start' -and -not (Get-AdmissionField $_ 'terminalReceipt')}).Count){throw 'ManagedTurnTerminalReceiptMissing; reservation retained'}
    foreach($operation in @($operations|Where-Object{$_.method -ceq 'runtime/start'})){
        $receipt=$operation.receipt
        try{$process=[Diagnostics.Process]::GetProcessById([int]$receipt.processId)}catch [ArgumentException]{continue}
        try{if(-not $process.HasExited -and $process.StartTime.ToUniversalTime().ToString('o') -ceq $receipt.processStartedUtc){throw 'ManagedRuntimeStillOwnsStartRights; reservation retained'}}finally{$process.Dispose()}
    }
}
function Publish-ManagedReleaseWake([string]$Directory,[string]$EventPath) {
    Import-Module (Join-Path $PSScriptRoot 'CoordinatorEvents.psm1') -Force
    # Read ledger under registry lock, publish outside it, then CAS the cursor.
    $pending=@(Invoke-ManagedOperationLock $Directory {param($p,$entries)foreach($e in $entries){$wake=Get-AdmissionField $e 'releaseWake';if($wake -and $wake.state -ceq 'pending'){$wake}}})
    foreach($wake in $pending){
        Publish-CoordinatorEvent -Path $EventPath -Kind return_received -SourceId $wake.sourceId -Payload $wake.payload -Durable | Out-Null
        Invoke-ManagedOperationLock $Directory {
            param($path,$entries)
            $matches=@($entries|Where-Object{(Get-AdmissionField (Get-AdmissionField $_ 'releaseWake') 'sourceId') -ceq $wake.sourceId})
            if($matches.Count -ne 1 -or (Get-AdmissionObjectHash $matches[0].releaseWake.payload) -cne (Get-AdmissionObjectHash $wake.payload)){throw 'ManagedReleaseWakeConflict'}
            $matches[0].releaseWake.state='published';[void](Write-AdmissionJson $path @($entries))
        }
    }
}
function Save-ManagedTurnCompletion([string]$Directory,[string]$TaskId,[string]$WireBase64) {
    $bytes=[Convert]::FromBase64String($WireBase64)
    $notification=ConvertFrom-Json -InputObject ([Text.Encoding]::UTF8.GetString($bytes)) -ErrorAction Stop
    if($notification.method -cne 'turn/completed' -or $notification.params.turn.status -notin @('completed','failed','interrupted')){throw 'ManagedNativeTerminalRequired'}
    Invoke-ManagedOperationLock $Directory {
        param($path,$entries)
        $matches=@($entries|Where-Object{(Get-AdmissionGuid $_.taskId) -ceq (Get-AdmissionGuid $TaskId)})
        if($matches.Count -ne 1 -or $matches[0].nativeThreadId -cne $notification.params.threadId){throw 'ManagedTerminalThreadBindingMismatch'}
        $turns=@(Get-AdmissionField $matches[0] 'managedOperations' @()|Where-Object{$_.method -ceq 'turn/start' -and $_.state -ceq 'Acknowledged'})
        $bound=@(foreach($turn in $turns){$reply=ConvertFrom-Json -InputObject ([Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($turn.receipt.replyBase64)));if($reply.result.turn.id -ceq $notification.params.turn.id){$turn}})
        if($bound.Count -ne 1){throw 'ManagedTerminalTurnAckRequired'}
        $hash=Get-AdmissionHash $bytes;$prior=Get-AdmissionField $bound[0] 'terminalReceipt'
        if($prior -and $prior.wireHash -cne $hash){throw 'ManagedTerminalReceiptConflict'}
        $bound[0]|Add-Member -NotePropertyName terminalReceipt -NotePropertyValue @{wireBase64=$WireBase64;wireHash=$hash;threadId=$notification.params.threadId;turnId=$notification.params.turn.id;status=$notification.params.turn.status} -Force
        [void](Write-AdmissionJson $path @($entries))
    }
}
function Get-ManagedChildHeadroom([object[]]$Entries) {
    $seen=@{};$needed=0
    foreach($entry in $Entries){
        if($entry.role -notlike 'teamleiter_*' -or [int](Get-AdmissionField $entry 'minimumConcurrentExecutions' 1) -lt 2){continue}
        $id=[string]$entry.executionId;if($seen.ContainsKey($id)){continue};$seen[$id]=$true
        $jobPath=[string](Get-AdmissionField $entry 'jobPath');if(-not $jobPath){$jobPath=$entry.resultPath+'.job.json'}
        $children=@($Entries|Where-Object{(Get-AdmissionField $_ 'parentJobPath') -ceq $jobPath -and $_.state -in @('reserved','active','unknown')})
        if(-not $children.Count){$needed++}
    }
    return $needed
}
function Resume-ManagedSpecialistWaits([string]$Directory,[string]$RootJobPath,[string]$RepositoryRoot,[string[]]$ExcludedWorkItemIds=@()) {
    $waitDirectory=Join-Path $Directory 'managed-waiting'
    if(-not [IO.Directory]::Exists($waitDirectory)){return}
    foreach($file in @(Get-ChildItem -LiteralPath $waitDirectory -File -Filter '*.json')){
        $wait=Read-AdmissionJson $file.FullName
        if($wait.state -cne 'waiting' -or $wait.rootJobPath -cne $RootJobPath -or $wait.target.role -like 'teamleiter_*'){continue}
        # Replay only the exact specialist request authorized by its own team parent.
        # Ledger consumption in the starter prevents a second process after ambiguity.
        $target=$wait.target
        if((Get-AdmissionObjectHash $target) -cne $wait.targetHash -or (Get-AdmissionHash ([IO.File]::ReadAllBytes($target.startIntentPath))) -cne $target.startIntentHash){$wait.state='recovery-required';$wait.reason='authority-changed';[void](Write-AdmissionJson $file.FullName $wait);continue}
        $entries=@(Read-AdmissionJson (Join-Path $Directory 'executions.json'))
        $existing=@($entries|Where-Object{(Get-AdmissionGuid $_.taskId) -ceq (Get-AdmissionGuid $target.taskId) -or (Get-AdmissionGuid $_.dispatchId) -ceq (Get-AdmissionGuid $target.dispatchId)})
        if($existing.Count){$wait.state='reservation-bound';[void](Write-AdmissionJson $file.FullName $wait);continue}
        $authority=Read-AdmissionJson $target.startIntentPath
        if($authority.kind -cne 'delegated-start-authority-v1'){$wait.state='recovery-required';$wait.reason='ssot-authority-required';[void](Write-AdmissionJson $file.FullName $wait);continue}
        if([string]$authority.parameters.WorkItemId -in $ExcludedWorkItemIds){$wait.reason='local-start-recovery';[void](Write-AdmissionJson $file.FullName $wait);continue}
        $arguments=@{};foreach($property in $authority.parameters.PSObject.Properties){$arguments[$property.Name]=$property.Value}
        $arguments.ParentJobPath=$authority.parentJobPath;$arguments.ParentContextPath=$authority.parentContextPath;$arguments.ParentContextHash=$authority.parentContextHash
        $arguments.StartIntentPath=$target.startIntentPath;$arguments.StartIntentHash=$target.startIntentHash
        try{
            # Starter verifies original Prepared bytes before direct local admission.
            $arguments.ManagedWaitReplay=$true
            $inheritedNames=@('AGENT_ORG_PARENT_TASK_ID','AGENT_ORG_PARENT_JOB_FILE','AGENT_ORG_PARENT_CONTEXT_PATH','AGENT_ORG_PARENT_CONTEXT_HASH','AGENT_ORG_PARENT_THREAD_ID','AGENT_ORG_PARENT_TURN_ID')
            $inherited=@{};foreach($name in $inheritedNames){$inherited[$name]=[Environment]::GetEnvironmentVariable($name,'Process')}
            try{
                # Replay the parent's persisted authority; never derive a new role/contact.
                $values=@($arguments.ParentTaskId,$authority.parentJobPath,$authority.parentContextPath,$authority.parentContextHash,$authority.parentThreadId,$authority.parentTurnId)
                for($i=0;$i -lt $inheritedNames.Count;$i++){[Environment]::SetEnvironmentVariable($inheritedNames[$i],[string]$values[$i],'Process')}
                & (Join-Path $RepositoryRoot 'scripts/delegation/Start-DelegatedCodexTask.ps1') @arguments | Out-Null
            }finally{foreach($name in $inheritedNames){[Environment]::SetEnvironmentVariable($name,$inherited[$name],'Process')}}
            $wait.state='reservation-bound';[void](Write-AdmissionJson $file.FullName $wait)
        }catch{
            if($_.Exception.Message -like 'CoordinatorCapacityFull*'){continue}
            $wait.state='recovery-required';$wait.reason=$_.Exception.Message;[void](Write-AdmissionJson $file.FullName $wait)
        }
    }
}
