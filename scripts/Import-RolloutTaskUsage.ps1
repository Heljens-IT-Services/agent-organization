[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$RolloutPath,
    [Parameter(Mandatory = $true)][string]$ThreadId,
    [Parameter(Mandatory = $true)][string]$TurnId,
    [Parameter(Mandatory = $true)][string]$Role,
    [string]$TaskId,
    [string]$ParentTaskId,
    [Parameter(Mandatory = $true)][string]$AccountingDirectory
)
$ErrorActionPreference = 'Stop'
$utf8 = New-Object System.Text.UTF8Encoding($false, $true)
# Explicit opt-in to this observed internal format, not a public rollout API.
# Only metadata is read; message payloads are never returned or included in errors.
$nativeFields = @('input_tokens', 'cached_input_tokens', 'output_tokens', 'reasoning_output_tokens', 'total_tokens', 'cache_write_input_tokens')
$ledgerFields = @('inputTokens', 'cachedInputTokens', 'outputTokens', 'reasoningOutputTokens', 'totalTokens', 'cacheWriteInputTokens')
function Id([string]$Value, [string]$Label, [string]$Format = 'D') {
    $parsed = [guid]::Empty
    if (-not [guid]::TryParse($Value, [ref]$parsed)) { throw "Invalid $Label GUID." }
    return $parsed.ToString($Format)
}
function Snapshot($Value) {
    if ($null -eq $Value -or $Value -isnot [pscustomobject]) { throw 'Missing or unknown token snapshot format.' }
    foreach ($property in $Value.PSObject.Properties) {
        if ($nativeFields -cnotcontains $property.Name) { throw 'Unknown token snapshot field.' }
    }
    $result = [ordered]@{}
    for ($i = 0; $i -lt $nativeFields.Count; $i++) {
        $field = $nativeFields[$i]
        $property = $Value.PSObject.Properties[$field]
        $number = if ($null -eq $property -and $field -eq 'cache_write_input_tokens') { 0 } else { $Value.$field }
        if ($null -eq $number -or $number -is [string] -or $number -is [bool] -or
            $number -is [array] -or $number -is [pscustomobject]) { throw "Malformed token counter: $field." }
        try {
            $decimal = [decimal]$number
            if ($decimal -lt 0 -or $decimal -gt [long]::MaxValue -or [decimal]::Truncate($decimal) -ne $decimal) { throw 'range' }
            $result[$ledgerFields[$i]] = [long]$decimal
        } catch { throw "Malformed or negative token counter: $field." }
    }
    if ($result.cachedInputTokens -gt $result.inputTokens -or $result.reasoningOutputTokens -gt $result.outputTokens) {
        throw 'Invalid token subset counters.'
    }
    return [pscustomobject]$result
}
function Same-Record($Existing, $Expected) {
    $keys = @('task_id', 'parent_task_id', 'role', 'thread_id', 'turn_id', 'token_usage', 'source')
    if ($null -eq $Existing -or @($Existing.PSObject.Properties).Count -ne $keys.Count) { return $false }
    foreach ($key in $keys) {
        if ($null -eq $Existing.PSObject.Properties[$key]) { return $false }
        if ($key -eq 'token_usage') { continue }
        if ($null -eq $Expected.$key) { if ($null -ne $Existing.$key) { return $false } }
        elseif ($Existing.$key -isnot [string] -or $Existing.$key -cne $Expected.$key) { return $false }
    }
    if ($null -eq $Expected.token_usage) { return ($null -eq $Existing.token_usage) }
    if ($null -eq $Existing.token_usage -or @($Existing.token_usage.PSObject.Properties).Count -ne 6) { return $false }
    foreach ($key in $ledgerFields) {
        $number = $Existing.token_usage.$key
        if ($null -eq $Existing.token_usage.PSObject.Properties[$key] -or
            ($number -isnot [int] -and $number -isnot [long] -and $number -isnot [decimal] -and $number -isnot [double]) -or
            $number -ne $Expected.token_usage.$key) { return $false }
    }
    return $true
}
function Check-Existing([string]$Path, $Expected) {
    try { $existing = [System.IO.File]::ReadAllText($Path, $utf8) | ConvertFrom-Json } catch { throw 'Conflicting or unreadable existing usage artifact.' }
    if (-not (Same-Record $existing $Expected)) { throw 'Conflicting existing usage artifact; not overwritten.' }
}
$thread = Id $ThreadId 'ThreadId'
$turn = Id $TurnId 'TurnId'
if (-not $PSBoundParameters.ContainsKey('TaskId')) { $TaskId = $turn }
$task = Id $TaskId 'TaskId' 'N'
$parent = if ($PSBoundParameters.ContainsKey('ParentTaskId')) { Id $ParentTaskId 'ParentTaskId' 'N' } else { $null }
if ($parent -eq $task) { throw 'Task cannot be its own parent.' }
if ([string]::IsNullOrWhiteSpace($Role)) { throw 'Role is required.' }
$file = Get-Item -LiteralPath $RolloutPath
if ($file.PSIsContainer) { throw 'RolloutPath must select one file.' }
# Observed native filename: rollout-YYYY-MM-DDTHH-mm-ss-<thread UUID>.jsonl.
if ($file.Name -notmatch '^rollout-\d{4}-\d{2}-\d{2}T\d{2}-\d{2}-\d{2}-([0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12})\.jsonl$') {
    throw 'Unknown rollout filename identity format.'
}
if ((Id $Matches[1] 'file identity') -ne $thread) { throw 'Rollout file identity does not match ThreadId.' }
# Newer observed rollouts have explicit native per-thread/per-turn accounting.
# Prefer that identity-bearing snapshot; forked ancestor histories are not own usage.
$direct = $null
$directMetadata = 0
$directStarted = $false
$directCompleted = $false
$directError = $null
$directStream = [System.IO.File]::Open($file.FullName, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::ReadWrite)
$directReader = New-Object System.IO.StreamReader($directStream, $utf8, $false)
try {
    while ($null -ne ($line = $directReader.ReadLine())) {
        try { $data = $line | ConvertFrom-Json } catch { throw 'Malformed rollout JSON record.' }
        if ($null -eq $data -or $data -isnot [pscustomobject] -or $data.type -isnot [string] -or $data.payload -isnot [pscustomobject]) { throw 'Unknown rollout record envelope.' }
        if (@('session_meta','event_msg','response_item','turn_context','compacted','world_state','inter_agent_communication_metadata','token_usage_record') -cnotcontains $data.type) { throw 'Unknown rollout record type.' }
        if ($data.type -eq 'session_meta' -and $data.payload.id -eq $thread) { $directMetadata++ }
        if ($data.type -eq 'event_msg' -and $data.payload.turn_id -eq $turn) {
            if ($data.payload.type -eq 'task_started') {
                if ($directStarted -or $directMetadata -ne 1) { $directError = 'Ambiguous selected native turn start.' }
                $directStarted = $true
            }
            if ($data.payload.type -eq 'task_complete') {
                if (-not $directStarted -or $directCompleted) { $directError = 'Ambiguous selected native turn completion.' }
                $directCompleted = $true
            }
        }
        if ($data.type -eq 'token_usage_record' -and $data.payload.thread_id -eq $thread -and $data.payload.turn_id -eq $turn) {
            if (-not $directStarted -or $directCompleted) { throw 'Native usage outside selected turn boundaries.' }
            $next = Snapshot $data.payload.turn_token_usage
            if ($null -ne $direct) {
                foreach ($key in $ledgerFields) { if ($next.$key -lt $direct.$key) { throw 'Native turn counter reset.' } }
            }
            $direct = $next
        }
    }
} finally { $directReader.Dispose() }
if ($null -ne $direct) {
    if ($directError) { throw $directError }
    if ($directMetadata -ne 1 -or -not $directCompleted) { throw 'Selected native turn is incomplete or ambiguous.' }
}
$ownMetadata = $false
$activeTurn = $null
$seenStarts = @{}
$seenCompletes = @{}
$latest = $null
$baseline = $null
$final = $null
$completed = $false
if ($null -eq $direct) {
$stream = [System.IO.File]::Open($file.FullName, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::ReadWrite)
$reader = New-Object System.IO.StreamReader($stream, $utf8, $false)
try {
    while ($null -ne ($line = $reader.ReadLine())) {
        if ([string]::IsNullOrWhiteSpace($line)) { throw 'Unknown empty rollout record.' }
        try { $data = $line | ConvertFrom-Json } catch { throw 'Malformed rollout JSON record.' }
        if ($null -eq $data -or $data -isnot [pscustomobject] -or $data.type -isnot [string] -or $data.payload -isnot [pscustomobject]) {
            throw 'Unknown rollout record envelope.'
        }
        switch -CaseSensitive ($data.type) {
            'session_meta' {
                $metaId = Id $data.payload.id 'session metadata'
                if ($metaId -eq $thread) {
                    if ($ownMetadata) { throw 'Repeated own session metadata is ambiguous.' }
                    $ownMetadata = $true
                } elseif ($ownMetadata) { throw 'Foreign session metadata after own identity is ambiguous.' }
            }
            'event_msg' {
                $event = $data.payload
                if ($event.type -isnot [string]) { throw 'Unknown event metadata format.' }
                switch -CaseSensitive ($event.type) {
                    'token_count' {
                        $snapshot = Snapshot $event.info.total_token_usage
                        if ($null -ne $latest) {
                            foreach ($key in $ledgerFields) {
                                if ($snapshot.$key -lt $latest.$key) { throw "Token counter reset: $key." }
                            }
                        }
                        $latest = $snapshot
                        if ($activeTurn -eq $turn) { $final = $snapshot }
                    }
                    'task_started' {
                        $eventTurn = Id $event.turn_id 'task start turn'
                        if (-not $ownMetadata) {
                            if ($eventTurn -eq $turn) { throw 'Target turn starts before own session metadata.' }
                            break
                        }
                        if ($null -ne $activeTurn -or $seenStarts.ContainsKey($eventTurn)) { throw 'Nested or repeated task start is ambiguous.' }
                        $seenStarts[$eventTurn] = $true
                        $activeTurn = $eventTurn
                        if ($eventTurn -eq $turn) { $baseline = $latest }
                    }
                    'task_complete' {
                        $eventTurn = Id $event.turn_id 'task completion turn'
                        if (-not $ownMetadata) {
                            if ($eventTurn -eq $turn) { throw 'Target completion before own session metadata.' }
                            break
                        }
                        if ($activeTurn -ne $eventTurn -or $seenCompletes.ContainsKey($eventTurn)) { throw 'Unmatched or repeated task completion is ambiguous.' }
                        $seenCompletes[$eventTurn] = $true
                        if ($eventTurn -eq $turn) { $completed = $true }
                        $activeTurn = $null
                    }
                    default { } # Other native event payloads contain no accounting input.
                }
            }
            'response_item' { }
            'turn_context' { }
            'compacted' { }
            'world_state' { }
            'inter_agent_communication_metadata' { }
            'token_usage_record' { }
            default { throw 'Unknown rollout record type.' }
        }
    }
} finally { $reader.Dispose() }
}
if ($null -ne $direct) { $ownMetadata = $true; $completed = $true }
if (-not $ownMetadata) { throw 'Matching own session metadata is missing.' }
if (-not $completed) { throw 'Selected turn is missing or incomplete.' }
$usage = $direct
if ($null -ne $baseline -and $null -ne $final) {
    $delta = [ordered]@{}
    foreach ($key in $ledgerFields) { $delta[$key] = [long]($final.$key - $baseline.$key) }
    if ($delta.cachedInputTokens -gt $delta.inputTokens -or $delta.reasoningOutputTokens -gt $delta.outputTokens) { throw 'Invalid delta token subsets.' }
    $usage = [pscustomobject]$delta
}
$record = [pscustomobject][ordered]@{
    task_id = $task; parent_task_id = $parent; role = $Role; thread_id = $thread; turn_id = $turn
    token_usage = $usage; source = $(if ($null -ne $direct) { 'local_rollout_native_turn_usage' } else { 'local_rollout_completed_turn_delta' })
}
$directory = [System.IO.Path]::GetFullPath($AccountingDirectory)
$null = [System.IO.Directory]::CreateDirectory($directory)
$destination = Join-Path $directory ($task + '.usage.json')
if ([System.IO.File]::Exists($destination)) { Check-Existing $destination $record }
else {
    $temporary = Join-Path $directory ($task + '.' + [guid]::NewGuid().ToString('N') + '.tmp')
    try {
        [System.IO.File]::WriteAllText($temporary, ($record | ConvertTo-Json -Depth 10), $utf8)
        try { [System.IO.File]::Move($temporary, $destination) }
        catch {
            if (-not [System.IO.File]::Exists($destination)) { throw 'Atomic usage artifact creation failed.' }
            Check-Existing $destination $record
        }
    } finally { if ([System.IO.File]::Exists($temporary)) { [System.IO.File]::Delete($temporary) } }
}
$record
