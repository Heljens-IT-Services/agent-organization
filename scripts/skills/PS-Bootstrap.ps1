function ConvertTo-SkillRequestJson {
    param([System.Collections.IDictionary]$Request, [string]$RawParametersJson)
    # Keep parameter JSON verbatim; configuration remains ordinary serialized JSON.
    $outer = ConvertTo-Json -InputObject $Request -Compress -Depth 32
    if ($outer.Length -gt 4MB) { throw 'Betriebskonfiguration überschreitet das Bootstraplimit.' }
    if ([string]::IsNullOrWhiteSpace($RawParametersJson)) { throw 'ParametersJson darf nicht leer sein.' }
    $outer = $outer.TrimEnd()
    if (-not $outer.EndsWith('}')) { throw 'Betriebskonfiguration konnte nicht serialisiert werden.' }
    $prefix = $outer.Substring(0, $outer.Length - 1)
    $separator = if ($prefix.EndsWith('{')) { '' } else { ',' }
    return ($prefix + $separator + '"parameters":' + $RawParametersJson + '}')
}

function Get-SkillInterpreterBindings {
    param([string]$CoreInterpreterPath, [System.Collections.IDictionary]$CallerBindings)
    $bindings = @{}
    if (-not [IO.Path]::IsPathRooted($CoreInterpreterPath) -or -not (Test-Path -LiteralPath $CoreInterpreterPath -PathType Leaf)) {
        throw 'CoreInterpreterPath muss auf eine vorhandene absolute Executabledatei zeigen.'
    }
    $coreFullPath = [IO.Path]::GetFullPath($CoreInterpreterPath)
    $bindings[$coreFullPath] = $coreFullPath
    $bindings['python'] = $coreFullPath
    $powershell = Join-Path $env:SystemRoot 'System32/WindowsPowerShell/v1.0/powershell.exe'
    if (Test-Path -LiteralPath $powershell -PathType Leaf) {
        $powerShellFullPath = [IO.Path]::GetFullPath($powershell)
        $bindings[$powerShellFullPath] = $powerShellFullPath
        $bindings['powershell.exe'] = $powerShellFullPath
    }
    foreach ($key in $CallerBindings.Keys) {
        $value = [string]$CallerBindings[$key]
        if ([string]::IsNullOrWhiteSpace($value) -or -not [IO.Path]::IsPathRooted($value) -or -not (Test-Path -LiteralPath $value -PathType Leaf)) {
            throw "Interpreterbindung '$key' muss auf eine vorhandene absolute Executabledatei zeigen."
        }
        $bindings[[string]$key] = [IO.Path]::GetFullPath($value)
    }
    return $bindings
}

function Assert-SkillPathHasNoReparsePoints {
    param([string]$Path, [string]$StopAt)
    $current = [IO.Path]::GetFullPath($Path)
    $stop = if ($StopAt) { [IO.Path]::GetFullPath($StopAt).TrimEnd('\') } else { [IO.Path]::GetPathRoot($current).TrimEnd('\') }
    while ($current -and $current.Length -ge $stop.Length) {
        if ((Get-Item -LiteralPath $current -Force).Attributes -band [IO.FileAttributes]::ReparsePoint) { throw "Pfadkomponente '$current' darf kein Reparse Point sein." }
        if ($current.TrimEnd('\').Equals($stop, [StringComparison]::OrdinalIgnoreCase)) { return }
        $parent = [IO.Directory]::GetParent($current)
        if (-not $parent) { break }
        $current = $parent.FullName
    }
    throw "Pruefgrenze '$stop' liegt nicht in der Pfadkette von '$Path'."
}

function Invoke-SkillRuntimeBootstrap {
    param([string]$Operation, [System.Collections.IDictionary]$Request, [string]$RequestJson,
          [string]$RawParametersJson, [System.Collections.IDictionary]$CallerInterpreterBindings = @{},
          [string]$CoreInterpreterPath, [string]$ExecutionRef)
    $utf8 = New-Object System.Text.UTF8Encoding($false, $true)
    $process = $null; $tempRequest = $null; $outTask = $null; $errTask = $null
    $script:BootstrapPhase = 'Bootstrap'
    try {
        if ([string]::IsNullOrEmpty($RequestJson)) {
            if ($Operation -eq 'run') {
                $Request.interpreterBindings = Get-SkillInterpreterBindings -CoreInterpreterPath $CoreInterpreterPath -CallerBindings $CallerInterpreterBindings
                $RequestJson = ConvertTo-SkillRequestJson -Request $Request -RawParametersJson $RawParametersJson
            } else {
                $RequestJson = ConvertTo-Json -InputObject $Request -Compress -Depth 32
            }
        }
        if ([Text.Encoding]::UTF8.GetByteCount($RequestJson) -gt 4MB) { throw 'Runneranfrage überschreitet 4 MiB.' }
        $repoRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..'))
        $core = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot 'skill_runtime.py'))
        if (-not $core.StartsWith($repoRoot.TrimEnd('\') + '\', [StringComparison]::OrdinalIgnoreCase) -or
            -not (Test-Path -LiteralPath $core -PathType Leaf)) { throw 'Gemeinsamer Pythonkern scripts/skills/skill_runtime.py fehlt oder liegt außerhalb des Repositoryroots.' }
        Assert-SkillPathHasNoReparsePoints -Path $core -StopAt $repoRoot
        if (-not [IO.Path]::IsPathRooted($CoreInterpreterPath) -or -not (Test-Path -LiteralPath $CoreInterpreterPath -PathType Leaf)) {
            throw 'CoreInterpreterPath muss auf eine vorhandene absolute Executabledatei zeigen.'
        }
        Assert-SkillPathHasNoReparsePoints -Path $CoreInterpreterPath
        $tempRequest = [IO.Path]::GetTempFileName()
        [IO.File]::WriteAllText($tempRequest, $RequestJson, $utf8)
        $psi = New-Object Diagnostics.ProcessStartInfo
        $psi.FileName = [IO.Path]::GetFullPath($CoreInterpreterPath)
        $psi.WorkingDirectory = $repoRoot
        $psi.UseShellExecute = $false; $psi.CreateNoWindow = $true
        $psi.RedirectStandardOutput = $true; $psi.RedirectStandardError = $true
        $psi.StandardOutputEncoding = $utf8; $psi.StandardErrorEncoding = $utf8
        $psi.EnvironmentVariables['PYTHONUTF8'] = '1'
        $psi.EnvironmentVariables['PYTHONIOENCODING'] = 'utf-8:strict'
        $psi.Arguments = ((@($core, $Operation, '--request-file', $tempRequest) | ForEach-Object { ConvertTo-SkillWindowsArgument ([string]$_) }) -join ' ')
        $process = New-Object Diagnostics.Process
        $process.StartInfo = $psi
        $script:BootstrapPhase = 'Start'
        if (-not $process.Start()) { throw 'Pythonkern konnte nicht gestartet werden.' }
        $outTask = $process.StandardOutput.ReadToEndAsync()
        $errTask = $process.StandardError.ReadToEndAsync()
        $timeoutSeconds = if ($Operation -eq 'discover') { 60 } else { [int]$Request.timeoutSeconds }
        if ($timeoutSeconds -lt 1) { $timeoutSeconds = 60 }
        $timeoutMilliseconds = [int][Math]::Min([int]::MaxValue, ([double]$timeoutSeconds + 10) * 1000)
        $script:BootstrapPhase = 'Timeout'
        if (-not $process.WaitForExit($timeoutMilliseconds)) {
            try { $process.Kill() } catch {}
            [void]$process.WaitForExit(2000)
            if ($outTask -and -not $outTask.IsCompleted) { [void]$outTask.Wait(2000) }
            if ($errTask -and -not $errTask.IsCompleted) { [void]$errTask.Wait(2000) }
            throw "Pythonbootstrap-Timeout nach $timeoutSeconds Sekunden plus 10 Sekunden Nachfrist."
        }
        $tasks = [System.Threading.Tasks.Task[]]@($outTask, $errTask)
        [void][System.Threading.Tasks.Task]::WaitAll($tasks, 2000)
        if (-not $outTask.IsCompleted -or -not $errTask.IsCompleted) { throw 'Pythonkern-Ausgabestreams wurden nach Prozessende nicht rechtzeitig abgeschlossen.' }
        # Access Result only after completion; strict UTF-8 decoding failures become RunnerError.
        $stdout = $outTask.GetAwaiter().GetResult()
        $stderr = $errTask.GetAwaiter().GetResult()
        if ($stderr) { [Console]::Error.Write($stderr) }
        if ([Text.Encoding]::UTF8.GetByteCount($stdout) -gt 16MB -or [Text.Encoding]::UTF8.GetByteCount($stderr) -gt 16MB) {
            $script:BootstrapPhase = 'Output'; throw 'Pythonbootstrap-Ausgabe überschreitet das Limit von 16 MiB.'
        }
        if ([string]::IsNullOrWhiteSpace($stdout)) { $script:BootstrapPhase = 'Exit'; throw "Pythonkern endete mit Exitcode $($process.ExitCode) ohne Vertragsobjekt." }
        # The core owns the response contract. Preserve every original byte represented by the decoded text.
        [Console]::Out.Write($stdout)
    } catch {
        $message = ConvertTo-Json -InputObject $_.Exception.Message -Compress
        $phase = ConvertTo-Json -InputObject $script:BootstrapPhase -Compress
        $exec = ConvertTo-Json -InputObject $ExecutionRef -Compress
        [Console]::Error.WriteLine($_.Exception.Message)
        [Console]::Out.WriteLine('{"isSuccessful":false,"exception":{"code":"RunnerError","message":' + $message + ',"phase":' + $phase + ',"executionRef":' + $exec + '},"result":null}')
    } finally {
        if ($process) {
            try {
                if (-not $process.HasExited) { try { $process.Kill() } catch {}; [void]$process.WaitForExit(2000) }
            } catch {}
            if ($outTask -and -not $outTask.IsCompleted) { try { [void]$outTask.Wait(2000) } catch {} }
            if ($errTask -and -not $errTask.IsCompleted) { try { [void]$errTask.Wait(2000) } catch {} }
            try { $process.Dispose() } catch { [Console]::Error.WriteLine($_.Exception.Message) }
        }
        if ($tempRequest) { try { Remove-Item -LiteralPath $tempRequest -Force -ErrorAction Stop } catch { [Console]::Error.WriteLine($_.Exception.Message) } }
    }
}

function ConvertTo-SkillWindowsArgument([string]$Value) {
    if ($Value.Length -gt 0 -and $Value -notmatch '[\s"]') { return $Value }
    $builder = New-Object Text.StringBuilder; [void]$builder.Append('"'); $slashes=0
    foreach ($character in $Value.ToCharArray()) {
        if ($character -eq '\') { $slashes++; continue }
        if ($character -eq '"') { [void]$builder.Append(('\' * (2*$slashes+1))); [void]$builder.Append('"'); $slashes=0; continue }
        if ($slashes) { [void]$builder.Append(('\' * $slashes)); $slashes=0 }; [void]$builder.Append($character)
    }
    if ($slashes) { [void]$builder.Append(('\' * (2*$slashes))) }; [void]$builder.Append('"'); return $builder.ToString()
}
