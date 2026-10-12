[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)][string]$DataDirectory,
    [Parameter(Mandatory=$true)][string]$WorkingDirectory,
    [Parameter(Mandatory=$true)][string]$RuntimeExecutable,
    [string]$CodexHome,
    [string]$TaskId,
    [string]$ParentTaskId,
    [string]$AccountingDirectory,
    [string]$CoordinatorJobPath,
    [string]$CoordinatorJobHash,
    [string]$CoordinatorLaunchConfigPath,
    [string]$CoordinatorLaunchConfigHash,
    [string]$WorkItemStorePath,
    [string]$EventJournalPath,
    [string[]]$ResultDirectories,
    [string]$RegistryDirectory,
    [string[]]$RuntimeArguments,
    [string]$PinnedRuntimeExecutable,
    [string]$PinnedCodexHome,
    [string]$PinnedDataDirectory,
    [string]$PinnedWorkingDirectory,
    [int]$PinnedCapacity,
    [string]$PinnedAccountingDirectory,
    [switch]$RestartRequestedByHuman
)
<#
.SYNOPSIS
Starts the coordinator supervisor in this visible console.
.DESCRIPTION
The console remains available for inspection after supervisor completion or failure.
.PARAMETER DataDirectory
Persistent coordinator state directory; use the same value for every start.
.PARAMETER WorkingDirectory
Working directory bound to the coordinator runtime session.
.PARAMETER RuntimeExecutable
Absolute path to the Codex runtime executable.
.PARAMETER CodexHome
Fixed CODEX_HOME used by the runtime and session history.
.PARAMETER TaskId
Optional task accounting context from the confirmed coordinator runner.
.PARAMETER ParentTaskId
Optional parent task accounting context.
.PARAMETER AccountingDirectory
Optional accounting ledger directory.
.PARAMETER RestartRequestedByHuman
Explicitly requests the human-only reset of the supervisor restart budget.
.NOTES
This script does not register or start a scheduled task. Start it in the confirmed visible Koordinator console.
#>
$ErrorActionPreference='Stop'
$consoleTitleAvailable=$false
try {
    try { $Host.UI.RawUI.WindowTitle='Koordinator'; $consoleTitleAvailable=$true } catch { }
    $DataDirectory=[IO.Path]::GetFullPath($DataDirectory)
    $WorkingDirectory=[IO.Path]::GetFullPath($WorkingDirectory)
    $RuntimeExecutable=[IO.Path]::GetFullPath($RuntimeExecutable)
    if (-not $CodexHome) { $CodexHome=Join-Path $env:USERPROFILE '.codex' }
    $CodexHome=[IO.Path]::GetFullPath($CodexHome)
    $env:CODEX_HOME=$CodexHome
    $context=$null
    if ($TaskId -or $ParentTaskId -or $RestartRequestedByHuman -or $CoordinatorJobPath) {
        $context=[pscustomobject]@{TaskId=$TaskId;ParentTaskId=$ParentTaskId;RestartRequestedByHuman=[bool]$RestartRequestedByHuman;CoordinatorJobPath=$CoordinatorJobPath;CoordinatorJobHash=$CoordinatorJobHash;CoordinatorLaunchConfigPath=$CoordinatorLaunchConfigPath;CoordinatorLaunchConfigHash=$CoordinatorLaunchConfigHash;WorkItemStorePath=$WorkItemStorePath;EventJournalPath=$EventJournalPath;ResultDirectories=@($ResultDirectories);RegistryDirectory=$RegistryDirectory;RuntimeArguments=@($RuntimeArguments);PinnedRuntimeExecutable=$PinnedRuntimeExecutable;PinnedCodexHome=$PinnedCodexHome;PinnedDataDirectory=$PinnedDataDirectory;PinnedWorkingDirectory=$PinnedWorkingDirectory;PinnedCapacity=$PinnedCapacity;PinnedAccountingDirectory=$PinnedAccountingDirectory}
    }
    $supervisorPath=Join-Path $PSScriptRoot 'coordinator/CoordinatorSupervisor.psm1'
    if (-not (Test-Path -LiteralPath $supervisorPath -PathType Leaf)) { throw "Coordinator supervisor module is not available: $supervisorPath" }
    Import-Module $supervisorPath -Force
    $result=Invoke-CoordinatorSupervisor -DataDirectory $DataDirectory -WorkingDirectory $WorkingDirectory -RuntimeExecutable $RuntimeExecutable -CodexHome $CodexHome -TaskContext $context -AccountingDirectory $AccountingDirectory
    Write-Host 'Koordinator-Aufsicht beendet.'
    if ($result) { $result | Format-List * }
} catch { Write-Error -ErrorRecord $_ -ErrorAction Continue }
finally { if ($consoleTitleAvailable) { try { $Host.UI.RawUI.WindowTitle='Koordinator' } catch { } } }
while ($true) {
    try { [void](Read-Host 'Koordinator-Konsole bleibt offen; Enter zum Anzeigen des Status, Strg+C zum Beenden') } catch { Start-Sleep -Seconds 1 }
    Write-Host ('Status: Supervisor-Aufruf beendet. Zeit: ' + [DateTime]::Now.ToString('yyyy-MM-dd HH:mm:ss'))
}
