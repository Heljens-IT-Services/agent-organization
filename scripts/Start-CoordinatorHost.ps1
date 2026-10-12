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
    [Parameter(Mandatory=$true)][string]$CoordinatorJobPath,
    [Parameter(Mandatory=$true)][string]$CoordinatorJobHash,
    [Parameter(Mandatory=$true)][string]$CoordinatorLaunchConfigPath,
    [Parameter(Mandatory=$true)][string]$CoordinatorLaunchConfigHash,
    [string]$WorkItemStorePath,
    [string]$EventJournalPath,
    [string[]]$ResultDirectories,
    [string]$RegistryDirectory,
    [string]$NativeInventoryPath,
    [string]$CompleteEpoch,
    [ValidateRange(1,100)][int]$AutomationCapacity=4,
    [ValidateRange(1,100)][int]$ResumeRetryLimit=3,
    [ValidateRange(100,60000)][int]$RpcTimeoutMilliseconds=15000,
    [string[]]$RuntimeArguments,
    [string]$PinnedRuntimeExecutable,
    [string]$PinnedCodexHome,
    [string]$PinnedDataDirectory,
    [string]$PinnedWorkingDirectory,
    [int]$PinnedCapacity,
    [string]$PinnedAccountingDirectory,
    [string]$WorkingDirectory=(Get-Location).Path
)
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'coordinator\Lifecycle.Persistence.ps1')
$utf8=New-Object System.Text.UTF8Encoding($false,$true)
Import-Module (Join-Path $PSScriptRoot 'coordinator/CoordinatorHost.Core.psm1') -Force
Import-Module (Join-Path $PSScriptRoot 'coordinator/CoordinatorAdmission.psm1')
$contextModule=Import-Module (Join-Path $PSScriptRoot 'workitems/CoordinatorExecutionContext.psm1') -PassThru -Force
$owner=$null; $runtime=$null; $activation=$null
$session=$null
$runtimePid=$null; $runtimeStartedAtUtc=$null
$hostOutcome=[pscustomobject]@{Classification='Running';RetryAllowed=$false;Reason=$null;CleanupConfirmed=$false}
try {
    $CoordinatorJobPath=[IO.Path]::GetFullPath($CoordinatorJobPath);$CoordinatorLaunchConfigPath=[IO.Path]::GetFullPath($CoordinatorLaunchConfigPath)
    $rootJob=& $contextModule {param($p)Read-ContextJson $p} $CoordinatorJobPath
    $launch=& $contextModule {param($p)Read-ContextJson $p} $CoordinatorLaunchConfigPath
    if(-not $TaskId -or $rootJob.role -cne 'koordinator' -or $rootJob.parent_task_id -or $rootJob.parent_job_path -or $rootJob.work_item_id -or $rootJob.execution_id -or $rootJob.work_item_request_path -or $rootJob.task_id -cne $TaskId -or (& $contextModule {param($j)Get-ExecutionJobHash $j} $rootJob) -cne $CoordinatorJobHash -or $rootJob.coordinator_launch.inputPath -cne $CoordinatorLaunchConfigPath -or $rootJob.coordinator_launch.inputHash -cne $CoordinatorLaunchConfigHash -or (& $contextModule {param($b)Get-ContextHash $b} ([IO.File]::ReadAllBytes($CoordinatorLaunchConfigPath))) -cne $CoordinatorLaunchConfigHash){throw 'BlockedRecovery: root ownership or launch input mismatch.'}
    if(-not $AccountingDirectory -or [IO.Path]::GetFullPath($AccountingDirectory) -cne [IO.Path]::GetFullPath($rootJob.accounting_directory) -or [IO.Path]::GetFullPath($WorkingDirectory) -cne [IO.Path]::GetFullPath($rootJob.cwd) -or [IO.Path]::GetFullPath($rootJob.coordinator_launch.dataDirectory) -cne [IO.Path]::GetFullPath($DataDirectory) -or [int]$rootJob.coordinator_launch.capacity -ne [int]$rootJob.admission_capacity){throw 'BlockedRecovery: root job accounting/CWD/data/capacity mismatch.'}
    if(-not $PinnedDataDirectory -or [IO.Path]::GetFullPath($PinnedDataDirectory) -cne [IO.Path]::GetFullPath($DataDirectory) -or [IO.Path]::GetFullPath($PinnedWorkingDirectory) -cne [IO.Path]::GetFullPath($WorkingDirectory) -or [int]$PinnedCapacity -ne [int]$rootJob.admission_capacity -or [IO.Path]::GetFullPath($PinnedAccountingDirectory) -cne [IO.Path]::GetFullPath($AccountingDirectory) -or [IO.Path]::GetFullPath($PinnedRuntimeExecutable) -cne [IO.Path]::GetFullPath($launch.runtimeExecutable) -or [IO.Path]::GetFullPath($PinnedCodexHome) -cne [IO.Path]::GetFullPath($launch.codexHome) -or (ConvertTo-Json -InputObject @($RuntimeArguments) -Compress) -cne (ConvertTo-Json -InputObject @($launch.runtimeArguments) -Compress)){throw 'BlockedRecovery: supervisor root launch group differs from pinned launch input.'}
    $WorkItemStorePath=[IO.Path]::GetFullPath($launch.workItemStorePath);$EventJournalPath=[IO.Path]::GetFullPath($launch.eventJournalPath);$RegistryDirectory=[IO.Path]::GetFullPath($launch.registryDirectory);$ResultDirectories=@($launch.resultDirectories|ForEach-Object{[IO.Path]::GetFullPath($_)});$NativeInventoryPath=$launch.nativeInventoryPath;$CompleteEpoch=$launch.completeEpoch;$AutomationCapacity=[int]$rootJob.admission_capacity
    if([IO.Path]::GetFullPath($WorkItemStorePath) -cne [IO.Path]::GetFullPath($launch.workItemStorePath) -or [IO.Path]::GetFullPath($EventJournalPath) -cne [IO.Path]::GetFullPath($launch.eventJournalPath) -or [IO.Path]::GetFullPath($RegistryDirectory) -cne [IO.Path]::GetFullPath($launch.registryDirectory) -or (ConvertTo-Json -InputObject @($ResultDirectories|ForEach-Object{[IO.Path]::GetFullPath($_)}) -Compress) -cne (ConvertTo-Json -InputObject @($launch.resultDirectories|ForEach-Object{[IO.Path]::GetFullPath($_)}) -Compress) -or [string]$NativeInventoryPath -cne [string]$launch.nativeInventoryPath -or [string]$CompleteEpoch -cne [string]$launch.completeEpoch){throw 'BlockedRecovery: supervisor technical launch roots differ from pinned launch input.'}
    if(-not (Test-Path -LiteralPath $WorkItemStorePath -PathType Leaf) -or -not (Test-Path -LiteralPath $EventJournalPath -PathType Leaf) -or -not $ResultDirectories.Count -or -not $AutomationCapacity){throw 'BlockedRecovery: explicit root store/event/result/capacity binding incomplete.'}
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
        $session=[pscustomobject]@{SchemaVersion=1;LogicalSessionId=[guid]::NewGuid().ToString('N');NativeThreadId=$null;State='BlockedRecovery';Revision=0;LastRequestId=$null;LastTurnId=$null;LastOutcome=$null;LastError='Controlled first handoff required';ResumeAttempts=0;RequestHistory=@();LastUsage=$null;AccountingError=$null;RuntimePid=$null;RuntimeStartedAtUtc=$null;Cwd=[IO.Path]::GetFullPath($WorkingDirectory);RuntimeExecutable=$null;CodexHome=$null;HistoryBase=$null;AllowProvisioning=[bool]$TestMode;OwnerPid=$PID;OwnerStartedUtc=$owner.OwnerStartedUtc;RootTaskId=$rootJob.task_id;CoordinatorJobPath=$CoordinatorJobPath;CoordinatorJobHash=$CoordinatorJobHash;CoordinatorLaunchConfigPath=$CoordinatorLaunchConfigPath;CoordinatorLaunchConfigHash=$CoordinatorLaunchConfigHash;StorePath=$WorkItemStorePath;AccountingDirectory=[IO.Path]::GetFullPath($AccountingDirectory);EventJournalPath=$EventJournalPath;RegistryDirectory=$RegistryDirectory;ResultDirectories=@($ResultDirectories);NativeInventoryPath=$NativeInventoryPath;CompleteEpoch=$CompleteEpoch;AutomationCapacity=$AutomationCapacity;RuntimeArguments=@($launch.runtimeArguments);CreatedAtUtc=[DateTime]::UtcNow.ToString('o')}
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
    $admissionPolicy=Get-AdmissionField $launch 'admissionPolicy'
    $scanBudgetMilliseconds=[int](Get-AdmissionField $admissionPolicy 'scanBudgetMilliseconds' 10000)
    if((Get-AdmissionField $admissionPolicy 'snapshotReuse' $false) -ne $false -or $scanBudgetMilliseconds -le 0){throw 'BlockedRecovery: Admission policy invalid.'}
    $jobPolicy=Get-AdmissionField $rootJob.coordinator_launch 'admissionPolicy'
    $runtimeBinding=Get-AdmissionField $rootJob.coordinator_launch 'runtimeBinding'
    if(-not $jobPolicy -or $jobPolicy.snapshotReuse -ne $false -or [int]$jobPolicy.scanBudgetMilliseconds -ne $scanBudgetMilliseconds -or -not $runtimeBinding -or $runtimeBinding.executable -cne $launch.runtimeExecutable -or $runtimeBinding.codexHome -cne $launch.codexHome -or (Get-AdmissionObjectHash @($runtimeBinding.arguments)) -cne (Get-AdmissionObjectHash @($launch.runtimeArguments)) -or (Get-AdmissionHash ([IO.File]::ReadAllBytes($launch.runtimeExecutable))) -cne $runtimeBinding.executableHash){throw 'BlockedRecovery: Admission policy/runtime source group changed.'}
    if((Get-AdmissionHash ([IO.File]::ReadAllBytes((Join-Path $PSScriptRoot 'coordinator/AdmissionInstalledContract.json')))) -cne $runtimeBinding.sourceContractHash){throw 'BlockedRecovery: Installed CLI source contract group changed.'}
    $runtimeConfig=@{RuntimeExecutable=$launch.runtimeExecutable;RuntimeArguments=@($launch.runtimeArguments);WorkingDirectory=[IO.Path]::GetFullPath($rootJob.cwd);CodexHome=[IO.Path]::GetFullPath($launch.codexHome);AdmissionPolicy=@{snapshotReuse=$false;scanBudgetMilliseconds=$scanBudgetMilliseconds};ContextJobPath=$CoordinatorJobPath;ContextStorePath=$WorkItemStorePath;ContextDirectory=(Join-Path $owner.DataDirectory 'contexts')}
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
    $effectiveHome=[IO.Path]::GetFullPath($launch.codexHome)
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
    foreach($pair in @(@('RootTaskId',$rootJob.task_id),@('CoordinatorJobPath',$CoordinatorJobPath),@('CoordinatorJobHash',$CoordinatorJobHash),@('CoordinatorLaunchConfigPath',$CoordinatorLaunchConfigPath),@('CoordinatorLaunchConfigHash',$CoordinatorLaunchConfigHash),@('StorePath',$WorkItemStorePath),@('AccountingDirectory',[IO.Path]::GetFullPath($AccountingDirectory)),@('EventJournalPath',$EventJournalPath),@('RegistryDirectory',$RegistryDirectory),@('NativeInventoryPath',$NativeInventoryPath),@('CompleteEpoch',$CompleteEpoch),@('AutomationCapacity',$AutomationCapacity),@('ResultDirectories',@($ResultDirectories)),@('RuntimeArguments',@($launch.runtimeArguments)))){if($session.PSObject.Properties[$pair[0]] -and $null -ne $session.($pair[0]) -and (ConvertTo-Json -InputObject $session.($pair[0]) -Depth 10 -Compress) -cne (ConvertTo-Json -InputObject $pair[1] -Depth 10 -Compress)){throw 'BlockedRecovery: persisted root session group changed.'};$session|Add-Member -NotePropertyName $pair[0] -NotePropertyValue $pair[1] -Force}
    $runtimeConfig.RuntimeExecutable=$effectiveExe; $runtimeConfig.WorkingDirectory=$effectiveCwd
    if(-not $EventJournalPath){$EventJournalPath=Join-Path $owner.DataDirectory 'events.store.json'}
    if(-not $WorkItemStorePath){$WorkItemStorePath=Join-Path (Split-Path -Parent $PSScriptRoot) 'runtime/workitems.json'}
    if(-not $RegistryDirectory){$RegistryDirectory=$owner.DataDirectory}
    if(-not $ResultDirectories){$ResultDirectories=@()}
    Import-Module (Join-Path $PSScriptRoot 'coordinator/CoordinatorEvents.psm1') -Force
    Import-Module (Join-Path $PSScriptRoot 'coordinator/CoordinatorAutomation.psm1') -Force
    if(-not (Test-Path -LiteralPath $EventJournalPath -PathType Leaf)){[void][IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName([IO.Path]::GetFullPath($EventJournalPath)));[IO.File]::WriteAllText($EventJournalPath,'{"schemaVersion":"1.0","events":[]}',$utf8)}
    $runtime=Start-CoordinatorRuntime $runtimeConfig
    $runtime | Add-Member -MemberType NoteProperty -Name ResumeRetryLimit -Value $ResumeRetryLimit -Force
    $runtime | Add-Member -MemberType NoteProperty -Name RpcTimeoutMilliseconds -Value $RpcTimeoutMilliseconds -Force
    $runtime | Add-Member -MemberType NoteProperty -Name TurnTimeoutMilliseconds -Value 600000 -Force
    if ($runtime.Process) { $runtimePid=$runtime.Process.Id; $runtimeStartedAtUtc=$runtime.StartedAtUtc; $session.RuntimePid=$runtimePid; $session.RuntimeStartedAtUtc=$runtimeStartedAtUtc;Write-CoordinatorAtomicJson $path $session }
    try { $session=Initialize-CoordinatorRuntime $runtime $session $path $CoordinatorJobPath $CoordinatorJobHash $CoordinatorLaunchConfigHash } catch { $session.State='BlockedRecovery';$session.LastError=$_.Exception.Message;Write-CoordinatorAtomicJson $path $session; throw }
    $initialRequestId='mainstarter:'+$rootJob.task_id+':'+$CoordinatorJobHash
    $initialHistory=@((Get-CoordinatorHistory $session)|Where-Object{$_.requestId -ceq $initialRequestId})
    if(-not $initialHistory.Count){
        if([string]::IsNullOrWhiteSpace([string]$rootJob.task)){throw 'BlockedRecovery: root mainstarter task is empty.'}
        $initialInput=([string]$rootJob.task+"`n`n"+[string]$rootJob.context).Trim()
        $initialReply=Invoke-CoordinatorTurn $runtime $session $path ([pscustomobject]@{operation='SubmitInput';source='mainstarter';logicalSessionId=$session.LogicalSessionId;requestId=$initialRequestId;inputText=$initialInput;taskId=$rootJob.task_id;accountingDirectory=$rootJob.accounting_directory})
        if($initialReply.status -ne 'Accepted'){throw 'BlockedRecovery: actual root mainstarter turn is not terminal-successful.'}
    } elseif($initialHistory[0].outcome -notin @('completed','Completed')){throw 'BlockedRecovery: root mainstarter turn history is unresolved.'}
    foreach($entry in @($session.RequestHistory)){if((Get-CoordinatorConfigValue $entry 'effectMode') -ne 'coordinator-effects-v1' -and $entry.outcome -in @('completed','failed','interrupted') -and (Get-CoordinatorConfigValue $entry 'decision')){Set-LCValue $entry 'archiveReady' $true}}
    Write-CoordinatorAtomicJson $path $session
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
        $rootCompleted=@((Get-CoordinatorHistory $session)|Where-Object{$_.terminalContextPath -and $_.outcome -eq 'completed'}|Select-Object -Last 1)
        $automationConfig=[pscustomobject]@{EventJournalPath=[IO.Path]::GetFullPath($EventJournalPath);DataDirectory=$owner.DataDirectory;WorkItemStorePath=[IO.Path]::GetFullPath($WorkItemStorePath);RepositoryRoot=[IO.Path]::GetFullPath((Split-Path -Parent $PSScriptRoot));AccountingDirectory=$AccountingDirectory;ParentTaskId=$rootJob.task_id;TaskId=$rootJob.task_id;ParentJobPath=$CoordinatorJobPath;CoordinatorJobHash=$CoordinatorJobHash;ParentContextPath=$(if($rootCompleted.Count){$rootCompleted[0].terminalContextPath}else{$null});ParentContextHash=$(if($rootCompleted.Count){$rootCompleted[0].terminalContextHash}else{$null});WorkingDirectory=$effectiveCwd;ResultDirectories=@($ResultDirectories|ForEach-Object{[IO.Path]::GetFullPath($_)});RegistryDirectory=[IO.Path]::GetFullPath($RegistryDirectory);Capacity=$AutomationCapacity;NativeInventoryPath=$NativeInventoryPath;CompleteEpoch=$CompleteEpoch;AdmissionPolicy=$runtimeConfig.AdmissionPolicy;RuntimeConfig=$runtimeConfig;RetryBaseSeconds=$(if($launch.PSObject.Properties['retryBaseSeconds']){[int]$launch.retryBaseSeconds}else{5});RetryCeilingSeconds=$(if($launch.PSObject.Properties['retryCeilingSeconds']){[int]$launch.retryCeilingSeconds}else{3600});RetryAttemptCeiling=$(if($launch.PSObject.Properties['retryAttemptCeiling']){[int]$launch.retryAttemptCeiling}else{256});EventBatchLimit=$(if($launch.PSObject.Properties['eventBatchLimit']){[int]$launch.eventBatchLimit}else{256})}
        Start-CoordinatorPipe @{PipeName=$PipeName;StopRequested=$false;RuntimeProcess=$runtime.Process} { param($request) if($TaskId){$request.taskId=$TaskId};if($ParentTaskId){$request.parentTaskId=$ParentTaskId};if($AccountingDirectory){$request.accountingDirectory=$AccountingDirectory};Invoke-CoordinatorTurn $runtime $session $path $request } { Invoke-CoordinatorAutomationIdle $automationConfig $runtime $session $path }
    }
} catch {
    $reason=$_.Exception.Message
    $classification=if($reason -eq 'DuplicateHost'){'DuplicateHost'}elseif($reason -like 'RetryableRuntimeExit:*' -and $session -and $session.State -eq 'RecoveryUnknown'){'BlockedUnknownTurn'}elseif($reason -like 'RetryableRuntimeExit:*' -or $reason -like 'Unavailable:*'){'RetryableRuntimeExit'}elseif($reason -like 'RecoveryUnknown:*'){'BlockedUnknownTurn'}elseif($reason -like 'BlockedRecovery:*'){'BlockedRecovery'}else{'Fatal'}
    $hostOutcome=[pscustomobject]@{Classification=$classification;RetryAllowed=($classification -eq 'RetryableRuntimeExit');Reason=$reason;CleanupConfirmed=$false}
} finally {
    $cleanupConfirmed=$true
    if ($runtime -and $runtime.Owned) {
        $ended=$false
        try {
            if ($runtime.JobHandle -and $runtime.JobHandle -ne [IntPtr]::Zero) { $handleClosed=[CoordinatorRuntimeJob]::CloseHandle($runtime.JobHandle); if ($handleClosed) { $runtime.JobHandle=[IntPtr]::Zero } else { Write-Warning 'Runtime job handle close was not confirmed; observing the child process directly.' } }
            if (-not $runtime.Process.HasExited) {
                try { $runtime.Input.Close() } catch { }
                $ended=[bool]$runtime.Process.WaitForExit(5000) -and [bool]$runtime.Process.HasExited
            } else { $ended=[bool]$runtime.Process.HasExited }
        } catch { $ended=$false }
        if (-not $ended) { $cleanupConfirmed=$false }
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
    if ($activation) { try { $activation.ReleaseMutex() } catch { $cleanupConfirmed=$false }; try { $activation.Dispose() } catch { $cleanupConfirmed=$false } }
    if ($owner) { try { Exit-CoordinatorOwnership $owner } catch { $cleanupConfirmed=$false; Write-Warning ('Store lock release failed: '+$_.Exception.Message) } }
    if ($hostOutcome.Classification -eq 'Running') { $hostOutcome.Classification='Stopped'; $hostOutcome.RetryAllowed=$false; $hostOutcome.Reason='Host stopped normally.' }
    $hostOutcome.CleanupConfirmed=[bool]$cleanupConfirmed
    if (-not $cleanupConfirmed) { $hostOutcome.Classification='BlockedCleanup'; $hostOutcome.RetryAllowed=$false; $hostOutcome.Reason='Host cleanup or runtime termination was not confirmed.' }
}
$hostOutcome
