Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$script:Utf8 = New-Object System.Text.UTF8Encoding($false, $true)

function Write-CoordinatorAtomicJson([string]$Path, $Value) {
    $dir = [IO.Path]::GetDirectoryName($Path)
    if (-not [IO.Directory]::Exists($dir)) { [void][IO.Directory]::CreateDirectory($dir) }
    $tmp = $Path + '.' + [guid]::NewGuid().ToString('N') + '.writing'
    [IO.File]::WriteAllText($tmp, (ConvertTo-Json -InputObject $Value -Depth 20 -Compress), $script:Utf8)
    if ([IO.File]::Exists($Path)) {
        $backup = $tmp + '.replace-backup'
        [IO.File]::Replace($tmp, $Path, $backup)
        [IO.File]::Delete($backup)
    }
    else { [IO.File]::Move($tmp, $Path) }
}

function Read-CoordinatorSession([string]$Path) {
    if (-not [IO.File]::Exists($Path)) { return $null }
    try { return ([IO.File]::ReadAllText($Path, $script:Utf8) | ConvertFrom-Json -ErrorAction Stop) }
    catch { throw 'BlockedRecovery: Sessiondaten unlesbar oder unvollständig.' }
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
    $id = [int]$Runtime.NextId; $Runtime.NextId++
    $request = @{jsonrpc='2.0';id=$id;method=$Method;params=$Params} | ConvertTo-Json -Depth 20 -Compress
    $bytes = $script:Utf8.GetBytes($request + "`n")
    $Runtime.Input.Write($bytes,0,$bytes.Length); $Runtime.Input.Flush()
    $deadline = [DateTime]::UtcNow.AddMilliseconds($TimeoutMilliseconds)
    while ([DateTime]::UtcNow -lt $deadline) {
        if ($Runtime.Process.HasExited) { throw 'Unavailable: Runtime exited.' }
        if (-not $Runtime.PendingRead) { $Runtime.PendingRead=$Runtime.Reader.ReadLineAsync() }
        if ($Runtime.PendingRead.Wait([int][Math]::Max(1,($deadline-[DateTime]::UtcNow).TotalMilliseconds))) {
            $line=$Runtime.PendingRead.Result; $Runtime.PendingRead=$null
            if (-not $line) { throw 'Unavailable: Runtime closed stdout.' }
            $message = $line | ConvertFrom-Json -ErrorAction Stop
            if ($message.id -eq $id) {
                $rpcError=$message.PSObject.Properties['error']
                if ($rpcError -and $rpcError.Value) { throw ('RuntimeError: ' + $rpcError.Value.message) }
                return $message.result
            }
            if ($message.PSObject.Properties['method'] -and $message.method) { if (-not $Runtime.Notifications) { $Runtime.Notifications=New-Object System.Collections.ArrayList };[void]$Runtime.Notifications.Add($message) }
        }
    }
    throw 'RecoveryUnknown: Runtime RPC response timed out.'
}

function Start-CoordinatorRuntime($Config) {
    if ($Config.PSObject.Properties['RuntimeFactory'] -and $Config.RuntimeFactory) { return & $Config.RuntimeFactory $Config }
    $exe = if ($Config.PSObject.Properties['RuntimeExecutable'] -and $Config.RuntimeExecutable) { $Config.RuntimeExecutable } else { (Get-Command codex.exe -ErrorAction Stop).Source }
    $psi = New-Object Diagnostics.ProcessStartInfo
    $psi.FileName = $exe
    if ($Config.PSObject.Properties['RuntimeArguments'] -and $Config.RuntimeArguments) { $psi.Arguments=(@($Config.RuntimeArguments|ForEach-Object { '"'+([string]$_).Replace('"','\"')+'"' }) -join ' ') }
    else { $psi.Arguments = 'app-server --stdio' }
    $psi.UseShellExecute=$false
    $psi.RedirectStandardInput=$true; $psi.RedirectStandardOutput=$true; $psi.RedirectStandardError=$true
    $psi.CreateNoWindow=$true; $psi.WorkingDirectory=$Config.WorkingDirectory
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
        return [pscustomobject]@{ Process=$p; Input=$p.StandardInput.BaseStream; Reader=$p.StandardOutput; NextId=1; PendingRead=$null; Notifications=(New-Object System.Collections.ArrayList); Owned=$true; JobHandle=$jobHandle; StartedAtUtc=$p.StartTime.ToUniversalTime().ToString('o') }
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

function Initialize-CoordinatorRuntime($Runtime, $Session, [string]$SessionPath) {
    $null=Invoke-CoordinatorRuntimeRpc $Runtime 'initialize' @{clientInfo=@{name='agent-organization-coordinator';version='1'}}
    $null=Invoke-CoordinatorRuntimeRpc $Runtime 'initialized' @{}
    if ($Session.NativeThreadId) {
        $Session.State='Resuming'; $Session.ResumeAttempts=[int]$Session.ResumeAttempts+1
        Write-CoordinatorAtomicJson $SessionPath $Session
        $reply=$null; $retryLimit=[int]$Runtime.ResumeRetryLimit
        for($attempt=1;$attempt -le $retryLimit;$attempt++) {
            try { $reply=Invoke-CoordinatorRuntimeRpc $Runtime 'thread/resume' @{threadId=$Session.NativeThreadId}; break }
            catch {
                $message=$_.Exception.Message
                if($message -match 'authentication|auth|login|credential') { $Session.State='BlockedRecovery';$Session.LastError='AuthenticationUnavailable';Write-CoordinatorAtomicJson $SessionPath $Session;throw 'BlockedRecovery: authentication unavailable.' }
                $retryableRuntimeError = $message -like 'RuntimeError:*' -and $message -notmatch 'not found|does not exist|invalid thread|unsupported|authentication|auth|login|credential'
                $retryableTimeout = $message -like 'RecoveryUnknown: Runtime RPC response timed out.'
                if(($retryableRuntimeError -or $retryableTimeout) -and $attempt -lt $retryLimit -and -not $Runtime.Process.HasExited) { Start-Sleep -Milliseconds ([Math]::Min(1000,100*$attempt)); continue }
                $Session.State='BlockedRecovery';$Session.LastError=$message;Write-CoordinatorAtomicJson $SessionPath $Session;throw 'BlockedRecovery: same-thread resume failed; no replacement thread or replay.'
            }
        }
        if ($reply.thread.id -cne $Session.NativeThreadId) { $Session.State='BlockedRecovery'; $Session.LastError='Resume thread ID mismatch'; Write-CoordinatorAtomicJson $SessionPath $Session; throw 'BlockedRecovery: Resume ID mismatch.' }
    } else {
        # Provisioning is deliberately disabled unless explicitly enabled by an isolated harness.
        if (-not $Session.AllowProvisioning) { throw 'BlockedRecovery: No persisted native thread; provisioning requires controlled handoff.' }
        $reply=Invoke-CoordinatorRuntimeRpc $Runtime 'thread/start' @{cwd=$Session.Cwd}
        if (-not $reply.thread.id) { throw 'BlockedRecovery: thread/start did not return an ID.' }
        $Session.NativeThreadId=[string]$reply.thread.id
        $Session.ProvisionedAtUtc=[DateTime]::UtcNow.ToString('o')
        Write-CoordinatorAtomicJson $SessionPath $Session
    }
    $Session.State='Ready'; $Session.LastError=$null; Write-CoordinatorAtomicJson $SessionPath $Session
    return $Session
}

function Invoke-CoordinatorTurn($Runtime, $Session, [string]$SessionPath, $Request) {
    if ($Request.operation -eq 'Status') { return @{status=$Session.State;logicalSessionId=$Session.LogicalSessionId;nativeThreadId=$Session.NativeThreadId;requestId=$Request.requestId;lastRequestId=$Session.LastRequestId;lastTurnId=$Session.LastTurnId;lastUsage=$Session.LastUsage;usageStatus=$(if($null -eq $Session.LastUsage){'unknown'}else{'known'})} }
    if ($Request.operation -eq 'Interrupt') { return @{status='Unavailable';requestId=$Request.requestId;message='No safely identified active turn.'} }
    if ($Request.operation -ne 'SubmitInput' -or -not $Request.requestId -or -not $Request.inputText) { return @{status='Rejected';requestId=$Request.requestId} }
    if ($Request.logicalSessionId -cne $Session.LogicalSessionId) { return @{status='Rejected';requestId=$Request.requestId} }
    if ($Session.LastRequestId -ceq $Request.requestId) { return @{status='Duplicate';requestId=$Request.requestId;outcome=$Session.LastOutcome;turnId=$Session.LastTurnId;tokenUsage=$Session.LastUsage;usageStatus=$(if($null -eq $Session.LastUsage){'unknown'}else{'known'})} }
    if ($Session.State -ne 'Ready') { return @{status='Busy';requestId=$Request.requestId} }
    $Session.State='StartingTurn'; $Session.LastRequestId=$Request.requestId; $Session.LastTurnId=$null; $Session.LastUsage=$null; $Session.LastOutcome='Starting'; $Session.LastSource=$Request.source
    Write-CoordinatorAtomicJson $SessionPath $Session
    try {
        $started=Invoke-CoordinatorRuntimeRpc $Runtime 'turn/start' @{threadId=$Session.NativeThreadId;input=@(@{type='text';text=[string]$Request.inputText})}
        $Session.LastTurnId=if($started.turn.id){[string]$started.turn.id}else{$null}
        if (-not $Session.LastTurnId) { throw 'RecoveryUnknown: turn/start ACK lacks turn ID.' }
        $Session.State='RunningTurn'; Write-CoordinatorAtomicJson $SessionPath $Session
        $end=[DateTime]::UtcNow.AddMinutes(10); $terminal=$false
        $usage=$null
        foreach($n in @($Runtime.Notifications.ToArray())) { if($n.method -eq 'thread/tokenUsage/updated' -and $n.params.threadId -ceq $Session.NativeThreadId -and $n.params.turnId -ceq $Session.LastTurnId){$usage=$n.params.tokenUsage.last}; if ($n.method -eq 'turn/completed' -and $n.params.turn.id -ceq $Session.LastTurnId) { $terminal=$true } }
        while ([DateTime]::UtcNow -lt $end -and -not $Runtime.Process.HasExited) {
            if (-not $Runtime.PendingRead) { $Runtime.PendingRead=$Runtime.Reader.ReadLineAsync() }
            if ($Runtime.PendingRead.Wait(100)) { $line=$Runtime.PendingRead.Result;$Runtime.PendingRead=$null; if ($line) { $m=$line|ConvertFrom-Json; if ($m.method) { [void]$Runtime.Notifications.Add($m) };if($m.method -eq 'thread/tokenUsage/updated' -and $m.params.threadId -ceq $Session.NativeThreadId -and $m.params.turnId -ceq $Session.LastTurnId){$usage=$m.params.tokenUsage.last};if ($m.method -eq 'turn/completed' -and $m.params.turn.id -ceq $Session.LastTurnId) { $terminal=$true; break } } }
            if ($terminal) { break }
        }
        if (-not $terminal) { $Session.State='RecoveryUnknown'; $Session.LastOutcome='Unknown'; Write-CoordinatorAtomicJson $SessionPath $Session; return @{status='BlockedRecovery';requestId=$Request.requestId} }
        $Session.State='Ready'; $Session.LastOutcome='Completed'; $Session.LastUsage=$usage; Write-CoordinatorAtomicJson $SessionPath $Session
        $ledgerDirectory=$Request.accountingDirectory
        if($ledgerDirectory){
            if (-not [IO.Path]::IsPathRooted([string]$ledgerDirectory)) { throw 'AccountingDirectory must be an explicit absolute path.' }
            $requestHash=[Security.Cryptography.SHA256]::Create().ComputeHash($script:Utf8.GetBytes([string]$Request.requestId))
            $taskId=([BitConverter]::ToString($requestHash)).Replace('-','').Substring(0,32).ToLowerInvariant()
            $record=@{task_id=$taskId;parent_task_id=$Request.parentTaskId;accounting_directory=[IO.Path]::GetFullPath($ledgerDirectory);role='koordinator';thread_id=$Session.NativeThreadId;turn_id=$Session.LastTurnId;request_id=$Request.requestId;token_usage=$usage;source='coordinator_last_snapshot'}
            [void][IO.Directory]::CreateDirectory($ledgerDirectory);$ledgerPath=Join-Path $ledgerDirectory ($taskId+'.usage.json')
            if(-not [IO.File]::Exists($ledgerPath)){Write-CoordinatorAtomicJson $ledgerPath $record}
            $summary=& (Join-Path (Split-Path -Parent $PSScriptRoot) 'Get-TaskTokenUsage.ps1') -TaskId $taskId -AccountingDirectory $ledgerDirectory
            return @{status='Accepted';requestId=$Request.requestId;turnId=$Session.LastTurnId;tokenUsage=$usage;usageSummary=$summary}
        }
        return @{status='Accepted';requestId=$Request.requestId;turnId=$Session.LastTurnId;tokenUsage=$usage;usageStatus=$(if($null -eq $usage){'unknown'}else{'known'})}
    } catch {
        $Session.State='RecoveryUnknown'; $Session.LastOutcome='Unknown'; $Session.LastError=$_.Exception.Message
        Write-CoordinatorAtomicJson $SessionPath $Session
        return @{status='BlockedRecovery';requestId=$Request.requestId}
    }
}

function Start-CoordinatorPipe($Config, [scriptblock]$OnRequest) {
    while (-not $Config.StopRequested) {
        $server=$null
        try {
            $server=New-CoordinatorPipeServer $Config.PipeName
            $wait=$server.BeginWaitForConnection($null,$null)
            while (-not $wait.AsyncWaitHandle.WaitOne(100)) { if ($Config.StopRequested) { break } }
            if ($Config.StopRequested) { break }
            $server.EndWaitForConnection($wait)
            $reader=New-Object IO.StreamReader($server,$script:Utf8,$false,4096,$true)
            $line=$reader.ReadLine()
            if (-not $line -or $script:Utf8.GetByteCount($line) -gt 1048576) { throw 'InvalidRequest' }
            $request=$line|ConvertFrom-Json -ErrorAction Stop
            $response=& $OnRequest $request
            $writer=New-Object IO.StreamWriter($server,$script:Utf8,4096,$true); $writer.AutoFlush=$true
            $writer.WriteLine((ConvertTo-Json -InputObject $response -Depth 20 -Compress)); $writer.Dispose(); $reader.Dispose()
        } catch { if ($server -and $server.IsConnected) { $server.Dispose() } }
        finally { if ($server) { $server.Dispose() } }
    }
}

Export-ModuleMember -Function Write-CoordinatorAtomicJson,Read-CoordinatorSession,Get-CoordinatorPrivateStoreModule,Invoke-CoordinatorPrivateStore,Enter-CoordinatorOwnership,Exit-CoordinatorOwnership,Invoke-CoordinatorRuntimeRpc,Start-CoordinatorRuntime,New-CoordinatorPipeServer,Initialize-CoordinatorRuntime,Invoke-CoordinatorTurn,Start-CoordinatorPipe
