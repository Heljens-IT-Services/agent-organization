Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'

function Invoke-CoordinatorPrivate($Module,[string]$Name,[object[]]$Arguments){& $Module {param($n,$a)$c=Get-Command $n -CommandType Function -ErrorAction Stop;& $c @a} $Name $Arguments}
function Import-CoordinatorWorkItemOutbox($Config){
    $path=[string]$Config.WorkItemStorePath;$root=[string]$Config.RepositoryRoot
    if(-not $path -or -not $root){return}
    $m=Import-Module (Join-Path $root 'scripts/workitems/WorkItemStore.psm1') -PassThru -Force
    $resolved=Invoke-CoordinatorPrivate $m 'Resolve-WorkItemStorePath' @($path,$root)
    $lock=Invoke-CoordinatorPrivate $m 'Enter-WorkItemStoreLock' @($resolved,5000)
    try {
        $snap=Invoke-CoordinatorPrivate $m 'Get-WorkItemStoreSnapshot' @($resolved,$root)
        Invoke-CoordinatorPrivate $m 'Resolve-WorkItemStoreOutbox' @($resolved,$snap)
        $box=Invoke-CoordinatorPrivate $m 'Get-WorkItemStoreOutbox' @($resolved)
        foreach($intent in @($box.intents|Where-Object{$_.state -ceq 'published'})){
            if($snap.Revision -cne $intent.candidateRevision){continue}
            $item=@($snap.Document.items|Where-Object{$_.id -ceq $intent.workItemId}|Select-Object -First 1)
            if(-not $item.Count){continue}
            $payload=@{workItemId=$intent.workItemId;revision=$intent.candidateRevision;item=$item[0]}
            $source='workitem:'+ $intent.workItemId+':'+$intent.candidateRevision
            Add-CoordinatorEvent -Path $Config.EventJournalPath -Kind workitem_changed -SourceId $source -Payload $payload|Out-Null
        }
    } finally {Invoke-CoordinatorPrivate $m 'Exit-WorkItemStoreLock' @($lock)}
}
function Invoke-CoordinatorAutomationIdle {
    param($Config,$Runtime,$Session,[string]$SessionPath)
    Import-CoordinatorWorkItemOutbox $Config
    $events=@(Get-CoordinatorPendingEvents -Path $Config.EventJournalPath -Limit 1)
    if(-not $events.Count){return}
    $event=$events[0];$claimId='host-'+$Session.LogicalSessionId
    try{$claimed=Claim-CoordinatorEvent -Path $Config.EventJournalPath -EventId $event.id -ClaimId $claimId -LeaseSeconds 3600}catch{return}
    $requestId='event-'+$event.id
    $inputText=ConvertTo-Json -InputObject ([ordered]@{eventId=$event.id;kind=$event.kind;sourceId=$event.sourceId;payload=$event.payload}) -Depth 40 -Compress
    $request=[pscustomobject]@{operation='SubmitInput';requestId=$requestId;logicalSessionId=$Session.LogicalSessionId;inputText=$inputText;source='coordinator-event';accountingDirectory=$Config.AccountingDirectory;parentTaskId=$Config.ParentTaskId}
    $result=Invoke-CoordinatorTurn $Runtime $Session $SessionPath $request
    if($result.status -eq 'BlockedRecovery' -or $result.classification -eq 'Unknown'){return}
    if($result.status -eq 'AccountingError'){throw 'AccountingError: terminal turn stored; event remains claimed for request-history reconciliation.'}
    if($result.status -in @('Accepted','Failed','Duplicate') -and $result.decision){Complete-CoordinatorEvent -Path $Config.EventJournalPath -EventId $event.id -ClaimId $claimId|Out-Null}
}
Export-ModuleMember -Function Invoke-CoordinatorAutomationIdle
