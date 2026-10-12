[CmdletBinding()]
param(
    [string]$AdapterPath,
    [string]$TaskId,
    [string]$AccountingDirectory
)

$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = [System.Text.UTF8Encoding]::new($false)
$OutputEncoding = [System.Text.UTF8Encoding]::new($false)

try {
    if ([string]::IsNullOrWhiteSpace($AdapterPath) -or
        [string]::IsNullOrWhiteSpace($TaskId) -or
        [string]::IsNullOrWhiteSpace($AccountingDirectory)) {
        throw 'AdapterPath, TaskId, and AccountingDirectory are required.'
    }
    & $AdapterPath -TaskId $TaskId -AccountingDirectory $AccountingDirectory
}
catch {
    [Console]::Error.WriteLine($_.Exception.Message)
    $response = [ordered]@{
        isSuccessful = $false
        exception = [ordered]@{
            code = 'RunnerError'
            message = $_.Exception.Message
            phase = 'Adapter'
        }
        result = $null
    }
    [Console]::Out.WriteLine((ConvertTo-Json -InputObject $response -Compress -Depth 8))
    exit 1
}
