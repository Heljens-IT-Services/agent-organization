. (Join-Path $PSScriptRoot 'Lifecycle.Persistence.ps1')
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'CoordinatorAdmission.psm1') -Force
$script:Utf8 = New-Object System.Text.UTF8Encoding($false, $true)

function Write-CoordinatorAtomicJson([string]$Path,$Value){Write-LCJournal $Path $Value}

function Read-CoordinatorSession([string]$Path) {
    if (-not [IO.File]::Exists($Path)) { return $null }
    try { return (Read-LCArchive $Path ([IO.File]::ReadAllText($Path, $script:Utf8) | ConvertFrom-Json -ErrorAction Stop)) }
    catch { throw 'BlockedRecovery: Sessiondaten unlesbar oder unvollständig.' }
}

function Get-CoordinatorHistory($Session){return @($Session.RequestHistory | Sort-Object @{Expression={Get-LCValue $_ 'submittedAtUtc' (Get-LCValue (Get-LCValue $_ 'decision') 'completedAtUtc' '')}},requestId)}

function Get-CoordinatorConfigValue($Config, [string]$Name) {
    if ($null -eq $Config) { return $null }
    if ($Config -is [System.Collections.IDictionary]) {
        if ($Config.Contains($Name)) { return $Config[$Name] }
        return $null
    }
    $property = $Config.PSObject.Properties[$Name]
    if ($property) { return $property.Value }
    return $null
}

function Get-CoordinatorPrivateStoreModule {
    $modulePath = Join-Path (Split-Path -Parent $PSScriptRoot) 'workitems/WorkItemStore.psm1'
    if (-not (Test-Path -LiteralPath $modulePath -PathType Leaf)) { return $null }
    $m = Import-Module -Name $modulePath -PassThru -Force
    return $m
}

function Invoke-CoordinatorPrivateStore([System.Management.Automation.PSModuleInfo]$Module, [string]$Name, [object[]]$Arguments) {
    # Intentional narrow dependency on the already-approved private store primitives.
    $command = $Module.ExportedCommands[$Name]
    if ($command) { throw 'Expected private store primitive unexpectedly became public.' }
    return & $Module { param($privateName,$privateArguments) $privateCommand=Get-Command -Name $privateName -CommandType Function -ErrorAction Stop; & $privateCommand @privateArguments } $Name $Arguments
}

function Enter-CoordinatorOwnership([string]$DataDirectory, [switch]$TestMode) {
    $full = [IO.Path]::GetFullPath($DataDirectory)
    if (-not [IO.Path]::IsPathRooted($DataDirectory)) { throw 'DataDirectory must be absolute.' }
    $canonical = [IO.Path]::GetFullPath((Join-Path $env:LOCALAPPDATA 'AgentOrganization/Coordinator'))
    if (-not $TestMode -and -not $full.Equals($canonical,[StringComparison]::OrdinalIgnoreCase)) { throw 'Production DataDirectory must be the canonical per-user coordinator directory.' }
    if ([IO.Directory]::Exists($full) -and ((Get-Item -LiteralPath $full -Force).Attributes -band [IO.FileAttributes]::ReparsePoint)) { throw 'Reparse-point data directories are not supported.' }
    [void][IO.Directory]::CreateDirectory($full)
    $module=Get-CoordinatorPrivateStoreModule
    if (-not $module) { throw 'BlockedRecovery: private store module unavailable.' }
    $storePath=Join-Path $full 'session.store.json'
    $storeModulePath=Join-Path (Split-Path -Parent $PSScriptRoot) 'workitems/WorkItemStore.psm1'
    $lock=Invoke-CoordinatorPrivateStore $module 'Enter-WorkItemStoreLock' @($storePath,5000)
    return [pscustomobject]@{ StoreModule=$module; StorePath=$storePath; StoreLock=$lock; DataDirectory=$full; SessionPath=(Join-Path $full 'session.json'); OwnerPid=$PID; OwnerStartedUtc=(Get-Process -Id $PID).StartTime.ToUniversalTime().ToString('o'); TestMode=[bool]$TestMode }
}

function Exit-CoordinatorOwnership($Owner) { if($Owner -and $Owner.StoreLock){ Invoke-CoordinatorPrivateStore $Owner.StoreModule 'Exit-WorkItemStoreLock' @($Owner.StoreLock) } }

function Invoke-CoordinatorRuntimeRpc($Runtime, [string]$Method, $Params, [int]$TimeoutMilliseconds=15000) {
    if($Runtime.TransportUnknown){throw 'AdmissionUnknown: TransportCorrelationLost'}
    $id = [int]$Runtime.NextId; $Runtime.NextId++
    $wire=@{jsonrpc='2.0';id=$id;method=$Method};if($null -ne $Params){$wire.params=$Params}
    $request=$wire|ConvertTo-Json -Depth 20 -Compress
    $requestStartedUtc=[DateTime]::UtcNow.ToString('o')
    $bytes = $script:Utf8.GetBytes($request + "`n")
    $Runtime.Input.Write($bytes,0,$bytes.Length); $Runtime.Input.Flush()
    $watch=[Diagnostics.Stopwatch]::StartNew()
    while ($watch.ElapsedMilliseconds -lt $TimeoutMilliseconds) {
        if ($Runtime.Process.HasExited) { throw 'Unavailable: Runtime exited.' }
        if (-not $Runtime.PendingRead) { $Runtime.PendingRead=$Runtime.Reader.ReadLineAsync() }
        if ($Runtime.PendingRead.Wait([int][Math]::Max(1,($TimeoutMilliseconds-$watch.ElapsedMilliseconds)))) {
            $line=$Runtime.PendingRead.Result; $Runtime.PendingRead=$null
            if (-not $line) { throw 'Unavailable: Runtime closed stdout.' }
            $message = $line | ConvertFrom-Json -ErrorAction Stop
            $idProperty=$message.PSObject.Properties['id'];$methodProperty=$message.PSObject.Properties['method']
            if ($idProperty -and $null -ne $idProperty.Value -and $idProperty.Value -eq $id -and -not $methodProperty) {
                $rpcError=$message.PSObject.Properties['error']
                if ($rpcError -and $rpcError.Value) { throw ('RuntimeError: ' + $rpcError.Value.message) }
                $resultProperty=$message.PSObject.Properties['result'];if(-not $resultProperty){throw 'RecoveryUnknown: RPC response lacks result.'};$replyBytes=$script:Utf8.GetBytes($line);$Runtime.LastRpcReceipt=@{method=$Method;id=$id;requestBase64=[Convert]::ToBase64String($bytes);requestBytesHash=(Get-AdmissionHash $bytes);replyBase64=[Convert]::ToBase64String($replyBytes);replyBytesHash=(Get-AdmissionHash $replyBytes);startedUtc=$requestStartedUtc;endedUtc=[DateTime]::UtcNow.ToString('o')};return $resultProperty.Value
            }
            if($idProperty -and $null -ne $idProperty.Value -and -not $methodProperty){$Runtime.TransportUnknown=$true;$Runtime.GapGeneration++;throw 'RecoveryUnknown: UnexpectedOrLateRpcResponse'}
            if ($methodProperty -and $methodProperty.Value) { if($idProperty -and $null -ne $idProperty.Value){throw 'BlockedRecovery: unsupported runtime server request.'};if (-not $Runtime.Notifications) { $Runtime.Notifications=New-Object System.Collections.ArrayList };$Runtime.MutationGeneration++;if($Runtime.Notifications.Count -ge 256){$Runtime.GapGeneration++;$Runtime.Notifications.RemoveAt(0)};[void]$Runtime.Notifications.Add($message) }
        }
    }
    $Runtime.TransportUnknown=$true;$Runtime.GapGeneration++
    throw 'RecoveryUnknown: Runtime RPC response timed out.'
}

function Test-CoordinatorNotificationBinding($Notification, [string]$ThreadId, [string]$TurnId) {
    if ($null -eq $Notification -or [string]::IsNullOrEmpty($ThreadId) -or [string]::IsNullOrEmpty($TurnId)) { return $false }
    $paramsValue=Get-CoordinatorConfigValue $Notification 'params'
    $threadValue=Get-CoordinatorConfigValue $paramsValue 'threadId'
    if ([string]$threadValue -cne $ThreadId) { return $false }
    $paramsTurnId=Get-CoordinatorConfigValue $paramsValue 'turnId'
    $paramsTurn=Get-CoordinatorConfigValue $paramsValue 'turn'
    $paramsNestedTurnId=Get-CoordinatorConfigValue $paramsTurn 'id'
    $topTurnId=Get-CoordinatorConfigValue $Notification 'turnId'
    $topTurn=Get-CoordinatorConfigValue $Notification 'turn'
    $topNestedTurnId=Get-CoordinatorConfigValue $topTurn 'id'
    $foundTurnId=$false
    foreach($candidate in @($paramsTurnId,$paramsNestedTurnId,$topTurnId,$topNestedTurnId)) {
        if ($null -eq $candidate) { continue }
        $foundTurnId=$true
        if ([string]$candidate -cne $TurnId) { return $false }
    }
    return $foundTurnId
}

function ConvertTo-CoordinatorEffectDecision($FinalItems, $Request, $Session, [string]$TerminalStatus, [bool]$InvalidFinalItem = $false) {
    $status='Missing'; $plan=$null; $payload=$null; $errorText=$null
    try {
        if ($TerminalStatus -ne 'completed') { return @{effectPlan=$null;planPayloadBase64=$null;effectPlanStatus='Missing';effectPlanError='EffectPlanNotExecutable: non-completed turns cannot produce an executable plan.'} }
        if ($InvalidFinalItem) { throw 'EffectFinalItemIdMissing' }
        if (@($FinalItems).Count -eq 0) { return @{effectPlan=$null;planPayloadBase64=$null;effectPlanStatus='Missing';effectPlanError='EffectFinalItemMissing'} }
        if (@($FinalItems).Count -ne 1) { throw 'EffectFinalItemAmbiguous' }
        $final=@($FinalItems)[0]
        $parsed=ConvertFrom-Json -InputObject ([string]$final.text) -ErrorAction Stop
        if ($parsed -isnot [System.Management.Automation.PSCustomObject]) { throw 'EffectProtocolRootMustBeObject' }
        $names=@($parsed.PSObject.Properties.Name)
        if (@($names | Where-Object { $_ -notin @('version','disposition','reason','commands') }).Count -or
            @(@('version','disposition','reason','commands') | Where-Object { $_ -notin $names }).Count) { throw 'EffectProtocolFieldsInvalid' }
        if ([string]$parsed.version -cne '1' -or [string]$parsed.disposition -notin @('apply','no_change') -or
            [string]::IsNullOrWhiteSpace([string]$parsed.reason) -or $parsed.commands -isnot [array]) { throw 'EffectProtocolHeaderInvalid' }
        $commands=@($parsed.commands)
        if (($parsed.disposition -eq 'no_change' -and $commands.Count -ne 0) -or
            ($parsed.disposition -eq 'apply' -and $commands.Count -eq 0)) { throw 'EffectProtocolDispositionInvalid' }
        $required=@('logicalSessionId','threadId','turnId','requestId','eventId','executionId','inputHash','baseRevision')
        foreach($field in $required) { if ([string]::IsNullOrWhiteSpace([string](Get-CoordinatorConfigValue $Request $field))) { throw "EffectBindingMissing:$field" } }
        if ([string]$Request.logicalSessionId -cne [string]$Session.LogicalSessionId -or [string]$Request.threadId -cne [string]$Session.NativeThreadId) { throw 'EffectHostBindingMismatch' }
        $boundCommands=New-Object System.Collections.Generic.List[object]; $ordinal=0
        foreach($command in $commands) {
            if ($command -isnot [System.Management.Automation.PSCustomObject]) { throw 'EffectCommandMustBeObject' }
            $kind=[string]$command.kind
            if ($kind -eq 'set_workitem') {
                if (@($command.PSObject.Properties.Name | Where-Object { $_ -notin @('kind','id','isNew','item') }).Count -or @(@('kind','id','isNew','item') | Where-Object { $_ -notin $command.PSObject.Properties.Name }).Count) { throw 'EffectSetWorkItemFieldsInvalid' }
                if ([string]::IsNullOrWhiteSpace([string]$command.id) -or $null -eq $command.isNew -or $null -eq $command.item) { throw 'EffectSetWorkItemInvalid' }
                if ($command.isNew -isnot [bool]) { throw 'EffectSetWorkItemIsNewMustBeBoolean' }
                $bound=[ordered]@{kind=$kind;id=[string]$command.id;isNew=[bool]$command.isNew;item=$command.item}
            } elseif ($kind -eq 'request_rework') {
                if (@($command.PSObject.Properties.Name | Where-Object { $_ -notin @('kind','workItemId','purpose','priorExecutionId','priorGeneration','reason') }).Count -or @(@('kind','workItemId','purpose','priorExecutionId','priorGeneration','reason') | Where-Object { $_ -notin $command.PSObject.Properties.Name }).Count) { throw 'EffectRequestReworkFieldsInvalid' }
                if ([string]::IsNullOrWhiteSpace([string]$command.workItemId) -or [string]$command.purpose -cne 'teamleiter-workitem' -or
                    [string]::IsNullOrWhiteSpace([string]$command.priorExecutionId) -or $command.priorGeneration -isnot [int] -or
                    [string]::IsNullOrWhiteSpace([string]$command.reason)) { throw 'EffectRequestReworkInvalid' }
                $bound=[ordered]@{kind=$kind;workItemId=[string]$command.workItemId;purpose=[string]$command.purpose;priorExecutionId=[string]$command.priorExecutionId;priorGeneration=[int]$command.priorGeneration;reason=[string]$command.reason;sourceEventId=[string]$Request.eventId}
            } elseif ($kind -eq 'propose_resume') {
                $fields=@('kind','workItemId','triggerEventId','requestedAt','responseHash','sourceRevision','priorExecutionId','priorGeneration','disposition','reason','assessmentText')
                if(@($command.PSObject.Properties.Name|Where-Object{$_ -notin $fields}).Count -or @($fields|Where-Object{$_ -notin $command.PSObject.Properties.Name}).Count){throw 'EffectResumeFieldsInvalid'}
                if($command.priorGeneration -isnot [int] -or $command.priorGeneration -lt 0 -or $command.disposition -notin @('resume','keep_blocked') -or $command.responseHash -notmatch '^[a-f0-9]{64}$'){throw 'EffectResumeInvalid'}
                foreach($n in @('workItemId','triggerEventId','sourceRevision','reason','assessmentText')){if([string]::IsNullOrWhiteSpace([string]$command.$n)){throw 'EffectResumeBindingMissing'}}
                if($command.triggerEventId -cne $Request.eventId -or $command.sourceRevision -cne $Request.baseRevision -or ($command.priorGeneration -gt 0 -and -not $command.priorExecutionId) -or ($command.priorGeneration -eq 0 -and $null -ne $command.priorExecutionId)){throw 'EffectResumeSourceConflict'}
                $bound=[ordered]@{};foreach($n in $fields){$bound[$n]=$command.$n}
            } else { throw 'EffectCommandKindUnsupported' }
            $identity=[string]$Request.executionId+"`n"+[string]$Request.inputHash+"`n"+$ordinal
            $sha=[Security.Cryptography.SHA256]::Create(); try { $effectId=([BitConverter]::ToString($sha.ComputeHash($script:Utf8.GetBytes($identity)))).Replace('-','').ToLowerInvariant() } finally { $sha.Dispose() }
            $bound.effectId=$effectId; $bound.ordinal=$ordinal; $boundCommands.Add($bound); $ordinal++
        }
        $plan=[ordered]@{version='1';logicalSessionId=[string]$Request.logicalSessionId;threadId=[string]$Request.threadId;turnId=[string]$Request.turnId;requestId=[string]$Request.requestId;eventId=[string]$Request.eventId;executionId=[string]$Request.executionId;inputHash=[string]$Request.inputHash;baseRevision=[string]$Request.baseRevision;disposition=[string]$parsed.disposition;reason=[string]$parsed.reason;commands=@($boundCommands.ToArray())}
        $planBytes=$script:Utf8.GetBytes((ConvertTo-Json -InputObject $plan -Depth 50 -Compress)); $sha=[Security.Cryptography.SHA256]::Create()
        try { $planHash=([BitConverter]::ToString($sha.ComputeHash($planBytes))).Replace('-','').ToLowerInvariant() } finally { $sha.Dispose() }
        $plan.planHash=$planHash; $payload=[Convert]::ToBase64String($planBytes)
        $status='Complete'
    } catch { $status='Invalid'; $errorText=$_.Exception.Message; $plan=$null; $payload=$null }
    return @{effectPlan=$plan;planPayloadBase64=$payload;effectPlanStatus=$status;effectPlanError=$errorText}
}

function Start-CoordinatorRuntime($Config) {
    if ($Config.PSObject.Properties['RuntimeFactory'] -and $Config.RuntimeFactory) { return & $Config.RuntimeFactory $Config }
    $configuredExe=Get-CoordinatorConfigValue $Config 'RuntimeExecutable'
    $exe = if ($configuredExe) { [string]$configuredExe } else { (Get-Command codex.exe -ErrorAction Stop).Source }
    $psi = New-Object Diagnostics.ProcessStartInfo
    $psi.FileName = $exe
    if (@(Get-AdmissionField $Config 'RuntimeArguments').Count -gt 0) { $psi.Arguments=(@($Config.RuntimeArguments|ForEach-Object { '"'+([string]$_).Replace('"','\"')+'"' }) -join ' ') }
    else { $psi.Arguments = 'app-server --stdio' }
    $psi.UseShellExecute=$false
    $psi.RedirectStandardInput=$true; $psi.RedirectStandardOutput=$true; $psi.RedirectStandardError=$true
    $psi.CreateNoWindow=$true; $psi.WorkingDirectory=$Config.WorkingDirectory
    $codexHome=Get-CoordinatorConfigValue $Config 'CodexHome'
    if ($codexHome) { $psi.EnvironmentVariables['CODEX_HOME']=[string]$codexHome }
    $p = New-Object Diagnostics.Process; $p.StartInfo=$psi
    if (-not $p.Start()) { throw 'Unavailable: Runtime start failed.' }
    $jobHandle = [IntPtr]::Zero
    try {
        if (-not ('CoordinatorRuntimeJob' -as [type])) {
            Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
public static class CoordinatorRuntimeJob {
  [StructLayout(LayoutKind.Sequential)] public struct Basic { public long ProcessTime, JobTime; public uint Flags; public UIntPtr MinWs, MaxWs; public uint Active; public UIntPtr Affinity; public uint Priority, Schedule; }
  [StructLayout(LayoutKind.Sequential)] public struct Io { public ulong ReadOps, WriteOps, OtherOps, ReadBytes, WriteBytes, OtherBytes; }
  [StructLayout(LayoutKind.Sequential)] public struct Extended { public Basic BasicInfo; public Io IoInfo; public UIntPtr ProcessMemory, JobMemory, PeakProcess, PeakJob; }
  [DllImport("kernel32.dll", CharSet=CharSet.Unicode, SetLastError=true)] public static extern IntPtr CreateJobObject(IntPtr attributes, string name);
  [DllImport("kernel32.dll", SetLastError=true)] public static extern bool SetInformationJobObject(IntPtr job, int kind, ref Extended info, uint length);
  [DllImport("kernel32.dll", SetLastError=true)] public static extern bool AssignProcessToJobObject(IntPtr job, IntPtr process);
  [DllImport("kernel32.dll", SetLastError=true)] public static extern bool CloseHandle(IntPtr handle);
}
'@ -ErrorAction Stop
        }
        $jobHandle = [CoordinatorRuntimeJob]::CreateJobObject([IntPtr]::Zero, $null)
        if ($jobHandle -eq [IntPtr]::Zero) { throw 'CreateJobObject failed.' }
        $limits = New-Object CoordinatorRuntimeJob+Extended
        $limits.BasicInfo.Flags = 0x00002000
        $size = [Runtime.InteropServices.Marshal]::SizeOf([type][CoordinatorRuntimeJob+Extended])
        if (-not [CoordinatorRuntimeJob]::SetInformationJobObject($jobHandle, 9, [ref]$limits, [uint32]$size)) { throw 'SetInformationJobObject failed.' }
        if (-not [CoordinatorRuntimeJob]::AssignProcessToJobObject($jobHandle, $p.Handle)) { throw 'AssignProcessToJobObject failed.' }
        return [pscustomobject]@{ Process=$p; Input=$p.StandardInput.BaseStream; Reader=$p.StandardOutput; NextId=1; PendingRead=$null; Notifications=(New-Object System.Collections.ArrayList); MutationGeneration=[long]0; GapGeneration=[long]0; TransportUnknown=$false; ProviderReceipt=$null; AdmissionSessionPath=$null; LastRpcReceipt=$null; RuntimeArguments=@($Config.RuntimeArguments); Owned=$true; JobHandle=$jobHandle; StartedAtUtc=$p.StartTime.ToUniversalTime().ToString('o') }
    } catch {
        if ($jobHandle -ne [IntPtr]::Zero) { [void][CoordinatorRuntimeJob]::CloseHandle($jobHandle) }
        if (-not $p.HasExited) { try { $p.Kill(); [void]$p.WaitForExit(3000) } catch { } }
        $p.Dispose()
        throw ('Unavailable: cannot safely bind owned runtime to host lifetime: ' + $_.Exception.Message)
    }
}

function New-CoordinatorPipeServer([string]$PipeName) {
    $sid=[Security.Principal.WindowsIdentity]::GetCurrent().User
    $security=New-Object IO.Pipes.PipeSecurity
    $security.SetAccessRuleProtection($true,$false)
    $rule=New-Object IO.Pipes.PipeAccessRule($sid,[IO.Pipes.PipeAccessRights]::FullControl,[Security.AccessControl.AccessControlType]::Allow)
    $security.AddAccessRule($rule)
    return New-Object IO.Pipes.NamedPipeServerStream($PipeName,[IO.Pipes.PipeDirection]::InOut,1,[IO.Pipes.PipeTransmissionMode]::Byte,[IO.Pipes.PipeOptions]::Asynchronous,65536,65536,$security)
}

function Initialize-CoordinatorRuntime($Runtime, $Session, [string]$SessionPath, [string]$JobPath, [string]$JobHash, [string]$LaunchHash) {
    $rpcTimeout=if($Runtime.RpcTimeoutMilliseconds){[int]$Runtime.RpcTimeoutMilliseconds}else{15000}
    $initializeReply=Invoke-CoordinatorRuntimeRpc $Runtime 'initialize' @{clientInfo=@{name='agent-organization-coordinator';version='1'}} $rpcTimeout
    $notification=@{jsonrpc='2.0';method='initialized';params=@{}}|ConvertTo-Json -Depth 10 -Compress
    $notificationBytes=$script:Utf8.GetBytes($notification+"`n")
    $Runtime.Input.Write($notificationBytes,0,$notificationBytes.Length); $Runtime.Input.Flush()
    $jobForAdmission=Read-AdmissionJson $JobPath
    $launchForAdmission=Read-AdmissionJson $jobForAdmission.coordinator_launch.inputPath
    $Runtime.AdmissionSessionPath=$SessionPath
    $receipt=New-AdmissionProviderReceipt $Runtime.Process $JobPath $JobPath $SessionPath $Session.RuntimeExecutable @($Runtime.RuntimeArguments) $Session.CodexHome $initializeReply 'host'
    $Runtime.ProviderReceipt=$receipt.receipt
    $registryScript=Join-Path $PSScriptRoot 'Register-CoordinatorExecution.ps1'
    & $registryScript -Action BindProvider -DataDirectory $launchForAdmission.registryDirectory -TaskId $jobForAdmission.task_id -ProviderBindingJson (ConvertTo-Json -InputObject $receipt -Depth 60 -Compress) | Out-Null
    $diagnosticRpc={param($m,$q,$ms)Invoke-CoordinatorRuntimeRpc $Runtime $m $q ([int][Math]::Min($ms,$Runtime.RpcTimeoutMilliseconds))}.GetNewClosure()
    $diagnosticMarkers={@{mutation=$Runtime.MutationGeneration;gap=$Runtime.GapGeneration;rpc=$Runtime.LastRpcReceipt}}.GetNewClosure()
    [void](Invoke-AdmissionReadDiagnostics $launchForAdmission.registryDirectory $JobPath $SessionPath $registryScript $Runtime.ProviderReceipt ([int](Get-AdmissionField $launchForAdmission.admissionPolicy 'scanBudgetMilliseconds' 10000)) $diagnosticRpc $diagnosticMarkers)
    # No thread/resume/start until actual installed API and native consistency contracts are present.
    $capability=Get-AdmissionInstalledContract $Runtime.ProviderReceipt
    if(-not $capability.api -or $capability.completionMode -eq 'Unknown'){throw ('BlockedRecovery: MissingExternalAccess:'+($capability.missing -join ','))}
    foreach($pair in @(@('ResumeAttempts',0),@('LastUsage',$null),@('RequestHistory',@()),@('AccountingError',$null),@('RuntimePid',$null),@('RuntimeStartedAtUtc',$null))){if(-not $Session.PSObject.Properties[$pair[0]]){$Session|Add-Member -NotePropertyName $pair[0] -NotePropertyValue $pair[1]}}
    if(-not $Session.LogicalSessionId -or (-not $Session.NativeThreadId -and (-not $JobPath -or -not $JobHash -or -not $LaunchHash))){throw 'BlockedRecovery: required session binding missing.'}
    if(-not $Session.NativeThreadId){
        $recoveryIntentPath=Join-Path (Split-Path -Parent $SessionPath) 'initial-thread-intent.json'
        $recoveryAckPath=Join-Path (Split-Path -Parent $SessionPath) 'initial-thread-ack.json'
        if([IO.File]::Exists($recoveryIntentPath)){
            if(-not [IO.File]::Exists($recoveryAckPath)){throw 'BlockedRecovery: initial thread intent has no durable ACK; thread creation outcome is unknown and must not be repeated.'}
            $intentBytes=[IO.File]::ReadAllBytes($recoveryIntentPath);$intent=ConvertFrom-Json -InputObject $script:Utf8.GetString($intentBytes) -ErrorAction Stop
            $ack=ConvertFrom-Json -InputObject $script:Utf8.GetString([IO.File]::ReadAllBytes($recoveryAckPath)) -ErrorAction Stop
            $intentHash=Get-FileHashText $intentBytes
            if($ack.kind -cne 'coordinator-initial-thread-ack-v1' -or $ack.intentHash -cne $intentHash -or $intent.rootTaskId -cne $Session.RootTaskId -or $intent.jobHash -cne $JobHash -or $intent.launchHash -cne $LaunchHash -or $intent.logicalSessionId -cne $Session.LogicalSessionId -or -not $ack.threadId -or $ack.rootTaskId -cne $Session.RootTaskId -or $ack.jobHash -cne $JobHash -or $ack.launchHash -cne $LaunchHash -or $ack.logicalSessionId -cne $Session.LogicalSessionId){throw 'BlockedRecovery: initial thread intent/ACK binding conflict.'}
            $Session.NativeThreadId=[string]$ack.threadId;$Session.InitialIntentPath=$recoveryIntentPath;$Session.InitialIntentHash=$intentHash;$Session.InitialAckPath=$recoveryAckPath;$Session.InitialAckHash=Get-FileHashText ([IO.File]::ReadAllBytes($recoveryAckPath));Write-CoordinatorAtomicJson $SessionPath $Session
        }
    }
    if ($Session.NativeThreadId) {
        $initialAckPath=Join-Path (Split-Path -Parent $SessionPath) 'initial-thread-ack.json'
        if(-not [IO.File]::Exists($initialAckPath)){throw 'BlockedRecovery: existing thread lacks immutable create ACK receipt.'}
        $initialAck=ConvertFrom-Json -InputObject $script:Utf8.GetString([IO.File]::ReadAllBytes($initialAckPath)) -ErrorAction Stop
        if($initialAck.threadId -cne $Session.NativeThreadId -or $initialAck.jobHash -cne $JobHash -or $initialAck.launchHash -cne $LaunchHash){throw 'BlockedRecovery: thread ownership receipt mismatch.'}
        $Session.State='Resuming'
        Write-CoordinatorAtomicJson $SessionPath $Session
        $reply=$null; $retryLimit=[int]$Runtime.ResumeRetryLimit
        for($attempt=1;$attempt -le $retryLimit;$attempt++) {
            try { $Session.ResumeAttempts=[int]$Session.ResumeAttempts+1; Write-CoordinatorAtomicJson $SessionPath $Session; $reply=Invoke-CoordinatorRuntimeRpc $Runtime 'thread/resume' @{threadId=$Session.NativeThreadId} $rpcTimeout; break }
            catch {
                $message=$_.Exception.Message
                if($message -match 'authentication|auth|login|credential') { $Session.State='BlockedRecovery';$Session.LastError='AuthenticationUnavailable';Write-CoordinatorAtomicJson $SessionPath $Session;throw 'BlockedRecovery: authentication unavailable.' }
                $retryableRuntimeError = $message -like 'RuntimeError:*' -and $message -notmatch 'not found|does not exist|invalid thread|unsupported|authentication|auth|login|credential'
                $retryableTimeout = $false
                if(($retryableRuntimeError -or $retryableTimeout) -and $attempt -lt $retryLimit -and -not $Runtime.Process.HasExited) { Start-Sleep -Milliseconds ([Math]::Min(1000,100*$attempt)); continue }
                $Session.State='BlockedRecovery';$Session.LastError=$message;Write-CoordinatorAtomicJson $SessionPath $Session;throw 'BlockedRecovery: same-thread resume failed; no replacement thread or replay.'
            }
        }
        if ($reply.thread.id -cne $Session.NativeThreadId) { $Session.State='BlockedRecovery'; $Session.LastError='Resume thread ID mismatch'; Write-CoordinatorAtomicJson $SessionPath $Session; throw 'BlockedRecovery: Resume ID mismatch.' }
        $read=Invoke-CoordinatorRuntimeRpc $Runtime 'thread/read' @{threadId=$Session.NativeThreadId;includeTurns=$true} $rpcTimeout
        if($read.thread.id -cne $Session.NativeThreadId -or $read.thread.status.type -cne 'idle'){throw 'BlockedRecovery: existing thread is not confirmed idle.'}
    } else {
        if (-not $JobPath -or -not $JobHash -or -not $LaunchHash) { throw 'BlockedRecovery: actual root job binding required for initial thread.' }
        $job=ConvertFrom-Json -InputObject $script:Utf8.GetString([IO.File]::ReadAllBytes($JobPath)) -ErrorAction Stop
        if($job.task_id -cne $Session.RootTaskId -or $job.role -cne 'koordinator'){throw 'BlockedRecovery: initial thread job identity mismatch.'}
        $initialPath=Join-Path (Split-Path -Parent $SessionPath) 'initial-thread-intent.json'
        if([IO.File]::Exists($initialPath)){throw 'BlockedRecovery: prior initial thread start intent exists; receipt-only recovery required.'}
        $params=[ordered]@{cwd=$job.cwd;model=$job.model;sandbox=$job.sandbox;approvalPolicy=$job.approval_policy;developerInstructions=$job.developer_instructions;config=$job.config}
        $intent=[ordered]@{kind='coordinator-initial-thread-v1';rootTaskId=$job.task_id;jobPath=[IO.Path]::GetFullPath($JobPath);jobHash=$JobHash;launchHash=$LaunchHash;logicalSessionId=$Session.LogicalSessionId;storePath=$Session.StorePath;runtimeExecutable=$Session.RuntimeExecutable;runtimeArguments=$Runtime.RuntimeArguments;codexHome=$Session.CodexHome;historyBase=$Session.HistoryBase;params=$params}
        $intentBytes=$script:Utf8.GetBytes(($intent|ConvertTo-Json -Depth 50 -Compress));$intentHash=Get-FileHashText $intentBytes
        $stream=New-Object IO.FileStream($initialPath,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::None);try{$stream.Write($intentBytes,0,$intentBytes.Length);$stream.Flush($true)}finally{$stream.Dispose()}
        $reply=Invoke-CoordinatorRuntimeRpc $Runtime 'thread/start' $params $rpcTimeout
        if (-not $reply.thread.id) { throw 'BlockedRecovery: thread/start did not return an ID; intent remains recovery-closed.' }
        $ack=[ordered]@{kind='coordinator-initial-thread-ack-v1';intentHash=$intentHash;rootTaskId=$job.task_id;jobHash=$JobHash;launchHash=$LaunchHash;logicalSessionId=$Session.LogicalSessionId;threadId=[string]$reply.thread.id;reply=$reply}
        $ackBytes=$script:Utf8.GetBytes(($ack|ConvertTo-Json -Depth 50 -Compress));$ackPath=Join-Path (Split-Path -Parent $SessionPath) 'initial-thread-ack.json';$ackStream=New-Object IO.FileStream($ackPath,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::None);try{$ackStream.Write($ackBytes,0,$ackBytes.Length);$ackStream.Flush($true)}finally{$ackStream.Dispose()}
        $nativeAck=[ordered]@{taskId=$job.task_id;threadId=[string]$reply.thread.id;origin=$Runtime.ProviderReceipt.origin;generation=$Runtime.ProviderReceipt.generation;reply=$reply;rpc=$Runtime.LastRpcReceipt;initialAckPath=$ackPath;initialAckHash=(Get-AdmissionHash $ackBytes)}
        $nativeAckPath=Join-Path ($JobPath+'.inventory') ((Get-AdmissionObjectHash $nativeAck)+'.thread-ack.json')
        $nativeAckHash=Write-AdmissionJson $nativeAckPath $nativeAck -Immutable
        & $registryScript -Action RegisterNative -DataDirectory $launchForAdmission.registryDirectory -TaskId $job.task_id -DispatchId $job.dispatch_id -NativeThreadId ([string]$reply.thread.id) -Role koordinator -State active -NativeAckPath $nativeAckPath -NativeAckHash $nativeAckHash | Out-Null
        $Session.NativeThreadId=[string]$reply.thread.id
        $Session.ProvisionedAtUtc=[DateTime]::UtcNow.ToString('o')
        $Session.InitialIntentPath=$initialPath;$Session.InitialIntentHash=$intentHash;$Session.InitialAckPath=$ackPath;$Session.InitialAckHash=(Get-FileHashText $ackBytes)
        Write-CoordinatorAtomicJson $SessionPath $Session
    }
    if($Session.LastOutcome -in @('Starting','Running','Unknown')){ $Session.State='RecoveryUnknown';$Session.LastError='Prior turn outcome unresolved; replay prohibited.';Write-CoordinatorAtomicJson $SessionPath $Session;throw 'BlockedRecovery: prior turn unresolved.' }
    $Session.State='Ready'; $Session.LastError=$null; Write-CoordinatorAtomicJson $SessionPath $Session
    return $Session
}

function Get-FileHashText([byte[]]$Bytes) { $sha=[Security.Cryptography.SHA256]::Create();try{return ([BitConverter]::ToString($sha.ComputeHash($Bytes))).Replace('-','').ToLowerInvariant()}finally{$sha.Dispose()} }

function Invoke-CoordinatorTurn($Runtime, $Session, [string]$SessionPath, $Request) {
    $rpcTimeout=if($Runtime.RpcTimeoutMilliseconds){[int]$Runtime.RpcTimeoutMilliseconds}else{15000}
    if((Get-AdmissionField $Request 'operation') -eq 'AdmissionRequest'){
        if((Get-AdmissionField $Request 'logicalSessionId') -cne $Session.LogicalSessionId -or $Session.State -cne 'Ready'){return @{status='Unknown';reason='SerializedHostNotReady'}}
            $hostRpc={param($m,$q,$ms)Invoke-CoordinatorRuntimeRpc $Runtime $m $q ([int][Math]::Min($ms,$Runtime.RpcTimeoutMilliseconds))}.GetNewClosure()
            $hostMarkers={@{mutation=$Runtime.MutationGeneration;gap=$Runtime.GapGeneration;rpc=$Runtime.LastRpcReceipt}}.GetNewClosure()
        try{$reservation=Invoke-CoordinatorAdmission $Runtime $Session $SessionPath (Get-AdmissionField $Request 'target') (Join-Path $PSScriptRoot 'Register-CoordinatorExecution.ps1') ([int](Get-AdmissionField $Request 'budgetMilliseconds' 10000)) -HostRpc $hostRpc -HostMarkers $hostMarkers;return @{status='Reserved';reservation=$reservation}}
        catch{return @{status='Unknown';reason=$_.Exception.Message}}
    }
    if ($Request.operation -eq 'Status') { return @{status=$Session.State;logicalSessionId=$Session.LogicalSessionId;nativeThreadId=$Session.NativeThreadId;requestId=$Request.requestId;lastRequestId=$Session.LastRequestId;lastTurnId=$Session.LastTurnId;lastUsage=$Session.LastUsage;usageStatus=$(if($null -eq $Session.LastUsage){'unknown'}else{'known'})} }
    if ($Request.operation -eq 'Interrupt') { return @{status='Unavailable';requestId=$Request.requestId;message='No safely identified active turn.'} }
    if ($Request.operation -ne 'SubmitInput' -or -not $Request.requestId -or -not $Request.inputText) { return @{status='Rejected';requestId=$Request.requestId} }
    if ($Request.logicalSessionId -cne $Session.LogicalSessionId) { return @{status='Rejected';requestId=$Request.requestId} }
    $effectMode=Get-CoordinatorConfigValue $Request 'effectMode'
    if ($effectMode -and $effectMode -cne 'coordinator-effects-v1') { return @{status='Rejected';requestId=$Request.requestId;message='UnsupportedEffectMode'} }
    if ($effectMode -eq 'coordinator-effects-v1') {
        foreach($field in @('executionId','eventId','inputHash','baseRevision','threadId')) { if ([string]::IsNullOrWhiteSpace([string](Get-CoordinatorConfigValue $Request $field))) { return @{status='Rejected';requestId=$Request.requestId;message="UnsupportedEffectMode: missing $field binding."} } }
        if ([string]$Request.threadId -cne [string]$Session.NativeThreadId) { return @{status='Rejected';requestId=$Request.requestId;message='EffectHostBindingMismatch: threadId.'} }
    }
    $history=@($Session.RequestHistory); $fingerprint=[Convert]::ToBase64String([Security.Cryptography.SHA256]::Create().ComputeHash($script:Utf8.GetBytes([string]$Request.inputText)))
    $prior=@($history|Where-Object{$_.requestId -ceq $Request.requestId});if($prior.Count -gt 1){throw 'RequestHistoryAmbiguous'}
    if($prior.Count){$oldDecision=Get-CoordinatorConfigValue $prior[0] 'decision';$oldOutcome=Get-CoordinatorConfigValue $prior[0] 'outcome';if((Get-CoordinatorConfigValue $prior[0] 'fingerprint') -cne $fingerprint){return @{status='Rejected';requestId=$Request.requestId;message='RequestId payload conflict.'}};if($oldOutcome -in @('Starting','Running','Unknown') -or -not $oldDecision){return @{status='BlockedRecovery';requestId=$Request.requestId;classification='Unknown'}};return @{status='Duplicate';classification='Duplicate';requestId=$Request.requestId;outcome=$oldOutcome;decision=$oldDecision;assistantText=(Get-CoordinatorConfigValue $prior[0] 'assistantText');turnId=(Get-CoordinatorConfigValue $prior[0] 'turnId');tokenUsage=(Get-CoordinatorConfigValue $prior[0] 'usage');usageStatus=$(if($null -eq (Get-CoordinatorConfigValue $prior[0] 'usage')){'unknown'}else{'known'})} }
    # Completed archived requests remain visible to dedup; unresolved history is never evicted.
    if ($Session.State -ne 'Ready') { return @{status='Busy';requestId=$Request.requestId} }
    $ledgerDirectory=if($Request.PSObject.Properties['accountingDirectory']){$Request.accountingDirectory}else{$null}
    if($ledgerDirectory -and -not [IO.Path]::IsPathRooted([string]$ledgerDirectory)){return @{status='Rejected';requestId=$Request.requestId;message='AccountingDirectory must be an explicit absolute path.'}}
    $historyEntry=@{requestId=$Request.requestId;fingerprint=$fingerprint;threadId=$Session.NativeThreadId;turnId=$null;outcome='Starting';usage=$null}
    if($effectMode -eq 'coordinator-effects-v1'){ $historyEntry.effectMode=$effectMode; $historyEntry.executionId=[string]$Request.executionId; $historyEntry.eventId=[string]$Request.eventId; $historyEntry.inputHash=[string]$Request.inputHash; $historyEntry.baseRevision=[string]$Request.baseRevision }
    $Session.RequestHistory=@($history)+@($historyEntry)
    $Session.State='StartingTurn'; $Session.LastRequestId=$Request.requestId; $Session.LastTurnId=$null; $Session.LastUsage=$null; $Session.LastOutcome='Starting'; $Session.LastSource=$Request.source
    Write-CoordinatorAtomicJson $SessionPath $Session
    try {
        $turnParams=@{threadId=$Session.NativeThreadId;input=@(@{type='text';text=[string]$Request.inputText})}
        if($effectMode -eq 'coordinator-effects-v1') { $turnParams.sandboxPolicy=@{type='readOnly'} }
        $started=Invoke-CoordinatorRuntimeRpc $Runtime 'turn/start' $turnParams $rpcTimeout
        $Session.LastTurnId=if($started.turn.id){[string]$started.turn.id}else{$null}
        if (-not $Session.LastTurnId) { throw 'RecoveryUnknown: turn/start ACK lacks turn ID.' }
        $Session.State='RunningTurn'; $runningEntry=@($Session.RequestHistory|Where-Object{$_.requestId -ceq $Request.requestId})[0];$runningEntry.turnId=$Session.LastTurnId;$runningEntry.outcome='Running'; Write-CoordinatorAtomicJson $SessionPath $Session
        if($Runtime.ContextJobPath -and $Runtime.ContextStorePath -and $Runtime.ContextDirectory){
            $cm=Import-Module (Join-Path $PSScriptRoot '..\workitems\CoordinatorExecutionContext.psm1') -PassThru -Force
            $authority=[Convert]::ToBase64String($script:Utf8.GetBytes([string]$Request.inputText));$authorityHash=& $cm {param($x)Get-ContextHash $x} ([Convert]::FromBase64String($authority))
            $runningContext=& $cm {param($d,$j,$s,$t,$u,$r,$sid,$a,$e) New-ExecutionTurnContext -Directory $d -JobPath $j -StorePath $s -ThreadId $t -TurnId $u -RequestId $r -Outcome Running -SessionId $sid -AuthorityHash $a -EvidenceHash $e} $Runtime.ContextDirectory $Runtime.ContextJobPath $Runtime.ContextStorePath $Session.NativeThreadId $Session.LastTurnId $Request.requestId $Session.LogicalSessionId $authorityHash $fingerprint
            $runningEntry.contextPath=$runningContext.path;$runningEntry.contextHash=$runningContext.hash
            Write-CoordinatorAtomicJson ($Runtime.ContextJobPath+'.active.json') ([ordered]@{task_id=$Session.RootTaskId;role='koordinator';job_hash=$runningContext.record.jobHash;thread_id=$Session.NativeThreadId;turn_id=$Session.LastTurnId;state='RunningTurn';store_path=$Runtime.ContextStorePath;accounting_directory=$Session.AccountingDirectory;logical_session_id=$Session.LogicalSessionId;owner_pid=$Session.OwnerPid;owner_started_utc=$Session.OwnerStartedUtc;context_path=$runningContext.path;context_hash=$runningContext.hash})
        }
        $turnTimeout=if($Runtime.TurnTimeoutMilliseconds){[int]$Runtime.TurnTimeoutMilliseconds}else{600000};$watch=[Diagnostics.Stopwatch]::StartNew(); $terminal=$false
        $usage=$null
        $assistantParts=New-Object System.Collections.Generic.List[string]
        $finalItems=[ordered]@{}; $invalidFinalItem=$false
        foreach($n in @($Runtime.Notifications.ToArray())) { if($n.method -eq 'thread/tokenUsage/updated' -and (Test-CoordinatorNotificationBinding $n $Session.NativeThreadId $Session.LastTurnId)){$usage=Get-CoordinatorConfigValue (Get-CoordinatorConfigValue (Get-CoordinatorConfigValue $n 'params') 'tokenUsage') 'last'}; if($n.method -eq 'item/agentMessage/delta' -and (Test-CoordinatorNotificationBinding $n $Session.NativeThreadId $Session.LastTurnId)){$delta=Get-CoordinatorConfigValue (Get-CoordinatorConfigValue $n 'params') 'delta';if($null -ne $delta){$assistantParts.Add([string]$delta)}}; if($effectMode -eq 'coordinator-effects-v1' -and $n.method -eq 'item/completed' -and (Test-CoordinatorNotificationBinding $n $Session.NativeThreadId $Session.LastTurnId)){ $item=Get-CoordinatorConfigValue (Get-CoordinatorConfigValue $n 'params') 'item';if((Get-CoordinatorConfigValue $item 'type') -eq 'agentMessage' -and (Get-CoordinatorConfigValue $item 'phase') -eq 'final_answer'){ $iid=[string](Get-CoordinatorConfigValue $item 'id');if(-not $iid){$invalidFinalItem=$true;continue};$itext=[string](Get-CoordinatorConfigValue $item 'text');if($finalItems.Contains($iid) -and $finalItems[$iid] -cne $itext){$iid='__conflict_'+[guid]::NewGuid().ToString('N')};$finalItems[$iid]=$itext } }; if ($n.method -eq 'turn/completed' -and (Test-CoordinatorNotificationBinding $n $Session.NativeThreadId $Session.LastTurnId)) { $terminal=$true } }
        while ($watch.ElapsedMilliseconds -lt $turnTimeout -and -not $Runtime.Process.HasExited) {
            if (-not $Runtime.PendingRead) { $Runtime.PendingRead=$Runtime.Reader.ReadLineAsync() }
            if ($Runtime.PendingRead.Wait(100)) { $line=$Runtime.PendingRead.Result;$Runtime.PendingRead=$null; if ($line) { $m=$line|ConvertFrom-Json; $messageMethod=Get-CoordinatorConfigValue $m 'method';if(-not $messageMethod){$Runtime.TransportUnknown=$true;$Runtime.GapGeneration++;throw 'RecoveryUnknown: UnexpectedOrLateRpcResponseDuringTurn'}; if ($messageMethod) { $messageId=Get-CoordinatorConfigValue $m 'id';if($null -ne $messageId){throw 'BlockedRecovery: unsupported runtime server request.'};if((Test-CoordinatorNotificationBinding $m $Session.NativeThreadId $Session.LastTurnId)){if($messageMethod -eq 'item/agentMessage/delta'){$delta=Get-CoordinatorConfigValue (Get-CoordinatorConfigValue $m 'params') 'delta';if($null -ne $delta){$assistantParts.Add([string]$delta)}};if($effectMode -eq 'coordinator-effects-v1' -and $messageMethod -eq 'item/completed'){ $item=Get-CoordinatorConfigValue (Get-CoordinatorConfigValue $m 'params') 'item';if((Get-CoordinatorConfigValue $item 'type') -eq 'agentMessage' -and (Get-CoordinatorConfigValue $item 'phase') -eq 'final_answer'){ $iid=[string](Get-CoordinatorConfigValue $item 'id');if(-not $iid){$invalidFinalItem=$true}else{$itext=[string](Get-CoordinatorConfigValue $item 'text');if($finalItems.Contains($iid) -and $finalItems[$iid] -cne $itext){$iid='__conflict_'+[guid]::NewGuid().ToString('N')};$finalItems[$iid]=$itext} } };if($messageMethod -eq 'thread/tokenUsage/updated'){$usage=Get-CoordinatorConfigValue (Get-CoordinatorConfigValue (Get-CoordinatorConfigValue $m 'params') 'tokenUsage') 'last'};if($messageMethod -eq 'turn/completed'){$terminal=$true}};$Runtime.MutationGeneration++;if($Runtime.Notifications.Count -ge 256){$Runtime.GapGeneration++;$Runtime.Notifications.RemoveAt(0)};[void]$Runtime.Notifications.Add($m) };if ($terminal) { break } } }
            if ($terminal) { break }
        }
        if (-not $terminal) { $Session.State='RecoveryUnknown'; $Session.LastOutcome='Unknown'; Write-CoordinatorAtomicJson $SessionPath $Session; return @{status='BlockedRecovery';requestId=$Request.requestId} }
        $terminalStatus='completed';foreach($n in @($Runtime.Notifications.ToArray())){$turnStatus=Get-CoordinatorConfigValue (Get-CoordinatorConfigValue (Get-CoordinatorConfigValue $n 'params') 'turn') 'status';if($n.method -eq 'turn/completed' -and (Test-CoordinatorNotificationBinding $n $Session.NativeThreadId $Session.LastTurnId) -and $turnStatus){$terminalStatus=[string]$turnStatus}}
        $Session.State='Ready'; $Session.LastOutcome=$terminalStatus; $Session.LastUsage=$usage
        $assistantText=($assistantParts -join '')
        $decision=[ordered]@{outcome=$terminalStatus;requestId=$Request.requestId;turnId=$Session.LastTurnId;assistantText=$assistantText;usage=$usage;completedAtUtc=[DateTime]::UtcNow.ToString('o')}
        if($effectMode -eq 'coordinator-effects-v1') { $effectRequest=[ordered]@{logicalSessionId=[string]$Session.LogicalSessionId;threadId=[string]$Session.NativeThreadId;turnId=[string]$Session.LastTurnId;requestId=[string]$Request.requestId;eventId=[string]$Request.eventId;executionId=[string]$Request.executionId;inputHash=[string]$Request.inputHash;baseRevision=[string]$Request.baseRevision}; $planDecision=ConvertTo-CoordinatorEffectDecision @($finalItems.GetEnumerator()|ForEach-Object{@{id=$_.Key;text=$_.Value}}) $effectRequest $Session $terminalStatus $invalidFinalItem; foreach($key in $planDecision.Keys){$decision[$key]=$planDecision[$key]} }
        $entry=@($Session.RequestHistory|Where-Object{$_.requestId -ceq $Request.requestId})[0];$entry.turnId=$Session.LastTurnId;$entry.outcome=$terminalStatus;$entry.usage=$usage;$entry.assistantText=$assistantText;$entry.decision=$decision
        if($Runtime.ContextJobPath -and $Runtime.ContextStorePath -and $Runtime.ContextDirectory){
            $cm=Import-Module (Join-Path $PSScriptRoot '..\workitems\CoordinatorExecutionContext.psm1') -PassThru -Force
            $decisionBytes=$script:Utf8.GetBytes(($decision|ConvertTo-Json -Depth 50 -Compress));$evidenceHash=& $cm {param($b)Get-ContextHash $b} $decisionBytes
            $outcome=if($terminalStatus -eq 'completed'){'Completed'}elseif($terminalStatus -eq 'interrupted'){'Interrupted'}else{'Failed'}
            $terminalContext=& $cm {param($d,$j,$s,$t,$u,$r,$sid,$a,$e,$o) New-ExecutionTurnContext -Directory $d -JobPath $j -StorePath $s -ThreadId $t -TurnId $u -RequestId $r -Outcome $o -SessionId $sid -AuthorityHash $a -EvidenceHash $e} $Runtime.ContextDirectory $Runtime.ContextJobPath $Runtime.ContextStorePath $Session.NativeThreadId $Session.LastTurnId $Request.requestId $Session.LogicalSessionId $authorityHash $evidenceHash $outcome
            $entry.terminalContextPath=$terminalContext.path;$entry.terminalContextHash=$terminalContext.hash
            Write-CoordinatorAtomicJson ($Runtime.ContextJobPath+'.active.json') ([ordered]@{task_id=$Session.RootTaskId;role='koordinator';job_hash=$terminalContext.record.jobHash;thread_id=$Session.NativeThreadId;turn_id=$Session.LastTurnId;state='Ready';store_path=$Runtime.ContextStorePath;accounting_directory=$Session.AccountingDirectory;logical_session_id=$Session.LogicalSessionId;owner_pid=$Session.OwnerPid;owner_started_utc=$Session.OwnerStartedUtc;context_path=$terminalContext.path;context_hash=$terminalContext.hash})
        }
        Write-CoordinatorAtomicJson $SessionPath $Session
        if($ledgerDirectory){
            $requestHash=[Security.Cryptography.SHA256]::Create().ComputeHash($script:Utf8.GetBytes([string]$Request.requestId))
            $taskId=([BitConverter]::ToString($requestHash)).Replace('-','').Substring(0,32).ToLowerInvariant()
            $parentTaskId=if($Request.PSObject.Properties['parentTaskId']){$Request.parentTaskId}else{$null}
            $record=@{task_id=$taskId;parent_task_id=$parentTaskId;accounting_directory=[IO.Path]::GetFullPath($ledgerDirectory);role='koordinator';thread_id=$Session.NativeThreadId;turn_id=$Session.LastTurnId;request_id=$Request.requestId;token_usage=$usage;source='coordinator_last_snapshot'}
            [void][IO.Directory]::CreateDirectory($ledgerDirectory);$ledgerPath=Join-Path $ledgerDirectory ($taskId+'.usage.json')
            if(-not [IO.File]::Exists($ledgerPath)){Write-CoordinatorAtomicJson $ledgerPath $record}
            $summary=& (Join-Path (Split-Path -Parent $PSScriptRoot) 'Get-TaskTokenUsage.ps1') -TaskId $taskId -AccountingDirectory $ledgerDirectory
            if($effectMode -ne 'coordinator-effects-v1'){Set-LCValue $entry 'archiveReady' $true;Write-CoordinatorAtomicJson $SessionPath $Session}
            return @{status=$(if($terminalStatus -eq 'completed'){'Accepted'}else{'Failed'});classification='Terminal';outcome=$terminalStatus;decision=$decision;assistantText=$assistantText;requestId=$Request.requestId;turnId=$Session.LastTurnId;tokenUsage=$usage;usageSummary=$summary;usageStatus=$(if($null -eq $usage){'unknown'}else{'known'})}
        }
        if($effectMode -ne 'coordinator-effects-v1'){Set-LCValue $entry 'archiveReady' $true;Write-CoordinatorAtomicJson $SessionPath $Session}
        return @{status=$(if($terminalStatus -eq 'completed'){'Accepted'}else{'Failed'});classification='Terminal';outcome=$terminalStatus;decision=$decision;assistantText=$assistantText;requestId=$Request.requestId;turnId=$Session.LastTurnId;tokenUsage=$usage;usageStatus=$(if($null -eq $usage){'unknown'}else{'known'})}
    } catch {
        if($Session.LastOutcome -in @('completed','failed','interrupted')){$Session.AccountingError=$_.Exception.Message;Write-CoordinatorAtomicJson $SessionPath $Session;return @{status='AccountingError';requestId=$Request.requestId;turnId=$Session.LastTurnId;message='Turn completed; accounting persistence failed.'}}
        $Session.State='RecoveryUnknown'; $Session.LastOutcome='Unknown'; $Session.LastError=$_.Exception.Message
        Write-CoordinatorAtomicJson $SessionPath $Session
        return @{status='BlockedRecovery';requestId=$Request.requestId}
    }
}

function Start-CoordinatorPipe($Config, [scriptblock]$OnRequest, [scriptblock]$OnIdle) {
    $nextIdle=[DateTime]::UtcNow.AddSeconds(5)
    while (-not $Config.StopRequested) {
        if ($Config.RuntimeProcess -and $Config.RuntimeProcess.HasExited) { throw 'RetryableRuntimeExit: Runtime exited while coordinator pipe was idle.' }
        $server=$null
        try {
            $server=New-CoordinatorPipeServer $Config.PipeName
            $wait=$server.BeginWaitForConnection($null,$null)
            while (-not $wait.AsyncWaitHandle.WaitOne(100)) { if ($Config.StopRequested) { break }; if ($Config.RuntimeProcess -and $Config.RuntimeProcess.HasExited) { throw 'RetryableRuntimeExit: Runtime exited while coordinator pipe was idle.' };if($OnIdle -and [DateTime]::UtcNow -ge $nextIdle){try{& $OnIdle}catch{if($_.Exception.Message -like 'BlockedRecovery:*' -or $_.Exception.Message -like 'RecoveryUnknown:*'){throw}};$nextIdle=[DateTime]::UtcNow.AddSeconds(5)} }
            if ($Config.StopRequested) { break }
            $server.EndWaitForConnection($wait)
            $reader=New-Object IO.StreamReader($server,$script:Utf8,$false,4096,$true)
            $line=$reader.ReadLine()
            if (-not $line -or $script:Utf8.GetByteCount($line) -gt 1048576) { throw 'InvalidRequest' }
            $request=$line|ConvertFrom-Json -ErrorAction Stop
            if($OnIdle -and [DateTime]::UtcNow -ge $nextIdle){try{& $OnIdle}catch{if($_.Exception.Message -like 'BlockedRecovery:*' -or $_.Exception.Message -like 'RecoveryUnknown:*'){throw}};$nextIdle=[DateTime]::UtcNow.AddSeconds(5)}
            $response=& $OnRequest $request
            $writer=New-Object IO.StreamWriter($server,$script:Utf8,4096,$true); $writer.AutoFlush=$true
            $writer.WriteLine((ConvertTo-Json -InputObject $response -Depth 20 -Compress)); $writer.Dispose(); $reader.Dispose()
        } catch { if ($server -and $server.IsConnected) { $server.Dispose() }; if ($_.Exception.Message -like 'RetryableRuntimeExit:*' -or $_.Exception.Message -like 'BlockedRecovery:*' -or $_.Exception.Message -like 'RecoveryUnknown:*') { throw } }
        finally { if ($server) { $server.Dispose() } }
    }
}

Export-ModuleMember -Function Get-CoordinatorHistory,Write-CoordinatorAtomicJson,Read-CoordinatorSession,Get-CoordinatorPrivateStoreModule,Get-CoordinatorConfigValue,Invoke-CoordinatorPrivateStore,Enter-CoordinatorOwnership,Exit-CoordinatorOwnership,Invoke-CoordinatorRuntimeRpc,Test-CoordinatorNotificationBinding,Start-CoordinatorRuntime,New-CoordinatorPipeServer,Initialize-CoordinatorRuntime,Invoke-CoordinatorTurn,Start-CoordinatorPipe
