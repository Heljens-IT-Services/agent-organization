[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$Path,
    [Parameter(Mandatory)][string]$RepositoryRoot,
    [Parameter(Mandatory)][string]$WorkItemId,
    [Parameter(Mandatory)][string]$ExpectedRevision,
    [Parameter(Mandatory)]$Verification
)
$ErrorActionPreference = 'Stop'
$jobPath = $env:AGENT_ORG_PARENT_JOB_FILE
if (-not $jobPath -or -not (Test-Path -LiteralPath $jobPath -PathType Leaf)) { throw 'Persistent caller job is required for parent acceptance.' }
$utf8 = New-Object Text.UTF8Encoding($false, $true)
$job = ConvertFrom-Json -InputObject $utf8.GetString([IO.File]::ReadAllBytes($jobPath)) -ErrorAction Stop
if ($job.work_item_id -cne $WorkItemId -or [string]::IsNullOrWhiteSpace([string]$job.task_id) -or [string]::IsNullOrWhiteSpace([string]$job.role)) { throw 'Caller is not bound to this parent WorkItem.' }
$activePath = [IO.Path]::GetFullPath([string]$job.result_file) + '.job.json.active.json'
if (-not [IO.File]::Exists($activePath)) { throw 'Current parent task lacks persisted thread/turn identity.' }
$active = ConvertFrom-Json -InputObject $utf8.GetString([IO.File]::ReadAllBytes($activePath)) -ErrorAction Stop
if ($active.task_id -cne $job.task_id -or $active.role -cne $job.role -or [string]::IsNullOrWhiteSpace([string]$active.thread_id) -or [string]::IsNullOrWhiteSpace([string]$active.turn_id)) { throw 'Current parent thread/turn binding is invalid.' }
Import-Module (Join-Path $PSScriptRoot 'WorkItemStore.psm1') -Force
$path = [IO.Path]::GetFullPath($Path)
$snapshot = Get-WorkItemStoreResult -Path $path -RepositoryRoot $RepositoryRoot
if ($snapshot.Revision -cne $ExpectedRevision) { throw 'Parent verification ExpectedRevision does not match the current store.' }
if ([IO.Path]::GetFullPath($job.work_item_store_path) -cne $path) { throw 'Caller job store binding mismatch.' }
$parents = @($snapshot.Document.items | Where-Object { $_.id -ceq $WorkItemId })
if ($parents.Count -ne 1) { throw 'Parent WorkItem missing or ambiguous.' }
$parent = $parents[0]
if ($parent.owner.type -cne 'agent' -or $parent.owner.id -cne $job.role) { throw 'Acceptance caller does not own parent WorkItem.' }
if ([IO.Path]::GetFullPath($job.work_item_store_path) -cne [IO.Path]::GetFullPath($Path)) { throw 'Current job store binding mismatch.' }
$parentJobPath = [IO.Path]::GetFullPath([string]$job.parent_job_path)
if (-not [IO.File]::Exists($parentJobPath)) { throw 'Persistent parent job is missing.' }
$previousJob = ConvertFrom-Json -InputObject $utf8.GetString([IO.File]::ReadAllBytes($parentJobPath)) -ErrorAction Stop
if ($previousJob.task_id -cne $job.parent_task_id -or [IO.Path]::GetFullPath($previousJob.accounting_directory) -cne [IO.Path]::GetFullPath($job.accounting_directory) -or ($previousJob.work_item_id -and $parent.parentId -cne $previousJob.work_item_id)) { throw 'WorkItem parent task chain does not bind this acceptance.' }
$children = @($snapshot.Document.items | Where-Object { $_.parentId -ceq $WorkItemId })
$openChildren = @($children | Where-Object { $_.status -cnotin @('accepted','cancelled') })
if ($openChildren.Count) { throw ('Parent review blocked by unfinished children: ' + (@($openChildren | ForEach-Object id) -join ', ')) }
. (Join-Path $PSScriptRoot 'HumanInteraction.ps1')
if (-not (Test-HISatisfied $parent.humanInteraction)) { throw 'Unresolved humanInteraction blocks parent acceptance.' }
Assert-HIProposalCurrent $parent.humanInteraction
$criteria = @($parent.acceptanceCriteria)
foreach ($required in @('implementedAt','checkedAt','reviewer','passed','results')) { if (-not $Verification.PSObject.Properties[$required]) { throw "Verification lacks required bound field $required." } }
if ($Verification.passed -isnot [bool] -or $Verification.reviewer -isnot [pscustomobject] -or $Verification.reviewer.type -cne 'agent' -or $Verification.reviewer.id -cne $job.role) { throw 'Verification reviewer or passed value is not the caller identity and a strict boolean.' }
$checkedTime = [DateTimeOffset]::MinValue; $implementationTime = [DateTimeOffset]::MinValue
if (-not [DateTimeOffset]::TryParse([string]$Verification.checkedAt, [Globalization.CultureInfo]::InvariantCulture, [Globalization.DateTimeStyles]::RoundtripKind, [ref]$checkedTime) -or $checkedTime.Offset -ne [TimeSpan]::Zero -or -not [DateTimeOffset]::TryParse([string]$Verification.implementedAt, [Globalization.CultureInfo]::InvariantCulture, [Globalization.DateTimeStyles]::RoundtripKind, [ref]$implementationTime) -or $implementationTime.Offset -ne [TimeSpan]::Zero) { throw 'Verification timestamps must be valid exact UTC values.' }
if ($null -eq $Verification.results -or @($Verification.results).Count -ne $criteria.Count) { throw 'Complete criterion-by-criterion verification is required.' }
$ids = @($Verification.results | ForEach-Object { [string]$_.criterionId })
if (@($ids | Select-Object -Unique).Count -ne $criteria.Count) { throw 'Verification criterion IDs must be unique.' }
$allPassed = $true
foreach ($criterion in $criteria) {
    $proof = @($Verification.results | Where-Object { $_.criterionId -ceq $criterion.id })
    if ($proof.Count -ne 1 -or $proof[0].passed -isnot [bool] -or [string]::IsNullOrWhiteSpace([string]$proof[0].evidence)) { throw "Invalid current evidence for criterion $($criterion.id)." }
    if (-not $proof[0].passed) { $allPassed = $false }
}
if (@($ids | Where-Object { $_ -notin @($criteria | ForEach-Object id) }).Count) { throw 'Unknown verification criterion supplied.' }
if ($parent.status -cne 'implemented' -or $null -eq $parent.implementedAt) { throw 'Only a currently implemented parent can be accepted.' }
if ($Verification.implementedAt -cne $parent.implementedAt -or $implementationTime -gt $checkedTime -or $checkedTime -gt [DateTimeOffset]::UtcNow) { throw 'Verification implementation time or checkedAt is stale, future dated, or differs from the current implementation.' }
$now = [string]$Verification.checkedAt
$check = [pscustomobject]@{
    implementedAt=[string]$Verification.implementedAt; checkedAt=[string]$Verification.checkedAt
    reviewer=$Verification.reviewer
    passed=$Verification.passed; results=@($Verification.results | ForEach-Object { [pscustomobject]@{ criterionId=[string]$_.criterionId; passed=$_.passed; evidence=[string]$_.evidence } })
}
if ($Verification.passed -ne $allPassed) { throw 'Verification.passed must equal the conjunction of criterion results.' }
$parent.verifications = @($parent.verifications) + @($check)
if ($allPassed) { $parent.status='accepted'; $parent.acceptedAt=$now; $parent.blockReason=$null }
else { $parent.status='rework'; $parent.acceptedAt=$null; $parent.blockReason=$null }
$parent.updatedAt=$now
$writeResult = Set-WorkItemStoreEntry -Path $path -Id $WorkItemId -Item $parent -ExpectedRevision $snapshot.Revision -RepositoryRoot $RepositoryRoot
[pscustomobject]@{ persisted=$true; workItemId=$WorkItemId; revision=$writeResult.Revision; accepted=($allPassed -and $parent.status -eq 'accepted'); rework=(-not $allPassed); openChildren=@($openChildren | ForEach-Object id); verification=$check }
