. (Join-Path $PSScriptRoot '..\coordinator\Lifecycle.Persistence.ps1')
Set-StrictMode -Version 2

$script:WorkItemStoreLocks = @{}
$script:WorkItemStoreLockContexts = New-Object 'System.Collections.Generic.HashSet[object]'

# A module instance owns its registry; a shared CLR type is never a shared registry.
$script:WorkItemLockDiagnostics = $null
$script:WorkItemLockGate = New-Object object
try {
    if (-not ('AgentOrg.LockDiagnosticsV1.Registry' -as [type])) {
        Add-Type -Path (Join-Path $PSScriptRoot 'WorkItemStoreLockDiagnostics.cs') -ReferencedAssemblies @('System.dll', 'System.Core.dll', 'System.Runtime.Serialization.dll', 'System.Xml.dll') -ErrorAction Stop
    }
    $script:WorkItemLockDiagnostics = New-Object AgentOrg.LockDiagnosticsV1.Registry
    $script:WorkItemLockGate = $script:WorkItemLockDiagnostics.Gate
} catch { $script:WorkItemLockDiagnostics = $null } # diagnostic failure never prevents store acquisition
$ExecutionContext.SessionState.Module.OnRemove = {
    if ($null -ne $script:WorkItemLockDiagnostics) { $script:WorkItemLockDiagnostics.Dispose() }
}

function Undo-WorkItemLockAcquisition {
    param($Context, $Stream)
    $entry = $null
    try {
        [Threading.Monitor]::Enter($script:WorkItemLockGate)
        try {
            if ($null -ne $Context -and [object]::ReferenceEquals($script:WorkItemStoreLocks[$Context.LockId], $Context)) {
                $entry = $Context.DiagnosticEntry
                if ($null -ne $entry) { $script:WorkItemLockDiagnostics.Retire($entry, $Context, $Context.DiagnosticToken) }
                [void]$script:WorkItemStoreLocks.Remove($Context.LockId)
                [void]$script:WorkItemStoreLockContexts.Remove($Context)
            }
            if ($null -ne $Stream) { $Stream.Dispose() }
        } finally { [Threading.Monitor]::Exit($script:WorkItemLockGate) }
    } finally {
        if ($null -ne $entry) { [void]$script:WorkItemLockDiagnostics.Stop($entry) }
    }
}

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

# Private producer lifecycle observations. Every caller treats these as best effort.
function Get-WorkItemStoreObservationSource {
    try {
        $path = [IO.Path]::GetFullPath($PSCommandPath)
        $bytes = [IO.File]::ReadAllBytes($path)
        $sha = [Security.Cryptography.SHA256]::Create()
        try { $hash = ([BitConverter]::ToString($sha.ComputeHash($bytes))).Replace('-', '').ToLowerInvariant() } finally { $sha.Dispose() }
        return [pscustomobject]@{ modulePath = $path; sha256 = $hash }
    } catch { return $null }
}

function Get-WorkItemStoreMetadataHashBestEffort {
    param([byte[]]$Bytes)
    try {
        $sha = [Security.Cryptography.SHA256]::Create()
        try { return ([BitConverter]::ToString($sha.ComputeHash($Bytes))).Replace('-', '').ToLowerInvariant() }
        finally { $sha.Dispose() }
    } catch { return $null }
}

function Write-WorkItemStoreObservation {
    param([string]$StorePath, [string]$FileName, $Observation)
    $temp = $null; $stream = $null
    try {
        $directory = [IO.Path]::GetFullPath($StorePath) + '.lock-observations'
        if (-not [IO.Directory]::Exists($directory)) { [void][IO.Directory]::CreateDirectory($directory) }
        $target = Join-Path $directory $FileName
        $json = ConvertTo-Json -InputObject $Observation -Depth 8 -Compress
        $bytes = (New-Object Text.UTF8Encoding($false, $true)).GetBytes($json)
        $temp = Join-Path $directory ('.' + [Guid]::NewGuid().ToString('N') + '.tmp')
        $stream = New-Object IO.FileStream($temp, [IO.FileMode]::CreateNew, [IO.FileAccess]::Write, [IO.FileShare]::None)
        $stream.Write($bytes, 0, $bytes.Length); $stream.Flush($true); $stream.Dispose(); $stream = $null
        [IO.File]::Move($temp, $target)
        return ,$bytes
    } catch { return $null }
    finally {
        if ($null -ne $stream) { try { $stream.Dispose() } catch {} }
        if ($null -ne $temp) { try { if ([IO.File]::Exists($temp)) { [IO.File]::Delete($temp) } } catch {} }
    }
}

function Get-WorkItemStoreObservationBase {
    param($Context, [string]$Event, [int]$AttemptOrdinal, [string]$FailureCode)
    try {
        return [ordered]@{
            diagnosticVersion = '1'; event = $Event; eventAtUtc = [DateTime]::UtcNow.ToString('o')
            observationScope = 'producerLifecycle'; lockId = [string]$Context.LockId
            storePath = [string]$Context.StorePath; lockPath = [string]$Context.LockPath
            attemptOrdinal = $AttemptOrdinal; acquiredAtUtc = [string]$Context.Metadata.acquiredAtUtc
            ownerSid = [string]$Context.Metadata.ownerSid; ownerName = [string]$Context.Metadata.ownerName
            processId = $Context.Metadata.processId; processStartedAtUtc = [string]$Context.Metadata.processStartedAtUtc
            host = [string]$Context.Metadata.host; machineGuid = [string]$Context.Metadata.machineGuid
            originalMetadataHash = [string]$Context.OriginalMetadataHash
            sourceReference = $Context.ProducerSource
            failureCode = $FailureCode
        }
    } catch { return $null }
}

function Publish-WorkItemStoreLifecycleEvent {
    param($Context, [string]$Event, [int]$AttemptOrdinal, [string]$AcquiredHash, [string]$FailureCode)
    try {
        $observation = Get-WorkItemStoreObservationBase $Context $Event $AttemptOrdinal $FailureCode
        if ($null -eq $observation) { return }
        if ($Event -eq 'acquired') {
            $payload = Write-WorkItemStoreObservation $Context.StorePath ("{0}.{1}.acquired.json" -f $Context.LockId, $AttemptOrdinal) $observation
            if ($null -ne $payload) {
                $sha = [Security.Cryptography.SHA256]::Create()
                try { $Context.AcquiredObservationHash = ([BitConverter]::ToString($sha.ComputeHash($payload))).Replace('-', '').ToLowerInvariant() } finally { $sha.Dispose() }
            }
            return
        }
        if ($Event -in @('released', 'releaseUnconfirmed')) {
            $observation.acquiredHash = $AcquiredHash
            if ([string]::IsNullOrEmpty($AcquiredHash)) { $observation.acquisitionEvidenceMissing = $true }
            [void](Write-WorkItemStoreObservation $Context.StorePath ("{0}.{1}.terminal.json" -f $Context.LockId, $AttemptOrdinal) $observation)
            return
        }
        [void](Write-WorkItemStoreObservation $Context.StorePath ("{0}.{1}.acquisitionAborted.json" -f $Context.LockId, $AttemptOrdinal) $observation)
    } catch {}
}

function Enter-WorkItemStoreLock {
    param([string]$StorePath, [int]$TimeoutMilliseconds = 5000)
    if ($TimeoutMilliseconds -lt 0 -or $TimeoutMilliseconds -gt 60000) { New-WorkItemStoreError 'InvalidTimeout' 'TimeoutMilliseconds must be between 0 and 60000.' }
    $lockPath = $StorePath + '.lock'
    $watch = [Diagnostics.Stopwatch]::StartNew()
    $lockId = [Guid]::NewGuid().ToString('D')
    $attemptOrdinal = 0
    while ($true) {
        $attemptOrdinal++
        $stream = $null; $context = $null
        $metadata = $null; $bytes = $null; $metadataHash = $null; $producerSource = $null
        try {
            $options = [IO.FileOptions]::DeleteOnClose
            $stream = New-Object IO.FileStream($lockPath, [IO.FileMode]::CreateNew, [IO.FileAccess]::ReadWrite, [IO.FileShare]::Read, 4096, $options)
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
            $metadataHash = Get-WorkItemStoreMetadataHashBestEffort $bytes
            $stream.Write($bytes, 0, $bytes.Length)
            $stream.Flush($true)
            $producerSource = Get-WorkItemStoreObservationSource
            $context = [pscustomobject]@{ LockId = $lockId; StorePath = $StorePath; LockPath = $lockPath; Stream = $stream; OwnerSid = $identity.User.Value; OwnerName = $identity.Name; ProcessId = $PID; ProcessStartedAtUtc = $process.StartTime.ToUniversalTime().ToString('o'); Host = [Environment]::MachineName; Released = $false; Metadata = $metadata; OriginalMetadataHash = $metadataHash; ProducerSource = $producerSource; AttemptOrdinal = $attemptOrdinal; AcquiredObservationHash = $null; DiagnosticEntry = $null; DiagnosticToken = (New-Object object); DiagnosticStatus = 'unavailable' }
            # Both registries publish this exact context under the same lifetime gate.
            [Threading.Monitor]::Enter($script:WorkItemLockGate)
            try {
                $script:WorkItemStoreLocks[$lockId] = $context
                [void]$script:WorkItemStoreLockContexts.Add($context)
                if ($null -ne $script:WorkItemLockDiagnostics) {
                    try {
                        $startFileTime = $process.StartTime.ToUniversalTime().ToFileTimeUtc()
                        $data = New-Object AgentOrg.LockDiagnosticsV1.Acquisition($context.StorePath, $context.LockPath, $context.LockId, $context.AttemptOrdinal, $context.OriginalMetadataHash, $context.OwnerSid, $context.OwnerName, $context.ProcessId, $startFileTime, $context.ProcessStartedAtUtc, $context.Host, $metadata.acquiredAtUtc)
                        $context.DiagnosticEntry = $script:WorkItemLockDiagnostics.Register($context, $context.DiagnosticToken, $context.Stream, $data)
                        $context.DiagnosticStatus = 'registered'
                    } catch { $context.DiagnosticStatus = 'unavailable' }
                }
            } finally { [Threading.Monitor]::Exit($script:WorkItemLockGate) }
            if ($null -ne $context.DiagnosticEntry) {
                try {
                    $script:WorkItemLockDiagnostics.Start($context.DiagnosticEntry, $context, $context.DiagnosticToken)
                    $context.DiagnosticStatus = 'started'
                } catch {
                    [Threading.Monitor]::Enter($script:WorkItemLockGate)
                    try { $script:WorkItemLockDiagnostics.Retire($context.DiagnosticEntry, $context, $context.DiagnosticToken) }
                    finally { [Threading.Monitor]::Exit($script:WorkItemLockGate) }
                    $context.DiagnosticStatus = $script:WorkItemLockDiagnostics.Stop($context.DiagnosticEntry)
                }
            }
            Publish-WorkItemStoreLifecycleEvent $context 'acquired' $attemptOrdinal $null $null
            return $context
        } catch [System.IO.IOException] {
            $disposeSucceeded = $false
            if ($null -ne $stream) { Undo-WorkItemLockAcquisition $context $stream; $disposeSucceeded = $true }
            if ($disposeSucceeded -and $null -ne $metadata -and $null -ne $metadataHash) {
                $aborted = [pscustomobject]@{ LockId=$lockId; StorePath=$StorePath; LockPath=$lockPath; Metadata=$metadata; OriginalMetadataHash=$metadataHash; ProducerSource=$producerSource; AttemptOrdinal=$attemptOrdinal }
                Publish-WorkItemStoreLifecycleEvent $aborted 'acquisitionAborted' $attemptOrdinal $null 'IOException'
            }
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
            $disposeSucceeded = $false
            if ($null -ne $stream) { Undo-WorkItemLockAcquisition $context $stream; $disposeSucceeded = $true }
            if ($disposeSucceeded -and $null -ne $metadata -and $null -ne $metadataHash) {
                $aborted = [pscustomobject]@{ LockId=$lockId; StorePath=$StorePath; LockPath=$lockPath; Metadata=$metadata; OriginalMetadataHash=$metadataHash; ProducerSource=$producerSource; AttemptOrdinal=$attemptOrdinal }
                Publish-WorkItemStoreLifecycleEvent $aborted 'acquisitionAborted' $attemptOrdinal $null 'Other'
            }
            throw
        }
    }
}

function Exit-WorkItemStoreLock {
    param([Parameter(Mandatory = $true)]$Context)
    $entry = $null; $authorized = $false; $disposeFailure = $null
    try {
        [Threading.Monitor]::Enter($script:WorkItemLockGate)
        try {
            if (-not $script:WorkItemStoreLockContexts.Contains($Context)) { New-WorkItemStoreError 'LockNotOwned' 'The lock context is not privately registered in this module.' }
            if ($null -ne $Context -and $Context.PSObject.Properties['Released'] -and $Context.Released -eq $true) { return }
            $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
            $process = [Diagnostics.Process]::GetCurrentProcess()
            $registered = $script:WorkItemStoreLocks[$Context.LockId]
            if (-not [object]::ReferenceEquals($registered, $Context) -or $Context.OwnerSid -cne $identity.User.Value -or $Context.OwnerName -cne $identity.Name -or $Context.ProcessId -ne $PID -or $Context.Host -cne [Environment]::MachineName -or $Context.ProcessStartedAtUtc -cne $process.StartTime.ToUniversalTime().ToString('o') -or $Context.StorePath -cne [IO.Path]::GetFullPath($Context.StorePath)) {
                New-WorkItemStoreError 'LockNotOwned' 'Lock ownership could not be verified against this process.'
            }
            $authorized = $true
            $entry = $Context.DiagnosticEntry
            if ($null -ne $entry) { $script:WorkItemLockDiagnostics.Retire($entry, $Context, $Context.DiagnosticToken) }
            $Context.Released = $true
            try {
                $Context.Stream.Dispose()
                [void]$script:WorkItemStoreLocks.Remove($Context.LockId)
            } catch { $disposeFailure = $_ }
        } finally { [Threading.Monitor]::Exit($script:WorkItemLockGate) }
        # Lifecycle publication and pipe cleanup are outside the lifetime gate.
        if ($null -ne $disposeFailure) {
            Publish-WorkItemStoreLifecycleEvent $Context 'releaseUnconfirmed' $Context.AttemptOrdinal $Context.AcquiredObservationHash 'DisposeFailure'
            throw $disposeFailure
        }
        Publish-WorkItemStoreLifecycleEvent $Context 'released' $Context.AttemptOrdinal $Context.AcquiredObservationHash $null
    } finally {
        if ($authorized -and $null -ne $entry) { $Context.DiagnosticStatus = $script:WorkItemLockDiagnostics.Stop($entry) }
    }
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

function Write-WorkItemStoreOutbox($Path,$Outbox){Write-LCJournal ($Path+'.outbox.json') $Outbox}

function Get-WorkItemStoreOutbox($Path) { $target=$Path+'.outbox.json';if(-not [IO.File]::Exists($target)){return [pscustomobject]@{schemaVersion='1.0';intents=@()}};try{return (Read-LCArchive $target ([IO.File]::ReadAllText($target,(New-Object Text.UTF8Encoding($false,$true)))|ConvertFrom-Json -ErrorAction Stop))}catch{New-WorkItemStoreError 'OutboxRecoveryRequired' "Outbox is unreadable; preserve it: $target"} }
function Resolve-WorkItemStoreOutbox($Path,$Snapshot) {
    $outbox=Get-WorkItemStoreOutbox $Path;if($outbox.schemaVersion -cne '1.0'){New-WorkItemStoreError 'OutboxRecoveryRequired' 'Unsupported outbox schema.'}
    foreach($intent in @($outbox.intents)){foreach($field in @('publishedAtUtc','resolvedAtUtc')){if(-not $intent.PSObject.Properties[$field]){$intent|Add-Member -NotePropertyName $field -NotePropertyValue $null}}}
    foreach($intent in @($outbox.intents|Where-Object{$_.state -ceq 'pending'})) { if($Snapshot.Revision -ceq $intent.candidateRevision){$intent.state='published';$intent.publishedAtUtc=[DateTime]::UtcNow.ToString('o')} elseif($Snapshot.Revision -ceq $intent.previousRevision){$intent.state='aborted';$intent.resolvedAtUtc=[DateTime]::UtcNow.ToString('o')} else {New-WorkItemStoreError 'OutboxRecoveryRequired' "Current revision matches neither outbox boundary for '$($intent.workItemId)'."};if($intent.PSObject.Properties['effectContext'] -and $intent.effectContext){$r=New-WorkItemStoreEffectReceipt $intent.effectContext $intent.operationHash $intent.state $intent.workItemId $intent.previousRevision $intent.candidateRevision ([bool]($intent.state -eq 'published')) $intent.intentId $intent.itemPayloadBase64;$storedPayload=Get-WorkItemStoreProperty $intent 'receiptPayloadBase64';$storedHash=Get-WorkItemStoreProperty $intent 'receiptHash';if($storedPayload -and $storedPayload -cne $r.receiptPayloadBase64){New-WorkItemStoreError 'EffectIdentityConflict' "Pending intent '$($intent.intentId)' has conflicting immutable receipt bytes."};if($storedHash -and $storedHash -cne $r.receiptHash){New-WorkItemStoreError 'EffectIdentityConflict' "Pending intent '$($intent.intentId)' has a conflicting immutable receipt hash."};if(-not $storedPayload){$intent|Add-Member -NotePropertyName receiptPayloadBase64 -NotePropertyValue $r.receiptPayloadBase64 -Force};if(-not $storedHash){$intent|Add-Member -NotePropertyName receiptHash -NotePropertyValue $r.receiptHash -Force}} }
    Write-WorkItemStoreOutbox $Path $outbox
}

function Get-WorkItemStoreProperty($Object,[string]$Name) {
    if ($null -eq $Object) { return $null }
    if ($Object -is [System.Collections.IDictionary]) { if ($Object.Contains($Name)) { return $Object[$Name] }; return $null }
    $property = $Object.PSObject.Properties[$Name]
    if ($null -ne $property) { return $property.Value }
    return $null
}

function Get-WorkItemStoreSha256([byte[]]$Bytes) {
    $sha = [Security.Cryptography.SHA256]::Create()
    try { return [BitConverter]::ToString($sha.ComputeHash($Bytes)).Replace('-', '').ToLowerInvariant() } finally { $sha.Dispose() }
}

function ConvertTo-WorkItemStoreCanonicalJson($Value) {
    return (ConvertTo-Json -InputObject $Value -Depth 100 -Compress -ErrorAction Stop)
}

function ConvertTo-WorkItemStoreReceipt($Receipt) {
    $payload=Get-WorkItemStoreProperty $Receipt 'receiptPayloadBase64';$receiptHash=Get-WorkItemStoreProperty $Receipt 'receiptHash'
    if (-not $payload -or -not $receiptHash) { New-WorkItemStoreError 'EffectIdentityConflict' 'Effect receipt has no immutable receipt payload.' }
    try { $bytes = [Convert]::FromBase64String([string]$payload) } catch { New-WorkItemStoreError 'EffectIdentityConflict' 'Effect receipt payload is invalid base64.' }
    if ((Get-WorkItemStoreSha256 $bytes) -cne [string]$receiptHash) { New-WorkItemStoreError 'EffectIdentityConflict' 'Effect receipt immutable payload hash does not match.' }
    try { $data = ConvertFrom-Json -InputObject ((New-Object Text.UTF8Encoding($false,$true)).GetString($bytes)) -ErrorAction Stop } catch { New-WorkItemStoreError 'EffectIdentityConflict' 'Effect receipt immutable payload cannot be decoded.' }
    $receiptContext=Get-WorkItemStoreProperty $Receipt 'context';if($null -eq $receiptContext){$receiptContext=Get-WorkItemStoreProperty $Receipt 'effectContext'}
    $expectedEffectId=Get-WorkItemStoreProperty $Receipt 'effectId';if(-not $expectedEffectId){$expectedEffectId=Get-WorkItemStoreProperty $receiptContext 'effectId'}
    $expectedOperationHash=Get-WorkItemStoreProperty $Receipt 'operationHash'
    if (-not $expectedEffectId -or -not $expectedOperationHash -or $data.effectId -cne [string]$expectedEffectId -or $data.operationHash -cne [string]$expectedOperationHash -or $data.context.effectId -cne [string]$expectedEffectId) { New-WorkItemStoreError 'EffectIdentityConflict' 'Effect receipt identity binding conflicts.' }
    if($receiptContext -and (ConvertTo-WorkItemStoreCanonicalJson $receiptContext) -cne (ConvertTo-WorkItemStoreCanonicalJson $data.context)){New-WorkItemStoreError 'EffectIdentityConflict' 'Effect receipt context binding conflicts.'}
    return [pscustomobject]@{ effectId=$data.effectId; operationHash=$data.operationHash; context=$data.context; state=$data.state; workItemId=$data.workItemId; previousRevision=$data.previousRevision; candidateRevision=$data.candidateRevision; changed=[bool]$data.changed; intentId=$data.intentId; itemPayloadBase64=$data.itemPayloadBase64; receiptPayloadBase64=[string]$payload; receiptHash=[string]$receiptHash }
}

function New-WorkItemStoreEffectReceipt($Context,[string]$OperationHash,[string]$State,[string]$WorkItemId,[string]$PreviousRevision,[string]$CandidateRevision,[bool]$Changed,[string]$IntentId,[string]$ItemPayloadBase64) {
    $body=[ordered]@{effectId=[string]$Context.effectId;operationHash=$OperationHash;context=$Context;state=$State;workItemId=$WorkItemId;previousRevision=$PreviousRevision;candidateRevision=$CandidateRevision;changed=$Changed;intentId=$IntentId;itemPayloadBase64=$ItemPayloadBase64}
    $bytes=(New-Object Text.UTF8Encoding($false,$true)).GetBytes((ConvertTo-WorkItemStoreCanonicalJson $body))
    return [pscustomobject]@{receiptPayloadBase64=[Convert]::ToBase64String($bytes);receiptHash=(Get-WorkItemStoreSha256 $bytes)}
}

function Get-WorkItemStoreEffectReceipt {
    param([string]$Path,[string]$EffectId,[string]$RepositoryRoot,[int]$TimeoutMilliseconds=5000)
    if ([string]::IsNullOrWhiteSpace($EffectId)) { New-WorkItemStoreError 'EffectIdentityConflict' 'EffectId is required.' }
    $path=Resolve-WorkItemStorePath $Path $RepositoryRoot; $lock=Enter-WorkItemStoreLock $path $TimeoutMilliseconds
    try {
        $snapshot=Get-WorkItemStoreSnapshot $path $RepositoryRoot
        Resolve-WorkItemStoreOutbox $path $snapshot
        $outbox=Get-WorkItemStoreOutbox $path; $matches=@()
        foreach($intent in @($outbox.intents)) { $ctx=Get-WorkItemStoreProperty $intent 'effectContext'; if ($null -ne $ctx -and [string](Get-WorkItemStoreProperty $ctx 'effectId') -ceq $EffectId) {
            $payload=Get-WorkItemStoreProperty $intent 'receiptPayloadBase64'; $hash=Get-WorkItemStoreProperty $intent 'receiptHash'
            $op=[string](Get-WorkItemStoreProperty $intent 'operationHash')
            if (-not $payload -or -not $hash) { $itemBytes=[string](Get-WorkItemStoreProperty $intent 'itemPayloadBase64');$state=[string](Get-WorkItemStoreProperty $intent 'state');if (-not $op -or -not $itemBytes -or $state -cne 'published') { New-WorkItemStoreError 'OutboxRecoveryRequired' "Effect intent '$EffectId' lacks published receipt reconstruction metadata." };$receipt=New-WorkItemStoreEffectReceipt $ctx $op $state ([string](Get-WorkItemStoreProperty $intent 'workItemId')) ([string](Get-WorkItemStoreProperty $intent 'previousRevision')) ([string](Get-WorkItemStoreProperty $intent 'candidateRevision')) $true ([string](Get-WorkItemStoreProperty $intent 'intentId')) $itemBytes;if($payload -and $payload -cne $receipt.receiptPayloadBase64){New-WorkItemStoreError 'EffectIdentityConflict' "Effect intent '$EffectId' has conflicting immutable receipt bytes."};if($hash -and $hash -cne $receipt.receiptHash){New-WorkItemStoreError 'EffectIdentityConflict' "Effect intent '$EffectId' has a conflicting immutable receipt hash."};if(-not $payload){$intent|Add-Member -NotePropertyName receiptPayloadBase64 -NotePropertyValue $receipt.receiptPayloadBase64 -Force};if(-not $hash){$intent|Add-Member -NotePropertyName receiptHash -NotePropertyValue $receipt.receiptHash -Force};Write-WorkItemStoreOutbox $path $outbox;$payload=$receipt.receiptPayloadBase64;$hash=$receipt.receiptHash }
            $matches+=,(ConvertTo-WorkItemStoreReceipt ([pscustomobject]@{effectId=$EffectId;context=$ctx;operationHash=$op;receiptPayloadBase64=$payload;receiptHash=$hash}))
        } }
        foreach($receipt in @(Get-WorkItemStoreProperty $outbox 'effectReceipts')) { if ([string](Get-WorkItemStoreProperty (Get-WorkItemStoreProperty $receipt 'context') 'effectId') -ceq $EffectId) { $matches+=,(ConvertTo-WorkItemStoreReceipt $receipt) } }
        if ($matches.Count -gt 1) { $first=ConvertTo-WorkItemStoreCanonicalJson $matches[0];foreach($m in $matches | Select-Object -Skip 1){if((ConvertTo-WorkItemStoreCanonicalJson $m) -cne $first){New-WorkItemStoreError 'EffectIdentityConflict' "EffectId '$EffectId' has conflicting receipts."}};New-WorkItemStoreError 'EffectIdentityConflict' "EffectId '$EffectId' has multiple receipt records." }
        if ($matches.Count -eq 0) { return $null }
        if ($matches[0].state -ceq 'pending') { New-WorkItemStoreError 'OutboxRecoveryRequired' "EffectId '$EffectId' remains pending." }
        return $matches[0]
    } finally { Exit-WorkItemStoreLock $lock }
}

function Set-WorkItemStoreEntry {
    param([string]$Path, [string]$Id, $Item, [bool]$IsNew, [string]$ExpectedRevision, [string]$RepositoryRoot, [int]$TimeoutMilliseconds, $EffectContext=$null)
    try { $Item = ConvertFrom-Json -InputObject (ConvertTo-Json -InputObject $Item -Depth 100 -ErrorAction Stop) -ErrorAction Stop } catch { New-WorkItemStoreError 'InvalidCandidate' "WorkItem item is not serializable JSON data: $($_.Exception.Message)" }
    $path = Resolve-WorkItemStorePath $Path $RepositoryRoot
    $lock = Enter-WorkItemStoreLock $path $TimeoutMilliseconds
    $previous = $null; $candidate = $null; $backup = $null; $preservePublicationEvidence = $false
    try {
        $artifacts = @(Get-WorkItemStoreLockArtifacts $path)
        if (-not [IO.File]::Exists($path) -and $artifacts.Count -gt 0) { New-WorkItemStoreError 'StoreRecoveryRequired' "Store '$path' is missing but publication artifacts are present; preserve them and resolve the intended revision manually: $($artifacts.FullName -join ', ')" }
        $snapshot = Get-WorkItemStoreSnapshot $path $RepositoryRoot
        Resolve-WorkItemStoreOutbox $path $snapshot
        $effect=$null;$operationHash=$null;$itemPayloadBase64=$null
        if ($null -ne $EffectContext) {
            $required=@('effectId','executionId','requestId','threadId','turnId','eventId','inputHash','planHash','ordinal')
            foreach($field in $required){if($null -eq (Get-WorkItemStoreProperty $EffectContext $field) -or [string]::IsNullOrWhiteSpace([string](Get-WorkItemStoreProperty $EffectContext $field))){New-WorkItemStoreError 'EffectIdentityConflict' "EffectContext.$field is required."}}
            $ctx=[ordered]@{};foreach($field in $required){$ctx[$field]=Get-WorkItemStoreProperty $EffectContext $field};foreach($field in @('resumeEffectKind','resumeCommandHash')){if($null -ne (Get-WorkItemStoreProperty $EffectContext $field)){$ctx[$field]=Get-WorkItemStoreProperty $EffectContext $field}};$effect=[pscustomobject]$ctx
            $itemJson=ConvertTo-WorkItemStoreCanonicalJson $Item;$itemBytes=(New-Object Text.UTF8Encoding($false,$true)).GetBytes($itemJson);$itemPayloadBase64=[Convert]::ToBase64String($itemBytes)
            $opBody=[ordered]@{Id=$Id;IsNew=$IsNew;ExpectedRevision=$ExpectedRevision;Item=$Item;EffectContext=$effect};$opBytes=(New-Object Text.UTF8Encoding($false,$true)).GetBytes((ConvertTo-WorkItemStoreCanonicalJson $opBody));$operationHash=Get-WorkItemStoreSha256 $opBytes
            $outbox=Get-WorkItemStoreOutbox $path;$known=@()
            foreach($oldIntent in @($outbox.intents)){ $oldContext=Get-WorkItemStoreProperty $oldIntent 'effectContext';if($null -ne $oldContext -and [string](Get-WorkItemStoreProperty $oldContext 'effectId') -ceq $effect.effectId){$known+=,$oldIntent} }
            foreach($oldReceipt in @(Get-WorkItemStoreProperty $outbox 'effectReceipts')){if([string](Get-WorkItemStoreProperty (Get-WorkItemStoreProperty $oldReceipt 'context') 'effectId') -ceq $effect.effectId){$known+=,$oldReceipt}}
            if($known.Count -gt 1){New-WorkItemStoreError 'EffectIdentityConflict' "EffectId '$($effect.effectId)' has multiple prior records."}
            if($known.Count -eq 1){$old=$known[0];$oldOp=[string](Get-WorkItemStoreProperty $old 'operationHash');$oldContext=Get-WorkItemStoreProperty $old 'effectContext';if($null -eq $oldContext){$oldContext=Get-WorkItemStoreProperty $old 'context'};if($oldOp -cne $operationHash -or (ConvertTo-WorkItemStoreCanonicalJson $oldContext) -cne (ConvertTo-WorkItemStoreCanonicalJson $effect)){New-WorkItemStoreError 'EffectIdentityConflict' "EffectId '$($effect.effectId)' was reused with different operation data."};$savedPayload=Get-WorkItemStoreProperty $old 'receiptPayloadBase64';$savedHash=Get-WorkItemStoreProperty $old 'receiptHash';if($savedPayload -and $savedHash){$saved=[pscustomobject]@{effectId=$effect.effectId;context=$oldContext;operationHash=$oldOp;receiptPayloadBase64=$savedPayload;receiptHash=$savedHash};$receipt=ConvertTo-WorkItemStoreReceipt $saved;$state=$receipt.state}else{$state=[string](Get-WorkItemStoreProperty $old 'state');if($state -cne 'published'){if($state -ceq 'aborted'){New-WorkItemStoreError 'EffectAborted' "EffectId '$($effect.effectId)' was previously aborted."};New-WorkItemStoreError 'OutboxRecoveryRequired' "EffectId '$($effect.effectId)' has no verifiable published receipt."};$itemBytes=[string](Get-WorkItemStoreProperty $old 'itemPayloadBase64');$workItemId=[string](Get-WorkItemStoreProperty $old 'workItemId');$previousRevision=[string](Get-WorkItemStoreProperty $old 'previousRevision');$candidateRevision=[string](Get-WorkItemStoreProperty $old 'candidateRevision');$intentId=[string](Get-WorkItemStoreProperty $old 'intentId');if(-not $itemBytes -or -not $workItemId -or -not $candidateRevision -or -not $intentId){New-WorkItemStoreError 'OutboxRecoveryRequired' "EffectId '$($effect.effectId)' lacks published intent reconstruction metadata."};$saved=New-WorkItemStoreEffectReceipt $effect $operationHash $state $workItemId $previousRevision $candidateRevision $true $intentId $itemBytes;if($savedPayload -and $savedPayload -cne $saved.receiptPayloadBase64){New-WorkItemStoreError 'EffectIdentityConflict' 'Conflicting immutable receipt bytes.'};if($savedHash -and $savedHash -cne $saved.receiptHash){New-WorkItemStoreError 'EffectIdentityConflict' 'Conflicting immutable receipt hash.'};if(-not $savedPayload){$old|Add-Member -NotePropertyName receiptPayloadBase64 -NotePropertyValue $saved.receiptPayloadBase64 -Force};if(-not $savedHash){$old|Add-Member -NotePropertyName receiptHash -NotePropertyValue $saved.receiptHash -Force};Write-WorkItemStoreOutbox $path $outbox;$receipt=ConvertTo-WorkItemStoreReceipt ([pscustomobject]@{effectId=$effect.effectId;context=$effect;operationHash=$operationHash;receiptPayloadBase64=$saved.receiptPayloadBase64;receiptHash=$saved.receiptHash})};if($state -ceq 'pending'){New-WorkItemStoreError 'OutboxRecoveryRequired' "EffectId '$($effect.effectId)' remains pending after resolution."};if($state -ceq 'aborted'){New-WorkItemStoreError 'EffectAborted' "EffectId '$($effect.effectId)' was previously aborted."};if($state -cne 'published'){New-WorkItemStoreError 'EffectIdentityConflict' "EffectId '$($effect.effectId)' has an unsupported prior state."};return [pscustomobject]@{Document=$snapshot.Document;Revision=$snapshot.Revision;Changed=$receipt.changed;Id=$Id;EffectReceipt=$receipt}}
        }
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
            if ($oldJson -ceq $newJson) { if($null -eq $effect){return [pscustomobject]@{ Document = $snapshot.Document; Revision = $snapshot.Revision; Changed = $false; Id = $Id }};$receipt=New-WorkItemStoreEffectReceipt $effect $operationHash 'published' $Id $snapshot.Revision $snapshot.Revision $false $null $itemPayloadBase64;$outbox=Get-WorkItemStoreOutbox $path;if(-not $outbox.PSObject.Properties['effectReceipts']){$outbox|Add-Member -NotePropertyName effectReceipts -NotePropertyValue @()};$outbox.effectReceipts=@($outbox.effectReceipts)+@([pscustomobject]@{context=$effect;operationHash=$operationHash;receiptPayloadBase64=$receipt.receiptPayloadBase64;receiptHash=$receipt.receiptHash});Write-WorkItemStoreOutbox $path $outbox;return [pscustomobject]@{Document=$snapshot.Document;Revision=$snapshot.Revision;Changed=$false;Id=$Id;EffectReceipt=(ConvertTo-WorkItemStoreReceipt ([pscustomobject]@{effectId=$effect.effectId;operationHash=$operationHash;receiptPayloadBase64=$receipt.receiptPayloadBase64;receiptHash=$receipt.receiptHash}))} }
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
        $intent=[pscustomobject]@{intentId=([Guid]::NewGuid().ToString('D'));type='workitem_changed';sourceId=$Id;revision=$newRevision;item=$Item;workItemId=$Id;previousRevision=$snapshot.Revision;candidateRevision=$newRevision;previousPayloadBase64=$(if($snapshot.Exists){[Convert]::ToBase64String($snapshot.Bytes)}else{$null});candidatePayloadBase64=[Convert]::ToBase64String($candidateBytes);state='pending';createdAtUtc=[DateTime]::UtcNow.ToString('o');publishedAtUtc=$null;resolvedAtUtc=$null}
        if($null -ne $effect){$intent|Add-Member -NotePropertyName effectContext -NotePropertyValue $effect;$intent|Add-Member -NotePropertyName operationHash -NotePropertyValue $operationHash;$intent|Add-Member -NotePropertyName itemPayloadBase64 -NotePropertyValue $itemPayloadBase64}
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
        if($null -ne $effect){$intent.state='published';$intent.publishedAtUtc=[DateTime]::UtcNow.ToString('o');$intentReceipt=New-WorkItemStoreEffectReceipt $effect $operationHash 'published' $Id $snapshot.Revision $newRevision $true $intent.intentId $itemPayloadBase64;$intent|Add-Member -NotePropertyName receiptPayloadBase64 -NotePropertyValue $intentReceipt.receiptPayloadBase64 -Force;$intent|Add-Member -NotePropertyName receiptHash -NotePropertyValue $intentReceipt.receiptHash -Force;Write-WorkItemStoreOutbox $path $outbox;$intentReceipt=ConvertTo-WorkItemStoreReceipt $intent};return [pscustomobject]@{ Document = $document; Revision = $newRevision; Changed = $true; Id = $Id; EffectReceipt=$(if($null -ne $effect){$intentReceipt}else{$null}) }
    } finally {
        foreach ($temporary in @($previous, $(if (-not $preservePublicationEvidence) { $candidate }), $(if (-not $preservePublicationEvidence) { $backup }))) { if ($temporary -and [IO.File]::Exists($temporary)) { try { [IO.File]::Delete($temporary) } catch { Write-Error -ErrorId 'TemporaryCleanupFailed' -Message "Could not remove own temporary file '$temporary': $($_.Exception.Message)" -ErrorAction Continue } } }
        Exit-WorkItemStoreLock $lock
    }
}


function Get-WorkItemStoreResumeRequirement {
    param([string]$Path,$Item,[string]$RepositoryRoot)
    $path=Resolve-WorkItemStorePath $Path $RepositoryRoot;$lock=Enter-WorkItemStoreLock $path 5000
    try{
        $snapshot=Get-WorkItemStoreSnapshot $path $RepositoryRoot;Resolve-WorkItemStoreOutbox $path $snapshot
        $outbox=Get-WorkItemStoreOutbox $path;$records=@($outbox.intents)+@(Get-WorkItemStoreProperty $outbox 'effectReceipts');$found=@()
        foreach($entry in $records){
            $ctx=Get-WorkItemStoreProperty $entry 'effectContext';if(-not $ctx){$ctx=Get-WorkItemStoreProperty $entry 'context'}
            if((Get-WorkItemStoreProperty $ctx 'resumeEffectKind') -cne 'propose_resume'){continue}
            $r=ConvertTo-WorkItemStoreReceipt $entry
            if($r.state -cne 'published' -or $r.workItemId -cne $Item.id){continue}
            $saved=ConvertFrom-Json -InputObject ([Text.UTF8Encoding]::new($false,$true).GetString([Convert]::FromBase64String($r.itemPayloadBase64)))
            if($saved.status -in @('planned','rework','in_progress') -and (Get-LCResumeContent $saved) -ceq (Get-LCResumeContent $Item)){$found+=,$r}
        }
        return $found
    }finally{Exit-WorkItemStoreLock $lock}
}

Export-ModuleMember -Function Get-WorkItemStoreResumeRequirement,Get-WorkItemStoreResult, Set-WorkItemStoreEntry, Get-WorkItemStoreEffectReceipt
