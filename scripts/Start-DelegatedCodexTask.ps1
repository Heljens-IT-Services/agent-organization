[CmdletBinding(DefaultParameterSetName = 'Start')]
param(
    [Parameter(Mandatory = $true, ParameterSetName = 'Start')][ValidatePattern('^[a-z][a-z0-9_]*$')][string]$Role,
    [Parameter(Mandatory = $true, ParameterSetName = 'Start')][string]$Task,
    [Parameter(ParameterSetName = 'Start')][string]$ContextFile,
    [Parameter(Mandatory = $true, ParameterSetName = 'Start')][string]$WorkingDirectory,
    [Parameter(Mandatory = $true, ParameterSetName = 'Start')][string]$ResultPath,
    [Parameter(ParameterSetName = 'Start')][ValidateRange(5, 3600)][int]$TimeoutSeconds = 120,
    [Parameter(ParameterSetName = 'Start')][switch]$KeepWindowOpen,
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
if ($PSCmdlet.ParameterSetName -eq 'Start') {
    $resultFile = [System.IO.Path]::GetFullPath($ResultPath)
    foreach ($suffix in @('', '.job.json', '.window.json', '.go.json', '.events.jsonl')) {
        if (Test-Path -LiteralPath ($resultFile + $suffix)) { throw "Vorhandenes Artefakt bleibt erhalten: $resultFile$suffix" }
    }
    $workdir = (Resolve-Path -LiteralPath $WorkingDirectory).Path
    if (-not (Test-Path -LiteralPath $workdir -PathType Container)) { throw 'WorkingDirectory ist kein Verzeichnis.' }
    New-Item -ItemType Directory -Path (Split-Path -Parent $resultFile) -Force | Out-Null
    $agentHome = if ($env:CODEX_HOME) { $env:CODEX_HOME } else { Join-Path $env:USERPROFILE '.codex' }
    $roleText = [System.IO.File]::ReadAllText((Join-Path $agentHome ('agents\' + $Role + '.toml')), $utf8)
    if ((Read-RoleString $roleText 'name') -ne $Role) { throw 'Rollenname passt nicht zur Datei.' }
    $instructions = [regex]::Match($roleText, "(?s)developer_instructions\s*=\s*'''(.*?)'''")
    $agents = [regex]::Match($roleText, '(?s)\[agents\]\s*enabled\s*=\s*(true|false)')
    if (-not $instructions.Success -or -not $agents.Success) { throw 'Rollenstruktur wird nicht unterstützt.' }
    $config = @{ agents = @{ enabled = ($agents.Groups[1].Value -eq 'true') } }
    foreach ($key in @('model_reasoning_effort', 'model_verbosity', 'web_search')) { $config[$key] = Read-RoleString $roleText $key }
    $context = if ($ContextFile) { [System.IO.File]::ReadAllText((Resolve-Path -LiteralPath $ContextFile).Path, $utf8) } else { '' }
    $spec = @{
        task_id = [guid]::NewGuid().ToString('N'); role = $Role; task = $Task; context = $context
        cwd = $workdir; result_file = $resultFile; timeout_seconds = $TimeoutSeconds; keep_window_open = [bool]$KeepWindowOpen
        developer_instructions = ('Explizit zugewiesene Rolle: ' + $Role + ".`n" + $instructions.Groups[1].Value); config = $config
        model = (Read-RoleString $roleText 'model'); sandbox = (Read-RoleString $roleText 'sandbox_mode')
        approval_policy = (Read-RoleString $roleText 'approval_policy')
    }
    $jobPath = $resultFile + '.job.json'
    Write-Json $jobPath $spec
    $protected = @(Get-Process -Name ChatGPT,powershell,conhost,WindowsTerminal -ErrorAction SilentlyContinue | ForEach-Object { [AgentTerminalWindow]::ForPid([uint32]$_.Id) } | Select-Object -Unique)
    $runner = Start-Process -FilePath (Get-Command powershell.exe).Source -ArgumentList @(
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
        $confirmed = $window.runner_pid -eq $runner.Id -and $window.task_id -eq $spec.task_id -and $window.title.Contains($spec.task_id) -and $candidates.Count -eq 1
        if ($confirmed) {
            $handle = [IntPtr][long]$candidates[0]
            $window.window_handle = $handle.ToInt64()
            Write-Json ($resultFile + '.go.json') @{ task_id = $spec.task_id; runner_pid = $runner.Id; window_handle = $handle.ToInt64(); visible = $true; title = $window.title; confirmed_at = [DateTime]::UtcNow.ToString('o') }
            Write-Output ('Fenster bestätigt: PID ' + $runner.Id + ', HWND ' + $handle.ToInt64() + ', ' + $window.title)
        }
    }
    $deadline = [DateTime]::UtcNow.AddSeconds($TimeoutSeconds + 25)
    while (-not (Test-Path -LiteralPath $resultFile) -and -not $runner.HasExited -and [DateTime]::UtcNow -lt $deadline) { Start-Sleep -Milliseconds 200 }
    if (-not (Test-Path -LiteralPath $resultFile)) { throw 'Runner ohne gesichertes Resultat; kein Erfolg und kein pauschales Beenden anderer Prozesse.' }
    $result = [System.IO.File]::ReadAllText($resultFile, $utf8) | ConvertFrom-Json
    if (-not $KeepWindowOpen) { [void]$runner.WaitForExit(5000) }
    if (-not $KeepWindowOpen -and $confirmed -and $runner.HasExited -and [AgentTerminalWindow]::IsWindow($handle) -and [AgentTerminalWindow]::Title($handle) -eq $window.title) {
        [void][AgentTerminalWindow]::PostMessage($handle, 0x0010, [IntPtr]::Zero, [IntPtr]::Zero)
        $closeDeadline = [DateTime]::UtcNow.AddSeconds(3)
        while ([AgentTerminalWindow]::IsWindow($handle) -and [DateTime]::UtcNow -lt $closeDeadline) { Start-Sleep -Milliseconds 100 }
    }
    $result | Add-Member -NotePropertyName window_closed -NotePropertyValue ($window -and -not [AgentTerminalWindow]::IsWindow([IntPtr][long]$window.window_handle))
    $result | Add-Member -NotePropertyName protected_window_handles -NotePropertyValue $protected
    $result | Add-Member -NotePropertyName controller_visibility_confirmed -NotePropertyValue $confirmed
    [System.IO.File]::WriteAllText($resultFile, ($result | ConvertTo-Json -Depth 10), $utf8)
    $result | ConvertTo-Json -Depth 10
    if (-not $result.success -or -not $confirmed) { exit 2 }
    exit 0
}

# Eigener sichtbarer Runner: Taskdaten stehen nicht in einer Shell-Kommandozeile.
$job = [System.IO.File]::ReadAllText((Resolve-Path -LiteralPath $JobFile).Path, $utf8) | ConvertFrom-Json
$resultFile = [string]$job.result_file
$title = 'Codex Auftrag ' + $job.task_id
$host.UI.RawUI.WindowTitle = $title
$handle = [AgentTerminalWindow]::GetConsoleWindow()
$windowPid = [uint32]0
[void][AgentTerminalWindow]::GetWindowThreadProcessId($handle, [ref]$windowPid)
Write-Host ('Rolle: ' + $job.role)
Write-Host ('Auftrag: ' + $job.task)
Write-Host ('Kontext: ' + $job.context)
Write-Host 'Arbeit beginnt nach bestätigtem Fenster und zehn Sekunden zum Mitlesen.'
$evidence = [ordered]@{
    task_id = $job.task_id; role = $job.role; runner_pid = $PID; window_handle = $handle.ToInt64(); title = $title
    model_started = $false; thread_id = $null; turn_id = $null; terminal_outcome = $null; output = $null; success = $false; error = $null
}
$process = $null
function Write-Event([string]$Kind, $Data) {
    $line = @{ at = [DateTime]::UtcNow.ToString('o'); kind = $Kind; data = $Data } | ConvertTo-Json -Depth 8 -Compress
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
        Write-Event 'notification' @{ method = $message.method }
        if ($message.id) { throw ('Interaktive Serveranforderung: ' + $message.method) }
        if ($message.method -eq 'item/agentMessage/delta') { Write-Host -NoNewline ([string]$message.params.delta) }
        elseif ($message.method -in @('turn/started', 'turn/completed', 'item/started')) { Write-Host ('[' + $message.method + ']') }
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
    Write-Host ('Thread: ' + $evidence.thread_id)
    Write-Event 'thread_created' @{ thread_id = $evidence.thread_id }
    $text = [string]$job.task
    if ($job.context) { $text += "`n`nBenötigter Auftragskontext:`n" + $job.context }
    Send-Rpc 'turn/start' @{ threadId = $evidence.thread_id; input = @(@{ type = 'text'; text = $text }) } 3
    $evidence.model_started = $true
    $turn = Wait-Rpc 3
    $evidence.turn_id = $turn.turn.id
    $messages = New-Object System.Collections.Generic.List[string]
    do {
        $message = Read-Rpc
        if ($message.method -eq 'item/completed' -and $message.params.item.type -eq 'agentMessage') { $messages.Add([string]$message.params.item.text) }
    } while ($message.method -ne 'turn/completed')
    $evidence.terminal_outcome = $message.params.turn.status
    $evidence.output = $messages -join "`n"
    $evidence.success = ($evidence.terminal_outcome -eq 'completed')
    Write-Event 'terminal' @{ outcome = $evidence.terminal_outcome; thread_id = $evidence.thread_id }
    Write-Host "`nErgebnis:"
    Write-Host $evidence.output
} catch {
    $evidence.error = $_.Exception.Message
    Write-Host ('Fehler: ' + $evidence.error)
    if ($process -and $evidence.turn_id -and -not $evidence.terminal_outcome) {
        try { Send-Rpc 'turn/interrupt' @{ threadId = $evidence.thread_id; turnId = $evidence.turn_id } 4 } catch { }
    }
} finally {
    Write-Json $resultFile $evidence
    if ($process) {
        try { $process.StandardInput.Close() } catch { }
        [void]$process.WaitForExit(3000)
        $process.Dispose()
    }
    Write-Host ('Resultat gesichert: ' + $resultFile)
    if ($job.keep_window_open) { [void](Read-Host 'Zum Schließen Enter drücken') } else { Start-Sleep -Seconds 2 }
}
if (-not $evidence.success) { exit 2 }
