param([string]$Config)
$ErrorActionPreference = 'Stop'
$c = Get-Content -LiteralPath $Config -Raw -Encoding UTF8 | ConvertFrom-Json
$utf8 = New-Object Text.UTF8Encoding($false, $true)
function Save($value, $path) { [IO.File]::WriteAllText($path, ($value | ConvertTo-Json -Depth 100), $utf8) }
function Wait-File($path) {
    $w = [Diagnostics.Stopwatch]::StartNew()
    while (-not [IO.File]::Exists($path)) {
        if ($w.ElapsedMilliseconds -gt 30000) { throw "Barrier timeout: $path" }
        Start-Sleep -Milliseconds 10
    }
}
try {
    $m = Import-Module $c.module -Force -PassThru
    switch ($c.mode) {
        'churn' {
            Save @{pid=$PID} $c.ready; Wait-File $c.go
            $failures=New-Object 'System.Collections.Generic.List[object]'
            for ($i=0; $i -lt 40; $i++) {
                $ctx=$null
                try { $ctx=& $m { param($p) Enter-WorkItemStoreLock $p 1000 } $c.store }
                catch { $failures.Add(@{iteration=$i;errorId=$_.FullyQualifiedErrorId;message=$_.Exception.Message}) }
                finally { if ($ctx) { & $m { param($x) Exit-WorkItemStoreLock $x } $ctx } }
            }
            Save @{pid=$PID;attempts=40;failures=$failures.ToArray()} $c.result
        }
        'race' {
            Save @{ pid=$PID } $c.ready
            Wait-File $c.go
            $ctx = $null
            try {
                $ctx = & $m { param($p) Enter-WorkItemStoreLock $p 0 } $c.store
                $actual = [Security.Principal.WindowsIdentity]::GetCurrent()
                $ctx.Stream.Position = 0
                $b = New-Object byte[] ([int]$ctx.Stream.Length)
                [void]$ctx.Stream.Read($b,0,$b.Length)
                $metadata = $utf8.GetString($b) | ConvertFrom-Json
                $identityOK = $metadata.processId -eq $PID -and $metadata.host -ceq [Environment]::MachineName -and $metadata.ownerSid -ceq $actual.User.Value -and $metadata.ownerName -ceq $actual.Name -and $metadata.processStartedAtUtc -ceq ([Diagnostics.Process]::GetCurrentProcess().StartTime.ToUniversalTime().ToString('o')) -and $metadata.lockId -ceq $ctx.LockId -and $metadata.storePath -ceq $c.store
                Save @{won=$true;pid=$PID;identityOK=$identityOK;metadata=$metadata} $c.result
                Wait-File $c.release
            } catch {
                Save @{won=$false;pid=$PID;errorId=$_.FullyQualifiedErrorId;message=$_.Exception.Message} $c.result
            } finally { if ($ctx) { & $m { param($x) Exit-WorkItemStoreLock $x } $ctx } }
        }
        'foreign' {
            $copy = Get-Content $c.context -Raw -Encoding UTF8 | ConvertFrom-Json
            $releaseId = ''; $deleteDenied = $false
            try { & $m { param($x) Exit-WorkItemStoreLock $x } $copy } catch { $releaseId=$_.FullyQualifiedErrorId }
            $idOnly=''; try { & $m { param($x) Exit-WorkItemStoreLock $x } $copy.LockId } catch { $idOnly=$_.FullyQualifiedErrorId }
            $copy.Released=$true
            $releasedCopy=''; try { & $m { param($x) Exit-WorkItemStoreLock $x } $copy } catch { $releasedCopy=$_.FullyQualifiedErrorId }
            try { [IO.File]::Delete($c.store + '.lock') } catch { $deleteDenied=$true }
            $w = [Diagnostics.Stopwatch]::StartNew(); $timeoutId=''
            try { & $m { param($p) Enter-WorkItemStoreLock $p 200 } $c.store } catch { $timeoutId=$_.FullyQualifiedErrorId }
            Save @{pid=$PID;releaseId=$releaseId;idOnlyError=$idOnly;releasedCopyError=$releasedCopy;deleteDenied=$deleteDenied;timeoutId=$timeoutId;elapsedMs=$w.ElapsedMilliseconds} $c.result
        }
        'writer' {
            $snapshot = & (Join-Path $c.repo 'scripts/Get-WorkItems.ps1') -Path $c.store -RepositoryRoot $c.repo
            Save @{revision=$snapshot.Revision;pid=$PID} $c.ready
            Wait-File $c.go
            $item = @($snapshot.Document.items | Where-Object id -eq $c.id)[0]
            $item.title = $c.title; $item.updatedAt='2026-10-12T11:00:00Z'
            try {
                $r = & (Join-Path $c.repo 'scripts/Set-WorkItem.ps1') -Path $c.store -RepositoryRoot $c.repo -Id $c.id -Item $item -ExpectedRevision $snapshot.Revision
                Save @{success=$true;revision=$r.Revision;pid=$PID} $c.result
            } catch {
                $conflict = $_.FullyQualifiedErrorId
                Save @{success=$false;errorId=$conflict;pid=$PID} $c.result
                if ($c.retry -and $conflict -match 'RevisionConflict') {
                    Wait-File $c.retryGo
                    $fresh = & (Join-Path $c.repo 'scripts/Get-WorkItems.ps1') -Path $c.store -RepositoryRoot $c.repo
                    $item = @($fresh.Document.items | Where-Object id -eq $c.id)[0]
                    $item.title=$c.title; $item.updatedAt='2026-10-12T11:01:00Z'
                    $r = & (Join-Path $c.repo 'scripts/Set-WorkItem.ps1') -Path $c.store -RepositoryRoot $c.repo -Id $c.id -Item $item -ExpectedRevision $fresh.Revision
                    Save @{success=$true;revision=$r.Revision;pid=$PID} $c.retryResult
                }
            }
        }
        'fault' {
            $s=Get-WorkItemStoreResult -Path $c.store -RepositoryRoot $c.repo -TimeoutMilliseconds 5000
            $item=$s.Document.items[1]; $item.title='published-fault-test'; $item.updatedAt='2026-10-12T11:00:00Z'
            $id=''
            try { Set-WorkItemStoreEntry -Path $c.store -Id $item.id -Item $item -IsNew $false -ExpectedRevision $s.Revision -RepositoryRoot $c.repo -TimeoutMilliseconds 5000 | Out-Null } catch { $id=$_.Exception.Message }
            Save @{failure=$id;pid=$PID} $c.result
        }
    }
} catch { Save @{fatal=$_.Exception.Message;errorId=$_.FullyQualifiedErrorId;pid=$PID} $c.result; exit 1 }
