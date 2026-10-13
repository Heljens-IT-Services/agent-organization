# A reviewed hypothesis becomes a WorkItem for the product team leader.
# The existing outbox/event dispatcher and visible Starter perform routing.
[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)][string]$ConfigurationPath,
    [Parameter(Mandatory=$true)][string]$ConfigurationHash,
    [Parameter(Mandatory=$true)][string]$ContextWorkItemId,
    [Parameter(Mandatory=$true)][string]$DataDirectory,
    [Parameter(Mandatory=$true)][string]$DecisionId,
    [Parameter(Mandatory=$true)][string]$Id,
    [Parameter(Mandatory=$true)][string]$ReviewWorkItemId,
    [Parameter(Mandatory=$true)][string]$ParentId,
    [Parameter(Mandatory=$true)][string]$Title,
    [Parameter(Mandatory=$true)][string]$Hypothesis,
    [Parameter(Mandatory=$true)][string]$OutcomeMetric,
    [Parameter(Mandatory=$true)][string]$OutcomeTarget,
    [Parameter(Mandatory=$true)][string]$ReviewDueAt,
    [Parameter(Mandatory=$true)][string]$StorePath,
    [Parameter(Mandatory=$true)][string]$ExpectedRevision,
    [string]$RepositoryRoot=(Split-Path -Parent (Split-Path -Parent $PSScriptRoot))
)
Import-Module (Join-Path $PSScriptRoot 'ProductManagement.psm1')
. (Join-Path $PSScriptRoot '../coordinator/Lifecycle.Persistence.ps1')
$snapshot=& (Join-Path $PSScriptRoot '../workitems/Get-WorkItems.ps1') -Path $StorePath -RepositoryRoot $RepositoryRoot
if ($ExpectedRevision -cne $snapshot.Revision) { throw 'ProductFeatureRevisionConflict' }
if ($Id -notmatch '^[a-z0-9][a-z0-9_-]{0,127}$' -or $ReviewWorkItemId -notmatch '^[a-z0-9][a-z0-9_-]{0,127}$' -or $Id -ceq $ReviewWorkItemId -or @($snapshot.Document.items | Where-Object { $_.id -ceq $Id -or $_.id -ceq $ReviewWorkItemId }).Count) { throw 'ProductFeatureOrReviewIdConflict' }
$reference=[pscustomobject]@{path=$ConfigurationPath;hash=$ConfigurationHash}
$binding=Get-ProductBinding $reference $ContextWorkItemId @($snapshot.Document.items)
if (-not $binding) { throw 'ProductSolutionAssignmentMissing' }
$context=Get-ProductContext $binding $DataDirectory @() @($DecisionId)
if ($context.decisions.Count -ne 1) { throw 'ProductFeatureNeedsAcceptedDecision' }
$decision=$context.decisions[0]
if (@($snapshot.Document.items | Where-Object { $_.id -ceq $ParentId }).Count -ne 1) { throw 'ProductFeatureParentMissing' }
$parentBinding=Get-ProductBinding $reference $ParentId @($snapshot.Document.items)
if (-not $parentBinding -or $parentBinding.solution.solutionId -cne $binding.solution.solutionId -or $parentBinding.solution.pmIdentity -cne $binding.solution.pmIdentity) { throw 'ProductFeatureParentSolutionConflict' }
# Old content-only receipts need a fresh scoped review; no implicit migration.
$envelope=Get-LCValue $decision.entry 'envelope'
if (-not $envelope -or $envelope.kind -cne 'product-decision-envelope-v1' -or $envelope.solutionId -cne $binding.solution.solutionId -or $envelope.pmIdentity -cne $binding.solution.pmIdentity -or $envelope.configuration.path -cne $reference.path -or $envelope.configuration.hash -cne $reference.hash -or (Get-LCHash (Get-LCBytes $envelope)) -cne $decision.entry.decisionHash) { throw 'ProductFeatureDecisionEnvelopeConflict' }
$review=Assert-ProductReviewBinding $binding $snapshot $decision.entry.review.workItemId $decision.entry.decisionHash
$due=[DateTimeOffset]::Parse($ReviewDueAt).UtcDateTime.ToString('o')
$now=[DateTime]::UtcNow.ToString('o')
$spec=[ordered]@{solutionId=$context.solutionId;pmIdentity=$context.pmIdentity;configuration=$reference;featureWorkItemId=$Id;reviewWorkItemId=$ReviewWorkItemId;hypothesis=$Hypothesis;decision=$decision.reference;outcomeMetric=$OutcomeMetric;outcomeTarget=$OutcomeTarget;reviewDueAt=$due;handoff='Product team leader selects PO; specialist team WorkItems go through coordinator. Review effects against outcome; do not infer success from delivery.'}
$item=[ordered]@{
    id=$Id;parentId=$ParentId;title=$Title;description=$Hypothesis;owner=@{type='agent';id='teamleiter_produktmanagement'}
    goal=@{description=$Hypothesis;metric=$OutcomeMetric;target=$OutcomeTarget};priority='normal';dependencies=@($review.id)
    specification=@{inline=(ConvertTo-Json -InputObject $spec -Depth 30 -Compress)}
    acceptanceCriteria=@(@{id='strategy';description='Backlog scope traces to the exact reviewed strategy decision and sources'},@{id='handoff';description='PO result reviewed by product team leader; specialist execution commissioned only via coordinator'})
    status='planned';result=$null;verifications=@();humanInteraction=$null;blockReason=$null;createdAt=$now;updatedAt=$now;implementedAt=$null;acceptedAt=$null;dueAt=$null
}
$outcomeReview=[ordered]@{
    id=$ReviewWorkItemId;parentId=$ParentId;title=('Outcome review: '+$Title);description=$Hypothesis;owner=@{type='agent';id='teamleiter_produktmanagement'}
    goal=@{description='Observe feature outcome';metric=$OutcomeMetric;target=$OutcomeTarget};priority='normal';dependencies=@($Id)
    specification=@{inline=(ConvertTo-Json -InputObject $spec -Depth 30 -Compress)}
    acceptanceCriteria=@(@{id='outcome';description='Document observed outcome against bound metric, target, feature and decision; unknown measurement remains open'})
    status='planned';result=$null;verifications=@();humanInteraction=$null;blockReason=$null;createdAt=$now;updatedAt=$now;implementedAt=$null;acceptedAt=$null;dueAt=$due
}
# Existing writer publishes each CAS change through its outbox. Two writes are not atomic.
$featureWrite=& (Join-Path $PSScriptRoot '../workitems/New-WorkItem.ps1') -Path $StorePath -Item $item -ExpectedRevision $ExpectedRevision -RepositoryRoot $RepositoryRoot
try {
    $reviewWrite=& (Join-Path $PSScriptRoot '../workitems/New-WorkItem.ps1') -Path $StorePath -Item $outcomeReview -ExpectedRevision $featureWrite.Revision -RepositoryRoot $RepositoryRoot
} catch { throw ('ProductOutcomeReviewPublicationIncomplete: feature='+$Id+'; review='+$ReviewWorkItemId+'; revision='+$featureWrite.Revision+'; preserve feature and resolve missing review through existing writer: '+$_.Exception.Message) }
[pscustomobject]@{feature=$featureWrite;outcomeReview=$reviewWrite}
