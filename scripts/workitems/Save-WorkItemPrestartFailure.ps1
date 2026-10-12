[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$StorePath,
    [Parameter(Mandatory)][string]$RepositoryRoot,
    [Parameter(Mandatory)][string]$WorkItemId,
    [Parameter(Mandatory)][string]$TaskId,
    [Parameter(Mandatory)][string]$ParentTaskId,
    [Parameter(Mandatory)][string]$ExecutionId,
    [Parameter(Mandatory)][string]$ResultPath,
    [Parameter(Mandatory)][string]$ParentJobPath,
    [Parameter(Mandatory)][string]$AccountingDirectory,
    [Parameter(Mandatory)][string]$Reason
)
$ErrorActionPreference = 'Stop'
if ([string]::IsNullOrWhiteSpace($Reason)) { throw 'Prestart failure reason is required.' }
$utf8 = New-Object Text.UTF8Encoding($false, $true)
$store = [IO.Path]::GetFullPath($StorePath); $accounting = [IO.Path]::GetFullPath($AccountingDirectory)
$parentPath = [IO.Path]::GetFullPath($ParentJobPath); $result = [IO.Path]::GetFullPath($ResultPath)
if (-not [IO.File]::Exists($parentPath)) { throw 'Bound parent job is missing.' }
$parent = ConvertFrom-Json -InputObject $utf8.GetString([IO.File]::ReadAllBytes($parentPath)) -ErrorAction Stop
$parentId = ([guid]$ParentTaskId).ToString('N'); $childId = ([guid]$TaskId).ToString('N')
if ($parent.task_id -cne $parentId -or [IO.Path]::GetFullPath($parent.accounting_directory) -cne $accounting -or [IO.Path]::GetFullPath($parent.work_item_store_path) -cne $store -or [string]::IsNullOrWhiteSpace([string]$parent.role) -or [string]::IsNullOrWhiteSpace([string]$parent.work_item_id)) { throw 'Prestart failure parent task/store binding is invalid.' }
$parentActivePath = [IO.Path]::GetFullPath([string]$parent.result_file) + '.job.json.active.json'
if (-not [IO.File]::Exists($parentActivePath)) { throw 'Persisted parent active task identity is missing.' }
$parentActive = ConvertFrom-Json -InputObject $utf8.GetString([IO.File]::ReadAllBytes($parentActivePath)) -ErrorAction Stop
if ($parentActive.task_id -cne $parentId -or $parentActive.role -cne $parent.role -or $parentActive.work_item_id -cne $parent.work_item_id -or [IO.Path]::GetFullPath($parentActive.store_path) -cne $store -or [IO.Path]::GetFullPath($parentActive.accounting_directory) -cne $accounting) { throw 'Persisted parent active task binding is invalid.' }
$hash = [Security.Cryptography.SHA256]::Create().ComputeHash([Text.Encoding]::UTF8.GetBytes($ExecutionId))
$key = ([BitConverter]::ToString($hash)).Replace('-', '').ToLowerInvariant()
$reservationPath = Join-Path $accounting ('execution-' + $key + '.json')
$bindingIdentity = [Text.Encoding]::UTF8.GetBytes($store.ToLowerInvariant() + "`n" + $WorkItemId)
$bindingKey = ([BitConverter]::ToString(([Security.Cryptography.SHA256]::Create().ComputeHash($bindingIdentity)))).Replace('-', '').ToLowerInvariant()
$bindingPath = Join-Path $accounting ('workitem-current-' + $bindingKey + '.json')
if (-not [IO.File]::Exists($reservationPath) -or -not [IO.File]::Exists($bindingPath)) { throw 'Secured execution reservation or current binding is missing.' }
$reservation = ConvertFrom-Json -InputObject $utf8.GetString([IO.File]::ReadAllBytes($reservationPath)) -ErrorAction Stop
$binding = ConvertFrom-Json -InputObject $utf8.GetString([IO.File]::ReadAllBytes($bindingPath)) -ErrorAction Stop
if ($reservation.executionId -cne $ExecutionId -or $reservation.task_id -cne $childId -or $reservation.parent_task_id -cne $parentId -or $reservation.workItemId -cne $WorkItemId -or [IO.Path]::GetFullPath($reservation.store_path) -cne $store -or [IO.Path]::GetFullPath($reservation.result_path) -cne $result -or [IO.Path]::GetFullPath($reservation.parent_job_path) -cne $parentPath -or [IO.Path]::GetFullPath($reservation.current_binding_path) -cne $bindingPath) { throw 'Prestart failure does not match the persisted execution reservation.' }
if ($binding.kind -cne 'workitem-current-execution' -or $binding.executionId -cne $ExecutionId -or $binding.taskId -cne $childId -or $binding.parentTaskId -cne $parentId -or [IO.Path]::GetFullPath($binding.parentJobPath) -cne $parentPath -or $binding.workItemId -cne $WorkItemId -or [IO.Path]::GetFullPath($binding.storePath) -cne $store) { throw 'Prestart failure does not match the persisted current binding.' }
$role = [string]$reservation.role
if (-not $role -or $role -ceq [string]$parent.role) { throw 'Reserved child role is missing or equals the parent role.' }
if ([IO.File]::Exists($result)) {
    $savedResult = ConvertFrom-Json -InputObject $utf8.GetString([IO.File]::ReadAllBytes($result)) -ErrorAction Stop
    if ($savedResult.task_id -cne $childId -or $savedResult.parent_task_id -cne $parentId -or $savedResult.work_item_id -cne $WorkItemId -or $savedResult.execution_id -cne $ExecutionId -or $savedResult.terminal_outcome -notin @('failed','blocked') -or $savedResult.model_started -eq $true) { throw 'Existing result path is not the matching prestart failure result.' }
}
Import-Module (Join-Path $PSScriptRoot 'WorkItemStore.psm1') -Force
$snapshot = Get-WorkItemStoreResult -Path $store -RepositoryRoot $RepositoryRoot
$items = @($snapshot.Document.items | Where-Object { $_.id -ceq $WorkItemId })
if ($items.Count -ne 1) { throw 'WorkItem missing or ambiguous.' }
$item = $items[0]
if ($item.owner.type -cne 'agent' -or $item.owner.id -cne $role) { throw 'Failed child role does not own this WorkItem.' }
$seen = @{}; $cursor = $item; $foundParent = $false
while ($null -ne $cursor.parentId) {
    $id = [string]$cursor.id
    if ($seen.ContainsKey($id)) { throw 'WorkItem ancestry contains a cycle.' }
    $seen[$id] = $true
    if ($cursor.parentId -ceq $parent.work_item_id) { $foundParent = $true }
    $next = @($snapshot.Document.items | Where-Object { $_.id -ceq $cursor.parentId })
    if ($next.Count -ne 1) { throw 'WorkItem ancestry is incomplete.' }
    $cursor = $next[0]
}
if (-not $foundParent) { throw 'WorkItem is not below the persisted parent WorkItem.' }
$recordPath = Join-Path $accounting ('prestart-failure-' + $key + '.json')
$record = $null; $recordReplay = $false
if ([IO.File]::Exists($recordPath)) {
    $existing = ConvertFrom-Json -InputObject $utf8.GetString([IO.File]::ReadAllBytes($recordPath)) -ErrorAction Stop
    if ($existing.executionId -cne $ExecutionId -or $existing.taskId -cne $childId -or $existing.parentTaskId -cne $parentId -or $existing.workItemId -cne $WorkItemId -or $existing.storePath -cne $store -or $existing.resultPath -cne $result -or $existing.parentJobPath -cne $parentPath -or $existing.reason -cne $Reason) { throw 'Existing prestart failure record conflicts.' }
    if ($item.status -ceq 'blocked' -and $item.blockReason -ceq $Reason) {
        if (-not [IO.File]::Exists($result)) {
            $prestartEvidence = [ordered]@{ task_id=$childId; parent_task_id=$parentId; work_item_id=$WorkItemId; execution_id=$ExecutionId; parent_job_task_id=$parentId; parent_job_path=$parentPath; work_item_store_path=$store; accounting_directory=$accounting; role=$role; model_started=$false; thread_id=$null; turn_id=$null; terminal_outcome='failed'; success=$false; output=$null; error=$Reason; prestart_failure_record_path=$recordPath }
            $resultDirectory = Split-Path -Parent $result
            if ($resultDirectory) { New-Item -ItemType Directory -Path $resultDirectory -Force | Out-Null }
            $resultStream = New-Object IO.FileStream($result, [IO.FileMode]::CreateNew, [IO.FileAccess]::Write, [IO.FileShare]::None)
            try { $resultBytes = $utf8.GetBytes(($prestartEvidence | ConvertTo-Json -Depth 30 -Compress)); $resultStream.Write($resultBytes,0,$resultBytes.Length); $resultStream.Flush($true) } finally { $resultStream.Dispose() }
        }
        if ($binding.state -ceq 'active') { $binding.state = 'failed'; $binding.finishedAt = [DateTime]::UtcNow.ToString('o'); [IO.File]::WriteAllText($bindingPath, ($binding | ConvertTo-Json -Depth 40 -Compress), $utf8) }
        if ($reservation.state -ne 'failed' -or $reservation.failure_record_path -cne $recordPath) { $reservation.state = 'failed'; $reservation.failure_record_path = $recordPath; $reservation.failure_recorded_at = [DateTime]::UtcNow.ToString('o'); [IO.File]::WriteAllText($reservationPath, ($reservation | ConvertTo-Json -Depth 30 -Compress), $utf8) }
        return [pscustomobject]@{ persisted=$true; outcome='failed'; unchanged=$true; recordPath=$recordPath; revision=$snapshot.Revision; workItemId=$WorkItemId; executionId=$ExecutionId }
    }
    if ($binding.state -cne 'active' -or $reservation.state -notin @('reserved','failed') -or $item.status -in @('accepted','cancelled')) { throw 'Existing prestart failure record cannot be safely replayed against the current WorkItem.' }
    $record = $existing; $recordReplay = $true
}
if ($binding.state -cne 'active' -or $reservation.state -notin @('reserved','failed')) { throw 'Execution is not the active or explicitly replayable prestart attempt.' }
if ($item.status -ceq 'blocked' -and $item.blockReason -ceq $Reason) { throw 'Matching blocked state lacks its correlated prestart record; refusing to infer ownership.' }
if ($item.status -in @('accepted','cancelled')) { throw 'Terminal WorkItem cannot receive a prestart failure mutation.' }
$now = [DateTime]::UtcNow.ToString('yyyy-MM-ddTHH:mm:ss.fffffffZ')
if (-not $recordReplay) {
    $record = [ordered]@{ kind='prestart-failure'; outcome='failed'; taskId=$childId; parentTaskId=$parentId; executionId=$ExecutionId; workItemId=$WorkItemId; storePath=$store; resultPath=$result; parentJobPath=$parentPath; childRole=$role; parentRole=[string]$parent.role; sourceRevision=$snapshot.Revision; reason=$Reason; recordedAt=$now }
    $recordBytes = $utf8.GetBytes(($record | ConvertTo-Json -Depth 20 -Compress))
    $recordStream = New-Object IO.FileStream($recordPath, [IO.FileMode]::CreateNew, [IO.FileAccess]::Write, [IO.FileShare]::None)
    try { $recordStream.Write($recordBytes, 0, $recordBytes.Length); $recordStream.Flush($true) } finally { $recordStream.Dispose() }
}
if (-not [IO.File]::Exists($result)) {
    $prestartEvidence = [ordered]@{
        task_id=$childId; parent_task_id=$parentId; work_item_id=$WorkItemId; execution_id=$ExecutionId
        parent_job_task_id=$parentId; parent_job_path=$parentPath; work_item_store_path=$store
        accounting_directory=$accounting; role=$role; model_started=$false; thread_id=$null; turn_id=$null
        terminal_outcome='failed'; success=$false; output=$null; error=$Reason; prestart_failure_record_path=$recordPath
    }
    $resultDirectory = Split-Path -Parent $result
    if ($resultDirectory) { New-Item -ItemType Directory -Path $resultDirectory -Force | Out-Null }
    $resultStream = New-Object IO.FileStream($result, [IO.FileMode]::CreateNew, [IO.FileAccess]::Write, [IO.FileShare]::None)
    try { $resultBytes = $utf8.GetBytes(($prestartEvidence | ConvertTo-Json -Depth 30 -Compress)); $resultStream.Write($resultBytes,0,$resultBytes.Length); $resultStream.Flush($true) } finally { $resultStream.Dispose() }
}
$item.status='blocked'; $item.blockReason=$Reason; $item.updatedAt=$now
try { $write = Set-WorkItemStoreEntry -Path $store -Id $WorkItemId -Item $item -ExpectedRevision $snapshot.Revision -RepositoryRoot $RepositoryRoot }
catch { throw ('Failure record retained; WorkItem store publication failed: ' + $_.Exception.Message) }
$binding.state = 'failed'; $binding.finishedAt = [DateTime]::UtcNow.ToString('o')
$binding.failureRecordPath = $recordPath; $binding.resultPath = $result
[IO.File]::WriteAllText($bindingPath, ($binding | ConvertTo-Json -Depth 40 -Compress), $utf8)
$reservation.failure_record_path = $recordPath; $reservation.failure_recorded_at = [DateTime]::UtcNow.ToString('o'); $reservation.state = 'failed'
[IO.File]::WriteAllText($reservationPath, ($reservation | ConvertTo-Json -Depth 30 -Compress), $utf8)
[pscustomobject]@{ persisted=$true; outcome='failed'; delivered=$false; recordPath=$recordPath; revision=$write.Revision; workItemId=$WorkItemId; executionId=$ExecutionId }
