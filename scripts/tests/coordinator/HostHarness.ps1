[CmdletBinding()]
param([string]$ResultPath,[string]$DeliveryReport,[Parameter(Mandatory=$true)][string[]]$Gate)
$ErrorActionPreference='Stop'
$utf8=New-Object Text.UTF8Encoding($false,$true)
$root=Join-Path ([IO.Path]::GetTempPath()) ('story16-qa-'+[guid]::NewGuid().ToString('N'))
[void][IO.Directory]::CreateDirectory($root)
if (-not $ResultPath) { $ResultPath=Join-Path $root 'result.json' }
$workers=$PSScriptRoot
$children=New-Object 'System.Collections.Generic.List[object]'
$checks=New-Object 'System.Collections.Generic.List[object]'
function Save($value,$path) { [IO.File]::WriteAllText($path,(ConvertTo-Json -InputObject $value -Depth 30),$utf8) }
function Assert($condition,$message) { if (-not $condition) { throw $message } }
function Check($name,[scriptblock]$body) {
    if ($name -notin $Gate) { return }
    try { $detail=& $body; $checks.Add(@{name=$name;passed=$true;detail=$detail}) }
    catch {
        $diagnostics=@($children | Where-Object { $_.process.HasExited -and $_.stderr } | ForEach-Object {
            $text=$_.stderr.Result
            @{name=$_.name;pid=$_.pid;exitCode=$_.process.ExitCode;stderrTail=$text.Substring([Math]::Max(0,$text.Length-2000))}
        })
        $checks.Add(@{name=$name;passed=$false;error=$_.Exception.Message;diagnostics=$diagnostics})
    }
}
function Spawn($script,$config,$name) {
    $config.testRoot=$root
    $path=Join-Path $root ($name+'.config.json'); Save $config $path
    $psi=New-Object Diagnostics.ProcessStartInfo
    $psi.FileName=Join-Path $PSHOME 'powershell.exe'
    $psi.Arguments='-NoProfile -ExecutionPolicy Bypass -File "'+(Join-Path $workers $script)+'" -ConfigPath "'+$path+'"'
    $psi.UseShellExecute=$false; $psi.CreateNoWindow=$true
    $psi.RedirectStandardInput=$true; $psi.RedirectStandardOutput=$true; $psi.RedirectStandardError=$true
    $psi.StandardOutputEncoding=$utf8; $psi.StandardErrorEncoding=$utf8
    $process=[Diagnostics.Process]::Start($psi)
    $entry=@{name=$name;pid=$process.Id;startTicks=$process.StartTime.ToUniversalTime().Ticks;startedAtUtc=$process.StartTime.ToUniversalTime().ToString('o');process=$process;stderr=$process.StandardError.ReadToEndAsync();config=$config;killed=$false;exitCode=$null}
    # Keep stdin Unicode and without BOM; writing a BOM would corrupt the first JSON request.
    $entry.input=New-Object IO.StreamWriter($process.StandardInput.BaseStream,$utf8)
    $entry.input.AutoFlush=$true
    $children.Add($entry)
    return $entry
}
function Runtime($mode,$name) {
    $journal=Join-Path $root ($name+'.rpc.jsonl')
    return (Spawn 'MockRuntime.ps1' @{mode=$mode;journal=$journal;turnDelayMilliseconds=0} $name)
}
function Send($child,$id,$method,$params) { $child.input.WriteLine((ConvertTo-Json -InputObject @{id=$id;method=$method;params=$params} -Depth 20 -Compress)) }
function Notify($child,$method) { $child.input.WriteLine((ConvertTo-Json @{method=$method;params=@{}} -Compress)) }
function Receive($child,[int]$timeout=5000) {
    $pending=$child.process.StandardOutput.ReadLineAsync()
    if (-not $pending.Wait($timeout)) { throw 'QA RPC response timeout' }
    if ($null -eq $pending.Result) { throw 'QA RPC EOF' }
    return ($pending.Result | ConvertFrom-Json)
}
function Journal($child) {
    if (-not [IO.File]::Exists($child.config.journal)) { return @() }
    return @([IO.File]::ReadAllLines($child.config.journal,$utf8) | ForEach-Object { $_ | ConvertFrom-Json })
}
function Kill-Owned($child) {
    Assert ($children.Contains($child)) 'Unregistered child: refusing termination'
    if ($child.process.HasExited) { return }
    $actual=[Diagnostics.Process]::GetProcessById($child.pid)
    try {
        Assert ($actual.StartTime.ToUniversalTime().Ticks -eq $child.startTicks) 'PID/start-time mismatch: refusing termination'
        Assert ($actual.Id -eq $child.process.Id) 'Not a registered harness child'
        $actual.Kill(); $child.killed=$true
        Assert ($child.process.WaitForExit(5000)) 'Own child did not exit after termination'
    } finally { $actual.Dispose() }
    $child.exitCode=$child.process.ExitCode
}
function Close-Owned($child) {
    $child.input.Close()
    if (-not $child.process.WaitForExit(5000)) { Kill-Owned $child; throw 'Own child did not exit on EOF' }
    $child.exitCode=$child.process.ExitCode
    Assert ($child.exitCode -eq 0) ('Worker failed: '+$child.stderr.Result)
}
function Wait-File($path) {
    $watch=[Diagnostics.Stopwatch]::StartNew()
    while (-not [IO.File]::Exists($path)) {
        if ($watch.ElapsedMilliseconds -gt 5000) { throw 'QA barrier timeout' }
        Start-Sleep -Milliseconds 10
    }
}
# The preparation fixtures are reused here; their self-tests are intentionally not rerun.
$repo=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../..'))
$hostEntry=Join-Path $repo 'scripts/Start-CoordinatorHost.ps1'
if (-not $DeliveryReport -or -not [IO.File]::Exists($DeliveryReport)) { throw 'Final host execution requires the infrastructure delivery report' }
$hashPaths=@($hostEntry,(Join-Path $repo 'scripts/coordinator/CoordinatorHost.Core.psm1'),(Join-Path $repo 'scripts/Invoke-CoordinatorTurn.ps1'),(Join-Path $repo 'scripts/delegation/Start-DelegatedCodexTask.ps1'),(Join-Path $repo 'scripts/Test-CoordinatorHost.ps1'),$PSCommandPath,(Join-Path $workers 'MockRuntime.ps1'),(Join-Path $workers 'ClientWorker.ps1'),$DeliveryReport)
$hashBefore=@($hashPaths | ForEach-Object { @{path=$_;sha256=(Get-FileHash -LiteralPath $_ -Algorithm SHA256).Hash} })
function ReadJson($path) {
    $clock=[Diagnostics.Stopwatch]::StartNew()
    while ($true) {
        try {
            $stream=New-Object IO.FileStream($path,[IO.FileMode]::Open,[IO.FileAccess]::Read,([IO.FileShare]::ReadWrite -bor [IO.FileShare]::Delete))
            try { $reader=New-Object IO.StreamReader($stream,$utf8,$false);$text=$reader.ReadToEnd() } finally { if($reader){$reader.Dispose()};$stream.Dispose() }
        }
        catch {
            $cause=$_.Exception
            while($cause.InnerException){$cause=$cause.InnerException}
            if ($cause -isnot [IO.IOException] -or ($cause.HResult -band 65535) -notin @(2,32,33)) { throw }
            if ($clock.ElapsedMilliseconds -ge 500) { throw ('ReadbackPrecondition: bounded JSON read failed: '+$path+'; '+$_.Exception.Message) }
            Start-Sleep -Milliseconds 10
            continue
        }
        return ($text | ConvertFrom-Json -ErrorAction Stop) # Corrupt JSON is a precondition error; do not hide it with retries.
    }
}
function Await([scriptblock]$condition,[int]$milliseconds=12000) {
    $clock=[Diagnostics.Stopwatch]::StartNew()
    while (-not (& $condition)) { if($clock.ElapsedMilliseconds -ge $milliseconds){throw 'Bounded host condition timeout'}; Start-Sleep -Milliseconds 30 }
}
function HostProcess($spec,$name) {
    $psi=New-Object Diagnostics.ProcessStartInfo
    $psi.FileName=Join-Path $PSHOME 'powershell.exe'
    $args=@('-NoProfile','-ExecutionPolicy','Bypass','-File',$hostEntry,'-TestMode','-DataDirectory',$spec.data,'-PipeName',$spec.pipe,'-RuntimeConfigPath',$spec.runtimeConfig,'-ReadyPath',$spec.ready,'-ReleasePath',$spec.release,'-ExitPath',$spec.stop,'-WorkingDirectory',$spec.data,'-ResumeRetryLimit','3','-RpcTimeoutMilliseconds','700')
    $psi.Arguments=($args | ForEach-Object {'"'+$_+'"'}) -join ' '
    $psi.UseShellExecute=$false; $psi.CreateNoWindow=$true
    $psi.RedirectStandardInput=$true; $psi.RedirectStandardOutput=$true; $psi.RedirectStandardError=$true
    $process=[Diagnostics.Process]::Start($psi)
    $c=@{name=$name;pid=$process.Id;startTicks=$process.StartTime.ToUniversalTime().Ticks;startedAtUtc=$process.StartTime.ToUniversalTime().ToString('o');process=$process;stderr=$process.StandardError.ReadToEndAsync();stdout=$process.StandardOutput.ReadToEndAsync();input=$process.StandardInput;killed=$false;exitCode=$null;config=$spec}
    $children.Add($c); return $c
}
function Spec($name,$mode='normal',[int]$delay=0) {
    $dir=Join-Path $root $name; [void][IO.Directory]::CreateDirectory($dir)
    $mock=Join-Path $dir 'mock.json';$rc=Join-Path $dir 'runtime.json'
    $journal=Join-Path $dir 'rpc.jsonl';$identity=Join-Path $dir 'runtime.identity.json'
    Save @{testRoot=$root;mode=$mode;journal=$journal;identityPath=$identity;turnTimingPath=(Join-Path $dir 'turn-timing.jsonl');turnDelayMilliseconds=$delay} $mock
    Save @{RuntimeExecutable=(Join-Path $PSHOME 'powershell.exe');RuntimeArguments=@('-NoProfile','-ExecutionPolicy','Bypass','-File',(Join-Path $workers 'MockRuntime.ps1'),'-ConfigPath',$mock);WorkingDirectory=$dir;RuntimeFactory=$null} $rc
    return @{data=$dir;pipe=('story16-qa-'+[guid]::NewGuid().ToString('N'));ready=(Join-Path $dir 'ready');release=(Join-Path $dir 'release');stop=(Join-Path $dir 'stop');runtimeConfig=$rc;timing=(Join-Path $dir 'turn-timing.jsonl');journal=$journal;identity=$identity;session=(Join-Path $dir 'session.json')}
}
function Seed($spec,$thread='qa-persisted-thread') {
    Save @{SchemaVersion=1;LogicalSessionId=[guid]::NewGuid().ToString('N');NativeThreadId=$thread;State='Ready';Revision=0;LastRequestId=$null;LastTurnId=$null;LastOutcome=$null;LastError=$null;LastUsage=$null;LastSource=$null;ResumeAttempts=0;Cwd=$spec.data;AllowProvisioning=$true;OwnerPid=$null;OwnerStartedUtc=$null;RuntimePid=$null;RuntimeStartedAtUtc=$null;CreatedAtUtc=[DateTime]::UtcNow.ToString('o')} $spec.session
}
function RegisterRuntime($spec) {
    if (-not [IO.File]::Exists($spec.identity)) { return }
    $id=ReadJson $spec.identity
    if (@($children | Where-Object { $_.pid -eq $id.pid -and $_.startedAtUtc -ceq $id.startedAtUtc }).Count) { return }
    $p=Get-Process -Id $id.pid -ErrorAction SilentlyContinue
    if (-not $p) { return } # Exited runtime is expected in fail-closed cases; never reacquire by PID alone.
    Assert ($p.StartTime.ToUniversalTime().ToString('o') -ceq $id.startedAtUtc) 'Runtime identity mismatch'
    $children.Add(@{name='owned-runtime';pid=$p.Id;startTicks=$p.StartTime.ToUniversalTime().Ticks;startedAtUtc=$id.startedAtUtc;process=$p;input=$null;killed=$false;exitCode=$null})
}
function StartHost($spec,$name) {
    $c=HostProcess $spec $name
    Await { [IO.File]::Exists($spec.ready) -or $c.process.HasExited }
    Assert (-not $c.process.HasExited) 'Host exited before readiness'
    $barrier=ReadJson $spec.ready
    Assert ($barrier.pid -eq $c.pid -and $barrier.startedAtUtc -ceq $c.startedAtUtc) 'ReadinessPrecondition: stale host barrier identity'
    [IO.File]::WriteAllText($spec.release,'go',$utf8)
    Await { $c.process.HasExited -or ([IO.File]::Exists($spec.session) -and (ReadJson $spec.session).State -eq 'Ready' -and [IO.File]::Exists($spec.identity)) }
    RegisterRuntime $spec
    Assert (-not $c.process.HasExited) 'Host initialization failed'
    $status=Call $spec 'Status' ('readiness-'+[guid]::NewGuid().ToString('N'))
    Assert ($status.status -eq 'Ready') 'ReadinessPrecondition: live dispatcher not Ready'
    return $c
}
function StopHost($c) {
    [IO.File]::WriteAllText($c.config.stop,'stop',$utf8)
    Assert ($c.process.WaitForExit(6000)) 'Host failed bounded controlled stop'
    $c.exitCode=$c.process.ExitCode
    Assert ($c.exitCode -eq 0) ('Host stop failed: '+$c.stderr.Result)
}
function RPCs($spec) {
    if(-not [IO.File]::Exists($spec.journal)){return @()}
    return @([IO.File]::ReadAllLines($spec.journal,$utf8) | ForEach-Object {$_|ConvertFrom-Json})
}
function Client($spec,$operation,$id,$text='harmless QA',$source='chat',$go=$null) {
    $n='client-'+[guid]::NewGuid().ToString('N');if(-not $go){$go=Join-Path $root ($n+'.go')}
    $cfg=@{pipeName=$spec.pipe;ready=(Join-Path $root ($n+'.ready'));go=$go;result=(Join-Path $root ($n+'.result.json'));timeoutMilliseconds=10000;request=@{operation=$operation;requestId=$id;logicalSessionId=(ReadJson $spec.session).LogicalSessionId;inputText=$text;source=$source}}
    return (Spawn 'ClientWorker.ps1' $cfg $n)
}
function ClientResult($c) {
    Assert ($c.process.WaitForExit(12000)) 'Client deadline failed'
    $c.exitCode=$c.process.ExitCode
    $r=ReadJson $c.config.result
    Assert ($r.success) ('IPC failed: '+$r.error)
    return $r.response
}
function Call($spec,$op,$id,$text='harmless QA',$source='chat') {
    $c=Client $spec $op $id $text $source
    Wait-File $c.config.ready; [IO.File]::WriteAllText($c.config.go,'go',$utf8)
    return (ClientResult $c)
}
function Evidence($spec) { @{evidenceClass='real-OS-host-and-client-processes/mock-RPC';dataDirectory=$spec.data;journal=$spec.journal;session=$spec.session;runtimeIdentity=$spec.identity} }
$mockOwnershipGate=$false
try {
    Check 'Fixture strictly rejects initialized RPC and never answers notification' {
        $c=Runtime 'normal' 'notification-correct'
        Send $c 1 'initialize' @{};$r=Receive $c;Assert ($r.id -eq 1) 'Fixture initialize failed'
        Notify $c 'initialized';Send $c 3 'thread/read' @{}
        $r=Receive $c;Assert ($r.id -eq 3) 'Fixture emitted unexpected initialized response'
        Close-Owned $c
        foreach($badId in @(2,$null)) {
            $c=Runtime 'normal' ('notification-invalid-'+[guid]::NewGuid().ToString('N'))
            Send $c 1 'initialize' @{};$null=Receive $c
            Send $c $badId 'initialized' @{}
            Assert ($c.process.WaitForExit(2000)) 'Invalid initialized RPC not rejected promptly'
            Assert ($c.process.ExitCode -ne 0 -and $c.stderr.Result -match 'ProtocolViolation') 'Malformed RPC was not a fixture protocol error'
            Assert ($c.process.StandardOutput.ReadToEnd() -eq '') 'Fixture answered invalid initialized RPC'
        }
        @{evidenceClass='fixture-protocol-contract';initializedResponseExpected=$false;rejectedIdValues=@(2,$null)}
    }
    Check 'Harness kill protection refuses unregistered and mismatched identities' {
        $c=Runtime 'normal' 'kill-protection'
        $original=$c.startTicks;$rejected=$false
        try { $c.startTicks=$original+1;Kill-Owned $c } catch { $rejected=$_.Exception.Message -match 'mismatch' } finally { $c.startTicks=$original }
        Assert ($rejected -and -not $c.process.HasExited) 'Mismatched identity was not protected'
        $copy=$c.Clone();$rejected=$false
        try { Kill-Owned $copy } catch { $rejected=$_.Exception.Message -match 'Unregistered' }
        Assert ($rejected -and -not $c.process.HasExited) 'Unregistered process reference was not protected'
        Close-Owned $c;@{evidenceClass='own-fixture-kill-guard';foreignProcessesTouched=$false}
    }
    Check 'Two competing OS hosts: exactly one owner and one runtime; idle no turn' {
        $s=Spec 'competition';Seed $s
        $a=HostProcess $s 'host-a';$b=HostProcess $s 'host-b'
        Await { [IO.File]::Exists($s.ready) }
        $ready=ReadJson $s.ready
        Assert ($ready.pid -in @($a.pid,$b.pid)) 'Owner not one of own competing hosts'
        $winner=if($ready.pid -eq $a.pid){$a}else{$b};$loser=if($ready.pid -eq $a.pid){$b}else{$a}
        Assert ($loser.process.WaitForExit(8000)) 'Competing host did not fail within ownership budget'
        $loser.exitCode=$loser.process.ExitCode
        Assert ($loser.exitCode -ne 0) 'Both host processes acquired ownership'
        [IO.File]::WriteAllText($s.release,'go',$utf8)
        Await { $winner.process.HasExited -or ([IO.File]::Exists($s.identity) -and (ReadJson $s.session).State -eq 'Ready') }
        RegisterRuntime $s
        Assert (-not $winner.process.HasExited) 'Owner initialization failed'
        Start-Sleep -Milliseconds 350
        $rpc=RPCs $s
        $notifications=@($rpc|Where-Object method -eq 'initialized')
        Assert ($notifications.Count -eq 1 -and $notifications[0].PSObject.Properties.Name -notcontains 'id') 'initialized was not exactly one notification without id'
        Assert (@($rpc | Where-Object method -eq 'initialize').Count -eq 1) 'More than one runtime initialized'
        Assert (@($rpc | Where-Object method -eq 'turn/start').Count -eq 0) 'Idle inference detected'
        $e=Evidence $s;$e.owner=$winner.pid;$e.loser=$loser.pid;$e.loserExit=$loser.exitCode;$e.idleMilliseconds=350
        StopHost $winner;$mockOwnershipGate=$true;$e
    }
    Check 'Parallel chat/event, Unicode, turn token dedupe, RequestId replay prevention' {
        $s=Spec 'parallel' 'normal' 400;Seed $s;$h=StartHost $s 'parallel-host'
        $go=Join-Path $s.data 'clients.go';$text='Grüße 東京 🧪'
        $a=Client $s 'SubmitInput' 'chat-request' $text 'chat' $go
        $b=Client $s 'SubmitInput' 'event-request' 'harmless event' 'event' $go
        Wait-File $a.config.ready;Wait-File $b.config.ready;[IO.File]::WriteAllText($go,'go',$utf8)
        $ra=ClientResult $a;$rb=ClientResult $b
        Assert ($ra.status -in @('Accepted','Busy') -and $rb.status -in @('Accepted','Busy') -and 'Accepted' -in @($ra.status,$rb.status)) 'Parallel admission unexpected'
        # Either source may win. A Busy response must be retried after the completed winner.
        if ($ra.status -eq 'Busy') { $ra=Call $s 'SubmitInput' 'chat-request' $text }
        if ($rb.status -eq 'Busy') {
            $retry=Client $s 'SubmitInput' 'event-request' 'harmless event' 'event'
            Wait-File $retry.config.ready;[IO.File]::WriteAllText($retry.config.go,'go',$utf8);$rb=ClientResult $retry
        }
        Assert ($ra.status -eq 'Accepted' -and $rb.status -eq 'Accepted') 'Precondition: both sources must complete before serialization assertion'
        $rpc=RPCs $s;$turns=@($rpc | Where-Object method -eq 'turn/start')
        Assert ($turns.Count -eq 2) 'Both sources did not execute exactly once'
        Assert (@($turns | Where-Object {$_.params.input[0].text -ceq $text}).Count -eq 1) 'Unicode payload not preserved'
        Assert ($ra.tokenUsage.totalTokens -eq 12) 'Turn usage is not deduplicated last snapshot 12'
        $timing=@([IO.File]::ReadAllLines($s.timing,$utf8)|ForEach-Object {$_|ConvertFrom-Json}|Where-Object {$_.phase -in @('start','completed')})
        $firstCompletion=@($timing|Where-Object phase -eq 'completed')[0].ticks
        Assert ((ReadJson $a.config.result).connectAttemptTicks -lt $firstCompletion -and (ReadJson $b.config.result).connectAttemptTicks -lt $firstCompletion) 'SerializationPrecondition: clients did not contend before first completion'
        $active=0;$maximum=0
        foreach($event in $timing) { if($event.phase -eq 'start'){$active++}else{$active--};$maximum=[Math]::Max($maximum,$active);Assert ($active -ge 0 -and $active -le 1) 'Overlapping active runtime turns' }
        Assert ($active -eq 0 -and $maximum -eq 1) 'Turn timing lacks matched terminal evidence'
        $last=ReadJson $s.session
        $duplicate=Call $s 'SubmitInput' $last.LastRequestId $turns[-1].params.input[0].text $last.LastSource
        Assert ($duplicate.status -eq 'Duplicate') 'Immediate RequestId duplicate not rejected'
        Assert (@((RPCs $s)|Where-Object method -eq 'turn/start').Count -eq $turns.Count) 'Duplicate replayed'
        $e=Evidence $s;$e.responses=@($ra,$rb,$duplicate);$e.concurrentClients=@($a.pid,$b.pid);$e.turns=$turns.Count;$e.maximumActiveTurns=$maximum;$e.timingJournal=$s.timing
        StopHost $h;$e
    }
    Check 'Older RequestId remains deduplicated after another completed request' {
        $s=Spec 'dedupe-history';Seed $s;$h=StartHost $s 'dedupe-host'
        $first=Call $s 'SubmitInput' 'first';$second=Call $s 'SubmitInput' 'second'
        Assert ($first.status -eq 'Accepted' -and $second.status -eq 'Accepted' -and $first.turnId -ne $second.turnId) 'ReplayPrecondition: two distinct completed Accepted requests required'
        Assert (@((RPCs $s)|Where-Object method -eq 'turn/start').Count -eq 2) 'ReplayPrecondition: missing two turn/start records'
        $r=Call $s 'SubmitInput' 'first'
        $conflict=Call $s 'SubmitInput' 'first' 'changed payload must be rejected'
        $e=Evidence $s;$e.response=$r;Save $e (Join-Path $s.data 'dedupe-evidence.json')
        StopHost $h
        Assert ($r.status -eq 'Duplicate' -and @((RPCs $s)|Where-Object method -eq 'turn/start').Count -eq 2) 'Older RequestId replayed after another request'
        Assert ($conflict.status -eq 'Rejected') 'RequestId reused with changed payload was not rejected'
        $e
    }
    Check 'Controlled host restart preserves logical/native thread and resumes only' {
        $s=Spec 'restart';Seed $s;$h=StartHost $s 'restart-h1'
        $r=Call $s 'SubmitInput' 'before-restart';Assert ($r.status -eq 'Accepted') 'RestartPrecondition: completed turn required'
        $r2=Call $s 'SubmitInput' 'second-before-restart';Assert ($r2.status -eq 'Accepted' -and $r.turnId -ne $r2.turnId) 'RestartPrecondition: two distinct completed requests required'
        $before=ReadJson $s.session
        $runtimeBefore=ReadJson $s.identity
        StopHost $h
        Remove-Item -LiteralPath $s.ready,$s.release,$s.stop,$s.identity
        $h2=StartHost $s 'restart-h2';$after=ReadJson $s.session
        Assert ($before.NativeThreadId -ceq $after.NativeThreadId -and $before.LogicalSessionId -ceq $after.LogicalSessionId) 'Restart changed binding'
        Assert (@((RPCs $s)|Where-Object method -eq 'thread/resume').Count -eq 2) 'Restart did not resume same thread'
        Assert (@((RPCs $s)|Where-Object {$_.method -eq 'thread/resume' -and $_.params.threadId -cne $before.NativeThreadId}).Count -eq 0) 'Resume used another thread ID'
        $runtimeAfter=ReadJson $s.identity
        Assert ($runtimeBefore.pid -ne $runtimeAfter.pid -or $runtimeBefore.startedAtUtc -cne $runtimeAfter.startedAtUtc) 'RestartPrecondition: runtime process identity did not change'
        Assert (@((RPCs $s)|Where-Object method -eq 'thread/start').Count -eq 0) 'Replacement thread created'
        $replay=Call $s 'SubmitInput' 'before-restart'
        Assert ($replay.status -eq 'Duplicate' -and @((RPCs $s)|Where-Object method -eq 'turn/start').Count -eq 2) 'Restart replayed older completed request'
        StopHost $h2;Evidence $s
    }
    Check 'Own abrupt host abort: job ends runtime before controlled restart' {
        $s=Spec 'abort';Seed $s;$h=StartHost $s 'abort-h1';$runtime=ReadJson $s.identity
        Save @{hostPid=$h.pid;hostStartedUtc=$h.startedAtUtc;runtime=$runtime} (Join-Path $s.data 'pre-abort-identities.json')
        Kill-Owned $h
        Remove-Item -LiteralPath $s.ready,$s.release
        $r=@($children | Where-Object {$_.pid -eq $runtime.pid})[0]
        Assert ($r.process.WaitForExit(5000)) 'KillOnJobClose did not end own runtime after abrupt host abort'
        Remove-Item -LiteralPath $s.identity
        $before=ReadJson $s.session
        $h2=StartHost $s 'abort-h2';$after=ReadJson $s.session
        Assert ($before.LogicalSessionId -ceq $after.LogicalSessionId -and $before.NativeThreadId -ceq $after.NativeThreadId) 'Abrupt restart changed session binding'
        Assert (@((RPCs $s)|Where-Object method -eq 'thread/start').Count -eq 0 -and @((RPCs $s)|Where-Object method -eq 'thread/resume').Count -eq 2) 'Abrupt restart replaced thread or failed to resume'
        StopHost $h2
        $e=Evidence $s;$e.abortHostPid=$h.pid;$e.oldRuntime=$runtime;$e.runtimeExitedBeforeRestart=$true;$e
    }
    foreach($identityCase in @('live','mismatched-start','missing-start','foreign-unregistered')) {
    Check ('Process identity blocks without killing: '+$identityCase) {
        $s=Spec ('identity-'+$identityCase);Seed $s
        $c=Runtime 'normal' 'old-runtime';$session=ReadJson $s.session
        $session.RuntimePid=$c.pid
        $session.RuntimeStartedAtUtc=switch ($identityCase) { 'mismatched-start' { [DateTime]::Parse($c.startedAtUtc).AddSeconds(1).ToString('o') }; 'missing-start' { $null }; default { $c.startedAtUtc } }
        Save $session $s.session
        $h=HostProcess $s 'ambiguous-host';Assert ($h.process.WaitForExit(8000)) 'Ambiguous owner not bounded'
        $h.exitCode=$h.process.ExitCode
        Assert ($h.exitCode -ne 0 -and $h.stderr.Result -match 'ambiguous|BlockedRecovery' -and -not $c.process.HasExited) 'Ambiguous owner activated or killed old process'
        Assert (@(RPCs $s).Count -eq 0 -and -not [IO.File]::Exists($s.identity)) 'Blocked identity launched a new runtime'
        # foreign-unregistered means foreign to the host; it is still an owned QA child.
        Close-Owned $c;Evidence $s
    }
    }
    foreach($mode in @('auth-error','resume-error','resume-mismatch','cli-error')) {
        Check ('Host fail-closed '+$mode) {
            $s=Spec $mode $mode;Seed $s;$h=HostProcess $s ('failure-'+$mode)
            Await {[IO.File]::Exists($s.ready) -or $h.process.HasExited}
            [IO.File]::WriteAllText($s.release,'go',$utf8)
            $bounded=$h.process.WaitForExit(6000);RegisterRuntime $s
            $rpc=RPCs $s;$session=ReadJson $s.session
            $e=Evidence $s;$e.bounded=$bounded;$e.state=$session.State;$e.error=$session.LastError;Save $e (Join-Path $s.data 'failure-evidence.json')
            Assert $bounded 'Configured 700ms RPC timeout not honored within 6 seconds'
            $h.exitCode=$h.process.ExitCode
            Assert ($h.exitCode -ne 0 -and $session.State -in @('BlockedRecovery','RecoveryUnknown')) 'Failure did not fail closed'
            Assert (@($rpc|Where-Object method -eq 'thread/start').Count -eq 0 -and @($rpc|Where-Object method -eq 'turn/start').Count -eq 0) 'Failure provisioned or replayed'
            $attempts=@($rpc|Where-Object method -eq 'thread/resume').Count
            Assert ($attempts -le 3) 'Resume retry exceeded budget'
            if($mode -eq 'resume-error'){Assert ($attempts -eq 3) 'Configured retry budget not exercised'}
            if($mode -eq 'auth-error'){Assert ($attempts -le 1) 'Auth failure retried'}
            $e.resumeAttempts=$attempts;$e
        }
    }
    Check 'Lost turn ACK blocks replay and replacement within configured timeout' {
        $s=Spec 'lost-ack' 'lost-turn-ack';Seed $s;$h=StartHost $s 'lost-ack-host'
        $r=Call $s 'SubmitInput' 'uncertain-turn'
        Assert ($r.status -eq 'BlockedRecovery') 'Lost ACK not blocked within client budget'
        $r2=Call $s 'SubmitInput' 'new-turn'
        Assert ($r2.status -in @('Busy','BlockedRecovery')) 'Unknown turn admitted another request'
        Assert (@((RPCs $s)|Where-Object method -eq 'turn/start').Count -eq 1) 'Unknown turn replayed'
        $before=ReadJson $s.session;StopHost $h
        Remove-Item -LiteralPath $s.ready,$s.release,$s.stop,$s.identity
        $h2=HostProcess $s 'lost-ack-restart'
        Await {[IO.File]::Exists($s.ready) -or $h2.process.HasExited}
        Assert (-not $h2.process.HasExited) 'ACKRestartPrecondition: no current startup barrier'
        $barrier=ReadJson $s.ready;Assert ($barrier.pid -eq $h2.pid -and $barrier.startedAtUtc -ceq $h2.startedAtUtc) 'Stale restart barrier'
        [IO.File]::WriteAllText($s.release,'go',$utf8)
        Await { $h2.process.HasExited -or @((RPCs $s)|Where-Object method -eq 'thread/resume').Count -eq 2 }
        if(-not $h2.process.HasExited){$null=Call $s 'Status' 'after-ack-restart'}
        $after=ReadJson $s.session
        Assert ($after.State -in @('BlockedRecovery','RecoveryUnknown') -and $after.LogicalSessionId -ceq $before.LogicalSessionId -and $after.NativeThreadId -ceq $before.NativeThreadId) 'ACK loss silently became Ready or changed binding after restart'
        Assert (@((RPCs $s)|Where-Object method -eq 'turn/start').Count -eq 1 -and @((RPCs $s)|Where-Object method -eq 'thread/start').Count -eq 0) 'ACK restart replayed or provisioned replacement'
        RegisterRuntime $s;if(-not $h2.process.HasExited){StopHost $h2};Evidence $s
    }
    Check 'Optional accountingDirectory absent accepts completed turn' {
        $s=Spec 'no-accounting';Seed $s;$h=StartHost $s 'no-accounting-host'
        $c=Client $s 'SubmitInput' 'no-accounting-request'
        Assert (-not $c.config.request.ContainsKey('accountingDirectory')) 'AccountingPrecondition: property must be absent, not null'
        Wait-File $c.config.ready;[IO.File]::WriteAllText($c.config.go,'go',$utf8)
        $r=ClientResult $c;$session=ReadJson $s.session
        Assert ($r.status -eq 'Accepted' -and $session.State -eq 'Ready' -and $session.LastOutcome -eq 'completed') 'Absent optional accounting prevented successful turn'
        Assert ($r.tokenUsage.totalTokens -eq 12) 'Absent accounting lost per-turn token snapshot'
        StopHost $h;Evidence $s
    }
    foreach($timeoutMode in @('no-response','start-no-response','resume-no-response','lost-turn-ack')) {
        Check ('700ms runtime deadline: '+$timeoutMode) {
            $s=Spec ('deadline-'+$timeoutMode) $timeoutMode
            if($timeoutMode -eq 'start-no-response'){Seed $s $null}else{Seed $s}
            $target=switch($timeoutMode) { 'no-response' {'initialize'}; 'start-no-response' {'thread/start'}; 'resume-no-response' {'thread/resume'}; default {'turn/start'} }
            if ($target -eq 'turn/start') {
                $h=StartHost $s ('deadline-'+$timeoutMode)
                $c=Client $s 'SubmitInput' 'deadline-request'
                Wait-File $c.config.ready;[IO.File]::WriteAllText($c.config.go,'go',$utf8)
                $r=ClientResult $c
                $terminalTicks=(ReadJson $c.config.result).responseReceivedTicks
                Assert ($r.status -eq 'BlockedRecovery') 'Runtime timeout did not return fail-closed response'
            } else {
                $h=HostProcess $s ('deadline-'+$timeoutMode)
                Await {[IO.File]::Exists($s.ready) -or $h.process.HasExited}
                Assert (-not $h.process.HasExited) 'DeadlinePrecondition: host must reach release barrier'
                [IO.File]::WriteAllText($s.release,'go',$utf8)
                Await { (ReadJson $s.session).State -in @('BlockedRecovery','RecoveryUnknown') } 5000
                $terminalTicks=[DateTime]::UtcNow.Ticks
            }
            $events=@([IO.File]::ReadAllLines($s.timing,$utf8)|ForEach-Object {$_|ConvertFrom-Json}|Where-Object phase -eq ('rpc:'+$target))
            Assert ($events.Count -gt 0 -and $events.Count -le 3) 'DeadlinePrecondition: missing request timestamps or excessive retries'
            if ($target -eq 'thread/resume') { Assert ($events.Count -eq 1) 'Ambiguous Resume timeout was retried without version-specific safety proof' }
            $intervals=@()
            for($i=0;$i -lt $events.Count;$i++) {
                $end=if($i+1 -lt $events.Count){$events[$i+1].ticks}else{$terminalTicks}
                $ms=($end-$events[$i].ticks)/10000.0;$intervals+=$ms
                Assert ($ms -ge 550 -and $ms -le 1700) ('700ms deadline outside 550..1700ms observation tolerance: '+$ms)
            }
            $expectedStarts=if($target -eq 'thread/start'){1}else{0}
            Assert (@((RPCs $s)|Where-Object method -eq 'thread/start').Count -eq $expectedStarts) 'Timeout provisioned replacement thread or retried provisioning'
            $expectedTurns=if($target -eq 'turn/start'){1}else{0}
            Assert (@((RPCs $s)|Where-Object method -eq 'turn/start').Count -eq $expectedTurns) 'Timeout replayed a turn'
            $e=Evidence $s;$e.rpcIntervalsMilliseconds=$intervals;$e.configuredDeadlineMilliseconds=700;$e.observationToleranceMilliseconds=@(550,1700)
            if($target -eq 'turn/start'){StopHost $h}else{Assert ($h.process.WaitForExit(6000)) 'Fail-closed host did not exit';RegisterRuntime $s}
            $e
        }
    }
    Check 'Window protection source decision for completed, timeout, error' {
        $path=Join-Path $repo 'scripts/delegation/Start-DelegatedCodexTask.ps1'
        $source=[IO.File]::ReadAllText($path,$utf8)
        Assert ($source.Contains("if (`$Role -ceq 'koordinator') { `$KeepWindowOpen = `$true }") -and $source.Contains("if (`$Role -cne 'koordinator' -and -not `$KeepWindowOpen")) 'Coordinator close guard absent'
        foreach($outcome in @('completed','timeout','error')) { $role='koordinator';$keep=$true;Assert (-not ($role -cne 'koordinator' -and -not $keep)) 'Synthetic close decision allowed' }
        @{evidenceClass='source-guard-and-synthetic-decision';source=$path;sha256=(Get-FileHash $path).Hash;actualWindowsTouched=$false;globalGuiLockProven=$false}
    }
} finally {
    $cleanupErrors=@()
    # Discover only runtimes identified by our own isolated workers before cleanup.
    foreach($spec in @($children | Where-Object {$_.config -and $_.config.identity} | ForEach-Object {$_.config})) {
        try { RegisterRuntime $spec } catch { if($_.Exception.Message -notmatch 'exist|vorhanden|ausgeführt|running'){ $cleanupErrors+=$_.Exception.Message } }
    }
    foreach($child in $children) {
        try { if(-not $child.process.HasExited){ Kill-Owned $child };if($child.name -ne 'owned-runtime'){$child.exitCode=$child.process.ExitCode} }
        catch {$cleanupErrors+=$_.Exception.Message}
        finally {if($child.input){$child.input.Dispose()}}
    }
    $hashAfter=@($hashPaths | ForEach-Object { @{path=$_;sha256=(Get-FileHash -LiteralPath $_ -Algorithm SHA256).Hash} })
    $changed=@($hashBefore|Where-Object {$before=$_;@($hashAfter|Where-Object {$_.path -ceq $before.path -and $_.sha256 -ceq $before.sha256}).Count -ne 1})
    if($changed.Count){$checks.Add(@{name='Source stability precondition';passed=$false;error='Source changed during execution: results require version-specific review';paths=@($changed|ForEach-Object {$_.path})})}
    $unmatched=@($Gate|Where-Object {$_ -notin @($checks|ForEach-Object {$_.name})})
    foreach($name in $unmatched){$checks.Add(@{name=$name;passed=$false;error='Unknown gate: no test executed'})}
    $summary=@{stage='host-integration';selectedGates=$Gate;testRoot=$root;passed=@($checks|Where-Object passed).Count;failed=@($checks|Where-Object {-not $_.passed}).Count;checks=@($checks.ToArray());cleanupErrors=$cleanupErrors;sourceHashesBefore=$hashBefore;sourceHashesAfter=$hashAfter;children=@($children|ForEach-Object {@{name=$_.name;pid=$_.pid;startedAtUtc=$_.startedAtUtc;killed=$_.killed;exitCode=$_.exitCode}});nativeCliExecuted=$false;mockOwnershipGate=$mockOwnershipGate;guiProtectionProven=$false}
    Save $summary $ResultPath
    foreach($child in $children){$child.process.Dispose()}
}
Write-Output (ConvertTo-Json @{stage=$summary.stage;passed=$summary.passed;failed=$summary.failed;cleanupErrors=$cleanupErrors.Count;resultPath=$ResultPath;mockOwnershipGate=$mockOwnershipGate;nativeCliExecuted=$false} -Compress)
if($summary.failed -or $cleanupErrors.Count){exit 1}
