[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$AccountingDirectory,
    [Parameter(Mandatory)][string]$StorePath,
    [Parameter(Mandatory)][string]$RepositoryRoot,
    [Parameter(Mandatory)][string]$WorkItemId,
    [Parameter(Mandatory)][string]$ExecutionId,
    [Parameter(Mandatory)][string]$TaskId,
    [Parameter(Mandatory)][string]$ParentTaskId,
    [Parameter(Mandatory)][string]$ParentJobPath
)
$ErrorActionPreference = 'Stop'
$utf8 = New-Object Text.UTF8Encoding($false, $true)
$accounting = [IO.Path]::GetFullPath($AccountingDirectory)
$store = [IO.Path]::GetFullPath($StorePath)
New-Item -ItemType Directory -Path $accounting -Force | Out-Null
$identity = [Text.Encoding]::UTF8.GetBytes($store.ToLowerInvariant() + "`n" + $WorkItemId)
$key = ([BitConverter]::ToString(([Security.Cryptography.SHA256]::Create().ComputeHash($identity)))).Replace('-', '').ToLowerInvariant()
$bindingPath = Join-Path $accounting ('workitem-current-' + $key + '.json')
$lockPath = Join-Path $accounting ('workitem-current-' + $key + '.lock')
$lock = $null
try {
    $lock = [IO.File]::Open($lockPath, [IO.FileMode]::OpenOrCreate, [IO.FileAccess]::ReadWrite, [IO.FileShare]::None)
    Import-Module (Join-Path $PSScriptRoot '..\workitems\WorkItemStore.psm1') -Force
    $snapshot = Get-WorkItemStoreResult -Path $store -RepositoryRoot $RepositoryRoot
    $matches = @($snapshot.Document.items | Where-Object { $_.id -ceq $WorkItemId })
    if ($matches.Count -ne 1) { throw 'Current WorkItem missing or ambiguous.' }
    $item = $matches[0]
    if ($item.status -notin @('planned','in_progress','rework','blocked')) { throw 'WorkItem is not executable.' }
    $old = $null
    if ([IO.File]::Exists($bindingPath)) { $old = ConvertFrom-Json -InputObject $utf8.GetString([IO.File]::ReadAllBytes($bindingPath)) -ErrorAction Stop }
    if ($old -and $old.state -notin @('completed','failed','blocked')) { throw 'A prior WorkItem execution is not conclusively terminal.' }
    $record = [ordered]@{ kind='workitem-current-execution'; state='active'; executionId=$ExecutionId; taskId=$TaskId; parentTaskId=$ParentTaskId; parentJobPath=[IO.Path]::GetFullPath($ParentJobPath); storePath=$store; workItemId=$WorkItemId; startingRevision=$snapshot.Revision; startingImplementedAt=$item.implementedAt; startingSnapshot=$item; registeredAt=[DateTime]::UtcNow.ToString('o') }
    $temporary = $bindingPath + '.' + [guid]::NewGuid().ToString('N') + '.writing'
    [IO.File]::WriteAllText($temporary, ($record | ConvertTo-Json -Depth 40 -Compress), $utf8)
    if ([IO.File]::Exists($bindingPath)) { [IO.File]::Replace($temporary, $bindingPath, $null) } else { [IO.File]::Move($temporary, $bindingPath) }
    [pscustomobject]@{ path=$bindingPath; record=$record }
} finally {
    if ($lock) { $lock.Dispose() }
}
