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
$taskNamespace='http://schemas.microsoft.com/windows/2004/02/mit/task'
function Add-TaskXmlElement {
    param([xml]$Document,[System.Xml.XmlNode]$Parent,[string]$Name,[string]$Value)
    $element=$Document.CreateElement($Name,$taskNamespace)
    if ($null -ne $Value) { $element.InnerText=$Value }
    [void]$Parent.AppendChild($element)
    return $element
}

$scriptPath=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot 'Start-CoordinatorConsole.ps1'))
$DataDirectory=[IO.Path]::GetFullPath($DataDirectory)
$WorkingDirectory=[IO.Path]::GetFullPath($WorkingDirectory)
$RuntimeExecutable=[IO.Path]::GetFullPath($RuntimeExecutable)
$CodexHome=[IO.Path]::GetFullPath($CodexHome)
$powershell=[IO.Path]::GetFullPath((Join-Path $env:WINDIR 'System32\WindowsPowerShell\v1.0\powershell.exe'))
$user=[Security.Principal.WindowsIdentity]::GetCurrent().Name
$argList=@('-NoProfile','-ExecutionPolicy','Bypass','-NoExit','-File',('"'+$scriptPath+'"'),'-DataDirectory',('"'+$DataDirectory+'"'),'-WorkingDirectory',('"'+$WorkingDirectory+'"'),'-RuntimeExecutable',('"'+$RuntimeExecutable+'"'),'-CodexHome',('"'+$CodexHome+'"'))
if ($AccountingDirectory) {
    $AccountingDirectory=[IO.Path]::GetFullPath($AccountingDirectory)
    $argList+=@('-AccountingDirectory',('"'+$AccountingDirectory+'"'))
}
$arguments=$argList -join ' '

# Build the unregistered Task Scheduler 1.2 definition directly as supported XML.
$document=New-Object System.Xml.XmlDocument
$document.AppendChild($document.CreateXmlDeclaration('1.0','UTF-16',$null)) | Out-Null
$task=$document.CreateElement('Task',$taskNamespace)
$task.SetAttribute('version','1.2')
$document.AppendChild($task) | Out-Null
$registration=Add-TaskXmlElement $document $task 'RegistrationInfo' $null
[void](Add-TaskXmlElement $document $registration 'Description' 'Visible per-user coordinator console and bounded supervisor.')
$triggers=Add-TaskXmlElement $document $task 'Triggers' $null
$logon=Add-TaskXmlElement $document $triggers 'LogonTrigger' $null
[void](Add-TaskXmlElement $document $logon 'Enabled' 'true')
[void](Add-TaskXmlElement $document $logon 'UserId' $user)
$principals=Add-TaskXmlElement $document $task 'Principals' $null
$principal=Add-TaskXmlElement $document $principals 'Principal' $null
$principal.SetAttribute('id','Author')
[void](Add-TaskXmlElement $document $principal 'UserId' $user)
[void](Add-TaskXmlElement $document $principal 'LogonType' 'InteractiveToken')
[void](Add-TaskXmlElement $document $principal 'RunLevel' 'LeastPrivilege')
$settings=Add-TaskXmlElement $document $task 'Settings' $null
[void](Add-TaskXmlElement $document $settings 'MultipleInstancesPolicy' 'IgnoreNew')
[void](Add-TaskXmlElement $document $settings 'DisallowStartIfOnBatteries' 'false')
[void](Add-TaskXmlElement $document $settings 'StopIfGoingOnBatteries' 'false')
[void](Add-TaskXmlElement $document $settings 'AllowHardTerminate' 'true')
[void](Add-TaskXmlElement $document $settings 'StartWhenAvailable' 'true')
[void](Add-TaskXmlElement $document $settings 'Enabled' 'true')
[void](Add-TaskXmlElement $document $settings 'Hidden' 'false')
[void](Add-TaskXmlElement $document $settings 'RunOnlyIfIdle' 'false')
[void](Add-TaskXmlElement $document $settings 'WakeToRun' 'false')
[void](Add-TaskXmlElement $document $settings 'ExecutionTimeLimit' 'PT0S')
[void](Add-TaskXmlElement $document $settings 'Priority' '7')
$actions=Add-TaskXmlElement $document $task 'Actions' $null
$actions.SetAttribute('Context','Author')
$exec=Add-TaskXmlElement $document $actions 'Exec' $null
[void](Add-TaskXmlElement $document $exec 'Command' $powershell)
[void](Add-TaskXmlElement $document $exec 'Arguments' $arguments)
[void](Add-TaskXmlElement $document $exec 'WorkingDirectory' $WorkingDirectory)

$ExportPath=[IO.Path]::GetFullPath($ExportPath)
$exportDirectory=Split-Path -Parent $ExportPath
if (-not (Test-Path -LiteralPath $exportDirectory)) { New-Item -ItemType Directory -Path $exportDirectory -Force | Out-Null }
$writerSettings=New-Object System.Xml.XmlWriterSettings
$writerSettings.Encoding=[System.Text.Encoding]::Unicode
$writerSettings.Indent=$true
$writer=[System.Xml.XmlWriter]::Create($ExportPath,$writerSettings)
try { $document.Save($writer) } finally { $writer.Dispose() }

if ($RegisterTask) {
    $existing=Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue
    if ($existing) { throw "Task '$TaskName' already exists; it was not changed." }
    $exportedXml=[IO.File]::ReadAllText($ExportPath)
    Register-ScheduledTask -TaskName $TaskName -Xml $exportedXml -ErrorAction Stop | Out-Null
}
[pscustomobject]@{TaskName=$TaskName;ExportPath=$ExportPath;Registered=[bool]$RegisterTask;Started=$false;Action=@{Execute=$powershell;Argument=$arguments;WorkingDirectory=$WorkingDirectory};Trigger=@{AtLogOn=$user};Principal=@{UserId=$user;LogonType='InteractiveToken';RunLevel='LeastPrivilege'};Settings=@{MultipleInstances='IgnoreNew';ExecutionTimeLimit='PT0S';StartWhenAvailable=$true}}
