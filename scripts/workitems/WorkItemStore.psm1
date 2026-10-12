Set-StrictMode -Version 2

$script:WorkItemStoreLocks = @{}
$script:WorkItemStoreLockContexts = New-Object 'System.Collections.Generic.HashSet[object]'

# Keep the interop type in the AppDomain across Import-Module -Force.
if (-not ('WorkItemStoreNativeLock' -as [type])) {
    Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
using Microsoft.Win32.SafeHandles;
public static class WorkItemStoreNativeLock {
  [StructLayout(LayoutKind.Sequential)] public struct FILE_DISPOSITION_INFO { [MarshalAs(UnmanagedType.Bool)] public bool DeleteFile; }
  [DllImport("kernel32.dll", CharSet=CharSet.Unicode, SetLastError=true)]
  public static extern SafeFileHandle CreateFile(string name, uint access, uint share, IntPtr security, uint creation, uint flags, IntPtr template);
  [DllImport("kernel32.dll", SetLastError=true)]
  public static extern bool SetFileInformationByHandle(SafeFileHandle handle, int infoClass, ref FILE_DISPOSITION_INFO info, uint size);
}
'@
}

function Get-WorkItemStoreMachineGuid {
    try { $value = (Get-ItemProperty -LiteralPath 'HKLM:\SOFTWARE\Microsoft\Cryptography' -Name MachineGuid -ErrorAction Stop).MachineGuid }
    catch { New-WorkItemStoreError 'LockIdentityUnavailable' "Cannot read this machine's Windows MachineGuid: $($_.Exception.Message)" }
    if ([string]::IsNullOrWhiteSpace([string]$value)) { New-WorkItemStoreError 'LockIdentityUnavailable' 'Windows MachineGuid is empty.' }
    return ([string]$value).Trim().ToLowerInvariant()
}

function Get-WorkItemStoreLockArtifacts {
    param([string]$StorePath)
    $directory = [IO.Path]::GetDirectoryName($StorePath); $base = [IO.Path]::GetFileName($StorePath)
    return @(Get-ChildItem -LiteralPath $directory -File -Force | Where-Object { $_.Name -like ".$base.*.read.tmp" -or $_.Name -like ".$base.*.previous.tmp" -or $_.Name -like ".$base.*.candidate.tmp" -or $_.Name -like ".$base.*.replace-backup.tmp" })
}

function New-WorkItemStoreExclusiveFile {
    param([string]$Path, [byte[]]$Bytes)
    $stream = New-Object IO.FileStream($Path, [IO.FileMode]::CreateNew, [IO.FileAccess]::Write, [IO.FileShare]::None)
    try { $stream.Write($Bytes, 0, $Bytes.Length); $stream.Flush($true) } finally { $stream.Dispose() }
}

function Test-WorkItemStoreLockOwnerDead {
    param([string]$LockPath)
    $handle = [WorkItemStoreNativeLock]::CreateFile($LockPath, [uint32]2147549184, 0, [IntPtr]::Zero, 3, 0x80, [IntPtr]::Zero)
    if ($handle.IsInvalid) {
        $code = [Runtime.InteropServices.Marshal]::GetLastWin32Error(); $handle.Dispose()
        if ($code -in @(2,3)) { return 'Missing' }
        if ($code -in @(32,33,80,183)) { return 'Protected' }
        New-WorkItemStoreError 'LockOwnerUncertain' "Cannot inspect lock '$LockPath' safely (Win32 $code); lock retained for manual clarification."
    }
    $stream = $null
    try {
        $stream = New-Object IO.FileStream($handle, [IO.FileAccess]::Read)
        $memory = New-Object IO.MemoryStream
        try { $stream.CopyTo($memory); $raw = (New-Object Text.UTF8Encoding($false,$true)).GetString($memory.ToArray()); $meta = ConvertFrom-Json -InputObject $raw -ErrorAction Stop } finally { $memory.Dispose() }
        if ($meta.machineGuid -cne (Get-WorkItemStoreMachineGuid) -or $meta.host -cne [Environment]::MachineName -or -not $meta.processId -or -not $meta.processStartedAtUtc) {
            New-WorkItemStoreError 'LockOwnerUncertain' "Lock '$LockPath' has legacy, foreign, or incomplete owner identity; preserve it and verify host/PID/start manually."
        }
        $pidValue = 0
        if (-not [int]::TryParse([string]$meta.processId, [Globalization.NumberStyles]::None, [Globalization.CultureInfo]::InvariantCulture, [ref]$pidValue) -or $pidValue -le 0) { New-WorkItemStoreError 'LockOwnerUncertain' "Lock '$LockPath' contains an invalid PID; preserve it for manual clarification." }
        $expectedStart = [DateTimeOffset]::MinValue
        if (-not [DateTimeOffset]::TryParse([string]$meta.processStartedAtUtc, [Globalization.CultureInfo]::InvariantCulture, [Globalization.DateTimeStyles]::RoundtripKind, [ref]$expectedStart) -or $expectedStart.Offset -ne [TimeSpan]::Zero) { New-WorkItemStoreError 'LockOwnerUncertain' "Lock '$LockPath' contains an invalid or non-UTC process start time; preserve it for manual clarification." }
        $dead = $false
        try {
            $process = [Diagnostics.Process]::GetProcessById($pidValue)
            try {
                $actual = $process.StartTime.ToUniversalTime()
                if ($actual.Ticks -eq $expectedStart.UtcDateTime.Ticks) { return 'Protected' }
                $dead = $true
            } finally { $process.Dispose() }
        } catch [ArgumentException] { $dead = $true }
          catch { New-WorkItemStoreError 'LockOwnerUncertain' "Cannot reliably query PID $pidValue for lock '$LockPath': $($_.Exception.Message); lock retained." }
        if (-not $dead) { return 'Protected' }
        $info = New-Object WorkItemStoreNativeLock+FILE_DISPOSITION_INFO
        $info.DeleteFile = $true
        if (-not [WorkItemStoreNativeLock]::SetFileInformationByHandle($handle, 4, [ref]$info, [uint32][Runtime.InteropServices.Marshal]::SizeOf([type][WorkItemStoreNativeLock+FILE_DISPOSITION_INFO]))) {
            $code = [Runtime.InteropServices.Marshal]::GetLastWin32Error(); New-WorkItemStoreError 'LockOwnerUncertain' "Confirmed dead lock owner but could not mark the inspected handle for deletion (Win32 $code); lock retained."
        }
        return 'Reaped'
    } catch { if ($_.FullyQualifiedErrorId -match 'LockOwnerUncertain') { throw }; New-WorkItemStoreError 'LockOwnerUncertain' "Lock '$LockPath' metadata is unreadable or ambiguous: $($_.Exception.Message); lock retained." }
    finally { if ($null -ne $stream) { $stream.Dispose() } else { $handle.Dispose() } }
}

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
            $machineGuid = Get-WorkItemStoreMachineGuid
            $metadata = [ordered]@{
                lockId = $lockId; storePath = $StorePath; acquiredAtUtc = [DateTime]::UtcNow.ToString('o')
                ownerSid = $identity.User.Value; ownerName = $identity.Name; processId = $PID
                processStartedAtUtc = $process.StartTime.ToUniversalTime().ToString('o'); host = [Environment]::MachineName; machineGuid = $machineGuid
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
            $inspection = Test-WorkItemStoreLockOwnerDead $lockPath
            if ($inspection -eq 'Reaped' -or $inspection -eq 'Missing') { continue }
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
        $artifacts = @(Get-WorkItemStoreLockArtifacts $path)
        if (-not [IO.File]::Exists($path) -and $artifacts.Count -gt 0) { New-WorkItemStoreError 'StoreRecoveryRequired' "Store '$path' is missing but publication artifacts are present; preserve them and resolve the intended revision manually: $($artifacts.FullName -join ', ')" }
        $snapshot = Get-WorkItemStoreSnapshot $path $RepositoryRoot
        Resolve-WorkItemStoreOutbox $path $snapshot
        if ($snapshot.Exists) {
            $temporary = Join-Path ([IO.Path]::GetDirectoryName($path)) ('.' + [IO.Path]::GetFileName($path) + '.' + [Guid]::NewGuid().ToString('N') + '.read.tmp')
            try {
                New-WorkItemStoreExclusiveFile $temporary $snapshot.Bytes
                $validation = & (Join-Path $RepositoryRoot 'scripts\workitems\Test-WorkItems.ps1') -Path $temporary -RepositoryRoot $RepositoryRoot
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

function Write-WorkItemStoreOutbox($Path,$Outbox) {
    $target=$Path+'.outbox.json';$temp=$target+'.'+[Guid]::NewGuid().ToString('N')+'.writing';$utf8=New-Object Text.UTF8Encoding($false,$true)
    try { [IO.File]::WriteAllText($temp,(ConvertTo-Json -InputObject $Outbox -Depth 30 -Compress),$utf8);if([IO.File]::Exists($target)){[IO.File]::Replace($temp,$target,$null)}else{[IO.File]::Move($temp,$target)} } finally { if([IO.File]::Exists($temp)){[IO.File]::Delete($temp)} }
}
function Get-WorkItemStoreOutbox($Path) { $target=$Path+'.outbox.json';if(-not [IO.File]::Exists($target)){return [pscustomobject]@{schemaVersion='1.0';intents=@()}};try{return [IO.File]::ReadAllText($target,(New-Object Text.UTF8Encoding($false,$true)))|ConvertFrom-Json -ErrorAction Stop}catch{New-WorkItemStoreError 'OutboxRecoveryRequired' "Outbox is unreadable; preserve it: $target"} }
function Resolve-WorkItemStoreOutbox($Path,$Snapshot) {
    $outbox=Get-WorkItemStoreOutbox $Path;if($outbox.schemaVersion -cne '1.0'){New-WorkItemStoreError 'OutboxRecoveryRequired' 'Unsupported outbox schema.'}
    foreach($intent in @($outbox.intents|Where-Object{$_.state -ceq 'pending'})) { if($Snapshot.Revision -ceq $intent.candidateRevision){$intent.state='published';$intent.publishedAtUtc=[DateTime]::UtcNow.ToString('o')} elseif($Snapshot.Revision -ceq $intent.previousRevision){$intent.state='aborted';$intent.resolvedAtUtc=[DateTime]::UtcNow.ToString('o')} else {New-WorkItemStoreError 'OutboxRecoveryRequired' "Current revision matches neither outbox boundary for '$($intent.workItemId)'."} }
    Write-WorkItemStoreOutbox $Path $outbox
}

function Set-WorkItemStoreEntry {
    param([string]$Path, [string]$Id, $Item, [bool]$IsNew, [string]$ExpectedRevision, [string]$RepositoryRoot, [int]$TimeoutMilliseconds)
    try { $Item = ConvertFrom-Json -InputObject (ConvertTo-Json -InputObject $Item -Depth 100 -ErrorAction Stop) -ErrorAction Stop } catch { New-WorkItemStoreError 'InvalidCandidate' "WorkItem item is not serializable JSON data: $($_.Exception.Message)" }
    $path = Resolve-WorkItemStorePath $Path $RepositoryRoot
    $lock = Enter-WorkItemStoreLock $path $TimeoutMilliseconds
    $previous = $null; $candidate = $null; $backup = $null; $preservePublicationEvidence = $false
    try {
        $artifacts = @(Get-WorkItemStoreLockArtifacts $path)
        if (-not [IO.File]::Exists($path) -and $artifacts.Count -gt 0) { New-WorkItemStoreError 'StoreRecoveryRequired' "Store '$path' is missing but publication artifacts are present; preserve them and resolve the intended revision manually: $($artifacts.FullName -join ', ')" }
        $snapshot = Get-WorkItemStoreSnapshot $path $RepositoryRoot
        Resolve-WorkItemStoreOutbox $path $snapshot
        if ($snapshot.Exists) {
            $previous = Join-Path ([IO.Path]::GetDirectoryName($path)) ('.' + [IO.Path]::GetFileName($path) + '.' + $lock.LockId + '.' + [Guid]::NewGuid().ToString('N') + '.previous.tmp')
            New-WorkItemStoreExclusiveFile $previous $snapshot.Bytes
            try { $storedCheck = & (Join-Path $RepositoryRoot 'scripts\workitems\Test-WorkItems.ps1') -Path $previous -RepositoryRoot $RepositoryRoot } catch { New-WorkItemStoreError 'InvalidStoredDocument' "Stored WorkItem document failed validation: $($_.Exception.Message)" }
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
            New-WorkItemStoreExclusiveFile $previousForValidator ((New-Object Text.UTF8Encoding($false, $true)).GetBytes('{"schemaVersion":"1.0","items":[]}'))
            $previous = $previousForValidator
        }
        New-WorkItemStoreExclusiveFile $candidate $candidateBytes
        try { $validation = & (Join-Path $RepositoryRoot 'scripts\workitems\Test-WorkItems.ps1') -Path $candidate -PreviousPath $previousForValidator -RepositoryRoot $RepositoryRoot } catch { New-WorkItemStoreError 'ValidationFailed' "WorkItem transition validation failed: $($_.Exception.Message)" }
        if (-not $validation.valid -or -not $validation.transitionsChecked) { New-WorkItemStoreError 'ValidationFailed' 'Validator did not confirm a valid snapshot and checked transitions.' }
        $newRevision = 'sha256:' + [BitConverter]::ToString(([Security.Cryptography.SHA256]::Create().ComputeHash($candidateBytes))).Replace('-', '').ToLowerInvariant()
        $outbox=Get-WorkItemStoreOutbox $path
        $intent=[pscustomobject]@{intentId=([Guid]::NewGuid().ToString('N'));workItemId=$Id;previousRevision=$snapshot.Revision;candidateRevision=$newRevision;state='pending';createdAtUtc=[DateTime]::UtcNow.ToString('o');publishedAtUtc=$null}
        $outbox.intents=@($outbox.intents)+@($intent);Write-WorkItemStoreOutbox $path $outbox
        if ($snapshot.Exists) {
            $backup = Join-Path ([IO.Path]::GetDirectoryName($path)) ('.' + [IO.Path]::GetFileName($path) + '.' + $lock.LockId + '.' + [Guid]::NewGuid().ToString('N') + '.replace-backup.tmp')
            try { [IO.File]::Replace($candidate, $path, $backup) } catch { $preservePublicationEvidence = $true; New-WorkItemStoreError 'PublishFailed' "Atomic replacement failed: $($_.Exception.Message); recovery artifacts were retained where present." }
            try { [IO.File]::Delete($backup); $backup = $null } catch { Write-Error -ErrorId 'TemporaryCleanupFailed' -Message "Published successfully but could not remove own replacement backup '$backup': $($_.Exception.Message)" -ErrorAction Continue }
        } else {
            try { [IO.File]::Move($candidate, $path) } catch { $preservePublicationEvidence = $true; New-WorkItemStoreError 'PublishFailed' "Atomic initial publication failed: $($_.Exception.Message); recovery artifacts were retained where present." }
        }
        $candidate = $null
        $intent.state='published';$intent.publishedAtUtc=[DateTime]::UtcNow.ToString('o');Write-WorkItemStoreOutbox $path $outbox
        return [pscustomobject]@{ Document = $document; Revision = $newRevision; Changed = $true; Id = $Id }
    } finally {
        foreach ($temporary in @($previous, $(if (-not $preservePublicationEvidence) { $candidate }), $(if (-not $preservePublicationEvidence) { $backup }))) { if ($temporary -and [IO.File]::Exists($temporary)) { try { [IO.File]::Delete($temporary) } catch { Write-Error -ErrorId 'TemporaryCleanupFailed' -Message "Could not remove own temporary file '$temporary': $($_.Exception.Message)" -ErrorAction Continue } } }
        Exit-WorkItemStoreLock $lock
    }
}

Export-ModuleMember -Function Get-WorkItemStoreResult, Set-WorkItemStoreEntry
