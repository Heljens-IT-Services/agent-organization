[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$TaskId,
    [Parameter(Mandatory = $true)][string]$AccountingDirectory
)
$ErrorActionPreference = 'Stop'
$utf8 = New-Object System.Text.UTF8Encoding($false, $true)
$fields = @('inputTokens', 'cachedInputTokens', 'outputTokens', 'reasoningOutputTokens', 'totalTokens', 'cacheWriteInputTokens')
function Normalize-Id($Value) {
    $parsed = [guid]::Empty
    if (-not [guid]::TryParse([string]$Value, [ref]$parsed)) { throw "Ungültige Task-ID: $Value" }
    return $parsed.ToString('N')
}
function Normalize-Usage($Value) {
    if ($null -eq $Value) { return $null }
    $usage = [ordered]@{}
    foreach ($field in $fields) {
        $valueField = $Value.$field
        if ($field -eq 'cacheWriteInputTokens' -and $null -eq $valueField) { $valueField = 0 }
        if ($null -eq $valueField -or $valueField -is [string] -or $valueField -is [bool] -or
            $valueField -lt 0 -or [decimal]$valueField -ne [decimal][long]$valueField) { throw "Ungültiger Tokenwert: $field" }
        $usage[$field] = [long]$valueField
    }
    if ($usage.cachedInputTokens -gt $usage.inputTokens -or $usage.reasoningOutputTokens -gt $usage.outputTokens) { throw 'Ungültige Token-Teilmengen.' }
    return [pscustomobject]$usage
}
$rootId = Normalize-Id $TaskId
$records = @{}
$native = @{}
foreach ($file in Get-ChildItem -LiteralPath $AccountingDirectory -Filter '*.usage.json' -File) {
    $record = [System.IO.File]::ReadAllText($file.FullName, $utf8) | ConvertFrom-Json
    foreach ($field in @('task_id', 'parent_task_id', 'role', 'thread_id', 'turn_id', 'token_usage')) {
        if ($null -eq $record.PSObject.Properties[$field]) { throw "Ledgerfeld fehlt: $field ($($file.Name))" }
    }
    if ($record.PSObject.Properties['status']) { throw 'Ledger darf kein status-Feld enthalten.' }
    $id = Normalize-Id $record.task_id
    $parent = if ($null -eq $record.parent_task_id) { $null } else { Normalize-Id $record.parent_task_id }
    if ($record.role -isnot [string] -or [string]::IsNullOrWhiteSpace($record.role)) { throw 'Ledgerrolle fehlt oder ist ungültig.' }
    foreach ($identity in @('thread_id', 'turn_id')) {
        if ($null -ne $record.$identity -and $record.$identity -isnot [string]) { throw "Ungültige native Identität: $identity" }
    }
    if (($null -eq $record.thread_id) -ne ($null -eq $record.turn_id)) {
        # Ein gestarteter Thread ohne gestarteten Turn ist bei fehlgeschlagenem Start erlaubt.
        if ($null -ne $record.turn_id -or $null -ne $record.token_usage) { throw 'Unvollständige native Identität.' }
    }
    if ($null -ne $record.thread_id -and [string]::IsNullOrWhiteSpace($record.thread_id)) { throw 'Leere Thread-ID.' }
    if ($null -ne $record.turn_id -and [string]::IsNullOrWhiteSpace($record.turn_id)) { throw 'Leere Turn-ID.' }
    $usage = Normalize-Usage $record.token_usage
    if ($null -ne $usage -and ($null -eq $record.thread_id -or $null -eq $record.turn_id)) { throw 'Tokenverbrauch ohne native Identität.' }
    $normalized = [pscustomobject][ordered]@{ task_id = $id; parent_task_id = $parent; role = $record.role; thread_id = $record.thread_id; turn_id = $record.turn_id; token_usage = $usage }
    $signature = $normalized | ConvertTo-Json -Depth 10 -Compress
    if ($records.ContainsKey($id)) {
        if ($records[$id].signature -cne $signature) { throw "Widersprüchliche Task-Duplikate: $id" }
        continue
    }
    $key = if ($null -ne $record.thread_id -and $null -ne $record.turn_id) { @($record.thread_id, $record.turn_id) | ConvertTo-Json -Compress } else { $null }
    if ($null -ne $key) {
        $usageSignature = $usage | ConvertTo-Json -Depth 5 -Compress
        if ($native.ContainsKey($key) -and $native[$key] -cne $usageSignature) { throw 'Widersprüchliche native Thread/Turn-Duplikate.' }
        $native[$key] = $usageSignature
    }
    $records[$id] = @{ record = $normalized; signature = $signature; native_key = $key }
}
# Alle eingelesenen Elternketten prüfen, auch außerhalb des angefragten Teilbaums.
foreach ($id in @($records.Keys)) {
    $seen = @{}
    $cursor = $id
    while ($null -ne $cursor -and $records.ContainsKey($cursor)) {
        if ($seen.ContainsKey($cursor)) { throw "Zyklus im Task-Ledger: $cursor" }
        $seen[$cursor] = $true
        $cursor = $records[$cursor].record.parent_task_id
    }
}
$queue = New-Object System.Collections.Generic.Queue[string]
$queue.Enqueue($rootId)
$selected = @{}
while ($queue.Count -gt 0) {
    $id = $queue.Dequeue()
    if ($selected.ContainsKey($id)) { continue }
    $selected[$id] = $true
    foreach ($child in $records.Keys) { if ($records[$child].record.parent_task_id -eq $id) { $queue.Enqueue($child) } }
}
$totals = [ordered]@{}
foreach ($field in $fields) { $totals[$field] = [long]0 }
$missing = 0
$known = 0
$counted = @{}
foreach ($id in $selected.Keys) {
    if (-not $records.ContainsKey($id) -or $null -eq $records[$id].record.token_usage) { $missing++; continue }
    $entry = $records[$id]
    if ($counted.ContainsKey($entry.native_key)) { continue }
    $counted[$entry.native_key] = $true
    $known++
    foreach ($field in $fields) {
        $sum = [decimal]$totals[$field] + [decimal]$entry.record.token_usage.$field
        if ($sum -gt [long]::MaxValue) { throw "Token-Summenüberlauf: $field" }
        $totals[$field] = [long]$sum
    }
}
$own = if ($records.ContainsKey($rootId)) { $records[$rootId].record.token_usage } else { $null }
[pscustomobject][ordered]@{
    task_id = $rootId; own = $own
    inclusive = $(if ($missing -eq 0) { [pscustomobject]$totals } else { $null })
    known_partial = [pscustomobject]$totals; missing_count = $missing
    distinct_known_usage_count = $known; task_count = $selected.Count
}
