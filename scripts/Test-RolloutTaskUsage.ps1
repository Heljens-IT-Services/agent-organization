[CmdletBinding()]
param()
$ErrorActionPreference = 'Stop'
$utf8 = New-Object System.Text.UTF8Encoding($false, $true)
$fixtureRoot = Join-Path ([System.IO.Path]::GetTempPath()) ('agent-org-rollout-test-' + [guid]::NewGuid().ToString('N'))
$null = New-Item -ItemType Directory -Path $fixtureRoot
$importer = Join-Path $PSScriptRoot 'Import-RolloutTaskUsage.ps1'
$thread = [guid]::NewGuid().ToString('D')
$turn = [guid]::NewGuid().ToString('D')
$ancestor = [guid]::NewGuid().ToString('D')
$passed = 0
function Assert($Condition, [string]$Label) {
    if (-not $Condition) { throw "FAIL: $Label" }
    $script:passed++
    Write-Host "PASS: $Label"
}
function Meta($Id) { return @{ type = 'session_meta'; payload = @{ id = $Id } } }
function Event($Type, $Id = $turn) { return @{ type = 'event_msg'; payload = @{ type = $Type; turn_id = $Id } } }
function Tokens([long]$Scale, [switch]$WithCacheWrite) {
    $usage = @{ input_tokens = 10 * $Scale; cached_input_tokens = 2 * $Scale; output_tokens = 4 * $Scale; reasoning_output_tokens = $Scale; total_tokens = 14 * $Scale }
    if ($WithCacheWrite) { $usage.cache_write_input_tokens = $Scale }
    return @{ type = 'event_msg'; payload = @{ type = 'token_count'; info = @{ total_token_usage = $usage } } }
}
function Fixture($Rows, $FileId = $thread) {
    $directory = Join-Path $fixtureRoot ([guid]::NewGuid().ToString('N'))
    $null = New-Item -ItemType Directory -Path $directory
    $path = Join-Path $directory ('rollout-2026-10-12T12-00-00-' + $FileId + '.jsonl')
    $lines = @($Rows | ForEach-Object { $_ | ConvertTo-Json -Depth 20 -Compress })
    [System.IO.File]::WriteAllLines($path, [string[]]$lines, $utf8)
    return @{ RolloutPath = $path; ThreadId = $thread; TurnId = $turn; Role = 'koordinator'; AccountingDirectory = (Join-Path $directory 'ledger') }
}
function Must-Fail($Rows, [string]$Pattern, [string]$Label, $FileId = $thread) {
    $arguments = Fixture $Rows $FileId
    $failed = $false
    try { $null = & $importer @arguments } catch { $failed = $_.Exception.Message -match $Pattern }
    Assert $failed $Label
    Assert (-not (Test-Path -LiteralPath $arguments.AccountingDirectory)) ($Label + ': no artifact')
}
try {
    foreach ($path in @($importer, $PSCommandPath)) {
        $parseTokens = $null; $parseErrors = $null
        $null = [System.Management.Automation.Language.Parser]::ParseFile($path, [ref]$parseTokens, [ref]$parseErrors)
        Assert ($parseErrors.Count -eq 0) ('Parser: ' + [System.IO.Path]::GetFileName($path))
        $bytes = [System.IO.File]::ReadAllBytes($path)
        Assert ($bytes.Length -ge 3 -and $bytes[0] -eq 239 -and $bytes[1] -eq 187 -and $bytes[2] -eq 191) ('UTF8 BOM: ' + [System.IO.Path]::GetFileName($path))
    }
    $rows = @((Meta $ancestor), (Tokens 100), (Meta $thread), (Event 'task_started'), (Tokens 102), (Tokens 102), (Tokens 103), (Event 'task_complete'), (Tokens 104))
    $arguments = Fixture $rows
    $record = & $importer @arguments
    Assert ($record.token_usage.inputTokens -eq 30 -and $record.token_usage.cachedInputTokens -eq 6 -and $record.token_usage.outputTokens -eq 12 -and $record.token_usage.reasoningOutputTokens -eq 3 -and $record.token_usage.totalTokens -eq 42 -and $record.token_usage.cacheWriteInputTokens -eq 0) 'Inherited baseline, last in-turn snapshot, duplicates, subset delta'
    Assert ($record.task_id -eq ([guid]$turn).ToString('N') -and $record.thread_id -eq $thread -and $record.turn_id -eq $turn -and $null -eq $record.parent_task_id) 'Selected native identity and default task GUID'
    $artifact = Join-Path $arguments.AccountingDirectory ($record.task_id + '.usage.json')
    $saved = [System.IO.File]::ReadAllText($artifact, $utf8) | ConvertFrom-Json
    Assert ($null -eq $saved.PSObject.Properties['status'] -and @($saved.PSObject.Properties).Count -eq 7 -and $saved.source -eq 'local_rollout_completed_turn_delta') 'Minimal ledger, source, no status'
    $before = [System.IO.File]::ReadAllBytes($artifact)
    $null = & $importer @arguments
    Assert ([Convert]::ToBase64String($before) -ceq [Convert]::ToBase64String([System.IO.File]::ReadAllBytes($artifact))) 'Idempotent import preserves artifact bytes'
    $arguments.Role = 'different-role'
    $failed = $false
    try { $null = & $importer @arguments } catch { $failed = $_.Exception.Message -match 'Conflicting' }
    Assert ($failed -and [Convert]::ToBase64String($before) -ceq [Convert]::ToBase64String([System.IO.File]::ReadAllBytes($artifact))) 'Conflicting artifact is not overwritten'
    $ledger = & (Join-Path $PSScriptRoot 'Get-TaskTokenUsage.ps1') -TaskId $turn -AccountingDirectory $arguments.AccountingDirectory
    Assert ($ledger.own.totalTokens -eq 42 -and $ledger.inclusive.totalTokens -eq 42 -and $ledger.missing_count -eq 0) 'Existing ledger reader accepts delta'
    foreach ($missing in @(
        @((Meta $thread), (Event 'task_started'), (Tokens 1), (Event 'task_complete')),
        @((Meta $thread), (Tokens 1), (Event 'task_started'), (Event 'task_complete')),
        @((Meta $thread), (Event 'task_started'), (Event 'task_complete'))
    )) {
        $arguments = Fixture $missing
        $record = & $importer @arguments
        Assert ($null -eq $record.token_usage) 'Missing baseline or final stays null (including fresh thread)'
        $ledger = & (Join-Path $PSScriptRoot 'Get-TaskTokenUsage.ps1') -TaskId $turn -AccountingDirectory $arguments.AccountingDirectory
        Assert ($null -eq $ledger.inclusive -and $ledger.missing_count -eq 1) 'Unknown usage remains unknown in reader'
    }
    $arguments = Fixture @((Meta $thread), (Tokens 1 -WithCacheWrite), (Event 'task_started'), (Tokens 2 -WithCacheWrite), (Event 'task_complete'))
    $arguments.TaskId = [guid]::NewGuid().ToString('D')
    $arguments.ParentTaskId = [guid]::NewGuid().ToString('D')
    $record = & $importer @arguments
    Assert ($record.task_id -eq ([guid]$arguments.TaskId).ToString('N') -and $record.parent_task_id -eq ([guid]$arguments.ParentTaskId).ToString('N') -and $record.token_usage.cacheWriteInputTokens -eq 1) 'Explicit task/parent mapping and optional cache-write delta'
    Must-Fail @((Meta $thread), (Tokens 1), (Event 'task_started'), (Tokens 2)) 'incomplete' 'Incomplete turn rejected'
    Must-Fail @((Meta $thread), (Tokens 2), (Event 'task_started'), (Tokens 1), (Event 'task_complete')) 'reset' 'Reset counters rejected'
    $negative = Tokens 2; $negative.payload.info.total_token_usage.input_tokens = -1
    Must-Fail @((Meta $thread), (Tokens 1), (Event 'task_started'), $negative, (Event 'task_complete')) 'negative' 'Negative counters rejected'
    $malformed = Tokens 2; $malformed.payload.info.total_token_usage.total_tokens = '28'
    Must-Fail @((Meta $thread), (Tokens 1), (Event 'task_started'), $malformed, (Event 'task_complete')) 'Malformed' 'String counter rejected'
    $missing = Tokens 2; $missing.payload.info.total_token_usage.Remove('total_tokens')
    Must-Fail @((Meta $thread), (Tokens 1), (Event 'task_started'), $missing, (Event 'task_complete')) 'Malformed' 'Missing required counter rejected'
    $unknown = Tokens 2; $unknown.payload.info.total_token_usage.new_counter = 1
    Must-Fail @((Meta $thread), (Tokens 1), (Event 'task_started'), $unknown, (Event 'task_complete')) 'Unknown token snapshot field' 'Unknown snapshot schema rejected'
    $fraction = Tokens 2; $fraction.payload.info.total_token_usage.total_tokens = 28.5
    Must-Fail @((Meta $thread), (Tokens 1), (Event 'task_started'), $fraction, (Event 'task_complete')) 'Malformed' 'Fractional counter rejected'
    $badSubset = Tokens 2; $badSubset.payload.info.total_token_usage.cached_input_tokens = 21
    Must-Fail @((Meta $thread), (Tokens 1), (Event 'task_started'), $badSubset, (Event 'task_complete')) 'subset' 'Invalid absolute subset rejected'
    $badDelta = Tokens 2; $badDelta.payload.info.total_token_usage.cached_input_tokens = 15
    Must-Fail @((Meta $thread), (Tokens 1), (Event 'task_started'), $badDelta, (Event 'task_complete')) 'delta token subsets' 'Invalid delta subset rejected'
    Must-Fail @((Meta $ancestor), (Tokens 1)) 'metadata is missing' 'Wrong metadata ThreadId rejected'
    Must-Fail $rows 'file identity' 'Wrong file ThreadId rejected' $ancestor
    Must-Fail @((Event 'task_started'), (Meta $thread), (Tokens 1), (Event 'task_complete')) 'before own' 'Target start before own metadata rejected'
    Must-Fail @((Meta $thread), (Event 'task_started'), (Event 'task_started'), (Event 'task_complete')) 'Nested or repeated' 'Repeated start rejected'
    Must-Fail @((Meta $thread), (Event 'task_started'), (Event 'task_started' $ancestor), (Event 'task_complete')) 'Nested or repeated' 'Nested other turn rejected'
    Must-Fail @((Meta $thread), (Event 'task_started'), (Event 'task_complete'), (Event 'task_complete')) 'Unmatched or repeated' 'Repeated completion rejected'
    Must-Fail @((Meta $thread), (Event 'task_started'), (Event 'task_complete'), (Event 'task_started'), (Event 'task_complete')) 'Nested or repeated' 'Repeated completed target rejected'
    Must-Fail @((Meta $thread), (Event 'task_started'), (Event 'task_complete' $ancestor)) 'Unmatched' 'Mismatched completion rejected'
    Must-Fail @((Meta $thread), (Meta $thread), (Event 'task_started'), (Event 'task_complete')) 'Repeated own' 'Repeated own session metadata rejected'
    Must-Fail @((Meta $thread), (Meta $ancestor), (Event 'task_started'), (Event 'task_complete')) 'Foreign session' 'Foreign metadata after own identity rejected'
    Must-Fail @((Meta $thread), @{ type = 'unknown'; payload = @{} }) 'Unknown' 'Unknown record format rejected'
    $arguments = Fixture $rows
    [System.IO.File]::WriteAllText($arguments.RolloutPath, '{private malformed payload', $utf8)
    $failed = $false
    try { $null = & $importer @arguments } catch { $failed = $_.Exception.Message -eq 'Malformed rollout JSON record.' }
    Assert $failed 'Malformed JSON rejected without payload output'
    Assert (@(Get-ChildItem -LiteralPath $fixtureRoot -Recurse -Filter '*.tmp').Count -eq 0) 'No temporary ledger artifacts remain'
    $native = @{ type = 'token_usage_record'; payload = @{ thread_id = $thread; turn_id = $turn; turn_token_usage = (Tokens 2).payload.info.total_token_usage } }
    $foreign = @{ type = 'token_usage_record'; payload = @{ thread_id = $ancestor; turn_id = $turn; turn_token_usage = (Tokens 99).payload.info.total_token_usage } }
    $arguments = Fixture @((Meta $thread), (Meta $ancestor), (Event 'task_started'), $foreign, $native, $native, (Event 'task_complete'))
    $record = & $importer @arguments
    Assert ($record.token_usage.totalTokens -eq 28 -and $record.source -eq 'local_rollout_native_turn_usage') 'Identity-bearing native turn usage wins, including fork metadata and no baseline'
    $before = [IO.File]::ReadAllBytes((Join-Path $arguments.AccountingDirectory ($record.task_id + '.usage.json')))
    $null = & $importer @arguments
    Assert ([Convert]::ToBase64String($before) -ceq [Convert]::ToBase64String([IO.File]::ReadAllBytes((Join-Path $arguments.AccountingDirectory ($record.task_id + '.usage.json'))))) 'Native snapshot import is idempotent'
    Must-Fail @((Meta $thread), (Event 'task_started'), $native) 'incomplete' 'Native snapshot needs completed target turn'
    $reset = @{ type = 'token_usage_record'; payload = @{ thread_id = $thread; turn_id = $turn; turn_token_usage = (Tokens 1).payload.info.total_token_usage } }
    Must-Fail @((Meta $thread), (Event 'task_started'), $native, $reset, (Event 'task_complete')) 'reset' 'Native snapshot reset rejected'
    Must-Fail @((Meta $thread), (Event 'task_started'), @{ type = 'unknown_accounting_v2'; payload = @{} }, $native, (Event 'task_complete')) 'Unknown' 'Native route rejects unknown record types'
    Must-Fail @((Meta $thread), (Event 'task_started'), @{ type = 'world_state'; payload = 'invalid' }, $native, (Event 'task_complete')) 'envelope' 'Native route rejects malformed envelopes'
    Write-Host "Offline successful: $passed checks. Fixtures: $fixtureRoot"
    exit 0
} catch {
    Write-Error -ErrorAction Continue $_
    Write-Host "Offline failed after $passed checks. Fixtures: $fixtureRoot"
    exit 1
}
