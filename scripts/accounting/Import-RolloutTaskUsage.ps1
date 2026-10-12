[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$RolloutPath,
    [Parameter(Mandatory = $true)][string]$ThreadId,
    [Parameter(Mandatory = $true)][string]$TurnId,
    [Parameter(Mandatory = $true)][string]$Role,
    [string]$TaskId,
    [string]$ParentTaskId,
    [string]$WorkItemId,
    [string]$ExecutionId,
    [string]$StorePath,
    [Parameter(Mandatory = $true)][string]$AccountingDirectory
)
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'AccountingEvidence.psm1') -Force
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
$thread = Id $ThreadId 'ThreadId'
$turn = Id $TurnId 'TurnId'
if (-not $PSBoundParameters.ContainsKey('TaskId')) { $TaskId = $turn }
$task = Get-CanonicalId $TaskId
$parent = if ($PSBoundParameters.ContainsKey('ParentTaskId')) { Get-CanonicalId $ParentTaskId -Optional } else { $null }
$workItem = if ($PSBoundParameters.ContainsKey('WorkItemId')) { Get-Text $WorkItemId } else { $null }
$execution = if ($PSBoundParameters.ContainsKey('ExecutionId')) { Get-Text $ExecutionId } else { $null }
$storeBinding = if ($PSBoundParameters.ContainsKey('StorePath')) {
    $null = Get-CanonicalPath $StorePath
    [IO.Path]::GetFullPath($StorePath)
} else { $null }
$present = @(@($workItem,$execution,$storeBinding) | Where-Object { $null -ne $_ }).Count
if ($present -ne 0 -and $present -ne 3) { throw 'WorkItem, execution and store must be supplied together.' }
$directory = [IO.Path]::GetFullPath($AccountingDirectory)
$parentThread = $null; $parentTurn = $null; $initialTurns = @()
if ($null -ne $workItem) {
    $priorEntries = @(Read-UsageEntries $directory)
    $state = Read-ExecutionEvidence $directory $priorEntries
    if (-not $state.ContainsKey($execution)) { throw 'No existing execution binding.' }
    $binding = $state[$execution]
    if ($binding.artifactCount -eq 0 -or $binding.conflicts.Count -gt 0) { throw 'Missing or conflicting execution binding.' }
    if ($binding.workItemId -cne $workItem -or $binding.storePath -cne (Get-CanonicalPath $storeBinding)) { throw 'WorkItem/store binding conflicts.' }
    if ($null -ne $binding.threadId -and $binding.threadId -cne (Get-CanonicalId $thread)) { throw 'Execution thread conflicts.' }
    if ($null -eq $binding.taskId) { throw 'Execution task binding is missing.' }
    if ($binding.taskId -cne $task) {
        $aliases = @($priorEntries | Where-Object {
            $_.identity.threadId -ceq (Get-CanonicalId $thread) -and
            $_.identity.turnId -ceq (Get-CanonicalId $turn) -and
            $_.AliasTaskIds -ccontains $binding.taskId
        })
        if ($aliases.Count -ne 1) { throw 'Unproven task alias.' }
    }
    if ($PSBoundParameters.ContainsKey('ParentTaskId') -and $null -ne $binding.parentTaskId -and $parent -cne $binding.parentTaskId) { throw 'ParentTaskId differs from execution binding.' }
    if (-not $PSBoundParameters.ContainsKey('ParentTaskId')) { $parent = $binding.parentTaskId }
    if ($null -ne $binding.parentThreadId) { $parentThread = ([guid]$binding.parentThreadId).ToString('D') }
    if ($null -ne $binding.parentTurnId) { $parentTurn = ([guid]$binding.parentTurnId).ToString('D') }
    $initialTurns = @($binding.initialTurns)
    # Later turns are importable, but cannot replace initial-turn coverage.
}
if ($parent -ceq $task) { throw 'Self-parent task.' }
$null = Get-Text $Role
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
        if ($data.type -eq 'session_meta' -and (Get-CanonicalId (Get-Field $data.payload 'id')) -ceq (Get-CanonicalId $thread)) { $directMetadata++ }
        if ($data.type -eq 'event_msg' -and (Get-CanonicalId (Get-Field $data.payload 'turn_id') -Optional) -ceq (Get-CanonicalId $turn)) {
            if ($data.payload.type -eq 'task_started') {
                if ($directStarted -or $directMetadata -ne 1) { $directError = 'Ambiguous selected native turn start.' }
                $directStarted = $true
            }
            if ($data.payload.type -eq 'task_complete') {
                if (-not $directStarted -or $directCompleted) { $directError = 'Ambiguous selected native turn completion.' }
                $directCompleted = $true
            }
        }
        if ($data.type -eq 'token_usage_record' -and (Get-CanonicalId (Get-Field $data.payload 'thread_id')) -ceq (Get-CanonicalId $thread) -and (Get-CanonicalId (Get-Field $data.payload 'turn_id')) -ceq (Get-CanonicalId $turn)) {
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
    parent_thread_id = $parentThread; parent_turn_id = $parentTurn; token_usage = $usage; final = $true; source = $(if ($null -ne $direct) { 'local_rollout_native_turn_usage' } else { 'local_rollout_completed_turn_delta' })
}
if ($null -ne $workItem) {
    $record | Add-Member -NotePropertyName work_item_id -NotePropertyValue $workItem
    $record | Add-Member -NotePropertyName execution_id -NotePropertyValue $execution
    $record | Add-Member -NotePropertyName work_item_store_path -NotePropertyValue $storeBinding
}
$null = [IO.Directory]::CreateDirectory($directory)
# Cooperating imports serialize conflict scan/publication. Other writers use other locks.
$lockPath = Join-Path $directory 'accounting-import.lock'
$lock = [IO.File]::Open($lockPath,[IO.FileMode]::OpenOrCreate,[IO.FileAccess]::ReadWrite,[IO.FileShare]::None)
try {
    $identity = Get-UsageIdentity $record
    $entries = @(Read-UsageEntries $directory)
    foreach ($entry in $entries) {
        if ($entry.AliasTaskIds -ccontains $task -and (Get-TaskBindingSignature $entry.identity) -cne (Get-TaskBindingSignature $identity)) { throw 'Cross-turn task binding conflict.' }
        if ($entry.identity.threadId -ceq $identity.threadId -and $entry.identity.turnId -ceq $identity.turnId -and (Get-NativeSignature $entry.identity) -cne (Get-NativeSignature $identity)) {
            throw 'Native measurement, Unknown, binding or finality conflict; existing records retained.'
        }
    }
    if ($null -ne $execution) {
        $state = Read-ExecutionEvidence $directory $entries
        if (-not $state.ContainsKey($execution) -or $state[$execution].artifactCount -eq 0) { throw 'Execution binding disappeared.' }
        $canonical = Get-UsageIdentity $record
        if ($state[$execution].taskId -cne $canonical.taskId) {
            $same = @($entries | Where-Object { $_.native_key -ceq ($canonical.threadId+'/'+$canonical.turnId) -and $_.AliasTaskIds -ccontains $state[$execution].taskId })
            if ($same.Count -ne 1) { throw 'Unproven task alias at publication.' }
            $canonical.taskId = $state[$execution].taskId
        }
        Add-ExecutionEvidence $state $canonical 'usage' 'pending import' $null
        if ($state[$execution].conflicts.Count -gt 0) { throw 'Execution binding conflicts at publication.' }
        $initialTurns = @($state[$execution].initialTurns)
    }
    $legacyDestination = Join-Path $directory ($task+'.usage.json')
    $turnDestination = Join-Path $directory ($task+'.'+$thread+'.'+$turn+'.usage.json')
    $destination = $legacyDestination
    if ($null -ne $execution -and ($initialTurns.Count -ne 1 -or $initialTurns -cnotcontains $identity.turnId)) { $destination = $turnDestination }
    if ([IO.File]::Exists($legacyDestination)) {
        $legacy = Get-UsageIdentity (Get-Content -LiteralPath $legacyDestination -Raw -Encoding UTF8 | ConvertFrom-Json)
        if ($legacy.threadId -ceq $identity.threadId -and $legacy.turnId -ceq $identity.turnId) { $destination = $legacyDestination }
        else { $destination = $turnDestination }
    }
    foreach ($path in @($destination,$turnDestination) | Select-Object -Unique) {
        if (-not [IO.File]::Exists($path)) { continue }
        $old = Get-UsageIdentity (Get-Content -LiteralPath $path -Raw -Encoding UTF8 | ConvertFrom-Json)
        if ($old.taskId -cne $identity.taskId -or $old.threadId -cne $identity.threadId -or $old.turnId -cne $identity.turnId -or (Get-NativeSignature $old) -cne (Get-NativeSignature $identity)) { throw 'Existing destination conflicts; no replacement.' }
    }
    if (-not [IO.File]::Exists($destination)) {
        $temporary = Join-Path $directory ($task+'.'+[guid]::NewGuid().ToString('N')+'.tmp')
        try {
            [IO.File]::WriteAllText($temporary,($record | ConvertTo-Json -Depth 10),$utf8)
            try { [IO.File]::Move($temporary,$destination) }
            catch {
                if (-not [IO.File]::Exists($destination)) { throw 'Atomic publication failed.' }
                $raced = Get-UsageIdentity (Get-Content -LiteralPath $destination -Raw -Encoding UTF8 | ConvertFrom-Json)
                if ($raced.taskId -cne $identity.taskId -or $raced.threadId -cne $identity.threadId -or $raced.turnId -cne $identity.turnId -or (Get-NativeSignature $raced) -cne (Get-NativeSignature $identity)) { throw 'Concurrent destination conflict.' }
            }
        } finally { if ([IO.File]::Exists($temporary)) { [IO.File]::Delete($temporary) } }
    }
} finally { $lock.Dispose() }
$record
