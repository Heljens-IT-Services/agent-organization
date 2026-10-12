[CmdletBinding()]
param(
    [string]$TaskId,
    [string]$AccountingDirectory
)
$ErrorActionPreference = 'Stop'

function Write-SkillResponse($Successful, $Exception, $Result) {
    $response = [ordered]@{ isSuccessful = [bool]$Successful; exception = $Exception; result = $Result }
    [Console]::Out.WriteLine((ConvertTo-Json -InputObject $response -Depth 100 -Compress))
}

try {
    if ([string]::IsNullOrWhiteSpace($TaskId)) { throw 'Pflichtparameter task_id fehlt oder ist leer.' }
    if ([string]::IsNullOrWhiteSpace($AccountingDirectory)) { throw 'Pflichtparameter accounting_directory fehlt oder ist leer.' }
    $source = Join-Path $PSScriptRoot '../../scripts/accounting/Get-TaskTokenUsage.ps1'
    $source = [IO.Path]::GetFullPath($source)
    if (-not (Test-Path -LiteralPath $source -PathType Leaf)) { throw "Vorhandener Ledger-Leser nicht gefunden: $source" }
    $result = & $source -TaskId $TaskId -AccountingDirectory $AccountingDirectory
    Write-SkillResponse $true $null $result
} catch {
    Write-SkillResponse $false ([ordered]@{ message = $_.Exception.Message }) $null
}
