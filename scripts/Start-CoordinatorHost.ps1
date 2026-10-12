[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)][string]$DataDirectory,
    [string]$PipeName,
    [switch]$TestMode,
    [string]$RuntimeExecutable,
    [string]$RuntimeConfigPath,
    [string]$ReadyPath,
    [string]$ReleasePath,
    [string]$ExitPath,
    [string]$TaskId,
    [string]$ParentTaskId,
    [string]$AccountingDirectory,
    [ValidateRange(1,100)][int]$ResumeRetryLimit=3,
    [ValidateRange(100,60000)][int]$RpcTimeoutMilliseconds=15000,
    [string]$WorkingDirectory=(Get-Location).Path
)
$ErrorActionPreference='Stop'
$utf8=New-Object System.Text.UTF8Encoding($false,$true)
Import-Module (Join-Path $PSScriptRoot 'coordinator/CoordinatorHost.Core.psm1') -Force
$owner=$null; $runtime=$null; $activation=$null
$runtimePid=$null; $runtimeStartedAtUtc=$null
try {
    if (-not $PipeName) { $PipeName='agent-coordinator-'+([Convert]::ToBase64String([Security.Cryptography.SHA256]::Create().ComputeHash([Text.Encoding]::UTF8.GetBytes([IO.Path]::GetFullPath($DataDirectory)))).TrimEnd('=').Replace('+','_').Replace('/','_').Substring(0,24)) }
    if ($PipeName -notmatch '^[A-Za-z0-9_.-]{1,200}$') { throw 'Invalid PipeName.' }
    $owner=Enter-CoordinatorOwnership $DataDirectory -TestMode:$TestMode
    $activationName='Local\AgentOrganization.CoordinatorActivation.' + [Convert]::ToBase64String([Security.Cryptography.SHA256]::Create().ComputeHash([Text.Encoding]::UTF8.GetBytes($owner.DataDirectory))).TrimEnd('=').Replace('+','_').Replace('/','_')
    $activation=New-Object Threading.Mutex($false,$activationName)
    if (-not $activation.WaitOne(0)) { throw 'BlockedRecovery: another activation owns the native session.' }
    if (-not $TestMode -and $Host.UI.RawUI) { $Host.UI.RawUI.WindowTitle='Koordinator' }
    $path=$owner.SessionPath
    $session=Read-CoordinatorSession $path
    if ($null -eq $session) {
        $session=[pscustomobject]@{SchemaVersion=1;LogicalSessionId=[guid]::NewGuid().ToString('N');NativeThreadId=$null;State='BlockedRecovery';Revision=0;LastRequestId=$null;LastTurnId=$null;LastOutcome=$null;LastError='Controlled first handoff required';ResumeAttempts=0;RequestHistory=@();LastUsage=$null;AccountingError=$null;RuntimePid=$null;RuntimeStartedAtUtc=$null;Cwd=[IO.Path]::GetFullPath($WorkingDirectory);RuntimeExecutable=$null;CodexHome=$null;HistoryBase=$null;AllowProvisioning=[bool]$TestMode;OwnerPid=$PID;OwnerStartedUtc=$owner.OwnerStartedUtc;CreatedAtUtc=[DateTime]::UtcNow.ToString('o')}
        Write-CoordinatorAtomicJson $path $session
    }
    foreach($pair in @(@('ResumeAttempts',0),@('LastUsage',$null),@('RequestHistory',@()),@('AccountingError',$null),@('RuntimePid',$null),@('RuntimeStartedAtUtc',$null),@('RuntimeExecutable',$null),@('CodexHome',$null),@('HistoryBase',$null))) {
        if(-not $session.PSObject.Properties[$pair[0]]) { $session | Add-Member -NotePropertyName $pair[0] -NotePropertyValue $pair[1] }
    }
    if ($session.PSObject.Properties.Name -notcontains 'NativeThreadId') { throw 'BlockedRecovery: Session contract incomplete.' }
    if ($null -ne $session.RuntimePid) {
        $validatedRuntimePid=0
        if (-not [int]::TryParse([string]$session.RuntimePid,[ref]$validatedRuntimePid) -or $validatedRuntimePid -le 0) { throw 'BlockedRecovery: persisted runtime PID is invalid; no process was stopped.' }
        $old=$null
        $missing=$false
        try { $old=[Diagnostics.Process]::GetProcessById($validatedRuntimePid) }
        catch {
            $exception=$_.Exception
            while ($exception -and -not ($exception -is [ArgumentException])) { $exception=$exception.InnerException }
            if ($exception -is [ArgumentException]) { $missing=$true }
            else { throw 'BlockedRecovery: prior runtime identity could not be verified; no process was stopped.' }
        }
        if (-not $missing) {
            try {
                $oldStart=$old.StartTime.ToUniversalTime().ToString('o')
                if ($session.RuntimeStartedAtUtc -and $oldStart -ceq $session.RuntimeStartedAtUtc) { throw 'BlockedRecovery: prior runtime still alive; no process was stopped.' }
                throw 'BlockedRecovery: runtime owner identity is ambiguous; no process was stopped.'
            } catch { if ($_.Exception.Message -like 'BlockedRecovery:*') { throw }; throw 'BlockedRecovery: prior runtime start time could not be verified; no process was stopped.' }
            finally { if($old){$old.Dispose()} }
        }
        $session.RuntimePid=$null; $session.RuntimeStartedAtUtc=$null
        Write-CoordinatorAtomicJson $path $session
    }
    if ($ReadyPath) { [IO.File]::WriteAllText($ReadyPath, (ConvertTo-Json @{pid=$PID;startedAtUtc=$owner.OwnerStartedUtc;pipeName=$PipeName;dataDirectory=$owner.DataDirectory} -Compress),$utf8) }
    if ($TestMode -and $ReleasePath) {
        $deadline=[DateTime]::UtcNow.AddSeconds(30)
        while (-not (Test-Path -LiteralPath $ReleasePath) -and [DateTime]::UtcNow -lt $deadline) { Start-Sleep -Milliseconds 25 }
    }
    if ($ExitPath -and (Test-Path -LiteralPath $ExitPath)) { return }
    $runtimeConfig=@{RuntimeExecutable=$RuntimeExecutable;WorkingDirectory=[IO.Path]::GetFullPath($WorkingDirectory)}
    if ($RuntimeConfigPath) {
        if (-not $TestMode) { throw 'RuntimeConfigPath is restricted to TestMode.' }
        $runtimeConfig=([IO.File]::ReadAllText((Resolve-Path -LiteralPath $RuntimeConfigPath).Path,$utf8)|ConvertFrom-Json)
    }
    if ($runtimeConfig -is [System.Collections.IDictionary]) { $runtimeConfig['ResumeRetryLimit']=$ResumeRetryLimit }
    else { $runtimeConfig | Add-Member -MemberType NoteProperty -Name ResumeRetryLimit -Value $ResumeRetryLimit -Force }
    if ($runtimeConfig -is [System.Collections.IDictionary]) { $runtimeConfig['RpcTimeoutMilliseconds']=$RpcTimeoutMilliseconds; $runtimeConfig['TurnTimeoutMilliseconds']=600000 }
    else { $runtimeConfig | Add-Member -MemberType NoteProperty -Name RpcTimeoutMilliseconds -Value $RpcTimeoutMilliseconds -Force; $runtimeConfig | Add-Member -MemberType NoteProperty -Name TurnTimeoutMilliseconds -Value 600000 -Force }
    $effectiveCwd=[IO.Path]::GetFullPath([string]$runtimeConfig.WorkingDirectory)
    $configuredExe=Get-CoordinatorConfigValue $runtimeConfig 'RuntimeExecutable'
    $effectiveExe=if ($configuredExe) { [IO.Path]::GetFullPath((Resolve-Path -LiteralPath ([string]$configuredExe) -ErrorAction Stop).Path) } else { [IO.Path]::GetFullPath((Get-Command codex.exe -ErrorAction Stop).Source) }
    $effectiveHome=if ($env:CODEX_HOME) { [IO.Path]::GetFullPath($env:CODEX_HOME) } else { [IO.Path]::GetFullPath((Join-Path $env:USERPROFILE '.codex')) }
    if ($runtimeConfig -is [System.Collections.IDictionary]) { $runtimeConfig['CodexHome']=$effectiveHome }
    else { $runtimeConfig | Add-Member -MemberType NoteProperty -Name CodexHome -Value $effectiveHome -Force }
    if ($session.RuntimeExecutable -or $session.CodexHome -or $session.HistoryBase) {
        if (-not $session.RuntimeExecutable -or -not $session.CodexHome -or -not $session.HistoryBase -or
            -not ([IO.Path]::GetFullPath([string]$session.Cwd)).Equals($effectiveCwd,[StringComparison]::OrdinalIgnoreCase) -or
            -not ([IO.Path]::GetFullPath([string]$session.RuntimeExecutable)).Equals($effectiveExe,[StringComparison]::OrdinalIgnoreCase) -or
            -not ([IO.Path]::GetFullPath([string]$session.CodexHome)).Equals($effectiveHome,[StringComparison]::OrdinalIgnoreCase) -or
            -not ([IO.Path]::GetFullPath([string]$session.HistoryBase)).Equals($effectiveHome,[StringComparison]::OrdinalIgnoreCase)) { throw 'BlockedRecovery: runtime CWD, CLI, or CODEX_HOME history binding differs from the persisted session.' }
    } elseif ($session.NativeThreadId) { throw 'BlockedRecovery: persisted session lacks runtime history binding; controlled recovery required.' }
    else { $session.Cwd=$effectiveCwd; $session.RuntimeExecutable=$effectiveExe; $session.CodexHome=$effectiveHome; $session.HistoryBase=$effectiveHome; Write-CoordinatorAtomicJson $path $session }
    $runtimeConfig.RuntimeExecutable=$effectiveExe; $runtimeConfig.WorkingDirectory=$effectiveCwd
    $runtime=Start-CoordinatorRuntime $runtimeConfig
    $runtime | Add-Member -MemberType NoteProperty -Name ResumeRetryLimit -Value $ResumeRetryLimit -Force
    $runtime | Add-Member -MemberType NoteProperty -Name RpcTimeoutMilliseconds -Value $RpcTimeoutMilliseconds -Force
    $runtime | Add-Member -MemberType NoteProperty -Name TurnTimeoutMilliseconds -Value 600000 -Force
    if ($runtime.Process) { $runtimePid=$runtime.Process.Id; $runtimeStartedAtUtc=$runtime.StartedAtUtc; $session.RuntimePid=$runtimePid; $session.RuntimeStartedAtUtc=$runtimeStartedAtUtc;Write-CoordinatorAtomicJson $path $session }
    try { $session=Initialize-CoordinatorRuntime $runtime $session $path } catch { $session.State='BlockedRecovery';$session.LastError=$_.Exception.Message;Write-CoordinatorAtomicJson $path $session; throw }
    $config=[pscustomobject]@{PipeName=$PipeName;StopRequested=$false}
    if ($ExitPath -and $TestMode) {
        $until=[DateTime]::UtcNow.AddMinutes(30)
        while (-not (Test-Path -LiteralPath $ExitPath) -and [DateTime]::UtcNow -lt $until) {
            $config.StopRequested=$false
            # Request processing runs synchronously, guaranteeing one active dispatcher turn.
            $server=New-CoordinatorPipeServer $PipeName
            $pending=$server.BeginWaitForConnection($null,$null)
            while (-not $pending.AsyncWaitHandle.WaitOne(100) -and -not (Test-Path -LiteralPath $ExitPath)) { }
            if (Test-Path -LiteralPath $ExitPath) { $server.Dispose(); break }
            $server.EndWaitForConnection($pending)
            $reader=New-Object IO.StreamReader($server,$utf8,$false,4096,$true);$line=$reader.ReadLine()
            try { if (-not $line -or $utf8.GetByteCount($line) -gt 1048576) { throw 'Bad request' };$request=$line|ConvertFrom-Json -ErrorAction Stop;if($TaskId){$request.taskId=$TaskId};if($ParentTaskId){$request.parentTaskId=$ParentTaskId};if($AccountingDirectory){$request.accountingDirectory=$AccountingDirectory};$response=Invoke-CoordinatorTurn $runtime $session $path $request }
            catch { $response=@{status='Rejected';message=$_.Exception.Message} }
            $writer=New-Object IO.StreamWriter($server,$utf8,4096,$true);$writer.AutoFlush=$true;$writer.WriteLine((ConvertTo-Json -InputObject $response -Depth 20 -Compress));$writer.Dispose();$reader.Dispose();$server.Dispose()
        }
    } else {
        # Production host remains resident; callers use the single local dispatcher.
        Start-CoordinatorPipe @{PipeName=$PipeName;StopRequested=$false} { param($request) if($TaskId){$request.taskId=$TaskId};if($ParentTaskId){$request.parentTaskId=$ParentTaskId};if($AccountingDirectory){$request.accountingDirectory=$AccountingDirectory};Invoke-CoordinatorTurn $runtime $session $path $request }
    }
} catch {
    if ($_.Exception.Message -eq 'DuplicateHost') { Write-Error 'DuplicateHost'; exit 10 }
    Write-Error $_.Exception.Message
    if ($TestMode) { exit 1 }
    while ($true) { Start-Sleep -Seconds 60 }
} finally {
    if ($runtime -and $runtime.Owned) {
        $ended=$false
        try {
            if ($runtime.JobHandle -and $runtime.JobHandle -ne [IntPtr]::Zero) { $handleClosed=[CoordinatorRuntimeJob]::CloseHandle($runtime.JobHandle); if ($handleClosed) { $runtime.JobHandle=[IntPtr]::Zero } else { Write-Warning 'Runtime job handle close was not confirmed; observing the child process directly.' } }
            if (-not $runtime.Process.HasExited) {
                try { $runtime.Input.Close() } catch { }
                $ended=[bool]$runtime.Process.WaitForExit(5000) -and [bool]$runtime.Process.HasExited
            } else { $ended=[bool]$runtime.Process.HasExited }
        } catch { $ended=$false }
        if ($ended -and $runtimePid -and $runtimeStartedAtUtc -and $owner) {
            try {
                $saved=Read-CoordinatorSession $owner.SessionPath
                if ([int]$saved.RuntimePid -eq [int]$runtimePid -and [string]$saved.RuntimeStartedAtUtc -ceq [string]$runtimeStartedAtUtc) {
                    $saved.RuntimePid=$null; $saved.RuntimeStartedAtUtc=$null; Write-CoordinatorAtomicJson $owner.SessionPath $saved
                }
            } catch { Write-Warning ('Confirmed runtime exit but persisted owner binding could not be cleared: '+$_.Exception.Message) }
        }
        if ($runtime.Process) { $runtime.Process.Dispose() }
    }
    if ($activation) { try { $activation.ReleaseMutex() } catch { }; $activation.Dispose() }
    if ($owner) { try { Exit-CoordinatorOwnership $owner } catch { Write-Warning ('Store lock release failed: '+$_.Exception.Message) } }
}
