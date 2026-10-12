[CmdletBinding()]
param([string]$EvidenceStream, [string]$DisplayEvidencePath)
$ErrorActionPreference = 'Stop'
# Pure functions only. No starter invocation, model turn or visible window.
$tokens = $null; $errors = $null
$ast = [System.Management.Automation.Language.Parser]::ParseFile((Join-Path $PSScriptRoot '../../delegation/Start-DelegatedCodexTask.ps1'), [ref]$tokens, [ref]$errors)
if ($errors.Count) { throw 'Starter parser failed' }
$names = @('Format-DelegatedStartLayout','New-ProgressState','Protect-ProgressText','Get-ProgressName','Get-ProgressCommand','Get-ProgressPath','ConvertTo-ProgressPayload','Get-ProgressContent','Get-PublicProgress','Format-ProgressLines','Write-ProgressDisplay','Write-Event','Write-Json')
foreach ($node in $ast.FindAll({ param($n) $n -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $false)) {
    if ($node.Name -in $names) { . ([scriptblock]::Create($node.Extent.Text)) }
}
$script:checks = 0
function Assert($Condition, [string]$Name) { if (-not $Condition) { throw "FAIL: $Name" }; $script:checks++; Write-Host "PASS: $Name" }
function Event($Type, $Fields = @{}, $Method = 'item/completed', $Thread = 'own', $Turn = 'turn') {
    $item = @{ type = $Type; id = [guid]::NewGuid().ToString('N') }
    foreach ($k in $Fields.Keys) { $item[$k] = $Fields[$k] }
    return [pscustomobject]@{ method = $Method; params = [pscustomobject]@{ threadId = $Thread; turnId = $Turn; item = [pscustomobject]$item } }
}
function Render($E, $State = (New-ProgressState)) { return @(Get-PublicProgress $E 'own' 'turn' $State) -join "`n" }

# Exactly the three reported failures, with public fields from the v2 schema.
$web = Event 'webSearch' @{query='Codex app-server events';action=@{type='open_page';url='https://learn.chatgpt.com/docs/app-server'}} 'item/started'
$toolText = Render $web
Assert ($toolText -match 'Werkzeug Start: webSearch' -and $toolText -match 'https://learn.chatgpt.com/docs/app-server' -and $toolText -notmatch 'unbekannte Eventform|Status unbekannt') 'Failure 1: concrete tool/action without invented status'
Assert ((Render (Event 'internalFutureItem' @{payload='PRIVATE_INTERNAL'} 'item/started')) -eq '') 'Unmapped internal event suppressed'
$command = 'powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "Get-Content scripts/delegation/Start-DelegatedCodexTask.ps1; git status --short"'
$cmdText = Render (Event 'commandExecution' @{command=$command;cwd='C:\repo';status='inProgress'} 'item/started')
Assert ($cmdText.Contains('PowerShell-Inline:') -and $cmdText.Contains('Get-Content scripts/delegation/Start-DelegatedCodexTask.ps1; git status --short') -and $cmdText.Contains($command) -and $cmdText -notmatch 'Argumente ausgeblendet') 'Failure 2: full wrapper and meaningful inline command'
$prose = 'Ich prüfe `scripts/delegation/Start-DelegatedCodexTask.ps1`, weil die Ausgabe fehlt. Danach teste ich die Fixtures; Quelle: https://learn.chatgpt.com/docs/app-server.'
Assert ((Render (Event 'agentMessage' @{phase='commentary';text=$prose})) -ceq ('Fortschritt: ' + $prose)) 'Failure 3: actual commentary, reason and next step preserved'

# Captured v2 fields from the harmless AR55 probe on 2026-10-12.
# Source: %TEMP%/agent-org-ar55-final-20261012/probe.json.events.jsonl.
# IDs/timestamps omitted, binding uses fixture IDs. Text/command/output match
# the capture, including the doubled backslashes in the shell wrapper.
$realCommand = '"C:\\Windows\\System32\\WindowsPowerShell\\v1.0\\powershell.exe" -Command Get-Location'
$realOutput = "`r`nPath                                                    `r`n----                                                    `r`nC:\Users\Tom-OliverMarek\source\repos\agent-organization`r`n`r`n`r`n"
$realStart = Event 'commandExecution' @{command=$realCommand;cwd='C:\Users\Tom-OliverMarek\source\repos\agent-organization';processId='69395';source='unifiedExecStartup';status='inProgress';commandActions=@(@{type='unknown';command='Get-Location'});aggregatedOutput=$null;exitCode=$null;durationMs=$null} 'item/started'
$realEnd = Event 'commandExecution' @{command=$realCommand;status='completed';aggregatedOutput=$realOutput;exitCode=0;durationMs=55}
$realEnd.params.item.id = $realStart.params.item.id
Assert ((Render $realStart).Contains("PowerShell-Inline:`nGet-Location")) 'Captured current CLI command start'
$realText = Render $realEnd
Assert ($realText -match 'Exitcode 0' -and $realText.Contains("Ausgabe:`n" + $realOutput.Replace("`r`n","`n"))) 'Captured current CLI completion and readable output'
$realComment = Event 'agentMessage' @{phase='commentary';text="Ich prüfe das aktuelle Arbeitsverzeichnis mit ``Get-Location``.`n";memoryCitation=$null;delivery=$null;questions=$null}
Assert ((Render $realComment).Contains('`Get-Location`')) 'Captured commentary with Markdown code'
# Captured path/kind/status from optimierer.json.events.jsonl; synthetic diff.
$file = Event 'fileChange' @{status='completed';changes=@(@{path='C:\Users\Tom-OliverMarek\source\repos\agent-organization\scripts\delegation\Start-DelegatedCodexTask.ps1';kind=@{type='update';move_path=$null};diff="-old`n+new"})}
$fileText = Render $file
Assert ($fileText -match 'Start-DelegatedCodexTask.ps1' -and $fileText.Contains("Diff:`n-old`n+new")) 'Captured file shape and synthetic readable diff'

# Generated 0.162.1 schema fixtures, not claims of observed live tool calls.
$mcp = Event 'mcpToolCall' @{server='local';tool='read_file';status='completed';arguments=@{path='docs/example.md';password='FIELD_CANARY'};result=@{content=@(@{type='text';text='Read 12 lines.'},@{type='image';data='BINARY_CANARY'});structuredContent=@{lines=12;accessToken='STRUCT_CANARY'};_meta=@{text='META_CANARY'}}}
$mcpText = Render $mcp
Assert ($mcpText -match 'local/read_file' -and $mcpText -match 'docs/example.md' -and $mcpText -match 'Read 12 lines' -and $mcpText -notmatch 'FIELD_CANARY|STRUCT_CANARY|BINARY_CANARY|META_CANARY') 'MCP public arguments/results with selective field protection'
Assert ((Render (Event 'mcpToolCall' @{server='local';tool='read_file';status='failed';error=@{message='File missing: docs/example.md'}})) -match 'Fehler: File missing: docs/example.md') 'MCP supplied error message'
$dynamic = Render (Event 'dynamicToolCall' @{namespace='functions';tool='exec_command';status='completed';success=$true;arguments=@{cmd='git status --short'};contentItems=@(@{type='inputText';text='working tree clean'},@{type='inputImage';imageUrl='BINARY_CANARY'})})
Assert ($dynamic -match 'functions/exec_command' -and $dynamic -match 'git status --short' -and $dynamic -match 'working tree clean' -and $dynamic -notmatch 'BINARY_CANARY') 'Dynamic tool namespace, arguments and text result'
Assert ((Render (Event 'imageView' @{path='C:\repo\preview.png'})) -match 'imageView\nPfad: C:\\repo\\preview.png') 'Image viewer name and supplied path'
Assert ((Render (Event 'webSearch' @{query='test';results=@(@{title='Found';url='https://example.com'})})) -match 'Found') 'Web result rendered only when supplied'
$collab = Render (Event 'collabAgentToolCall' @{tool='wait';status='completed';receiverThreadIds=@('child');prompt='INTERNAL_PROMPT'})
Assert ($collab -match 'wait; Status completed\nZielthreads: child' -and $collab -notmatch 'INTERNAL_PROMPT' -and (Render (Event 'collabToolCall' @{tool='wait';receiverThreadId='child'})) -match 'Zielthread: child') 'Current/documented collab shapes; no delegation executed'

$state = New-ProgressState; $state.secrets = @('KNOWN_CANARY')
$sensitive = 'Write-Host KNOWN_CANARY; --password "value with spaces"; token=QUERY_CANARY; Bearer BEARER_CANARY; https://user:URL_CANARY@host/path?api_key=API_CANARY; git status --short'
$safe = Get-ProgressCommand $sensitive $state
Assert ($safe -notmatch 'KNOWN_CANARY|value with spaces|QUERY_CANARY|BEARER_CANARY|URL_CANARY|API_CANARY' -and $safe.Contains('git status --short') -and $safe.Contains('Write-Host')) 'Sensitive values masked; safe command arguments retained'
Assert ((Protect-ProgressText $safe $state) -ceq $safe -and (Protect-ProgressText $mcpText $state) -ceq $mcpText) 'Masking is idempotent across formatter and writer'
Assert ((Protect-ProgressText "KNOWN$([char]27)[31m_CANARY" $state) -eq '[maskiert]') 'Control-separated known value protected before rendering'
Assert ((Protect-ProgressText 'countertoken=12; ordinary prose' $state) -eq 'countertoken=12; ordinary prose') 'Unrelated key suffix not treated as credential'
Assert ((ConvertTo-ProgressPayload @{nested=@(@{value='quote"slash\canary'})} @{secrets=@('quote"slash\canary')}) -notmatch 'canary') 'Known structured value protected before JSON escaping'
foreach ($payload in @(@{'quote"slash\canary'='public'}, [pscustomobject]@{'quote"slash\canary'='public'})) {
    $safePayload = ConvertTo-ProgressPayload $payload @{secrets=@('quote"slash\canary')}
    Assert ($safePayload -notmatch 'canary' -and ($safePayload | ConvertFrom-Json).'[maskiert]' -eq 'public') 'Known dictionary/object key protected before JSON escaping'
}
$collision = ConvertTo-ProgressPayload ([ordered]@{CANARY_SAFE='one';maskiert='two';'[maskiert]'='three'}) @{secrets=@('maskiert','CANARY_SAFE')}
Assert (@(($collision | ConvertFrom-Json).PSObject.Properties).Count -eq 3 -and $collision -notmatch 'CANARY_SAFE|\[\[maskiert\]\]') 'Masked key collisions preserve all fields'
$markerState = @{secrets=@('maskiert','CANARY_SAFE')}
$markerText = Protect-ProgressText 'maskiert CANARY_SAFE [maskiert] token=CANARY_SAFE Bearer CANARY_SAFE' $markerState
Assert ($markerText -ceq '[maskiert] [maskiert] [maskiert] token="[maskiert]" Bearer [maskiert]' -and (Protect-ProgressText $markerText $markerState) -ceq $markerText) 'Known marker word and safe canary remain idempotent'
Assert ((Protect-ProgressText 'sk-ABC123test ghp_abcd1234 github_pat_abcd1234' $state) -notmatch 'ABC123|abcd1234') 'Credential signatures masked'
Assert ((Protect-ProgressText 'Tokenabrechnung wird gesichert; token usage: 12' $state) -eq 'Tokenabrechnung wird gesichert; token usage: 12') 'Accounting prose is not a credential'
Assert ((Protect-ProgressText "safe$([char]27)[31m red$([char]27)[0m`nnext$([char]27)]0;EVIL_TITLE$([char]7)" $state) -eq "safe red`nnext") 'ANSI/OSC removed, newlines retained'
Assert ((Render (Event 'commandExecution' @{command='custom-tool --file docs/test.md';aggregatedOutput='known output';status='failed';exitCode=7})) -match 'custom-tool --file docs/test.md' -and (Render (Event 'commandExecution' @{status='RAW_STATUS';exitCode='RAW_EXIT'})) -notmatch 'RAW_|unbekannt') 'Executable visible; missing/malformed metadata not invented'
$longCommand = 'rg --files ' + ('C:\long\path\' * 60) + ' final-file.md'
$wrapped = @(Format-ProgressLines (Protect-ProgressText $longCommand $state) 40)
Assert (($wrapped -join '') -ceq $longCommand -and @($wrapped | Where-Object Length -gt 40).Count -eq 0) 'Long command wraps losslessly without truncation'
Assert ((@(Format-ProgressLines "first`n`nsecond" 40) -join "`n") -ceq "first`n`nsecond") 'Paragraphs and blank lines preserved'
$manyFiles = Render (Event 'fileChange' @{changes=@(1..5 | ForEach-Object {@{path="docs/file$_.md"}})})
Assert ($manyFiles -match 'file5.md' -and $manyFiles -notmatch 'ausgeblendet') 'All supplied file paths survive'

# Identity/stage dedup, not content hashes. Legacy is not a second public source.
$state = New-ProgressState
Assert ((Render $realStart $state) -ne '' -and (Render $realEnd $state) -ne '' -and (Render $realEnd $state) -eq '') 'Start/end retained, ID replay deduplicated'
$legacy = @{method='codex/event/exec_command_end';params=@{threadId='own';turnId='turn';msg=@{type='exec_command_end';call_id=$realEnd.params.item.id;aggregated_output=$realOutput;exit_code=0}}}
$legacyStart = @{method='codex/event/exec_command_begin';params=@{threadId='own';turnId='turn';msg=@{type='exec_command_begin';call_id=$realStart.params.item.id;command=$realCommand}}}
foreach ($legacyFirst in @($true,$false)) {
    $state = New-ProgressState
    $pair = if ($legacyFirst) { @($legacyStart,$realStart,$legacy,$realEnd) } else { @($realStart,$legacyStart,$realEnd,$legacy) }
    $shown = @($pair | ForEach-Object {Get-PublicProgress $_ 'own' 'turn' $state})
    Assert ($shown.Count -eq 2 -and $shown[0] -match 'Befehl Start' -and $shown[1] -match 'Exitcode 0' -and (Render $legacyStart) -eq '' -and (Render $legacy) -eq '') "Legacy/current start/end each once; legacy-only technical (legacy first: $legacyFirst)"
}
$state = New-ProgressState
Assert ((Render $realComment $state) -ne '' -and (Render $realComment $state) -eq '' -and (Render (Event 'agentMessage' @{phase='commentary';text=$realComment.params.item.text}) $state) -ne '') 'Replay suppressed; distinct messages with same prose retained'
foreach ($type in @('reasoning','userMessage','hookPrompt','plan','contextCompaction','internalFutureItem')) {
    Assert ((Render (Event $type @{text='PRIVATE_INTERNAL';content='PRIVATE_INTERNAL';summary='PRIVATE_INTERNAL'})) -eq '') "$type suppressed"
}
foreach ($method in @('item/reasoning/textDelta','item/reasoning/summaryTextDelta','item/commandExecution/outputDelta','item/agentMessage/delta','rawResponseItem/completed')) {
    Assert ((Render (Event 'agentMessage' @{text='PRIVATE_INTERNAL'} $method)) -eq '') "$method suppressed; authoritative item only"
}
$final = Event 'agentMessage' @{phase='final_answer';text='PUBLIC_FINAL'}
$state = New-ProgressState
Assert ((Render $realComment $state) -match 'Fortschritt:' -and (Render $final $state) -ceq "Ergebnis (vollständig, maskiert):`nPUBLIC_FINAL" -and (Render $final $state) -eq '' -and (Render (Event 'agentMessage' @{text='UNKNOWN_PHASE'})) -eq '') 'Commentary and public final each once; unknown phase suppressed'
$functionText = Render (Event 'functionCallOutput' @{name='exec_command';namespace='functions';output='PUBLIC_FUNCTION_OUTPUT'})
$functionContent = Render (Event 'functionCallOutput' @{name='read';namespace=$null;output=@(@{type='input_text';text='PUBLIC_TEXT'},@{type='input_image';image_url='BINARY_CANARY'},@{type='encrypted_content';encrypted_content='ENCRYPTED_CANARY'})})
$sleepStart = Event 'sleep' @{durationMs=1500} 'item/started'
$sleepEnd = Event 'sleep' @{durationMs=1500}; $sleepEnd.params.item.id = $sleepStart.params.item.id
Assert ($functionText -match 'functions/exec_command' -and $functionText -match 'PUBLIC_FUNCTION_OUTPUT' -and $functionText -notmatch 'Status' -and $functionContent -match 'PUBLIC_TEXT' -and $functionContent -notmatch 'BINARY_CANARY|ENCRYPTED_CANARY') 'Local functionCallOutput string/text schema rendered without invented status'
$state = New-ProgressState
Assert ((Render $sleepStart $state) -ceq "Pause Start`nDauer (ms): 1500" -and (Render $sleepEnd $state) -ceq "Pause Ende`nDauer (ms): 1500" -and (Render $sleepEnd $state) -eq '' -and (Render (Event 'sleep')) -ceq 'Pause Ende') 'Local sleep duration/start/end/replay without invented metadata'
Assert ((Render (Event 'commandExecution' @{} 'item/started' 'foreign')) -eq '' -and (Render (Event 'commandExecution' @{} 'item/started' 'own' 'foreign')) -eq '' -and @(Get-PublicProgress $realStart 'own' '' (New-ProgressState)).Count -eq 0) 'Foreign/unbound thread and turn excluded'
$end = @{method='turn/completed';params=@{threadId='own';turn=@{id='turn';status='completed'}}}
$state = New-ProgressState; $state.count = 200
Assert ((Render $realEnd $state) -ne '' -and (Render $end $state) -match 'Tokenabrechnung wird gesichert') 'Full output and completion survive former event cap'
$layout = @(Format-DelegatedStartLayout 'Teamleiter Äpfel' 'Eine Aufgabe mit ausreichend Worten zum Umbruch und Prüfung.' "Erster Absatz`n`nZweiter Absatz" 40)
Assert ($layout[0] -eq ('=' * 40) -and $layout[-4] -eq ('=' * 40) -and $layout[2] -ceq 'TEAMLEITER ÄPFEL' -and $layout -contains ('-' * 40) -and $layout -contains 'KONTEXT' -and $layout[-2] -eq 'FORTSCHRITT' -and @($layout | Where-Object Length -gt 40).Count -eq 0) 'Separators, uppercase role, spacing and layout retained'

# Actual production host/log/file writer, without executing the starter.
$resultFile = Join-Path ([IO.Path]::GetTempPath()) ('ar-public-progress-fixture-' + [guid]::NewGuid().ToString('N') + '.json')
$utf8 = New-Object System.Text.UTF8Encoding($false)
$progressState = New-ProgressState; $progressState.secrets = @('DISPLAY_CANARY')
$evidence = @{thread_id='own';turn_id='turn';output=("DISPLAY_CANARY password=UNKNOWN`n" + ('X' * 1000));success=$true;terminal_outcome='completed'}
try {
    $records = @(Write-ProgressDisplay $evidence.output 6>&1)
    $rows = @(Get-Content ($resultFile + '.events.jsonl') -Encoding UTF8 | ForEach-Object { $_ | ConvertFrom-Json })
    $hostText = @($records | ForEach-Object {[string]$_.MessageData})
    $logText = @($rows | ForEach-Object {$_.data.text})
    Assert ($records.Count -eq $rows.Count -and ($hostText -join "`n") -ceq ($logText -join "`n") -and @($rows | Where-Object {$_.kind -ne 'display' -or $_.data.thread_id -ne 'own' -or $_.data.turn_id -ne 'turn'}).Count -eq 0) 'Write-Host equals identity-bound display evidence'
    $public = Get-Content ($resultFile + '.public.txt') -Raw -Encoding UTF8
    Assert ($public.Contains('X' * 1000) -and $public -notmatch 'DISPLAY_CANARY|UNKNOWN|[\x00-\x09\x0b-\x1f]' -and @($hostText | Where-Object Length -gt 88).Count -eq 0) 'Full safe text file and masked bounded display'
    Write-Json $resultFile $evidence
    $saved = Get-Content $resultFile -Raw -Encoding UTF8 | ConvertFrom-Json
    Assert ($saved.output -ceq $evidence.output -and $saved.success -and $saved.terminal_outcome -eq 'completed') 'Raw result/outcome contract retained separately'
    Assert ([regex]::Matches($ast.Extent.Text, 'ForEach-Object \{ Write-ProgressDisplay \$_ \}').Count -eq 2 -and $ast.Extent.Text -notmatch 'Write-(?:Host|ProgressDisplay) \$evidence.output') 'Live/replay/final share safe writer; raw output is never redisplayed'
    if ($DisplayEvidencePath) { Copy-Item -LiteralPath ($resultFile + '.events.jsonl') -Destination $DisplayEvidencePath }
} finally {
    Remove-Item -LiteralPath $resultFile, ($resultFile + '.events.jsonl'), ($resultFile + '.public.txt') -Force -ErrorAction SilentlyContinue
}
if ($EvidenceStream) {
    $state = New-ProgressState
    $rows = @(Get-Content -LiteralPath $EvidenceStream -Encoding UTF8 | ForEach-Object { $_ | ConvertFrom-Json })
    $ownTurn = $rows | Where-Object { $_.data.method -eq 'turn/started' } | Select-Object -First 1
    if (-not $ownTurn) { throw 'Evidence stream has no bound turn/started' }
    $shown = @($rows | Where-Object kind -eq 'notification' | ForEach-Object { Get-PublicProgress $_.data $ownTurn.data.params.threadId $ownTurn.data.params.turn.id $state })
    $text = $shown -join "`n"
    # Recorded command outputs include historical formatter/test source, which
    # legitimately quotes old failure strings. Check emitted fallback headers.
    Assert ($shown.Count -gt 0 -and $text -notmatch '(?m)^(?:Werkzeug (?:Start|Ende): unbekannte Eventform|Befehl (?:Start|Ende): powershell.exe \(Argumente ausgeblendet\)|Fortschritt: \(öffentliche Meldung; Nutzlast ausgeblendet\))') 'Real stream has none of the reported fallback failures'
    Assert ($text -match 'Befehl Ende; Status completed; Exitcode 0' -and $text -match 'Ausgabe:' -and $text -match 'Fortschritt:') 'Real stream supplies result/output and commentary'
    $publicMessages = @($rows | Where-Object { $_.kind -eq 'notification' -and $_.data.method -eq 'item/completed' -and $_.data.params.threadId -ceq $ownTurn.data.params.threadId -and $_.data.params.turnId -ceq $ownTurn.data.params.turn.id -and $_.data.params.item.type -eq 'agentMessage' -and $_.data.params.item.phase -in @('commentary','final_answer') } | ForEach-Object { $_.data.params.item } | Sort-Object id -Unique)
    $messageBlocks = @($shown | Where-Object { $_ -match '^(Fortschritt: |Ergebnis \(vollständig, maskiert\):)' })
    $secondReplay = @($rows | Where-Object kind -eq 'notification' | ForEach-Object { Get-PublicProgress $_.data $ownTurn.data.params.threadId $ownTurn.data.params.turn.id $state })
    Assert ($messageBlocks.Count -eq $publicMessages.Count -and @($shown | Where-Object { $_ -match '^Ergebnis \(vollständig, maskiert\):' }).Count -eq @($publicMessages | Where-Object phase -eq 'final_answer').Count -and $secondReplay.Count -eq 0) 'Real bound commentary/final count matches unique public items; replay silent'
    if ($DisplayEvidencePath) {
        $resultFile = $DisplayEvidencePath + '.replay'
        if (Test-Path ($resultFile + '.events.jsonl')) { throw 'Replay destination already exists' }
        if (Test-Path ($resultFile + '.public.txt')) { throw 'Replay public destination already exists' }
        $progressState = $state
        $evidence = @{thread_id=$ownTurn.data.params.threadId;turn_id=$ownTurn.data.params.turn.id}
        $replayHost = @($shown | ForEach-Object { Write-ProgressDisplay $_ } 6>&1)
        $replayRows = @(Get-Content ($resultFile + '.events.jsonl') -Encoding UTF8 | ForEach-Object { $_ | ConvertFrom-Json })
        Assert ((@($replayHost | ForEach-Object {[string]$_.MessageData}) -join "`n") -ceq (@($replayRows | ForEach-Object {$_.data.text}) -join "`n")) 'Actual review replay host lines equal saved display evidence'
    }
    Write-Host ('Existing stream public blocks: ' + $shown.Count)
}
[pscustomobject]@{passed=$true;checkCount=$script:checks}
