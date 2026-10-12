[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)][string]$DataDirectory,
    [Parameter(Mandatory=$true)][string]$WorkingDirectory,
    [Parameter(Mandatory=$true)][string]$RuntimeExecutable,
    [string]$CodexHome=(Join-Path $env:USERPROFILE '.codex'),
    [string]$TaskId,
    [string]$ParentTaskId,
    [string]$AccountingDirectory
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
.NOTES
This script does not register or start a scheduled task. Start it in the confirmed visible Koordinator console.
#>
$ErrorActionPreference='Stop'
$Host.UI.RawUI.WindowTitle='Koordinator'
$DataDirectory=[IO.Path]::GetFullPath($DataDirectory)
$WorkingDirectory=[IO.Path]::GetFullPath($WorkingDirectory)
$RuntimeExecutable=[IO.Path]::GetFullPath($RuntimeExecutable)
$CodexHome=[IO.Path]::GetFullPath($CodexHome)
$env:CODEX_HOME=$CodexHome
$context=$null
if ($TaskId -or $ParentTaskId) { $context=[pscustomobject]@{TaskId=$TaskId;ParentTaskId=$ParentTaskId} }
$supervisorPath=Join-Path $PSScriptRoot 'coordinator/CoordinatorSupervisor.psm1'
try {
    if (-not (Test-Path -LiteralPath $supervisorPath -PathType Leaf)) { throw "Coordinator supervisor module is not available: $supervisorPath" }
    Import-Module $supervisorPath -Force
    $result=Invoke-CoordinatorSupervisor -DataDirectory $DataDirectory -WorkingDirectory $WorkingDirectory -RuntimeExecutable $RuntimeExecutable -CodexHome $CodexHome -TaskContext $context -AccountingDirectory $AccountingDirectory
    Write-Host 'Koordinator-Aufsicht beendet.'
    if ($result) { $result | Format-List * }
} catch { Write-Error -ErrorRecord $_ -ErrorAction Continue }
finally { $Host.UI.RawUI.WindowTitle='Koordinator' }
while ($true) {
    try { [void](Read-Host 'Koordinator-Konsole bleibt offen; Enter zum Anzeigen des Status, Strg+C zum Beenden') } catch { Start-Sleep -Seconds 1 }
    Write-Host ('Status: Supervisor-Aufruf beendet. Zeit: ' + [DateTime]::Now.ToString('yyyy-MM-dd HH:mm:ss'))
}
