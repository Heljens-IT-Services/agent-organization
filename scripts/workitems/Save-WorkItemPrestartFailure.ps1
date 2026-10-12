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
    [Parameter(Mandatory)][string]$ParentContextPath,
    [Parameter(Mandatory)][string]$ParentContextHash,
    [Parameter(Mandatory)][string]$StartIntentPath,
    [Parameter(Mandatory)][string]$StartIntentHash,
    [Parameter(Mandatory)][string]$StartAttemptPath,
    [Parameter(Mandatory)][string]$StartAttemptHash,
    [Parameter(Mandatory)][string]$NoSpawnAttemptPath,
    [Parameter(Mandatory)][string]$NoSpawnAttemptHash,
    [Parameter(Mandatory)][string]$PayloadHash,
    [Parameter(Mandatory)][string]$NoSpawnReceiptPath,
    [Parameter(Mandatory)][string]$FailureCommitPath,
    [Parameter(Mandatory)][string]$DispatchJournalPath,
    [Parameter(Mandatory)][string]$RegistryDirectory,
    [Parameter(Mandatory)][string]$Reason
)
$ErrorActionPreference='Stop'
Import-Module (Join-Path $PSScriptRoot 'WorkItemPrestartRecovery.psm1') -Force
$cm=Import-Module (Join-Path $PSScriptRoot 'CoordinatorExecutionContext.psm1') -PassThru -Force
$sm=Import-Module (Join-Path $PSScriptRoot 'WorkItemStore.psm1') -PassThru -Force
$store=[IO.Path]::GetFullPath($StorePath);$accounting=[IO.Path]::GetFullPath($AccountingDirectory)
$result=[IO.Path]::GetFullPath($ResultPath);$parentPath=[IO.Path]::GetFullPath($ParentJobPath)
$childId=([guid]$TaskId).ToString('N');$parentId=([guid]$ParentTaskId).ToString('N')
$paths=Get-PrestartRecoveryPaths $accounting $ExecutionId $store $WorkItemId
if([IO.Path]::GetFullPath($NoSpawnReceiptPath) -cne $paths.receipt -or [IO.Path]::GetFullPath($FailureCommitPath) -cne $paths.commit -or [string]::IsNullOrWhiteSpace($Reason)){throw 'InvalidFailureReceiptLocationOrReason'}
$lock=$null
try {
    $lock=[IO.File]::Open($paths.lock,[IO.FileMode]::OpenOrCreate,[IO.FileAccess]::ReadWrite,[IO.FileShare]::None)
    $parent=Read-RecoveryJson $parentPath
    $ctx=& $cm {param($p,$h,$j,$t,$s,$a)Assert-ExecutionContext $p $h $j $t $s $a} $ParentContextPath $ParentContextHash $parentPath $parentId $store $accounting
    & $cm {param($p,$h,$s,$a)Assert-ExecutionAncestors $p $h $s $a|Out-Null} $ParentContextPath $ParentContextHash $store $accounting
    $authority=& $cm {param($p,$h)Read-DelegatedStartAuthority $p $h} $StartIntentPath $StartIntentHash
    $prepared=Read-RecoveryJson $StartAttemptPath $StartAttemptHash
    $noSpawn=Read-RecoveryJson $NoSpawnAttemptPath $NoSpawnAttemptHash
    $reservation=Read-RecoveryJson $paths.reservation
    Assert-PrestartAttemptGroup $prepared $noSpawn $authority $ctx $reservation
    if($prepared.taskId -cne $childId -or $prepared.parentTaskId -cne $parentId -or $prepared.executionId -cne $ExecutionId -or $prepared.workItemId -cne $WorkItemId -or $prepared.storePath -cne $store -or $prepared.resultPath -cne $result -or $prepared.parentJobPath -cne $parentPath -or $prepared.parentContextHash -cne $ParentContextHash -or $prepared.startIntentHash -cne $StartIntentHash -or $prepared.payloadHash -cne $PayloadHash -or $reservation.start_attempt_path -cne [IO.Path]::GetFullPath($StartAttemptPath) -or $reservation.start_attempt_hash -cne $StartAttemptHash -or $reservation.current_binding_path -cne $paths.binding -or $reservation.state -notin @('reserved','failed')){throw 'CallerReservationAttemptConflict'}
    $role=[string]$prepared.role
    $root=$parent.role -ceq 'koordinator' -and $null -eq $parent.work_item_id -and -not $parent.parent_task_id -and -not $parent.parent_job_path -and -not $parent.execution_id -and -not $parent.work_item_request_path
    if($root){if($ctx.outcome -cne 'Completed' -or $role -notmatch '^teamleiter_[a-z][a-z0-9_]*$'){throw 'InvalidCompletedRootAuthority'}}elseif(-not $parent.work_item_id -or $ctx.outcome -cne 'Running'){throw 'InvalidHistoricalParentAuthority'}
    $eventJournal=Get-PrestartEventJournal $ctx
    if([IO.Path]::GetFullPath($RegistryDirectory) -cne [IO.Path]::GetFullPath($authority.parameters.CoordinatorDataDirectory) -or [IO.Path]::GetFullPath($DispatchJournalPath) -cne $prepared.dispatchJournalPath){throw 'CallerDispatchRegistryConflict'}
    $snapshot=& $sm {param($p,$repo)Get-WorkItemStoreResult -Path $p -RepositoryRoot $repo} $store $RepositoryRoot
    $items=@($snapshot.Document.items|Where-Object{$_.id -ceq $WorkItemId})
    if($items.Count -ne 1){throw 'WorkItemMissingOrAmbiguous'};$item=$items[0]
    if($item.owner.type -cne 'agent' -or $item.owner.id -cne $role -or $item.status -in @('accepted','cancelled')){throw 'ForeignOwnerOrTerminalWorkItem'}
    if($root -and $null -ne $item.parentId){throw 'RootWorkItemMustBeParentless'}
    if(-not $root){$cursor=$item;$seen=@{};$found=$false;while($null -ne $cursor.parentId){if($seen.ContainsKey($cursor.id)){throw 'WorkItemAncestryCycle'};$seen[$cursor.id]=$true;if($cursor.parentId -ceq $parent.work_item_id){$found=$true};$next=@($snapshot.Document.items|Where-Object{$_.id -ceq $cursor.parentId});if($next.Count -ne 1){throw 'WorkItemAncestryIncomplete'};$cursor=$next[0]};if(-not $found){throw 'ForeignParentWorkItem'}}
    if($snapshot.Revision -cne $reservation.startingRevision -and -not [IO.File]::Exists($paths.receipt)){
        if(-not $reservation.startingCAS -or $snapshot.Revision -cne $reservation.startingCAS.candidateRevision -or $reservation.startingCAS.sourceRevision -cne $reservation.startingRevision){throw 'ForeignPrestartStoreCAS'}
        $startReceipt=& $sm {param($r,$repo)Get-WorkItemStoreEffectReceipt -Path $r.store_path -EffectId $r.startingCAS.effectContext.effectId -RepositoryRoot $repo} $reservation $RepositoryRoot
        if(-not $startReceipt -or $startReceipt.state -cne 'published' -or $startReceipt.previousRevision -cne $reservation.startingRevision -or $startReceipt.candidateRevision -cne $snapshot.Revision -or $startReceipt.context.executionId -cne $ExecutionId -or $startReceipt.context.inputHash -cne $StartIntentHash -or $startReceipt.context.planHash -cne $StartAttemptHash){throw 'OwnedStartCASReceiptRequired'}
    }
    $receipt=$null
    if([IO.File]::Exists($paths.receipt)){
        $receipt=Read-RecoveryJson $paths.receipt
        foreach($n in @('executionId','taskId','parentTaskId','workItemId','payloadHash','parentContextHash','startIntentHash')){if([string]$receipt.$n -cne [string]$prepared.$n){throw 'ExistingReceiptGroupConflict'}}
        if($receipt.noSpawnReceiptVersion -cne '1.0' -or $receipt.reason -cne $Reason -or $receipt.startAttemptHash -cne $StartAttemptHash -or $receipt.noSpawnAttemptHash -cne $NoSpawnAttemptHash -or $receipt.resultPath -cne $result -or $receipt.storePath -cne $store -or $receipt.registryDirectory -cne [IO.Path]::GetFullPath($RegistryDirectory) -or $receipt.eventJournalPath -cne $eventJournal){throw 'LegacyOrConflictingReceiptRecoveryClosed'}
        if($snapshot.Revision -notin @($receipt.sourceRevision,$receipt.candidateRevision)){throw 'FailureCASReconcileMismatch'}
    }
    $binding=$null
    if([IO.File]::Exists($paths.binding)){$binding=Read-RecoveryJson $paths.binding;Assert-PrestartCurrentBinding $binding $prepared;if($binding.startAttemptPath -cne [IO.Path]::GetFullPath($StartAttemptPath) -or $binding.startAttemptHash -cne $StartAttemptHash -or $binding.startingRevision -cne $reservation.startingRevision){throw 'BindingPreparedReservationConflict'}}
    else {
        # Reconstruct only the identical reserved attempt, never replace a foreign binding.
        if($reservation.state -cne 'reserved' -or $snapshot.Revision -cne $reservation.startingRevision -or $snapshot.Revision -cne $prepared.storeRevision -or (Get-RecoveryHash (ConvertTo-RecoveryBytes $item)) -cne (Get-RecoveryHash (ConvertTo-RecoveryBytes $reservation.startingSnapshot))){throw 'EarlyBindingRecoveryCASMismatch'}
        $binding=New-PrestartCurrentBinding $prepared $reservation
        Write-RecoveryBytes $paths.binding (ConvertTo-RecoveryBytes $binding) -Immutable
    }
    if(-not $receipt){
        if($binding.state -cne 'active' -or $reservation.state -cne 'reserved' -or $item.status -notin @('planned','in_progress','rework','blocked')){throw 'UncorrelatedOrNonTransitionablePrestartState'}
        $candidateItem=ConvertFrom-Json -InputObject (ConvertTo-Json -InputObject $item -Depth 100)
        $candidateItem.status='blocked';$candidateItem.blockReason=$Reason;$candidateItem.updatedAt=[DateTime]::UtcNow.ToString('yyyy-MM-ddTHH:mm:ss.fffffffZ')
        $document=ConvertFrom-Json -InputObject (ConvertTo-Json -InputObject $snapshot.Document -Depth 100)
        for($i=0;$i -lt @($document.items).Count;$i++){if($document.items[$i].id -ceq $WorkItemId){$document.items[$i]=$candidateItem}}
        $candidateBytes=& $sm {param($d) ,(ConvertTo-WorkItemStoreCandidate $d)} $document
        $candidateRevision='sha256:'+(Get-RecoveryHash $candidateBytes)
        $evidence=[ordered]@{task_id=$childId;dispatch_id=$ExecutionId;parent_task_id=$parentId;work_item_id=$WorkItemId;execution_id=$ExecutionId;parent_job_task_id=$parentId;parent_job_path=$parentPath;parent_thread_id=$ctx.threadId;parent_turn_id=$ctx.turnId;parent_context_path=[IO.Path]::GetFullPath($ParentContextPath);parent_context_hash=$ParentContextHash;start_intent_path=[IO.Path]::GetFullPath($StartIntentPath);start_intent_hash=$StartIntentHash;work_item_store_path=$store;accounting_directory=$accounting;role=$role;model_started=$false;thread_id=$null;turn_id=$null;terminal_outcome='failed';success=$false;output=$null;error=$Reason;result_path=$result;prestart_failure_record_path=$paths.receipt;no_spawn_receipt_path=$paths.receipt;failure_commit_path=$paths.commit}
        $resultBytes=ConvertTo-RecoveryBytes $evidence
        # Effect thread/turn/requestId refer to the real historical authorizing parent turn.
        $effect=[ordered]@{effectId=('prestart:'+ $ExecutionId);executionId=$ExecutionId;requestId=$ctx.requestId;threadId=$ctx.threadId;turnId=$ctx.turnId;eventId=('prestart:'+ $ExecutionId);inputHash=$StartIntentHash;planHash=$NoSpawnAttemptHash;ordinal=1}
        $receipt=[ordered]@{kind='prestart-failure';noSpawnReceiptVersion='1.0';outcome='failed';executionId=$ExecutionId;taskId=$childId;parentTaskId=$parentId;workItemId=$WorkItemId;payloadHash=$PayloadHash;storePath=$store;accountingDirectory=$accounting;resultPath=$result;parentJobPath=$parentPath;parentContextPath=[IO.Path]::GetFullPath($ParentContextPath);parentContextHash=$ParentContextHash;startIntentPath=[IO.Path]::GetFullPath($StartIntentPath);startIntentHash=$StartIntentHash;startAttemptPath=[IO.Path]::GetFullPath($StartAttemptPath);startAttemptHash=$StartAttemptHash;noSpawnAttemptPath=[IO.Path]::GetFullPath($NoSpawnAttemptPath);noSpawnAttemptHash=$NoSpawnAttemptHash;contextAuthorityAttempt=[ordered]@{parentContextHash=$ParentContextHash;startIntentHash=$StartIntentHash;preparedAttemptHash=$StartAttemptHash;noSpawnAttemptHash=$NoSpawnAttemptHash};reservationProof=$reservation;noSpawnProof=$noSpawn.noSpawnProof;childRole=$role;reason=$Reason;sourceRevision=$snapshot.Revision;candidateRevision=$candidateRevision;candidateBytesHash=(Get-RecoveryHash $candidateBytes);candidatePayloadBase64=[Convert]::ToBase64String($candidateBytes);candidateItem=$candidateItem;resultHash=(Get-RecoveryHash $resultBytes);resultPayloadBase64=[Convert]::ToBase64String($resultBytes);effectContext=$effect;dispatchJournalPath=$prepared.dispatchJournalPath;registryDirectory=[IO.Path]::GetFullPath($RegistryDirectory);eventJournalPath=$eventJournal}
        Write-RecoveryBytes $paths.receipt (ConvertTo-RecoveryBytes $receipt) -Immutable
        $receipt=Read-RecoveryJson $paths.receipt
    }
    $receiptHash=Get-RecoveryHash ([IO.File]::ReadAllBytes($paths.receipt))
    if(('sha256:'+(Get-RecoveryHash ([Convert]::FromBase64String($receipt.candidatePayloadBase64)))) -cne $receipt.candidateRevision -or (Get-RecoveryHash ([Convert]::FromBase64String($receipt.resultPayloadBase64))) -cne $receipt.resultHash){throw 'ReceiptBytePlanInvalid'}
    $sr=& $sm {param($r,$repo)Get-WorkItemStoreEffectReceipt -Path $r.storePath -EffectId $r.effectContext.effectId -RepositoryRoot $repo} $receipt $RepositoryRoot
    if(-not $sr){
        if($snapshot.Revision -cne $receipt.sourceRevision){throw 'CandidateRevisionWithoutOwnedStoreReceipt'}
        $write=& $sm {param($r,$repo)Set-WorkItemStoreEntry -Path $r.storePath -Id $r.workItemId -Item $r.candidateItem -ExpectedRevision $r.sourceRevision -RepositoryRoot $repo -EffectContext $r.effectContext} $receipt $RepositoryRoot
        $sr=$write.EffectReceipt
    }
    if(-not $sr -or $sr.state -cne 'published' -or $sr.previousRevision -cne $receipt.sourceRevision -or $sr.candidateRevision -cne $receipt.candidateRevision -or $sr.workItemId -cne $WorkItemId -or (Get-RecoveryHash (ConvertTo-RecoveryBytes $sr.context)) -cne (Get-RecoveryHash (ConvertTo-RecoveryBytes $receipt.effectContext))){throw 'PublishedStoreCASReceiptMismatch'}
    $readback=& $sm {param($p,$repo)Get-WorkItemStoreResult -Path $p -RepositoryRoot $repo} $store $RepositoryRoot
    if($readback.Revision -cne $receipt.candidateRevision){throw 'FailureStoreReadbackCASMismatch'}
    Write-RecoveryBytes $result ([Convert]::FromBase64String($receipt.resultPayloadBase64)) -Immutable
    $commit=[ordered]@{kind='prestart-failure-commit-v1';noSpawnReceiptPath=$paths.receipt;noSpawnReceiptHash=$receiptHash;sourceRevision=$receipt.sourceRevision;candidateRevision=$receipt.candidateRevision;resultHash=$receipt.resultHash;storeReceiptHash=$sr.receiptHash;storeReceiptPayloadBase64=$sr.receiptPayloadBase64;contextAuthorityAttempt=$receipt.contextAuthorityAttempt}
    Write-RecoveryBytes $paths.commit (ConvertTo-RecoveryBytes $commit) -Immutable
    $commitHash=Get-RecoveryHash ([IO.File]::ReadAllBytes($paths.commit))
    foreach($pair in @(@('state','failed'),@('failureRecordPath',$paths.receipt),@('resultPath',$result),@('failureCommitPath',$paths.commit),@('failureCommitHash',$commitHash),@('noSpawnReceiptHash',$receiptHash))){$binding|Add-Member -NotePropertyName $pair[0] -NotePropertyValue $pair[1] -Force}
    Write-RecoveryBytes $paths.binding (ConvertTo-RecoveryBytes $binding)
    foreach($pair in @(@('state','failed'),@('failure_record_path',$paths.receipt),@('failure_commit_path',$paths.commit),@('failure_commit_hash',$commitHash),@('no_spawn_receipt_hash',$receiptHash))){$reservation|Add-Member -NotePropertyName $pair[0] -NotePropertyValue $pair[1] -Force}
    Write-RecoveryBytes $paths.reservation (ConvertTo-RecoveryBytes $reservation)
    $saved=[pscustomobject]@{persisted=$true;outcome='failed';revision=$receipt.candidateRevision;recordPath=$paths.receipt;noSpawnReceiptPath=$paths.receipt;noSpawnReceiptHash=$receiptHash;failureCommitPath=$paths.commit;failureCommitHash=$commitHash;resultHash=$receipt.resultHash;workItemId=$WorkItemId;executionId=$ExecutionId}
    $verified=Assert-PrestartFailureCommit $paths.receipt $receiptHash $paths.commit $commitHash $RepositoryRoot
    $completion=Complete-PrestartReceiptGroup $saved $RepositoryRoot
    $saved|Add-Member -NotePropertyName completion -NotePropertyValue $completion
    $saved
}finally{if($lock){$lock.Dispose()}}
