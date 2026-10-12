[CmdletBinding()]
param()
$ErrorActionPreference = 'Stop'
$utf8 = New-Object System.Text.UTF8Encoding($false, $true)
$fixtureRoot = Join-Path ([System.IO.Path]::GetTempPath()) ('agent-org-usage-test-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $fixtureRoot | Out-Null
$helper = Join-Path $PSScriptRoot 'Get-TaskTokenUsage.ps1'
$passed = 0
function Assert($Condition, [string]$Label) { if (-not $Condition) { throw "FAIL: $Label" }; $script:passed++; Write-Host "PASS: $Label" }
function Usage([long]$Total) {
    return [pscustomobject]@{ inputTokens = $Total - 2; cachedInputTokens = 1; outputTokens = 2; reasoningOutputTokens = 1; totalTokens = $Total }
}
function Record($Id, $Parent, $Usage, $Thread = $Id, $Turn = 'turn') {
    return [pscustomobject]@{ task_id = $Id; parent_task_id = $Parent; role = 'fixture'; thread_id = $Thread; turn_id = $Turn; token_usage = $Usage }
}
function Fixture($Records) {
    $dir = Join-Path $fixtureRoot ([guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $dir | Out-Null
    $i = 0
    foreach ($record in $Records) {
        [System.IO.File]::WriteAllText((Join-Path $dir ((++$i).ToString() + '.usage.json')), ($record | ConvertTo-Json -Depth 10), $utf8)
    }
    return $dir
}
function Must-Fail($Records, $Id, [string]$Pattern, [string]$Label) {
    $dir = Fixture $Records
    $failed = $false
    try { $null = & $helper -TaskId $Id -AccountingDirectory $dir } catch { $failed = $_.Exception.Message -match $Pattern }
    Assert $failed $Label
}
try {
    $a = [guid]::NewGuid().ToString('N'); $b = [guid]::NewGuid().ToString('N'); $c = [guid]::NewGuid().ToString('N'); $d = [guid]::NewGuid().ToString('N')
    $ra = Record $a $null (Usage 10); $rb = Record $b $a (Usage 20); $rc = Record $c $b (Usage 30)
    $dir = Fixture @($ra, $rb, $rc)
    $result = & $helper -TaskId $a -AccountingDirectory $dir
    Assert ($result.own.totalTokens -eq 10 -and $result.inclusive.totalTokens -eq 60 -and $result.missing_count -eq 0) 'Eltern-Kind-Enkel: eigene 10, inklusive 60'
    Assert ($result.inclusive.inputTokens -eq 54 -and $result.inclusive.cachedInputTokens -eq 3 -and $result.inclusive.reasoningOutputTokens -eq 3 -and $result.inclusive.cacheWriteInputTokens -eq 0) 'Native Kategorien ohne Teilmengen-Doppelzählung, optionaler Cache-Write=0'
    $result = & $helper -TaskId $b -AccountingDirectory $dir
    Assert ($result.inclusive.totalTokens -eq 50 -and $result.task_count -eq 2) 'Teilbaum enthält keine Elternverbrauchswerte'
    $dir = Fixture @($ra, $ra, $rb, $rc)
    $result = & $helper -TaskId $a -AccountingDirectory $dir
    Assert ($result.inclusive.totalTokens -eq 60 -and $result.task_count -eq 3) 'Identischer Task-Datensatz dedupliziert'
    $dir = Fixture @($ra, $rb, $rc, (Record $d $a (Usage 20) $b))
    $result = & $helper -TaskId $a -AccountingDirectory $dir
    Assert ($result.inclusive.totalTokens -eq 60 -and $result.distinct_known_usage_count -eq 3) 'Native Thread/Turn-Identität dedupliziert'
    $dir = Fixture @($ra, (Record $b $a $null))
    $result = & $helper -TaskId $a -AccountingDirectory $dir
    Assert ($result.own.totalTokens -eq 10 -and $null -eq $result.inclusive -and $result.known_partial.totalTokens -eq 10 -and $result.missing_count -eq 1) 'Unbekanntes Kind lässt inklusive Summe unbekannt'
    $dir = Fixture @((Record $b $a (Usage 20)), $rc)
    $result = & $helper -TaskId $a -AccountingDirectory $dir
    Assert ($null -eq $result.own -and $null -eq $result.inclusive -and $result.known_partial.totalTokens -eq 50 -and $result.missing_count -eq 1) 'Externe Root ohne eigene Messung: bekannte Nachkommen 50'
    $dir = Fixture @((Record $a $null $null $null $null))
    $result = & $helper -TaskId $a -AccountingDirectory $dir
    Assert ($null -eq $result.own -and $null -eq $result.inclusive -and $result.missing_count -eq 1) 'Kein Event bedeutet null statt gemessener Null'
    $dir = Fixture @()
    $result = & $helper -TaskId $a -AccountingDirectory $dir
    Assert ($null -eq $result.own -and $result.missing_count -eq 1) 'Leeres Ledger hat unbekannte Root'
    $zero = [pscustomobject]@{ inputTokens = 0; cachedInputTokens = 0; outputTokens = 0; reasoningOutputTokens = 0; totalTokens = 0; cacheWriteInputTokens = 0 }
    $dir = Fixture @((Record $a $null $zero))
    $result = & $helper -TaskId $a -AccountingDirectory $dir
    Assert ($null -ne $result.own -and $result.inclusive.totalTokens -eq 0 -and $result.missing_count -eq 0) 'Native gemessene Null bleibt bekannte Null'
    $withCacheWrite = Usage 10; $withCacheWrite | Add-Member cacheWriteInputTokens 4
    $dir = Fixture @((Record $a $null $withCacheWrite))
    $result = & $helper -TaskId $a -AccountingDirectory $dir
    Assert ($result.inclusive.cacheWriteInputTokens -eq 4 -and $result.inclusive.totalTokens -eq 10) 'Cache-Write separat ohne Addition zur nativen Gesamtsumme'
    Must-Fail @($ra, (Record $a $null (Usage 11))) $a 'Task-Duplikate' 'Widersprüchliche Task-ID schlägt fehl'
    Must-Fail @($ra, (Record $b $a (Usage 11) $a)) $a 'Thread/Turn-Duplikate' 'Widersprüchliche native Identität schlägt fehl'
    Must-Fail @((Record $a $b (Usage 10)), (Record $b $a (Usage 20))) $a 'Zyklus' 'Elternzyklus schlägt fehl'
    Must-Fail @((Record $a $a (Usage 10))) $a 'Zyklus' 'Selbstzyklus schlägt fehl'
    Must-Fail @([pscustomobject]@{ task_id = $a }) $a 'Ledgerfeld fehlt' 'Fehlende Felder schlagen fehl'
    Must-Fail @((Record 'kein-guid' $null (Usage 10))) $a 'Task-ID' 'Ungültige Task-ID schlägt fehl'
    $bad = Usage 10; $bad.totalTokens = -1
    Must-Fail @((Record $a $null $bad)) $a 'Tokenwert' 'Negativer Verbrauch schlägt fehl'
    $bad = Usage 10; $bad.totalTokens = 1.5
    Must-Fail @((Record $a $null $bad)) $a 'Tokenwert' 'Bruchzahl schlägt fehl'
    $bad = Usage 10; $bad.cachedInputTokens = 99
    Must-Fail @((Record $a $null $bad)) $a 'Teilmengen' 'Ungültige Teilmengen schlagen fehl'
    Must-Fail @((Record $a $null (Usage 10) 123)) $a 'native Identität' 'Nichttextuelle native Identität schlägt fehl'
    Must-Fail @((Record $a $null (Usage ([long]::MaxValue))), (Record $b $a (Usage 10))) $a 'Summenüberlauf' 'Summenüberlauf schlägt fehl statt unendlicher Werte'
    $badRecord = Record $a $null (Usage 10); $badRecord | Add-Member status 'completed'
    Must-Fail @($badRecord) $a 'status-Feld' 'Ledger enthält kein status'
    $dir = Fixture @(); [System.IO.File]::WriteAllText((Join-Path $dir 'bad.usage.json'), '{broken', $utf8)
    $failed = $false; try { $null = & $helper -TaskId $a -AccountingDirectory $dir } catch { $failed = $true }
    Assert $failed 'Malformed JSON schlägt fehl'

    # Produktionsfunktionen isoliert aus AST laden: kein Runner, kein HWND, kein Modell.
    $parseTokens = $null; $parseErrors = $null
    $ast = [System.Management.Automation.Language.Parser]::ParseFile((Join-Path $PSScriptRoot 'Start-DelegatedCodexTask.ps1'), [ref]$parseTokens, [ref]$parseErrors)
    Assert ($parseErrors.Count -eq 0) 'Starter parst unter Windows PowerShell'
    foreach ($name in @('Update-NativeUsage', 'Write-Event', 'Read-Rpc', 'Wait-Rpc', 'Send-Rpc', 'Test-ConsoleBinding', 'Get-FinalLedgerUsage',
        'New-ProgressState', 'Protect-ProgressText', 'Get-ProgressName', 'Get-ProgressCommand', 'Get-ProgressPath', 'Get-PublicProgress', 'Write-ProgressDisplay')) {
        $definition = $ast.Find({ param($node) $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq $name }, $true)
        Invoke-Expression $definition.Extent.Text
    }
    $owned = [pscustomobject]@{ task_id = 'own'; title = 'Qualitätssicherung - Token Summierung prüfen'; window_handle = 22; window_pid = 44 }
    Assert (Test-ConsoleBinding $owned 10 10 @(22) 44 'own' $owned.title) 'Eigener Consolehandle, Hostparent und PID bestätigt'
    Assert (-not (Test-ConsoleBinding $owned 10 10 @(23) 44 'own' $owned.title)) 'Fremdes neues Titelgleichfenster abgelehnt'
    Assert (-not (Test-ConsoleBinding $owned 10 11 @(22) 44 'own' $owned.title)) 'Runner ohne eigenen gestarteten Host abgelehnt'
    Assert (-not (Test-ConsoleBinding $owned 10 10 @(22) 45 'own' $owned.title)) 'Fremder Fensterbesitzer abgelehnt'
    Assert (-not (Test-ConsoleBinding $owned 10 10 @(22,23) 44 'own' $owned.title)) 'Mehrdeutige Titelgleichfenster abgelehnt'
    $close = $ast.Find({ param($node) $node -is [System.Management.Automation.Language.IfStatementAst] -and $node.Clauses[0].Item1.Extent.Text -match "Role -cne 'koordinator'" }, $true)
    $closeCondition = [scriptblock]::Create($close.Clauses[0].Item1.Extent.Text)
    $Role = 'koordinator'; $KeepWindowOpen = $false; $confirmed = $true; $runner = @{ HasExited = $true }
    foreach ($outcome in @('completed','error','timeout')) { Assert (-not (& $closeCondition)) ('Koordinator niemals automatisch schließen: ' + $outcome) }
    # Test the actual assignment guard, not a duplicated role policy.
    $forceKeep = $ast.Find({ param($node) $node -is [System.Management.Automation.Language.IfStatementAst] -and $node.Extent.Text.StartsWith("if (`$Role -ceq 'koordinator') { `$KeepWindowOpen = `$true }") }, $true)
    Invoke-Expression $forceKeep.Extent.Text
    Assert ([bool]$KeepWindowOpen) 'Koordinator bleibt auch ohne KeepWindowOpen offen'
    Assert ($null -eq (Get-FinalLedgerUsage @{ usage_finalized = $false; token_usage = (Usage 10) })) 'Fehler-/Timeoutsnapshot nicht als vollständige Ledgernutzung zählen'
    Assert ((Get-FinalLedgerUsage @{ usage_finalized = $true; token_usage = (Usage 10) }).totalTokens -eq 10) 'Final drain bestätigt gemessene Ledgernutzung'
    $evidence = [ordered]@{ thread_id = 'own-thread'; turn_id = $null; token_usage = $null }
    $notifications = New-Object System.Collections.Generic.List[object]
    $progressState = New-ProgressState
    $resultFile = Join-Path $fixtureRoot 'rpc-result'
    function Notification($Total, $Thread = 'own-thread', $Turn = 'own-turn') {
        return @{ method = 'thread/tokenUsage/updated'; params = @{ threadId = $Thread; turnId = $Turn; tokenUsage = @{ total = (Usage $Total); last = (Usage 5) } } }
    }
    Update-NativeUsage (Notification 10)
    Assert ($null -eq $evidence.token_usage) 'Usage ohne bestätigte Turn-ID wird nicht zugeordnet'
    $evidence.turn_id = 'own-turn'
    Update-NativeUsage (Notification 10); Update-NativeUsage (Notification 20)
    Update-NativeUsage (Notification 99 'foreign-thread'); Update-NativeUsage (Notification 98 'own-thread' 'foreign-turn')
    Assert ($evidence.token_usage.totalTokens -eq 20) 'Snapshots ersetzt; fremder Thread und Turn ignoriert'
    $lines = @(
        @{ method = 'turn/completed'; params = @{ threadId = 'own-thread'; turn = @{ id = 'own-turn'; status = 'completed' } } },
        (Notification 30),
        @{ id = 5; result = @{ thread = @{ id = 'own-thread' } } }
    ) | ForEach-Object { $_ | ConvertTo-Json -Depth 20 -Compress }
    $stream = New-Object System.IO.MemoryStream
    $process = [pscustomobject]@{ StandardOutput = (New-Object System.IO.StringReader(($lines -join "`n"))); StandardInput = [pscustomobject]@{ BaseStream = $stream } }
    $deadline = [DateTime]::UtcNow.AddSeconds(5)
    Send-Rpc 'thread/read' @{ threadId = 'own-thread'; includeTurns = $false } 5
    $reply = Wait-Rpc 5
    Assert ($evidence.token_usage.totalTokens -eq 30 -and $reply.thread.id -eq 'own-thread') 'Flush-Roundtrip liest letzte Usage nach Turn-Ende'
    $rawEvents = [System.IO.File]::ReadAllLines($resultFile + '.events.jsonl', $utf8) | ForEach-Object { $_ | ConvertFrom-Json }
    $usageEvent = $rawEvents | Where-Object { $_.data.method -eq 'thread/tokenUsage/updated' }
    Assert ($usageEvent.data.params.tokenUsage.total.totalTokens -eq 30 -and $usageEvent.data.params.tokenUsage.last.totalTokens -eq 5) 'Raw native Usage mit total und last im JSON-Event erhalten'
    $request = $utf8.GetString($stream.ToArray()) | ConvertFrom-Json
    Assert ($request.method -eq 'thread/read' -and $request.params.includeTurns -eq $false) 'Flush verwendet schema-konformen metadata-only thread/read'
    Write-Host "Offline erfolgreich: $passed Prüfungen. Fixtures: $fixtureRoot"
    exit 0
} catch {
    Write-Error -ErrorAction Continue $_
    Write-Host "Offline fehlgeschlagen nach $passed Prüfungen. Fixtures: $fixtureRoot"
    exit 1
}
