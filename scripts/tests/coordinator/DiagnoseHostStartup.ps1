[CmdletBinding()]
param([Parameter(Mandatory=$true)][string]$ResultPath)
$ErrorActionPreference='Stop'
$utf8=New-Object Text.UTF8Encoding($false,$true)
$root=Join-Path ([IO.Path]::GetTempPath()) ('story16-qa-diagnostic-'+[guid]::NewGuid().ToString('N'))
[void][IO.Directory]::CreateDirectory($root)
$repo=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../..'))
$entry=Join-Path $repo 'scripts/Start-CoordinatorHost.ps1'
function Save($v,$p){[IO.File]::WriteAllText($p,(ConvertTo-Json -InputObject $v -Depth 25),$utf8)}
$mock=Join-Path $root 'mock.json';$config=Join-Path $root 'runtime.json'
Save @{testRoot=$root;mode='normal';journal=(Join-Path $root 'rpc.jsonl');identityPath=(Join-Path $root 'runtime.identity.json');turnDelayMilliseconds=0} $mock
Save @{RuntimeExecutable=(Join-Path $PSHOME 'powershell.exe');RuntimeArguments=@('-NoProfile','-ExecutionPolicy','Bypass','-File',(Join-Path $PSScriptRoot 'MockRuntime.ps1'),'-ConfigPath',$mock);WorkingDirectory=$root} $config
Save @{SchemaVersion=1;LogicalSessionId=[guid]::NewGuid().ToString('N');NativeThreadId='qa-persisted-thread';State='Ready';Revision=0;LastRequestId=$null;LastTurnId=$null;LastOutcome=$null;LastError=$null;LastUsage=$null;LastSource=$null;ResumeAttempts=0;Cwd=$root;AllowProvisioning=$true;OwnerPid=$null;OwnerStartedUtc=$null;RuntimePid=$null;RuntimeStartedAtUtc=$null;CreatedAtUtc=[DateTime]::UtcNow.ToString('o')} (Join-Path $root 'session.json')
$psi=New-Object Diagnostics.ProcessStartInfo
$psi.FileName=Join-Path $PSHOME 'powershell.exe'
$args=@('-NoProfile','-ExecutionPolicy','Bypass','-File',$entry,'-TestMode','-DataDirectory',$root,'-WorkingDirectory',$root,'-PipeName',('story16-qa-'+[guid]::NewGuid().ToString('N')),'-RuntimeConfigPath',$config,'-ReadyPath',(Join-Path $root 'ready'),'-ExitPath',(Join-Path $root 'stop'),'-ResumeRetryLimit','3','-RpcTimeoutMilliseconds','700')
$psi.Arguments=($args|ForEach-Object {'"'+$_+'"'}) -join ' '
$psi.UseShellExecute=$false;$psi.CreateNoWindow=$true;$psi.RedirectStandardOutput=$true;$psi.RedirectStandardError=$true
$p=[Diagnostics.Process]::Start($psi);$ticks=$p.StartTime.ToUniversalTime().Ticks
$identity=@{pid=$p.Id;startedAtUtc=$p.StartTime.ToUniversalTime().ToString('o')}
Save $identity (Join-Path $root 'host.identity.json')
$err=$p.StandardError.ReadToEndAsync();$out=$p.StandardOutput.ReadToEndAsync();$killed=$false
try {
    if(-not $p.WaitForExit(10000)) {
        [IO.File]::WriteAllText((Join-Path $root 'stop'),'stop',$utf8)
        if(-not $p.WaitForExit(4000)){
            $actual=[Diagnostics.Process]::GetProcessById($p.Id)
            try {if($actual.StartTime.ToUniversalTime().Ticks -ne $ticks){throw 'Own PID/start mismatch'};$actual.Kill();$killed=$true;[void]$p.WaitForExit(5000)}finally{$actual.Dispose()}
        }
    }
    $result=@{evidenceClass='real-isolated-TestMode-host/declared-runtime-config';testRoot=$root;host=$identity;exitCode=$p.ExitCode;killed=$killed;stderr=$err.Result;stdout=$out.Result;runtimeStarted=[IO.File]::Exists((Join-Path $root 'runtime.identity.json'));rpcJournalExists=[IO.File]::Exists((Join-Path $root 'rpc.jsonl'));source=@{path=$entry;sha256=(Get-FileHash $entry).Hash};session=([IO.File]::ReadAllText((Join-Path $root 'session.json'),$utf8)|ConvertFrom-Json);runtimeConfig=$config;arguments=$args}
    Save $result $ResultPath
    ConvertTo-Json @{exitCode=$result.exitCode;stderr=$result.stderr;runtimeStarted=$result.runtimeStarted;resultPath=$ResultPath} -Compress
}finally{$p.Dispose()}