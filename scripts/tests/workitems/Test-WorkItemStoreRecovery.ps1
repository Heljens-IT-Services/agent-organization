[CmdletBinding()]
param([string]$ResultPath)
$ErrorActionPreference='Stop'
$repo=(Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)))
$module=Join-Path $PSScriptRoot '../../workitems/WorkItemStore.psm1'
$worker=Join-Path $PSScriptRoot 'RecoveryWorker.ps1'
$temp=Join-Path ([IO.Path]::GetTempPath()) ('workitem-recovery-qa-'+[guid]::NewGuid().ToString('N'))
[void][IO.Directory]::CreateDirectory($temp)
$utf8=New-Object Text.UTF8Encoding($false,$true)
$checks=New-Object 'System.Collections.Generic.List[object]'
$children=New-Object 'System.Collections.Generic.List[object]'
$startHash=(Get-FileHash -LiteralPath $module -Algorithm SHA256).Hash
function Save($v,$p) { [IO.File]::WriteAllText($p,(ConvertTo-Json -InputObject $v -Depth 100),$utf8) }
function Read($p) { $utf8.GetString([IO.File]::ReadAllBytes($p)) | ConvertFrom-Json }
function Hash($p) { (Get-FileHash -LiteralPath $p -Algorithm SHA256).Hash }
function Signal($p) { [IO.File]::WriteAllText($p,'go',$utf8) }
function Wait-Barrier($p) {
    $watch=[Diagnostics.Stopwatch]::StartNew()
    while (-not [IO.File]::Exists($p)) {
        if ($watch.ElapsedMilliseconds -gt 30000) { throw "Barrier timeout: $p" }
        Start-Sleep -Milliseconds 10
    }
}
function Assert($ok,$why) { if (-not $ok) { throw $why } }
function Check($name,[scriptblock]$body) {
    try { $detail=& $body; $checks.Add(@{name=$name;passed=$true;detail=$detail}) }
    catch { $checks.Add(@{name=$name;passed=$false;error=$_.Exception.Message;errorId=$_.FullyQualifiedErrorId}) }
}
function Case($name,[bool]$seed=$true) {
    $dir=Join-Path $temp $name; [void][IO.Directory]::CreateDirectory($dir)
    $path=Join-Path $dir 'store.json'
    if ($seed) { [IO.File]::Copy((Join-Path $repo 'examples/workitems/goal-with-children.json'),$path) }
    return $path
}
function Inventory($store) {
    return @(Get-ChildItem -LiteralPath (Split-Path $store) -File | Sort-Object Name | ForEach-Object { @{name=$_.Name;length=$_.Length;hash=(Hash $_.FullName)} })
}
function Same-Inventory($a,$b) { Assert ((ConvertTo-Json -InputObject $a -Depth 10 -Compress) -ceq (ConvertTo-Json -InputObject $b -Depth 10 -Compress)) 'Preserved file inventory/bytes changed' }
function Spawn($config,$name) {
    if (-not $config.module) { $config.module=$module }; $config.repo=$repo
    $config.result=Join-Path $temp ($name+'.result.json')
    $path=Join-Path $temp ($name+'.config.json'); Save $config $path
    $psi=New-Object Diagnostics.ProcessStartInfo
    $psi.FileName='powershell.exe'; $psi.Arguments='-NoProfile -ExecutionPolicy Bypass -File "'+$worker+'" -Config "'+$path+'"'
    $psi.UseShellExecute=$false; $psi.CreateNoWindow=$true
    $process=[Diagnostics.Process]::Start($psi)
    $entry=@{name=$name;pid=$process.Id;startedAtUtc=$process.StartTime.ToUniversalTime().ToString('o');moduleHash=(Hash $config.module);killed=$false;exitCode=$null;process=$process;config=$config}
    $children.Add($entry); return $entry
}
function Join-Child($entry) {
    Assert ($entry.process.WaitForExit(30000)) "Child timeout: $($entry.pid)"
    $entry.exitCode=$entry.process.ExitCode; $entry.exitedAtUtc=[DateTime]::UtcNow.ToString('o')
}
function Kill-Child($entry) {
    Assert (-not $entry.process.HasExited) 'Child exited before external kill'
    $entry.killAtUtc=[DateTime]::UtcNow.ToString('o'); $entry.process.Kill(); $entry.killed=$true
    Join-Child $entry
    Assert ($entry.exitCode -ne 0) 'External kill had unexpected zero exit'
}
function Run($config,$name) {
    $entry=Spawn $config $name; Join-Child $entry
    Assert ([IO.File]::Exists($config.result)) "Missing worker result $name"
    $r=Read $config.result; $r | Add-Member -NotePropertyName exitCode -NotePropertyValue $entry.exitCode
    return $r
}
function Get($p,$name) { Run @{mode='get';store=$p;timeout=0} $name }
function Validate($p) {
    $null=$utf8.GetString([IO.File]::ReadAllBytes($p)) | ConvertFrom-Json
    $v=& (Join-Path $PSScriptRoot '../../workitems/Test-WorkItems.ps1') -Path $p -RepositoryRoot $repo
    Assert $v.valid 'Target contract invalid'
    return @{strictUtf8=$true;contractValid=$true;hash=(Hash $p);revision=('sha256:'+(Hash $p).ToLowerInvariant())}
}
function Lock-Config($p,$name,$go,$release,$rewrite='none') {
    return @{mode='lock';store=$p;timeout=0;rewrite=$rewrite;ready=(Join-Path $temp ($name+'.ready'));go=$go;release=$release;deadPid=$dead.processId;deadStart=$dead.processStartedAtUtc}
}
function Instrument($phase) {
    $source=[IO.File]::ReadAllText($module,$utf8)
    switch ($phase) {
        'partial-candidate' {
            $needle='New-WorkItemStoreExclusiveFile $candidate $candidateBytes'
            $replacement='$qaStream = New-Object IO.FileStream($candidate,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::None); $qaStream.Write($candidateBytes,0,[int]($candidateBytes.Length/2)); $qaStream.Flush($true); Wait-QAPhase; $qaStream.Dispose()'
        }
        'before-replace' { $needle='[IO.File]::Replace($candidate, $path, $backup)'; $replacement='Wait-QAPhase; '+$needle }
        'after-replace' { $needle='[IO.File]::Replace($candidate, $path, $backup)'; $replacement=$needle+'; Wait-QAPhase' }
        'before-move' { $needle='[IO.File]::Move($candidate, $path)'; $replacement='Wait-QAPhase; '+$needle }
        'after-move' { $needle='[IO.File]::Move($candidate, $path)'; $replacement=$needle+'; Wait-QAPhase' }
        'query-denied' { $needle='$process = [Diagnostics.Process]::GetProcessById($pidValue)'; $replacement='throw (New-Object System.ComponentModel.Win32Exception(5))' }
        default { throw "Unknown seam $phase" }
    }
    Assert (([regex]::Matches($source,[regex]::Escape($needle))).Count -eq 1) "Instrumentation seam changed: $phase"
    $copy=Join-Path $temp ($phase+'.psm1'); [IO.File]::WriteAllText($copy,$source.Replace($needle,$replacement),$utf8)
    return $copy
}
try {
    # Observe an actual live owner, then kill only this harness's process and await exit.
    $store=Case 'owner' $false; $go=Join-Path $temp 'owner.go'; $release=Join-Path $temp 'owner.release'
    $c=@{mode='lock';store=$store;timeout=0;rewrite='old';ready=(Join-Path $temp 'owner.ready');go=$go;release=$release}
    $owner=Spawn $c 'owner'; Wait-Barrier $c.ready; Signal $go; Wait-Barrier $c.result
    $observed=Read $c.result; Assert $observed.success 'Failed to acquire owner identity'; $dead=$observed.metadata
    Check 'Live exclusive handle with ancient acquisition stays writable across contender timeout' {
        $r=Get $store 'old-live-contender'; Assert ($r.errorId -match 'LockTimeout') ($r | ConvertTo-Json)
        Assert (-not $owner.process.HasExited) 'Owner died unexpectedly'; return $r
    }
    Check 'External kill of held DeleteOnClose lock and original-module restart' {
        Kill-Child $owner; Assert (-not [IO.File]::Exists($store+'.lock')) 'Killed process lock survived DeleteOnClose'
        $r=Get $store 'owner-restart'; Assert ($r.success -and -not $r.exists) ($r | ConvertTo-Json)
        return @{deadIdentity=$dead;pid=$owner.pid;exitCode=$owner.exitCode;restart=$r}
    }
    foreach ($kind in @('dead','pid-start-mismatch','live-free-old','foreign','legacy','missing-start','broken-start-live','broken-start-dead','broken-json','invalid-utf8','query-denied')) {
        Check "Persistent lock identity: $kind" {
            $p=Case ('identity-'+$kind); $meta=ConvertFrom-Json (ConvertTo-Json $dead)
            $meta.storePath=$p
            $live=[Diagnostics.Process]::GetCurrentProcess()
            switch ($kind) {
                'pid-start-mismatch' { $meta.processId=$PID; $meta.processStartedAtUtc=$live.StartTime.ToUniversalTime().AddYears(-1).ToString('o') }
                'live-free-old' { $meta.processId=$PID; $meta.processStartedAtUtc=$live.StartTime.ToUniversalTime().ToString('o') }
                'foreign' { $meta.machineGuid='foreign-installation' }
                'legacy' { $meta.PSObject.Properties.Remove('machineGuid') }
                'missing-start' { $meta.PSObject.Properties.Remove('processStartedAtUtc') }
                'broken-start-live' { $meta.processId=$PID; $meta.processStartedAtUtc='not-a-date' }
                'broken-start-dead' { $meta.processStartedAtUtc='not-a-date' }
            }
            Save $meta ($p+'.lock')
            if ($kind -eq 'broken-json') { [IO.File]::WriteAllText($p+'.lock','{"processId":',$utf8) }
            if ($kind -eq 'invalid-utf8') { [IO.File]::WriteAllBytes($p+'.lock',[byte[]]@(195,40)) }
            $before=Inventory $p; $config=@{mode='get';store=$p;timeout=0}
            if ($kind -eq 'query-denied') { $config.module=Instrument 'query-denied' }
            $r=Run $config ('inspect-'+$kind); $after=Inventory $p
            $expected=if ($kind -in @('dead','pid-start-mismatch')) { 'success' } elseif ($kind -eq 'live-free-old') { 'LockTimeout' } else { 'LockOwnerUncertain' }
            # Persist evidence even when the assertion exposes a production defect.
            Save @{expected=$expected;actual=$r;before=$before;after=$after;fixtureIdentity=$meta} (Join-Path $temp ($kind+'.evidence.json'))
            if ($expected -eq 'success') { Assert $r.success ($r | ConvertTo-Json); Assert (-not [IO.File]::Exists($p+'.lock')) 'Dead fixture remained'; Assert ((Hash $p) -ceq $before[0].hash) 'Store changed on recovery' }
            else { Assert ($r.errorId -match $expected) "Expected $expected, got $($r.errorId)"; Same-Inventory $before $after }
            return @{expected=$expected;actual=$r;before=$before;after=$after;fixtureIdentity=$meta}
        }
    }
    foreach ($type in @('normal','recovery')) {
        Check "Two true processes compete at $type lock barrier" {
            $p=Case ('race-'+$type)
            if ($type -eq 'recovery') { Save $dead ($p+'.lock') }
            $go=Join-Path $temp ($type+'.go'); $release=Join-Path $temp ($type+'.release')
            $a=Lock-Config $p ($type+'-a') $go $release; $b=Lock-Config $p ($type+'-b') $go $release
            $pa=Spawn $a ($type+'-a'); $pb=Spawn $b ($type+'-b')
            try {
                Wait-Barrier $a.ready; Wait-Barrier $b.ready; Signal $go
                Wait-Barrier $a.result; Wait-Barrier $b.result
                $r=@((Read $a.result),(Read $b.result)); $wins=@($r | Where-Object success); $loss=@($r | Where-Object { -not $_.success })
                Assert ($wins.Count -eq 1 -and $loss.Count -eq 1 -and $loss[0].errorId -match 'LockTimeout') ($r | ConvertTo-Json -Depth 8)
            } finally { Signal $release; Join-Child $pa; Join-Child $pb }
            $re=Get $p ($type+'-reacquire'); Assert $re.success 'Could not reacquire after winner release'
            return @{results=$r;reacquire=$re;validated=(Validate $p)}
        }
    }
    Check 'Exclusive live handle protects even misleading dead owner metadata' {
        $p=Case 'misleading'; $go=Join-Path $temp 'misleading.go'; $release=Join-Path $temp 'misleading.release'
        $c=Lock-Config $p 'misleading' $go $release 'dead'; $entry=Spawn $c 'misleading'
        try { Wait-Barrier $c.ready; Signal $go; Wait-Barrier $c.result; $r=Get $p 'misleading-contender'; Assert ($r.errorId -match 'LockTimeout') ($r | ConvertTo-Json) }
        finally { Signal $release; Join-Child $entry }
        Assert ($entry.exitCode -eq 0) 'Live owner failed after contender'; return $r
    }
    Check 'Two actual R0 writers, unchanged conflict bytes and new-process fresh retry without loss' {
        $p=Case 'writers'; $r0=Hash $p
        $a=@{mode='write';store=$p;id='task-a';title='writer-A';initial=$false;barrier=$true;ready=(Join-Path $temp 'writer-a.ready');go=(Join-Path $temp 'writer-a.go')}
        $b=@{mode='write';store=$p;id='task-b';title='writer-B';initial=$false;barrier=$true;ready=(Join-Path $temp 'writer-b.ready');go=(Join-Path $temp 'writer-b.go')}
        $pa=Spawn $a 'writer-a'; $pb=Spawn $b 'writer-b'; Wait-Barrier $a.ready; Wait-Barrier $b.ready
        Assert ((Read $a.ready).revision -ceq (Read $b.ready).revision) 'Writers did not share R0'
        Signal $a.go; Join-Child $pa; $ar=Read $a.result; Assert $ar.success 'Writer A failed'; $r1=Hash $p
        Signal $b.go; Join-Child $pb; $br=Read $b.result; Assert ($br.errorId -match 'RevisionConflict' -and (Hash $p) -ceq $r1) 'Stale writer changed bytes'
        $retry=Run @{mode='write';store=$p;id='task-b';title='writer-B';initial=$false;barrier=$false} 'writer-retry'
        Assert $retry.success 'Fresh retry failed'; $final=Get $p 'writers-final'
        Assert ($final.document.items[1].title -ceq 'writer-A' -and $final.document.items[2].title -ceq 'writer-B') 'Lost update'
        return @{r0=$r0;r1=$r1;first=$ar;stale=$br;retry=$retry;final=$final;validated=(Validate $p)}
    }
    foreach ($kind in @('utf8','json','schema')) {
        Check "Invalid stored $kind stays byte-identical on read and write" {
            $p=Case ('invalid-'+$kind)
            switch ($kind) { utf8 { [IO.File]::WriteAllBytes($p,[byte[]]@(195,40)) }; json { [IO.File]::WriteAllText($p,'{"items":',$utf8) }; schema { Save @{schemaVersion='unsupported';items=@()} $p } }
            $before=Inventory $p; $r=Get $p ('invalid-read-'+$kind)
            $w=Run @{mode='reject-write';store=$p} ('invalid-write-'+$kind)
            $after=Inventory $p
            $expectedError=if ($kind -eq 'schema') { 'Schema const at $.schemaVersion' } else { 'InvalidStoredDocument' }
            Save @{expectedReadError=$expectedError;expectedWriteError='InvalidStoredDocument';read=$r;write=$w;before=$before;after=$after} (Join-Path $temp ('invalid-'+$kind+'.evidence.json'))
            Assert (-not $r.success -and -not $w.success -and $r.exitCode -eq 2 -and $w.exitCode -eq 2) 'Invalid stored document was accepted'
            Assert ($r.errorId -ceq $expectedError -and $w.errorId -ceq 'InvalidStoredDocument') 'Unexpected stored document rejection'
            Same-Inventory $before $after; return @{expectedReadError=$expectedError;expectedWriteError='InvalidStoredDocument';read=$r;write=$w;preserved=$before}
        }
    }
    foreach ($phase in @('partial-candidate','before-replace','after-replace','before-move','after-move')) {
        Check "External kill at $phase barrier; original-module new-process restart" {
            $initial=$phase -match 'move'; $p=Case ('kill-'+$phase) (-not $initial)
            $oldHash=if ($initial) { 'absent' } else { Hash $p }
            if ($initial) { $expected=[pscustomobject][ordered]@{schemaVersion='1.0';items=@((Read (Join-Path $repo 'examples/workitems/goal-with-children.json')).items[0])} }
            else { $expected=Read $p; $expected.items[1].title='crash-change'; $expected.items[1].updatedAt='2026-10-12T11:00:00Z' }
            $expectedPath=Join-Path $temp ($phase+'.expected.json'); Save $expected $expectedPath; $newHash=Hash $expectedPath
            # Foreign artifacts include matching publishing patterns and another store's artifacts.
            $foreign=Join-Path (Split-Path $p) '.store.json.foreign.replace-backup.tmp'; Save @{foreign='do not overwrite'} $foreign
            if ($initial) { [IO.File]::Move($foreign,(Join-Path (Split-Path $p) '.other.json.foreign.replace-backup.tmp')); $foreign=Join-Path (Split-Path $p) '.other.json.foreign.replace-backup.tmp' }
            $foreignHash=Hash $foreign
            $c=@{mode='write';store=$p;id='task-a';title='crash-change';initial=$initial;barrier=$false;module=(Instrument $phase);phase=$phase;phaseReady=(Join-Path $temp ($phase+'.phase'));phaseRelease=(Join-Path $temp ($phase+'.release'))}
            $entry=Spawn $c ('kill-'+$phase); Wait-Barrier $c.phaseReady
            $barrier=Read $c.phaseReady; Assert ($barrier.pid -eq $entry.pid) 'Wrong phase process'
            Kill-Child $entry; Assert (-not [IO.File]::Exists($c.result)) 'Killed worker returned a regular result'
            $afterKill=Inventory $p
            $committed=$phase -in @('after-replace','after-move')
            $actual=if ([IO.File]::Exists($p)) { Hash $p } else { 'absent' }
            Save @{phase=$barrier;oldHash=$oldHash;expectedNewHash=$newHash;actualHash=$actual;afterKill=$afterKill;exitCode=$entry.exitCode} (Join-Path $temp ($phase+'.evidence.json'))
            Assert ($actual -ceq $(if ($committed) { $newHash } else { $oldHash })) "Unexpected target hash at $phase"
            $validated=if ($actual -ne 'absent') { Validate $p } else { $null }
            $restart=Get $p ($phase+'-restart')
            if ($actual -eq 'absent') {
                Assert ($restart.errorId -match 'StoreRecoveryRequired') 'Missing store with publishing artifacts was accepted'
                $write=Run @{mode='write';store=$p;initial=$true;barrier=$false} ($phase+'-restart-write')
                Assert ($write.errorId -match 'StoreRecoveryRequired') 'Missing store with artifacts was bootstrapped'
            } else {
                Assert ($restart.success -and $restart.revision -ceq ('sha256:'+$actual.ToLowerInvariant())) 'Restart changed authoritative revision'
            }
            Same-Inventory $afterKill (Inventory $p); Assert ((Hash $foreign) -ceq $foreignHash) 'Foreign artifact modified'
            $candidate=@($afterKill | Where-Object { $_.name -like '*.candidate.tmp' })
            if ($phase -eq 'partial-candidate') { Assert ($candidate.Count -eq 1 -and $candidate[0].hash -cne $newHash) 'Partial candidate not evidenced' }
            $continued=$null
            if ($actual -ne 'absent') {
                $continued=Run @{mode='write';store=$p;id=$(if ($initial) {'goal'} else {'task-b'});title='restart-change';initial=$false;barrier=$false} ($phase+'-continue')
                Assert $continued.success 'Restart write failed'
                if ($phase -eq 'after-replace') { Assert ($continued.document.items[1].title -ceq 'crash-change') 'Restart lost committed change' }
                $null=Validate $p
                Assert ((Hash $foreign) -ceq $foreignHash) 'Foreign artifact changed during continuation'
                foreach ($artifact in @($afterKill | Where-Object name -ne 'store.json')) { Assert ((Hash (Join-Path (Split-Path $p) $artifact.name)) -ceq $artifact.hash) 'Restart mutation removed old crash artifacts' }
            }
            return @{phase=$barrier;pid=$entry.pid;externalKill=$true;exitCode=$entry.exitCode;oldHash=$oldHash;newHash=$newHash;actualHash=$actual;strictValidation=$validated;afterKill=$afterKill;restart=$restart;continued=$continued;finalInventory=(Inventory $p);instrumentedHash=(Hash $c.module);restartModuleHash=$startHash}
        }
    }
    Check 'Valid R1 plus valid old backup stays R1; unrelated artifacts retained' {
        $p=Case 'old-backup'; $r0=[IO.File]::ReadAllBytes($p)
        $w=Run @{mode='write';store=$p;id='task-a';title='authoritative-R1';initial=$false;barrier=$false} 'backup-create-r1'; Assert $w.success 'R1 write failed'
        [IO.File]::WriteAllBytes((Join-Path (Split-Path $p) '.store.json.old.replace-backup.tmp'),$r0)
        [IO.File]::WriteAllBytes((Join-Path (Split-Path $p) '.other.json.foreign.candidate.tmp'),[byte[]]@(195,40))
        $before=Inventory $p; $r=Get $p 'backup-restart'; Assert ($r.success -and $r.document.items[1].title -ceq 'authoritative-R1') 'Backup rolled back R1'
        Same-Inventory $before (Inventory $p); return @{read=$r;inventory=$before;validated=(Validate $p)}
    }
    Check 'Independent operations guide: persistent local path, public callers and conservative uncertainty' {
        $directory=Join-Path $env:LOCALAPPDATA ('Heljens/WorkItems-QA-'+[guid]::NewGuid().ToString('N'))
        [void][IO.Directory]::CreateDirectory($directory)
        $p=Join-Path $directory 'workitems.json'
        Assert (([IO.DriveInfo]::new([IO.Path]::GetPathRoot($p))).DriveFormat -ceq 'NTFS') 'Guide requires local NTFS'
        $s=& (Join-Path $PSScriptRoot '../../workitems/Get-WorkItems.ps1') -Path $p -RepositoryRoot $repo
        Assert (-not $s.Exists -and $s.Revision -ceq 'absent' -and -not [IO.File]::Exists($p)) 'Guide read bootstrapped store'
        $item=(Read (Join-Path $repo 'examples/workitems/goal-with-children.json')).items[0]
        $created=& (Join-Path $PSScriptRoot '../../workitems/New-WorkItem.ps1') -Path $p -Item $item -ExpectedRevision $s.Revision -RepositoryRoot $repo
        $fresh=& (Join-Path $PSScriptRoot '../../workitems/Get-WorkItems.ps1') -Path $p -RepositoryRoot $repo
        $item=$fresh.Document.items[0]; $item.title='persistent-guide-change'; $item.updatedAt='2026-10-12T11:00:00Z'
        $changed=& (Join-Path $PSScriptRoot '../../workitems/Set-WorkItem.ps1') -Path $p -Id $item.id -Item $item -ExpectedRevision $fresh.Revision -RepositoryRoot $repo
        $restart=Get $p 'guide-new-process'
        Assert ($restart.success -and $restart.revision -ceq $changed.Revision -and $restart.document.items[0].title -ceq 'persistent-guide-change') 'Persistent guide restart lost change'
        $meta=ConvertFrom-Json (ConvertTo-Json $dead); $meta.storePath=$p; $meta.processStartedAtUtc='not-a-date'; Save $meta ($p+'.lock')
        $before=Inventory $p; $r=Get $p 'guide-uncertain'
        Assert (-not $r.success -and $r.errorId -match 'LockOwnerUncertain' -and $r.exitCode -eq 2) 'Guide uncertain lock not protected'
        Same-Inventory $before (Inventory $p)
        $backup=Join-Path $directory 'manual-clarification-copy'; [void][IO.Directory]::CreateDirectory($backup)
        foreach ($file in $before) { [IO.File]::Copy((Join-Path $directory $file.name),(Join-Path $backup $file.name)); Assert ((Hash (Join-Path $backup $file.name)) -ceq $file.hash) 'Guide backup differs' }
        return @{persistentDirectory=$directory;repositoryRoot=$repo;initialRevision=$s.Revision;createdRevision=$created.Revision;changedRevision=$changed.Revision;restart=$restart;uncertainty=$r;preserved=$before;backupDirectory=$backup;validated=(Validate $p);manualRecoveryPerformed=$false}
    }
} finally {
    foreach ($entry in $children) { if (-not $entry.process.HasExited) { Kill-Child $entry; $entry.cleanupKill=$true }; if ($null -eq $entry.exitCode) { Join-Child $entry } }
    $processEvidence=@($children | ForEach-Object { $e=@{}; foreach ($key in $_.Keys) { if ($key -notin @('process','config')) { $e[$key]=$_[$key] } }; $e })
    $endHash=Hash $module
    $result=@{passed=(@($checks | Where-Object { -not $_.passed }).Count -eq 0 -and $startHash -ceq $endHash);checkCount=$checks.Count;passedCount=@($checks | Where-Object passed).Count;failedCount=@($checks | Where-Object { -not $_.passed }).Count;checks=$checks.ToArray();processes=$processEvidence;tempPath=$temp;sourceStartHash=$startHash;sourceEndHash=$endHash;powerShell=$PSVersionTable.PSVersion.ToString();os=[Environment]::OSVersion.VersionString;volume=([IO.DriveInfo]::new([IO.Path]::GetPathRoot($temp))).DriveFormat;recordedAtUtc=[DateTime]::UtcNow.ToString('o');limits=@('Local Windows filesystem, cooperating callers only','No power loss, reboot, storage failure or exact interruption inside the native atomic API','PID reuse simulated with actual PID and deliberately different start; no observed OS PID reuse','AccessDenied query injected in isolated copy; not an actual OS access denial')}
    if ($ResultPath) { Save $result ([IO.Path]::GetFullPath($ResultPath)) }
    [pscustomobject]$result
}
if (-not $result.passed) { exit 1 }
