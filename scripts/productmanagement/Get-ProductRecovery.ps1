# Creates a source-bound proposal; optional intent preparation uses existing locks.
[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)][string]$ConfigurationPath,
    [Parameter(Mandatory=$true)][string]$ConfigurationHash,
    [Parameter(Mandatory=$true)][string]$WorkItemId,
    [Parameter(Mandatory=$true)][string]$DataDirectory,
    [Parameter(Mandatory=$true)][string[]]$DocumentIds,
    [string[]]$DecisionIds,
    [Parameter(Mandatory=$true)][string]$Reason,
    [Parameter(Mandatory=$true)][string]$StorePath,
    [Parameter(Mandatory=$true)][string]$ExpectedRevision,
    [switch]$PrepareIntent,
    [string]$ExpectedSessionHash,
    [string]$RepositoryRoot=(Split-Path -Parent (Split-Path -Parent $PSScriptRoot))
)
Import-Module (Join-Path $PSScriptRoot 'ProductManagement.psm1')
. (Join-Path $PSScriptRoot '../coordinator/Lifecycle.Persistence.ps1')
if (-not [IO.Path]::IsPathRooted($StorePath)) { throw 'ProductWorkItemStorePathUnresolved' }
$StorePath=[IO.Path]::GetFullPath($StorePath)
$snapshot=& (Join-Path $PSScriptRoot '../workitems/Get-WorkItems.ps1') -Path $StorePath -RepositoryRoot $RepositoryRoot
if (-not $snapshot.Exists -or $ExpectedRevision -cne $snapshot.Revision) { throw 'ProductRecoveryRevisionConflict' }
if (@($snapshot.Document.items | Where-Object { $_.id -ceq $WorkItemId }).Count -ne 1) { throw 'ProductRecoveryWorkItemMissing' }
$binding=Get-ProductBinding ([pscustomobject]@{path=$ConfigurationPath;hash=$ConfigurationHash}) $WorkItemId @($snapshot.Document.items)
if (-not $binding) { throw 'ProductSolutionAssignmentMissing' }
$directory=Initialize-ProductDirectory $DataDirectory $binding.solution.solutionId
$path=Join-Path $directory 'session.json'
# Stable read: same private store lock used by the visible PM runner.
$m=Import-Module (Join-Path $PSScriptRoot '../workitems/WorkItemStore.psm1') -PassThru
$lock=& $m {param($p)Enter-WorkItemStoreLock $p 5000} $path
$storeLock=$null
try {
    # Session -> store lock order matches the admitted PM activation path.
    $storeLock=& $m {param($p)Enter-WorkItemStoreLock $p 5000} $StorePath
    $snapshot=& $m {param($p,$root)Get-WorkItemStoreSnapshot $p $root} $StorePath $RepositoryRoot
    if (-not $snapshot.Exists -or $ExpectedRevision -cne $snapshot.Revision) { throw 'ProductRecoveryRevisionConflict' }
    $binding=Get-ProductBinding ([pscustomobject]@{path=$ConfigurationPath;hash=$ConfigurationHash}) $WorkItemId @($snapshot.Document.items)
    if (-not $binding) { throw 'ProductSolutionAssignmentMissing' }
    $owned=@($snapshot.Document.items | Where-Object { $_.id -ceq $WorkItemId -and $_.owner.id -ceq 'produktmanagement_pm_strategie' -and $_.status -in @('planned','in_progress','rework') })
    if ($PrepareIntent -and $owned.Count -ne 1) { throw 'ProductRecoveryPMWorkItemOwnerOrStateChanged' }
    $prior=$null
    if ([IO.File]::Exists($path)) {
        $bytes=[IO.File]::ReadAllBytes($path)
        $prior=[ordered]@{path=$path;hash=(Get-LCHash $bytes);originalBase64=[Convert]::ToBase64String($bytes)}
    }
    $context=Get-ProductContext $binding $DataDirectory $DocumentIds $DecisionIds
    $plan=[ordered]@{kind='product-document-recovery-proposal-v1';solutionId=$binding.solution.solutionId;pmIdentity=$binding.solution.pmIdentity;configuration=$binding.configuration;workItemId=$WorkItemId;workItemSnapshot=[ordered]@{storePath=[IO.Path]::GetFullPath($StorePath);revision=$snapshot.Revision;document=$snapshot.Document};reason=$Reason;priorSession=$prior;context=$context;disposition='requires_version_bound_definitive_resume_denial';required=@('Documented definitive denial for the pinned runtime and exact old thread','Existing local terminal/registry release and runner-end lifecycle; no additional provider OwnerReceipt','Fresh configuration/context/WorkItem/session CAS; admitted existing starter only')}
    $proposal=Save-LCImmutable (Join-Path $directory 'recovery-proposals') $plan
    $intent=$null
    if ($PrepareIntent) {
        if (-not $prior -or $ExpectedSessionHash -notmatch '^[a-f0-9]{64}$' -or $ExpectedSessionHash -cne $prior.hash) { throw 'ProductRecoverySessionCASConflict' }
        $intent=Save-ProductRecoveryIntent $plan $directory $path
    }
    [pscustomobject]@{proposal=$proposal;intent=$intent;replacementAuthorized=$false}
} finally {
    if ($storeLock) { & $m {param($l)Exit-WorkItemStoreLock $l} $storeLock }
    & $m {param($l)Exit-WorkItemStoreLock $l} $lock
}
