[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)][ValidateSet('Status','SubmitInput','Interrupt')][string]$Operation,
    [Parameter(Mandatory=$true)][string]$DataDirectory,
    [string]$PipeName,
    [string]$LogicalSessionId,
    [string]$RequestId=([guid]::NewGuid().ToString('N')),
    [string]$InputText,
    [ValidateSet('chat','event','host')][string]$Source='chat',
    [ValidateRange(100,30000)][int]$TimeoutMilliseconds=5000
)
$ErrorActionPreference='Stop'
$utf8=New-Object System.Text.UTF8Encoding($false,$true)
if (-not $PipeName) { $PipeName='agent-coordinator-'+([Convert]::ToBase64String([Security.Cryptography.SHA256]::Create().ComputeHash([Text.Encoding]::UTF8.GetBytes([IO.Path]::GetFullPath($DataDirectory)))).TrimEnd('=').Replace('+','_').Replace('/','_').Substring(0,24)) }
if (-not $LogicalSessionId) {
    $sessionPath=Join-Path ([IO.Path]::GetFullPath($DataDirectory)) 'session.json'
    if (-not (Test-Path -LiteralPath $sessionPath)) { throw 'Unavailable: no coordinator session.' }
    $LogicalSessionId=([IO.File]::ReadAllText($sessionPath,$utf8)|ConvertFrom-Json).LogicalSessionId
}
$request=@{requestId=$RequestId;operation=$Operation;logicalSessionId=$LogicalSessionId;source=$Source}
if ($Operation -eq 'SubmitInput') { if ($null -eq $InputText) { throw 'InputText required.' };$request.inputText=$InputText }
$pipe=$null
try {
    $pipe=New-Object IO.Pipes.NamedPipeClientStream('.', $PipeName,[IO.Pipes.PipeDirection]::InOut,[IO.Pipes.PipeOptions]::Asynchronous)
    $pipe.Connect($TimeoutMilliseconds)
    $reader=New-Object IO.StreamReader($pipe,$utf8,$false,4096,$true);$writer=New-Object IO.StreamWriter($pipe,$utf8,4096,$true);$writer.AutoFlush=$true
    $wire=ConvertTo-Json -InputObject $request -Depth 12 -Compress
    if ($utf8.GetByteCount($wire) -gt 1048576) { throw 'Request too large.' }
    $writer.WriteLine($wire)
    $task=$reader.ReadLineAsync()
    if (-not $task.Wait($TimeoutMilliseconds)) { throw 'Unavailable: response timeout.' }
    $reply=$task.Result|ConvertFrom-Json -ErrorAction Stop
    $writer.Dispose();$reader.Dispose()
    $reply|ConvertTo-Json -Depth 20 -Compress
} catch { Write-Error $_.Exception.Message; exit 1 }
finally { if ($pipe) { $pipe.Dispose() } }
