[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][ValidateNotNullOrEmpty()][string]$RepositoryRoot,
    [Parameter(Mandatory = $true)][ValidateNotNullOrEmpty()][string]$StorePath,
    [Parameter(Mandatory = $true)][ValidateRange(1024, 65535)][int]$Port,
    [string]$AccountingDirectory,
    [string]$DisplayProjectionPath,
    [string]$DisplayTeamSourcePath,
    [string]$DisplayRoleRoot,
    [string[]]$SpecificationDirectories = @('docs/specifications', 'specifications', 'specs')
)
$ErrorActionPreference = 'Stop'
$repository = (Resolve-Path -LiteralPath $RepositoryRoot -ErrorAction Stop).Path
$storeDirectory = [IO.Path]::GetDirectoryName([IO.Path]::GetFullPath($StorePath))
if (-not [IO.Directory]::Exists($storeDirectory) -or -not [IO.File]::Exists([IO.Path]::GetFullPath($StorePath))) { throw 'StorePath muss auf eine bereits vorhandene Storedatei in einem vorhandenen lokalen Ordner zeigen.' }
if ($StorePath.StartsWith('\\') -or $storeDirectory.StartsWith('\\')) { throw 'StorePath muss auf lokalem NTFS liegen; UNC ist nicht unterstützt.' }
$storeDrive = [IO.DriveInfo]::new([IO.Path]::GetPathRoot([IO.Path]::GetFullPath($StorePath)))
if (-not $storeDrive.IsReady -or $storeDrive.DriveType -ne [IO.DriveType]::Fixed -or $storeDrive.DriveFormat -ne 'NTFS') { throw 'StorePath muss auf einem lokalen, bereitstehenden NTFS-Laufwerk liegen.' }
foreach ($directory in $SpecificationDirectories) {
    if ($directory -notmatch '^(docs/specifications|specifications|specs)(/[a-zA-Z0-9_.-]+)*$' -or $directory -match '(^|/)\.\.?(/|$)') { throw 'SpecificationDirectories darf nur sichere Markdown-Unterordner der freigegebenen Fachpfadwurzeln enthalten.' }
}
if ($AccountingDirectory) {
    $AccountingDirectory = (Resolve-Path -LiteralPath $AccountingDirectory -ErrorAction Stop).Path
    if (-not [IO.Directory]::Exists($AccountingDirectory)) { throw 'AccountingDirectory muss bereits vorhanden sein.' }
}
$canonicalStorePath = [IO.Path]::GetFullPath($StorePath)
if ($DisplayProjectionPath) {
    if (-not [IO.Path]::IsPathRooted($DisplayProjectionPath)) { throw 'DisplayProjectionPath muss ausdrücklich als absoluter Pfad angegeben werden.' }
    if (-not [IO.File]::Exists($DisplayProjectionPath)) { throw 'DisplayProjectionPath muss auf eine bereits vorhandene Anzeigeprojektionsdatei zeigen; sie wird nicht angelegt.' }
    $DisplayProjectionPath = [IO.Path]::GetFullPath((Resolve-Path -LiteralPath $DisplayProjectionPath -ErrorAction Stop).Path)
    if ([string]::Equals($DisplayProjectionPath, $canonicalStorePath, [StringComparison]::OrdinalIgnoreCase)) { throw 'DisplayProjectionPath darf nicht auf den WorkItem-Store zeigen.' }
}
if ($DisplayTeamSourcePath -and -not [IO.Path]::IsPathRooted($DisplayTeamSourcePath)) { throw 'DisplayTeamSourcePath muss ausdrücklich als absoluter Pfad angegeben werden.' }
if ($DisplayRoleRoot -and -not [IO.Path]::IsPathRooted($DisplayRoleRoot)) { throw 'DisplayRoleRoot muss ausdrücklich als absoluter Pfad angegeben werden.' }
if ($DisplayTeamSourcePath) { $DisplayTeamSourcePath = [IO.Path]::GetFullPath($DisplayTeamSourcePath) }
if ($DisplayRoleRoot) { $DisplayRoleRoot = [IO.Path]::GetFullPath($DisplayRoleRoot) }
$configuration = [pscustomobject]@{ RepositoryRoot = $repository; StorePath = $canonicalStorePath; AccountingDirectory = $AccountingDirectory; DisplayProjectionPath = $DisplayProjectionPath; DisplayTeamSourcePath = $DisplayTeamSourcePath; DisplayRoleRoot = $DisplayRoleRoot; Port = $Port; SpecificationDirectories = $SpecificationDirectories }
$staticFiles = @{
    '/' = @{ path = 'web/index.html'; type = 'text/html; charset=utf-8' }
    '/index.html' = @{ path = 'web/index.html'; type = 'text/html; charset=utf-8' }
    '/styles.css' = @{ path = 'web/styles.css'; type = 'text/css; charset=utf-8' }
    '/app.js' = @{ path = 'web/app.js'; type = 'text/javascript; charset=utf-8' }
    '/bridge.js' = @{ path = 'web/bridge.js'; type = 'text/javascript; charset=utf-8' }
}
$randomBytes = New-Object byte[] 32
$randomGenerator = [Security.Cryptography.RandomNumberGenerator]::Create()
try { $randomGenerator.GetBytes($randomBytes) } finally { $randomGenerator.Dispose() }
$session = [Convert]::ToBase64String($randomBytes).TrimEnd('=').Replace('+','-').Replace('/','_')
$origin = "http://127.0.0.1:$Port"
$listener = New-Object Net.HttpListener
$listener.Prefixes.Add("$origin/")
Import-Module (Join-Path $PSScriptRoot 'LocalWebBridge.psm1') -Force
try {
    $listener.Start()
    $launchUrl = "$origin/#session=$session"
    Write-Output "LocalWeb: $launchUrl"
    Write-Output 'Stop: Ctrl+C in diesem Prozessfenster.'
    while ($listener.IsListening) {
        $context = $listener.GetContext()
        $request = $context.Request
        $response = $context.Response
        $parsed = $null
        $result = $null
        try {
            $expectedHost = "127.0.0.1:$Port"
            if ($request.UserHostName -cne $expectedHost) { $response.StatusCode = 403; continue }
            if ($request.HttpMethod -eq 'POST' -and $request.Url.AbsolutePath -ceq '/bridge') {
                if ($request.Headers['Origin'] -cne $origin) { $response.StatusCode = 403; continue }
                if ($request.Headers['X-Local-Session'] -cne $session) { $response.StatusCode = 403; continue }
                if ($request.ContentType -notmatch '^application/json\s*;\s*charset=utf-8$') { $result = Get-LocalWebFailure -Code 'UnsupportedMediaType' -Message 'Content-Type muss application/json; charset=utf-8 sein.' -StatusCode 400 }
                elseif ($request.ContentLength64 -gt 1048576 -or $request.ContentLength64 -lt 0) { $result = Get-LocalWebFailure -Code 'RequestTooLarge' -Message 'Request überschreitet 1 MiB.' -StatusCode 400 }
                else {
                    $reader = New-Object IO.StreamReader($request.InputStream, (New-Object Text.UTF8Encoding($false, $true)))
                    try { $body = $reader.ReadToEnd() } finally { $reader.Dispose() }
                    try { $parsed = ConvertFrom-Json -InputObject $body -ErrorAction Stop; $result = Invoke-LocalWebOperation $parsed $configuration }
                    catch { $result = Get-LocalWebFailure -Code 'MalformedRequest' -Message 'Request enthält kein gültiges UTF-8 JSON-Objekt.' -StatusCode 400 }
                }
                if ($result.ContainsKey('response')) { $response.StatusCode = 200; $payload = $result.response }
                else {
                    $response.StatusCode = $result.status
                    $responseOperation = if ($parsed -and $parsed.operation) { [string]$parsed.operation } else { $null }
                    $responseRequestId = if ($parsed -and $parsed.requestId) { [string]$parsed.requestId } else { $null }
                    $payload = New-LocalWebResponse $responseRequestId $responseOperation $false $result.status $null $result.error
                }
                $response.ContentType = 'application/json; charset=utf-8'
                $bytes = (New-Object Text.UTF8Encoding($false, $true)).GetBytes((ConvertTo-Json -InputObject $payload -Depth 100 -Compress))
                $response.ContentLength64 = $bytes.Length
                $response.OutputStream.Write($bytes, 0, $bytes.Length)
                continue
            }
            if ($request.HttpMethod -ne 'GET' -or -not $staticFiles.ContainsKey($request.Url.AbsolutePath)) { $response.StatusCode = 404; continue }
            $file = Join-Path $repository $staticFiles[$request.Url.AbsolutePath].path
            if (-not [IO.File]::Exists($file)) { $response.StatusCode = 404; continue }
            $bytes = [IO.File]::ReadAllBytes($file)
            $response.StatusCode = 200
            $response.ContentType = $staticFiles[$request.Url.AbsolutePath].type
            $response.ContentLength64 = $bytes.Length
            $response.OutputStream.Write($bytes, 0, $bytes.Length)
        } catch {
            try { $response.StatusCode = 500 } catch { }
        } finally {
            try { $response.Close() } catch { }
        }
    }
} finally {
    if ($listener.IsListening) { $listener.Stop() }
    $listener.Close()
}
