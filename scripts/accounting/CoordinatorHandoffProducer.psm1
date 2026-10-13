Set-StrictMode -Version Latest

$script:MaxFile = 67108864L
$script:MaxRange = 16777216L
$script:MaxManifest = 1048576L
$script:MaxMarker = 256L

function Get-HandoffSha256 {
    param([Parameter(Mandatory)][byte[]] $Bytes)
    $hash = [Security.Cryptography.SHA256]::Create()
    try { ([BitConverter]::ToString($hash.ComputeHash($Bytes))).Replace('-', '').ToLowerInvariant() }
    finally { $hash.Dispose() }
}

function Get-HandoffProperty {
    param($Object, [string] $Name)
    if ($null -eq $Object) { return $null }
    $property = $Object.PSObject.Properties[$Name]
    if ($null -eq $property) { return $null }
    return $property.Value
}

function Assert-HandoffFields {
    param($Object, [string[]] $Names, [string] $Label)
    $values = [ordered]@{}
    foreach ($name in $Names) {
        $value = Get-HandoffProperty $Object $name
        if ($null -eq $value -or [string]::IsNullOrWhiteSpace([string]$value)) {
            throw "$Label field missing or empty: $name"
        }
        $values[$name] = $value
    }
    return $values
}

function Read-HandoffSnapshot {
    param(
        [Parameter(Mandatory)][string] $Path,
        [long] $Offset = 0,
        [long] $Length = 0,
        [long] $Limit = 67108864,
        [long] $RangeLimit = 16777216,
        [switch] $WholeOnly
    )
    if ($Offset -lt 0) { throw 'OriginalByteRangeInvalid' }
    if (-not $WholeOnly -and ($Length -le 0 -or $Length -gt $RangeLimit -or $Length -gt $script:MaxRange -or $Offset -gt [long]::MaxValue - $Length)) {
        throw 'OriginalByteRangeInvalid'
    }
    $fullPath = [IO.Path]::GetFullPath($Path)
    $stream = $null
    try {
        $stream = [IO.File]::Open($fullPath, 'Open', 'Read', ([IO.FileShare]::ReadWrite -bor [IO.FileShare]::Delete))
        $size = $stream.Length
        if ($size -gt $Limit -or $size -gt $script:MaxFile -or $size -gt [int]::MaxValue) {
            throw 'OriginalSourceTooLarge'
        }
        if (-not $WholeOnly -and $Offset + $Length -gt $size) { throw 'OriginalByteRangeLimitOrBounds' }
        $bytes = [byte[]]::new([int]$size)
        $position = 0
        while ($position -lt $bytes.Length) {
            $read = $stream.Read($bytes, $position, [Math]::Min(65536, $bytes.Length - $position))
            if ($read -le 0) { throw 'OriginalTruncatedDuringCapture' }
            $position += $read
        }
        $slice = $null
        if (-not $WholeOnly) {
            $slice = [byte[]]::new([int]$Length)
            [Array]::Copy($bytes, [int]$Offset, $slice, 0, [int]$Length)
        }
        return [pscustomobject]@{
            Path = $fullPath; Bytes = $bytes; Slice = $slice
            SourceSha256 = Get-HandoffSha256 $bytes
            SliceSha256 = if ($null -ne $slice) { Get-HandoffSha256 $slice } else { $null }
        }
    }
    finally { if ($null -ne $stream) { $stream.Dispose() } }
}

function Read-HandoffRange {
    param([string] $Path, [long] $Offset, [long] $Length, [long] $MaxFile = 67108864, [long] $MaxRange = 16777216)
    if ($MaxFile -le 0 -or $MaxFile -gt $script:MaxFile -or $MaxRange -le 0 -or $MaxRange -gt $script:MaxRange) {
        throw 'ReadLimitExceedsContract'
    }
    return (Read-HandoffSnapshot -Path $Path -Offset $Offset -Length $Length -Limit $MaxFile -RangeLimit $MaxRange).Slice
}

function Write-HandoffNewFile {
    param([Parameter(Mandatory)][string] $Path, [Parameter(Mandatory)][byte[]] $Bytes)
    $stream = [IO.File]::Open($Path, 'CreateNew', 'Write', 'None')
    try {
        $position = 0
        while ($position -lt $Bytes.Length) {
            $count = [Math]::Min(65536, $Bytes.Length - $position)
            $stream.Write($Bytes, $position, $count)
            $position += $count
        }
        $stream.Flush($true)
    }
    finally { $stream.Dispose() }
}

function Get-HandoffIdentity {
    param($Record)
    $names = @('schema','rootId','owner','version','boundaryId','rootGeneration','provider','generation','threadId','turnId','originalPath','byteOffset','byteLength','sourceSha256','sliceSha256')
    $identity = Assert-HandoffFields $Record $names 'Manifest identity'
    foreach($name in $names){
        if($name -in @('byteOffset','byteLength')){
            if($identity[$name] -isnot [byte] -and $identity[$name] -isnot [int16] -and $identity[$name] -isnot [int32] -and $identity[$name] -isnot [int64]){throw 'ManifestRangeTypeInvalid'}
        } elseif($identity[$name] -isnot [string]){throw "ManifestFieldTypeInvalid:$name"}
    }
    if($identity.byteOffset -lt 0 -or $identity.byteLength -le 0 -or $identity.byteLength -gt $script:MaxRange -or $identity.byteOffset -gt [long]::MaxValue-$identity.byteLength){throw 'ManifestRangeInvalid'}
    foreach($name in @('sourceSha256','sliceSha256')){if($identity[$name] -cnotmatch '^[0-9a-f]{64}$'){throw 'ManifestHashInvalid'}}
    if ($identity.schema -cne 'handoff-original-bytes-v3') { throw 'ArchiveSchemaMismatch' }

    return $identity
}

function Assert-HandoffInventoryList {
    param($Value, [string] $Name)
    if ($null -eq $Value -or $Value -is [string] -or $Value -isnot [System.Collections.IEnumerable]) { throw "InventoryListTypeInvalid: $Name" }
    $items = @($Value)
    foreach ($item in $items) {
        if ($null -eq $item -or $item -is [string] -or $item -is [ValueType]) { throw "InventoryItemTypeInvalid: $Name" }
        [void](Get-HandoffTupleKey $item)
    }
    return ,$items
}

function Assert-HandoffMeasurementShape {
    param($Measurement)
    $fields = Assert-HandoffFields $Measurement @('provider','generation','threadId','turnId','sourcePath','byteOffset','byteLength','sourceSha256','sha256','archiveSha256','rootGeneration') 'Original measurement'
    foreach ($name in @('provider','generation','threadId','turnId','sourcePath','sourceSha256','sha256','archiveSha256','rootGeneration')) {
        if ($fields[$name] -isnot [string]) { throw "OriginalMeasurementFieldTypeInvalid: $name" }
    }
    foreach ($name in @('byteOffset','byteLength')) {
        if ($fields[$name] -isnot [byte] -and $fields[$name] -isnot [int16] -and $fields[$name] -isnot [int32] -and $fields[$name] -isnot [int64]) { throw "OriginalMeasurementFieldTypeInvalid: $name" }
    }
    if($fields.byteOffset -lt 0 -or $fields.byteLength -le 0 -or $fields.byteLength -gt $script:MaxRange -or $fields.byteOffset -gt [long]::MaxValue-$fields.byteLength){throw 'MeasurementRangeInvalid'}
    foreach($name in @('sourceSha256','sha256','archiveSha256')){if($fields[$name] -cnotmatch '^[0-9a-f]{64}$'){throw 'MeasurementHashInvalid'}}
    return $fields
}

function Get-HandoffTupleKey {
    param($Tuple)
    $values = @()
    foreach ($name in @('provider','generation','threadId','turnId')) {
        $value = Get-HandoffProperty $Tuple $name
        if ($value -isnot [string] -or [string]::IsNullOrWhiteSpace($value)) { throw "TupleFieldTypeInvalid: $name" }
        $values += ,([string]$value)
    }
    return ConvertTo-Json -InputObject $values -Compress
}

function Get-HandoffBoundInput {
    param($InputRecord)
    $reference = Get-HandoffProperty $InputRecord 'originalInput'
    $inputFields = Assert-HandoffFields $reference @('path','byteOffset','byteLength','sha256','sourceSha256') 'Original input'
    foreach($name in @('path','sha256','sourceSha256')){if($inputFields[$name] -isnot [string]){throw 'InputReferenceTypeInvalid'}}
    foreach($name in @('byteOffset','byteLength')){if($inputFields[$name] -isnot [int] -and $inputFields[$name] -isnot [long]){throw 'InputRangeTypeInvalid'}}
    $offset = [long]$inputFields.byteOffset
    $length = [long]$inputFields.byteLength
    $snapshot = Read-HandoffSnapshot -Path ([string]$inputFields.path) -Offset $offset -Length $length
    if ($snapshot.SliceSha256 -cne [string]$inputFields.sha256 -or $snapshot.SourceSha256 -cne [string]$inputFields.sourceSha256) {
        throw 'OriginalInputPinMismatch'
    }
    $record = [Text.UTF8Encoding]::new($false, $true).GetString($snapshot.Slice) | ConvertFrom-Json -ErrorAction Stop
    return [pscustomobject]@{ Record = $record; Snapshot = $snapshot; Range = $inputFields }
}

function Get-HandoffCanonicalArchivePaths {
    param($Measurement, $Manifest)
    $identity = Get-HandoffIdentity $Manifest
    $keyBytes = [Text.UTF8Encoding]::new($false).GetBytes(($identity | ConvertTo-Json -Compress -Depth 8))
    $key = Get-HandoffSha256 $keyBytes
    $manifestPath = [IO.Path]::GetFullPath([string](Get-HandoffProperty $Measurement 'manifestPath'))
    $manifestDirectory = [IO.Path]::GetDirectoryName($manifestPath)
    $blob = [IO.Path]::GetFullPath((Join-Path $manifestDirectory "$key.bytes"))
    $canonicalManifest = [IO.Path]::GetFullPath((Join-Path $manifestDirectory "$key.json"))
    $marker = [IO.Path]::GetFullPath((Join-Path $manifestDirectory "$key.committed"))
    $manifestArchivePath = Get-HandoffProperty $Manifest 'archivePath'
    if ($null -eq $manifestArchivePath -or [IO.Path]::GetFullPath([string]$manifestArchivePath) -cne $blob) { throw 'ManifestArchivePathNotCanonical' }
    foreach ($pair in @(@('archivePath',$blob),@('manifestPath',$canonicalManifest),@('committedPath',$marker))) {
        $given = Get-HandoffProperty $Measurement $pair[0]
        if ($null -eq $given -or [IO.Path]::GetFullPath([string]$given) -cne $pair[1]) { throw "NonCanonicalArchivePath: $($pair[0])" }
    }
    return [pscustomobject]@{ Key=$key; Blob=$blob; Manifest=$canonicalManifest; Marker=$marker; Identity=$identity }
}


function Assert-HandoffStrings {
    param($Object,[string[]]$Names,[string]$Label)
    $fields=Assert-HandoffFields $Object $Names $Label
    foreach($name in $Names){if($fields[$name] -isnot [string]){throw "FieldTypeInvalid:$Label/$name"}}
    return $fields
}
function Get-HandoffCheckedInventory {
    param($Bound)
    $source=Assert-HandoffStrings $Bound.Record @('rootId','owner','version','rootGeneration') 'Source'
    $boundary=Assert-HandoffStrings (Get-HandoffProperty $Bound.Record 'captureBoundary') @('id') 'Boundary'
    $expected=[Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    foreach($turn in (Assert-HandoffInventoryList (Get-HandoffProperty $Bound.Record 'expectedTurns') 'expectedTurns')){
        if(-not $expected.Add((Get-HandoffTupleKey $turn))){throw 'DuplicateExpectedTuple'}
    }
    $original=[Collections.Generic.Dictionary[string,object]]::new([StringComparer]::Ordinal)
    foreach($item in (Assert-HandoffInventoryList (Get-HandoffProperty $Bound.Record 'originalMeasurements') 'originalMeasurements')){
        $fields=Assert-HandoffMeasurementShape $item; $tuple=Get-HandoffTupleKey $item
        if($original.ContainsKey($tuple)){throw 'DuplicateOriginalTuple'}
        if($fields.rootGeneration -cne $source.rootGeneration){throw 'RootGenerationConflict'}
        $copy=[ordered]@{}; foreach($name in $fields.Keys){$copy[$name]=$fields[$name]}
        $original.Add($tuple,[pscustomobject]@{Fields=$copy;Record=[pscustomobject]$copy})
    }
    foreach($tuple in $expected){if(-not $original.ContainsKey($tuple)){throw "ExpectedMeasurementMissing:$tuple"}}
    foreach($tuple in $original.Keys){if(-not $expected.Contains($tuple)){throw "UnexpectedMeasurement:$tuple"}}
    return [pscustomobject]@{Bound=$Bound;SourceFields=$source;BoundaryFields=$boundary;Expected=$expected;OriginalByTuple=$original}
}
function Get-HandoffPublicationPlan {
    param($Prepared,[string]$ArchiveDirectory)
    $identity=$Prepared.Identity
    $key=Get-HandoffSha256 ([Text.UTF8Encoding]::new($false).GetBytes(($identity|ConvertTo-Json -Depth 8 -Compress)))
    $directory=[IO.Path]::GetFullPath($ArchiveDirectory)
    $record=[ordered]@{}; foreach($name in $identity.Keys){$record[$name]=$identity[$name]}
    $record.archivePath=Join-Path $directory "$key.bytes"; $record.archiveSha256=$identity.sliceSha256
    return [pscustomobject]@{Key=$key;Prepared=$Prepared;Directory=$directory;Record=[pscustomobject]$record;
        Blob=$record.archivePath;Manifest=(Join-Path $directory "$key.json");Marker=(Join-Path $directory "$key.committed");
        StageBlob=(Join-Path $directory "$key.bytes.stage");StageManifest=(Join-Path $directory "$key.json.stage");StageMarker=(Join-Path $directory "$key.committed.stage");
        ManifestBytes=[Text.UTF8Encoding]::new($false).GetBytes(($record|ConvertTo-Json -Depth 8))}
}
function Read-HandoffPublicationState {
    param($Plan)
    # One bounded binding for whole-batch preflight, replay and postpublication.
    $all=@($Plan.Blob,$Plan.Manifest,$Plan.Marker,$Plan.StageBlob,$Plan.StageManifest,$Plan.StageMarker)
    foreach($path in $all){
        if([IO.Directory]::Exists($path)){throw 'ArchiveDestinationIsDirectory'}
        $parent=[IO.Path]::GetDirectoryName([IO.Path]::GetFullPath($path))
        while($parent){if([IO.File]::Exists($parent)){throw 'PublicationParentIsFile'};$next=[IO.Path]::GetDirectoryName($parent);if($next -ceq $parent){break};$parent=$next}
    }
    $present=@($all|Where-Object{[IO.File]::Exists($_)})
    if($present.Count -eq 0){return 'Absent'}
    if($present.Count -ne 3 -or -not ([IO.File]::Exists($Plan.Blob) -and [IO.File]::Exists($Plan.Manifest) -and [IO.File]::Exists($Plan.Marker)) -or
        [IO.File]::Exists($Plan.StageBlob) -or [IO.File]::Exists($Plan.StageManifest) -or [IO.File]::Exists($Plan.StageMarker)){throw 'ExistingArchiveArtifactsRetainedRecoveryRequired'}
    $mb=(Read-HandoffSnapshot -Path $Plan.Manifest -Limit $script:MaxManifest -WholeOnly).Bytes
    if([Convert]::ToBase64String($mb) -cne [Convert]::ToBase64String($Plan.ManifestBytes)){throw 'ReplayManifestConflict'}
    $saved=[Text.UTF8Encoding]::new($false,$true).GetString($mb)|ConvertFrom-Json -ErrorAction Stop
    $id=Get-HandoffIdentity $saved
    if((Get-HandoffTupleKey $id) -cne (Get-HandoffTupleKey $Plan.Prepared.Identity) -or $saved.archivePath -cne $Plan.Blob -or $saved.archiveSha256 -cne $id.sliceSha256){throw 'ReplayIdentityConflict'}
    $marker=(Read-HandoffSnapshot -Path $Plan.Marker -Limit $script:MaxMarker -WholeOnly).Bytes
    if([Text.UTF8Encoding]::new($false,$true).GetString($marker) -cne "$($Plan.Key)`n"){throw 'ReplayMarkerConflict'}
    $blob=(Read-HandoffSnapshot -Path $Plan.Blob -Limit $script:MaxRange -WholeOnly).Bytes
    if($blob.Length -ne $Plan.Prepared.Snapshot.Slice.Length -or (Get-HandoffSha256 $blob) -cne $id.sliceSha256 -or (Get-HandoffSha256 $blob) -cne $saved.archiveSha256){throw 'ReplayBlobConflict'}
    return 'Committed'
}

function Copy-HandoffPreparedSnapshot {
    param([Parameter(Mandatory)] $Prepared, [Parameter(Mandatory)][string] $ArchiveDirectory)
    if ($Prepared -isnot [pscustomobject] -or $null -eq $Prepared.Snapshot -or $null -eq $Prepared.Identity) { throw 'InternalPreparedSnapshotRequired' }
    $snapshot = $Prepared.Snapshot
    $identity = $Prepared.Identity
    if ($snapshot.SourceSha256 -cne $identity.sourceSha256 -or $snapshot.SliceSha256 -cne $identity.sliceSha256) { throw 'PreparedSnapshotPinMismatch' }
    $plan=Get-HandoffPublicationPlan $Prepared $ArchiveDirectory
    if((Read-HandoffPublicationState $plan) -ceq 'Committed'){return $plan.Record}
    [IO.Directory]::CreateDirectory($plan.Directory)|Out-Null
    try {
        $marker=[Text.UTF8Encoding]::new($false).GetBytes("$($plan.Key)`n")
        foreach($pair in @(@($plan.StageBlob,$snapshot.Slice,$script:MaxRange),@($plan.StageManifest,$plan.ManifestBytes,$script:MaxManifest),@($plan.StageMarker,$marker,$script:MaxMarker))){
            Write-HandoffNewFile $pair[0] $pair[1]
            $rb=(Read-HandoffSnapshot -Path $pair[0] -Limit $pair[2] -WholeOnly).Bytes
            if([Convert]::ToBase64String($rb) -cne [Convert]::ToBase64String($pair[1])){throw 'StageReadbackConflict'}
        }
        [IO.File]::Move($plan.StageBlob,$plan.Blob); [IO.File]::Move($plan.StageManifest,$plan.Manifest); [IO.File]::Move($plan.StageMarker,$plan.Marker)
        if((Read-HandoffPublicationState $plan) -cne 'Committed'){throw 'PublicationNotCommitted'}
    } catch {throw 'ImmutableArchivePublicationIncompleteRecoveryRequired; retain all artifacts'}
    return $plan.Record
}

function Copy-HandoffImmutableBytes {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string] $SourcePath,
        [Parameter(Mandatory)][string] $ArchiveDirectory,
        [Parameter(Mandatory)][string] $Provider,
        [Parameter(Mandatory)][string] $Generation,
        [Parameter(Mandatory)][string] $ThreadId,
        [Parameter(Mandatory)][string] $TurnId,
        [Parameter(Mandatory)][long] $ByteOffset,
        [Parameter(Mandatory)][long] $ByteLength,
        [Parameter(Mandatory)][string] $RootId,
        [Parameter(Mandatory)][string] $Owner,
        [Parameter(Mandatory)][string] $Version,
        [Parameter(Mandatory)][string] $BoundaryId,
        [Parameter(Mandatory)][string] $RootGeneration,
        [Parameter(Mandatory)][string] $SourceSha256,
        [Parameter(Mandatory)][string] $SliceSha256
    )
    $snapshot = Read-HandoffSnapshot -Path $SourcePath -Offset $ByteOffset -Length $ByteLength
    if ($snapshot.SourceSha256 -cne $SourceSha256 -or $snapshot.SliceSha256 -cne $SliceSha256) { throw 'IndependentSourcePinMismatch' }
    $identity = [ordered]@{
        schema='handoff-original-bytes-v3'; rootId=$RootId; owner=$Owner; version=$Version; boundaryId=$BoundaryId
        rootGeneration=$RootGeneration; provider=$Provider; generation=$Generation; threadId=$ThreadId; turnId=$TurnId
        originalPath=$snapshot.Path; byteOffset=$ByteOffset; byteLength=$ByteLength
        sourceSha256=$snapshot.SourceSha256; sliceSha256=$snapshot.SliceSha256
    }
    $prepared = [pscustomobject]@{ Snapshot=$snapshot; Identity=$identity }
    return Copy-HandoffPreparedSnapshot -Prepared $prepared -ArchiveDirectory $ArchiveDirectory
}

function Get-HandoffPreparedProjection {
    param($Context, [object[]] $ArchiveReferences, [object[]] $PreparedSnapshots)
    $Bound=$Context.Bound; $sourceFields=$Context.SourceFields; $boundaryFields=$Context.BoundaryFields
    $originalByTuple=$Context.OriginalByTuple; $expected=$Context.Expected

    $refs = @()
    if ($null -ne $ArchiveReferences) { $refs = @($ArchiveReferences) }
    elseif ($null -ne $PreparedSnapshots) { $refs = @($PreparedSnapshots | ForEach-Object { $_.Reference }) }
    else { throw 'ArchiveReferencesRequired' }

    $rows = [Collections.Generic.List[object]]::new()
    $missing = [Collections.Generic.List[string]]::new()
    $seen = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    $good = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    foreach ($reference in $refs) {
        $tuple = Get-HandoffTupleKey $reference
        try {
            if (-not $seen.Add($tuple)) { throw 'DuplicateArchiveReferenceTuple' }
            if (-not $originalByTuple.ContainsKey($tuple)) { throw 'UnexpectedArchiveReferenceTuple' }
            $original = $originalByTuple[$tuple]
            foreach ($name in @('provider','generation','threadId','turnId','sourcePath','byteOffset','byteLength','sourceSha256','sha256','archiveSha256','rootGeneration')) {
                $actual = Get-HandoffProperty $reference $name
                if ($null -ne $actual -and [string]$actual -cne [string](Get-HandoffProperty $original.Record $name)) { throw "OriginalProvenanceConflict: $name" }
            }
            $manifestPath = [string](Get-HandoffProperty $reference 'manifestPath')
            if ([string]::IsNullOrWhiteSpace($manifestPath)) { throw 'ManifestPathMissing' }
            $manifestSnapshot = Read-HandoffSnapshot -Path $manifestPath -Offset 0 -Length 1 -Limit $script:MaxManifest -WholeOnly
            $manifest = [Text.Encoding]::UTF8.GetString($manifestSnapshot.Bytes) | ConvertFrom-Json -ErrorAction Stop
            $paths = Get-HandoffCanonicalArchivePaths $reference $manifest
            $markerBytes = Read-HandoffSnapshot -Path $paths.Marker -Offset 0 -Length 1 -Limit $script:MaxMarker -WholeOnly
            if ([Text.Encoding]::UTF8.GetString($markerBytes.Bytes) -cne "$($paths.Key)`n") { throw 'MarkerIdentityConflict' }
            $identity = $paths.Identity
            foreach ($pair in @(@('rootId',$sourceFields.rootId),@('owner',$sourceFields.owner),@('version',$sourceFields.version),@('boundaryId',$boundaryFields.id),@('rootGeneration',$sourceFields.rootGeneration))) {
                if ([string]$identity[$pair[0]] -cne [string]$pair[1]) { throw "ManifestSourceIdentityConflict: $($pair[0])" }
            }
            $origin = $original.Fields
            if ((Get-HandoffTupleKey $identity) -cne $tuple) { throw 'ManifestOriginalTupleConflict' }
            foreach ($pair in @(@('originalPath',[IO.Path]::GetFullPath([string]$origin.sourcePath)),@('byteOffset',[long]$origin.byteOffset),@('byteLength',[long]$origin.byteLength),@('sourceSha256',[string]$origin.sourceSha256),@('sliceSha256',[string]$origin.sha256),@('rootGeneration',[string]$origin.rootGeneration))) {
                if ([string]$identity[$pair[0]] -cne [string]$pair[1]) { throw "ManifestOriginalProvenanceConflict: $($pair[0])" }
            }
            if ([string]$manifest.archiveSha256 -cne [string]$origin.archiveSha256 -or [string]$manifest.archiveSha256 -cne [string]$origin.sha256) { throw 'ManifestArchiveHashConflict' }
            if ($null -ne $PreparedSnapshots) {
                $prepared = @($PreparedSnapshots | Where-Object { $_.Tuple -ceq $tuple }) | Select-Object -First 1
                if ($null -eq $prepared -or $prepared.Snapshot.SourceSha256 -cne [string]$origin.sourceSha256 -or $prepared.Snapshot.SliceSha256 -cne [string]$origin.sha256) { throw 'PreparedSnapshotBindingConflict' }
                $archiveBytes = $prepared.ArchiveBytes
            }
            else { $archiveBytes = (Read-HandoffSnapshot -Path $paths.Blob -Offset 0 -Length ([long]$identity.byteLength)).Bytes }
            if ($archiveBytes.Length -ne [long]$identity.byteLength -or (Get-HandoffSha256 $archiveBytes) -cne [string]$origin.archiveSha256) { throw 'ArchiveContentOrLengthConflict' }
            $rows.Add([ordered]@{
                provider=$identity.provider; generation=$identity.generation; threadId=$identity.threadId; turnId=$identity.turnId
                archivePath=$paths.Blob; manifestPath=$paths.Manifest; committedPath=$paths.Marker
                sourcePath=$identity.originalPath; byteOffset=$identity.byteOffset; byteLength=$identity.byteLength
                sourceSha256=$identity.sourceSha256; sha256=$identity.sliceSha256; archiveSha256=$manifest.archiveSha256
                rootGeneration=$identity.rootGeneration; status='unknown'; usage=$null
            })
            $good.Add($tuple) | Out-Null
        }
        catch { $missing.Add(('measurement-invalid:{0}:{1}' -f $tuple, $_.Exception.Message)) }
    }
    foreach ($tuple in $expected) { if (-not $good.Contains($tuple)) { $missing.Add("expected-turn-missing:$tuple") } }
    foreach ($tuple in $good) { if (-not $expected.Contains($tuple)) { $missing.Add("unexpected-measurement:$tuple") } }
    $missing.Add('owner-authentication-and-source-sequence-verification-unavailable')
    $missing.Add('usage-value-extraction-and-cumulative-turn-boundary-unverified')
    return [ordered]@{
        schema='project-closed-family-usage-v2'; verifiedInputSourceSha256=$Bound.Snapshot.SourceSha256
        inputRange=[ordered]@{path=$Bound.Range.path;byteOffset=$Bound.Range.byteOffset;byteLength=$Bound.Range.byteLength;sha256=$Bound.Range.sha256;sourceSha256=$Bound.Range.sourceSha256}
        rootId=$sourceFields.rootId; rootGeneration=$sourceFields.rootGeneration; captureBoundary=[ordered]@{id=$boundaryFields.id}
        originalMeasurements=@($rows.ToArray()); missingOrConflictingTurns=@($missing.ToArray()); usage=$null; status='partial'
    }
}

function Project-ClosedFamilyUsage {
    [CmdletBinding()]
    param([Parameter(Mandatory)][object] $InputRecord, [object[]] $ArchivedMeasurements)
    $bound = Get-HandoffBoundInput $InputRecord
    return Get-HandoffPreparedProjection -Context (Get-HandoffCheckedInventory $bound) -ArchiveReferences $ArchivedMeasurements
}

function Invoke-HandoffArchiveAndProject {
    [CmdletBinding()]
    param([Parameter(Mandatory)][object] $InputRecord, [Parameter(Mandatory)][string] $ArchiveDirectory)
    $bound = Get-HandoffBoundInput $InputRecord
    $context=Get-HandoffCheckedInventory $bound
    $sourceFields=$context.SourceFields; $boundary=$context.BoundaryFields
    $measurementList=@($context.OriginalByTuple.Values|ForEach-Object{$_.Record})

    $prepared = [Collections.Generic.List[object]]::new()
    $tuples = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    foreach ($measurement in @($measurementList)) {
        $fields = Assert-HandoffMeasurementShape $measurement
        if ([string]$fields.rootGeneration -cne [string]$sourceFields.rootGeneration) { throw 'MeasurementRootGenerationConflict' }
        $tuple = Get-HandoffTupleKey $measurement
        if (-not $tuples.Add($tuple)) { throw "DuplicateOriginalMeasurement: $tuple" }
        $offset = [long]$fields.byteOffset
        $length = [long]$fields.byteLength
        $snapshot = Read-HandoffSnapshot -Path ([string]$fields.sourcePath) -Offset $offset -Length $length
        if ($snapshot.SourceSha256 -cne [string]$fields.sourceSha256 -or $snapshot.SliceSha256 -cne [string]$fields.sha256 -or [string]$fields.archiveSha256 -cne $snapshot.SliceSha256) {
            throw 'IndependentSourcePinMismatch'
        }
        $identity = [ordered]@{
            schema='handoff-original-bytes-v3'; rootId=$sourceFields.rootId; owner=$sourceFields.owner; version=$sourceFields.version
            boundaryId=$boundary.id; rootGeneration=$fields.rootGeneration; provider=$fields.provider; generation=$fields.generation
            threadId=$fields.threadId; turnId=$fields.turnId; originalPath=$snapshot.Path; byteOffset=$offset; byteLength=$length
            sourceSha256=$snapshot.SourceSha256; sliceSha256=$snapshot.SliceSha256
        }
        $prepared.Add([pscustomobject]@{ Tuple=$tuple; Measurement=$measurement; Snapshot=$snapshot; Identity=$identity })
    }
    $plans=@($prepared|ForEach-Object{Get-HandoffPublicationPlan $_ $ArchiveDirectory})
    $plannedPaths=[Collections.Generic.List[string]]::new()
    $directoryTarget=[IO.Path]::GetFullPath($ArchiveDirectory)
    if([IO.File]::Exists($directoryTarget)){throw 'PublicationDirectoryIsFile'}
    $directoryParent=[IO.Path]::GetDirectoryName($directoryTarget);while($directoryParent){if([IO.File]::Exists($directoryParent)){throw 'PublicationParentIsFile'};$next=[IO.Path]::GetDirectoryName($directoryParent);if($next -ceq $directoryParent){break};$directoryParent=$next}
    foreach($plan in $plans){
        foreach($path in @($plan.Blob,$plan.Manifest,$plan.Marker,$plan.StageBlob,$plan.StageManifest,$plan.StageMarker)){
            $plannedPaths.Add([IO.Path]::GetFullPath($path))
            if([IO.Directory]::Exists($path)){throw 'PublicationDestinationIsDirectory'}
            $fullPath=[IO.Path]::GetFullPath($path)
            if($fullPath.Equals($directoryTarget,[StringComparison]::OrdinalIgnoreCase) -or $directoryTarget.StartsWith($fullPath+[IO.Path]::DirectorySeparatorChar,[StringComparison]::OrdinalIgnoreCase)){throw 'PublicationDirectoryTreeOverlap'}
            $parent=[IO.Path]::GetDirectoryName([IO.Path]::GetFullPath($path))
            while($parent){if([IO.File]::Exists($parent)){throw 'PublicationParentIsFile'};$next=[IO.Path]::GetDirectoryName($parent);if($next -ceq $parent){break};$parent=$next}
        }
    }
    if([IO.Directory]::Exists($directoryTarget) -and $plans.Count -eq 0){$null=Get-ChildItem -LiteralPath $directoryTarget -Force | Select-Object -First 1}
    for($i=0;$i -lt $plannedPaths.Count;$i++){for($j=$i+1;$j -lt $plannedPaths.Count;$j++){
        if($plannedPaths[$i].Equals($plannedPaths[$j],[StringComparison]::OrdinalIgnoreCase) -or $plannedPaths[$i].StartsWith($plannedPaths[$j]+[IO.Path]::DirectorySeparatorChar,[StringComparison]::OrdinalIgnoreCase) -or $plannedPaths[$j].StartsWith($plannedPaths[$i]+[IO.Path]::DirectorySeparatorChar,[StringComparison]::OrdinalIgnoreCase)){throw 'PublicationPlanTreeOverlap'}
    }}
    foreach($plan in $plans){[void](Read-HandoffPublicationState $plan)}
    $archives = [Collections.Generic.List[object]]::new()
    foreach ($item in $prepared) {
        $archives.Add((Copy-HandoffPreparedSnapshot -Prepared $item -ArchiveDirectory $ArchiveDirectory))
    }
    $references = @()
    foreach ($archive in $archives) {
        $references += [pscustomobject]@{
            provider=$archive.provider; generation=$archive.generation; threadId=$archive.threadId; turnId=$archive.turnId
            archivePath=$archive.archivePath; manifestPath=([IO.Path]::ChangeExtension($archive.archivePath,'.json'))
            committedPath=([IO.Path]::ChangeExtension($archive.archivePath,'.committed'))
        }
    }
    $preparedWithArchives = @()
    foreach ($item in $prepared) {
        $archive = @($archives | Where-Object { (Get-HandoffTupleKey $_) -ceq $item.Tuple }) | Select-Object -First 1
        $preparedWithArchives += [pscustomobject]@{ Tuple=$item.Tuple; Snapshot=$item.Snapshot; Reference=($references | Where-Object { (Get-HandoffTupleKey $_) -ceq $item.Tuple } | Select-Object -First 1); ArchiveBytes=$item.Snapshot.Slice }
    }
    return [ordered]@{
        archives=@($archives.ToArray())
        projection=(Get-HandoffPreparedProjection -Context $context -PreparedSnapshots $preparedWithArchives)
    }
}

function Invoke-CoordinatorHandoffProducer {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][ValidateSet('ProjectClosedFamilyUsage','ArchiveAndProject','VerifyEnrollment','ReconcileEnrollment','VerifyReconciliation','AssertEnrollmentFence','EnrollmentCommitted','VerifyMember','VerifyCapability','BeginFence','CollectFence','CollectViaOwner','AssertReservationFence','ReservationCommitted','RouteAdmission')][string] $Operation,
        [Parameter(Mandatory)][object] $InputRecord,
        [string] $ArchiveDirectory
    )
    if ($Operation -eq 'ProjectClosedFamilyUsage') { return Project-ClosedFamilyUsage $InputRecord }
    if ($Operation -eq 'ArchiveAndProject') {
        if ([string]::IsNullOrWhiteSpace($ArchiveDirectory)) { throw 'ArchiveDirectoryRequired' }
        return Invoke-HandoffArchiveAndProject $InputRecord $ArchiveDirectory
    }
    throw "Owner capability unavailable for operation '$Operation': no authenticated callback bound to original root/connection generation"
}

Export-ModuleMember -Function Invoke-CoordinatorHandoffProducer,Copy-HandoffImmutableBytes
