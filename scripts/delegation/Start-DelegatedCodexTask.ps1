[CmdletBinding(DefaultParameterSetName = 'Start')]
param(
    [Parameter(Mandatory = $true, ParameterSetName = 'Start')][ValidatePattern('^[a-z][a-z0-9_]*$')][string]$Role,
    [Parameter(Mandatory = $true, ParameterSetName = 'Start')][string]$Task,
    [Parameter(ParameterSetName = 'Start')][ValidateScript({ ($_ -split '\s+' | Where-Object { $_ }).Count -eq 3 -and $_ -notmatch '[\r\n]' })][string]$TaskTitle,
    [Parameter(ParameterSetName = 'Start')][ValidateScript({ $_ -notmatch '[\r\n]' })][string]$RoleDisplayName,
    [Parameter(ParameterSetName = 'Start')][string]$ContextFile,
    [Parameter(Mandatory = $true, ParameterSetName = 'Start')][string]$WorkingDirectory,
    [Parameter(Mandatory = $true, ParameterSetName = 'Start')][string]$ResultPath,
    [Parameter(ParameterSetName = 'Start')][ValidateRange(5, 3600)][int]$TimeoutSeconds = 120,
    [Parameter(ParameterSetName = 'Start')][switch]$KeepWindowOpen,
    [Parameter(ParameterSetName = 'Start')][string]$ParentTaskId,
    [Parameter(ParameterSetName = 'Start')][string]$AccountingDirectory,
    [Parameter(Mandatory = $true, ParameterSetName = 'Runner')][string]$JobFile
)
$ErrorActionPreference = 'Stop'
$utf8 = New-Object System.Text.UTF8Encoding($false, $true)
if (-not ('AgentTerminalWindow' -as [type])) { Add-Type @'
using System; using System.Text; using System.Runtime.InteropServices; using System.Collections.Generic;
public static class AgentTerminalWindow {
 [DllImport("kernel32.dll")] public static extern IntPtr GetConsoleWindow();
 [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr h);
 [DllImport("user32.dll")] public static extern bool IsWindow(IntPtr h);
 [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr h,out uint p);
 [DllImport("user32.dll",CharSet=CharSet.Unicode)] public static extern int GetWindowText(IntPtr h,StringBuilder s,int n);
 public delegate bool EnumProc(IntPtr h,IntPtr p);
 [DllImport("user32.dll")] public static extern bool EnumWindows(EnumProc f,IntPtr p);
 [DllImport("user32.dll")] public static extern bool PostMessage(IntPtr h,uint m,IntPtr w,IntPtr l);
 [DllImport("user32.dll",CharSet=CharSet.Unicode)] public static extern bool SetProp(IntPtr h,string name,IntPtr data);
 [DllImport("user32.dll",CharSet=CharSet.Unicode)] public static extern IntPtr GetProp(IntPtr h,string name);
 public static string Title(IntPtr h){var s=new StringBuilder(512);GetWindowText(h,s,512);return s.ToString();}
 public static long[] ForPid(uint pid){var l=new List<long>();EnumWindows((h,p)=>{uint id;GetWindowThreadProcessId(h,out id);if(id==pid)l.Add(h.ToInt64());return true;},IntPtr.Zero);return l.ToArray();}
}
'@
}
function Write-Json([string]$Path, $Value) {
    [System.IO.File]::WriteAllText($Path + '.writing', ($Value | ConvertTo-Json -Depth 20), $utf8)
    [System.IO.File]::Move($Path + '.writing', $Path)
}
function Read-RoleString([string]$Text, [string]$Key) {
    $match = [regex]::Match($Text, '(?m)^' + [regex]::Escape($Key) + '\s*=\s*"([^"\r\n]*)"\s*$')
    if (-not $match.Success) { throw "Nicht unterstütztes Rollenfeld: $Key" }
    return $match.Groups[1].Value
}
function Format-TokenUsage($Usage) {
    if ($null -eq $Usage) { return 'unbekannt' }
    return ('Gesamt {0}; Eingabe {1} (davon Cache {2}); Ausgabe {3} (davon Reasoning {4})' -f
        $Usage.totalTokens, $Usage.inputTokens, $Usage.cachedInputTokens, $Usage.outputTokens, $Usage.reasoningOutputTokens)
}
function Test-ConsoleBinding($Window, [long]$LauncherPid, [long]$ChildParentPid, $Candidates, [long]$ActualOwner, [string]$TaskId, [string]$Title) {
    return ($ChildParentPid -eq $LauncherPid -and $Window.task_id -ceq $TaskId -and
        $Window.title -ceq $Title -and @($Candidates).Count -eq 1 -and
        [long]$Candidates[0] -eq [long]$Window.window_handle -and $ActualOwner -eq $Window.window_pid)
}
function Get-FinalLedgerUsage($Evidence) {
    if ($Evidence.usage_finalized) { return $Evidence.token_usage }
    return $null
}
function New-ProgressState {
    $secrets = @(Get-ChildItem Env: | Where-Object { $_.Name -match '(?i)secret|token|password|passwd|api_?key|credential|connection_?string' -and $_.Value.Length -ge 4 } | ForEach-Object { $_.Value })
    return @{ seen = @{}; count = 0; secrets = @($secrets | Sort-Object Length -Descending) }
}
function Protect-ProgressText([string]$Text, $State, [int]$Limit = [int]::MaxValue) {
    # Normalize controls before matching secrets, so an ANSI sequence cannot
    # separate the characters of a known value. Redact before wrapping/truncation.
    $Text = [regex]::Replace($Text, '\x1b\][^\x07\x1b]*(?:\x07|\x1b\\)|\x1b\[[0-?]*[ -/]*[@-~]', '')
    $Text = $Text.Replace("`r`n", "`n").Replace("`r", "`n").Replace("`t", '    ')
    $Text = [regex]::Replace($Text, '[\x00-\x09\x0b-\x1f\x7f-\x9f]', '')
    # Preserve existing placeholders; match original values once, longest first.
    # Never rescan a replacement (a known value may itself be 'maskiert').
    $patterns = @($State.secrets | Where-Object { $_ } | Sort-Object Length -Descending | ForEach-Object { [regex]::Escape([string]$_) })
    if ($patterns.Count) {
        $parts = [regex]::Split($Text, '(\[maskiert\])')
        $Text = (@(foreach ($part in $parts) {
            if ($part -ceq '[maskiert]') { $part }
            else { [regex]::Replace($part, ($patterns -join '|'), '[maskiert]') }
        }) -join '')
    }
    $Text = [regex]::Replace($Text, '(?i)\b(?:sk-[a-z0-9_-]+|gh[pousr]_[a-z0-9_]+|github_pat_[a-z0-9_]+|eyJ[a-z0-9_-]+\.[a-z0-9_-]+\.[a-z0-9_-]+)\b', '[maskiert]')
    # Values, not entire commands/prose. Include quoted values containing spaces.
    $Text = [regex]::Replace($Text, '(?i)\bBearer\s+[^\s"'';,]+', 'Bearer [maskiert]')
    $Text = [regex]::Replace($Text, '(?i)((?:\b["'']?(?:access[_-]?token|refresh[_-]?token|client[_-]?secret|connection[_-]?string|token|password|passwd|secret|api[_-]?key|authorization)["'']?)\s*[:=]\s*|--(?:token|password|passwd|secret|api[_-]?key|authorization)\s+)("(?:\\.|[^"\\])*"|''(?:''''|[^''])*''|\[maskiert\]|[^\s,;&}\]]+)', '$1"[maskiert]"')
    $Text = [regex]::Replace($Text, '(?i)(https?://)[^\s/@]+:[^\s/@]+@', '$1[maskiert]@')
    if ($Text.Length -gt $Limit) { $Text = $Text.Substring(0, $Limit - 3) + '...' }
    return $Text
}
function Format-DelegatedStartLayout([string]$RoleName, [string]$Task, [string]$Context, [int]$Width = 88, $State = @{ secrets = @() }) {
    $Width = [Math]::Max(40, [Math]::Min(120, $Width))
    $lines = New-Object 'System.Collections.Generic.List[string]'
    $lines.Add(('=' * $Width))
    $lines.Add('')
    $lines.Add((Protect-ProgressText $RoleName $State 200).ToUpperInvariant())
    $lines.Add('')
    foreach ($section in @(@{ name = 'AUFTRAG'; text = $Task }, @{ name = 'KONTEXT'; text = $Context })) {
        if ($section.name -eq 'KONTEXT' -and [string]::IsNullOrWhiteSpace($section.text)) { continue }
        $lines.Add(('-' * $Width))
        $lines.Add($section.name)
        $lines.Add('')
        foreach ($paragraph in ([string]$section.text -split '\r?\n')) {
            $text = Protect-ProgressText $paragraph $State ([int]::MaxValue)
            while ($text.Length -gt $Width) {
                $split = $text.LastIndexOf(' ', $Width)
                if ($split -le 0) { $split = $Width }
                $lines.Add($text.Substring(0, $split))
                $text = $text.Substring($split).TrimStart()
            }
            $lines.Add($text)
        }
        $lines.Add('')
    }
    $lines.Add(('=' * $Width))
    $lines.Add('')
    $lines.Add('FORTSCHRITT')
    $lines.Add('')
    return $lines.ToArray()
}
function Get-ProgressName([string]$Name, $State) {
    if ($Name) { return Protect-ProgressText $Name $State }
}
function Get-ProgressCommand([string]$Command, $State) {
    if ([string]::IsNullOrWhiteSpace($Command)) { return }
    $safe = Protect-ProgressText $Command $State
    # Presentation only: never evaluate, unescape or decode shell code. Anchor the
    # known PowerShell wrapper and require -Command to consume the remaining text.
    $wrapper = [regex]::Match($safe, '(?is)^\s*(?:"[^"\r\n]*[\\/])?(?:powershell|pwsh)(?:\.exe)?"?\s+(?:(?:-NoProfile|-NonInteractive|-NoLogo)\s+|-ExecutionPolicy\s+\w+\s+)*-Command\s+(?<inline>.+)$')
    if ($wrapper.Success) {
        $inline = $wrapper.Groups['inline'].Value.Trim()
        if (($inline.StartsWith('"') -and $inline.EndsWith('"')) -or ($inline.StartsWith("'") -and $inline.EndsWith("'"))) { $inline = $inline.Substring(1, $inline.Length - 2) }
        return "PowerShell-Inline:`n$inline`nVollständiger Befehl:`n$safe"
    }
    return $safe
}
function Get-ProgressPath([string]$Path, $State) {
    if ($Path) { return Protect-ProgressText $Path $State }
}
function ConvertTo-ProgressPayload($Value, $State) {
    if ($null -eq $Value) { return }
    # Public tool arguments/results can be structured. Redact secret fields before
    # serialization as well as recognizable values in the resulting text.
    function Protect-Value($v) {
        if ($null -eq $v) { return $null }
        if ($v -is [string]) { return Protect-ProgressText $v $State }
        if ($v -is [ValueType]) { return $v }
        if ($v -is [System.Collections.IDictionary] -or $v -is [pscustomobject]) {
            $copy = [ordered]@{}
            $keys = if ($v -is [System.Collections.IDictionary]) { @($v.Keys) } else { @($v.PSObject.Properties.Name) }
            foreach ($key in $keys) {
                $safeKey = Protect-ProgressText ([string]$key) $State
                # Keep distinct fields even when masking collapses their names.
                $baseKey = $safeKey; $suffix = 2
                while ($copy.Contains($safeKey)) { $safeKey = $baseKey + ' (' + $suffix + ')'; $suffix++ }
                if ($key -match '^(?i:access[_-]?token|refresh[_-]?token|client[_-]?secret|connection[_-]?string|token|password|passwd|secret|api[_-]?key|authorization)$') { $copy[$safeKey] = '[maskiert]' }
                else { $copy[$safeKey] = Protect-Value $v.$key }
            }
            return $copy
        }
        return ,@(foreach ($part in $v) { Protect-Value $part })
    }
    $text = if ($Value -is [string]) { $Value } else { Protect-Value $Value | ConvertTo-Json -Depth 40 }
    return Protect-ProgressText $text $State
}
function Get-ProgressContent($Content, $State) {
    foreach ($part in $Content) {
        # Deliberately select public text, never binary images/audio or _meta.
        if ($part.type -in @('text','inputText','input_text') -and $null -ne $part.text) { Protect-ProgressText ([string]$part.text) $State }
    }
}
function Get-PublicProgress($Message, [string]$ThreadId, [string]$TurnId, $State) {
    $p = $Message.params
    if (-not $ThreadId -or -not $TurnId -or $p.threadId -cne $ThreadId) { return }
    $eventTurn = if ($Message.method -in @('turn/started', 'turn/completed')) { $p.turn.id } else { $p.turnId }
    if ($eventTurn -cne $TurnId) { return }
    $item = $p.item
    $lines = @()
    $key = $null
    if ($Message.method -in @('turn/started', 'turn/completed')) {
        $key = $Message.method
        if ($Message.method -eq 'turn/started') { $lines = @('Bearbeitung gestartet.') }
        else {
            $status = if ($p.turn.status -in @('completed','failed','interrupted')) { ": $($p.turn.status)" } else { '' }
            $lines = @("Bearbeitung beendet$status; Tokenabrechnung wird gesichert.")
        }
    } elseif ($Message.method -in @('item/started', 'item/completed')) {
        if ($item.type -in @('reasoning','userMessage','hookPrompt','plan')) { return }
        if ($item.id) { $key = $Message.method + ':' + [string]$item.id }
        $status = if ($item.status -in @('inProgress','completed','failed','declined','interrupted')) { "; Status $($item.status)" } else { '' }
        $stage = if ($Message.method -eq 'item/started') { 'Start' } else { 'Ende' }
        switch ($item.type) {
            'agentMessage' {
                # Final answers use the same ID-bound display path, not raw output.
                if ($Message.method -ne 'item/completed' -or $item.phase -notin @('commentary','final_answer')) { return }
                $text = [string]$item.text
                if (-not $text.Trim()) { return }
                $label = if ($item.phase -eq 'commentary') { 'Fortschritt: ' } else { "Ergebnis (vollständig, maskiert):`n" }
                $lines = @($label + (Protect-ProgressText $text $State))
            }
            'functionCallOutput' {
                if (-not $item.name) { return }
                $name = Get-ProgressName $item.name $State
                if ($item.namespace) { $name = (Get-ProgressName $item.namespace $State) + '/' + $name }
                $lines = @("Funktionsausgabe ${stage}: $name")
                if ($stage -eq 'Ende' -and $null -ne $item.output) {
                    $outputText = if ($item.output -is [string]) { Protect-ProgressText $item.output $State }
                        else { @(Get-ProgressContent $item.output $State) -join "`n" }
                    if ($outputText) { $lines += "Ausgabe:`n" + $outputText }
                }
            }
            'sleep' {
                $lines = @("Pause ${stage}")
                if ($null -ne $item.durationMs) { $lines += "Dauer (ms): $($item.durationMs)" }
            }
            'commandExecution' {
                $exit = if ($stage -eq 'Ende' -and $null -ne $item.exitCode -and [string]$item.exitCode -match '^-?\d{1,10}$') { "; Exitcode $($item.exitCode)" } else { '' }
                $lines = @("Befehl ${stage}$status$exit")
                if ($item.cwd) { $lines += 'Arbeitsverzeichnis: ' + (Get-ProgressPath $item.cwd $State) }
                if ($item.command) { $lines += Get-ProgressCommand $item.command $State }
                if ($stage -eq 'Ende' -and $null -ne $item.aggregatedOutput -and [string]$item.aggregatedOutput -ne '') { $lines += "Ausgabe:`n" + [string]$item.aggregatedOutput }
            }
            'fileChange' {
                $lines = @("Dateien ${stage}$status")
                foreach ($change in $item.changes) {
                    if ($change.path) { $lines += 'Pfad: ' + (Get-ProgressPath $change.path $State) }
                    if ($change.kind.type -in @('add','delete','update')) { $lines += 'Änderung: ' + $change.kind.type }
                    if ($stage -eq 'Ende' -and $change.diff) { $lines += "Diff:`n" + [string]$change.diff }
                }
            }
            'mcpToolCall' {
                if (-not $item.tool -or -not $item.server) { return }
                $lines = @("MCP ${stage}: $(Get-ProgressName $item.server $State)/$(Get-ProgressName $item.tool $State)$status")
                if ($null -ne $item.arguments) { $lines += "Argumente:`n" + (ConvertTo-ProgressPayload $item.arguments $State) }
                if ($stage -eq 'Ende') {
                    $content = @(Get-ProgressContent $item.result.content $State)
                    if ($content.Count) { $lines += "Ergebnis:`n" + ($content -join "`n") }
                    if ($null -ne $item.result.structuredContent) { $lines += "Strukturiertes Ergebnis:`n" + (ConvertTo-ProgressPayload $item.result.structuredContent $State) }
                    if ($item.error.message) { $lines += 'Fehler: ' + [string]$item.error.message }
                }
            }
            'dynamicToolCall' {
                if (-not $item.tool) { return }
                $success = if ($item.success -is [bool]) { "; Erfolg $($item.success)" } else { '' }
                $name = Get-ProgressName $item.tool $State
                if ($item.namespace) { $name = (Get-ProgressName $item.namespace $State) + '/' + $name }
                $lines = @("Tool ${stage}: $name$status$success")
                if ($null -ne $item.arguments) { $lines += "Argumente:`n" + (ConvertTo-ProgressPayload $item.arguments $State) }
                if ($stage -eq 'Ende') {
                    $content = @(Get-ProgressContent $item.contentItems $State)
                    if ($content.Count) { $lines += "Ergebnis:`n" + ($content -join "`n") }
                }
            }
            'webSearch' {
                $lines = @("Werkzeug ${stage}: webSearch")
                if ($item.query) { $lines += 'Suche: ' + [string]$item.query }
                if ($item.action.type -in @('search','open_page','find_in_page','openPage','findInPage')) {
                    $lines += 'Aktion: ' + [string]$item.action.type
                    foreach ($field in @('query','queries','url','pattern')) {
                        if ($item.action.$field) { $lines += "${field}: " + (@($item.action.$field) -join "`n") }
                    }
                }
                if ($stage -eq 'Ende' -and $null -ne $item.results) { $lines += "Ergebnis:`n" + (ConvertTo-ProgressPayload $item.results $State) }
            }
            'imageView' {
                $lines = @("Werkzeug ${stage}: imageView")
                if ($item.path) { $lines += 'Pfad: ' + (Get-ProgressPath $item.path $State) }
            }
            { $_ -in @('collabAgentToolCall','collabToolCall') } {
                if (-not $item.tool) { return }
                $lines = @("Werkzeug ${stage}: $(Get-ProgressName $item.tool $State)$status")
                # Only identities and reported status, never prompt/developer payloads.
                if ($item.receiverThreadIds) { $lines += 'Zielthreads: ' + (@($item.receiverThreadIds) -join ', ') }
                if ($item.receiverThreadId) { $lines += 'Zielthread: ' + [string]$item.receiverThreadId }
            }
            default { return } # Unmapped/internal items remain in the technical notification log.
        }
    } else { return } # v2 authoritative items only: no legacy codex/event/* duplicates or deltas.
    if ($key -and $State.seen.ContainsKey($key)) { return }
    if ($key) { $State.seen[$key] = $true }; $State.count++
    if ($lines.Count) { Protect-ProgressText ($lines -join "`n") $State }
}
function Format-ProgressLines([string]$Text, [int]$Width = 88) {
    $Width = [Math]::Max(40, [Math]::Min(120, $Width))
    foreach ($paragraph in ($Text -split "`n")) {
        while ($paragraph.Length -gt $Width) {
            # Include the whitespace at the boundary: joining wrapped lines must
            # preserve even long commands/paths byte-for-byte after sanitization.
            $split = $paragraph.LastIndexOf(' ', $Width - 1)
            if ($split -le 0) { $split = $Width } else { $split++ }
            $paragraph.Substring(0, $split)
            $paragraph = $paragraph.Substring($split)
        }
        $paragraph
    }
}
function Write-ProgressDisplay([string]$Text) {
    # One path for actual host lines and their sanitized evidence, including final output.
    $safe = Protect-ProgressText $Text $progressState
    [System.IO.File]::AppendAllText($resultFile + '.public.txt', $safe + "`n`n", $utf8)
    $width = 88
    try { $width = [Math]::Min(88, $host.UI.RawUI.WindowSize.Width - 1) } catch { }
    foreach ($line in (Format-ProgressLines $safe $width)) {
        Write-Host $line
        Write-Event 'display' @{ text = $line; thread_id = $evidence.thread_id; turn_id = $evidence.turn_id }
    }
    Write-Host ''
    Write-Event 'display' @{ text = ''; thread_id = $evidence.thread_id; turn_id = $evidence.turn_id }
}
if ($PSCmdlet.ParameterSetName -eq 'Start') {
    # A coordinator console is user-owned: it is never automatically closed.
    if ($Role -ceq 'koordinator') { $KeepWindowOpen = $true }
    $resultFile = [System.IO.Path]::GetFullPath($ResultPath)
    foreach ($suffix in @('', '.job.json', '.window.json', '.go.json', '.events.jsonl', '.public.txt')) {
        if (Test-Path -LiteralPath ($resultFile + $suffix)) { throw "Vorhandenes Artefakt bleibt erhalten: $resultFile$suffix" }
    }
    $workdir = (Resolve-Path -LiteralPath $WorkingDirectory).Path
    if (-not (Test-Path -LiteralPath $workdir -PathType Container)) { throw 'WorkingDirectory ist kein Verzeichnis.' }
    New-Item -ItemType Directory -Path (Split-Path -Parent $resultFile) -Force | Out-Null
    $agentHome = if ($env:CODEX_HOME) { $env:CODEX_HOME } else { Join-Path $env:USERPROFILE '.codex' }
    if (-not $RoleDisplayName) {
        $RoleDisplayName = $Role
        if ($Role -eq 'koordinator') { $RoleDisplayName = 'Koordinator' }
        elseif ($Role.StartsWith('teamleiter_')) {
            $team = ([IO.File]::ReadAllText((Join-Path $agentHome 'agents\koordinator\teams.json'), $utf8) | ConvertFrom-Json).teams | Where-Object { $_.leader_id -ceq $Role }
            if (@($team).Count -eq 1) { $RoleDisplayName = 'Teamleiter ' + $team.name }
        } else {
            $ownTeam = Get-ChildItem -LiteralPath (Join-Path $agentHome 'agents') -Directory | Where-Object { $Role.StartsWith($_.Name + '_') } | Sort-Object { $_.Name.Length } -Descending | Select-Object -First 1
            if ($ownTeam -and (Test-Path -LiteralPath (Join-Path $ownTeam.FullName 'agenten.json'))) {
                $entry = ([IO.File]::ReadAllText((Join-Path $ownTeam.FullName 'agenten.json'), $utf8) | ConvertFrom-Json).agents | Where-Object { $_.agent_id -ceq $Role }
                if (@($entry).Count -eq 1) { $RoleDisplayName = $entry.name }
            }
        }
    }
    if (-not $TaskTitle) {
        $words = @($Task -split '\s+' | Where-Object { $_ })
        $TaskTitle = if ($words.Count -ge 3) { $words[0..2] -join ' ' } else { 'Auftrag jetzt bearbeiten' }
    }
    $roleText = [System.IO.File]::ReadAllText((Join-Path $agentHome ('agents\' + $Role + '.toml')), $utf8)
    if ((Read-RoleString $roleText 'name') -ne $Role) { throw 'Rollenname passt nicht zur Datei.' }
    $instructions = [regex]::Match($roleText, "(?s)developer_instructions\s*=\s*'''(.*?)'''")
    $agents = [regex]::Match($roleText, '(?s)\[agents\]\s*enabled\s*=\s*(true|false)')
    if (-not $instructions.Success -or -not $agents.Success) { throw 'Rollenstruktur wird nicht unterstützt.' }
    $config = @{ agents = @{ enabled = ($agents.Groups[1].Value -eq 'true') } }
    foreach ($key in @('model_reasoning_effort', 'model_verbosity', 'web_search')) { $config[$key] = Read-RoleString $roleText $key }
    $context = if ($ContextFile) { [System.IO.File]::ReadAllText((Resolve-Path -LiteralPath $ContextFile).Path, $utf8) } else { '' }
    if (-not $PSBoundParameters.ContainsKey('ParentTaskId')) { $ParentTaskId = $env:AGENT_ORG_PARENT_TASK_ID }
    if ($ParentTaskId) { $ParentTaskId = ([guid]$ParentTaskId).ToString('N') }
    if (-not $PSBoundParameters.ContainsKey('AccountingDirectory')) { $AccountingDirectory = $env:AGENT_ORG_ACCOUNTING_DIRECTORY }
    if (-not $AccountingDirectory) { $AccountingDirectory = Join-Path (Split-Path -Parent $resultFile) 'token-accounting' }
    $AccountingDirectory = [System.IO.Path]::GetFullPath($AccountingDirectory)
    New-Item -ItemType Directory -Path $AccountingDirectory -Force | Out-Null
    $spec = @{
        task_id = [guid]::NewGuid().ToString('N'); role = $Role; task = $Task; context = $context
        role_display_name = $RoleDisplayName; task_title = $TaskTitle; window_title = $(if ($Role -ceq 'koordinator') { 'Koordinator' } else { $RoleDisplayName + ' - ' + $TaskTitle })
        context_file = $(if ($ContextFile) { (Resolve-Path -LiteralPath $ContextFile).Path } else { $null })
        parent_task_id = $(if ($ParentTaskId) { $ParentTaskId } else { $null }); accounting_directory = $AccountingDirectory
        cwd = $workdir; result_file = $resultFile; timeout_seconds = $TimeoutSeconds; keep_window_open = [bool]$KeepWindowOpen
        developer_instructions = ('Explizit zugewiesene Rolle: ' + $Role + ".`n" + $instructions.Groups[1].Value); config = $config
        model = (Read-RoleString $roleText 'model'); sandbox = (Read-RoleString $roleText 'sandbox_mode')
        approval_policy = (Read-RoleString $roleText 'approval_policy')
    }
    $jobPath = $resultFile + '.job.json'
    Write-Json $jobPath $spec
    $protected = @(Get-Process -Name ChatGPT,powershell,conhost,WindowsTerminal -ErrorAction SilentlyContinue | ForEach-Object { [AgentTerminalWindow]::ForPid([uint32]$_.Id) } | Select-Object -Unique)
    # Explicit console host avoids Windows Terminal's non-owning pseudohandle.
    $runner = Start-Process -FilePath (Join-Path $env:WINDIR 'System32\conhost.exe') -ArgumentList @(
        ('"' + (Get-Command powershell.exe).Source + '"'),
        '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', ('"' + $PSCommandPath + '"'), '-JobFile', ('"' + $jobPath + '"')
    ) -WorkingDirectory $workdir -WindowStyle Normal -PassThru
    $windowPath = $resultFile + '.window.json'
    $gateDeadline = [DateTime]::UtcNow.AddSeconds(15)
    while (-not (Test-Path -LiteralPath $windowPath) -and -not $runner.HasExited -and [DateTime]::UtcNow -lt $gateDeadline) { Start-Sleep -Milliseconds 100 }
    $confirmed = $false
    $window = $null
    if (Test-Path -LiteralPath $windowPath) {
        $window = [System.IO.File]::ReadAllText($windowPath, $utf8) | ConvertFrom-Json
        $hostDeadline = [DateTime]::UtcNow.AddSeconds(5)
        do {
            $candidates = @(Get-Process -Name powershell,conhost,WindowsTerminal -ErrorAction SilentlyContinue | ForEach-Object {
                [AgentTerminalWindow]::ForPid([uint32]$_.Id)
            } | Select-Object -Unique | Where-Object {
                $protected -notcontains $_ -and [AgentTerminalWindow]::IsWindowVisible([IntPtr]$_) -and [AgentTerminalWindow]::Title([IntPtr]$_) -eq $window.title
            })
            if ($candidates.Count -ne 1) { Start-Sleep -Milliseconds 100 }
        } while ($candidates.Count -ne 1 -and [DateTime]::UtcNow -lt $hostDeadline)
        $child = Get-CimInstance Win32_Process -Filter ('ProcessId=' + [int]$window.runner_pid)
        $actualOwner = [uint32]0
        if ($candidates.Count -eq 1) { [void][AgentTerminalWindow]::GetWindowThreadProcessId([IntPtr][long]$candidates[0], [ref]$actualOwner) }
        $confirmed = $child -and (Test-ConsoleBinding $window $runner.Id $child.ParentProcessId $candidates $actualOwner $spec.task_id $spec.window_title)
        if ($confirmed) {
            $handle = [IntPtr][long]$candidates[0]
            $window.window_handle = $handle.ToInt64()
            if (-not [AgentTerminalWindow]::SetProp($handle, ('AgentOrganizationTask.' + $spec.task_id), [IntPtr][int]$window.runner_pid)) { throw 'Eigene Fenstermarkierung fehlgeschlagen; kein ACK oder Modellstart.' }
            if ($Role -ceq 'koordinator') { $protected = @($protected) + $handle.ToInt64() }
            Write-Json ($resultFile + '.go.json') @{ task_id = $spec.task_id; runner_pid = $window.runner_pid; launcher_pid = $runner.Id; window_handle = $handle.ToInt64(); visible = $true; title = $window.title; confirmed_at = [DateTime]::UtcNow.ToString('o'); console_binding_verified = $true }
            Write-Output ('Fenster bestätigt: PID ' + $window.runner_pid + ', HWND ' + $handle.ToInt64() + ', ' + $window.title)
        }
    }
    $deadline = [DateTime]::UtcNow.AddSeconds($TimeoutSeconds + 25)
    while (-not (Test-Path -LiteralPath $resultFile) -and -not $runner.HasExited -and [DateTime]::UtcNow -lt $deadline) { Start-Sleep -Milliseconds 200 }
    if (-not (Test-Path -LiteralPath $resultFile)) { throw 'Runner ohne gesichertes Resultat; kein Erfolg und kein pauschales Beenden anderer Prozesse.' }
    $result = [System.IO.File]::ReadAllText($resultFile, $utf8) | ConvertFrom-Json
    if (-not $KeepWindowOpen) { [void]$runner.WaitForExit(5000) }
    if ($Role -cne 'koordinator' -and -not $KeepWindowOpen -and $confirmed -and $runner.HasExited -and [AgentTerminalWindow]::IsWindow($handle) -and [AgentTerminalWindow]::Title($handle) -eq $window.title -and [AgentTerminalWindow]::GetProp($handle, ('AgentOrganizationTask.' + $spec.task_id)) -eq [IntPtr][int]$window.runner_pid) {
        [void][AgentTerminalWindow]::PostMessage($handle, 0x0010, [IntPtr]::Zero, [IntPtr]::Zero)
        $closeDeadline = [DateTime]::UtcNow.AddSeconds(3)
        while ([AgentTerminalWindow]::IsWindow($handle) -and [DateTime]::UtcNow -lt $closeDeadline) { Start-Sleep -Milliseconds 100 }
    }
    $result | Add-Member -NotePropertyName window_closed -NotePropertyValue ($window -and -not [AgentTerminalWindow]::IsWindow([IntPtr][long]$window.window_handle))
    $result | Add-Member -NotePropertyName protected_window_handles -NotePropertyValue $protected
    $result | Add-Member -NotePropertyName controller_visibility_confirmed -NotePropertyValue $confirmed
    $result | Add-Member -NotePropertyName console_binding_verified -NotePropertyValue $confirmed
    [System.IO.File]::WriteAllText($resultFile, ($result | ConvertTo-Json -Depth 10), $utf8)
    Write-Output ('Auftrag ' + $result.task_id + ': ' + $(if ($result.success) { 'abgeschlossen' } else { 'fehlgeschlagen' }))
    Write-Output ($(if ($result.usage_finalized) { 'Eigene Tokens: ' } else { 'Vorläufig beobachtete eigene Tokens: ' }) + (Format-TokenUsage $result.token_usage))
    if ($result.token_summary) {
        Write-Output ('Inklusive Unteraufträgen: ' + (Format-TokenUsage $result.token_summary.inclusive))
        if ($result.token_summary.missing_count) { Write-Output ('Bekannte Teilsumme: ' + (Format-TokenUsage $result.token_summary.known_partial) + '; unbekannte Aufgaben: ' + $result.token_summary.missing_count) }
    }
    Write-Output ('Vollständiges Resultat: ' + $resultFile)
    if (Test-Path -LiteralPath ($resultFile + '.public.txt')) { Write-Output ('Vollständige maskierte Darstellung: ' + $resultFile + '.public.txt') }
    if ($result.output) { Format-ProgressLines (Protect-ProgressText $result.output (New-ProgressState)) | Write-Output }
    if ($result.error) { Format-ProgressLines (Protect-ProgressText ('Fehler: ' + $result.error) (New-ProgressState)) | Write-Output }
    if (-not $result.success -or -not $confirmed) { exit 2 }
    exit 0
}

# Eigener sichtbarer Runner: Taskdaten stehen nicht in einer Shell-Kommandozeile.
$job = [System.IO.File]::ReadAllText((Resolve-Path -LiteralPath $JobFile).Path, $utf8) | ConvertFrom-Json
$resultFile = [string]$job.result_file
$title = $job.window_title
$host.UI.RawUI.WindowTitle = $title
$handle = [AgentTerminalWindow]::GetConsoleWindow()
$windowPid = [uint32]0
[void][AgentTerminalWindow]::GetWindowThreadProcessId($handle, [ref]$windowPid)
$startState = New-ProgressState
$layoutWidth = 88
try { $layoutWidth = [Math]::Min(88, $host.UI.RawUI.WindowSize.Width - 1) } catch { }
foreach ($line in (Format-DelegatedStartLayout $job.role_display_name $job.task $job.context $layoutWidth $startState)) { Write-Host $line }
Write-Host 'Arbeit beginnt nach bestätigtem Fenster und zehn Sekunden zum Mitlesen.'
$evidence = [ordered]@{
    task_id = $job.task_id; role = $job.role; runner_pid = $PID; window_handle = $handle.ToInt64(); title = $title
    model_started = $false; thread_id = $null; turn_id = $null; terminal_outcome = $null; output = $null; success = $false; error = $null
    parent_task_id = $job.parent_task_id; accounting_directory = $job.accounting_directory; token_usage = $null; token_summary = $null; usage_finalized = $false
}
$notifications = New-Object System.Collections.Generic.List[object]
$progressState = New-ProgressState
$process = $null
function Update-NativeUsage($Notification) {
    if ($Notification.method -eq 'thread/tokenUsage/updated' -and
        $evidence.thread_id -and $evidence.turn_id -and
        $Notification.params.threadId -ceq $evidence.thread_id -and $Notification.params.turnId -ceq $evidence.turn_id) {
        # Kumulativer Snapshot des eigenen frischen Threads, niemals Updates addieren.
        $evidence.token_usage = $Notification.params.tokenUsage.total
    }
}
function Write-Event([string]$Kind, $Data) {
    $line = @{ at = [DateTime]::UtcNow.ToString('o'); kind = $Kind; data = $Data } | ConvertTo-Json -Depth 30 -Compress
    [System.IO.File]::AppendAllText($resultFile + '.events.jsonl', $line + "`n", $utf8)
}
function Send-Rpc([string]$Method, $Params, [int]$Id) {
    $message = @{ method = $Method; params = $Params }
    if ($Id -gt 0) { $message.id = $Id }
    $bytes = $utf8.GetBytes(($message | ConvertTo-Json -Depth 20 -Compress) + "`n")
    $process.StandardInput.BaseStream.Write($bytes, 0, $bytes.Length)
    $process.StandardInput.BaseStream.Flush()
    Write-Event 'request' @{ method = $Method; id = $Id }
}
function Read-Rpc {
    $remaining = [int][Math]::Max(1, ($deadline - [DateTime]::UtcNow).TotalMilliseconds)
    $read = $process.StandardOutput.ReadLineAsync()
    if (-not $read.Wait($remaining)) { throw 'Timeout beim Warten auf App-server.' }
    if ($null -eq $read.Result) { throw 'App-server hat seinen Ausgabestrom geschlossen.' }
    $message = $read.Result | ConvertFrom-Json
    if ($message.error) { throw ('App-server-Fehler: ' + $message.error.message) }
    if ($message.method) {
        Write-Event 'notification' $message
        $notifications.Add($message)
        Update-NativeUsage $message
        if ($message.id) { throw ('Interaktive Serveranforderung: ' + $message.method) }
        Get-PublicProgress $message $evidence.thread_id $evidence.turn_id $progressState | ForEach-Object { Write-ProgressDisplay $_ }
    }
    return $message
}
function Wait-Rpc([int]$Id) { do { $message = Read-Rpc } while ($message.id -ne $Id); return $message.result }
try {
    if ($handle -eq [IntPtr]::Zero -or -not [AgentTerminalWindow]::IsWindowVisible($handle)) { throw 'Eigenes sichtbares Konsolenfenster nicht verfügbar; kein Modellstart.' }
    Write-Json ($resultFile + '.window.json') @{ task_id = $job.task_id; runner_pid = $PID; window_handle = $handle.ToInt64(); window_pid = $windowPid; title = $title }
    $gateDeadline = [DateTime]::UtcNow.AddSeconds(15)
    while (-not (Test-Path -LiteralPath ($resultFile + '.go.json')) -and [DateTime]::UtcNow -lt $gateDeadline) { Start-Sleep -Milliseconds 100 }
    if (-not (Test-Path -LiteralPath ($resultFile + '.go.json'))) { throw 'Fenster wurde nicht bestätigt; kein Modellstart.' }
    $ack = [System.IO.File]::ReadAllText($resultFile + '.go.json', $utf8) | ConvertFrom-Json
    if ($ack.task_id -ne $job.task_id -or $ack.runner_pid -ne $PID -or $ack.title -ne $title) { throw 'Ungültige Fensterbestätigung.' }
    $handle = [IntPtr][long]$ack.window_handle
    $evidence.window_handle = $handle.ToInt64()
    Start-Sleep -Seconds 10
    if (-not [AgentTerminalWindow]::IsWindowVisible($handle)) { throw 'Fenster vor Arbeitsbeginn nicht mehr sichtbar.' }
    if ([AgentTerminalWindow]::Title($handle) -ne $title) { throw 'Fenstertitel vor Arbeitsbeginn verändert; kein Modellstart.' }
    # Nur dieser Runner und seine eigenen Kindprozesse erhalten den Elternkontext.
    $env:AGENT_ORG_PARENT_TASK_ID = [string]$job.task_id
    $env:AGENT_ORG_ACCOUNTING_DIRECTORY = [string]$job.accounting_directory
    $deadline = [DateTime]::UtcNow.AddSeconds([int]$job.timeout_seconds)
    $command = Get-Command codex.cmd -ErrorAction Stop
    $start = New-Object System.Diagnostics.ProcessStartInfo
    $start.FileName = $env:ComSpec
    $start.Arguments = '/d /s /c ""' + $command.Source + '" app-server --stdio"'
    $start.WorkingDirectory = $job.cwd
    $start.UseShellExecute = $false; $start.CreateNoWindow = $true
    $start.RedirectStandardInput = $true; $start.RedirectStandardOutput = $true; $start.RedirectStandardError = $true
    $start.StandardOutputEncoding = $utf8
    $process = New-Object System.Diagnostics.Process
    $process.StartInfo = $start
    [void]$process.Start()
    $stderr = $process.StandardError.ReadToEndAsync()
    Send-Rpc 'initialize' @{ clientInfo = @{ name = 'agent_organization_terminal'; version = '0.1.0' } } 1
    [void](Wait-Rpc 1)
    Send-Rpc 'initialized' @{} 0
    Send-Rpc 'thread/start' @{ cwd = $job.cwd; model = $job.model; sandbox = $job.sandbox; approvalPolicy = $job.approval_policy; developerInstructions = $job.developer_instructions; config = $job.config } 2
    $thread = Wait-Rpc 2
    $evidence.thread_id = $thread.thread.id
    Write-Host 'Eigene Sitzung ist bereit.'
    Write-Event 'thread_created' @{ thread_id = $evidence.thread_id }
    $text = [string]$job.task
    if ($job.context) { $text += "`n`nBenötigter Auftragskontext:`n" + $job.context }
    Send-Rpc 'turn/start' @{ threadId = $evidence.thread_id; input = @(@{ type = 'text'; text = $text }) } 3
    $evidence.model_started = $true
    $turn = Wait-Rpc 3
    $evidence.turn_id = $turn.turn.id
    # turn/started and items can precede the turn/start response; replay once after binding.
    foreach ($notification in $notifications) {
        Update-NativeUsage $notification
        Get-PublicProgress $notification $evidence.thread_id $evidence.turn_id $progressState | ForEach-Object { Write-ProgressDisplay $_ }
    }
    $completion = $null
    while ($null -eq $completion) {
        $completion = $notifications | Where-Object { $_.method -eq 'turn/completed' -and $_.params.threadId -ceq $evidence.thread_id -and $_.params.turn.id -ceq $evidence.turn_id } | Select-Object -Last 1
        if ($null -eq $completion) { [void](Read-Rpc) }
    }
    $evidence.terminal_outcome = $completion.params.turn.status
    $evidence.output = ($notifications | Where-Object { $_.method -eq 'item/completed' -and $_.params.threadId -ceq $evidence.thread_id -and $_.params.turnId -ceq $evidence.turn_id -and $_.params.item.type -eq 'agentMessage' } | ForEach-Object { [string]$_.params.item.text }) -join "`n"
    # Unterstützter Roundtrip: auch nach turn/completed noch eintreffende Usage lesen.
    $deadline = [DateTime]::UtcNow.AddSeconds(10)
    Send-Rpc 'thread/read' @{ threadId = $evidence.thread_id; includeTurns = $false } 5
    [void](Wait-Rpc 5)
    $evidence.usage_finalized = $true
    $evidence.output = ($notifications | Where-Object { $_.method -eq 'item/completed' -and $_.params.threadId -ceq $evidence.thread_id -and $_.params.turnId -ceq $evidence.turn_id -and $_.params.item.type -eq 'agentMessage' } | ForEach-Object { [string]$_.params.item.text }) -join "`n"
    $evidence.success = ($evidence.terminal_outcome -eq 'completed')
    Write-Event 'terminal' @{ outcome = $evidence.terminal_outcome; thread_id = $evidence.thread_id }
    # Public final_answer items were displayed once above. Keep raw output in
    # the result contract without replaying commentary or unknown phases here.
} catch {
    $evidence.error = $_.Exception.Message
    Write-ProgressDisplay ('Fehler: ' + $evidence.error)
    if ($process -and $evidence.turn_id -and -not $evidence.terminal_outcome) {
        try { Send-Rpc 'turn/interrupt' @{ threadId = $evidence.thread_id; turnId = $evidence.turn_id } 4 } catch { }
    }
} finally {
    try {
    try {
        Write-Json (Join-Path $job.accounting_directory ($job.task_id + '.usage.json')) ([ordered]@{
            task_id = $job.task_id; parent_task_id = $job.parent_task_id; role = $job.role
            thread_id = $evidence.thread_id; turn_id = $evidence.turn_id; token_usage = (Get-FinalLedgerUsage $evidence)
        })
        $evidence.token_summary = & (Join-Path $PSScriptRoot '../accounting/Get-TaskTokenUsage.ps1') -TaskId $job.task_id -AccountingDirectory $job.accounting_directory
    } catch {
        $evidence.success = $false
        $ledgerError = 'Tokenabrechnung konnte nicht gesichert oder ausgewertet werden: ' + $_.Exception.Message
        $evidence.error = $(if ($evidence.error) { $evidence.error + '; ' + $ledgerError } else { $ledgerError })
    }
    Write-Json $resultFile $evidence
    if ($process) {
        try { $process.StandardInput.Close() } catch { }
        [void]$process.WaitForExit(3000)
        $process.Dispose()
    }
    Write-Host ('Resultat gesichert: ' + $resultFile)
    if (Test-Path -LiteralPath ($resultFile + '.public.txt')) { Write-Host ('Vollständige maskierte Darstellung: ' + $resultFile + '.public.txt') }
    Write-Host ($(if ($evidence.usage_finalized) { 'Eigene Tokens: ' } else { 'Vorläufig beobachtete eigene Tokens: ' }) + (Format-TokenUsage $evidence.token_usage))
    if ($evidence.token_summary) {
        Write-Host ('Inklusive Unteraufträgen: ' + (Format-TokenUsage $evidence.token_summary.inclusive))
        if ($evidence.token_summary.missing_count) { Write-Host ('Bekannte Teilsumme: ' + (Format-TokenUsage $evidence.token_summary.known_partial) + '; unbekannte Aufgaben: ' + $evidence.token_summary.missing_count) }
    }
    } finally {
        if ($job.role -ceq 'koordinator') { [void](Read-Host 'Koordinator-Konsole bleibt offen. Nur auf Benutzerwunsch mit Enter schließen') }
        elseif ($job.keep_window_open) { [void](Read-Host 'Zum Schließen Enter drücken') }
        else { Start-Sleep -Seconds 2 }
    }
}
if (-not $evidence.success) { exit 2 }
