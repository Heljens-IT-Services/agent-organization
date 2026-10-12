Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$script:Utf8 = New-Object System.Text.UTF8Encoding($false,$true)

function Invoke-CoordinatorSupervisor {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][string]$DataDirectory,
        [Parameter(Mandatory=$true)][string]$WorkingDirectory,
        [Parameter(Mandatory=$true)][string]$RuntimeExecutable,
        [Parameter(Mandatory=$true)][string]$CodexHome,
        [object]$TaskContext,
        [string]$AccountingDirectory
    )
    $data=[IO.Path]::GetFullPath($DataDirectory)
    if (-not [IO.Path]::IsPathRooted($DataDirectory)) { throw 'DataDirectory must be absolute.' }
    [void][IO.Directory]::CreateDirectory($data)
    $identity=[Security.Principal.WindowsIdentity]::GetCurrent().User.Value
    $hash=[Convert]::ToBase64String([Security.Cryptography.SHA256]::Create().ComputeHash([Text.Encoding]::UTF8.GetBytes($data.ToUpperInvariant()+'|'+$identity))).TrimEnd('=').Replace('+','_').Replace('/','_')
    $mutex=New-Object Threading.Mutex($false,'Local\AgentOrganization.CoordinatorSupervisor.'+$hash)
    if (-not $mutex.WaitOne(0)) { $mutex.Dispose(); return [pscustomobject]@{State='Blocked';Reason='Another supervisor owns this DataDirectory and user.';Attempts=0} }
    $statePath=Join-Path $data 'supervisor.json'
    $state=[pscustomobject]@{SchemaVersion=1;RetryCount=0;LastError=$null;LastClassification=$null;UpdatedAtUtc=[DateTime]::UtcNow.ToString('o')}
    try {
        if ([IO.File]::Exists($statePath)) {
            try { $state=[IO.File]::ReadAllText($statePath,$script:Utf8)|ConvertFrom-Json -ErrorAction Stop }
            catch { return [pscustomobject]@{State='Blocked';Reason='Supervisor state is unreadable; retry budget cannot be trusted.';Attempts=0} }
            if ($state.SchemaVersion -ne 1 -or $null -eq $state.RetryCount -or $state.RetryCount -lt 0 -or $state.RetryCount -gt 3) { return [pscustomobject]@{State='Blocked';Reason='Supervisor state is invalid; retry budget cannot be trusted.';Attempts=0} }
        }
        $humanRestart=$TaskContext -and $TaskContext.PSObject.Properties['RestartRequestedByHuman'] -and [bool]$TaskContext.RestartRequestedByHuman
        if ($humanRestart) {
            $state.RetryCount=0; $state.LastError=$null; $state.LastClassification='HumanRestart'; $state.UpdatedAtUtc=[DateTime]::UtcNow.ToString('o')
            $resetTmp=$statePath+'.'+[guid]::NewGuid().ToString('N')+'.writing'
            [IO.File]::WriteAllText($resetTmp,(ConvertTo-Json -InputObject $state -Depth 10 -Compress),$script:Utf8)
            if ([IO.File]::Exists($statePath)) { $backup=$resetTmp+'.bak'; [IO.File]::Replace($resetTmp,$statePath,$backup); [IO.File]::Delete($backup) } else { [IO.File]::Move($resetTmp,$statePath) }
        }
        $hostPath=Join-Path (Split-Path -Parent $PSScriptRoot) 'Start-CoordinatorHost.ps1'
        $delays=@(5,15,30)
        while ($true) {
            if ([int]$state.RetryCount -ge 3) { return [pscustomobject]@{State='Blocked';Reason='Restart budget exhausted. Human restart required.';Classification=$state.LastClassification;Attempts=$state.RetryCount} }
            $started=[DateTime]::UtcNow
            $priorHome=$env:CODEX_HOME
            try {
                $env:CODEX_HOME=[IO.Path]::GetFullPath($CodexHome)
                $hostParameters=@{DataDirectory=$data;WorkingDirectory=[IO.Path]::GetFullPath($WorkingDirectory);RuntimeExecutable=[IO.Path]::GetFullPath($RuntimeExecutable)}
                if ($AccountingDirectory) { $hostParameters.AccountingDirectory=[IO.Path]::GetFullPath($AccountingDirectory) }
                if ($TaskContext) {
                    foreach ($name in @('TaskId','ParentTaskId','PipeName','ResumeRetryLimit','RpcTimeoutMilliseconds')) {
                        $property=$TaskContext.PSObject.Properties[$name]
                        if ($property -and $null -ne $property.Value) { $hostParameters[$name]=$property.Value }
                    }
                }
                $outcome=& $hostPath @hostParameters
            } catch { $outcome=[pscustomobject]@{Classification='Fatal';RetryAllowed=$false;Reason=$_.Exception.Message;CleanupConfirmed=$false} }
            finally { $env:CODEX_HOME=$priorHome }
            $state.LastError=[string]$outcome.Reason; $state.LastClassification=[string]$outcome.Classification; $state.UpdatedAtUtc=[DateTime]::UtcNow.ToString('o')
            $tmp=$statePath+'.'+[guid]::NewGuid().ToString('N')+'.writing'
            [IO.File]::WriteAllText($tmp,(ConvertTo-Json -InputObject $state -Depth 10 -Compress),$script:Utf8)
            if ([IO.File]::Exists($statePath)) { $backup=$tmp+'.bak'; [IO.File]::Replace($tmp,$statePath,$backup); [IO.File]::Delete($backup) } else { [IO.File]::Move($tmp,$statePath) }
            if ($outcome.Classification -in @('DuplicateHost','BlockedUnknownTurn','BlockedRecovery','BlockedCleanup','Fatal') -or -not $outcome.CleanupConfirmed) { return [pscustomobject]@{State='Blocked';Reason=$state.LastError;Classification=$state.LastClassification;Attempts=$state.RetryCount} }
            if (-not $outcome.RetryAllowed) { return [pscustomobject]@{State='Stopped';Reason=$state.LastError;Classification=$state.LastClassification;Attempts=$state.RetryCount} }
            if ($state.RetryCount -ge 3) { return [pscustomobject]@{State='Blocked';Reason='Restart budget exhausted. Human restart required.';Classification=$state.LastClassification;Attempts=$state.RetryCount} }
            $delay=$delays[[int]$state.RetryCount]
            $state.RetryCount=[int]$state.RetryCount+1
            $state.UpdatedAtUtc=[DateTime]::UtcNow.ToString('o')
            $tmp=$statePath+'.'+[guid]::NewGuid().ToString('N')+'.writing'
            [IO.File]::WriteAllText($tmp,(ConvertTo-Json -InputObject $state -Depth 10 -Compress),$script:Utf8)
            if ([IO.File]::Exists($statePath)) { $backup=$tmp+'.bak'; [IO.File]::Replace($tmp,$statePath,$backup); [IO.File]::Delete($backup) } else { [IO.File]::Move($tmp,$statePath) }
            Start-Sleep -Seconds $delay
        }
    } finally { try { $mutex.ReleaseMutex() } catch {}; $mutex.Dispose() }
}

Export-ModuleMember -Function Invoke-CoordinatorSupervisor
