# Creates a source-bound recovery proposal, never changes session ownership.
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
    [string]$RepositoryRoot=(Split-Path -Parent (Split-Path -Parent $PSScriptRoot))
)
Import-Module (Join-Path $PSScriptRoot 'ProductManagement.psm1')
. (Join-Path $PSScriptRoot '../coordinator/Lifecycle.Persistence.ps1')
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
try {
    $prior=$null
    if ([IO.File]::Exists($path)) {
        $bytes=[IO.File]::ReadAllBytes($path)
        $prior=[ordered]@{path=$path;hash=(Get-LCHash $bytes);originalBase64=[Convert]::ToBase64String($bytes)}
    }
    $context=Get-ProductContext $binding $DataDirectory $DocumentIds $DecisionIds
    $plan=[ordered]@{kind='product-document-recovery-proposal-v1';solutionId=$binding.solution.solutionId;pmIdentity=$binding.solution.pmIdentity;configuration=$binding.configuration;workItemId=$WorkItemId;workItemSnapshot=[ordered]@{storePath=$StorePath;revision=$snapshot.Revision;document=$snapshot.Document};reason=$Reason;priorSession=$prior;context=$context;disposition='blocked_pending_owner_review';required=@('Owner confirms actual prior thread/turn and terminal release through registry/provider','Team leader reviews exact source hashes and rebuild context','Coordinator commissions bounded recovery WorkItem; no deletion of old session or fake thread ACK')}
    Save-LCImmutable (Join-Path $directory 'recovery-proposals') $plan
} finally { & $m {param($l)Exit-WorkItemStoreLock $l} $lock }
