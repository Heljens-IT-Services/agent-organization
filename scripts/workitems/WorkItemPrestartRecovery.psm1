$ErrorActionPreference='Stop'
$script:RecoveryUtf8=New-Object Text.UTF8Encoding($false,$true)
function Get-RecoveryHash([byte[]]$Bytes) {
    $sha=[Security.Cryptography.SHA256]::Create()
    try { ([BitConverter]::ToString($sha.ComputeHash($Bytes))).Replace('-','').ToLowerInvariant() } finally {$sha.Dispose()}
}
function ConvertTo-RecoveryBytes($Record) { ,$script:RecoveryUtf8.GetBytes((ConvertTo-Json -InputObject $Record -Depth 100 -Compress)) }
function Read-RecoveryJson([string]$Path,[string]$Hash) {
    $b=[IO.File]::ReadAllBytes($Path)
    if($Hash -and (Get-RecoveryHash $b) -cne $Hash){throw 'RecoveryByteHashMismatch'}
    ConvertFrom-Json -InputObject $script:RecoveryUtf8.GetString($b) -ErrorAction Stop
}
function Write-RecoveryBytes([string]$Path,[byte[]]$Bytes,[switch]$Immutable) {
    if($Immutable -and [IO.File]::Exists($Path)){
        if((Get-RecoveryHash ([IO.File]::ReadAllBytes($Path))) -cne (Get-RecoveryHash $Bytes)){throw 'ImmutableRecoveryConflict'}
        return
    }
    [void][IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName([IO.Path]::GetFullPath($Path)))
    if($Immutable){$temp=$Path}else{$temp=$Path+'.'+[guid]::NewGuid().ToString('N')+'.writing'}
    $f=New-Object IO.FileStream($temp,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::None)
    try{$f.Write($Bytes,0,$Bytes.Length);$f.Flush($true)}finally{$f.Dispose()}
    if(-not $Immutable){try{if([IO.File]::Exists($Path)){[IO.File]::Replace($temp,$Path,$null)}else{[IO.File]::Move($temp,$Path)}}finally{if([IO.File]::Exists($temp)){[IO.File]::Delete($temp)}}}
    if((Get-RecoveryHash ([IO.File]::ReadAllBytes($Path))) -cne (Get-RecoveryHash $Bytes)){throw 'RecoveryReadbackMismatch'}
}
function Get-PrestartRecoveryPaths([string]$AccountingDirectory,[string]$ExecutionId,[string]$StorePath,[string]$WorkItemId) {
    $a=[IO.Path]::GetFullPath($AccountingDirectory);$key=Get-RecoveryHash ([Text.Encoding]::UTF8.GetBytes($ExecutionId))
    $bk=Get-RecoveryHash ([Text.Encoding]::UTF8.GetBytes([IO.Path]::GetFullPath($StorePath).ToLowerInvariant()+"`n"+$WorkItemId))
    [pscustomobject]@{reservation=(Join-Path $a ('execution-'+$key+'.json'));receipt=(Join-Path $a ('prestart-failure-'+$key+'.json'));commit=(Join-Path $a ('prestart-commit-'+$key+'.json'));binding=(Join-Path $a ('workitem-current-'+$bk+'.json'));lock=(Join-Path $a ('workitem-current-'+$bk+'.lock'))}
}
function Assert-PrestartAttemptGroup($Prepared,$NoSpawn,$Authority,$Context,$Reservation) {
    if($Prepared.kind -cne 'workitem-prestart-attempt-v1' -or $Prepared.phase -cne 'Prepared' -or $NoSpawn.kind -cne $Prepared.kind -or $NoSpawn.phase -cne 'NoSpawnConfirmed' -or $NoSpawn.noSpawnProof.kind -cne 'synchronous-launcher-exception' -or $NoSpawn.noSpawnProof.spawnCallEntered -ne $false -or -not $NoSpawn.noSpawnProof.launcherProcessId -or -not $NoSpawn.noSpawnProof.launcherStartedAtUtc){throw 'PositiveNoSpawnProofRequired'}
    foreach($n in @('executionId','taskId','parentTaskId','parentJobPath','parentJobHash','parentContextPath','parentContextHash','parentThreadId','parentTurnId','startIntentPath','startIntentHash','payloadHash','requestPath','requestHash','storePath','workItemId','storeRevision','role','resultPath','dispatchJournalPath','dispatchId')){
        if([string]$Prepared.$n -cne [string]$NoSpawn.$n){throw ('AttemptImmutableGroupConflict:'+ $n)}
    }
    if($Authority.parentJobHash -cne $Prepared.parentJobHash -or $Authority.parentContextHash -cne $Prepared.parentContextHash -or $Authority.requestPayloadHash -cne $Prepared.requestHash -or $Authority.storeRevision -cne $Prepared.storeRevision -or $Context.jobHash -cne $Prepared.parentJobHash -or $Context.threadId -cne $Prepared.parentThreadId -or $Context.turnId -cne $Prepared.parentTurnId){throw 'AuthorityContextAttemptConflict'}
    $map=@{executionId='executionId';taskId='task_id';parentTaskId='parent_task_id';parentJobPath='parent_job_path';parentContextPath='parent_context_path';parentContextHash='parent_context_hash';parentThreadId='parent_thread_id';parentTurnId='parent_turn_id';startIntentPath='start_intent_path';startIntentHash='start_intent_hash';payloadHash='payload_hash';requestPath='request_path';requestHash='request_hash';storePath='store_path';workItemId='workItemId';role='role';resultPath='result_path'}
    foreach($n in $map.Keys){$rn=$map[$n];if([string]$Prepared.$n -cne [string]$Reservation.$rn){throw ('ReservationAttemptConflict:'+ $n)}}
    if($Reservation.startingRevision -cne $Prepared.storeRevision -or $Reservation.startingOwnerId -cne $Prepared.role -or $Reservation.startingSnapshot.id -cne $Prepared.workItemId -or $Reservation.startingSnapshot.owner.type -cne 'agent' -or $Reservation.startingSnapshot.owner.id -cne $Prepared.role){throw 'SecuredStartingSnapshotRequired'}
    $params=$Authority.parameters
    foreach($pair in @(@('ExecutionId','executionId'),@('WorkItemId','workItemId'),@('ParentTaskId','parentTaskId'),@('WorkItemStorePath','storePath'),@('WorkItemRequestPath','requestPath'),@('Role','role'),@('ResultPath','resultPath'),@('DispatchJournalPath','dispatchJournalPath'),@('DispatchId','dispatchId'))){if([string]$params.($pair[0]) -cne [string]$Prepared.($pair[1])){throw 'AuthorityParametersConflict'}}
    if(([guid]$params.StableTaskId).ToString('N') -cne $Prepared.taskId -or $Prepared.payloadHash -cne $Prepared.startIntentHash){throw 'AuthorityTaskPayloadConflict'}
}
function Assert-PrestartCurrentBinding($Binding,$Prepared) {
    if($Binding.kind -cne 'workitem-current-execution' -or $Binding.state -notin @('active','failed')){throw 'ForeignOrNonReplayableCurrentBinding'}
    foreach($n in @('executionId','taskId','parentTaskId','parentJobPath','parentJobHash','parentThreadId','parentTurnId','parentContextPath','parentContextHash','startIntentPath','startIntentHash','payloadHash','requestPath','requestHash','storePath','workItemId')){
        if([string]$Binding.$n -cne [string]$Prepared.$n){throw ('CurrentBindingConflict:'+ $n)}
    }
}
function New-PrestartCurrentBinding($Prepared,$Reservation) {
    $r=[ordered]@{kind='workitem-current-execution';state='active'}
    foreach($n in @('executionId','taskId','parentTaskId','parentJobPath','parentJobHash','parentThreadId','parentTurnId','parentContextPath','parentContextHash','startIntentPath','startIntentHash','payloadHash','requestPath','requestHash','storePath','workItemId')){$r[$n]=$Prepared.$n}
    $r.startAttemptPath=$Reservation.start_attempt_path;$r.startAttemptHash=$Reservation.start_attempt_hash
    $r.startingRevision=$Reservation.startingRevision;$r.startingSnapshot=$Reservation.startingSnapshot
    $r.startingImplementedAt=$Reservation.startingSnapshot.implementedAt;$r.registeredAt=$Reservation.reserved_at
    [pscustomobject]$r
}
function Get-PrestartEventJournal($Context) {
    $c=$Context;$seen=@{}
    while($c.role -cne 'koordinator'){
        if(-not $c.parentContextPath -or $seen.ContainsKey($c.parentContextHash)){throw 'RootEventAuthorityMissing'}
        $seen[$c.parentContextHash]=$true;$c=Read-RecoveryJson $c.parentContextPath $c.parentContextHash
    }
    $root=Read-RecoveryJson $c.jobPath
    if($root.parent_task_id -or $root.parent_job_path -or $root.work_item_id -or -not $root.coordinator_launch.eventJournalPath){throw 'RootEventAuthorityInvalid'}
    [IO.Path]::GetFullPath($root.coordinator_launch.eventJournalPath)
}
function Assert-PrestartFailureCommit {
    param([string]$ReceiptPath,[string]$ReceiptHash,[string]$CommitPath,[string]$CommitHash,[string]$RepositoryRoot,[switch]$HistoricalStoreReceipt)
    $r=Read-RecoveryJson $ReceiptPath $ReceiptHash;$c=Read-RecoveryJson $CommitPath $CommitHash
    if($r.kind -cne 'prestart-failure' -or $r.noSpawnReceiptVersion -cne '1.0' -or $c.kind -cne 'prestart-failure-commit-v1' -or $c.noSpawnReceiptHash -cne $ReceiptHash -or $c.noSpawnReceiptPath -cne [IO.Path]::GetFullPath($ReceiptPath) -or $c.resultHash -cne $r.resultHash -or $c.sourceRevision -cne $r.sourceRevision -or $c.candidateRevision -cne $r.candidateRevision){throw 'FailureCommitGroupConflict'}
    $p=Read-RecoveryJson $r.startAttemptPath $r.startAttemptHash;$n=Read-RecoveryJson $r.noSpawnAttemptPath $r.noSpawnAttemptHash
    $cm=Import-Module (Join-Path $PSScriptRoot 'CoordinatorExecutionContext.psm1') -PassThru -Force
    $a=& $cm {param($p,$h)Read-DelegatedStartAuthority $p $h} $r.startIntentPath $r.startIntentHash
    $ctx=& $cm {param($r)Assert-ExecutionContext $r.parentContextPath $r.parentContextHash $r.parentJobPath $r.parentTaskId $r.storePath $r.accountingDirectory} $r
    & $cm {param($r)Assert-ExecutionAncestors $r.parentContextPath $r.parentContextHash $r.storePath $r.accountingDirectory|Out-Null} $r
    Assert-PrestartAttemptGroup $p $n $a $ctx $r.reservationProof
    foreach($name in @('executionId','taskId','parentTaskId','workItemId','payloadHash','parentContextHash','startIntentHash')){if([string]$r.$name -cne [string]$p.$name){throw 'ReceiptAttemptConflict'}}
    if($r.contextAuthorityAttempt.parentContextHash -cne $r.parentContextHash -or $r.contextAuthorityAttempt.startIntentHash -cne $r.startIntentHash -or $r.contextAuthorityAttempt.preparedAttemptHash -cne $r.startAttemptHash -or $r.contextAuthorityAttempt.noSpawnAttemptHash -cne $r.noSpawnAttemptHash){throw 'ReceiptAuthorityGroupConflict'}
    foreach($name in @('storePath','resultPath','parentJobPath','parentContextPath','startIntentPath','startAttemptPath','noSpawnAttemptPath','dispatchJournalPath')){
        if([string]::IsNullOrWhiteSpace([string]$r.$name) -or [IO.Path]::GetFullPath($r.$name) -cne [string]$r.$name){throw 'ReceiptPathsMustBeCanonical'}
    }
    if($r.storePath -cne $p.storePath -or $r.resultPath -cne $p.resultPath -or $r.parentJobPath -cne $p.parentJobPath -or $r.parentContextPath -cne $p.parentContextPath -or $r.startIntentPath -cne $p.startIntentPath -or $r.dispatchJournalPath -cne $p.dispatchJournalPath -or $r.childRole -cne $p.role -or $r.registryDirectory -cne [IO.Path]::GetFullPath($a.parameters.CoordinatorDataDirectory) -or $r.eventJournalPath -cne (Get-PrestartEventJournal $ctx) -or (Get-RecoveryHash (ConvertTo-RecoveryBytes $r.noSpawnProof)) -cne (Get-RecoveryHash (ConvertTo-RecoveryBytes $n.noSpawnProof))){throw 'ReceiptHistoricalPathOrProofConflict'}
    $rootParent=Read-RecoveryJson $r.parentJobPath
    if($rootParent.role -ceq 'koordinator' -and ($rootParent.parent_task_id -or $rootParent.parent_job_path -or $rootParent.work_item_id -or $ctx.outcome -cne 'Completed')){throw 'ReceiptRootAuthorityConflict'}
    if($r.reason -cne $n.noSpawnProof.failure -or $r.candidateBytesHash -cne (Get-RecoveryHash ([Convert]::FromBase64String($r.candidatePayloadBase64)))){throw 'ReceiptReasonCandidateHashConflict'}
    $paths=Get-PrestartRecoveryPaths $r.accountingDirectory $r.executionId $r.storePath $r.workItemId
    if([IO.Path]::GetFullPath($ReceiptPath) -cne $paths.receipt -or [IO.Path]::GetFullPath($CommitPath) -cne $paths.commit){throw 'CommitPathsConflict'}
    $current=Read-RecoveryJson $paths.binding;$reserved=Read-RecoveryJson $paths.reservation
    Assert-PrestartCurrentBinding $current $p
    Assert-PrestartAttemptGroup $p $n $a $ctx $reserved
    if($current.state -cne 'failed' -or $current.failureCommitHash -cne $CommitHash -or $current.noSpawnReceiptHash -cne $ReceiptHash -or $reserved.state -cne 'failed' -or $reserved.failure_commit_hash -cne $CommitHash -or $reserved.no_spawn_receipt_hash -cne $ReceiptHash){throw 'PersistedFailureBindingGroupRequired'}
    $resultBytes=[Convert]::FromBase64String($r.resultPayloadBase64)
    if((Get-RecoveryHash $resultBytes) -cne $r.resultHash -or (Get-RecoveryHash ([IO.File]::ReadAllBytes($r.resultPath))) -cne $r.resultHash -or ('sha256:'+(Get-RecoveryHash ([Convert]::FromBase64String($r.candidatePayloadBase64)))) -cne $r.candidateRevision){throw 'ReceiptResultCandidateBytesConflict'}
    $result=Read-RecoveryJson $r.resultPath $r.resultHash
    if($result.model_started -ne $false -or $result.thread_id -or $result.turn_id -or $result.terminal_outcome -cne 'failed' -or $result.task_id -cne $r.taskId -or $result.execution_id -cne $r.executionId -or $result.dispatch_id -cne $r.executionId -or $result.work_item_id -cne $r.workItemId -or $result.parent_task_id -cne $r.parentTaskId -or $result.parent_job_path -cne $r.parentJobPath -or $result.parent_context_hash -cne $r.parentContextHash -or $result.start_intent_hash -cne $r.startIntentHash -or $result.work_item_store_path -cne $r.storePath -or $result.accounting_directory -cne $r.accountingDirectory -or $result.error -cne $r.reason -or $result.success -ne $false -or $result.no_spawn_receipt_path -cne [IO.Path]::GetFullPath($ReceiptPath)){throw 'NoSpawnResultContractConflict'}
    $sm=Import-Module (Join-Path $PSScriptRoot 'WorkItemStore.psm1') -PassThru -Force
    $sr=& $sm {param($r,$repo)Get-WorkItemStoreEffectReceipt -Path $r.storePath -EffectId $r.effectContext.effectId -RepositoryRoot $repo} $r $RepositoryRoot
    if(-not $sr -or $sr.state -cne 'published' -or $sr.receiptHash -cne $c.storeReceiptHash -or $sr.receiptPayloadBase64 -cne $c.storeReceiptPayloadBase64 -or $sr.previousRevision -cne $r.sourceRevision -or $sr.candidateRevision -cne $r.candidateRevision -or $sr.workItemId -cne $r.workItemId){throw 'PublishedStoreReceiptRequired'}
    if((Get-RecoveryHash (ConvertTo-RecoveryBytes $sr.context)) -cne (Get-RecoveryHash (ConvertTo-RecoveryBytes $r.effectContext))){throw 'StoreEffectContextConflict'}
    $live=& $sm {param($r,$repo)Get-WorkItemStoreResult -Path $r.storePath -RepositoryRoot $repo} $r $RepositoryRoot
    # Resume verifies the historical published CAS; its own terminal command CAS binds the current source revision.
    if(-not $HistoricalStoreReceipt -and $live.Revision -cne $r.candidateRevision){throw 'CurrentStoreCASMismatchRecoveryClosed'}
    $expectedOperation=& $sm {param($r)$b=[ordered]@{Id=$r.workItemId;IsNew=$false;ExpectedRevision=$r.sourceRevision;Item=$r.candidateItem;EffectContext=$r.effectContext};Get-WorkItemStoreSha256 ((New-Object Text.UTF8Encoding($false,$true)).GetBytes((ConvertTo-WorkItemStoreCanonicalJson $b)))} $r
    $expectedItem=& $sm {param($r)[Convert]::ToBase64String((New-Object Text.UTF8Encoding($false,$true)).GetBytes((ConvertTo-WorkItemStoreCanonicalJson $r.candidateItem)))} $r
    if($sr.operationHash -cne $expectedOperation -or $sr.itemPayloadBase64 -cne $expectedItem -or (Get-RecoveryHash (ConvertTo-RecoveryBytes $c.contextAuthorityAttempt)) -cne (Get-RecoveryHash (ConvertTo-RecoveryBytes $r.contextAuthorityAttempt))){throw 'StoreOperationOrCommitAuthorityConflict'}
    $candidate=ConvertFrom-Json -InputObject $script:RecoveryUtf8.GetString([Convert]::FromBase64String($r.candidatePayloadBase64))
    $ci=@($candidate.items|Where-Object{$_.id -ceq $r.workItemId})
    if($ci.Count -ne 1 -or $ci[0].status -cne 'blocked' -or $ci[0].blockReason -cne $r.reason -or (Get-RecoveryHash (ConvertTo-RecoveryBytes $ci[0])) -cne (Get-RecoveryHash (ConvertTo-RecoveryBytes $r.candidateItem))){throw 'CandidateWorkItemByteConflict'}
    [pscustomobject]@{receipt=$r;commit=$c;result=$result}
}
function Get-PrestartSaveParameters($Job,[string]$RepositoryRoot,[string]$Reason) {
    $rp=Get-PrestartRecoveryPaths $Job.accounting_directory $Job.execution_id $Job.work_item_store_path $Job.work_item_id
    $reserved=Read-RecoveryJson $rp.reservation
    if($reserved.task_id -cne $Job.task_id -or $reserved.parent_task_id -cne $Job.parent_task_id -or $reserved.result_path -cne [IO.Path]::GetFullPath($Job.result_file)){throw 'ReplayJobReservationMismatch'}
    foreach($n in @('no_spawn_attempt_path','no_spawn_attempt_hash')){if(-not $Job.$n){$Job|Add-Member -NotePropertyName $n -NotePropertyValue $reserved.$n -Force}}
    if(-not $Job.no_spawn_attempt_path){
        $proofKey=Get-RecoveryHash ([Text.Encoding]::UTF8.GetBytes([string]$Job.execution_id));$proofPath=Join-Path $Job.accounting_directory ('prestart-intent-'+$proofKey+'.json.nospawn.json')
        if([IO.File]::Exists($proofPath)){
            $Job|Add-Member -NotePropertyName no_spawn_attempt_path -NotePropertyValue $proofPath -Force
            $Job|Add-Member -NotePropertyName no_spawn_attempt_hash -NotePropertyValue (Get-RecoveryHash ([IO.File]::ReadAllBytes($proofPath))) -Force
        }
    }
    foreach($n in @('start_attempt_path','start_attempt_hash','no_spawn_attempt_path','no_spawn_attempt_hash','parent_context_path','parent_context_hash','start_intent_path','start_intent_hash','payload_hash')){if(-not $Job.$n){throw ('LegacyAttemptRecoveryClosed:'+ $n)}}
    $paths=Get-PrestartRecoveryPaths $Job.accounting_directory $Job.execution_id $Job.work_item_store_path $Job.work_item_id
    @{StorePath=$Job.work_item_store_path;RepositoryRoot=$RepositoryRoot;WorkItemId=$Job.work_item_id;TaskId=$Job.task_id;ParentTaskId=$Job.parent_task_id;ExecutionId=$Job.execution_id;ResultPath=$Job.result_file;ParentJobPath=$Job.parent_job_path;AccountingDirectory=$Job.accounting_directory;ParentContextPath=$Job.parent_context_path;ParentContextHash=$Job.parent_context_hash;StartIntentPath=$Job.start_intent_path;StartIntentHash=$Job.start_intent_hash;StartAttemptPath=$Job.start_attempt_path;StartAttemptHash=$Job.start_attempt_hash;NoSpawnAttemptPath=$Job.no_spawn_attempt_path;NoSpawnAttemptHash=$Job.no_spawn_attempt_hash;PayloadHash=$Job.payload_hash;NoSpawnReceiptPath=$paths.receipt;FailureCommitPath=$paths.commit;DispatchJournalPath=$Job.dispatch_journal_path;RegistryDirectory=$Job.registry_directory;Reason=$Reason}
}
function Complete-PrestartReceiptGroup {
    param($Saved,[string]$RepositoryRoot)
    $g=Assert-PrestartFailureCommit $Saved.noSpawnReceiptPath $Saved.noSpawnReceiptHash $Saved.failureCommitPath $Saved.failureCommitHash $RepositoryRoot
    $r=$g.receipt
    $dm=Import-Module (Join-Path $PSScriptRoot '..\coordinator\CoordinatorDispatch.psm1') -PassThru -Force
    & $dm {param($r,$s,$repo)Complete-CoordinatorPrestartDispatch -JournalPath $r.dispatchJournalPath -ExecutionId $r.executionId -TaskId $r.taskId -WorkItemId $r.workItemId -PayloadHash $r.payloadHash -ParentContextHash $r.parentContextHash -StartIntentHash $r.startIntentHash -ResultPath $r.resultPath -ResultHash $r.resultHash -NoSpawnReceiptPath $s.noSpawnReceiptPath -NoSpawnReceiptHash $s.noSpawnReceiptHash -FailureCommitPath $s.failureCommitPath -FailureCommitHash $s.failureCommitHash -RepositoryRoot $repo|Out-Null} $r $Saved $RepositoryRoot
    & (Join-Path $PSScriptRoot '..\coordinator\Register-CoordinatorExecution.ps1') -Action Release -DataDirectory $r.registryDirectory -TaskId $r.taskId -DispatchId $r.executionId -ResultPath $r.resultPath -PayloadHash $r.payloadHash -DispatchJournalPath $r.dispatchJournalPath -NoSpawnReceiptPath $Saved.noSpawnReceiptPath -NoSpawnReceiptHash $Saved.noSpawnReceiptHash -FailureCommitPath $Saved.failureCommitPath -FailureCommitHash $Saved.failureCommitHash -RepositoryRoot $RepositoryRoot|Out-Null
    $em=Import-Module (Join-Path $PSScriptRoot '..\coordinator\CoordinatorEvents.psm1') -PassThru -Force
    $source='prestart:'+ $r.executionId+':'+$Saved.failureCommitHash
    $payload=[ordered]@{taskId=$r.taskId;dispatchId=$r.executionId;workItemId=$r.workItemId;resultPath=$r.resultPath;resultHash=$r.resultHash;result=$g.result;noSpawnReceiptPath=$Saved.noSpawnReceiptPath;noSpawnReceiptHash=$Saved.noSpawnReceiptHash;failureCommitPath=$Saved.failureCommitPath;failureCommitHash=$Saved.failureCommitHash;parentContextHash=$r.parentContextHash;startIntentHash=$r.startIntentHash}
    $event=& $em {param($p,$s,$b)Add-CoordinatorEvent -Path $p -Kind return_received -SourceId $s -Payload $b -Durable} $r.eventJournalPath $source $payload
    [pscustomobject]@{returned=$true;released=$true;eventId=$event.id;failureCommitHash=$Saved.failureCommitHash}
}
function Resume-PrestartReservation {
    param([Parameter(Mandatory)][string]$AccountingDirectory,[Parameter(Mandatory)][string]$StorePath,[Parameter(Mandatory)][string]$WorkItemId,[Parameter(Mandatory)][string]$ExecutionId,[Parameter(Mandatory)][string]$RepositoryRoot)
    $paths=Get-PrestartRecoveryPaths $AccountingDirectory $ExecutionId $StorePath $WorkItemId
    $reservation=Read-RecoveryJson $paths.reservation
    $prepared=Read-RecoveryJson $reservation.start_attempt_path $reservation.start_attempt_hash
    $authority=Read-RecoveryJson $prepared.startIntentPath $prepared.startIntentHash
    $job=[pscustomobject]@{task_id=$prepared.taskId;parent_task_id=$prepared.parentTaskId;parent_job_path=$prepared.parentJobPath;parent_context_path=$prepared.parentContextPath;parent_context_hash=$prepared.parentContextHash;start_intent_path=$prepared.startIntentPath;start_intent_hash=$prepared.startIntentHash;start_attempt_path=$reservation.start_attempt_path;start_attempt_hash=$reservation.start_attempt_hash;payload_hash=$prepared.payloadHash;accounting_directory=[IO.Path]::GetFullPath($AccountingDirectory);work_item_store_path=[IO.Path]::GetFullPath($StorePath);work_item_id=$WorkItemId;execution_id=$ExecutionId;result_file=$prepared.resultPath;dispatch_journal_path=$prepared.dispatchJournalPath;registry_directory=$authority.parameters.CoordinatorDataDirectory;no_spawn_attempt_path=$reservation.no_spawn_attempt_path;no_spawn_attempt_hash=$reservation.no_spawn_attempt_hash}
    $proofKey=Get-RecoveryHash ([Text.Encoding]::UTF8.GetBytes($ExecutionId))
    $proofPath=Join-Path $AccountingDirectory ('prestart-intent-'+$proofKey+'.json.nospawn.json')
    $proof=Read-RecoveryJson $proofPath
    if($proof.phase -cne 'NoSpawnConfirmed' -or -not $proof.noSpawnProof.failure){throw 'ImmutablePositiveProofMissingRecoveryClosed'}
    $parameters=Get-PrestartSaveParameters $job $RepositoryRoot ([string]$proof.noSpawnProof.failure)
    & (Join-Path $PSScriptRoot 'Save-WorkItemPrestartFailure.ps1') @parameters
}
Export-ModuleMember -Function Get-RecoveryHash,ConvertTo-RecoveryBytes,Read-RecoveryJson,Write-RecoveryBytes,Get-PrestartRecoveryPaths,Assert-PrestartAttemptGroup,Assert-PrestartCurrentBinding,New-PrestartCurrentBinding,Get-PrestartEventJournal,Assert-PrestartFailureCommit,Get-PrestartSaveParameters,Complete-PrestartReceiptGroup,Resume-PrestartReservation
