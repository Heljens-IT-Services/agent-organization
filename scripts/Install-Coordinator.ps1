[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$organizationRoot = Split-Path -Parent $PSScriptRoot
$coordinatorHome = if ($env:CODEX_HOME) { $env:CODEX_HOME } else { Join-Path $env:USERPROFILE '.codex' }
$installFiles = @(
    @{ Source = 'roles\koordinator.toml'; Target = 'agents\koordinator.toml' },
    @{ Source = 'profiles\koordinator.config.toml'; Target = 'koordinator.config.toml' }
)

# Erst alle Konflikte prüfen, damit vorhandene Konfiguration erhalten bleibt.
foreach ($installFile in $installFiles) {
    $source = Join-Path $organizationRoot $installFile.Source
    $target = Join-Path $coordinatorHome $installFile.Target
    if (-not (Test-Path -LiteralPath $source -PathType Leaf)) { throw "Quelle fehlt: $source" }
    if (Test-Path -LiteralPath $target) {
        if (-not (Test-Path -LiteralPath $target -PathType Leaf)) { throw "Ziel ist keine Datei: $target" }
        if ((Get-FileHash -LiteralPath $source).Hash -ne (Get-FileHash -LiteralPath $target).Hash) {
            throw "Vorhandene abweichende Datei bleibt erhalten: $target"
        }
    }
}

foreach ($installFile in $installFiles) {
    $source = Join-Path $organizationRoot $installFile.Source
    $target = Join-Path $coordinatorHome $installFile.Target
    if (-not (Test-Path -LiteralPath $target)) {
        New-Item -ItemType Directory -Path (Split-Path -Parent $target) -Force | Out-Null
        Copy-Item -LiteralPath $source -Destination $target
    }
    if ((Get-FileHash -LiteralPath $source).Hash -ne (Get-FileHash -LiteralPath $target).Hash) {
        throw "Installationsprüfung fehlgeschlagen: $target"
    }
    Write-Output "Installiert und bytegleich: $target"
}

Write-Output 'CLI-Hauptstart: codex --profile koordinator'
Write-Output 'App-Hauptchat und Fensterautomatik sind damit nicht als aktiviert nachgewiesen.'
