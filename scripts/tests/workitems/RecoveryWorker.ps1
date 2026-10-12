param([Parameter(Mandatory=$true)][string]$Config)
$ErrorActionPreference='Stop'
$c=Get-Content -LiteralPath $Config -Raw -Encoding UTF8 | ConvertFrom-Json
$utf8=New-Object Text.UTF8Encoding($false,$true)
function Save($v,$p) {
    $tmp=$p+'.writing'; [IO.File]::WriteAllText($tmp,(ConvertTo-Json -InputObject $v -Depth 100),$utf8)
    [IO.File]::Move($tmp,$p)
}
function Wait-Barrier($p) {
    $watch=[Diagnostics.Stopwatch]::StartNew()
    while (-not [IO.File]::Exists($p)) {
        if ($watch.ElapsedMilliseconds -gt 90000) { throw "Barrier timeout: $p" }
        Start-Sleep -Milliseconds 10
    }
}
# Called only by the isolated source copies created by the recovery harness.
function global:Wait-QAPhase {
    Save @{pid=$PID;phase=$c.phase;atUtc=[DateTime]::UtcNow.ToString('o')} $c.phaseReady
    Wait-Barrier $c.phaseRelease
}
$identity=@{pid=$PID;startedAtUtc=[Diagnostics.Process]::GetCurrentProcess().StartTime.ToUniversalTime().ToString('o');host=[Environment]::MachineName}
try {
    $m=Import-Module $c.module -Force -PassThru
    switch ($c.mode) {
        'lock' {
            Save $identity $c.ready; Wait-Barrier $c.go
            $ctx=$null
            try {
                $ctx=& $m { param($p,$t) Enter-WorkItemStoreLock $p $t } $c.store $c.timeout
                $ctx.Stream.Position=0; $bytes=New-Object byte[] ([int]$ctx.Stream.Length)
                [void]$ctx.Stream.Read($bytes,0,$bytes.Length); $meta=$utf8.GetString($bytes) | ConvertFrom-Json
                if ($c.rewrite -ne 'none') {
                    $meta.acquiredAtUtc='2000-01-01T00:00:00Z'
                    if ($c.rewrite -eq 'dead') { $meta.processId=$c.deadPid; $meta.processStartedAtUtc=$c.deadStart }
                    $new=$utf8.GetBytes((ConvertTo-Json -InputObject $meta -Compress))
                    $ctx.Stream.Position=0; $ctx.Stream.SetLength(0); $ctx.Stream.Write($new,0,$new.Length); $ctx.Stream.Flush($true)
                }
                Save @{success=$true;identity=$identity;metadata=$meta} $c.result
                Wait-Barrier $c.release
                if (-not $ctx.Stream.CanWrite) { throw 'Owner stream stopped being writable' }
                $ctx.Stream.Position=0
                $ctx.Stream.Write($bytes,0,$bytes.Length)
                $ctx.Stream.Flush($true)
            } catch { Save @{success=$false;identity=$identity;errorId=$_.FullyQualifiedErrorId;message=$_.Exception.Message} $c.result }
            finally { if ($ctx) { & $m { param($x) Exit-WorkItemStoreLock $x } $ctx } }
        }
        'get' {
            $r=Get-WorkItemStoreResult -Path $c.store -RepositoryRoot $c.repo -TimeoutMilliseconds $c.timeout
            Save @{success=$true;identity=$identity;revision=$r.Revision;exists=$r.Exists;document=$r.Document} $c.result
        }
        'write' {
            $s=Get-WorkItemStoreResult -Path $c.store -RepositoryRoot $c.repo -TimeoutMilliseconds 5000
            if ($c.barrier) { Save @{identity=$identity;revision=$s.Revision} $c.ready; Wait-Barrier $c.go }
            if ($c.initial) { $item=(Get-Content (Join-Path $c.repo 'examples/workitems/goal-with-children.json') -Raw -Encoding UTF8 | ConvertFrom-Json).items[0] }
            else { $item=@($s.Document.items | Where-Object id -CEQ $c.id)[0]; $item.title=$c.title; $item.updatedAt='2026-10-12T11:00:00Z' }
            $r=Set-WorkItemStoreEntry -Path $c.store -Id $item.id -Item $item -IsNew ([bool]$c.initial) -ExpectedRevision $s.Revision -RepositoryRoot $c.repo -TimeoutMilliseconds 5000
            Save @{success=$true;identity=$identity;revision=$r.Revision;document=$r.Document} $c.result
        }
        'reject-write' {
            # Invoke the write path directly, so an invalid pre-read cannot mask write validation.
            $item=(Get-Content (Join-Path $c.repo 'examples/workitems/goal-with-children.json') -Raw -Encoding UTF8 | ConvertFrom-Json).items[0]
            $revision='sha256:'+(Get-FileHash -LiteralPath $c.store -Algorithm SHA256).Hash.ToLowerInvariant()
            $r=Set-WorkItemStoreEntry -Path $c.store -Id $item.id -Item $item -IsNew $true -ExpectedRevision $revision -RepositoryRoot $c.repo -TimeoutMilliseconds 5000
            Save @{success=$true;identity=$identity;revision=$r.Revision;document=$r.Document} $c.result
        }
        default { throw "Unknown recovery worker mode: $($c.mode)" }
    }
} catch { Save @{success=$false;identity=$identity;errorId=$_.FullyQualifiedErrorId;message=$_.Exception.Message} $c.result; exit 2 }
