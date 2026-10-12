[CmdletBinding()]
param([Parameter(Mandatory=$true)][string]$ConfigPath)
$ErrorActionPreference = 'Stop'
$utf8 = New-Object Text.UTF8Encoding($false, $true)
[Console]::InputEncoding = $utf8
[Console]::OutputEncoding = $utf8
$config = [IO.File]::ReadAllText($ConfigPath, $utf8) | ConvertFrom-Json
$root = [IO.Path]::GetFullPath($config.testRoot).TrimEnd('\') + '\'
$journal = [IO.Path]::GetFullPath($config.journal)
if (-not $journal.StartsWith($root, [StringComparison]::OrdinalIgnoreCase)) { throw 'Journal outside test root' }
if ($config.mode -notin @('normal','auth-error','resume-error','resume-mismatch','no-response','lost-turn-ack','cli-error')) { throw 'Unknown fixture mode' }
$delay = [int]$config.turnDelayMilliseconds
if ($delay -lt 0 -or $delay -gt 2000) { throw 'Delay outside bounded fixture range' }
if ($config.identityPath) {
    $identity=[IO.Path]::GetFullPath($config.identityPath)
    if (-not $identity.StartsWith($root,[StringComparison]::OrdinalIgnoreCase)) { throw 'Identity outside test root' }
    [IO.File]::WriteAllText($identity,(ConvertTo-Json @{pid=$PID;startedAtUtc=(Get-Process -Id $PID).StartTime.ToUniversalTime().ToString('o')} -Compress),$utf8)
}
function Emit($value) { [Console]::Out.WriteLine((ConvertTo-Json -InputObject $value -Depth 20 -Compress)); [Console]::Out.Flush() }
function Timing($phase,$turnId) {
    if (-not $config.turnTimingPath) { return }
    $path=[IO.Path]::GetFullPath($config.turnTimingPath)
    if (-not $path.StartsWith($root,[StringComparison]::OrdinalIgnoreCase)) { throw 'Timing outside test root' }
    [IO.File]::AppendAllText($path,(ConvertTo-Json @{phase=$phase;turnId=$turnId;pid=$PID;ticks=[DateTime]::UtcNow.Ticks} -Compress)+"`n",$utf8)
}
if ($config.mode -eq 'cli-error') { exit 23 }
$threadId = 'qa-fixture-thread'
$turnNumber = 0
while ($null -ne ($line = [Console]::ReadLine())) {
    if ($utf8.GetByteCount($line) -gt 1048576) { throw 'Oversized fixture request' }
    $request = $line | ConvertFrom-Json
    [IO.File]::AppendAllText($journal, (ConvertTo-Json -InputObject $request -Depth 20 -Compress) + "`n", $utf8)
    if ($request.method -eq 'initialized') { if ($null -ne $request.id) { Emit @{id=$request.id;result=@{}} }; continue }
    if ($config.mode -eq 'no-response') { continue }
    if ($config.mode -eq 'auth-error' -and $request.method -ne 'initialize') {
        Emit @{id=$request.id;error=@{code=-32001;message='QA fixture: authentication unavailable'}}; continue
    }
    switch ($request.method) {
        'initialize' { Emit @{id=$request.id;result=@{userAgent='qa-protocol-fixture'}} }
        'thread/start' { Emit @{id=$request.id;result=@{thread=@{id=$threadId;turns=@()}}} }
        'thread/resume' {
            if ($config.mode -eq 'resume-error') { Emit @{id=$request.id;error=@{code=-32002;message='QA fixture: resume failed'}} }
            else {
                $threadId = $request.params.threadId
                $answerId = $threadId
                if ($config.mode -eq 'resume-mismatch') { $answerId='qa-wrong-thread' }
                Emit @{id=$request.id;result=@{thread=@{id=$answerId;turns=@()}}}
            }
        }
        'thread/read' { Emit @{id=$request.id;result=@{thread=@{id=$threadId;turns=@()}}} }
        'turn/start' {
            $turnNumber++
            $turnId = 'qa-turn-' + $turnNumber
            Timing 'start' $turnId
            if ($config.mode -eq 'lost-turn-ack') { continue }
            Emit @{id=$request.id;result=@{turn=@{id=$turnId;status='inProgress';items=@()}}}
            Emit @{method='turn/started';params=@{threadId=$threadId;turn=@{id=$turnId;status='inProgress';items=@()}}}
            if ($delay) { Start-Sleep -Milliseconds $delay }
            # Repeated snapshot: a consumer must deduplicate, never add the notifications.
            $usage=@{method='thread/tokenUsage/updated';params=@{threadId=$threadId;turnId=$turnId;tokenUsage=@{last=@{totalTokens=12;inputTokens=10;cachedInputTokens=0;outputTokens=2;reasoningOutputTokens=0};total=@{totalTokens=(100+12*$turnNumber);inputTokens=(90+10*$turnNumber);cachedInputTokens=0;outputTokens=(10+2*$turnNumber);reasoningOutputTokens=0}}}}
            Emit $usage; Emit $usage
            Timing 'completed' $turnId
            Emit @{method='turn/completed';params=@{threadId=$threadId;turn=@{id=$turnId;status='completed';items=@()}}}
        }
        'turn/interrupt' { Emit @{id=$request.id;result=@{}} }
        default { Emit @{id=$request.id;error=@{code=-32601;message='Unknown QA fixture method'}} }
    }
}
