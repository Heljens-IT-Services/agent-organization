[CmdletBinding()]
param([string]$ResultPath)
$ErrorActionPreference='Stop'
$repo=Split-Path -Parent $PSScriptRoot
$module=Join-Path $PSScriptRoot 'workitems/WorkItemStore.psm1'
$worker=Join-Path $PSScriptRoot 'tests/workitems/Worker.ps1'
$temp=Join-Path ([IO.Path]::GetTempPath()) ('workitem-store-qa-'+[guid]::NewGuid().ToString('N'))
[void][IO.Directory]::CreateDirectory($temp)
$utf8=New-Object Text.UTF8Encoding($false,$true)
$checks=New-Object 'System.Collections.Generic.List[object]'
$processes=New-Object 'System.Collections.Generic.List[object]'
$startHash=(Get-FileHash -LiteralPath $module -Algorithm SHA256).Hash
. (Join-Path $PSScriptRoot 'contracts/ContractValidation.ps1')
function Save($v,$p) { [IO.File]::WriteAllText($p,($v | ConvertTo-Json -Depth 100),$utf8) }
function Read($p) { Get-Content -LiteralPath $p -Raw -Encoding UTF8 | ConvertFrom-Json }
function Signal($p) { [IO.File]::WriteAllText($p,'go',$utf8) }
function Wait-File($p) { $w=[Diagnostics.Stopwatch]::StartNew(); while (-not [IO.File]::Exists($p)) { if ($w.ElapsedMilliseconds -gt 40000) { throw "Timeout: $p" }; Start-Sleep -Milliseconds 10 } }
function Assert($condition,$message) { if (-not $condition) { throw $message } }
function Check($name,[scriptblock]$action) {
    try { $detail=& $action; $checks.Add([pscustomobject]@{name=$name;passed=$true;detail=$detail}) }
    catch { $checks.Add([pscustomobject]@{name=$name;passed=$false;error=$_.Exception.Message;errorId=$_.FullyQualifiedErrorId}) }
}
function Spawn($config,$name) {
    $config.module=$module; $config.repo=$repo
    $path=Join-Path $temp ($name+'.config.json'); Save $config $path
    $psi=New-Object Diagnostics.ProcessStartInfo
    $psi.FileName='powershell.exe'; $psi.Arguments='-NoProfile -ExecutionPolicy Bypass -File "'+$worker+'" -Config "'+$path+'"'
    $psi.UseShellExecute=$false; $psi.CreateNoWindow=$true
    $p=[Diagnostics.Process]::Start($psi); $processes.Add($p); return $p
}
function Join-Worker($p) { if (-not $p.WaitForExit(40000)) { throw "Worker did not exit: $($p.Id)" }; Assert ($p.ExitCode -eq 0) "Worker exit $($p.ExitCode)" }
function Seed($name) { $p=Join-Path $temp ($name+'.json'); [IO.File]::Copy((Join-Path $repo 'examples/workitems/goal-with-children.json'),$p); return $p }
function Hash($p) { (Get-FileHash -LiteralPath $p -Algorithm SHA256).Hash }
function Get-Store($p) { & (Join-Path $PSScriptRoot 'Get-WorkItems.ps1') -Path $p -RepositoryRoot $repo }
function Set-Store($p,$item,$rev) { & (Join-Path $PSScriptRoot 'Set-WorkItem.ps1') -Path $p -Id $item.id -Item $item -ExpectedRevision $rev -RepositoryRoot $repo }
try {
    Check 'Lock race: barrier, timeout zero, exactly one winner, identity, reacquire' {
        $store=Join-Path $temp 'race.json'; $go=Join-Path $temp 'race.go'; $release=Join-Path $temp 'race.release'
        $a=@{mode='race';store=$store;go=$go;release=$release;ready=(Join-Path $temp 'a.ready');result=(Join-Path $temp 'a.result')}
        $b=@{mode='race';store=$store;go=$go;release=$release;ready=(Join-Path $temp 'b.ready');result=(Join-Path $temp 'b.result')}
        $pa=Spawn $a 'race-a'; $pb=Spawn $b 'race-b'
        Wait-File $a.ready; Wait-File $b.ready; Signal $go
        try {
            Wait-File $a.result; Wait-File $b.result
            $results=@((Read $a.result),(Read $b.result)); $winners=@($results | Where-Object won); $losers=@($results | Where-Object { -not $_.won })
            Assert ($winners.Count -eq 1 -and $losers.Count -eq 1) 'Expected one winner'
            Assert ($losers[0].errorId -match 'LockTimeout') ($losers[0] | ConvertTo-Json)
            Assert $winners[0].identityOK 'Actual lock identity mismatch'
        } finally { Signal $release }
        Join-Worker $pa; Join-Worker $pb
        $m=Import-Module $module -Force -PassThru
        & $m { param($p) $x=Enter-WorkItemStoreLock $p 0; Exit-WorkItemStoreLock $x } $store
        return $results
    }
    Check 'Foreign copied context and deletion denied; bounded wait' {
        $store=Join-Path $temp 'foreign.json'; $m=Import-Module $module -Force -PassThru
        $ctx=& $m { param($p) Enter-WorkItemStoreLock $p 0 } $store
        try {
            $copy=Join-Path $temp 'context.json'
            Save ($ctx | Select-Object LockId,StorePath,LockPath,OwnerSid,OwnerName,ProcessId,ProcessStartedAtUtc,Host,Released) $copy
            $c=@{mode='foreign';store=$store;context=$copy;result=(Join-Path $temp 'foreign.result')}
            $p=Spawn $c 'foreign'; Join-Worker $p; $r=Read $c.result
            Assert ($r.releaseId -match 'LockNotOwned' -and $r.deleteDenied -and $r.timeoutId -match 'LockTimeout') ($r | ConvertTo-Json)
            Assert ($r.idOnlyError -match 'LockNotOwned') 'ID-only foreign release was not rejected'
            Assert ($r.elapsedMs -ge 180 -and $r.elapsedMs -lt 2000) '200ms acquisition budget exceeded tolerance'
            Assert ($ctx.Stream.CanWrite -and [IO.File]::Exists($ctx.LockPath)) 'Owner lost active lock'
        } finally { & $m { param($x) Exit-WorkItemStoreLock $x } $ctx }
        Assert (-not [IO.File]::Exists($store+'.lock')) 'DeleteOnClose did not remove own lock'
        return $r
    }
    Check 'Forged Released=true context must still return LockNotOwned' {
        $r=Read (Join-Path $temp 'foreign.result')
        Assert ($r.releasedCopyError -match 'LockNotOwned') 'Foreign context with Released=true returned success instead of LockNotOwned (active handle remains protected)'
        return $r
    }
    Check 'CreateNew release window: bounded acquisition must not leak raw contention exceptions' {
        $store=Join-Path $temp 'churn.json'; $go=Join-Path $temp 'churn.go'
        $a=@{mode='churn';store=$store;go=$go;ready=(Join-Path $temp 'ca.ready');result=(Join-Path $temp 'ca.result')}
        $b=@{mode='churn';store=$store;go=$go;ready=(Join-Path $temp 'cb.ready');result=(Join-Path $temp 'cb.result')}
        $pa=Spawn $a 'churn-a'; $pb=Spawn $b 'churn-b'
        Wait-File $a.ready; Wait-File $b.ready; Signal $go; Join-Worker $pa; Join-Worker $pb
        $ar=Read $a.result; $br=Read $b.result
        $bad=@($ar.failures)+@($br.failures)
        Assert ($bad.Count -eq 0) ('Raw contention error in short held locks: '+($bad | ConvertTo-Json -Compress))
        return @{first=$ar;second=$br}
    }
    Check 'Public API bootstrap, duplicate ID, mismatch, idempotent Set, corrupt stored bytes' {
        $store=Join-Path $temp 'bootstrap.json'; $s=Get-Store $store
        Assert (-not $s.Exists -and $s.Revision -ceq 'absent' -and -not [IO.File]::Exists($store)) 'Get must not bootstrap missing file'
        $item=(Read (Join-Path $repo 'examples/workitems/goal-with-children.json')).items[0]
        $r=& (Join-Path $PSScriptRoot 'New-WorkItem.ps1') -Path $store -Item $item -ExpectedRevision 'absent' -RepositoryRoot $repo
        Assert ($r.Changed -and $r.Document.items.Count -eq 1) 'New did not create singleton store'
        $hash=Hash $store; $same=Set-Store $store $item $r.Revision
        Assert (-not $same.Changed -and $same.Revision -ceq $r.Revision -and (Hash $store) -ceq $hash) 'Identical Set rewrote target'
        $duplicate=''; try { & (Join-Path $PSScriptRoot 'New-WorkItem.ps1') -Path $store -Item $item -ExpectedRevision $r.Revision -RepositoryRoot $repo | Out-Null } catch { $duplicate=$_.FullyQualifiedErrorId }
        Assert ($duplicate -match 'DuplicateWorkItemId' -and (Hash $store) -ceq $hash) 'Duplicate ID was not safely rejected'
        $mismatch=''; try { & (Join-Path $PSScriptRoot 'Set-WorkItem.ps1') -Path $store -Id 'missing' -Item $item -ExpectedRevision $r.Revision -RepositoryRoot $repo | Out-Null } catch { $mismatch=$_.FullyQualifiedErrorId }
        Assert ($mismatch -match 'ItemNotFound' -and (Hash $store) -ceq $hash) 'Missing ID changed target'
        $wrong=Read (Join-Path $repo 'examples/workitems/goal-with-children.json'); $wrong.items[0].id='different'
        $mismatch=''; try { & (Join-Path $PSScriptRoot 'Set-WorkItem.ps1') -Path $store -Id 'goal' -Item $wrong.items[0] -ExpectedRevision $r.Revision -RepositoryRoot $repo | Out-Null } catch { $mismatch=$_.FullyQualifiedErrorId }
        Assert ($mismatch -match 'ItemIdMismatch' -and (Hash $store) -ceq $hash) 'ID mismatch changed target'
        $corrupt=Join-Path $temp 'corrupt.json'; [IO.File]::WriteAllBytes($corrupt,[byte[]]@(255,254,123)); $badHash=Hash $corrupt
        $bad=''; try { & (Join-Path $PSScriptRoot 'New-WorkItem.ps1') -Path $corrupt -Item $item -ExpectedRevision 'absent' -RepositoryRoot $repo | Out-Null } catch { $bad=$_.FullyQualifiedErrorId }
        Assert ($bad -match 'InvalidStoredDocument' -and (Hash $corrupt) -ceq $badHash) 'Corrupt bytes were replaced'
        return @{bootstrapRevision=$r.Revision;duplicateError=$duplicate;idMismatchError=$mismatch;corruptError=$bad;idempotentChanged=$same.Changed}
    }
    Check 'Two R0 processes: first R1, second conflict, fresh retry preserves both' {
        $store=Seed 'writers'
        $a=@{mode='writer';store=$store;id='task-a';title='writer-A';ready=(Join-Path $temp 'wa.ready');go=(Join-Path $temp 'wa.go');result=(Join-Path $temp 'wa.result');retry=$false}
        $b=@{mode='writer';store=$store;id='task-b';title='writer-B';ready=(Join-Path $temp 'wb.ready');go=(Join-Path $temp 'wb.go');result=(Join-Path $temp 'wb.result');retry=$true;retryGo=(Join-Path $temp 'wb.retry.go');retryResult=(Join-Path $temp 'wb.retry.result')}
        $pa=Spawn $a 'writer-a'; $pb=Spawn $b 'writer-b'; Wait-File $a.ready; Wait-File $b.ready
        Assert ((Read $a.ready).revision -ceq (Read $b.ready).revision) 'Writers did not read same R0'
        Signal $a.go; Wait-File $a.result; $ar=Read $a.result
        Assert $ar.success ($ar | ConvertTo-Json)
        $r1=Hash $store; Signal $b.go; Wait-File $b.result; $br=Read $b.result
        Assert ($br.errorId -match 'RevisionConflict') ($br | ConvertTo-Json)
        Assert ((Hash $store) -ceq $r1) 'Conflict changed target'
        Signal $b.retryGo; Join-Worker $pa; Join-Worker $pb
        $final=Get-Store $store
        Assert ($final.Document.items[1].title -ceq 'writer-A' -and $final.Document.items[2].title -ceq 'writer-B') 'Lost update after fresh retry'
        return @{first=$ar;second=$br;retry=(Read $b.retryResult);finalRevision=$final.Revision}
    }
    foreach ($case in @('schema','transition','timestamp','graph','stale')) {
        Check "Rejected $case leaves target byte-identical" {
            $store=Seed $case; $s=Get-Store $store; $before=Hash $store; $item=$s.Document.items[1]; $rev=$s.Revision
            $item.updatedAt='2026-10-12T11:00:00Z'
            switch ($case) {
                schema { $item.title=$false }
                transition { $item.status='accepted' }
                timestamp { $item.title='changed'; $item.updatedAt='2026-10-12T10:00:00Z' }
                graph { $item.dependencies=@('goal') }
                stale { $item.title='changed'; $rev='sha256:obsolete' }
            }
            $id=''; try { Set-Store $store $item $rev | Out-Null } catch { $id=$_.FullyQualifiedErrorId }
            $expected=if ($case -eq 'stale') {'RevisionConflict'} else {'ValidationFailed'}
            Assert ($id -match $expected) "Expected $expected, got $id"
            Assert ((Hash $store) -ceq $before) 'Rejected mutation changed bytes'
            return @{errorId=$id;unchangedHash=$before}
        }
    }
    Check 'File.Replace local .NET null backup succeeds; no target damage on sharing failure' {
        $p=Join-Path $temp 'replace.json'; $candidate=Join-Path $temp 'replace.tmp'
        Save @{version='old'} $p; Save @{version='new'} $candidate
        $old=Hash $p; $handle=New-Object IO.FileStream($p,[IO.FileMode]::Open,[IO.FileAccess]::Read,[IO.FileShare]::None)
        try { $failed=$false; try { [IO.File]::Replace($candidate,$p,[NullString]::Value) } catch { $failed=$true }; Assert $failed 'Replace unexpectedly bypassed exclusive handle' } finally { $handle.Dispose() }
        Assert ((Hash $p) -ceq $old) 'Failed replace changed target'
        [IO.File]::Replace($candidate,$p,[NullString]::Value)
        Assert ((Read $p).version -ceq 'new') 'Replace did not publish new JSON'
        Save @{version='next'} $candidate
        $plainNullError=''; $before=Hash $p
        try { [IO.File]::Replace($candidate,$p,$null) } catch { $plainNullError=$_.Exception.Message }
        if ($plainNullError) { Assert ((Hash $p) -ceq $before) 'Invalid PowerShell null backup changed target' }
        return @{volume=([IO.DriveInfo]::new([IO.Path]::GetPathRoot($p))).DriveFormat;nullBackup='NullString.Value';newHash=$before;plainPowerShellNullError=$plainNullError}
    }
    foreach ($stage in @('before','after')) {
        Check "Controlled abort $stage publication in isolated source copy" {
            $store=Seed ('fault-'+$stage); $oldHash=Hash $store
            $expected=Read $store; $expected.items[1].title='published-fault-test'; $expected.items[1].updatedAt='2026-10-12T11:00:00Z'
            $expectedPath=Join-Path $temp ('expected-'+$stage+'.json'); Save $expected $expectedPath; $newHash=Hash $expectedPath
            $source=[IO.File]::ReadAllText($module,$utf8)
            $needle='[IO.File]::Replace($candidate, $path, $backup)'
            Assert ($source.Contains($needle)) 'Publication seam changed: test instrumentation needs review'
            $throw='throw "QA controlled '+$stage+' publication"'
            $replacement=if ($stage -eq 'before') {$throw+"`r`n        "+$needle} else {$needle+"`r`n        "+$throw}
            $copy=Join-Path $temp ('Fault-'+$stage+'.psm1'); [IO.File]::WriteAllText($copy,$source.Replace($needle,$replacement),$utf8)
            $c=@{mode='fault';store=$store;result=(Join-Path $temp ('fault-'+$stage+'.result'))}
            $original=$module; $module=$copy
            try { $p=Spawn $c ('fault-'+$stage); Join-Worker $p } finally { $module=$original }
            $r=Read $c.result
            Assert ($r.failure -match [regex]::Escape('QA controlled '+$stage+' publication')) ($r | ConvertTo-Json)
            $parsed=Read-ContractJson $store
            if ($stage -eq 'before') { Assert ((Hash $store) -ceq $oldHash) 'Pre-publication abort changed target' }
            else { Assert ((Hash $store) -ceq $newHash) 'Post-publication abort did not leave byte-exact complete expected JSON' }
            $validated=& (Join-Path $PSScriptRoot 'Test-WorkItems.ps1') -Path $store -RepositoryRoot $repo
            Assert $validated.valid 'Abort left a contract-invalid document'
            return @{instrumentedCopy=$copy;failure=$r.failure;oldHash=$oldHash;expectedNewHash=$newHash;actualHash=(Hash $store);parseable=$true;contractValid=$true}
        }
    }
} finally {
    foreach ($p in $processes) { if (-not $p.HasExited) { $p.Kill(); $p.WaitForExit() } }
    $result=[pscustomobject]@{passed=(@($checks | Where-Object { -not $_.passed }).Count -eq 0);checkCount=$checks.Count;checks=$checks.ToArray();tempPath=$temp;recordedAtUtc=[DateTime]::UtcNow.ToString('o');powerShell=$PSVersionTable.PSVersion.ToString();sourceStartHash=$startHash;sourceHash=(Hash $module)}
    if ($ResultPath) { Save $result ([IO.Path]::GetFullPath($ResultPath)) }
    $result
}
if (-not $result.passed) { exit 1 }
