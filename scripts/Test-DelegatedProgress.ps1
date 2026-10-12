[CmdletBinding()]
param([string]$EvidenceStream, [string]$DisplayEvidencePath)
$ErrorActionPreference = 'Stop'
# Load only pure formatter functions: never execute the starter or open a window.
$tokens = $null; $errors = $null
$ast = [System.Management.Automation.Language.Parser]::ParseFile((Join-Path $PSScriptRoot 'Start-DelegatedCodexTask.ps1'), [ref]$tokens, [ref]$errors)
if ($errors.Count) { throw 'Starter parser failed' }
$names = @('Format-DelegatedStartLayout','New-ProgressState','Protect-ProgressText','Get-ProgressName','Get-ProgressCommand','Get-ProgressPath','Get-PublicProgress','Write-ProgressDisplay','Write-Event','Write-Json')
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
$layout = @(Format-DelegatedStartLayout 'Teamleiter Äpfel' 'Eine vollständige Aufgabe mit mehreren Worten und einem abschließenden Prüfauftrag.' '' 40)
Assert ($layout[0] -eq ('=' * 40) -and $layout[-4] -eq ('=' * 40)) 'Layout top and bottom separators'
Assert ($layout[2] -ceq 'TEAMLEITER ÄPFEL' -and ($layout -join ' ') -notmatch 'Rolle:') 'Uppercase role without label'
Assert ($layout -contains 'AUFTRAG' -and $layout[-2] -eq 'FORTSCHRITT' -and $layout -notcontains 'KONTEXT') 'Required sections and optional context'
Assert (@($layout | Where-Object Length -gt 40).Count -eq 0) 'Task wraps within width'
Assert ((($layout | Where-Object { $_ -and $_ -notmatch '^[=-]+$|^TEAMLEITER|^AUFTRAG$|^FORTSCHRITT$' }) -join ' ') -eq 'Eine vollständige Aufgabe mit mehreren Worten und einem abschließenden Prüfauftrag.') 'Complete task preserved'
$contextLayout = @(Format-DelegatedStartLayout 'Optimierer' 'Aufgabe' "Erster Absatz`n`nZweiter Absatz" 40)
Assert ($contextLayout -contains 'KONTEXT' -and $contextLayout -contains 'Zweiter Absatz') 'Context separately wrapped'
Assert ((@(Format-DelegatedStartLayout 'Optimierer' ('x' * 130) '' 40) -join '') -match ('x' * 130)) 'Long unbroken token preserved'
$maskLayout = @(Format-DelegatedStartLayout 'Optimierer' 'Prüfe MYCANARY123 vollständig.' '' 40 @{secrets=@('MYCANARY123')})
Assert (($maskLayout -join ' ') -notmatch 'MYCANARY123' -and ($maskLayout -join ' ') -match 'maskiert') 'Start layout masks known secret before wrapping'
Assert ((Render (Event 'fileChange' @{status='failed';changes=@(1..3|ForEach-Object {@{path=('a' * 120)}})})) -match '; Status failed$') 'Long file paths retain status'
$ok = Event 'commandExecution' @{ command = 'git status --short'; status = 'completed'; exitCode = 0; aggregatedOutput = 'PRIVATE OUTPUT' }
$line = Render $ok
Assert ($line -match 'git status' -and $line -match 'Exitcode 0' -and $line -notmatch 'PRIVATE|--short') 'Command success without arguments or output'
Assert ((Render (Event 'commandExecution' @{command='dotnet build';status='failed';exitCode=7})) -match 'failed; Exitcode 7') 'Command failure'
Assert ((Render (Event 'commandExecution')) -match 'unbekannt') 'Missing fields safe fallback'
Assert ((Render (Event 'commandExecution' @{command='Get-Location';status='inProgress'} 'item/started')) -match 'Start: Get-Location') 'Command start'
$file = Event 'fileChange' @{status='completed'; changes=@(@{path='scripts/example.ps1';kind=@{type='update'};diff='PRIVATE CONTENT'})}
Assert ((Render $file) -match 'scripts/example.ps1' -and (Render $file) -notmatch 'PRIVATE CONTENT') 'File path without contents'
Assert ((Render (Event 'fileChange' @{changes=@(@{path='https://user:secret@host/?token=abc'})})) -notmatch 'user|abc|host') 'Unsafe path suppressed'
$state = New-ProgressState
$state.secrets = @('MYKNOWNVALUE123')
Assert ((Render (Event 'fileChange' @{changes=@(@{path='docs/MYKNOWNVALUE123.md'})}) $state) -match 'maskiert') 'Known secret in path masked'
Assert ((Protect-ProgressText 'sk-ABC123test ghp_abcd1234 Bearer abcd1234' $state) -notmatch 'ABC123|abcd1234') 'Known credential patterns masked'
Assert ((Render (Event 'commandExecution' @{command='powershell.exe -Command "Write-Host MYKNOWNVALUE123 --password unknown"'}) $state) -notmatch 'MYKNOWN|unknown|password|Write-Host') 'Sensitive and nested arguments omitted'
Assert ((Render (Event 'commandExecution' @{command='mystery --data arbitrary-secret'})) -notmatch 'mystery|arbitrary') 'Unknown executable payload omitted'
Assert ((Render (Event 'mcpToolCall' @{server='local';tool='read_file';status='failed';arguments=@{secret='HIDDEN'};error='RAW ERROR';result='RAW RESULT'})) -eq 'MCP Ende: local/read_file; Status failed') 'MCP metadata only'
Assert ((Render (Event 'dynamicToolCall' @{tool='lookup';status='completed';success=$false;contentItems=@('HIDDEN')})) -match 'lookup; Status completed; Erfolg False') 'Dynamic tool result metadata'
Assert ((Render (Event 'futureTool' @{arguments='HIDDEN';result='HIDDEN';status='failed'})) -eq 'Werkzeug Ende: unbekannte Eventform; Status failed') 'Unknown tool form metadata fallback'
Assert ((Render (Event 'mcpToolCall' @{server='server';tool='lookup?token=hidden'})) -notmatch 'hidden') 'Invalid tool label suppressed'
Assert ((Render (Event 'agentMessage' @{phase='commentary';text='Ich pruefe jetzt die Fixturetests.'})) -eq 'Fortschritt: Ich pruefe jetzt die Fixturetests.') 'Public commentary'
Assert ((Render (Event 'agentMessage' @{phase='final_answer';text='FINAL'})) -eq '') 'Final answer not repeated in progress'
Assert ((Render (Event 'agentMessage' @{text='unknown phase'})) -eq '') 'Unknown message phase ignored'
Assert ((Render (Event 'agentMessage' @{phase='commentary';text='secret=UNKNOWN'})) -notmatch 'UNKNOWN') 'Risky commentary metadata fallback'
Assert ((Render (Event 'agentMessage' @{phase='commentary';text='MYKNOWNVALUE123'} ) $state) -notmatch 'MYKNOWNVALUE') 'Known secret in public prose masked'
Assert ((Render (Event 'reasoning' @{text='REASONING';summary='REASONING';content='REASONING'})) -eq '') 'Reasoning item ignored'
foreach ($method in @('item/reasoning/textDelta','item/reasoning/summaryTextDelta','item/commandExecution/outputDelta','item/agentMessage/delta')) {
    Assert ((Render (Event 'agentMessage' @{text='HIDDEN'} $method)) -eq '') "$method ignored"
}
Assert ((Render (Event 'commandExecution' @{} 'item/started' 'foreign')) -eq '') 'Foreign thread ignored'
Assert ((Render (Event 'commandExecution' @{} 'item/started' 'own' 'foreign')) -eq '') 'Foreign turn ignored'
Assert ((@(Get-PublicProgress $ok 'own' '' $state)).Count -eq 0) 'No output before turn binding'
$state = New-ProgressState
$null = Render $ok $state
Assert ((Render $ok $state) -eq '') 'Duplicate event suppressed after replay'
$comment = Event 'agentMessage' @{phase='commentary';text='Pruefung laeuft.'}
$null = Render $comment $state
Assert ((Render (Event 'agentMessage' @{phase='commentary';text='Pruefung laeuft.'}) $state) -eq '') 'Repeated public message suppressed'
$long = Render (Event 'fileChange' @{changes=@(1..5 | ForEach-Object {@{path=('a' * 500)}})})
Assert ($long.Length -le 240 -and $long -notmatch "`n") 'Single line length bound'
Assert ((Render (Event 'agentMessage' @{phase='commentary';text=('A' * 500)})).Length -le 240) 'Public prose length bound'
Assert ((Protect-ProgressText "safe$([char]27)[31m`nnext" (New-ProgressState)) -notmatch '[\x00-\x1f]') 'Terminal control characters removed'
foreach ($status in @('completed','failed','interrupted')) {
    $e = @{method='turn/completed';params=@{threadId='own';turn=@{id='turn';status=$status}}}
    Assert ((Render $e) -match $status) "Turn $status"
    $e.params.turn.id = 'foreign'
    Assert ((Render $e) -eq '') "Foreign turn completion $status ignored"
}
$state = New-ProgressState; $state.count = 200
Assert ((Render $ok $state) -eq '') 'Turn display budget bounds output'
$end = @{method='turn/completed';params=@{threadId='own';turn=@{id='turn';status='completed'}}}
Assert ((Render $end $state) -match 'beendet: completed') 'Turn completion survives display budget'
Assert ((Render $end) -match 'Tokenabrechnung wird gesichert') 'Accounting label not mistaken for credential'
Assert ((Render (Event 'commandExecution' @{command='git status';exitCode='RAW SECRET';status='RAW STATUS'})) -notmatch 'RAW') 'Malformed result metadata omitted'
Assert ((Render (Event 'fileChange')) -match 'Pfad fehlt') 'Missing file path'
$state = New-ProgressState; $state.secrets = @('BOUNDARYSECRET')
Assert ((Protect-ProgressText (('a' * 175) + 'BOUNDARYSECRET') $state) -notmatch 'BOUNDARY') 'Secret masked before truncation'
Assert ((Get-ProgressCommand '"C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe" -Command "Get-Location"' $state) -match '^Get-Location') 'Harmless quoted wrapper recognized'
Assert ((Get-ProgressCommand "pwsh -NoProfile -Command 'Get-Location'" $state) -match '^Get-Location') 'Harmless pwsh wrapper recognized'
Assert ((Get-ProgressCommand '"C:\\Windows\\System32\\WindowsPowerShell\\v1.0\\powershell.exe" -NoProfile -Command Get-Location' $state) -match '^Get-Location') 'Historical probe wrapper recognized'
foreach ($payload in @('powershell.exe -Command "Get-Location; Write-Host SECRET"', 'powershell.exe -Command "Write-Host Get-Location"', 'powershell.exe -Command "Get-Location -StackName SECRET"')) {
    Assert ((Get-ProgressCommand $payload $state) -notmatch 'Get-Location|SECRET|Write-Host') 'Nontrivial wrapper payload stays hidden'
}
$state = New-ProgressState
foreach ($type in @('commandExecution','fileChange','agentMessage')) {
    $a = Event $type @{command='Get-Location';phase='commentary';text='Pruefung laeuft.'}
    $b = Event $type @{command='git status';phase='commentary';text='Pruefung laeuft.'}
    $a.params.item.PSObject.Properties.Remove('id'); $b.params.item.PSObject.Properties.Remove('id')
    Assert ((Render $a $state) -ne '' -and (Render $b $state) -ne '') "Two $type events without ID survive"
}
# Exercise the production Write-Host path; information records are actual host writes.
$resultFile = Join-Path ([IO.Path]::GetTempPath()) ('ar55-display-fixture-' + [guid]::NewGuid().ToString('N') + '.json')
$utf8 = New-Object System.Text.UTF8Encoding($false)
$progressState = New-ProgressState; $progressState.secrets = @('AR55_DISPLAY_CANARY')
$evidence = @{thread_id='own';turn_id='turn';output=("AR55_DISPLAY_CANARY password=UNKNOWN$([char]27)[31m`n" + ('X' * 1000));success=$true;terminal_outcome='completed'}
try {
    $records = @(Write-ProgressDisplay (Render $ok) 6>&1; Write-ProgressDisplay $evidence.output 6>&1)
    $rows = @(Get-Content ($resultFile + '.events.jsonl') -Encoding UTF8 | ForEach-Object { $_ | ConvertFrom-Json })
    Assert ($records.Count -eq 2 -and $rows.Count -eq 2 -and $rows[0].data.text -ceq [string]$records[0].MessageData -and $rows[1].data.text -ceq [string]$records[1].MessageData) 'Display log equals actual Write-Host lines'
    Assert ($rows[1].kind -eq 'display' -and $rows[1].data.thread_id -eq 'own' -and $rows[1].data.turn_id -eq 'turn') 'Display evidence has own thread and turn'
    Assert ($rows[1].data.text.Length -le 240 -and $rows[1].data.text -notmatch 'CANARY|UNKNOWN|[\x00-\x1f]') 'Final display masked and bounded before logging'
    Write-Json $resultFile $evidence
    $saved = Get-Content $resultFile -Raw -Encoding UTF8 | ConvertFrom-Json
    Assert ($saved.output -ceq $evidence.output -and $saved.success -and $saved.terminal_outcome -eq 'completed') 'Full result and outcome contract preserved'
    $starter = $ast.Extent.Text
    Assert ($starter -notmatch 'Write-Host \$evidence.output|Write-Output \$result.output' -and $starter -match 'Write-ProgressDisplay \$evidence.output') 'Final runner and caller have no raw output display bypass'
    Assert ([regex]::Matches($starter, 'ForEach-Object \{ Write-ProgressDisplay \$_ \}').Count -eq 2) 'Live and replay share the display writer'
    if ($DisplayEvidencePath) { Copy-Item -LiteralPath ($resultFile + '.events.jsonl') -Destination $DisplayEvidencePath }
} finally {
    Remove-Item -LiteralPath $resultFile, ($resultFile + '.events.jsonl') -Force -ErrorAction SilentlyContinue
}
if ($EvidenceStream) {
    $state = New-ProgressState; $emitted = @(); $thread = $null; $turn = $null
    $rows = @(Get-Content -LiteralPath $EvidenceStream -Encoding UTF8 | ForEach-Object { $_ | ConvertFrom-Json })
    $ownTurn = $rows | Where-Object { $_.data.method -eq 'turn/started' } | Select-Object -First 1
    $thread = $ownTurn.data.params.threadId; $turn = $ownTurn.data.params.turn.id
    foreach ($row in $rows) {
        if ($row.kind -eq 'notification') { $emitted += @(Get-PublicProgress $row.data $thread $turn $state) }
    }
    Assert ($emitted.Count -gt 0 -and @($emitted | Where-Object { $_.Length -gt 240 -or $_ -match '[\x00-\x1f]' }).Count -eq 0) 'Existing real stream produces bounded display'
    Assert (@($emitted | Where-Object { $_ -match 'Befehl Ende:.*Exitcode 0' }).Count -gt 0) 'Real command completion rendered'
    Assert (@($emitted | Where-Object { $_ -match '^Dateien.*optimierer.toml' }).Count -gt 0) 'Real file path rendered'
    Assert (@($emitted | Where-Object { $_ -match '^Fortschritt:' }).Count -gt 0) 'Real public commentary rendered'
    Write-Host ('Existing stream display lines: ' + $emitted.Count)
}
[pscustomobject]@{passed=$true;checkCount=$script:checks}
