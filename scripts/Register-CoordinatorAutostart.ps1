[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)][string]$DataDirectory,
    [Parameter(Mandatory=$true)][string]$WorkingDirectory,
    [Parameter(Mandatory=$true)][string]$RuntimeExecutable,
    [string]$CodexHome=(Join-Path $env:USERPROFILE '.codex'),
    [string]$AccountingDirectory,
    [string]$TaskName='AgentOrganization-Coordinator',
    [string]$ExportPath=(Join-Path $PSScriptRoot '..\CoordinatorAutostart.xml'),
    [switch]$RegisterTask
)
<#
.SYNOPSIS
Prepares the per-user coordinator logon task definition; optionally registers it.
.DESCRIPTION
By default this only exports the scheduled-task XML and does not register or start anything.
Pass -RegisterTask to explicitly register. An existing task with the selected name is never replaced.
.PARAMETER DataDirectory
Absolute persistent state directory used by every coordinator start.
.PARAMETER WorkingDirectory
Absolute runtime working directory.
.PARAMETER RuntimeExecutable
Absolute Codex runtime executable path.
.PARAMETER CodexHome
Fixed CODEX_HOME path.
.PARAMETER AccountingDirectory
Optional accounting ledger path.
.PARAMETER TaskName
Per-user scheduled task name.
.PARAMETER ExportPath
Destination for the concrete task definition XML.
.PARAMETER RegisterTask
Explicitly register the prepared task; this switch does not start it.
.NOTES
InteractiveToken at user logon, least privilege, IgnoreNew, and no scheduler restart chain.
#>
$ErrorActionPreference='Stop'
$scriptPath=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot 'Start-CoordinatorConsole.ps1'))
$DataDirectory=[IO.Path]::GetFullPath($DataDirectory)
$WorkingDirectory=[IO.Path]::GetFullPath($WorkingDirectory)
$RuntimeExecutable=[IO.Path]::GetFullPath($RuntimeExecutable)
$CodexHome=[IO.Path]::GetFullPath($CodexHome)
$powershell=[IO.Path]::GetFullPath((Join-Path $env:WINDIR 'System32\WindowsPowerShell\v1.0\powershell.exe'))
$argList=@('-NoProfile','-ExecutionPolicy','Bypass','-File',('"'+$scriptPath+'"'),'-DataDirectory',('"'+$DataDirectory+'"'),'-WorkingDirectory',('"'+$WorkingDirectory+'"'),'-RuntimeExecutable',('"'+$RuntimeExecutable+'"'),'-CodexHome',('"'+$CodexHome+'"'))
if ($AccountingDirectory) { $AccountingDirectory=[IO.Path]::GetFullPath($AccountingDirectory); $argList+=@('-AccountingDirectory',('"'+$AccountingDirectory+'"')) }
$action=New-ScheduledTaskAction -Execute $powershell -Argument ($argList -join ' ') -WorkingDirectory $WorkingDirectory
$trigger=New-ScheduledTaskTrigger -AtLogOn -User ([Security.Principal.WindowsIdentity]::GetCurrent().Name)
$principal=New-ScheduledTaskPrincipal -UserId ([Security.Principal.WindowsIdentity]::GetCurrent().Name) -LogonType Interactive -RunLevel Limited
$settings=New-ScheduledTaskSettingsSet -MultipleInstances IgnoreNew -ExecutionTimeLimit ([TimeSpan]::Zero) -StartWhenAvailable
$definition=New-ScheduledTask -Action $action -Trigger $trigger -Principal $principal -Settings $settings -Description 'Visible per-user coordinator console and bounded supervisor.'
$ExportPath=[IO.Path]::GetFullPath($ExportPath)
$exportDirectory=Split-Path -Parent $ExportPath
if (-not (Test-Path -LiteralPath $exportDirectory)) { New-Item -ItemType Directory -Path $exportDirectory -Force | Out-Null }
Export-ScheduledTask -InputObject $definition | Set-Content -LiteralPath $ExportPath -Encoding Unicode
if ($RegisterTask) {
    if (Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue) { throw "Task '$TaskName' already exists; it was not changed." }
    Register-ScheduledTask -TaskName $TaskName -InputObject $definition -ErrorAction Stop | Out-Null
}
[pscustomobject]@{TaskName=$TaskName;ExportPath=$ExportPath;Registered=[bool]$RegisterTask;Started=$false;Action=$action;Trigger=$trigger;Principal=$principal;Settings=$settings}
