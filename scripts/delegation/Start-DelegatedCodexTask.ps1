[CmdletBinding(DefaultParameterSetName = 'Start')]
param(
    [Parameter(ParameterSetName = 'Start')][ValidatePattern('^[a-z][a-z0-9_]*$')][string]$Role,
    [Parameter(ParameterSetName = 'Start')][string]$Task,
    [Parameter(ParameterSetName = 'Start')][string]$ExecutionId,
    [Parameter(ParameterSetName = 'Start')][string]$WorkItemStorePath,
    [Parameter(ParameterSetName = 'Start')][string]$WorkItemRequestPath,
    [Parameter(ParameterSetName = 'Start')][string]$ParentContextPath,
    [Parameter(ParameterSetName = 'Start')][string]$ParentContextHash,
    [Parameter(ParameterSetName = 'Start')][string]$ParentJobPath,
    [Parameter(ParameterSetName = 'Start')][string]$StartIntentPath,
    [Parameter(ParameterSetName = 'Start')][string]$StartIntentHash,
    [Parameter(ParameterSetName = 'Start')][string]$AdmissionReservationJson,
    [Parameter(ParameterSetName = 'Start')][string]$CoordinatorLaunchConfigPath,
    [Parameter(ParameterSetName = 'Start')][string]$ResumeAssessment,
    [Parameter(ParameterSetName = 'Start')][ValidateScript({ ($_ -split '\s+' | Where-Object { $_ }).Count -eq 3 -and $_ -notmatch '[\r\n]' })][string]$TaskTitle,
    [Parameter(ParameterSetName = 'Start')][ValidateScript({ $_ -notmatch '[\r\n]' })][string]$RoleDisplayName,
    [Parameter(ParameterSetName = 'Start')][string]$ContextFile,
    [Parameter(Mandatory = $true, ParameterSetName = 'Start')][string]$WorkingDirectory,
    [Parameter(Mandatory = $true, ParameterSetName = 'Start')][string]$ResultPath,
    [Parameter(ParameterSetName = 'Start')][ValidateRange(5, 3600)][int]$TimeoutSeconds = 120,
    [Parameter(ParameterSetName = 'Start')][switch]$KeepWindowOpen,
    [Parameter(ParameterSetName = 'Start')][string]$ParentTaskId,
    [Parameter(ParameterSetName = 'Start')][string]$AccountingDirectory,
    [Parameter(ParameterSetName = 'Start')][string]$CoordinatorDataDirectory,
    [Parameter(ParameterSetName = 'Start')][string]$StableTaskId,
    [Parameter(ParameterSetName = 'Start')][string]$DispatchId,
    [Parameter(ParameterSetName = 'Start')][string]$WorkItemId,
    [Parameter(ParameterSetName = 'Start')][string]$Purpose,
    [Parameter(ParameterSetName = 'Start')][ValidateRange(1,2147483647)][int]$Generation,
    [Parameter(ParameterSetName = 'Start')][string]$DispatchJournalPath,
    [Parameter(ParameterSetName = 'Start')][switch]$DetachedAfterVisibleAck,
    [Parameter(ParameterSetName = 'Start')][ValidateRange(1,100)][int]$AdmissionCapacity = 4,
    [Parameter(Mandatory = $true, ParameterSetName = 'Runner')][string]$JobFile
)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '..\coordinator\Lifecycle.Persistence.ps1')
Import-Module (Join-Path $PSScriptRoot '..\coordinator\CoordinatorAdmission.psm1') -Force
$RepositoryRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
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
    $temporary = $Path + '.' + [guid]::NewGuid().ToString('N') + '.writing'
    [System.IO.File]::WriteAllText($temporary, ($Value | ConvertTo-Json -Depth 30), $utf8)
    if ([IO.File]::Exists($Path)) {
        try {
            [IO.File]::Replace($temporary, $Path, [System.Management.Automation.Language.NullString]::Value)
        }
        catch {
            $replaceError = $_
            $replaceInvocation = $replaceError.InvocationInfo
            Write-Host ('File.Replace Fehlerposition: Skript={0}; Zeile={1}; Spalte={2}' -f $replaceInvocation.ScriptName, $replaceInvocation.ScriptLineNumber, $replaceInvocation.OffsetInLine)
            if ($replaceError.ScriptStackTrace) {
                Write-Host 'File.Replace ScriptStackTrace:'
                Write-Host $replaceError.ScriptStackTrace
            }
            throw
        }
    } else {
        [IO.File]::Move($temporary, $Path)
    }
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
# H5: technical terminality is separate from SSOT transfer and acceptance.
function Invoke-BoundNoSpawnRecovery($BoundJob,[string]$Reason) {
    $rm=Import-Module (Join-Path $PSScriptRoot '..\workitems\WorkItemPrestartRecovery.psm1') -PassThru -Force
    $parameters=& $rm {param($j,$repo,$why)Get-PrestartSaveParameters $j $repo $why} $BoundJob $RepositoryRoot $Reason
    & (Join-Path $RepositoryRoot 'scripts\workitems\Save-WorkItemPrestartFailure.ps1') @parameters
}
function Complete-BoundRegistryJob($BoundJob) {
    if (-not [IO.File]::Exists([string]$BoundJob.result_file)) { throw 'Bound result missing; reservation retained.' }
    $terminal = [IO.File]::ReadAllText($BoundJob.result_file,$utf8) | ConvertFrom-Json
    if ($terminal.task_id -cne $BoundJob.task_id -or ($terminal.dispatch_id -and $terminal.dispatch_id -cne $BoundJob.dispatch_id) -or $terminal.terminal_outcome -notin @('completed','failed','interrupted')) { throw 'Bound terminal identity missing; reservation retained.' }
    if($terminal.model_started -eq $false){
        Invoke-BoundNoSpawnRecovery $BoundJob ([string]$terminal.error)|Out-Null
        return
    }
    if ($BoundJob.dispatch_journal_path) {
        $dm = Import-Module (Join-Path $PSScriptRoot '..\coordinator\CoordinatorDispatch.psm1') -PassThru -Force
        $entry = & $dm { param($j,$id) Get-CoordinatorDispatch -JournalPath $j -ExecutionId $id } $BoundJob.dispatch_journal_path $BoundJob.dispatch_id
        if (-not $entry -or ([guid]$entry.taskId).ToString('N') -cne $BoundJob.task_id -or ([guid]$entry.executionId).ToString('D') -cne $BoundJob.dispatch_id -or [IO.Path]::GetFullPath($entry.input.resultPath) -cne [IO.Path]::GetFullPath($BoundJob.result_file) -or $entry.input.payloadHash -cne $BoundJob.payload_hash) { throw 'Dispatch/job binding mismatch; reservation retained.' }
        if ($entry.state -in @('Running','RecoveryRequired') -and $entry.runningAtUtc -and $entry.launchBinding) {
            $launch = $entry.launchBinding | ConvertFrom-Json
            if ($launch.taskId -cne $terminal.task_id -or $launch.runnerPid -ne $terminal.runner_pid -or $launch.windowHandle -ne $terminal.window_handle -or $launch.title -cne $terminal.title) { throw 'Terminal launch binding mismatch; reservation retained.' }
            [void](& $dm { param($j,$id,$decision,$result) Set-CoordinatorDispatchState -JournalPath $j -ExecutionId $id -State Returned -TerminalDecision $decision -ReturnValue $result } $BoundJob.dispatch_journal_path $BoundJob.dispatch_id ([ordered]@{terminalOutcome=$terminal.terminal_outcome;success=$terminal.success}) $terminal)
        } elseif ($entry.state -ne 'Returned') {
            if ($entry.state -in @('Prepared','LaunchIntent','Running')) { [void](& $dm { param($j,$id) Set-CoordinatorDispatchState -JournalPath $j -ExecutionId $id -State RecoveryRequired } $BoundJob.dispatch_journal_path $BoundJob.dispatch_id) }
            throw 'DispatchRecoveryRequired; no proven Running-to-terminal binding.'
        }
    }
    [void](& (Join-Path $PSScriptRoot '..\coordinator\Register-CoordinatorExecution.ps1') -Action Release -DataDirectory $BoundJob.registry_directory -TaskId $BoundJob.task_id -DispatchId $BoundJob.registry_dispatch_id -ResultPath $BoundJob.result_file -DispatchJournalPath $BoundJob.dispatch_journal_path)
}
function Resume-BoundWorkItemResult($BoundJob) {
    $hash=[Security.Cryptography.SHA256]::Create()
    try { $key=([BitConverter]::ToString($hash.ComputeHash([Text.Encoding]::UTF8.GetBytes([string]$BoundJob.execution_id)))).Replace('-','').ToLowerInvariant() } finally { $hash.Dispose() }
    $workItemReservationPath=Join-Path $BoundJob.accounting_directory ('execution-'+$key+'.json')
    if (-not [IO.File]::Exists($workItemReservationPath)) { throw 'Execution reservation missing; no duplicate start.' }
    $saved=[IO.File]::ReadAllText($workItemReservationPath,$utf8)|ConvertFrom-Json
    if ($saved.executionId -cne $BoundJob.execution_id -or $saved.workItemId -cne $BoundJob.work_item_id -or $saved.task_id -cne $BoundJob.task_id -or $saved.parent_task_id -cne $BoundJob.parent_task_id -or [IO.Path]::GetFullPath($saved.store_path) -cne [IO.Path]::GetFullPath($BoundJob.work_item_store_path) -or [IO.Path]::GetFullPath($saved.result_path) -cne [IO.Path]::GetFullPath($BoundJob.result_file) -or [IO.Path]::GetFullPath($saved.parent_job_path) -cne [IO.Path]::GetFullPath($BoundJob.parent_job_path) -or $saved.parent_thread_id -cne $BoundJob.parent_thread_id -or $saved.parent_turn_id -cne $BoundJob.parent_turn_id -or [string]$saved.resume_assessment_path -cne [string]$BoundJob.resume_assessment_path -or [string](Get-LCValue $saved 'resume_assessment_hash') -cne [string](Get-LCValue $BoundJob 'resume_assessment_hash')) { throw 'Saved execution/job binding mismatch.' }
    $recoveryModule=Import-Module (Join-Path $PSScriptRoot '..\workitems\WorkItemPrestartRecovery.psm1') -PassThru -Force
    $proofPath=Join-Path $BoundJob.accounting_directory ('prestart-intent-'+$key+'.json.nospawn.json')
    if([IO.File]::Exists($proofPath)){
        $proof=& $recoveryModule {param($p)Read-RecoveryJson $p} $proofPath
        if($proof.phase -cne 'NoSpawnConfirmed' -or -not $proof.noSpawnProof.failure){throw 'PrestartImmutableProofInvalid'}
        Invoke-BoundNoSpawnRecovery $BoundJob ([string]$proof.noSpawnProof.failure)|Out-Null
        return
    }
    $failurePath=if($saved.failure_record_path){[string]$saved.failure_record_path}else{Join-Path $BoundJob.accounting_directory ('prestart-failure-'+$key+'.json')}
    if ([IO.File]::Exists($failurePath)) {
        $failure=[IO.File]::ReadAllText($failurePath,$utf8)|ConvertFrom-Json
        if ($failure.kind -cne 'prestart-failure' -or $failure.executionId -cne $saved.executionId -or $failure.workItemId -cne $saved.workItemId -or $failure.taskId -cne $saved.task_id -or $failure.parentTaskId -cne $saved.parent_task_id -or [IO.Path]::GetFullPath($failure.resultPath) -cne [IO.Path]::GetFullPath($saved.result_path)) { throw 'Prestart failure record binding mismatch.' }
        Invoke-BoundNoSpawnRecovery $BoundJob ([string]$failure.reason) | Out-Null
    } elseif ([IO.File]::Exists([string]$BoundJob.result_file)) {
        $savedEvidence=[IO.File]::ReadAllText($BoundJob.result_file,$utf8)|ConvertFrom-Json
        if ($savedEvidence.task_id -cne $BoundJob.task_id -or $savedEvidence.execution_id -cne $BoundJob.execution_id -or $savedEvidence.work_item_id -cne $BoundJob.work_item_id -or $savedEvidence.parent_job_task_id -cne $BoundJob.parent_task_id -or $savedEvidence.parent_thread_id -cne $BoundJob.parent_thread_id -or $savedEvidence.parent_turn_id -cne $BoundJob.parent_turn_id -or [IO.Path]::GetFullPath($savedEvidence.parent_job_path) -cne [IO.Path]::GetFullPath($BoundJob.parent_job_path) -or [IO.Path]::GetFullPath($savedEvidence.work_item_store_path) -cne [IO.Path]::GetFullPath($BoundJob.work_item_store_path) -or [IO.Path]::GetFullPath($savedEvidence.accounting_directory) -cne [IO.Path]::GetFullPath($BoundJob.accounting_directory)) { throw 'Saved technical evidence correlation mismatch.' }
        if ($savedEvidence.model_started -eq $false) {
            if (-not $savedEvidence.error) { throw 'Prestart reason missing; recovery required.' }
        Invoke-BoundNoSpawnRecovery $BoundJob ([string]$savedEvidence.error) | Out-Null
        } else {
            if ($savedEvidence.model_started -ne $true -or -not $savedEvidence.thread_id -or -not $savedEvidence.turn_id -or $savedEvidence.terminal_outcome -notin @('completed','failed','interrupted')) { throw 'Saved execution is not conclusively terminal; no transfer.' }
            if ($saved.state -eq 'reserved') {
                $saved.state='result_saved'; $saved.thread_id=$savedEvidence.thread_id; $saved.turn_id=$savedEvidence.turn_id
                Write-Json $workItemReservationPath $saved
            }
            & (Join-Path $RepositoryRoot 'scripts\workitems\Complete-DelegatedWorkItem.ps1') -StorePath $BoundJob.work_item_store_path -RepositoryRoot $RepositoryRoot -WorkItemId $BoundJob.work_item_id -ExecutionId $BoundJob.execution_id -ResultPath $BoundJob.result_file | Out-Null
        }
    } else { throw 'Execution state uncertain; duplicate model start prohibited.' }
}
function Test-DelegatedJobSsotBinding {
    param([Parameter(Mandatory=$true)]$Job)
    $hasExecution=-not [string]::IsNullOrWhiteSpace([string]$Job.execution_id)
    $hasRequest=-not [string]::IsNullOrWhiteSpace([string]$Job.work_item_request_path)
    # A manual job may carry the shared store solely to bind its own context.
    # SSOT identity begins with execution/request authority, never storePath alone.
    if(-not $hasExecution -and -not $hasRequest){return $false}
    if(-not $hasExecution -or -not $hasRequest -or [string]::IsNullOrWhiteSpace([string]$Job.work_item_store_path)){throw 'SavedSSOTBindingIncomplete; recovery required.'}
    return $true
}

if ($PSCmdlet.ParameterSetName -eq 'Start') {# A coordinator console is user-owned: it is never automatically closed.
    $contextModule=Import-Module (Join-Path $PSScriptRoot '..\workitems\CoordinatorExecutionContext.psm1') -PassThru -Force
    if ($Role -ceq 'koordinator') { $KeepWindowOpen = $true }
    $resultFile = [System.IO.Path]::GetFullPath($ResultPath)
    # H1: explicit input conflicts are rejected before recovering saved bindings.
    $existingJob=$resultFile+'.job.json'
    $oldJob=$null
    if ([IO.File]::Exists($existingJob)) {
        $oldJob=[IO.File]::ReadAllText($existingJob,$utf8)|ConvertFrom-Json
        $bindings=[ordered]@{Role='role';Task='task';ContextFile='context_file';ExecutionId='execution_id';WorkItemId='dispatch_work_item_id';WorkItemStorePath='work_item_store_path';WorkItemRequestPath='work_item_request_path';ResumeAssessment='resume_assessment';ParentTaskId='parent_task_id';AccountingDirectory='accounting_directory';Purpose='purpose';Generation='generation';DispatchJournalPath='dispatch_journal_path';DispatchId='dispatch_id';StableTaskId='task_id';WorkingDirectory='cwd';ResultPath='result_file';TaskTitle='task_title';RoleDisplayName='role_display_name';TimeoutSeconds='timeout_seconds';KeepWindowOpen='keep_window_open';AdmissionCapacity='admission_capacity';CoordinatorDataDirectory='coordinator_data_directory';CoordinatorLaunchConfigPath='coordinator_launch.inputPath';ParentContextPath='parent_context_path';ParentContextHash='parent_context_hash';StartIntentPath='start_intent_path';StartIntentHash='start_intent_hash'}
        foreach ($name in $bindings.Keys) {
            $field=$bindings[$name]; $savedValue=$oldJob.$field
            if ($name -eq 'WorkItemId' -and -not $oldJob.PSObject.Properties['dispatch_work_item_id']) { $savedValue=$oldJob.work_item_id }
            if ($PSBoundParameters.ContainsKey($name)) {
                $supplied=Get-Variable -Name $name -ValueOnly
                if ($name -in @('WorkingDirectory','ResultPath','ContextFile','WorkItemStorePath','WorkItemRequestPath','AccountingDirectory','DispatchJournalPath','CoordinatorDataDirectory') -and $supplied) {
                    if (-not $savedValue -or [IO.Path]::GetFullPath([string]$supplied) -cne [IO.Path]::GetFullPath([string]$savedValue)) { throw ('IdempotencyConflict: '+$name) }
                } elseif ($name -in @('DispatchId','StableTaskId','ParentTaskId') -and $supplied) {
                    if (-not $savedValue -or ([guid]$supplied).ToString('D') -cne ([guid]$savedValue).ToString('D')) { throw ('IdempotencyConflict: '+$name) }
                } elseif ([string]$supplied -cne [string]$savedValue) { throw ('IdempotencyConflict: '+$name) }
            }
            if ($null -ne $savedValue) { Set-Variable -Name $name -Value $savedValue }
        }
        if ([IO.Path]::GetFullPath([string]$oldJob.result_file) -cne $resultFile -or -not $oldJob.payload_hash -or -not $oldJob.registry_directory -or $oldJob.registry_dispatch_id -cne $oldJob.dispatch_id) { throw 'SavedJobBindingIncomplete; recovery required.' }
        if ($ContextFile -and [IO.File]::ReadAllText($ContextFile,$utf8) -cne [string]$oldJob.context) { throw 'IdempotencyConflict: context content changed.' }
    }
    $authorityParts=@([string]$ExecutionId,[string]$WorkItemRequestPath)
    $authorityPresent=@($authorityParts|Where-Object{-not [string]::IsNullOrWhiteSpace($_)}).Count
    if($authorityPresent -notin @(0,2)){throw 'IncompleteWorkItemStart; recovery required.'}
    if($authorityPresent -eq 2 -and [string]::IsNullOrWhiteSpace($WorkItemStorePath)){throw 'IncompleteWorkItemStoreBinding; recovery required.'}
    if ($ResumeAssessment -and $authorityPresent -ne 2) { throw 'IncompleteWorkItemStart; recovery required.' }
    $workItemMode=($authorityPresent -eq 2)
    $rootCoordinatorMode=($Role -ceq 'koordinator' -and -not $workItemMode)
    if($rootCoordinatorMode -and (-not $CoordinatorLaunchConfigPath -or $ParentTaskId)){throw 'Root coordinator requires an explicit launch input and must be parentless.'}
    $journalMode=[bool]$Purpose -or [bool]$Generation -or [bool]$DispatchJournalPath
    if ($WorkItemId -and -not $workItemMode -and -not $journalMode) { throw 'IncompleteWorkItemStart' }
    if ($journalMode -and (-not $WorkItemId -or -not $Purpose -or $Generation -lt 1 -or -not $DispatchJournalPath)) { throw 'WorkItemIdPurposeGenerationAndDispatchJournalPathRequired' }
    if ($workItemMode -and (-not $WorkItemId -or -not $ExecutionId -or -not $WorkItemStorePath -or -not $WorkItemRequestPath)) { throw 'IncompleteWorkItemStart' }
    if ($workItemMode -and ([string]::IsNullOrWhiteSpace($ExecutionId) -or $ExecutionId.Length -gt 128)) { throw 'InvalidExecutionId' }
    if ($workItemMode -and ($PSBoundParameters.ContainsKey('Task') -or $ContextFile)) { throw 'TaskAndContextFileForbiddenForWorkItemStart' }
    if (-not $workItemMode -and (-not $Role -or -not $Task)) { throw 'RoleAndTaskRequiredForLegacyStart' }
    if ($DispatchJournalPath) { $DispatchJournalPath=[IO.Path]::GetFullPath($DispatchJournalPath) }
    if (-not $DispatchId -and $StableTaskId) { $DispatchId = $StableTaskId }
    if ($journalMode) { $dispatchModule=Import-Module (Join-Path $PSScriptRoot '..\coordinator\CoordinatorDispatch.psm1') -PassThru -Force; $identity=& $dispatchModule {param($w,$p,$g)Get-CoordinatorDispatchIdentity $w $p $g} $WorkItemId $Purpose $Generation; if($DispatchId -and ([guid]$DispatchId).ToString('D') -cne $identity.ExecutionId){throw 'DispatchIdentityConflict'}; if($StableTaskId -and ([guid]$StableTaskId).ToString('D') -cne $identity.TaskId){throw 'TaskIdentityConflict'}; if($workItemMode -and $ExecutionId -cne $identity.ExecutionId){throw 'WorkItemExecutionIdentityConflict'}; $DispatchId=$identity.ExecutionId; $StableTaskId=([guid]$identity.TaskId).ToString('N') }
    if (-not $DispatchId) { $DispatchId = [guid]::NewGuid().ToString('D') }
    elseif (-not $journalMode) { $DispatchId = ([guid]$DispatchId).ToString('D') }
    if ($StableTaskId) { $StableTaskId = ([guid]$StableTaskId).ToString('N') }
    if ($oldJob) {
        if ($oldJob.dispatch_id -cne $DispatchId -or $oldJob.task_id -cne $StableTaskId) { throw 'SavedJobIdentityConflict' }
        if ($workItemMode) {
            if (-not $oldJob.parent_job_path -or -not $oldJob.parent_thread_id -or -not $oldJob.parent_turn_id) { throw 'SavedSSOTBindingIncomplete; recovery required.' }
            Resume-BoundWorkItemResult $oldJob
        }
        try { Complete-BoundRegistryJob $oldJob } catch { Write-Warning ('Reservation retained for recovery: '+$_.Exception.Message); throw }
        Write-Output ('Gebundenes Resultat wiederaufgenommen: '+$oldJob.task_id)
        return
    }
    $resolved=$null; $parentThreadId=$null; $parentTurnId=$null; $parentContextRecord=$null
    if(-not $PSBoundParameters.ContainsKey('ParentTaskId')){$ParentTaskId=$env:AGENT_ORG_PARENT_TASK_ID}
    if($ParentTaskId){$ParentTaskId=([guid]$ParentTaskId).ToString('N')}
    if($ParentTaskId -and $env:AGENT_ORG_PARENT_TASK_ID -and $ParentTaskId -cne ([guid]$env:AGENT_ORG_PARENT_TASK_ID).ToString('N')){throw 'ParentTaskBindingConflict'}
    # Choose a complete immutable parent group before SSOT resolution or any required-context assertion.
    $inheritedParentJob=[string]$env:AGENT_ORG_PARENT_JOB_FILE
    $inheritedParentContext=[string]$env:AGENT_ORG_PARENT_CONTEXT_PATH
    $inheritedParentHash=[string]$env:AGENT_ORG_PARENT_CONTEXT_HASH
    $explicitContextGroup=$PSBoundParameters.ContainsKey('ParentContextPath') -or $PSBoundParameters.ContainsKey('ParentContextHash')
    if($explicitContextGroup -and (-not $PSBoundParameters.ContainsKey('ParentContextPath') -or -not $PSBoundParameters.ContainsKey('ParentContextHash'))){throw 'ExplicitParentContextGroupIncomplete'}
    if($explicitContextGroup -and (-not $ParentContextPath -or -not $ParentContextHash)){throw 'ExplicitParentContextGroupEmpty'}
    if($ParentJobPath -and $inheritedParentJob -and [IO.Path]::GetFullPath($ParentJobPath) -cne [IO.Path]::GetFullPath($inheritedParentJob)){throw 'ParentJobBindingConflict'}
    if(-not $ParentJobPath){$ParentJobPath=$inheritedParentJob}
    if(([bool]$inheritedParentContext) -ne ([bool]$inheritedParentHash)){throw 'InheritedParentContextGroupIncomplete'}
    if(-not $explicitContextGroup){$ParentContextPath=$inheritedParentContext;$ParentContextHash=$inheritedParentHash}
    if($explicitContextGroup -and $inheritedParentContext -and ([IO.Path]::GetFullPath($ParentContextPath) -cne [IO.Path]::GetFullPath($inheritedParentContext) -or $ParentContextHash -cne $inheritedParentHash)){
        throw 'ExplicitParentContextBindingConflict'
    }
    if(-not $AccountingDirectory){$AccountingDirectory=[string]$env:AGENT_ORG_ACCOUNTING_DIRECTORY}
    if($AccountingDirectory){$AccountingDirectory=[IO.Path]::GetFullPath($AccountingDirectory)}
    if($PSBoundParameters.ContainsKey('AccountingDirectory') -and $env:AGENT_ORG_ACCOUNTING_DIRECTORY -and [IO.Path]::GetFullPath($AccountingDirectory) -cne [IO.Path]::GetFullPath($env:AGENT_ORG_ACCOUNTING_DIRECTORY)){throw 'AccountingDirectoryBindingConflict'}
    if(-not $explicitContextGroup -and $ParentTaskId -and $ParentJobPath -and $AccountingDirectory -and $ParentContextPath){
        $candidateJob=Read-AdmissionJson ([IO.Path]::GetFullPath($ParentJobPath))
        if($candidateJob.task_id -cne $ParentTaskId -or [IO.Path]::GetFullPath([string]$candidateJob.accounting_directory) -cne $AccountingDirectory){throw 'ParentJobEnvironmentBindingMismatch'}
        $activePath=[IO.Path]::GetFullPath($ParentJobPath)+'.active.json'
        if(-not [IO.File]::Exists($activePath)){throw 'ParentJobActiveContextMissing'}
        $active=Read-AdmissionJson $activePath
        $activeContextPath=[string]$active.context_path;$activeContextHash=[string]$active.context_hash
        if(-not $active.job_hash -or -not $active.thread_id -or -not $active.turn_id -or -not $activeContextPath -or -not $activeContextHash -or $active.task_id -cne $ParentTaskId -or $active.state -notin @('Running','RunningTurn','Ready')){throw 'ParentJobActiveContextBindingIncomplete'}
        $activeContextPath=[IO.Path]::GetFullPath($activeContextPath)
        $activeRecord=& $contextModule {param($p,$h,$j,$t,$s,$a)Assert-ExecutionContext $p $h $j $t $s $a} $activeContextPath $activeContextHash ([IO.Path]::GetFullPath($ParentJobPath)) $ParentTaskId ([string]$candidateJob.work_item_store_path) $AccountingDirectory
        if($active.job_hash -cne $activeRecord.jobHash -or $active.thread_id -cne $activeRecord.threadId -or $active.turn_id -cne $activeRecord.turnId -or $activeRecord.outcome -cne 'Running'){throw 'ParentJobActiveContextMismatch'}
        & $contextModule {param($p,$h,$s,$a)Assert-ExecutionAncestors $p $h $s $a|Out-Null} $activeContextPath $activeContextHash ([string]$candidateJob.work_item_store_path) $AccountingDirectory
        if([IO.Path]::GetFullPath($ParentContextPath) -cne $activeContextPath -or $ParentContextHash -cne $activeContextHash){
            # Replace only a stale inherited ancestor group with this exact parent's verified active ACK group.
            $ParentContextPath=$activeContextPath;$ParentContextHash=$activeContextHash
        }
    }
    if(([bool]$ParentContextPath) -ne ([bool]$ParentContextHash)){throw 'ParentContextBindingPairRequired'}
    if ($workItemMode) {
        if (-not $ParentTaskId) { $ParentTaskId=$env:AGENT_ORG_PARENT_TASK_ID }
        if (-not $ParentTaskId) { throw 'Persisted parent required for SSOT start.' }
        $ParentTaskId=([guid]$ParentTaskId).ToString('N')
        $WorkItemStorePath=[IO.Path]::GetFullPath($WorkItemStorePath)
        $WorkItemRequestPath=[IO.Path]::GetFullPath($WorkItemRequestPath)
        $accountingCandidate=if($AccountingDirectory){$AccountingDirectory}else{$env:AGENT_ORG_ACCOUNTING_DIRECTORY}
        if (-not $accountingCandidate) { throw 'Shared accounting root required.' }
        $AccountingDirectory=[IO.Path]::GetFullPath($accountingCandidate); $accountingCandidate=$AccountingDirectory
        $h=[Security.Cryptography.SHA256]::Create()
        try { $executionKey=([BitConverter]::ToString($h.ComputeHash([Text.Encoding]::UTF8.GetBytes($ExecutionId)))).Replace('-','').ToLowerInvariant() } finally { $h.Dispose() }
        if ([IO.File]::Exists((Join-Path $AccountingDirectory ('execution-'+$executionKey+'.json')))) { throw 'Execution reservation without matching saved job; recovery required, no duplicate start.' }
        if ([IO.File]::Exists($WorkItemRequestPath)) { throw 'Request locator exists without matching job; preserve for recovery.' }
        $resolved=& (Join-Path $PSScriptRoot 'Resolve-DelegatedWorkItem.ps1') -Path $WorkItemStorePath -RepositoryRoot $RepositoryRoot -WorkItemId $WorkItemId -ParentTaskId $ParentTaskId -ParentJobPath $ParentJobPath -AccountingDirectory $AccountingDirectory -ParentContextPath $ParentContextPath -ParentContextHash $ParentContextHash -ResumeAssessment $ResumeAssessment
        $resolved=$resolved|ConvertFrom-Json
        if ($Role -and $Role -cne $resolved.role) { throw 'RoleOverrideConflict' }
        $Role=[string]$resolved.role
        $parentThreadId=[string]$resolved.parentThreadId; $parentTurnId=[string]$resolved.parentTurnId
        $Task='Read the JSON request file and retrieve the current authoritative WorkItem using the documented store API. Return only a structured LTC result.'
    }
    if($workItemMode){
        foreach($required in @($ParentContextPath,$ParentContextHash,$StartIntentPath,$StartIntentHash)){if([string]::IsNullOrWhiteSpace($required)){throw 'SSOT start requires immutable parent context and pinned start authority.'}}
        $ParentContextPath=[IO.Path]::GetFullPath($ParentContextPath);$StartIntentPath=[IO.Path]::GetFullPath($StartIntentPath)
        if(-not $ParentJobPath){$ParentJobPath=$env:AGENT_ORG_PARENT_JOB_FILE};$ParentJobPath=[IO.Path]::GetFullPath($ParentJobPath)
        $parentContext=& $contextModule {param($p,$h,$j,$t,$s,$a) Assert-ExecutionContext $p $h $j $t $s $a} $ParentContextPath $ParentContextHash $ParentJobPath $ParentTaskId $WorkItemStorePath $AccountingDirectory
        & $contextModule {param($p,$h,$s,$a) Assert-ExecutionAncestors $p $h $s $a|Out-Null} $ParentContextPath $ParentContextHash $WorkItemStorePath $AccountingDirectory
        $startAuthority=& $contextModule {param($p,$h) Read-DelegatedStartAuthority $p $h} $StartIntentPath $StartIntentHash
        if($startAuthority.parentContextPath -cne $ParentContextPath -or $startAuthority.parentContextHash -cne $ParentContextHash -or $startAuthority.parentJobPath -cne $ParentJobPath){throw 'Pinned start authority parent binding mismatch.'}
        $ap=[ordered]@{};foreach($property in $startAuthority.parameters.PSObject.Properties){$ap[$property.Name]=$property.Value}
        if([string]$startAuthority.storeRevision -cne [string]$resolved.revision){throw 'StartAuthorityStoreRevisionConflict'}
        if([string](Get-LCValue $ap 'ResumeAssessment') -cne [string]$ResumeAssessment){throw 'Start authority ResumeAssessment conflict'}
        if($ResumeAssessment){$rd=Assert-LCResume $ResumeAssessment $resolved.item $resolved.revision $WorkItemStorePath $RepositoryRoot;if($rd.nextExecutionId -cne $ExecutionId -or [int]$rd.generation -ne $Generation){throw 'ResumeGenerationBindingConflict'}}
        foreach($pair in @(@('Role',$Role),@('WorkItemId',$WorkItemId),@('ExecutionId',$ExecutionId),@('Purpose',$Purpose),@('Generation',$Generation),@('StableTaskId',$StableTaskId),@('DispatchId',$DispatchId),@('TimeoutSeconds',$TimeoutSeconds),@('KeepWindowOpen',[bool]$KeepWindowOpen),@('AdmissionCapacity',$AdmissionCapacity),@('DetachedAfterVisibleAck',[bool]$DetachedAfterVisibleAck))){if([string]$ap[$pair[0]] -cne [string]$pair[1]){throw ('Start authority mismatch: '+$pair[0])}}
        foreach($pair in @(@('WorkItemStorePath',$WorkItemStorePath),@('WorkItemRequestPath',$WorkItemRequestPath),@('AccountingDirectory',$AccountingDirectory),@('ResultPath',$resultFile),@('WorkingDirectory',(Resolve-Path -LiteralPath $WorkingDirectory).Path),@('DispatchJournalPath',$DispatchJournalPath),@('CoordinatorDataDirectory',$CoordinatorDataDirectory))){if([IO.Path]::GetFullPath([string]$ap[$pair[0]]) -cne [IO.Path]::GetFullPath([string]$pair[1])){throw ('Start authority mismatch: '+$pair[0])}}
    }
    if ($Role -ceq 'koordinator') { $KeepWindowOpen=$true }
    $launchInput=$null
    if($rootCoordinatorMode){
        $CoordinatorLaunchConfigPath=[IO.Path]::GetFullPath($CoordinatorLaunchConfigPath)
        $launchInput=ConvertFrom-Json -InputObject $utf8.GetString([IO.File]::ReadAllBytes($CoordinatorLaunchConfigPath)) -ErrorAction Stop
        foreach($field in @('kind','workItemStorePath','eventJournalPath','registryDirectory','resultDirectories','runtimeExecutable','runtimeArguments','codexHome')){if(-not $launchInput.PSObject.Properties[$field]){throw "Coordinator launch input missing $field"}}
        if($launchInput.kind -cne 'coordinator-launch-input-v1' -or -not @($launchInput.resultDirectories).Count -or -not (Test-Path -LiteralPath $launchInput.runtimeExecutable -PathType Leaf)){throw 'Invalid coordinator launch input.'}
    }
    $workdir = (Resolve-Path -LiteralPath $WorkingDirectory).Path
    if (-not (Test-Path -LiteralPath $workdir -PathType Container)) { throw 'WorkingDirectory ist kein Verzeichnis.' }
    New-Item -ItemType Directory -Path (Split-Path -Parent $resultFile) -Force | Out-Null
    $agentHome = if ($env:CODEX_HOME) { $env:CODEX_HOME } else { Join-Path $env:USERPROFILE '.codex' }
    if (-not $RoleDisplayName) {
        $RoleDisplayName = $Role
        if ($workItemMode) { $RoleDisplayName = $Role }
        elseif ($Role -eq 'koordinator') { $RoleDisplayName = 'Koordinator' }
        elseif (-not $Role.StartsWith('teamleiter_')) {
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
    $context = if ($ContextFile -and -not $workItemMode) { [System.IO.File]::ReadAllText((Resolve-Path -LiteralPath $ContextFile).Path, $utf8) } else { '' }
    if(-not $AccountingDirectory -and -not $ParentContextPath){$AccountingDirectory=Join-Path (Split-Path -Parent $resultFile) 'token-accounting'}
    if(-not $workItemMode -and $ParentContextPath){
        if(-not $ParentTaskId -or -not $ParentJobPath -or -not $AccountingDirectory){throw 'ParentContextRequiresCompleteParentJobBinding'}
        $ParentJobPath=[IO.Path]::GetFullPath($ParentJobPath);$ParentContextPath=[IO.Path]::GetFullPath($ParentContextPath)
        $parentJob=Read-AdmissionJson $ParentJobPath
        if($parentJob.task_id -cne $ParentTaskId -or [IO.Path]::GetFullPath([string]$parentJob.accounting_directory) -cne [IO.Path]::GetFullPath($AccountingDirectory)){throw 'ParentJobEnvironmentBindingMismatch'}
        $parentContextRecord=& $contextModule {param($p,$h,$j,$t,$s,$a) Assert-ExecutionContext $p $h $j $t $s $a} $ParentContextPath $ParentContextHash $ParentJobPath $ParentTaskId ([string]$parentJob.work_item_store_path) $AccountingDirectory
        & $contextModule {param($p,$h,$s,$a) Assert-ExecutionAncestors $p $h $s $a|Out-Null} $ParentContextPath $ParentContextHash ([string]$parentJob.work_item_store_path) $AccountingDirectory
        if($parentJob.role -ceq 'koordinator'){$parentContextRecord=& $contextModule {param($p,$h,$j,$t,$s,$a) Assert-ExecutionContext $p $h $j $t $s $a -RequireTerminal -RequireLiveCoordinator} $ParentContextPath $ParentContextHash $ParentJobPath $ParentTaskId ([string]$parentJob.work_item_store_path) $AccountingDirectory}
        elseif($parentJob.role -notmatch '^teamleiter_[a-z][a-z0-9_]*$' -or $parentContextRecord.outcome -cne 'Running'){throw 'DelegatedParentMustBeTeamLeaderWithRunningAck'}
        if($parentJob.role -ceq 'koordinator') {if($Role -notmatch '^teamleiter_[a-z][a-z0-9_]*$'){throw 'CoordinatorMayStartOnlyTeamLeader'}}
        else{$teamPrefix=$parentJob.role.Substring('teamleader_'.Length)+'_';if($Role -notlike ($teamPrefix+'*') -or $Role -match '^teamleiter_' -or $Role -ceq $parentJob.role){throw 'TeamLeaderMayStartOnlyOwnOperationalRoles'}}
        & $contextModule {param($p,$h,$s,$a)Assert-ExecutionAncestors $p $h $s $a -MaxLevels 2|Out-Null} $ParentContextPath $ParentContextHash ([string]$parentJob.work_item_store_path) $AccountingDirectory
        $parentThreadId=[string]$parentContextRecord.threadId;$parentTurnId=[string]$parentContextRecord.turnId
    }
    if($rootCoordinatorMode -and ($ParentTaskId -or $oldJob -and ($oldJob.parent_task_id -or $oldJob.parent_job_path -or $oldJob.work_item_id -or $oldJob.execution_id -or $oldJob.work_item_request_path))){throw 'Root coordinator job must have no parent or delegated WorkItem binding.'}
    if (-not $AccountingDirectory) { $AccountingDirectory = Join-Path (Split-Path -Parent $resultFile) 'token-accounting' }
    $AccountingDirectory = [System.IO.Path]::GetFullPath($AccountingDirectory)
    New-Item -ItemType Directory -Path $AccountingDirectory -Force | Out-Null
    $payloadText = ($Role + "`n" + $Task + "`n" + $context + "`n" + $workdir + "`n" + $resultFile + "`n" + $ParentTaskId + "`n" + $TaskTitle + "`n" + $RoleDisplayName + "`n" + $TimeoutSeconds + "`n" + [string][bool]$KeepWindowOpen)
    if($journalMode){$payloadText += "`n"+$WorkItemId+"`n"+$Purpose+"`n"+$Generation+"`n"+[IO.Path]::GetFullPath($DispatchJournalPath)}
    if ($workItemMode) { $payloadText += "`n" + (ConvertTo-Json -InputObject ([ordered]@{ executionId=$ExecutionId; storePath=[IO.Path]::GetFullPath($WorkItemStorePath); requestPath=[IO.Path]::GetFullPath($WorkItemRequestPath); accountingDirectory=$AccountingDirectory; parentJobPath=[IO.Path]::GetFullPath($resolved.parentJobPath); parentThreadId=$parentThreadId; parentTurnId=$parentTurnId; resumeAssessment=$ResumeAssessment }) -Compress) }
    $sha = [Security.Cryptography.SHA256]::Create()
    try { $payloadHash = if($workItemMode){$StartIntentHash}else{([BitConverter]::ToString($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($payloadText)))).Replace('-', '').ToLowerInvariant()} } finally { $sha.Dispose() }
    foreach ($suffix in @('', '.window.json', '.go.json', '.events.jsonl', '.public.txt')) {
        if (Test-Path -LiteralPath ($resultFile + $suffix)) { throw "Vorhandenes Artefakt oder unklare Startabsicht bleibt erhalten: $resultFile$suffix" }
    }
    if($env:AGENT_ORG_ADMISSION_CAPACITY -and -not $PSBoundParameters.ContainsKey('AdmissionCapacity')){$AdmissionCapacity=[int]$env:AGENT_ORG_ADMISSION_CAPACITY}
    $executionDirectory = if ($CoordinatorDataDirectory) { [IO.Path]::GetFullPath($CoordinatorDataDirectory) } elseif ($env:AGENT_ORG_COORDINATOR_DATA_DIRECTORY) { [IO.Path]::GetFullPath($env:AGENT_ORG_COORDINATOR_DATA_DIRECTORY) } else { Join-Path $env:LOCALAPPDATA 'AgentOrganization\Coordinator' }
    $spec = @{
        task_id = $(if ($StableTaskId) { $StableTaskId } elseif($DispatchId -match '^[0-9a-fA-F-]{36}$') { ([guid]$DispatchId).ToString('N') } else { $DispatchId }); dispatch_id = $DispatchId; payload_hash = $payloadHash; request_hash=$(if($workItemMode){$startAuthority.requestPayloadHash}else{$null}); work_item_id=$WorkItemId;dispatch_work_item_id=$WorkItemId;execution_id=$ExecutionId;work_item_store_path=$WorkItemStorePath;work_item_request_path=$WorkItemRequestPath;resume_assessment=$ResumeAssessment;purpose=$Purpose;generation=$(if($Generation){$Generation}else{$null});dispatch_journal_path=$DispatchJournalPath; role = $Role; task = $Task; context = $context
        parent_job_path=$(if($workItemMode){[IO.Path]::GetFullPath($resolved.parentJobPath)}elseif($ParentTaskId){if($ParentJobPath){[IO.Path]::GetFullPath($ParentJobPath)}else{$env:AGENT_ORG_PARENT_JOB_FILE}}else{$null});parent_job_hash=$(if($workItemMode){$startAuthority.parentJobHash}else{$null})
        parent_thread_id=$parentThreadId; parent_turn_id=$parentTurnId; parent_context_path=$(if($ParentContextPath){$ParentContextPath}else{$null});parent_context_hash=$(if($ParentContextHash){$ParentContextHash}else{$null});start_intent_path=$(if($workItemMode){$StartIntentPath}else{$null});start_intent_hash=$(if($workItemMode){$StartIntentHash}else{$null});resume_assessment_path=$null;resume_assessment_hash=$null
        role_display_name = $RoleDisplayName; task_title = $TaskTitle; window_title = $(if ($Role -ceq 'koordinator') { 'Koordinator' } else { $RoleDisplayName + ' - ' + $TaskTitle })
        context_file = $(if ($ContextFile) { (Resolve-Path -LiteralPath $ContextFile).Path } else { $null })
        parent_task_id = $(if ($ParentTaskId) { $ParentTaskId } else { $null }); accounting_directory = $AccountingDirectory
        cwd = $workdir; result_file = $resultFile; timeout_seconds = $TimeoutSeconds; admission_capacity=$AdmissionCapacity; keep_window_open = [bool]$KeepWindowOpen
        coordinator_data_directory = $(if ($CoordinatorDataDirectory) { [IO.Path]::GetFullPath($CoordinatorDataDirectory) } elseif ($env:AGENT_ORG_COORDINATOR_DATA_DIRECTORY) { [IO.Path]::GetFullPath($env:AGENT_ORG_COORDINATOR_DATA_DIRECTORY) } else { Join-Path $env:LOCALAPPDATA 'AgentOrganization\Coordinator' })
        developer_instructions = ('Explizit zugewiesene Rolle: ' + $Role + ".`n" + $instructions.Groups[1].Value); config = $config
        model = (Read-RoleString $roleText 'model'); sandbox = (Read-RoleString $roleText 'sandbox_mode')
        approval_policy = (Read-RoleString $roleText 'approval_policy')
    }
    if(-not $workItemMode -and $ParentContextPath){$spec.work_item_store_path=[IO.Path]::GetFullPath([string]$parentJob.work_item_store_path)}
    if($rootCoordinatorMode){
        foreach($field in @('workItemStorePath','eventJournalPath','registryDirectory','runtimeExecutable','codexHome')){if([string]::IsNullOrWhiteSpace([string]$launchInput.$field)){throw "Coordinator launch input $field must be explicit."}}
        if(-not $launchInput.runtimeArguments -or -not $launchInput.resultDirectories -or -not $spec.admission_capacity -or -not $spec.coordinator_data_directory){throw 'Coordinator launch capacity, result roots, arguments, and data directory must be explicitly bound.'}
        $launchInput.workItemStorePath=[IO.Path]::GetFullPath($launchInput.workItemStorePath);$launchInput.eventJournalPath=[IO.Path]::GetFullPath($launchInput.eventJournalPath);$launchInput.registryDirectory=[IO.Path]::GetFullPath($launchInput.registryDirectory);$launchInput.runtimeExecutable=[IO.Path]::GetFullPath((Resolve-Path -LiteralPath $launchInput.runtimeExecutable -ErrorAction Stop).Path);$launchInput.codexHome=[IO.Path]::GetFullPath($launchInput.codexHome);$launchInput.resultDirectories=@($launchInput.resultDirectories|ForEach-Object{[IO.Path]::GetFullPath($_)})
        $policy=Get-AdmissionField $launchInput 'admissionPolicy';if((Get-AdmissionField $policy 'snapshotReuse' $false) -ne $false -or [int](Get-AdmissionField $policy 'scanBudgetMilliseconds' 10000) -le 0){throw 'AdmissionPolicyInvalid'}
        $spec.work_item_store_path=$launchInput.workItemStorePath;$spec.coordinator_launch=[ordered]@{inputPath=$CoordinatorLaunchConfigPath;inputHash=(& $contextModule {param($b)Get-ContextHash $b} ([IO.File]::ReadAllBytes($CoordinatorLaunchConfigPath)));dataDirectory=$spec.coordinator_data_directory;capacity=$spec.admission_capacity}
    }
    if($rootCoordinatorMode){
        $spec.coordinator_launch.admissionPolicy=[ordered]@{snapshotReuse=$false;scanBudgetMilliseconds=[int](Get-AdmissionField $policy 'scanBudgetMilliseconds' 10000)}
        $installed=Read-AdmissionJson (Join-Path $PSScriptRoot '..\coordinator\AdmissionInstalledContract.json')
        $spec.coordinator_launch.runtimeBinding=[ordered]@{executable=$launchInput.runtimeExecutable;executableHash=(Get-AdmissionHash ([IO.File]::ReadAllBytes($launchInput.runtimeExecutable)));arguments=@($launchInput.runtimeArguments);codexHome=$launchInput.codexHome;sourceContractHash=(Get-AdmissionHash ([IO.File]::ReadAllBytes((Join-Path $PSScriptRoot '..\coordinator\AdmissionInstalledContract.json'))));version=$installed.version}
    }
    $registry = Join-Path $PSScriptRoot '..\coordinator\Register-CoordinatorExecution.ps1'
    $startAttemptPath=$null;$startAttemptHash=$null;$startAttemptRecord=$null;$preparedAttemptPath=$null;$preparedAttemptHash=$null
    if($workItemMode){$intentModule=Import-Module (Join-Path $PSScriptRoot '..\workitems\WorkItemPrestartIntent.psm1') -PassThru -Force;$startAttemptPath=& $intentModule {param($a,$e)Get-WorkItemPrestartIntentPath $a $e} $AccountingDirectory $ExecutionId;$startAttemptRecord=[ordered]@{kind='workitem-prestart-attempt-v1';phase='Prepared';executionId=$ExecutionId;taskId=$spec.task_id;parentTaskId=$ParentTaskId;parentJobPath=$spec.parent_job_path;parentJobHash=$startAuthority.parentJobHash;parentContextPath=$ParentContextPath;parentContextHash=$ParentContextHash;parentThreadId=$parentThreadId;parentTurnId=$parentTurnId;startIntentPath=$StartIntentPath;startIntentHash=$StartIntentHash;payloadHash=$payloadHash;requestPath=$WorkItemRequestPath;requestHash=$startAuthority.requestPayloadHash;storePath=$WorkItemStorePath;workItemId=$WorkItemId;storeRevision=$resolved.revision;role=$Role;resultPath=$resultFile;dispatchJournalPath=$DispatchJournalPath;dispatchId=$DispatchId;noSpawnProof=$null;createdAtUtc=[DateTime]::UtcNow.ToString('o')};$startAttemptHash=& $intentModule {param($p,$r)Save-WorkItemPrestartIntent $p $r $null -Create} $startAttemptPath $startAttemptRecord;$recoveryModule=Import-Module (Join-Path $PSScriptRoot '..\workitems\WorkItemPrestartRecovery.psm1') -PassThru -Force;$preparedAttemptPath=$startAttemptPath+'.prepared.json';$preparedAttemptHash=$startAttemptHash;& $recoveryModule {param($p,$r)Write-RecoveryBytes $p (ConvertTo-RecoveryBytes $r) -Immutable} $preparedAttemptPath $startAttemptRecord;$spec.start_attempt_path=$preparedAttemptPath;$spec.start_attempt_hash=$preparedAttemptHash;$spec.no_spawn_attempt_path=$null;$spec.no_spawn_attempt_hash=$null}
    if($workItemMode){
        $dispatchInput=[ordered]@{authorityPath=$StartIntentPath;authorityHash=$StartIntentHash;parentJobPath=$spec.parent_job_path;parentJobHash=$startAuthority.parentJobHash;parentContextPath=$ParentContextPath;parentContextHash=$ParentContextHash;payloadHash=$payloadHash;resultPath=$resultFile;role=$Role;workItemId=$WorkItemId;purpose=$Purpose;generation=$Generation}
        $prepared=& $dispatchModule {param($j,$w,$p,$g,$i)Start-CoordinatorDispatch -JournalPath $j -WorkItemId $w -Purpose $p -Generation $g -Input $i} $DispatchJournalPath $WorkItemId $Purpose $Generation $dispatchInput
        if($prepared.state -cne 'Prepared'){throw 'ExistingDispatchRecoveryClosed'}
    }
    if($rootCoordinatorMode){
        # Persist actual root intent before enrollment; no inventory or TestMode bypass.
        $spec.registry_directory=$executionDirectory;$spec.registry_dispatch_id=$DispatchId
        Write-Json ($resultFile+'.job.json') $spec
        $enrollment=& $registry -Action EnrollRoot -DataDirectory $executionDirectory -RootJobPath ($resultFile+'.job.json')
        if((Get-AdmissionField $enrollment 'AdmissionAllowed' $false) -ne $true){throw ('AdmissionUnknown: '+(Get-AdmissionField $enrollment 'reason' 'RootEnrollmentNotGranted'))}
        $registryReservation=$enrollment
    }else{
        if(-not $workItemMode){
            if(-not $spec.parent_job_path -or -not $ParentContextPath -or -not $ParentContextHash){throw 'AdmissionUnknown: CoordinatorHandoffContextRequired'}
            $parent=Read-AdmissionJson $spec.parent_job_path
            if($parent.task_id -cne $ParentTaskId -or $parentContextRecord.taskId -cne $ParentTaskId){throw 'AdmissionUnknown: LegacyHistoricalContextMismatch'}
            if(-not $StartIntentPath){
                $authorityParameters=[ordered]@{StableTaskId=$spec.task_id;DispatchId=$DispatchId;ResultPath=$resultFile;Role=$Role;DispatchJournalPath=$DispatchJournalPath;CoordinatorDataDirectory=$executionDirectory;AdmissionCapacity=$AdmissionCapacity}
                $legacyAuthority=[ordered]@{kind='admission-legacy-start-authority-v1';parameters=$authorityParameters;payloadHash=$payloadHash;parentJobPath=$spec.parent_job_path;parentContextPath=$ParentContextPath;parentContextHash=$ParentContextHash}
                $StartIntentHash=Get-AdmissionObjectHash $legacyAuthority
                $StartIntentPath=Join-Path (Join-Path $AccountingDirectory 'start-authorities') ($StartIntentHash+'.json')
                if(-not [IO.File]::Exists($StartIntentPath)){[void](Write-AdmissionJson $StartIntentPath $legacyAuthority -Immutable)}
            }
            $spec.start_intent_path=$StartIntentPath;$spec.start_intent_hash=$StartIntentHash;$spec.parent_context_path=$ParentContextPath;$spec.parent_context_hash=$ParentContextHash
        }
        if(-not $spec.parent_job_path -or -not $StartIntentPath -or -not $StartIntentHash){throw 'AdmissionUnknown: ActualAncestorAndStartAuthorityRequired'}
        $admissionRoot=Get-AdmissionRoot $spec.parent_job_path
        $rootLaunch=Read-AdmissionJson $admissionRoot.Job.coordinator_launch.inputPath
        if([IO.Path]::GetFullPath($rootLaunch.registryDirectory) -cne $executionDirectory -or [int]$admissionRoot.Job.admission_capacity -ne $AdmissionCapacity){throw 'AdmissionUnknown: InheritedRootScopeMismatch'}
        $target=[ordered]@{taskId=$spec.task_id;dispatchId=$DispatchId;payloadHash=$payloadHash;resultPath=$resultFile;role=$Role;dispatchJournalPath=$DispatchJournalPath;startIntentPath=$StartIntentPath;startIntentHash=$StartIntentHash;parentJobPath=$spec.parent_job_path;parentContextPath=$ParentContextPath;parentContextHash=$ParentContextHash}
        if($AdmissionReservationJson){$provided=ConvertFrom-Json -InputObject $AdmissionReservationJson -ErrorAction Stop}
        else{$provided=Request-CoordinatorAdmission $admissionRoot.Path $target ([int](Get-AdmissionField (Get-AdmissionField $rootLaunch 'admissionPolicy') 'scanBudgetMilliseconds' 10000))}
        $registryReservation=& $registry -Action ReadAdmissionReservation -DataDirectory $executionDirectory -TargetJson (ConvertTo-Json -InputObject $target -Depth 50 -Compress) -AdmissionRequestHash $provided.admission.requestHash
        $spec.admission=$registryReservation.admission
        $spec.admission_runtime=@{executable=$rootLaunch.runtimeExecutable;arguments=@($rootLaunch.runtimeArguments);codexHome=$rootLaunch.codexHome;binaryHash=(Get-AdmissionHash ([IO.File]::ReadAllBytes($rootLaunch.runtimeExecutable)))}
    }
    if ($registryReservation.Reused) { Write-Output ('Vorhandene Execution bleibt belegt; keine erneute Ausfuehrung: TaskId ' + $spec.task_id + '; DispatchId ' + $DispatchId); return }
    $jobPath=$resultFile+'.job.json'
    $spec.registry_directory=$executionDirectory; $spec.registry_dispatch_id=$DispatchId
    $spawnAttempted=$false
    try {
        # Registry admission already succeeded. Durable job precedes SSOT mutation.
    if ($workItemMode) {
        $hash = [Security.Cryptography.SHA256]::Create().ComputeHash([Text.Encoding]::UTF8.GetBytes($ExecutionId))
        $executionKey = ([BitConverter]::ToString($hash)).Replace('-', '').ToLowerInvariant()
        $workItemReservationPath = Join-Path $AccountingDirectory ('execution-' + $executionKey + '.json')
        $resumeAssessmentPath = Join-Path $AccountingDirectory ('resume-' + $executionKey + '.json')
        if($ResumeAssessment){$loc=ConvertFrom-Json -InputObject $ResumeAssessment;$resumeAssessmentPath=$loc.path;$spec.resume_assessment_path=$loc.path;$spec.resume_assessment_hash=$loc.hash}
        $reservationJson = [ordered]@{ executionId = $ExecutionId; workItemId = $WorkItemId; store_path = $WorkItemStorePath; task_id = $spec.task_id; role=$Role; parent_task_id = $ParentTaskId; parent_job_path = $spec.parent_job_path; parent_thread_id=$parentThreadId; parent_turn_id=$parentTurnId;parent_context_path=$ParentContextPath;parent_context_hash=$ParentContextHash;start_intent_path=$StartIntentPath;start_intent_hash=$StartIntentHash;start_attempt_path=$preparedAttemptPath;start_attempt_hash=$preparedAttemptHash;no_spawn_attempt_path=$null;no_spawn_attempt_hash=$null;startingRevision=$resolved.revision;startingSnapshot=$resolved.item;startingOwnerId=$Role;current_binding_path=(& $recoveryModule {param($a,$e,$s,$w)(Get-PrestartRecoveryPaths $a $e $s $w).binding} $AccountingDirectory $ExecutionId $WorkItemStorePath $WorkItemId);request_path=$WorkItemRequestPath;request_hash=$startAuthority.requestPayloadHash;payload_hash=$payloadHash;resume_assessment_path=$(if ($ResumeAssessment) { $resumeAssessmentPath } else { $null });resume_assessment_hash=$(if($ResumeAssessment){$loc.hash}else{$null}); result_path = $resultFile; state = 'reserved'; reserved_at = [DateTime]::UtcNow.ToString('o') } | ConvertTo-Json -Depth 100 -Compress
        try {
            $stream = [IO.File]::Open($workItemReservationPath, [IO.FileMode]::CreateNew, [IO.FileAccess]::Write, [IO.FileShare]::None)
            try { $bytes = $utf8.GetBytes($reservationJson); $stream.Write($bytes, 0, $bytes.Length); $stream.Flush($true) } finally { $stream.Dispose() }
        } catch [IO.IOException] { throw 'ExecutionId ist bereits reserviert; kein automatischer Doppelstart.' }
        $module = Join-Path $RepositoryRoot 'scripts\workitems\WorkItemStore.psm1'; Import-Module $module -Force
        $currentStart = Get-WorkItemStoreResult -Path $WorkItemStorePath -RepositoryRoot $RepositoryRoot
        $startItem = @($currentStart.Document.items | Where-Object { $_.id -ceq $WorkItemId })
        if ($currentStart.Revision -cne $resolved.revision) { throw 'ReservationStartingCASMismatch' }
        Write-Json $jobPath $spec
        if ($startItem.Count -ne 1 -or $startItem[0].owner.id -cne $Role) { throw 'WorkItem changed after execution reservation.' }
        if ($startItem[0].status -notin @('planned','in_progress','rework','blocked')) { throw 'WorkItem became non-executable after reservation.' }
        if ($null -ne $startItem[0].humanInteraction -and $null -eq $startItem[0].humanInteraction.response) { throw 'Unanswered humanInteraction blocks execution.' }
        if($startItem[0].status -ceq 'blocked'){throw 'Blocked resume requires prior terminal effect CAS'}
        [void](Assert-LCResume $ResumeAssessment $startItem[0] $currentStart.Revision $WorkItemStorePath $RepositoryRoot -BeforeCAS)
        foreach ($dependencyId in $startItem[0].dependencies) {
            $dependencyItem = @($currentStart.Document.items | Where-Object { $_.id -ceq $dependencyId })
            if ($dependencyItem.Count -ne 1 -or $dependencyItem[0].status -cne 'accepted') { throw 'WorkItem dependency is no longer accepted.' }
        }
        $reservationData=[IO.File]::ReadAllText($workItemReservationPath,$utf8)|ConvertFrom-Json;if($reservationData.startingRevision -cne $currentStart.Revision){throw 'SecuredReservationChanged'}
        $currentBinding = & (Join-Path $PSScriptRoot 'Register-WorkItemExecution.ps1') -AccountingDirectory $AccountingDirectory -StorePath $WorkItemStorePath -RepositoryRoot $RepositoryRoot -WorkItemId $WorkItemId -ExecutionId $ExecutionId -TaskId $spec.task_id -ParentTaskId $ParentTaskId -ParentJobPath $spec.parent_job_path -ParentContextPath $ParentContextPath -ParentContextHash $ParentContextHash -StartIntentPath $StartIntentPath -StartIntentHash $StartIntentHash -ParentThreadId $parentThreadId -ParentTurnId $parentTurnId -PayloadHash $payloadHash -RequestPath $WorkItemRequestPath -RequestHash $startAuthority.requestPayloadHash -StartAttemptPath $preparedAttemptPath -StartAttemptHash $preparedAttemptHash
        $spec.work_item_binding_path = [string]$currentBinding.path
        $reservationData = [IO.File]::ReadAllText($workItemReservationPath, $utf8) | ConvertFrom-Json
        $reservationData.current_binding_path = [string]$currentBinding.path
        Write-Json $workItemReservationPath $reservationData
        Write-Json $jobPath $spec
        if ($startItem[0].status -ne 'in_progress') {
            $itemToStart = $startItem[0]
            $itemToStart.status = 'in_progress'; $itemToStart.blockReason = $null; $itemToStart.updatedAt = [DateTime]::UtcNow.ToString('yyyy-MM-ddTHH:mm:ss.fffffffZ')
            $startEffect=[ordered]@{effectId=('prestart-start:'+ $ExecutionId);executionId=$ExecutionId;requestId=(& $contextModule {param($p,$h)(Read-ContextJson $p).requestId} $ParentContextPath $ParentContextHash);threadId=$parentThreadId;turnId=$parentTurnId;eventId=('prestart-start:'+ $ExecutionId);inputHash=$StartIntentHash;planHash=$preparedAttemptHash;ordinal=1}
            $startDocument=ConvertFrom-Json -InputObject (ConvertTo-Json -InputObject $currentStart.Document -Depth 100)
            for($i=0;$i -lt @($startDocument.items).Count;$i++){if($startDocument.items[$i].id -ceq $WorkItemId){$startDocument.items[$i]=$itemToStart}}
            $storeModule=Get-Module WorkItemStore
            $startCandidate=& $storeModule {param($d) ,(ConvertTo-WorkItemStoreCandidate $d)} $startDocument
            $startCandidateHash=& $recoveryModule {param($b)Get-RecoveryHash $b} $startCandidate
            $startCAS=[ordered]@{sourceRevision=$currentStart.Revision;candidateRevision=('sha256:'+$startCandidateHash);effectContext=$startEffect}
            $reservationData|Add-Member -NotePropertyName startingCAS -NotePropertyValue $startCAS -Force
            Write-Json $workItemReservationPath $reservationData
            Set-WorkItemStoreEntry -Path $WorkItemStorePath -Id $WorkItemId -Item $itemToStart -IsNew $false -ExpectedRevision $currentStart.Revision -RepositoryRoot $RepositoryRoot -TimeoutMilliseconds 5000 -EffectContext $startEffect | Out-Null
        }
    }
        Write-Json $jobPath $spec
        if ($workItemMode) {
            $requestBytes=[Convert]::FromBase64String([string]$startAuthority.requestPayloadBase64)
            if((& $contextModule {param($b)Get-ContextHash $b} $requestBytes) -cne $startAuthority.requestPayloadHash){throw 'Pinned request locator byte hash mismatch.'}
            $stream=[IO.File]::Open($WorkItemRequestPath,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::None)
            try { $stream.Write($requestBytes,0,$requestBytes.Length);$stream.Flush($true) } finally { $stream.Dispose() }
        }
        if ($journalMode) {
            $dispatchInput=if($workItemMode){[ordered]@{authorityPath=$StartIntentPath;authorityHash=$StartIntentHash;parentJobPath=$spec.parent_job_path;parentJobHash=$startAuthority.parentJobHash;parentContextPath=$ParentContextPath;parentContextHash=$ParentContextHash;payloadHash=$payloadHash;resultPath=$resultFile;role=$Role;workItemId=$WorkItemId;purpose=$Purpose;generation=$Generation}}else{[ordered]@{task=$Task;context=$context;role=$Role;workingDirectory=$workdir;resultPath=$resultFile;payloadHash=$payloadHash}}
            $prepared=& $dispatchModule { param($j,$w,$p,$g,$i) Start-CoordinatorDispatch -JournalPath $j -WorkItemId $w -Purpose $p -Generation $g -Input $i } $DispatchJournalPath $WorkItemId $Purpose $Generation $dispatchInput
            if($workItemMode){$startAttemptRecord.phase='LaunchIntent';$startAttemptRecord.launchIntentAtUtc=[DateTime]::UtcNow.ToString('o');$startAttemptHash=& $intentModule {param($p,$r,$h)Save-WorkItemPrestartIntent $p $r $h} $startAttemptPath $startAttemptRecord $startAttemptHash}
            if($prepared.state -eq 'Prepared'){[void](& $dispatchModule { param($j,$id) Set-CoordinatorDispatchState -JournalPath $j -ExecutionId $id -State LaunchIntent } $DispatchJournalPath $DispatchId)}elseif($prepared.state -ne 'LaunchIntent'){throw 'DispatchReplayNoNewProcess'}
        }
    $protected = @(Get-Process -Name ChatGPT,powershell,conhost,WindowsTerminal -ErrorAction SilentlyContinue | ForEach-Object { [AgentTerminalWindow]::ForPid([uint32]$_.Id) } | Select-Object -Unique)
    # Explicit console host avoids Windows Terminal's non-owning pseudohandle.
    $spawnAttempted=$true
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
    } catch {
        $failureReason='Starter prestart failed: '+$_.Exception.Message
        if (-not $spawnAttempted -and $workItemMode -and $startAttemptPath) {
            try {
                $startAttemptRecord.noSpawnProof=[ordered]@{kind='synchronous-launcher-exception';spawnCallEntered=$false;launcherProcessId=$PID;launcherStartedAtUtc=([Diagnostics.Process]::GetCurrentProcess().StartTime.ToUniversalTime().ToString('o'));failure=$failureReason;recordedAtUtc=[DateTime]::UtcNow.ToString('o')};$startAttemptRecord.phase='NoSpawnConfirmed';$startAttemptHash=& $intentModule {param($p,$r,$h)Save-WorkItemPrestartIntent $p $r $h} $startAttemptPath $startAttemptRecord $startAttemptHash
                $noSpawnAttemptPath=$startAttemptPath+'.nospawn.json'
                & $recoveryModule {param($p,$r)Write-RecoveryBytes $p (ConvertTo-RecoveryBytes $r) -Immutable} $noSpawnAttemptPath $startAttemptRecord
                $spec.no_spawn_attempt_path=$noSpawnAttemptPath;$spec.no_spawn_attempt_hash=$startAttemptHash
                $reservationData=[IO.File]::ReadAllText($workItemReservationPath,$utf8)|ConvertFrom-Json
                $reservationData|Add-Member -NotePropertyName no_spawn_attempt_path -NotePropertyValue $noSpawnAttemptPath -Force
                $reservationData|Add-Member -NotePropertyName no_spawn_attempt_hash -NotePropertyValue $startAttemptHash -Force
                Write-Json $workItemReservationPath $reservationData
                try { Write-Json $jobPath $spec } catch { Write-Warning ('NoSpawn job readback unavailable; reservation proof retained: '+$_.Exception.Message) }
                Invoke-BoundNoSpawnRecovery ([pscustomobject]$spec) $failureReason | Out-Null
                try { Complete-BoundRegistryJob ([pscustomobject]$spec) } catch { Write-Warning ('Prestart reservation retained: '+$_.Exception.Message) }
            } catch { Write-Warning ('Secured prestart transfer rejected; recovery required: '+$_.Exception.Message) }
        }
        if ($journalMode) {
            try {
                $entry=& $dispatchModule { param($j,$id) Get-CoordinatorDispatch -JournalPath $j -ExecutionId $id } $DispatchJournalPath $DispatchId
                if ($entry -and $entry.state -in @('Prepared','LaunchIntent','Running')) { [void](& $dispatchModule { param($j,$id) Set-CoordinatorDispatchState -JournalPath $j -ExecutionId $id -State RecoveryRequired } $DispatchJournalPath $DispatchId) }
            } catch { Write-Warning ('Journal recovery unresolved: '+$_.Exception.Message) }
        }
        throw $failureReason
    }
    if ($DetachedAfterVisibleAck -and $confirmed) {
        Write-Output ('Start bestaetigt und reserviert: TaskId ' + $spec.task_id + '; DispatchId ' + $DispatchId)
        return
    }
    $deadline = [DateTime]::UtcNow.AddSeconds($TimeoutSeconds + 25)
    while (-not (Test-Path -LiteralPath $resultFile) -and -not $runner.HasExited -and [DateTime]::UtcNow -lt $deadline) { Start-Sleep -Milliseconds 200 }
    if (-not (Test-Path -LiteralPath $resultFile)) { throw 'Runner ohne gesichertes Resultat; kein Erfolg und kein pauschales Beenden anderer Prozesse.' }
    $result = [System.IO.File]::ReadAllText($resultFile, $utf8) | ConvertFrom-Json
    try { Complete-BoundRegistryJob ([pscustomobject]$spec) } catch { Write-Warning ('Reservation retained: '+$_.Exception.Message) }
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
    Write-Json $resultFile $result
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
$contextModule=Import-Module (Join-Path $PSScriptRoot '..\workitems\CoordinatorExecutionContext.psm1') -PassThru -Force
$jobSsotMode=Test-DelegatedJobSsotBinding -Job $job
$resultFile = [string]$job.result_file
$parentJobPath = [string]$job.parent_job_path
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
$terminalContext=$null
$evidence = [ordered]@{
    task_id = $job.task_id; dispatch_id=$job.dispatch_id; result_path=$resultFile; role = $job.role; runner_pid = $PID; window_handle = $handle.ToInt64(); title = $title
    work_item_id = $job.work_item_id; execution_id = $job.execution_id
    work_item_request_path = $job.work_item_request_path; work_item_store_path = $job.work_item_store_path
    parent_job_path = $job.parent_job_path; parent_job_task_id = $job.parent_task_id; parent_thread_id=$job.parent_thread_id; parent_turn_id=$job.parent_turn_id
    resume_assessment_path=$job.resume_assessment_path;resume_assessment_hash=$job.resume_assessment_hash
    model_started = $false; thread_id = $null; turn_id = $null; terminal_outcome = $null; output = $null; success = $false; error = $null
    parent_job_hash=$job.parent_job_hash
    parent_context_path=$job.parent_context_path;parent_context_hash=$job.parent_context_hash;request_hash=$job.request_hash
    start_intent_path=$job.start_intent_path;start_intent_hash=$job.start_intent_hash;payload_hash=$job.payload_hash
    parent_task_id = $job.parent_task_id; accounting_directory = $job.accounting_directory; token_usage = $null; token_summary = $null; usage_finalized = $false
    roleId=$job.role; modelId=$null; reasoningEffort=$null; measurementUTC=$null; measurementObservedAtUTC=$null; metadataSources=@()
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
        # Observation of the actual own native measurement, before publication.
        $evidence['measurementObservedAtUTC'] = [DateTime]::UtcNow.ToString("yyyy-MM-dd'T'HH:mm:ss.fffffff'Z'")
    }
}
function Write-Event([string]$Kind, $Data) {
    $line = @{ at = [DateTime]::UtcNow.ToString('o'); kind = $Kind; data = $Data } | ConvertTo-Json -Depth 30 -Compress
    [System.IO.File]::AppendAllText($resultFile + '.events.jsonl', $line + "`n", $utf8)
}
function Send-Rpc([string]$Method, $Params, [int]$Id) {
    $message=@{method=$Method};if($null -ne $Params){$message.params=$Params}
    if ($Id -gt 0) { $message.id = $Id }
    $bytes = $utf8.GetBytes(($message | ConvertTo-Json -Depth 20 -Compress) + "`n")
    if($Id -gt 0){$script:admissionRequests[[string]$Id]=@{method=$Method;id=$Id;requestBase64=[Convert]::ToBase64String($bytes);requestBytesHash=(Get-AdmissionHash $bytes);replyBase64=$null;replyBytesHash=$null;startedUtc=[DateTime]::UtcNow.ToString('o');endedUtc=$null}}
    $process.StandardInput.BaseStream.Write($bytes, 0, $bytes.Length)
    $process.StandardInput.BaseStream.Flush()
    Write-Event 'request' @{ method = $Method; id = $Id }
}
$script:admissionPendingRead=$null
$script:admissionPumping=$false
$script:admissionWaitingResponse=$false
$script:admissionResponses=@{}
$script:admissionNextRpc=100000
$script:admissionMutation=[long]0
$script:admissionGap=[long]0
$script:admissionProvider=$null
$script:admissionDiagnosticRequestHash=$null
$script:admissionRpcDeadline=$null
$script:admissionRequests=@{}
$script:admissionLastRpcReceipt=$null
function Invoke-RunnerAdmissionRpc([string]$Method,$Params,[int]$Milliseconds){
    $id=$script:admissionNextRpc;$script:admissionNextRpc++
    $prior=$script:admissionRpcDeadline;$script:admissionRpcDeadline=[DateTime]::UtcNow.AddMilliseconds($Milliseconds)
    try{Send-Rpc $Method $Params $id;Wait-Rpc $id}finally{$script:admissionRpcDeadline=$prior}
}
function Invoke-RunnerWaitRpcPump {
    if($script:admissionPumping -or -not $script:admissionProvider){return}
    $script:admissionPumping=$true
    try{
        $remaining=[int][Math]::Max(1,($deadline-[DateTime]::UtcNow).TotalMilliseconds)
        $budget=New-AdmissionBudget $remaining
        $rpc={param($m,$p,$ms)Invoke-RunnerAdmissionRpc $m $p $ms}
        $markers={@{mutation=$script:admissionMutation;gap=$script:admissionGap;rpc=$script:admissionLastRpcReceipt}}
        Invoke-AdmissionCallerPump $job.registry_directory $script:admissionProvider $budget $rpc $markers $script:admissionWaitingResponse $script:admissionDiagnosticRequestHash
    }finally{$script:admissionPumping=$false}
}
function Read-Rpc {
    if(-not $script:admissionPendingRead){$script:admissionPendingRead=$process.StandardOutput.ReadLineAsync()}
    while(-not $script:admissionPendingRead.IsCompleted){
        Invoke-RunnerWaitRpcPump
        if(-not $script:admissionPendingRead){$script:admissionPendingRead=$process.StandardOutput.ReadLineAsync()}
        $end=$deadline;if($script:admissionRpcDeadline -and $script:admissionRpcDeadline -lt $end){$end=$script:admissionRpcDeadline}
        $remaining=[int][Math]::Max(0,($end-[DateTime]::UtcNow).TotalMilliseconds)
        if($remaining -le 0){$script:admissionGap++;throw 'AdmissionUnknown: RunnerReaderDeadline'}
        [void]$script:admissionPendingRead.Wait([int][Math]::Min(20,$remaining))
    }
    $line=$script:admissionPendingRead.Result;$script:admissionPendingRead=$null
    if($null -eq $line){$script:admissionGap++;throw 'App-server hat seinen Ausgabestrom geschlossen.'}
    $message=ConvertFrom-Json -InputObject $line -ErrorAction Stop
    if(Get-AdmissionField $message 'method'){
        $script:admissionMutation++
        Write-Event 'notification' $message
        $notifications.Add($message)
        Update-NativeUsage $message
        if(Get-AdmissionField $message 'id'){$script:admissionGap++;throw ('Interaktive Serveranforderung: '+$message.method)}
        Get-PublicProgress $message $evidence.thread_id $evidence.turn_id $progressState | ForEach-Object {Write-ProgressDisplay $_}
    }elseif($null -ne (Get-AdmissionField $message 'id')){
        $key=[string]$message.id
        if(-not $script:admissionRequests.ContainsKey($key)){$script:admissionGap++;throw 'AdmissionUnknown: UnexpectedOrLateRpcResponse'}
        if($script:admissionResponses.ContainsKey($key)){$script:admissionGap++;throw 'AdmissionUnknown: DuplicateRpcResponse'}
        $script:admissionResponses[$key]=$message
        $req=$script:admissionRequests[$key];$replyBytes=$utf8.GetBytes($line)
        $req.replyBase64=[Convert]::ToBase64String($replyBytes);$req.replyBytesHash=Get-AdmissionHash $replyBytes;$req.endedUtc=[DateTime]::UtcNow.ToString('o')
    }else{$script:admissionGap++;throw 'AdmissionUnknown: UncorrelatedRpcMessage'}
    return $message
}
function Wait-Rpc([int]$Id) {
    $prior=$script:admissionWaitingResponse;$script:admissionWaitingResponse=$true
    try{
        while(-not $script:admissionResponses.ContainsKey([string]$Id)){[void](Read-Rpc)}
        $message=$script:admissionResponses[[string]$Id];$script:admissionResponses.Remove([string]$Id)
        if(Get-AdmissionField $message 'error'){throw ('App-server-Fehler: '+$message.error.message)}
        if(-not $message.PSObject.Properties['result']){throw 'AdmissionUnknown: RpcResultMissing'}
        $script:admissionLastRpcReceipt=$script:admissionRequests[[string]$Id];$script:admissionRequests.Remove([string]$Id)
        return $message.result
    }finally{$script:admissionWaitingResponse=$prior}
}

try {
    if ($handle -eq [IntPtr]::Zero -or -not [AgentTerminalWindow]::IsWindowVisible($handle)) { throw 'Eigenes sichtbares Konsolenfenster nicht verfügbar; kein Modellstart.' }
    Write-Json ($resultFile + '.window.json') @{ task_id = $job.task_id; runner_pid = $PID; window_handle = $handle.ToInt64(); window_pid = $windowPid; title = $title }
    $gateDeadline = [DateTime]::UtcNow.AddSeconds(15)
    while (-not (Test-Path -LiteralPath ($resultFile + '.go.json')) -and [DateTime]::UtcNow -lt $gateDeadline) { Start-Sleep -Milliseconds 100 }
    if (-not (Test-Path -LiteralPath ($resultFile + '.go.json'))) { throw 'Fenster wurde nicht bestätigt; kein Modellstart.' }
    $ack = [System.IO.File]::ReadAllText($resultFile + '.go.json', $utf8) | ConvertFrom-Json
    if ($ack.task_id -ne $job.task_id -or $ack.runner_pid -ne $PID -or $ack.title -ne $title) { throw 'Ungültige Fensterbestätigung.' }
    if($job.dispatch_journal_path){$dm=Import-Module (Join-Path $PSScriptRoot '..\coordinator\CoordinatorDispatch.psm1') -PassThru -Force;$binding=ConvertTo-Json -InputObject ([ordered]@{taskId=$job.task_id;runnerPid=$PID;windowHandle=$ack.window_handle;title=$title}) -Compress;[void](& $dm {param($j,$id,$b)Set-CoordinatorDispatchState -JournalPath $j -ExecutionId $id -State Running -LaunchBinding $b} $job.dispatch_journal_path $job.dispatch_id $binding)}
    $handle = [IntPtr][long]$ack.window_handle
    $evidence.window_handle = $handle.ToInt64()
    Start-Sleep -Seconds 10
    if (-not [AgentTerminalWindow]::IsWindowVisible($handle)) { throw 'Fenster vor Arbeitsbeginn nicht mehr sichtbar.' }
    if ([AgentTerminalWindow]::Title($handle) -ne $title) { throw 'Fenstertitel vor Arbeitsbeginn verändert; kein Modellstart.' }
    # Nur dieser Runner und seine eigenen Kindprozesse erhalten den Elternkontext.
    $env:AGENT_ORG_PARENT_TASK_ID = [string]$job.task_id
    $env:AGENT_ORG_PARENT_JOB_FILE = $resultFile + '.job.json'
    $env:AGENT_ORG_ACCOUNTING_DIRECTORY = [string]$job.accounting_directory
    $env:AGENT_ORG_COORDINATOR_DATA_DIRECTORY = [string]$job.coordinator_data_directory
    $env:AGENT_ORG_ADMISSION_CAPACITY = [string]$job.admission_capacity
    if ($job.role -ceq 'koordinator' -and -not $jobSsotMode) {
        $consoleScript = Join-Path (Split-Path -Parent $PSCommandPath) '..\Start-CoordinatorConsole.ps1'
        if (-not (Test-Path -LiteralPath $consoleScript -PathType Leaf)) { throw 'Coordinator console entrypoint missing.' }
        Write-Host 'Koordinator-Host ist aktiv; das bestätigte Fenster bleibt geöffnet.'
        $launchPath=[IO.Path]::GetFullPath([string]$job.coordinator_launch.inputPath)
        if(-not $launchPath -or (& $contextModule {param($b)Get-ContextHash $b} ([IO.File]::ReadAllBytes($launchPath))) -cne $job.coordinator_launch.inputHash){throw 'Coordinator launch input changed after root job persistence.'}
        $rootJobPath=[IO.Path]::GetFullPath($env:AGENT_ORG_PARENT_JOB_FILE)
        $rootLaunch=Read-AdmissionJson $launchPath
        $rootJobHash=& $contextModule {param($j)Get-ExecutionJobHash $j} $job
        & $consoleScript -DataDirectory $job.coordinator_data_directory -WorkingDirectory $job.cwd -TaskId $job.task_id -AccountingDirectory $job.accounting_directory -CoordinatorJobPath $rootJobPath -CoordinatorJobHash $rootJobHash -CoordinatorLaunchConfigPath $launchPath -CoordinatorLaunchConfigHash $job.coordinator_launch.inputHash -WorkItemStorePath $rootLaunch.workItemStorePath -EventJournalPath $rootLaunch.eventJournalPath -ResultDirectories @($rootLaunch.resultDirectories) -RegistryDirectory $rootLaunch.registryDirectory -RuntimeExecutable $rootLaunch.runtimeExecutable -RuntimeArguments @($rootLaunch.runtimeArguments) -CodexHome $rootLaunch.codexHome -PinnedRuntimeExecutable $rootLaunch.runtimeExecutable -PinnedCodexHome $rootLaunch.codexHome -PinnedDataDirectory $job.coordinator_data_directory -PinnedWorkingDirectory $job.cwd -PinnedCapacity $job.admission_capacity -PinnedAccountingDirectory $job.accounting_directory
        return
    }
    $deadline = [DateTime]::UtcNow.AddSeconds([int]$job.timeout_seconds)
    if(-not $job.admission_runtime -or (Get-AdmissionHash ([IO.File]::ReadAllBytes($job.admission_runtime.executable))) -cne $job.admission_runtime.binaryHash){throw 'AdmissionUnknown: EffectivePinnedBinaryRequired'}
    $start = New-Object System.Diagnostics.ProcessStartInfo
    $start.FileName = $job.admission_runtime.executable
    $start.Arguments = (@($job.admission_runtime.arguments|ForEach-Object{'"'+([string]$_).Replace('"','\"')+'"'}) -join ' ')
    $start.EnvironmentVariables['CODEX_HOME']=$job.admission_runtime.codexHome
    $start.WorkingDirectory = $job.cwd
    $start.UseShellExecute = $false; $start.CreateNoWindow = $true
    $start.RedirectStandardInput = $true; $start.RedirectStandardOutput = $true; $start.RedirectStandardError = $true
    $start.StandardOutputEncoding = $utf8
    $process = New-Object System.Diagnostics.Process
    $process.StartInfo = $start
    [void]$process.Start()
    $stderr = $process.StandardError.ReadToEndAsync()
    Send-Rpc 'initialize' @{ clientInfo = @{ name = 'agent_organization_terminal'; version = '0.1.0' } } 1
    $initializeReply=Wait-Rpc 1
    $rootForRunner=Get-AdmissionRoot $JobFile
    $runnerSessionPath=Join-Path $rootForRunner.Job.coordinator_data_directory 'session.json'
    $providerReceipt=New-AdmissionProviderReceipt $process $JobFile $rootForRunner.Path $runnerSessionPath $job.admission_runtime.executable @($job.admission_runtime.arguments) $job.admission_runtime.codexHome $initializeReply 'cli'
    [void](& (Join-Path $PSScriptRoot '..\coordinator\Register-CoordinatorExecution.ps1') -Action BindProvider -DataDirectory $job.registry_directory -TaskId $job.task_id -ProviderBindingJson (ConvertTo-Json -InputObject $providerReceipt -Depth 60 -Compress))
    $script:admissionProvider=$providerReceipt.receipt
    Send-Rpc 'initialized' @{} 0
    $runnerRpc={param($m,$p,$ms)Invoke-RunnerAdmissionRpc $m $p $ms}.GetNewClosure()
    $runnerMarkers={@{mutation=$script:admissionMutation;gap=$script:admissionGap;rpc=$script:admissionLastRpcReceipt}}.GetNewClosure()
    $pinnedRootLaunchPath=[IO.Path]::GetFullPath([string]$rootForRunner.Job.coordinator_launch.inputPath)
    if(-not $pinnedRootLaunchPath -or (Get-AdmissionHash ([IO.File]::ReadAllBytes($pinnedRootLaunchPath))) -cne [string]$rootForRunner.Job.coordinator_launch.inputHash){throw 'AdmissionPolicyRootLaunchPinMismatch'}
    $pinnedRootLaunch=Read-AdmissionJson $pinnedRootLaunchPath
    $runnerAdmissionPolicy=Get-AdmissionField $pinnedRootLaunch 'admissionPolicy'
    $runnerScanBudgetValue=Get-AdmissionField $runnerAdmissionPolicy 'scanBudgetMilliseconds' $null
    if($null -eq $runnerScanBudgetValue -or [int]$runnerScanBudgetValue -le 0){throw 'AdmissionPolicyInvalid'}
    $runnerScanBudget=[int]$runnerScanBudgetValue
    $setDiagnosticOwnership={param($hash)$script:admissionDiagnosticRequestHash=$hash}
    [void](Invoke-AdmissionReadDiagnostics $job.registry_directory $rootForRunner.Path $runnerSessionPath (Join-Path $PSScriptRoot '..\coordinator\Register-CoordinatorExecution.ps1') $script:admissionProvider $runnerScanBudget $runnerRpc $runnerMarkers $setDiagnosticOwnership)
    $capability=Get-AdmissionInstalledContract $script:admissionProvider
    if(-not $capability.api -or $capability.completionMode -eq 'Unknown'){throw ('AdmissionUnknown: MissingExternalAccess:'+($capability.missing -join ','))}
    Send-Rpc 'thread/start' @{ cwd = $job.cwd; model = $job.model; sandbox = $job.sandbox; approvalPolicy = $job.approval_policy; developerInstructions = $job.developer_instructions; config = $job.config } 2
    $thread = Wait-Rpc 2
    $evidence.thread_id = $thread.thread.id
    # Resolved thread/start response, never requested/current TOML settings.
    # This runner starts exactly one turn on a fresh thread, without overrides.
    if(-not $evidence.thread_id){throw 'AdmissionUnknown: NativeThreadACKMissing'}
    $nativeAck=[ordered]@{taskId=$job.task_id;threadId=$evidence.thread_id;origin=$script:admissionProvider.origin;generation=$script:admissionProvider.generation;reply=$thread;rpc=$script:admissionLastRpcReceipt}
    $nativeAckPath=Join-Path ($JobFile+'.inventory') ((Get-AdmissionObjectHash $nativeAck)+'.thread-ack.json')
    $nativeAckHash=Write-AdmissionJson $nativeAckPath $nativeAck -Immutable
    foreach($field in @('model','reasoningEffort')) {
        $property=$thread.PSObject.Properties[$field]
        if($null -ne $property -and $property.Value -is [string] -and $property.Value -cmatch '^[A-Za-z0-9][A-Za-z0-9_.:/-]{0,255}$') {
            $target=if($field -ceq 'model'){'modelId'}else{'reasoningEffort'}
            $evidence[$target]=$property.Value
            $evidence.metadataSources+=@([ordered]@{field=$target;value=$property.Value;source=$nativeAckPath;sha256=$nativeAckHash;basis='resolved fresh thread defaults; turn/start has no model or effort override'})
        }
    }
    if ($job.registry_directory) {
        [void](& (Join-Path $PSScriptRoot '..\coordinator\Register-CoordinatorExecution.ps1') -Action RegisterNative -DataDirectory $job.registry_directory -TaskId $job.task_id -DispatchId $job.registry_dispatch_id -NativeThreadId $evidence.thread_id -Role $job.role -State active -NativeAckPath $nativeAckPath -NativeAckHash $nativeAckHash)
    }
    Write-Host 'Eigene Sitzung ist bereit.'
    Write-Event 'thread_created' @{ thread_id = $evidence.thread_id }
    $text = [string]$job.task
    if ($jobSsotMode) {
        $env:AGENT_ORG_PARENT_TASK_ID = [string]$job.parent_task_id
        $env:AGENT_ORG_PARENT_JOB_FILE = $parentJobPath
        $current = & (Join-Path $PSScriptRoot 'Resolve-DelegatedWorkItem.ps1') -Path $job.work_item_store_path -RepositoryRoot $RepositoryRoot -WorkItemId $job.work_item_id -ParentTaskId $job.parent_task_id -AccountingDirectory $job.accounting_directory -ParentContextPath $job.parent_context_path -ParentContextHash $job.parent_context_hash -ResumeAssessment $job.resume_assessment
        $current = $current | ConvertFrom-Json
        if($job.resume_assessment){$rd=Assert-LCResume $job.resume_assessment $current.item $current.revision $job.work_item_store_path $RepositoryRoot;if($rd.nextExecutionId -cne $job.execution_id -or [int]$rd.generation -ne [int]$job.generation){throw 'RunnerResumeGenerationConflict'};$loc=ConvertFrom-Json -InputObject $job.resume_assessment;if($loc.path -cne $job.resume_assessment_path -or $loc.hash -cne $job.resume_assessment_hash){throw 'RunnerResumeReceiptConflict'}}
        if ($current.role -cne $job.role) { throw 'WorkItem owner changed after routing; refusing start.' }
        if ([IO.Path]::GetFullPath($current.parentJobPath) -cne [IO.Path]::GetFullPath($parentJobPath) -or $current.parentThreadId -cne $job.parent_thread_id -or $current.parentTurnId -cne $job.parent_turn_id) { throw 'Parent job/thread/turn binding changed after reservation; refusing start.' }
        $storeHint = ([string]$job.work_item_store_path).Replace("'", "''")
        $rootHint = ([string]$RepositoryRoot).Replace("'", "''")
        $text = 'Read request file ' + $job.work_item_request_path + ' as JSON (kind=request, workItemId, executionId). It is only a locator. Import-Module ''' + $rootHint + '\scripts\workitems\WorkItemStore.psm1''; call Get-WorkItemStoreResult -Path ''' + $storeHint + ''' -RepositoryRoot ''' + $rootHint + ''' to read the current authoritative WorkItem. Return the final_answer item as strict JSON: {"kind":"result","workItemId":"...","executionId":"...","outcome":"delivered|blocked|failed","result":{"summary":"...","evidence":["..."],"openPoints":[]},"reason":null}. For delivered, summary and nonempty evidence are mandatory. Preserve failed as outcome; distinguish blocked. No plain-text delivery.'
    }
    if ($job.context) { $text += "`n`nBenötigter Auftragskontext:`n" + $job.context }
    $contextRootHint = ([string]$RepositoryRoot).Replace("'", "''")
    $contextCli = "& '$contextRootHint\scripts\context\Get-WorkContext.ps1' -RepositoryRoot '$contextRootHint'"
    $text += "`n`nWissens-/Workflowhinweis (PowerShell; Beispiele gezielt an den Auftrag anpassen):`nSelektive Indexsuche: " + $contextCli + " -Kind all -Terms @('Suchbegriff')`nNur ausgewaehlte passende Eintraege lesen: " + $contextCli + " -Kind knowledge -Path 'entries/pfad.md'`nOder Workflow lesen: " + $contextCli + " -Kind workflow -Path 'pfad.md'`nSuchbegriff durch auftragsbezogene Suchwoerter ersetzen; -Path exakt aus RelativePath des ausgewaehlten Treffers uebernehmen. Apostrophe in Suchwoertern und Pfaden innerhalb einfacher PowerShell-Anfuehrungszeichen verdoppeln. Treffer anhand Quelle, WorkItem, Gueltigkeitskontext und Anwendbarkeit eigenstaendig pruefen; die Auswahl bleibt beim Agenten. Einen passenden Workflow selektiv lesen und im Rahmen des Auftrags verwenden. Ohne Treffer oder passenden Workflow die Arbeit anhand des verbindlichen Auftrags und geltender Projektregeln fortsetzen; keine Wahl erzwingen. Readerdiagnosen sind keine bestaetigte Trefferfreiheit. Workflows erteilen keinerlei Freigaben, ersetzen keine fehlende Spezifikation und umgehen keine erforderliche Freigabe. Bestehende Zustaendigkeiten und Ansprechpartner bleiben unveraendert; fehlende Spezifikation an den bestehenden Ansprechpartner melden."
    if ($jobSsotMode) {
        $env:AGENT_ORG_PARENT_TASK_ID = [string]$job.task_id
        $env:AGENT_ORG_PARENT_JOB_FILE = $resultFile + '.job.json'
        $env:AGENT_ORG_PARENT_CONTEXT_PATH=[string]$job.parent_context_path;$env:AGENT_ORG_PARENT_CONTEXT_HASH=[string]$job.parent_context_hash
    }
    $turnStartRpcId=3
    Send-Rpc 'turn/start' @{ threadId = $evidence.thread_id; input = @(@{ type = 'text'; text = $text }) } $turnStartRpcId
    $evidence.model_started = $true
    $turn = Wait-Rpc 3
    $evidence.turn_id = $turn.turn.id
    $turnContext=$null;$contextModuleRunner=$null;$turnAuthorityHash=$null
    if(($jobSsotMode -or ($job.parent_context_path -and $job.work_item_store_path)) -and $job.work_item_store_path -and $job.payload_hash){
        $contextModuleRunner=Import-Module (Join-Path $PSScriptRoot '..\workitems\CoordinatorExecutionContext.psm1') -PassThru -Force
        $payloadBytes=[Text.Encoding]::UTF8.GetBytes([string]$job.payload_hash);$turnAuthorityHash=& $contextModuleRunner {param($b)Get-ContextHash $b} $payloadBytes
        $ackBytes=$utf8.GetBytes(($turn|ConvertTo-Json -Depth 50 -Compress));$ackHash=& $contextModuleRunner {param($b)Get-ContextHash $b} $ackBytes
        $turnRequestId=if($jobSsotMode){[string]$job.execution_id}else{[string]$turnStartRpcId}
        $turnSessionId=if($jobSsotMode){[string]$job.execution_id}else{[string]$script:admissionProvider.generation}
        $turnContext=& $contextModuleRunner {param($d,$j,$s,$t,$u,$r,$sid,$a,$e)New-ExecutionTurnContext -Directory $d -JobPath $j -StorePath $s -ThreadId $t -TurnId $u -RequestId $r -Outcome Running -SessionId $sid -AuthorityHash $a -EvidenceHash $e} (Join-Path $job.accounting_directory 'contexts') ($resultFile+'.job.json') $job.work_item_store_path $evidence.thread_id $evidence.turn_id $turnRequestId $turnSessionId $turnAuthorityHash $ackHash
        $env:AGENT_ORG_PARENT_CONTEXT_PATH=$turnContext.path;$env:AGENT_ORG_PARENT_CONTEXT_HASH=$turnContext.hash;$env:AGENT_ORG_PARENT_THREAD_ID=$evidence.thread_id;$env:AGENT_ORG_PARENT_TURN_ID=$evidence.turn_id
    }
    if ($turnContext) {
        Write-Json ($resultFile + '.job.json.active.json') ([ordered]@{ task_id=$job.task_id; role=$job.role; job_hash=$turnContext.record.jobHash;thread_id=$evidence.thread_id; turn_id=$evidence.turn_id; work_item_id=$job.work_item_id; execution_id=$job.execution_id; store_path=$job.work_item_store_path; accounting_directory=$job.accounting_directory;state='RunningTurn';context_path=$turnContext.path;context_hash=$turnContext.hash;recorded_at=[DateTime]::UtcNow.ToString('o') })
    } else {
        Write-Json ($resultFile + '.job.json.active.json') ([ordered]@{ task_id=$job.task_id; role=$job.role; thread_id=$evidence.thread_id; turn_id=$evidence.turn_id; work_item_id=$null; execution_id=$null; store_path=$null; accounting_directory=$job.accounting_directory; recorded_at=[DateTime]::UtcNow.ToString('o') })
    }
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
    if($turnContext){$decisionBytes=$utf8.GetBytes(($completion|ConvertTo-Json -Depth 50 -Compress));$terminalEvidenceHash=& $contextModuleRunner {param($b)Get-ContextHash $b} $decisionBytes;$terminalOutcome=if($evidence.terminal_outcome -eq 'completed'){'Completed'}elseif($evidence.terminal_outcome -eq 'interrupted'){'Interrupted'}else{'Failed'};$terminalContext=& $contextModuleRunner {param($d,$j,$s,$t,$u,$r,$sid,$a,$e,$o)New-ExecutionTurnContext -Directory $d -JobPath $j -StorePath $s -ThreadId $t -TurnId $u -RequestId $r -Outcome $o -SessionId $sid -AuthorityHash $a -EvidenceHash $e} (Join-Path $job.accounting_directory 'contexts') ($resultFile+'.job.json') $job.work_item_store_path $evidence.thread_id $evidence.turn_id $turnRequestId $turnSessionId $turnAuthorityHash $terminalEvidenceHash $terminalOutcome}
    $evidence.output = ($notifications | Where-Object { $_.method -eq 'item/completed' -and $_.params.threadId -ceq $evidence.thread_id -and $_.params.turnId -ceq $evidence.turn_id -and $_.params.item.type -eq 'agentMessage' } | ForEach-Object { [string]$_.params.item.text }) -join "`n"
    $finalItems = @($notifications | Where-Object { $_.method -eq 'item/completed' -and $_.params.threadId -ceq $evidence.thread_id -and $_.params.turnId -ceq $evidence.turn_id -and $_.params.item.type -eq 'agentMessage' -and $_.params.item.phase -eq 'final_answer' })
    if ($finalItems.Count -eq 1) { $evidence.final_answer = [string]$finalItems[0].params.item.text }
    # Unterstützter Roundtrip: auch nach turn/completed noch eintreffende Usage lesen.

    $deadline = [DateTime]::UtcNow.AddSeconds(10)
    Send-Rpc 'thread/read' @{ threadId = $evidence.thread_id; includeTurns = $false } 5
    [void](Wait-Rpc 5)
    $evidence.usage_finalized = $true
    $evidence.output = ($notifications | Where-Object { $_.method -eq 'item/completed' -and $_.params.threadId -ceq $evidence.thread_id -and $_.params.turnId -ceq $evidence.turn_id -and $_.params.item.type -eq 'agentMessage' } | ForEach-Object { [string]$_.params.item.text }) -join "`n"
    $finalItems = @($notifications | Where-Object { $_.method -eq 'item/completed' -and $_.params.threadId -ceq $evidence.thread_id -and $_.params.turnId -ceq $evidence.turn_id -and $_.params.item.type -eq 'agentMessage' -and $_.params.item.phase -eq 'final_answer' })
    if ($finalItems.Count -eq 1) { $evidence.final_answer = [string]$finalItems[0].params.item.text }
    $evidence.success = ($evidence.terminal_outcome -eq 'completed')
    if($terminalContext){$technicalTerminalPath=$resultFile+'.job.json.active.json';Write-Json $technicalTerminalPath ([ordered]@{task_id=$job.task_id;role=$job.role;job_hash=$terminalContext.record.jobHash;thread_id=$evidence.thread_id;turn_id=$evidence.turn_id;work_item_id=$job.work_item_id;execution_id=$job.execution_id;store_path=$job.work_item_store_path;accounting_directory=$job.accounting_directory;state=$terminalOutcome;context_path=$terminalContext.path;context_hash=$terminalContext.hash;recorded_at=[DateTime]::UtcNow.ToString('o')})}
    Write-Event 'terminal' @{ outcome = $evidence.terminal_outcome; thread_id = $evidence.thread_id }
    # Public final_answer items were displayed once above. Keep raw output in
    # the result contract without replaying commentary or unknown phases here.
} catch {
    $evidence.error = $_.Exception.Message
    if (-not $evidence.model_started -and -not $evidence.terminal_outcome) { $evidence.terminal_outcome = 'failed' }
    Write-ProgressDisplay ('Fehler: ' + $evidence.error)
    if ($process -and $evidence.turn_id -and -not $evidence.terminal_outcome) {
        try { Send-Rpc 'turn/interrupt' @{ threadId = $evidence.thread_id; turnId = $evidence.turn_id } 4 } catch { }
    }
} finally {
    try {
    try {
        if($terminalContext){$evidence.own_context_path=$terminalContext.path;$evidence.own_context_hash=$terminalContext.hash}
        Write-Json (Join-Path $job.accounting_directory ($job.task_id + '.usage.json')) ([ordered]@{
            task_id = $job.task_id; parent_task_id = $job.parent_task_id; role = $job.role
            roleId=$evidence.roleId; modelId=$evidence.modelId; reasoningEffort=$evidence.reasoningEffort
            measurementUTC=$evidence.measurementUTC; importedAtUTC=[DateTime]::UtcNow.ToString("yyyy-MM-dd'T'HH:mm:ss.fffffff'Z'")
            measurementObservedAtUTC=$evidence['measurementObservedAtUTC']; measurementTimeBasis='native_time_unknown_notification_observation_only'
            requestedProfile=[ordered]@{modelId=$job.model;reasoningEffort=$job.config.model_reasoning_effort;source=$JobFile;effective=$false}
            metadataSources=$evidence.metadataSources; source='app_server_fresh_thread_single_turn'; counter_kind='turn_token_usage'
            thread_id = $evidence.thread_id; turn_id = $evidence.turn_id; parent_thread_id=$job.parent_thread_id; parent_turn_id=$job.parent_turn_id; work_item_id=$job.work_item_id; execution_id=$job.execution_id; work_item_store_path=$job.work_item_store_path; resume_assessment_path=$job.resume_assessment_path;resume_assessment_hash=$job.resume_assessment_hash; token_usage = (Get-FinalLedgerUsage $evidence)
        })
        $evidence.token_summary = & (Join-Path $PSScriptRoot '../accounting/Get-TaskTokenUsage.ps1') -TaskId $job.task_id -AccountingDirectory $job.accounting_directory
    } catch {
        $evidence.success = $false
        $ledgerError = 'Tokenabrechnung konnte nicht gesichert oder ausgewertet werden: ' + $_.Exception.Message
        $evidence.error = $(if ($evidence.error) { $evidence.error + '; ' + $ledgerError } else { $ledgerError })
    }
    Write-Json $resultFile $evidence
    if ($jobSsotMode) {
        try {
            $workItemReservationPath = Join-Path $job.accounting_directory ('execution-' + (([BitConverter]::ToString([Security.Cryptography.SHA256]::Create().ComputeHash([Text.Encoding]::UTF8.GetBytes([string]$job.execution_id)))).Replace('-', '').ToLowerInvariant()) + '.json')
            if (-not (Test-Path -LiteralPath $workItemReservationPath)) { throw 'Global execution reservation missing before transfer.' }
            $reservationData = [IO.File]::ReadAllText($workItemReservationPath, $utf8) | ConvertFrom-Json
            if ($reservationData.task_id -cne $job.task_id -or $reservationData.workItemId -cne $job.work_item_id -or $reservationData.executionId -cne $job.execution_id) { throw 'Execution reservation mismatch before transfer.' }
            if (-not $evidence.model_started) {
                $failureReason = if ($evidence.error) { [string]$evidence.error } else { 'Runner failed before model start.' }
                throw 'RunnerProcessExists; NoSpawn recovery is prohibited. Reservation remains closed.'
            } else {
                if (-not $evidence.thread_id -or -not $evidence.turn_id) { throw 'Started model execution lacks persisted thread/turn identity; no result transfer.' }
                $reservationData.state = 'result_saved'; $reservationData.thread_id = $evidence.thread_id; $reservationData.turn_id = $evidence.turn_id
                Write-Json $workItemReservationPath $reservationData
                & (Join-Path $RepositoryRoot 'scripts\workitems\Complete-DelegatedWorkItem.ps1') -StorePath $job.work_item_store_path -RepositoryRoot $RepositoryRoot -WorkItemId $job.work_item_id -ExecutionId $job.execution_id -ResultPath $resultFile
            }
        } catch {
            $evidence | Add-Member -NotePropertyName transfer_error -NotePropertyValue ('WorkItem-Store-Uebernahme fehlgeschlagen: ' + $_.Exception.Message) -Force
            Write-Json $resultFile $evidence
        }
    }
    if ($job.registry_directory -and $job.registry_dispatch_id) {
        try { Complete-BoundRegistryJob $job } catch { Write-Host ('Reservation retained for recovery: '+$_.Exception.Message) }
    }
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
        else { Start-Sleep -Seconds 2; if((Test-Path -LiteralPath $resultFile) -and [AgentTerminalWindow]::IsWindow($handle) -and [AgentTerminalWindow]::Title($handle) -ceq $title -and [AgentTerminalWindow]::GetProp($handle,('AgentOrganizationTask.'+$job.task_id)) -eq [IntPtr][int]$PID){[void][AgentTerminalWindow]::PostMessage($handle,0x0010,[IntPtr]::Zero,[IntPtr]::Zero)} }
    }
}
if (-not $evidence.success) { exit 2 }
