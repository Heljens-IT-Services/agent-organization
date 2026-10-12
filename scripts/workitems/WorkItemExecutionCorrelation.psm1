$ErrorActionPreference = 'Stop'
$script:CorrelationEncoding = New-Object Text.UTF8Encoding($false, $true)

function Get-WorkItemExecutionCorrelationPath {
    param([string]$AccountingDirectory, [string]$ExecutionId)
    $digest = [Security.Cryptography.SHA256]::Create().ComputeHash([Text.Encoding]::UTF8.GetBytes($ExecutionId))
    $key = ([BitConverter]::ToString($digest)).Replace('-', '').ToLowerInvariant()
    return Join-Path ([IO.Path]::GetFullPath($AccountingDirectory)) ('workitem-transfer-' + $key + '.json')
}

function Read-WorkItemExecutionCorrelation {
    param([string]$Path)
    if (-not [IO.File]::Exists($Path)) { return $null }
    try { return ConvertFrom-Json -InputObject $script:CorrelationEncoding.GetString([IO.File]::ReadAllBytes($Path)) -ErrorAction Stop }
    catch { throw 'Persisted execution correlation is unreadable; refusing a second WorkItem mutation.' }
}

function Write-WorkItemExecutionCorrelation {
    param([string]$Path, $Record, [bool]$Create)
    $bytes = $script:CorrelationEncoding.GetBytes(($Record | ConvertTo-Json -Depth 20 -Compress))
    if ($Create) {
        $stream = New-Object IO.FileStream($Path, [IO.FileMode]::CreateNew, [IO.FileAccess]::Write, [IO.FileShare]::None)
        try { $stream.Write($bytes, 0, $bytes.Length); $stream.Flush($true) } finally { $stream.Dispose() }
        return
    }
    $temp = $Path + '.' + [guid]::NewGuid().ToString('N') + '.tmp'
    [IO.File]::WriteAllBytes($temp, $bytes)
    try { [IO.File]::Replace($temp, $Path, $null) } finally { if ([IO.File]::Exists($temp)) { [IO.File]::Delete($temp) } }
}

Export-ModuleMember -Function Get-WorkItemExecutionCorrelationPath, Read-WorkItemExecutionCorrelation, Write-WorkItemExecutionCorrelation
