function Get-LCNoSpawnResumePrior($Config,$Prior,$Registered,$Command,$Plan,$Session,$TerminalContext,$DecisionRef) {
    $directory=Join-Path $Config.DataDirectory 'resume-receipts'
    $binder=Join-Path $directory ($Command.effectId+'.prior-nospawn.ref.json')
    $commandHash=Get-LCHash (Get-LCBytes $Command)
    if([IO.File]::Exists($binder)){
        $ref=Read-AutomationJson $binder $null;$saved=Read-LCReceipt $ref
        if($saved.kind -cne 'resume-prior-nospawn-closure-v1' -or $saved.effectId -cne $Command.effectId -or $saved.commandHash -cne $commandHash -or $saved.planHash -cne $Plan.planHash -or $saved.sourceRevision -cne $Plan.baseRevision -or $saved.priorExecutionId -cne $Command.priorExecutionId -or [int]$saved.priorGeneration -ne [int]$Command.priorGeneration -or $saved.workItemId -cne $Command.workItemId -or $saved.logicalSessionId -cne $Session.LogicalSessionId -or $saved.rootTaskId -cne $Session.RootTaskId -or $saved.coordinatorJobPath -cne $Session.CoordinatorJobPath -or $saved.coordinatorJobHash -cne $Session.CoordinatorJobHash -or $saved.terminalContext.hash -cne $TerminalContext.hash -or $saved.terminalDecision.hash -cne $DecisionRef.hash){throw 'ResumeNoSpawnClosureReplayConflict'}
        return $ref
    }
    if($Prior.state -cne 'Returned' -or $Prior.terminalDecision -cne 'prestart-failed' -or $Prior.launchBinding -or $Prior.runningAtUtc -or $Prior.purpose -cne 'teamleiter-workitem'){throw 'ResumeNoSpawnPriorNotClosed'}
    $v=$Prior.returnValue
    $rm=Import-Module (Join-Path $PSScriptRoot '..\workitems\WorkItemPrestartRecovery.psm1') -PassThru -Force
    $g=& $rm {param($v,$repo)Assert-PrestartFailureCommit $v.noSpawnReceiptPath $v.noSpawnReceiptHash $v.failureCommitPath $v.failureCommitHash $repo -HistoricalStoreReceipt} $v $Config.RepositoryRoot
    $r=$g.receipt
    $cm=Import-Module (Join-Path $PSScriptRoot '..\workitems\CoordinatorExecutionContext.psm1') -PassThru -Force
    $root=& $cm {param($r)Assert-ExecutionAncestors $r.parentContextPath $r.parentContextHash $r.storePath $r.accountingDirectory -MaxLevels 2} $r
    $authority=& $cm {param($r)Read-DelegatedStartAuthority $r.startIntentPath $r.startIntentHash} $r
    if($r.executionId -cne $Command.priorExecutionId -or $r.workItemId -cne $Command.workItemId -or $r.storePath -cne [IO.Path]::GetFullPath($Config.WorkItemStorePath) -or $r.accountingDirectory -cne [IO.Path]::GetFullPath($Config.AccountingDirectory) -or $r.registryDirectory -cne [IO.Path]::GetFullPath($Config.RegistryDirectory) -or $r.dispatchJournalPath -cne [IO.Path]::GetFullPath((Join-Path $Config.DataDirectory 'dispatch-journal.json')) -or $r.eventJournalPath -cne [IO.Path]::GetFullPath($Config.EventJournalPath) -or $root.logicalSessionId -cne $Session.LogicalSessionId -or $root.taskId -cne $Session.RootTaskId -or $root.jobPath -cne $Session.CoordinatorJobPath -or $root.jobHash -cne $Session.CoordinatorJobHash -or [int]$authority.parameters.Generation -ne [int]$Command.priorGeneration -or $authority.parameters.Purpose -cne 'teamleiter-workitem' -or $r.effectContext.effectId -cne ('prestart:'+ $Command.priorExecutionId)){throw 'ResumeNoSpawnAuthorityEpochConflict'}
    if(([guid]$Prior.taskId).ToString('N') -cne $r.taskId -or $Prior.input.payloadHash -cne $r.payloadHash -or $Prior.input.parentContextHash -cne $r.parentContextHash -or $Prior.input.authorityHash -cne $r.startIntentHash -or [IO.Path]::GetFullPath($Prior.input.resultPath) -cne $r.resultPath){throw 'ResumeNoSpawnDispatchBindingConflict'}
    foreach($n in @('taskId','resultPath','resultHash','payloadHash','parentContextHash','startIntentHash','startAttemptHash','noSpawnAttemptHash')){if([string]$v.$n -cne [string]$r.$n){throw ('ResumeNoSpawnReturnConflict:'+ $n)}}
    if($Registered.Count -ne 1){throw 'ResumeNoSpawnRegistryAmbiguous'};$entry=$Registered[0]
    if($entry.state -cne 'terminal' -or -not $entry.terminalAt -or $entry.nativeThreadId -or ([guid]$entry.taskId).ToString('N') -cne $r.taskId -or ([guid]$entry.executionId).ToString('D') -cne $r.executionId -or $entry.role -cne $r.childRole -or $entry.payloadHash -cne $r.payloadHash -or [IO.Path]::GetFullPath($entry.resultPath) -cne $r.resultPath -or [IO.Path]::GetFullPath($entry.dispatchJournalPath) -cne $r.dispatchJournalPath){throw 'ResumeNoSpawnRegistryReleaseConflict'}
    foreach($n in @('noSpawnReceiptPath','noSpawnReceiptHash','failureCommitPath','failureCommitHash','resultHash')){if([string]$entry.$n -cne [string]$v.$n){throw ('ResumeNoSpawnRegistryReceiptConflict:'+ $n)}}
    $closed=[ordered]@{kind='resume-prior-nospawn-closure-v1';effectId=$Command.effectId;commandHash=$commandHash;planHash=$Plan.planHash;sourceRevision=$Plan.baseRevision;workItemId=$r.workItemId;priorExecutionId=$Command.priorExecutionId;priorGeneration=$Command.priorGeneration;logicalSessionId=$Session.LogicalSessionId;rootTaskId=$Session.RootTaskId;coordinatorJobPath=$Session.CoordinatorJobPath;coordinatorJobHash=$Session.CoordinatorJobHash;terminalContext=$TerminalContext;terminalDecision=$DecisionRef;noSpawnReceipt=[ordered]@{path=$v.noSpawnReceiptPath;hash=$v.noSpawnReceiptHash};failureCommit=[ordered]@{path=$v.failureCommitPath;hash=$v.failureCommitHash};publishedStoreReceiptHash=$g.commit.storeReceiptHash;returnedReceipt=$v;registryRelease=$entry;parentContextHash=$r.parentContextHash;startIntentHash=$r.startIntentHash;startAttemptHash=$r.startAttemptHash;noSpawnAttemptHash=$r.noSpawnAttemptHash}
    $ref=Save-LCImmutable $directory $closed
    Write-LCCreateNew $binder (Get-LCBytes $ref)
    return $ref
}
function Apply-LCResume($Config,$Dispatch,$Plan,$Command,$Session) {
    $revision=[string]$Command.sourceRevision
    if($revision -cne [string]$Plan.baseRevision -or $Command.triggerEventId -cne $Plan.eventId){throw 'ResumeSourceRevisionConflict'}
    # The immutable dispatch snapshot supplies the candidate on replay, never current arbitrary bytes.
    $items=@($Dispatch.input.workItems|Where-Object{$_.id -ceq $Command.workItemId})
    if($items.Count -ne 1 -or $items[0].status -cne 'blocked'){throw 'ResumeSourceNotBlocked'};$item=$items[0]
    $interaction=Get-LCValue $item 'humanInteraction';$response=Get-LCValue $interaction 'response'
    $requested=Get-LCValue $interaction 'requestedAt';$responseHash=Get-LCHash (Get-LCBytes $response)
    if([string]$requested -cne [string]$Command.requestedAt -or $responseHash -cne $Command.responseHash -or ($interaction -and $null -eq $response)){throw 'ResumeResponseBindingConflict'}
    if([string](Get-LCValue $Dispatch.input.payload 'workItemId') -cne $item.id){throw 'ResumeTriggerItemConflict'}
    if($Dispatch.input.kind -notin @('human_response','reminder_due','workitem_changed','return_received')){throw 'ResumeTriggerUnsupported'}
    if($Dispatch.input.kind -ceq 'reminder_due'){
        $due=Get-LCValue $Dispatch.input.payload 'dueAt';if(-not $due -or [DateTimeOffset]::Parse([string]$due).UtcDateTime -gt [DateTime]::UtcNow -or [string]$due -cne [string](Get-LCValue $item 'dueAt')){throw 'ResumeDueBindingConflict'}
    }
    $hist=@((Get-CoordinatorHistory $Session)|Where-Object{$_.requestId -ceq $Plan.requestId})
    if($hist.Count -ne 1 -or $hist[0].outcome -cne 'completed' -or $hist[0].decision.effectPlan.planHash -cne $Plan.planHash){throw 'ResumeTerminalHistoryConflict'}
    $terminalContext=[pscustomobject]@{path=$hist[0].terminalContextPath;hash=$hist[0].terminalContextHash}
    $context=Read-LCReceipt $terminalContext
    $decisionRef=Save-LCImmutable (Join-Path $Config.DataDirectory 'resume-receipts') $hist[0].decision
    if($context.outcome -cne 'Completed' -or $context.evidenceHash -cne $decisionRef.hash -or $context.requestId -cne $Plan.requestId -or $context.threadId -cne $Plan.threadId -or $context.turnId -cne $Plan.turnId){throw 'ResumeTerminalContextConflict'}
    $operationContext=@{effectId=$Command.effectId;executionId=$Plan.executionId;requestId=$Plan.requestId;threadId=$Plan.threadId;turnId=$Plan.turnId;eventId=$Plan.eventId;inputHash=$Plan.inputHash;planHash=$Plan.planHash;ordinal=$Command.ordinal;baseRevision=$revision;resumeEffectKind='propose_resume';resumeCommandHash=(Get-LCHash (Get-LCBytes $Command))}
    if($context.logicalSessionId -cne $Session.LogicalSessionId -or $context.taskId -cne $Session.RootTaskId -or $context.jobPath -cne $Session.CoordinatorJobPath -or $context.jobHash -cne $Session.CoordinatorJobHash -or $hist[0].decision.outcome -cne 'completed'){throw 'ResumeTerminalSessionEpochConflict'}
    $priorClosure=$null;$generationReceipt=$null;$generation=[int]$Command.priorGeneration
    $generationModule=Get-AutomationStoreModule $Config
    $cas=Get-AutomationStoreEffectReceipt $Config ([string]$Command.effectId)
    if($Command.disposition -ceq 'resume'){
        foreach($dep in @($item.dependencies)){$match=@($Dispatch.input.workItems|Where-Object{$_.id -ceq $dep});if($match.Count -ne 1 -or $match[0].status -cne 'accepted'){throw 'ResumeDependencyNotAccepted'}}
        $root=Get-AutomationRoot @($Dispatch.input.workItems) $item
        $rootInteraction=Get-LCValue $root 'humanInteraction';if($rootInteraction -and $null -eq (Get-LCValue $rootInteraction 'response')){throw 'ResumeRootHumanResponseMissing'}
        if($generation -gt 0){
            # A real model transfer or separately verified NoSpawn closure is required.
            $dm=Import-Module (Join-Path $PSScriptRoot 'CoordinatorDispatch.psm1') -PassThru -Force
            $prior=& $dm {param($p,$id)Get-CoordinatorDispatch -JournalPath $p -ExecutionId $id} (Join-Path $Config.DataDirectory 'dispatch-journal.json') $Command.priorExecutionId
            if(-not $prior -or $prior.state -cne 'Returned' -or $prior.workItemId -cne $item.id -or [int]$prior.generation -ne $generation){throw 'ResumePriorNotReturned'}
            $registered=@(Read-AutomationJson (Join-Path $Config.RegistryDirectory 'executions.json') @()|Where-Object{(ConvertTo-AutomationGuid ([string]$_.dispatchId)) -ceq (ConvertTo-AutomationGuid ([string]$Command.priorExecutionId))})
            if($prior.terminalDecision -ceq 'prestart-failed'){
                $priorClosure=Get-LCNoSpawnResumePrior $Config $prior $registered $Command $Plan $Session $terminalContext $decisionRef
            }else{
                $transferPath=Join-Path $Config.AccountingDirectory ('workitem-transfer-'+(Get-AutomationHash ([string]$Command.priorExecutionId))+'.json')
                $transfer=Read-AutomationJson $transferPath $null
                if(-not $transfer -or $transfer.complete -ne $true -or $transfer.executionId -cne $Command.priorExecutionId -or $transfer.workItemId -cne $item.id -or $registered.Count -ne 1 -or $registered[0].state -cne 'terminal'){throw 'ResumePriorTransferOrReleaseMissing'}
            }
            $generationContext=@{};foreach($k in $operationContext.Keys){$generationContext[$k]=$operationContext[$k]};$generationContext.effectId=Get-AutomationHash ($Command.effectId+':resume-generation')
            $generationReceipt=Request-CoordinatorRework $Config $item.id 'teamleiter-workitem' $generation $Command.priorExecutionId $Command.reason $generationContext
            $generation=[int]$generationReceipt.nextGeneration
        }else{
            if($Command.priorExecutionId){throw 'ResumeInitialExecutionConflict'}
            $binding=Join-Path $Config.AccountingDirectory ('workitem-current-'+(Get-AutomationHash ([IO.Path]::GetFullPath($Config.WorkItemStorePath).ToLowerInvariant()+"`n"+[string]$item.id))+'.json')
            if([IO.File]::Exists($binding)){throw 'ResumeInitialPriorBindingExists'}
            $generation=Get-AutomationGeneration $Config $item 'teamleiter-workitem'
            if($generation -ne 1){throw 'ResumeInitialGenerationConflict'}
        }
        $candidate=ConvertFrom-Json -InputObject (ConvertTo-Json -InputObject $item -Depth 100 -Compress)
        $checks=@(Get-LCValue $candidate 'verifications' @())
        $candidate.status=if($null -eq $candidate.implementedAt){'planned'}elseif($checks.Count -and $checks[-1].passed -eq $false -and $checks[-1].implementedAt -ceq $candidate.implementedAt){'rework'}else{'in_progress'};$candidate.blockReason=$null
        $updated=[DateTimeOffset]::Parse([string]$hist[0].decision.completedAtUtc).UtcDateTime
        $oldUpdated=[DateTimeOffset]::Parse([string]$item.updatedAt).UtcDateTime
        if($updated -le $oldUpdated){$updated=$oldUpdated.AddTicks(1)};$candidate.updatedAt=$updated.ToString('yyyy-MM-ddTHH:mm:ss.fffffffZ')
    }elseif($Command.disposition -ceq 'keep_blocked'){$candidate=$item}else{throw 'ResumeDispositionInvalid'}
    if(-not $cas){
        $result=& $generationModule {param($p,$id,$i,$rev,$root,$ctx)Set-WorkItemStoreEntry -Path $p -Id $id -Item $i -IsNew $false -ExpectedRevision $rev -RepositoryRoot $root -TimeoutMilliseconds 5000 -EffectContext $ctx} $Config.WorkItemStorePath $item.id $candidate $revision $Config.RepositoryRoot $operationContext
        $cas=$result.EffectReceipt
    }
    $casItem=ConvertFrom-Json -InputObject ([Text.UTF8Encoding]::new($false,$true).GetString([Convert]::FromBase64String($cas.itemPayloadBase64)))
    if($cas.state -cne 'published' -or $cas.previousRevision -cne $revision -or (Get-LCHash (Get-LCBytes $casItem)) -cne (Get-LCHash (Get-LCBytes $candidate)) -or $cas.context.planHash -cne $Plan.planHash){throw 'ResumeCASConflict'}
    $dm=Import-Module (Join-Path $PSScriptRoot 'CoordinatorDispatch.psm1') -PassThru -Force
    $identity=if($Command.disposition -ceq 'resume'){& $dm {param($w,$g)Get-CoordinatorDispatchIdentity $w 'teamleiter-workitem' $g} $item.id $generation}else{$null}
    $receipt=[ordered]@{kind='terminal-resume-decision-v1';logicalSessionId=$Session.LogicalSessionId;rootTaskId=$Session.RootTaskId;coordinatorJobPath=$Session.CoordinatorJobPath;coordinatorJobHash=$Session.CoordinatorJobHash;state='published';disposition=$Command.disposition;workItemId=$item.id;storePath=[IO.Path]::GetFullPath($Config.WorkItemStorePath);effectId=$Command.effectId;ordinal=$Command.ordinal;sourceRevision=$revision;previousRevision=$revision;candidateRevision=$cas.candidateRevision;casReceiptHash=(Get-LCHash (Get-LCBytes $cas));commandHash=(Get-LCHash (Get-LCBytes $Command));contentHash=(Get-LCResumeContent $candidate);requestedAt=$requested;responseHash=$responseHash;blockReason=$item.blockReason;triggerEventId=$Plan.eventId;eventId=$Plan.eventId;requestId=$Plan.requestId;threadId=$Plan.threadId;turnId=$Plan.turnId;executionId=$Plan.executionId;inputHash=$Plan.inputHash;planHash=$Plan.planHash;priorExecutionId=$Command.priorExecutionId;priorGeneration=$Command.priorGeneration;generation=$generation;nextExecutionId=$(if($identity){$identity.ExecutionId}else{$null});reason=$Command.reason;assessmentText=$Command.assessmentText;terminalContext=$terminalContext;terminalDecision=$decisionRef;generationReceipt=$generationReceipt;priorClosure=$priorClosure}
    $ref=Save-LCImmutable (Join-Path $Config.DataDirectory 'resume-receipts') $receipt
    # Stable effect-id binder. CreateNew+exact bytes allows recovery after any preceding commit.
    $binder=Join-Path $Config.DataDirectory ('resume-receipts/'+$Command.effectId+'.binding.json')
    Write-LCCreateNew $binder (Get-LCBytes $ref)
    return [pscustomobject]@{effectId=$Command.effectId;state='published';ordinal=$Command.ordinal;previousRevision=$revision;candidateRevision=$cas.candidateRevision;reference=$ref;receipt=$receipt}
}
function Get-LCResumePromptBindings($Config,$Event,$Snapshot) {
    $workItemId=[string](Get-LCValue $Event.payload 'workItemId');$items=@($Snapshot.Document.items|Where-Object{$_.id -ceq $workItemId -and $_.status -ceq 'blocked'})
    if($items.Count -gt 1){throw 'ResumePromptItemAmbiguous'};if(-not $items.Count){return @()};$item=$items[0]
    $gen=Read-AutomationJson (Join-Path $Config.DataDirectory 'workitem-generations.json') ([pscustomobject]@{items=@()})
    $records=@($gen.items|Where-Object{$_.workItemId -ceq $workItemId -and $_.purpose -ceq 'teamleiter-workitem'})
    if($records.Count -gt 1){throw 'ResumePromptGenerationAmbiguous'}
    $generation=0;$priorId=$null;$priorState='never-executed'
    if($records.Count){
        $dm=Import-Module (Join-Path $PSScriptRoot 'CoordinatorDispatch.psm1') -PassThru -Force
        $identity=& $dm {param($w,$g)Get-CoordinatorDispatchIdentity $w 'teamleiter-workitem' $g} $workItemId ([int]$records[0].generation)
        $prior=& $dm {param($p,$id)Get-CoordinatorDispatch -JournalPath $p -ExecutionId $id} (Join-Path $Config.DataDirectory 'dispatch-journal.json') $identity.ExecutionId
        if($prior){$generation=[int]$records[0].generation;$priorId=$prior.executionId;$priorState=$prior.state}
    }
    $interaction=Get-LCValue $item 'humanInteraction'
    return @([ordered]@{workItemId=$workItemId;triggerEventId=$Event.id;sourceRevision=$Snapshot.Revision;requestedAt=(Get-LCValue $interaction 'requestedAt');responseHash=(Get-LCHash (Get-LCBytes (Get-LCValue $interaction 'response')));priorExecutionId=$priorId;priorGeneration=$generation;priorState=$priorState;blockReason=$item.blockReason})
}
function Get-LCResumeForStart($Config,$Item,[string]$ExecutionId,[int]$Generation) {
    $directory=Join-Path $Config.DataDirectory 'resume-receipts';$found=@()
    if([IO.Directory]::Exists($directory)){foreach($f in @(Get-ChildItem -LiteralPath $directory -Filter '*.binding.json' -File)){
        $ref=Read-AutomationJson $f.FullName $null;$r=Read-LCReceipt $ref
        if($r.workItemId -ceq $Item.id -and $r.nextExecutionId -ceq $ExecutionId -and [int]$r.generation -eq $Generation){$found+=,$ref}
    }}
    if($found.Count -gt 1){throw 'ResumeStartReceiptAmbiguous'}
    if(-not $found.Count){return $null}
    $assessment=ConvertTo-Json -InputObject $found[0] -Depth 10 -Compress
    [void](Assert-LCResume $assessment $Item '' $Config.WorkItemStorePath $Config.RepositoryRoot)
    return $assessment
}
function Complete-LCConsumedTrigger($Config,$Event) {
    if($Event.kind -notin @('human_response','workitem_changed')){return $false}
    $workItemId=[string](Get-LCValue $Event.payload 'workItemId');$revision=[string](Get-LCValue $Event.payload 'revision')
    if(-not $workItemId -or -not $revision){return $false}
    $state=Get-AutomationEffectState $Config
    foreach($effect in @($state.Data.executions)){
        if($effect.state -cne 'Complete'){continue}
        foreach($receipt in @($effect.receipts)){
            $ref=Get-LCValue $receipt 'reference';if(-not $ref){continue};$r=Read-LCReceipt $ref
            if($r.kind -cne 'terminal-resume-decision-v1' -or $r.workItemId -cne $workItemId -or $r.sourceRevision -cne $revision){continue}
            $item=Get-LCValue $Event.payload 'item';$response=if($Event.kind -ceq 'human_response'){Get-LCValue $Event.payload 'response'}else{Get-LCValue (Get-LCValue $item 'humanInteraction') 'response'}
            if($r.responseHash -cne (Get-LCHash (Get-LCBytes $response))){continue}
            $cas=Get-AutomationStoreEffectReceipt $Config ([string]$r.effectId)
            if(-not $cas -or (Get-LCHash (Get-LCBytes $cas)) -cne $r.casReceiptHash){throw 'ConsumedTriggerReceiptConflict'}
            Complete-CoordinatorEvent -Path $Config.EventJournalPath -EventId $Event.id -ClaimId $Event.claimId|Out-Null
            return $true
        }
    }
    return $false
}
