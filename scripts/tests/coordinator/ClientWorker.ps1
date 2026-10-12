[CmdletBinding()]
param([Parameter(Mandatory=$true)][string]$ConfigPath)
$ErrorActionPreference = 'Stop'
$utf8 = New-Object Text.UTF8Encoding($false,$true)
$config = [IO.File]::ReadAllText($ConfigPath,$utf8) | ConvertFrom-Json
$root = [IO.Path]::GetFullPath($config.testRoot).TrimEnd('\') + '\'
foreach ($name in @('ready','go','result')) {
    $path = [IO.Path]::GetFullPath($config.$name)
    if (-not $path.StartsWith($root,[StringComparison]::OrdinalIgnoreCase)) { throw 'Worker path outside isolated test root' }
}
if ($config.pipeName -notmatch '^story16-qa-[a-f0-9]{32}$') { throw 'Only isolated QA pipe names allowed' }
$timeout = [int]$config.timeoutMilliseconds
if ($timeout -lt 100 -or $timeout -gt 10000) { throw 'Invalid bounded client timeout' }
$result=@{evidenceClass='ipc-client-process';pid=$PID;startedAtUtc=(Get-Process -Id $PID).StartTime.ToUniversalTime().ToString('o');success=$false}
$pipe=$null
try {
    [IO.File]::WriteAllText($config.ready,'ready',$utf8)
    $clock=[Diagnostics.Stopwatch]::StartNew()
    while (-not [IO.File]::Exists($config.go)) {
        if ($clock.ElapsedMilliseconds -ge $timeout) { throw 'Start barrier timeout' }
        Start-Sleep -Milliseconds 10
    }
    $pipe=New-Object IO.Pipes.NamedPipeClientStream('.', $config.pipeName, [IO.Pipes.PipeDirection]::InOut, [IO.Pipes.PipeOptions]::Asynchronous)
    $result.connectAttemptTicks=[DateTime]::UtcNow.Ticks
    $pipe.Connect($timeout)
    $payload=$utf8.GetBytes((ConvertTo-Json -InputObject $config.request -Depth 20 -Compress)+"`n")
    if ($payload.Length -gt 1048576) { throw 'Oversized IPC request' }
    $write=$pipe.BeginWrite($payload,0,$payload.Length,$null,$null)
    try {
        if (-not $write.AsyncWaitHandle.WaitOne($timeout)) { throw 'IPC write timeout' }
        $pipe.EndWrite($write)
    } finally { $write.AsyncWaitHandle.Close() }
    $bytes=New-Object 'System.Collections.Generic.List[byte]'
    $buffer=New-Object byte[] 1
    $clock.Restart()
    while ($true) {
        $remaining=$timeout-[int]$clock.ElapsedMilliseconds
        if ($remaining -le 0) { throw 'IPC response timeout' }
        $read=$pipe.BeginRead($buffer,0,1,$null,$null)
        try {
            if (-not $read.AsyncWaitHandle.WaitOne($remaining)) { throw 'IPC response timeout' }
            $count=$pipe.EndRead($read)
        } finally { $read.AsyncWaitHandle.Close() }
        if ($count -eq 0) { throw 'IPC EOF before response' }
        if ($buffer[0] -eq 10) { break }
        $bytes.Add($buffer[0])
        if ($bytes.Count -gt 1048576) { throw 'Oversized IPC response' }
    }
    $result.response=$utf8.GetString($bytes.ToArray()) | ConvertFrom-Json
    $result.responseReceivedTicks=[DateTime]::UtcNow.Ticks
    $result.success=$true
} catch { $result.error=$_.Exception.Message }
finally {
    if ($pipe) { $pipe.Dispose() }
    [IO.File]::WriteAllText($config.result,(ConvertTo-Json -InputObject $result -Depth 25),$utf8)
}
if (-not $result.success) { exit 1 }
