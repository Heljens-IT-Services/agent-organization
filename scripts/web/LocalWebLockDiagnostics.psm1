Set-StrictMode -Version 2

function ConvertTo-LocalWebUtcTimestamp {
    param([string]$Value, [ref]$Result)
    $parsedOffset = [DateTimeOffset]::MinValue
    if ([DateTimeOffset]::TryParseExact($Value, 'o', [Globalization.CultureInfo]::InvariantCulture, [Globalization.DateTimeStyles]::None, [ref]$parsedOffset)) {
        if ($parsedOffset.Offset -ne [TimeSpan]::Zero) { return $false }
        $Result.Value = $parsedOffset
        return $true
    }
    $parsedUtc = [DateTime]::MinValue
    if ($Value -cmatch 'Z$' -and [DateTime]::TryParseExact($Value, 'o', [Globalization.CultureInfo]::InvariantCulture, [Globalization.DateTimeStyles]::RoundtripKind, [ref]$parsedUtc) -and $parsedUtc.Kind -eq [DateTimeKind]::Utc) {
        $Result.Value = [DateTimeOffset]$parsedUtc
        return $true
    }
    return $false
}

function Get-LocalWebLockDiagnostic {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][string]$StorePath)

    $started = [DateTime]::UtcNow
    $completed = $started
    $store = $null
    $dir = $null
    $reason = 'producer observations unavailable'
    $complete = 'unknown'
    $records = New-Object 'System.Collections.Generic.List[object]'
    $invalid = New-Object 'System.Collections.Generic.List[string]'
    $maxFiles = 256
    $maxFileBytes = 65536
    $maxTotalBytes = 1048576
    $totalBytes = 0

    function New-UnknownDiagnostic([string]$Why, [string]$Completeness, $Store, $Started, $Finished) {
        [pscustomobject][ordered]@{
            state = 'unknown'; observedAt = $Finished.ToString('o'); owner = $null; reason = $Why
            lifecycleEvent = $null; eventAtUtc = $null; sourceReference = $null; sourceRevision = $null
            originalMetadataHash = $null; lockId = $null; attemptOrdinal = $null
            readWindow = [pscustomobject][ordered]@{ startedAtUtc = $Started.ToString('o'); completedAtUtc = $Finished.ToString('o') }
            bindingStatus = 'producerLifecycle'; currentOwnership = 'unconfirmed'; completeness = $Completeness
            processIdentityStatus = 'unverified'
        }
    }

    try {
        $store = [IO.Path]::GetFullPath($StorePath)
        $dir = $store + '.lock-observations'
        if (-not [IO.Directory]::Exists($dir)) {
            $completed = [DateTime]::UtcNow
            return (New-UnknownDiagnostic 'producer observation directory is missing' 'missing' $store $started $completed)
        }
        $eligible = New-Object 'System.Collections.Generic.List[object]'
        $rx = '^(?<id>[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12})\.(?<ordinal>[1-9][0-9]*)\.(?<kind>acquired|terminal|acquisitionAborted)\.json$'
        foreach ($path in [IO.Directory]::EnumerateFiles($dir, '*', [IO.SearchOption]::TopDirectoryOnly)) {
            $name = [IO.Path]::GetFileName($path)
            if ($name -cmatch $rx) {
                $eligible.Add([pscustomobject]@{ Path=$path; Name=$name; Id=$Matches.id.ToLowerInvariant(); Ordinal=[long]$Matches.ordinal; Kind=$Matches.kind })
                if ($eligible.Count -gt $maxFiles) { break }
            }
        }
        if ($eligible.Count -eq 0) {
            $completed = [DateTime]::UtcNow
            return (New-UnknownDiagnostic 'no directly named producer lifecycle observations are available' 'missing' $store $started $completed)
        }
        if ($eligible.Count -gt $maxFiles) {
            $completed = [DateTime]::UtcNow
            return (New-UnknownDiagnostic "observation count exceeds limit ($maxFiles)" 'incomplete' $store $started $completed)
        }

        $budgetExceeded = $false
        foreach ($file in $eligible) {
            if ($budgetExceeded) { break }
            $fileBytes = 0
            try {
                $stream = [IO.File]::Open($file.Path, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::ReadWrite -bor [IO.FileShare]::Delete)
                try {
                    $readLimit = $maxFileBytes
                    $memory = New-Object IO.MemoryStream
                    try {
                        $buffer = New-Object byte[] 8192
                        while ($memory.Length -lt $readLimit) {
                            $availableTotal = $maxTotalBytes - $totalBytes
                            $availableFile = $maxFileBytes - $fileBytes
                            if ($availableTotal -le 0 -or $availableFile -le 0) { throw 'observation byte limit exceeded' }
                            $want = [int][Math]::Min([Math]::Min($buffer.Length, $readLimit - $memory.Length), [Math]::Min($availableTotal, $availableFile))
                            $read = $stream.Read($buffer, 0, $want)
                            if ($read -eq 0) { break }
                            $totalBytes += $read; $fileBytes += $read
                            $memory.Write($buffer, 0, $read)
                        }
                        $bytes = $memory.ToArray()
                    } finally { $memory.Dispose() }
                    $probe = $stream.ReadByte()
                    if ($probe -ne -1) {
                        $totalBytes++; $fileBytes++
                        throw 'observation byte limit exceeded'
                    }
                    $after = [IO.FileInfo]::new($file.Path).Length
                    [void]$stream.Seek(0, [IO.SeekOrigin]::Begin)
                    $confirmMemory = New-Object IO.MemoryStream
                    try {
                        while ($confirmMemory.Length -lt ($bytes.Length + 1)) {
                            $availableTotal = $maxTotalBytes - $totalBytes
                            $availableFile = $maxFileBytes - $fileBytes
                            if ($availableTotal -le 0 -or $availableFile -le 0) { throw 'observation byte limit exceeded' }
                            $want = [int][Math]::Min([Math]::Min($buffer.Length, ($bytes.Length + 1) - $confirmMemory.Length), [Math]::Min($availableTotal, $availableFile))
                            $read = $stream.Read($buffer, 0, $want)
                            if ($read -eq 0) { break }
                            $totalBytes += $read; $fileBytes += $read
                            $confirmMemory.Write($buffer, 0, $read)
                        }
                        $confirmBytes = $confirmMemory.ToArray()
                    } finally { $confirmMemory.Dispose() }
                } finally { $stream.Dispose() }
                if ($after -ne $bytes.Length -or $confirmBytes.Length -ne $bytes.Length -or [Convert]::ToBase64String($confirmBytes) -cne [Convert]::ToBase64String($bytes)) { throw 'readRace: observation changed during bounded read' }
                $utf8 = New-Object Text.UTF8Encoding($false, $true)
                $json = $utf8.GetString($bytes)
                $o = ConvertFrom-Json -InputObject $json -ErrorAction Stop
                if ($null -eq $o -or $o -is [array] -or $o -is [string] -or $o -is [ValueType]) { throw 'JSON root is not an object' }
                $digest = [Security.Cryptography.SHA256]::Create()
                try { $actualHash = ([BitConverter]::ToString($digest.ComputeHash($bytes))).Replace('-', '').ToLowerInvariant() } finally { $digest.Dispose() }
                $canonicalId = [Guid]::Empty
                if (-not [Guid]::TryParseExact([string]$o.lockId, 'D', [ref]$canonicalId) -or $canonicalId.ToString('D') -ne $file.Id) { throw 'lockId does not match canonical filename GUID' }
                $ordinal = 0L
                if ($o.attemptOrdinal -isnot [long] -and $o.attemptOrdinal -isnot [int] -and $o.attemptOrdinal -isnot [int64]) { throw 'attemptOrdinal has invalid type' }
                $ordinal = [long]$o.attemptOrdinal
                if ($ordinal -lt 1 -or $ordinal -ne $file.Ordinal) { throw 'attemptOrdinal does not match filename' }
                if ([string]$o.diagnosticVersion -cne '1' -or [string]$o.observationScope -cne 'producerLifecycle') { throw 'unsupported diagnostic version or observation scope' }
                $expectedEvent = switch ($file.Kind) { acquired { 'acquired' } terminal { @('released','releaseUnconfirmed') } acquisitionAborted { 'acquisitionAborted' } }
                if (($expectedEvent -is [string] -and [string]$o.event -cne $expectedEvent) -or ($expectedEvent -is [array] -and [string]$o.event -cnotin $expectedEvent)) { throw 'event type does not match filename' }
                if ([IO.Path]::GetFullPath([string]$o.storePath) -cne $store -or [string]$o.lockPath -cne ($store + '.lock')) { throw 'storePath or lockPath binding mismatch' }
                $eventTime = [DateTimeOffset]::MinValue
                if ($o.eventAtUtc -isnot [string] -or -not (ConvertTo-LocalWebUtcTimestamp ([string]$o.eventAtUtc) ([ref]$eventTime))) { throw 'eventAtUtc is not a round-trip UTC timestamp' }
                $acquiredTime = [DateTimeOffset]::MinValue
                if ($o.acquiredAtUtc -isnot [string] -or -not (ConvertTo-LocalWebUtcTimestamp ([string]$o.acquiredAtUtc) ([ref]$acquiredTime))) { throw 'acquiredAtUtc is not a round-trip UTC timestamp' }
                if ($o.processId -isnot [int] -and $o.processId -isnot [long]) { throw 'processId has invalid type' }
                foreach ($field in @('ownerSid','ownerName','host','machineGuid','processStartedAtUtc','originalMetadataHash')) { if ($o.$field -isnot [string]) { throw "$field has invalid type" } }
                $processStart = [DateTimeOffset]::MinValue
                if (-not (ConvertTo-LocalWebUtcTimestamp ([string]$o.processStartedAtUtc) ([ref]$processStart))) { throw 'processStartedAtUtc is not a round-trip UTC timestamp' }
                if ([string]$o.originalMetadataHash -cnotmatch '^[0-9a-f]{64}$') { throw 'originalMetadataHash is invalid' }
                if ($null -eq $o.sourceReference -or $o.sourceReference.modulePath -isnot [string] -or $o.sourceReference.sha256 -isnot [string] -or [string]$o.sourceReference.sha256 -cnotmatch '^[0-9a-f]{64}$') { throw 'sourceReference is invalid' }
                if ($null -ne $o.failureCode -and $o.failureCode -isnot [string]) { throw 'failureCode has invalid type' }
                if ($file.Kind -eq 'terminal' -and $null -ne $o.acquiredHash -and [string]$o.acquiredHash -cnotmatch '^[0-9a-f]{64}$') { throw 'acquiredHash is invalid' }
                if ($file.Kind -eq 'terminal') {
                    $missingProperty = $o.PSObject.Properties['acquisitionEvidenceMissing']
                    $hashProperty = $o.PSObject.Properties['acquiredHash']
                    if ($null -ne $missingProperty -and $missingProperty.Value -isnot [bool]) { throw 'invalidAcquisitionEvidenceFlag' }
                    if ($null -ne $missingProperty -and $missingProperty.Value -eq $true -and $null -ne $hashProperty -and -not [string]::IsNullOrEmpty([string]$hashProperty.Value)) { throw 'conflictingAcquisitionEvidence' }
                    if (($null -eq $missingProperty -or $missingProperty.Value -ne $true) -and ($null -eq $hashProperty -or [string]::IsNullOrEmpty([string]$hashProperty.Value))) { throw 'conflictingAcquisitionEvidence' }
                }
                $source = ([string]$o.sourceReference.modulePath) + '#sha256=' + ([string]$o.sourceReference.sha256) + '; observation=' + $file.Name
                $records.Add([pscustomobject]@{ File=$file; Data=$o; BytesHash=$actualHash; EventTime=$eventTime; AcquiredTime=$acquiredTime; Source=$source })
            } catch {
                $code = if ($_.Exception.Message -like '*byte limit exceeded*') { 'byteLimitExceeded' } elseif ($_.Exception.Message -like '*readRace*') { 'readRace' } else { 'observationInvalid' }
                $invalid.Add($file.Name + ':' + $code)
                if ($code -eq 'byteLimitExceeded') { $budgetExceeded = $true }
            }
        }
        $completed = [DateTime]::UtcNow
        if ($budgetExceeded) { return (New-UnknownDiagnostic "observation bytes exceed limit ($maxTotalBytes)" 'incomplete' $store $started $completed) }
        if ($totalBytes -gt $maxTotalBytes) { return (New-UnknownDiagnostic "observation bytes exceed limit ($maxTotalBytes)" 'incomplete' $store $started $completed) }
        if ($invalid.Count -gt 0) {
            $details = @($invalid | Sort-Object -Unique)
            $classification = if (($details -join '; ') -match 'readRace|byteLimitExceeded') { 'incomplete' } else { 'invalid' }
            return (New-UnknownDiagnostic ('observationInvalid; files=' + ($details -join ', ')) $classification $store $started $completed)
        }
        if ($records.Count -eq 0) { return (New-UnknownDiagnostic 'no valid producer observations were read' 'invalid' $store $started $completed) }

        $groups = @{}
        foreach ($r in $records) {
            $key = $r.File.Id + '.' + $r.File.Ordinal
            if (-not $groups.ContainsKey($key)) { $groups[$key] = @{} }
            $groups[$key][$r.File.Kind] = $r
        }
        $bound = New-Object 'System.Collections.Generic.List[object]'
        foreach ($key in $groups.Keys) {
            $g = $groups[$key]
            if ($g.ContainsKey('acquired') -and $g.ContainsKey('acquisitionAborted')) { return (New-UnknownDiagnostic "generation $key has conflicting acquired and acquisitionAborted events" 'invalid' $store $started $completed) }
            if ($g.ContainsKey('terminal')) {
                if (-not $g.ContainsKey('acquired')) { return (New-UnknownDiagnostic "terminal event $key has no acquired evidence" 'invalid' $store $started $completed) }
                $a = $g.acquired; $t = $g.terminal
                if ($a.EventTime.UtcDateTime.Ticks -lt $a.AcquiredTime.UtcDateTime.Ticks -or $t.EventTime.UtcDateTime.Ticks -lt $a.EventTime.UtcDateTime.Ticks) { return (New-UnknownDiagnostic 'generation chronology is contradictory' 'invalid' $store $started $completed) }
                if ([string]$t.Data.acquiredHash -cne $a.BytesHash) { return (New-UnknownDiagnostic "terminal event $key acquiredHash does not bind exact acquired bytes" 'invalid' $store $started $completed) }
                foreach ($field in @('lockId','storePath','lockPath','attemptOrdinal','acquiredAtUtc','ownerSid','ownerName','processId','processStartedAtUtc','host','machineGuid','originalMetadataHash')) {
                    if ([string]$a.Data.$field -cne [string]$t.Data.$field) { return (New-UnknownDiagnostic "terminal event $key metadata binding mismatch at $field" 'invalid' $store $started $completed) }
                }
                if ([string]$a.Data.sourceReference.modulePath -cne [string]$t.Data.sourceReference.modulePath -or [string]$a.Data.sourceReference.sha256 -cne [string]$t.Data.sourceReference.sha256) { return (New-UnknownDiagnostic "terminal event $key producer source binding mismatch" 'invalid' $store $started $completed) }
                $bound.Add($t)
            } elseif ($g.ContainsKey('acquired')) {
                if ($g.acquired.EventTime.UtcDateTime.Ticks -lt $g.acquired.AcquiredTime.UtcDateTime.Ticks) { return (New-UnknownDiagnostic 'generation chronology is contradictory' 'invalid' $store $started $completed) }
                $bound.Add($g.acquired)
            }
            elseif ($g.ContainsKey('acquisitionAborted')) {
                if ($g.acquisitionAborted.EventTime.UtcDateTime.Ticks -lt $g.acquisitionAborted.AcquiredTime.UtcDateTime.Ticks) { return (New-UnknownDiagnostic 'aborted acquisition chronology is contradictory' 'invalid' $store $started $completed) }
                $bound.Add($g.acquisitionAborted)
            }
        }
        if ($bound.Count -eq 0) { return (New-UnknownDiagnostic 'no lifecycle observation has a usable producer binding' 'invalid' $store $started $completed) }
        if ($bound.Count -gt 1) {
            $ordered = @($bound | Sort-Object { $_.EventTime.UtcDateTime.Ticks } -Descending)
            if ($ordered[0].EventTime.UtcDateTime.Ticks -eq $ordered[1].EventTime.UtcDateTime.Ticks) { return (New-UnknownDiagnostic 'multiple generations have indistinguishable lifecycle times' 'incomplete' $store $started $completed) }
            $latest = $ordered[0]
            $intervals = @()
            foreach ($entry in $ordered) {
                $entryKey = $entry.File.Id + '.' + $entry.File.Ordinal
                $entryGroup = $groups[$entryKey]
                if ($entryGroup.ContainsKey('acquired')) {
                    $startTicks = $entryGroup.acquired.AcquiredTime.UtcDateTime.Ticks
                    $endTicks = if ($entryGroup.ContainsKey('terminal')) { $entryGroup.terminal.EventTime.UtcDateTime.Ticks } else { [long]::MaxValue }
                    if ($endTicks -eq [long]::MaxValue) { return (New-UnknownDiagnostic 'generation history contains an open interval' 'incomplete' $store $started $completed) }
                } else {
                    $startTicks = $entry.AcquiredTime.UtcDateTime.Ticks; $endTicks = $entry.EventTime.UtcDateTime.Ticks
                }
                $intervals += [pscustomobject]@{ Start=$startTicks; End=$endTicks }
            }
            $intervals = @($intervals | Sort-Object Start, End)
            for ($i = 1; $i -lt $intervals.Count; $i++) {
                if ($intervals[$i].Start -le $intervals[$i - 1].End) { return (New-UnknownDiagnostic 'generation histories overlap or are temporally ambiguous' 'incomplete' $store $started $completed) }
            }
        } else {
            $latest = $bound[0]
            if ([string]$latest.Data.event -eq 'acquired') { return (New-UnknownDiagnostic 'generation history contains an open interval' 'incomplete' $store $started $completed) }
        }

        $e = $latest.Data
        $owner = $null
        $historicalOwner = [pscustomobject][ordered]@{ name=$e.ownerName; host=$e.host; processId=[long]$e.processId; processStartedAtUtc=$e.processStartedAtUtc; acquiredAtUtc=$e.acquiredAtUtc }
        $state = 'unknown'; $why = 'producer lifecycle event is historical; active original-handle ownership is unconfirmed'
        switch ([string]$e.event) {
            acquired { $state='ownerObserved'; $owner=$historicalOwner; $why='producer recorded acquisition; current original-handle ownership is unconfirmed' }
            released { $state='released'; $why='release of this generation confirmed; current ownership is unknown' }
            releaseUnconfirmed { $state='unknown'; $why='producer could not confirm release; current ownership is unconfirmed' }
            acquisitionAborted { $state='unknown'; $why='producer recorded an aborted acquisition attempt; no ownership is asserted' }
        }
        $result = [ordered]@{
            state=$state; observedAt=$completed.ToString('o'); owner=$owner; reason=$why
            lifecycleEvent=[string]$e.event; eventAtUtc=[string]$e.eventAtUtc; sourceReference=$latest.Source; sourceRevision=$latest.BytesHash
            originalMetadataHash=[string]$e.originalMetadataHash; lockId=[string]$e.lockId; attemptOrdinal=[long]$e.attemptOrdinal
            readWindow=[pscustomobject][ordered]@{ startedAtUtc=$started.ToString('o'); completedAtUtc=$completed.ToString('o') }
            bindingStatus='producerLifecycle'; currentOwnership='unconfirmed'; completeness='bounded'
            processIdentityStatus='unverified'
        }
        if ([string]$e.event -eq 'released' -or [string]$e.event -eq 'releaseUnconfirmed') { $result.historicalOwner=$historicalOwner }
        return [pscustomobject]$result
    } catch {
        $completed = [DateTime]::UtcNow
        return (New-UnknownDiagnostic 'lockDiagnosticReadFailed: observation source could not be read safely' 'unknown' $store $started $completed)
    }
}

Export-ModuleMember -Function Get-LocalWebLockDiagnostic
