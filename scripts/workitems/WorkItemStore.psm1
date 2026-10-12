Set-StrictMode -Version 2

$script:WorkItemStoreLocks = @{}
$script:WorkItemStoreLockContexts = New-Object 'System.Collections.Generic.HashSet[object]'

function New-WorkItemStoreError {
    param([string]$ErrorId, [string]$Message)
    $exception = New-Object System.InvalidOperationException($Message)
    $record = New-Object System.Management.Automation.ErrorRecord($exception, $ErrorId, [System.Management.Automation.ErrorCategory]::InvalidOperation, $null)
    throw $record
}

function Resolve-WorkItemStorePath {
    param([string]$Path, [string]$RepositoryRoot)
    if ([string]::IsNullOrWhiteSpace($Path)) { $Path = Join-Path $RepositoryRoot 'runtime\workitems.json' }
    $full = [IO.Path]::GetFullPath($Path)
    $directory = [IO.Path]::GetDirectoryName($full)
    if (-not [IO.Directory]::Exists($directory)) { New-WorkItemStoreError 'StoreDirectoryMissing' "Store directory does not exist: $directory" }
    foreach ($candidate in @($directory, $(if ([IO.File]::Exists($full)) { $full }))) {
        if (-not $candidate) { continue }
        $attributes = [IO.File]::GetAttributes($candidate)
        if (($attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { New-WorkItemStoreError 'UnsafeStorePath' "Reparse points are not supported: $candidate" }
    }
    return $full
}

function Enter-WorkItemStoreLock {
    param([string]$StorePath, [int]$TimeoutMilliseconds = 5000)
    if ($TimeoutMilliseconds -lt 0 -or $TimeoutMilliseconds -gt 60000) { New-WorkItemStoreError 'InvalidTimeout' 'TimeoutMilliseconds must be between 0 and 60000.' }
    $lockPath = $StorePath + '.lock'
    $watch = [Diagnostics.Stopwatch]::StartNew()
    $lockId = [Guid]::NewGuid().ToString('D')
    while ($true) {
        $stream = $null
        try {
            $options = [IO.FileOptions]::DeleteOnClose
            $stream = New-Object IO.FileStream($lockPath, [IO.FileMode]::CreateNew, [IO.FileAccess]::ReadWrite, [IO.FileShare]::None, 4096, $options)
            $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
            $process = [Diagnostics.Process]::GetCurrentProcess()
            $metadata = [ordered]@{
                lockId = $lockId; storePath = $StorePath; acquiredAtUtc = [DateTime]::UtcNow.ToString('o')
                ownerSid = $identity.User.Value; ownerName = $identity.Name; processId = $PID
                processStartedAtUtc = $process.StartTime.ToUniversalTime().ToString('o'); host = [Environment]::MachineName
            }
            $json = ConvertTo-Json -InputObject $metadata -Depth 5 -Compress
            $bytes = (New-Object Text.UTF8Encoding($false, $true)).GetBytes($json)
            $stream.Write($bytes, 0, $bytes.Length)
            $stream.Flush($true)
            $context = [pscustomobject]@{ LockId = $lockId; StorePath = $StorePath; LockPath = $lockPath; Stream = $stream; OwnerSid = $identity.User.Value; OwnerName = $identity.Name; ProcessId = $PID; ProcessStartedAtUtc = $process.StartTime.ToUniversalTime().ToString('o'); Host = [Environment]::MachineName; Released = $false }
            $script:WorkItemStoreLocks[$lockId] = $context
            [void]$script:WorkItemStoreLockContexts.Add($context)
            return $context
        } catch [System.IO.IOException] {
            if ($null -ne $stream) { $stream.Dispose() }
            $isLockContention = $false
            $ioException = $_.Exception
            while ($null -ne $ioException) {
                $nativeCode = $ioException.HResult -band 0xFFFF
                if (($ioException -is [System.ComponentModel.Win32Exception] -and $ioException.NativeErrorCode -in @(32, 33, 80, 183)) -or $nativeCode -in @(32, 33, 80, 183)) {
                    $isLockContention = $true
                    break
                }
                $ioException = $ioException.InnerException
            }
            if (-not $isLockContention) { throw }
            $remaining = $TimeoutMilliseconds - [int]$watch.ElapsedMilliseconds
            if ($remaining -le 0) { New-WorkItemStoreError 'LockTimeout' "Timed out acquiring store lock '$lockPath' after ${TimeoutMilliseconds}ms." }
            Start-Sleep -Milliseconds ([Math]::Min($remaining, 50))
        } catch {
            if ($null -ne $stream) { $stream.Dispose() }
            throw
        }
    }
}

function Exit-WorkItemStoreLock {
    param([Parameter(Mandatory = $true)]$Context)
    if (-not $script:WorkItemStoreLockContexts.Contains($Context)) { New-WorkItemStoreError 'LockNotOwned' 'The lock context is not privately registered in this module.' }
    if ($null -ne $Context -and $Context.PSObject.Properties['Released'] -and $Context.Released -eq $true) { return }
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $process = [Diagnostics.Process]::GetCurrentProcess()
    $registered = $script:WorkItemStoreLocks[$Context.LockId]
    if (-not [object]::ReferenceEquals($registered, $Context) -or $Context.OwnerSid -cne $identity.User.Value -or $Context.OwnerName -cne $identity.Name -or $Context.ProcessId -ne $PID -or $Context.Host -cne [Environment]::MachineName -or $Context.ProcessStartedAtUtc -cne $process.StartTime.ToUniversalTime().ToString('o') -or $Context.StorePath -cne [IO.Path]::GetFullPath($Context.StorePath)) {
        New-WorkItemStoreError 'LockNotOwned' 'Lock ownership could not be verified against this process.'
    }
    $Context.Released = $true
    $Context.Stream.Dispose()
    [void]$script:WorkItemStoreLocks.Remove($Context.LockId)
}

function Get-WorkItemStoreSnapshot {
    param([string]$Path, [string]$RepositoryRoot)
    if (-not [IO.File]::Exists($Path)) { return [pscustomobject]@{ Document = $null; Revision = 'absent'; Exists = $false; Bytes = $null } }
    try {
        $bytes = [IO.File]::ReadAllBytes($Path)
        $decoder = New-Object Text.UTF8Encoding($false, $true)
        $json = $decoder.GetString($bytes)
        $document = ConvertFrom-Json -InputObject $json -ErrorAction Stop
    } catch { New-WorkItemStoreError 'InvalidStoredDocument' "Stored WorkItem document could not be decoded: $($_.Exception.Message)" }
    return [pscustomobject]@{ Document = $document; Revision = 'sha256:' + [BitConverter]::ToString(([Security.Cryptography.SHA256]::Create().ComputeHash($bytes))).Replace('-', '').ToLowerInvariant(); Exists = $true; Bytes = $bytes }
}

function Get-WorkItemStoreResult {
    param([string]$Path, [string]$RepositoryRoot, [int]$TimeoutMilliseconds)
    $path = Resolve-WorkItemStorePath $Path $RepositoryRoot
    $lock = Enter-WorkItemStoreLock $path $TimeoutMilliseconds
    try {
        $snapshot = Get-WorkItemStoreSnapshot $path $RepositoryRoot
        if ($snapshot.Exists) {
            $temporary = Join-Path ([IO.Path]::GetDirectoryName($path)) ('.' + [IO.Path]::GetFileName($path) + '.' + [Guid]::NewGuid().ToString('N') + '.read.tmp')
            try {
                [IO.File]::WriteAllBytes($temporary, $snapshot.Bytes)
                $validation = & (Join-Path $RepositoryRoot 'scripts\Test-WorkItems.ps1') -Path $temporary -RepositoryRoot $RepositoryRoot
                if (-not $validation.valid) { New-WorkItemStoreError 'InvalidStoredDocument' 'Stored WorkItem document failed contract validation.' }
            } finally { if ([IO.File]::Exists($temporary)) { [IO.File]::Delete($temporary) } }
        }
        return [pscustomobject]@{ Document = $snapshot.Document; Revision = $snapshot.Revision; Exists = $snapshot.Exists }
    } finally { Exit-WorkItemStoreLock $lock }
}

function ConvertTo-WorkItemStoreCandidate {
    param($Document)
    try {
        $json = ConvertTo-Json -InputObject $Document -Depth 100 -ErrorAction Stop
        return (New-Object Text.UTF8Encoding($false, $true)).GetBytes($json)
    } catch { New-WorkItemStoreError 'SerializationFailed' "WorkItem document serialization failed: $($_.Exception.Message)" }
}

function Set-WorkItemStoreEntry {
    param([string]$Path, [string]$Id, $Item, [bool]$IsNew, [string]$ExpectedRevision, [string]$RepositoryRoot, [int]$TimeoutMilliseconds)
    try { $Item = ConvertFrom-Json -InputObject (ConvertTo-Json -InputObject $Item -Depth 100 -ErrorAction Stop) -ErrorAction Stop } catch { New-WorkItemStoreError 'InvalidCandidate' "WorkItem item is not serializable JSON data: $($_.Exception.Message)" }
    $path = Resolve-WorkItemStorePath $Path $RepositoryRoot
    $lock = Enter-WorkItemStoreLock $path $TimeoutMilliseconds
    $previous = $null; $candidate = $null; $backup = $null
    try {
        $snapshot = Get-WorkItemStoreSnapshot $path $RepositoryRoot
        if ($snapshot.Exists) {
            $previous = Join-Path ([IO.Path]::GetDirectoryName($path)) ('.' + [IO.Path]::GetFileName($path) + '.' + $lock.LockId + '.' + [Guid]::NewGuid().ToString('N') + '.previous.tmp')
            [IO.File]::WriteAllBytes($previous, $snapshot.Bytes)
            try { $storedCheck = & (Join-Path $RepositoryRoot 'scripts\Test-WorkItems.ps1') -Path $previous -RepositoryRoot $RepositoryRoot } catch { New-WorkItemStoreError 'InvalidStoredDocument' "Stored WorkItem document failed validation: $($_.Exception.Message)" }
            if (-not $storedCheck.valid) { New-WorkItemStoreError 'InvalidStoredDocument' 'Stored WorkItem document failed contract validation.' }
        } elseif (-not $IsNew) { New-WorkItemStoreError 'ItemNotFound' "Cannot update missing WorkItem store: $path" }
        if ($snapshot.Revision -cne $ExpectedRevision) { New-WorkItemStoreError 'RevisionConflict' "Expected revision '$ExpectedRevision'; actual revision '$($snapshot.Revision)'." }
        if ($snapshot.Exists) { $items = @($snapshot.Document.items) } else { $items = @() }
        $matches = @($items | Where-Object { $_.id -ceq $Id })
        if ($IsNew -and $matches.Count -gt 0) { New-WorkItemStoreError 'DuplicateWorkItemId' "WorkItem ID already exists: $Id" }
        if (-not $IsNew -and $matches.Count -ne 1) { New-WorkItemStoreError 'ItemNotFound' "Expected exactly one existing WorkItem with ID '$Id'." }
        if ($Item.id -cne $Id) { New-WorkItemStoreError 'ItemIdMismatch' "Item.id must equal '$Id'." }
        if ($IsNew -and $Item.status -cne 'planned') { New-WorkItemStoreError 'NewItemMustBePlanned' 'New WorkItems must begin in planned status.' }
        if (-not $IsNew) {
            $oldJson = ConvertTo-Json -InputObject $matches[0] -Depth 100 -Compress
            $newJson = ConvertTo-Json -InputObject $Item -Depth 100 -Compress
            if ($oldJson -ceq $newJson) { return [pscustomobject]@{ Document = $snapshot.Document; Revision = $snapshot.Revision; Changed = $false; Id = $Id } }
        }
        $document = if ($snapshot.Exists) { ConvertFrom-Json -InputObject (ConvertTo-Json -InputObject $snapshot.Document -Depth 100) -ErrorAction Stop } else { [pscustomobject]@{ schemaVersion = '1.0'; items = @() } }
        if ($IsNew) { $document.items = @($document.items) + @($Item) }
        else {
            $replaceAt = -1
            for ($i = 0; $i -lt @($document.items).Count; $i++) { if ($document.items[$i].id -ceq $Id) { $replaceAt = $i; break } }
            $document.items[$replaceAt] = $Item
        }
        $candidateBytes = ConvertTo-WorkItemStoreCandidate $document
        $candidate = Join-Path ([IO.Path]::GetDirectoryName($path)) ('.' + [IO.Path]::GetFileName($path) + '.' + $lock.LockId + '.' + [Guid]::NewGuid().ToString('N') + '.candidate.tmp')
        $previousForValidator = $previous
        if (-not $snapshot.Exists) {
            $previousForValidator = Join-Path ([IO.Path]::GetDirectoryName($path)) ('.' + [IO.Path]::GetFileName($path) + '.' + $lock.LockId + '.' + [Guid]::NewGuid().ToString('N') + '.previous.tmp')
            [IO.File]::WriteAllText($previousForValidator, '{"schemaVersion":"1.0","items":[]}', (New-Object Text.UTF8Encoding($false, $true)))
            $previous = $previousForValidator
        }
        $stream = New-Object IO.FileStream($candidate, [IO.FileMode]::CreateNew, [IO.FileAccess]::Write, [IO.FileShare]::None)
        try { $stream.Write($candidateBytes, 0, $candidateBytes.Length); $stream.Flush($true) } finally { $stream.Dispose() }
        try { $validation = & (Join-Path $RepositoryRoot 'scripts\Test-WorkItems.ps1') -Path $candidate -PreviousPath $previousForValidator -RepositoryRoot $RepositoryRoot } catch { New-WorkItemStoreError 'ValidationFailed' "WorkItem transition validation failed: $($_.Exception.Message)" }
        if (-not $validation.valid -or -not $validation.transitionsChecked) { New-WorkItemStoreError 'ValidationFailed' 'Validator did not confirm a valid snapshot and checked transitions.' }
        $newRevision = 'sha256:' + [BitConverter]::ToString(([Security.Cryptography.SHA256]::Create().ComputeHash($candidateBytes))).Replace('-', '').ToLowerInvariant()
        if ($snapshot.Exists) {
            $backup = Join-Path ([IO.Path]::GetDirectoryName($path)) ('.' + [IO.Path]::GetFileName($path) + '.' + $lock.LockId + '.' + [Guid]::NewGuid().ToString('N') + '.replace-backup.tmp')
            try { [IO.File]::Replace($candidate, $path, $backup) } catch { New-WorkItemStoreError 'PublishFailed' "Atomic replacement failed: $($_.Exception.Message)" }
            try { [IO.File]::Delete($backup); $backup = $null } catch { Write-Error -ErrorId 'TemporaryCleanupFailed' -Message "Published successfully but could not remove own replacement backup '$backup': $($_.Exception.Message)" -ErrorAction Continue }
        } else {
            try { [IO.File]::Move($candidate, $path) } catch { New-WorkItemStoreError 'PublishFailed' "Atomic initial publication failed: $($_.Exception.Message)" }
        }
        $candidate = $null
        return [pscustomobject]@{ Document = $document; Revision = $newRevision; Changed = $true; Id = $Id }
    } finally {
        foreach ($temporary in @($previous, $candidate, $backup)) { if ($temporary -and [IO.File]::Exists($temporary)) { try { [IO.File]::Delete($temporary) } catch { Write-Error -ErrorId 'TemporaryCleanupFailed' -Message "Could not remove own temporary file '$temporary': $($_.Exception.Message)" -ErrorAction Continue } } }
        Exit-WorkItemStoreLock $lock
    }
}

Export-ModuleMember -Function Get-WorkItemStoreResult, Set-WorkItemStoreEntry
