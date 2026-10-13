# Optional solution metadata on the existing Host/Starter/WorkItem lifecycle.
. (Join-Path $PSScriptRoot '../coordinator/Lifecycle.Persistence.ps1')
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Read-ProductConfiguration($Reference) {
    if (-not $Reference) { return $null }
    $config = Read-LCReceipt $Reference
    if ($config.schemaVersion -cne '1.0') { throw 'ProductConfigurationVersionUnsupported' }
    $ids = @{}; $identities = @{}; $work = @{}
    foreach ($s in @($config.solutions)) {
        foreach ($n in @('solutionId','pmIdentity','ownerId')) {
            if ([string](Get-LCValue $s $n) -notmatch '^[a-z0-9][a-z0-9_-]{0,127}$') { throw ('ProductIdentityMissing:'+ $n) }
        }
        if ($ids.ContainsKey($s.solutionId) -or $identities.ContainsKey($s.pmIdentity)) { throw 'ProductIdentityNotUnique' }
        $ids[$s.solutionId]=$true; $identities[$s.pmIdentity]=$true
        if (-not [IO.Path]::IsPathRooted($s.workspaceRoot) -or -not [IO.Directory]::Exists($s.workspaceRoot)) { throw 'ProductWorkspaceUnresolved' }
        $docs=@{}
        foreach ($d in @($s.documents)) {
            if (-not $d.id -or $docs.ContainsKey($d.id) -or $d.kind -notin @('vision','strategy','roadmap','idea','assumption','decision','source')) { throw 'ProductDocumentIdentityInvalid' }
            $docs[$d.id]=$true
            if (-not [IO.Path]::IsPathRooted($d.path) -or $d.hash -notmatch '^[a-f0-9]{64}$') { throw 'ProductDocumentSourceUnresolved' }
        }
        foreach ($id in @($s.workItemIds)) {
            if ([string]$id -notmatch '^[a-z0-9][a-z0-9_-]{0,127}$' -or $work.ContainsKey($id)) { throw 'ProductWorkItemMappingAmbiguous' }
            $work[$id]=$true
        }
    }
    return $config
}

function Get-ProductBinding($Reference,[string]$WorkItemId,$WorkItems=@()) {
    $c=Read-ProductConfiguration $Reference
    if (-not $c -or -not $WorkItemId) { return $null }
    $lineage=@();$seen=@{};$cursor=$WorkItemId
    while ($cursor) {
        if ($seen.ContainsKey($cursor)) { throw 'ProductWorkItemAncestorCycle' }
        $seen[$cursor]=$true;$lineage+=$cursor
        $parents=@($WorkItems | Where-Object { $_.id -ceq $cursor })
        if ($parents.Count -gt 1) { throw 'ProductWorkItemAncestorAmbiguous' }
        if (-not $parents.Count) {
            if (@($WorkItems).Count) { throw 'ProductWorkItemAncestorMissing' }
            break
        }
        $cursor=[string]$parents[0].parentId
    }
    $matches=@($c.solutions | Where-Object { @($_.workItemIds | Where-Object { $lineage -ccontains $_ }).Count -gt 0 })
    if ($matches.Count -gt 1) { throw 'ProductWorkItemMappingAmbiguous' }
    if (-not $matches.Count) { return $null }
    return [pscustomobject]@{configuration=$Reference;solution=$matches[0]}
}

function Get-ProductDirectory([string]$DataDirectory,[string]$SolutionId) {
    if (-not [IO.Path]::IsPathRooted($DataDirectory) -or [IO.Path]::GetPathRoot($DataDirectory) -ine [IO.Path]::GetPathRoot([IO.Path]::GetFullPath($DataDirectory)) -or $SolutionId -notmatch '^[a-z0-9][a-z0-9_-]{0,127}$') { throw 'ProductDirectoryBindingInvalid' }
    $key=Get-LCHash ([Text.Encoding]::UTF8.GetBytes($SolutionId))
    return [IO.Path]::GetFullPath((Join-Path $DataDirectory ('products/'+$key)))
}

function Initialize-ProductDirectory([string]$DataDirectory,[string]$SolutionId) {
    $root=[IO.Path]::GetFullPath($DataDirectory).TrimEnd('\','/')+[IO.Path]::DirectorySeparatorChar
    $directory=Get-ProductDirectory $DataDirectory $SolutionId
    if (-not $directory.StartsWith($root,[StringComparison]::OrdinalIgnoreCase)) { throw 'ProductDirectoryOutsideDataDirectory' }
    # Reject existing redirected ancestors before creating anything and again after creation.
    foreach ($phase in @('before','after')) {
        $cursor=$directory
        while ($cursor) {
            if (Test-Path -LiteralPath $cursor) {
                $entry=Get-Item -LiteralPath $cursor -Force
                if (-not $entry.PSIsContainer -or ($entry.Attributes -band [IO.FileAttributes]::ReparsePoint)) { throw 'ProductDirectoryReparsePointOrFileUnsupported' }
            }
            $cursor=[IO.Path]::GetDirectoryName($cursor)
        }
        if ($phase -ceq 'before') { [void][IO.Directory]::CreateDirectory($directory) }
    }
    return $directory
}

function Get-ProductDecisionEnvelope($Binding,$Decision) {
    return [ordered]@{kind='product-decision-envelope-v1';solutionId=$Binding.solution.solutionId;pmIdentity=$Binding.solution.pmIdentity;configuration=[ordered]@{path=$Binding.configuration.path;hash=$Binding.configuration.hash};decision=$Decision}
}

function Assert-ProductReviewBinding($Binding,$Snapshot,[string]$ReviewWorkItemId,[string]$Digest) {
    if (-not $Snapshot.Exists -or -not $Snapshot.Revision -or @($Snapshot.Document.items | Where-Object { $_.id -ceq $ReviewWorkItemId }).Count -ne 1) { throw 'ProductReviewSnapshotMissing' }
    $reviewBinding=Get-ProductBinding $Binding.configuration $ReviewWorkItemId @($Snapshot.Document.items)
    if (-not $reviewBinding -or $reviewBinding.solution.solutionId -cne $Binding.solution.solutionId -or $reviewBinding.solution.pmIdentity -cne $Binding.solution.pmIdentity -or $reviewBinding.configuration.path -cne $Binding.configuration.path -or $reviewBinding.configuration.hash -cne $Binding.configuration.hash) { throw 'ProductReviewScopeConflict' }
    $review=@($Snapshot.Document.items | Where-Object { $_.id -ceq $ReviewWorkItemId -and $_.status -ceq 'accepted' })
    if ($review.Count -ne 1 -or @($review[0].result.evidence | Where-Object { $_ -ceq ('product-decision-sha256:'+ $Digest) }).Count -ne 1) { throw 'ProductDecisionExactAcceptedReviewMissing' }
    return $review[0]
}

function Enter-ProductLock([string]$Path) {
    $m=Import-Module (Join-Path $PSScriptRoot '../workitems/WorkItemStore.psm1') -PassThru
    $lock=& $m {param($p) Enter-WorkItemStoreLock $p 5000} $Path
    return [pscustomobject]@{module=$m;lock=$lock}
}
function Exit-ProductLock($Owner) {
    if ($Owner) { & $Owner.module {param($l) Exit-WorkItemStoreLock $l} $Owner.lock }
}

function Read-ProductDocument($Solution,$Document) {
    # Source paths are owner supplied, explicitly selected and confined to the solution.
    $root=[IO.Path]::GetFullPath($Solution.workspaceRoot).TrimEnd('\','/')+[IO.Path]::DirectorySeparatorChar
    $path=[IO.Path]::GetFullPath($Document.path)
    if (-not $path.StartsWith($root,[StringComparison]::OrdinalIgnoreCase)) { throw 'ProductDocumentOutsideWorkspace' }
    $cursor=$path
    while ($cursor -and $cursor.Length -ge $root.TrimEnd('\','/').Length) {
        if ((Get-Item -LiteralPath $cursor -Force).Attributes -band [IO.FileAttributes]::ReparsePoint) { throw 'ProductDocumentReparsePointUnsupported' }
        $cursor=[IO.Path]::GetDirectoryName($cursor)
    }
    if ([IO.Path]::GetExtension($path) -cne '.md') { throw 'ProductContextRequiresMarkdownSource' }
    $bytes=[IO.File]::ReadAllBytes($path)
    if ($bytes.Length -gt 65536 -or (Get-LCHash $bytes) -cne $Document.hash) { throw 'ProductDocumentSourceChangedOrTooLarge' }
    return [pscustomobject]@{id=$Document.id;kind=$Document.kind;path=$path;hash=$Document.hash;content=[Text.UTF8Encoding]::new($false,$true).GetString($bytes)}
}

function Get-ProductContext($Binding,[string]$DataDirectory,[string[]]$DocumentIds,[string[]]$DecisionIds) {
    if (-not $Binding) { return $null }
    $s=$Binding.solution; $documents=@()
    $DocumentIds=@($DocumentIds | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
    $DecisionIds=@($DecisionIds | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
    if (@($DocumentIds).Count -gt 8) { throw 'ProductContextSelectionTooLarge' }
    foreach ($id in @($DocumentIds | Select-Object -Unique)) {
        $d=@($s.documents | Where-Object { $_.id -ceq $id })
        if ($d.Count -ne 1) { throw 'ProductDocumentSelectionUnknown' }
        $documents+=Read-ProductDocument $s $d[0]
    }
    $directory=Get-ProductDirectory $DataDirectory $s.solutionId
    $path=Join-Path $directory 'memory.json'
    $memory=@(); $decisionIndex=@()
    if (-not [IO.File]::Exists($path) -and $DecisionIds.Count) { throw 'ProductDecisionSelectionUnknown' }
    if ([IO.File]::Exists($path)) {
        $journal=Read-LCArchive $path ([IO.File]::ReadAllText($path) | ConvertFrom-Json)
        $replaced=@{}
        foreach ($ref in @($journal.entries)) {
            $entry=Read-LCReceipt $ref
            if ($entry.solutionId -cne $s.solutionId -or $entry.pmIdentity -cne $s.pmIdentity) { throw 'ProductMemoryIdentityConflict' }
            if ($entry.supersedes -and $entry.status -ceq 'accepted') { $replaced[[string]$entry.supersedes]=$true }
            $memory+= [pscustomobject]@{reference=$ref;entry=$entry}
        }
        $memory=@($memory | Where-Object { -not $replaced.ContainsKey([string]$_.reference.hash) -and $_.entry.status -ceq 'accepted' })
        $decisionIndex=@($memory | ForEach-Object { [pscustomobject]@{id=$_.entry.id;date=$_.entry.date;reference=$_.reference} })
        if (@($DecisionIds).Count -gt 20) { throw 'ProductDecisionSelectionTooLarge' }
        $selected=@()
        foreach ($id in @($DecisionIds | Select-Object -Unique)) {
            $entry=@($memory | Where-Object { $_.entry.id -ceq $id })
            if ($entry.Count -ne 1) { throw 'ProductDecisionSelectionUnknownOrAmbiguous' }
            $selected+=$entry[0]
        }
        $memory=$selected
    }
    return [pscustomobject]@{solutionId=$s.solutionId;pmIdentity=$s.pmIdentity;ownerId=$s.ownerId;configuration=$Binding.configuration;documents=$documents;decisionIndex=$decisionIndex;decisions=$memory;rules=@('PM strategy -> product team leader -> PO backlog; specialist team work only via coordinator','Only explicit review establishes acceptance; thread text is not authoritative product memory','No idle model calls; outcome observations and due reviews use existing WorkItem events')}
}

function Get-ProductSessionBindingHash($Session) {
    $value=[ordered]@{}
    foreach ($name in @('solutionId','pmIdentity','configuration','profileHash','generation','threadId','threadReceipt','executionId','workItemId','taskId','turnId','terminalReceipt','resultReceipt')) {
        $value[$name]=Get-LCValue $Session $name
    }
    return Get-LCHash (Get-LCBytes $value)
}

function Assert-ProductRecoveryUnconsumed($Session,$Intent,[string]$Directory) {
    if ($Intent.kind -cne 'product-recovery-intent-v1' -or $Intent.sessionBindingHash -cne (Get-ProductSessionBindingHash $Session) -or [int]$Intent.generation -ne ([int]$Session.generation+1) -or (Get-LCValue $Session 'replacementStartIntent')) { throw 'ProductRecoveryIntentConsumedOrUncertain' }
    # An immutable start may precede a failed session commit: do not reuse that generation.
    $starts=Join-Path $Directory 'recovery-starts'
    if ([IO.Directory]::Exists($starts)) {
        foreach ($file in [IO.Directory]::GetFiles($starts,'*.json')) {
            $record=Read-LCReceipt ([pscustomobject]@{path=$file;hash=[IO.Path]::GetFileNameWithoutExtension($file)})
            if ($record.kind -ceq 'product-replacement-response-v1') { $record=Read-LCReceipt $record.startIntent }
            if ($record.kind -cne 'product-replacement-start-intent-v1') { throw 'ProductRecoveryIntentConsumedOrUncertain' }
            if ($record.kind -ceq 'product-replacement-start-intent-v1' -and ($record.recoveryId -ceq $Intent.recoveryId -or [int]$record.generation -eq [int]$Intent.generation)) { throw 'ProductRecoveryIntentConsumedOrUncertain' }
        }
    }
}

function Assert-ProductRecoverySnapshot($Plan,$Snapshot,$Job) {
    if ($Plan.workItemId -cne $Job.work_item_id -or $Plan.workItemSnapshot.storePath -cne [IO.Path]::GetFullPath($Job.work_item_store_path)) { throw 'ProductRecoveryIntentCASConflict' }
    if ($Plan.workItemSnapshot.revision -ceq $Snapshot.Revision) { return }
    $transition=Read-LCReceipt (Get-LCValue $Job 'product_start_transition')
    if ($transition.kind -cne 'product-starter-transition-v1' -or $transition.executionId -cne $Job.execution_id -or $transition.taskId -cne $Job.task_id -or $transition.workItemId -cne $Job.work_item_id -or $transition.ownerId -cne $Job.role -or $transition.storePath -cne $Plan.workItemSnapshot.storePath -or $transition.parentTaskId -cne $Job.parent_task_id -or $transition.parentJobPath -cne $Job.parent_job_path -or $transition.sourceRevision -cne $Plan.workItemSnapshot.revision -or $transition.candidateRevision -cne $Snapshot.Revision) { throw 'ProductRecoveryIntentCASConflict' }
    if ((Get-LCHash (Get-LCBytes $transition.sourceDocument)) -cne (Get-LCHash (Get-LCBytes $Plan.workItemSnapshot.document))) { throw 'ProductRecoveryIntentCASConflict' }
    $effect=$transition.effectContext
    if ($effect.effectId -cne ('prestart-start:'+$Job.execution_id) -or $effect.executionId -cne $Job.execution_id -or $effect.inputHash -cne $Job.start_intent_hash -or $effect.planHash -cne $Job.start_attempt_hash -or $effect.threadId -cne $Job.parent_thread_id -or $effect.turnId -cne $Job.parent_turn_id) { throw 'ProductRecoveryIntentCASConflict' }
    $module=Get-Module WorkItemStore
    $receipt=& $module {param($r) ConvertTo-WorkItemStoreReceipt $r} $transition.effectReceipt
    if ($receipt.state -cne 'published' -or -not $receipt.changed -or $receipt.workItemId -cne $Job.work_item_id -or $receipt.previousRevision -cne $transition.sourceRevision -or $receipt.candidateRevision -cne $Snapshot.Revision -or (Get-LCHash (Get-LCBytes $receipt.context)) -cne (Get-LCHash (Get-LCBytes $effect))) { throw 'ProductRecoveryIntentCASConflict' }
    $candidate=ConvertFrom-Json -InputObject ([Text.UTF8Encoding]::new($false,$true).GetString((Get-LCBytes $Plan.workItemSnapshot.document)))
    $item=@($candidate.items | Where-Object { $_.id -ceq $Job.work_item_id })
    if ($item.Count -ne 1 -or $item[0].owner.id -cne $Job.role -or $item[0].status -notin @('planned','rework') -or -not $transition.updatedAt) { throw 'ProductRecoveryIntentCASConflict' }
    $item[0].status='in_progress';$item[0].blockReason=$null;$item[0].updatedAt=$transition.updatedAt
    $candidateBytes=& $module {param($d) ,(ConvertTo-WorkItemStoreCandidate $d)} $candidate
    if (('sha256:'+(Get-LCHash $candidateBytes)) -cne $Snapshot.Revision -or (Get-LCHash (Get-LCBytes $candidate)) -cne (Get-LCHash (Get-LCBytes $Snapshot.Document))) { throw 'ProductRecoveryIntentCASConflict' }
}

function Save-ProductRecoveryIntent($Plan,[string]$Directory,[string]$SessionPath) {
    # Caller holds the existing session and WorkItem store locks.
    if (-not $Plan.priorSession -or $Plan.priorSession.path -cne $SessionPath) { throw 'ProductRecoveryPriorSessionMissing' }
    $bytes=[IO.File]::ReadAllBytes($SessionPath)
    if ((Get-LCHash $bytes) -cne $Plan.priorSession.hash -or [Convert]::ToBase64String($bytes) -cne $Plan.priorSession.originalBase64) { throw 'ProductRecoverySessionCASConflict' }
    $session=Read-LCArchive $SessionPath ([Text.UTF8Encoding]::new($false,$true).GetString($bytes) | ConvertFrom-Json)
    if ($session.state -notin @('Ready','Resuming','RecoveryClosed','RecoveryPlanned') -or -not $session.threadId -or -not $session.terminalReceipt -or -not (Get-LCValue $session 'resultReceipt')) { throw 'ProductRecoveryPriorLifecycleUnresolved' }
    $predecessor=$null
    if ($session.state -in @('RecoveryPlanned','RecoveryClosed')) {
        $predecessor=$session.recoveryIntent
        Assert-ProductRecoveryUnconsumed $session (Read-LCReceipt $predecessor) $Directory
    }
    if ($session.solutionId -cne $Plan.solutionId -or $session.pmIdentity -cne $Plan.pmIdentity -or $session.configuration.path -cne $Plan.configuration.path -or $session.configuration.hash -cne $Plan.configuration.hash) { throw 'ProductRecoveryIntentBindingConflict' }
    if ($session.state -ceq 'Ready') {
        Set-LCValue $session 'priorReadySession' (Save-LCImmutable (Join-Path $Directory 'receipts') ([ordered]@{hash=(Get-LCHash $bytes);originalBase64=[Convert]::ToBase64String($bytes)}))
    }
    $intent=[ordered]@{kind='product-recovery-intent-v1';recoveryId=[guid]::NewGuid().ToString('N');generation=([int]$session.generation+1);sessionBindingHash=(Get-ProductSessionBindingHash $session);plan=$Plan}
    if ($predecessor) { $intent.predecessor=$predecessor }
    $reference=Save-LCImmutable (Join-Path $Directory 'recovery-intents') $intent
    Set-LCValue $session 'recoveryIntent' $reference
    $session.state='RecoveryPlanned'
    Write-LCJournal $SessionPath $session
    return $reference
}

function Get-ProductResumeDenial($Runtime,$Attempt,[string]$ThreadId) {
    # No reviewed version-bound denial classifier is supplied by the installed
    # contract. Do not accept a caller's boolean, text, status, or error code as
    # the missing provider guarantee. Only this adapter may eventually classify
    # a documented native thread/resume denial for the pinned runtime.
    return [pscustomobject]@{definitive=$false;reason='VersionBoundDefinitiveResumeSemanticsUnspecified';runtime=$Runtime;threadId=$ThreadId;rpc=(Get-LCValue $Attempt 'rpc')}
}

function Get-ProductPriorLifecycle($Session,$Job) {
    # Ready is published only after the existing starter confirms release and
    # runner exit. Preserve that original record; no new external OwnerReceipt.
    $readyReference=Get-LCValue $Session 'priorReadySession'
    if (-not $readyReference) { throw 'ProductRecoveryLocalReadyEvidenceMissing' }
    $readyRecord=Read-LCReceipt $readyReference
    $readyBytes=[Convert]::FromBase64String($readyRecord.originalBase64)
    if ((Get-LCHash $readyBytes) -cne $readyRecord.hash) { throw 'ProductRecoveryReadyBytesConflict' }
    $ready=[Text.UTF8Encoding]::new($false,$true).GetString($readyBytes) | ConvertFrom-Json
    if ($ready.state -cne 'Ready' -or (Get-ProductSessionBindingHash $ready) -cne (Get-ProductSessionBindingHash $Session)) { throw 'ProductRecoveryLocalReadyBindingConflict' }
    $resultReceipt=Read-LCReceipt $Session.resultReceipt
    $result=$resultReceipt.result
    if ($result.execution_id -cne $Session.executionId -or $result.thread_id -cne $Session.threadId -or $result.turn_id -cne $Session.turnId -or $result.terminal_outcome -notin @('completed','failed','interrupted') -or (Get-LCValue $result 'transfer_error')) { throw 'ProductRecoveryLocalResultConflict' }
    $oldJob=[IO.File]::ReadAllText($resultReceipt.path+'.job.json') | ConvertFrom-Json
    if ($oldJob.execution_id -cne $Session.executionId -or $oldJob.task_id -cne $Session.taskId -or $oldJob.registry_directory -cne $Job.registry_directory -or (Get-LCHash ([IO.File]::ReadAllBytes($resultReceipt.path))) -cne $resultReceipt.hash) { throw 'ProductRecoveryLocalRegistryBindingConflict' }
    $registryPath=Join-Path $Job.registry_directory 'executions.json'
    $mutex=New-Object Threading.Mutex($false,'Global\AgentOrganizationCoordinatorExecutions')
    if (-not $mutex.WaitOne(5000)) { $mutex.Dispose(); throw 'ProductRecoveryRegistryLockUnavailable' }
    try {
        $bytes=[IO.File]::ReadAllBytes($registryPath)
        $entries=@([Text.UTF8Encoding]::new($false,$true).GetString($bytes) | ConvertFrom-Json)
        $taskKey=([guid]$Session.taskId).ToString('D')
        $dispatchKey=([guid]$result.dispatch_id).ToString('D')
        $matches=@($entries | Where-Object { ([guid]$_.taskId).ToString('D') -ceq $taskKey -or $_.nativeThreadId -ceq $Session.threadId })
        # Registry resultPath binds the original result, not the immutable receipt.
        $exact=@($matches | Where-Object { ([guid]$_.taskId).ToString('D') -ceq $taskKey -and ([guid]$_.dispatchId).ToString('D') -ceq $dispatchKey -and $_.nativeThreadId -ceq $Session.threadId -and $_.state -ceq 'terminal' -and $_.terminalAt -and [IO.Path]::GetFullPath($_.resultPath) -ceq [IO.Path]::GetFullPath($resultReceipt.path) })
        if ($exact.Count -ne 1 -or @($matches | Where-Object { $_.state -cne 'terminal' }).Count) { throw 'ProductRecoveryLocalReservationNotReleased' }
        return [ordered]@{registryPath=$registryPath;registryHash=(Get-LCHash $bytes);entry=$exact[0];readySession=$readyReference;terminalReceipt=$Session.terminalReceipt;resultReceipt=$Session.resultReceipt}
    } finally { $mutex.ReleaseMutex();$mutex.Dispose() }
}

function Invoke-ProductReplacement($Binding,[string]$DataDirectory,$Job,$Rpc,$Session,[string]$Path,[string]$Directory,$Intent,$Attempt,$Snapshot) {
    $plan=$Intent.plan
    Assert-ProductRecoverySnapshot $plan $Snapshot $Job
    Assert-ProductRecoveryUnconsumed $Session $Intent $Directory
    $context=Get-ProductContext $Binding $DataDirectory @($plan.context.documents | ForEach-Object { $_.id }) @($plan.context.decisions | ForEach-Object { $_.entry.id })
    if ((Get-LCHash (Get-LCBytes $context)) -cne (Get-LCHash (Get-LCBytes $plan.context))) { throw 'ProductRecoveryContextChanged' }
    $attemptRef=Save-LCImmutable (Join-Path $Directory 'recovery-attempts') ([ordered]@{kind='product-recovery-resume-observation-v1';recoveryId=$Intent.recoveryId;priorThreadId=$Session.threadId;attempt=$Attempt})
    $denial=Get-ProductResumeDenial $Job.admission_runtime $Attempt $Session.threadId
    if (-not $denial.definitive) {
        Set-LCValue $Session 'recoveryObservation' $attemptRef
        $Session.state='RecoveryClosed';Write-LCJournal $Path $Session
        throw ('BlockedRecovery: '+$denial.reason)
    }
    $lifecycle=Get-ProductPriorLifecycle $Session $Job
    # Persist a single consumption record before the only replacement RPC.
    $startIntent=Save-LCImmutable (Join-Path $Directory 'recovery-starts') ([ordered]@{kind='product-replacement-start-intent-v1';recoveryId=$Intent.recoveryId;generation=$Intent.generation;priorThreadId=$Session.threadId;priorExecutionId=$Session.executionId;priorTurnId=$Session.turnId;newExecutionId=$Job.execution_id;newTaskId=$Job.task_id;workItemId=$Job.work_item_id;intent=$Session.recoveryIntent;resumeObservation=$attemptRef;denial=$denial;lifecycle=$lifecycle;context=$context})
    $priorThread=$Session.threadId
    Set-LCValue $Session 'replacementStartIntent' $startIntent
    $Session.state='StartingReplacement';Write-LCJournal $Path $Session
    $answer=& $Rpc 'thread/start' @{cwd=$Job.cwd;model=$Job.model;sandbox=$Job.sandbox;approvalPolicy=$Job.approval_policy;developerInstructions=$Job.developer_instructions;config=$Job.config}
    $answerRef=Save-LCImmutable (Join-Path $Directory 'recovery-starts') ([ordered]@{kind='product-replacement-response-v1';recoveryId=$Intent.recoveryId;startIntent=$startIntent;answer=$answer})
    if ((Get-LCValue $answer 'failure') -or -not $answer.reply -or -not $answer.reply.thread.id -or $answer.reply.thread.id -ceq $priorThread -or -not $answer.rpc -or $answer.rpc.method -cne 'thread/start') { throw 'BlockedRecovery: ProductReplacementStartUnknown; never repeat' }
    $Session.threadId=[string]$answer.reply.thread.id
    $Session.generation=[int]$Intent.generation
    $Session.threadReceipt=Save-LCImmutable (Join-Path $Directory 'receipts') ([ordered]@{kind='product-thread-ack-v1';solutionId=$Session.solutionId;pmIdentity=$Session.pmIdentity;profileHash=$Session.profileHash;configuration=$Binding.configuration;threadId=$Session.threadId;reply=$answer.reply;rpc=$answer.rpc})
    $event=Save-LCImmutable (Join-Path $Directory 'recovery-events') ([ordered]@{kind='product-replacement-provenance-v1';recoveryId=$Intent.recoveryId;solutionId=$Session.solutionId;pmIdentity=$Session.pmIdentity;intent=$Session.recoveryIntent;startIntent=$startIntent;response=$answerRef;priorThreadId=$priorThread;newThreadId=$Session.threadId;generation=$Session.generation;threadReceipt=$Session.threadReceipt})
    Set-LCValue $Session 'recoveryEvents' (@(Get-LCValue $Session 'recoveryEvents' @())+@($event))
    return [pscustomobject]@{reply=$answer.reply;rpc=$answer.rpc;context=$context}
}

function Open-ProductSession($Binding,[string]$DataDirectory,$Job,$Rpc) {
    $s=$Binding.solution
    $parent=ConvertFrom-Json -InputObject ([IO.File]::ReadAllText($Job.parent_job_path))
    if ($Job.role -cne 'produktmanagement_pm_strategie' -or -not $Job.work_item_id -or $parent.role -cne 'teamleiter_produktmanagement') { throw 'ProductSessionRequiresOwnedPMWorkItem' }
    $directory=Initialize-ProductDirectory $DataDirectory $s.solutionId
    $path=Join-Path $directory 'session.json'
    $owner=Enter-ProductLock $path
    $storeOwner=$null
    try {
        if (-not [IO.Path]::IsPathRooted($Job.work_item_store_path)) { throw 'ProductWorkItemStorePathUnresolved' }
        $storeOwner=Enter-ProductLock $Job.work_item_store_path
        $snapshot=& $storeOwner.module {param($p,$root) Get-WorkItemStoreSnapshot $p $root} $Job.work_item_store_path (Split-Path -Parent (Split-Path -Parent $PSScriptRoot))
        $fresh=Get-ProductBinding $Binding.configuration $Job.work_item_id @($snapshot.Document.items)
        if (-not $snapshot.Exists -or -not $fresh -or $fresh.solution.solutionId -cne $s.solutionId -or $fresh.solution.pmIdentity -cne $s.pmIdentity) { throw 'ProductActivationBindingChanged' }
        $owned=@($snapshot.Document.items | Where-Object { $_.id -ceq $Job.work_item_id -and $_.owner.id -ceq $Job.role -and $_.status -in @('planned','in_progress','rework') })
        if ($owned.Count -ne 1) { throw 'ProductPMWorkItemOwnerOrStateChanged' }
        $Binding=$fresh;$s=$fresh.solution
        $context=Get-ProductContext $Binding $DataDirectory @(Get-LCValue $s 'activationDocumentIds' @()) @(Get-LCValue $s 'activationDecisionIds' @())
        $profile=[ordered]@{role=$Job.role;cwd=$Job.cwd;model=$Job.model;sandbox=$Job.sandbox;approvalPolicy=$Job.approval_policy;developerInstructions=$Job.developer_instructions;config=$Job.config;runtime=$Job.admission_runtime}
        $profileHash=Get-LCHash (Get-LCBytes $profile)
        $session=$null
        if ([IO.File]::Exists($path)) { $session=Read-LCArchive $path ([IO.File]::ReadAllText($path) | ConvertFrom-Json) }
        if ($session) {
            if ($session.solutionId -cne $s.solutionId -or $session.pmIdentity -cne $s.pmIdentity -or $session.profileHash -cne $profileHash -or $session.configuration.path -cne $Binding.configuration.path -or $session.configuration.hash -cne $Binding.configuration.hash) { throw 'BlockedRecovery: ProductSessionBindingChanged' }
            if ($session.state -notin @('Ready','RecoveryPlanned') -or -not $session.threadId) { throw 'BlockedRecovery: ProductPriorActivationUnresolved' }
            $intent=$null
            if ($session.state -ceq 'RecoveryPlanned') {
                $intent=Read-LCReceipt $session.recoveryIntent
                Assert-ProductRecoveryUnconsumed $session $intent $directory
                Assert-ProductRecoverySnapshot $intent.plan $snapshot $Job
                if ($intent.plan.solutionId -cne $s.solutionId -or $intent.plan.pmIdentity -cne $s.pmIdentity -or $intent.plan.configuration.path -cne $Binding.configuration.path -or $intent.plan.configuration.hash -cne $Binding.configuration.hash) { throw 'ProductRecoveryIntentCASConflict' }
                $context=Get-ProductContext $Binding $DataDirectory @($intent.plan.context.documents | ForEach-Object { $_.id }) @($intent.plan.context.decisions | ForEach-Object { $_.entry.id })
                if ((Get-LCHash (Get-LCBytes $context)) -cne (Get-LCHash (Get-LCBytes $intent.plan.context))) { throw 'ProductRecoveryContextChanged' }
            } else {
                $readyBytes=[IO.File]::ReadAllBytes($path)
                Set-LCValue $session 'priorReadySession' (Save-LCImmutable (Join-Path $directory 'receipts') ([ordered]@{hash=(Get-LCHash $readyBytes);originalBase64=[Convert]::ToBase64String($readyBytes)}))
            }
            if ($session.executionId -ceq $Job.execution_id) { throw 'ProductExecutionAlreadyTerminal; use existing result and receipts' }
            $ack=Read-LCReceipt $session.threadReceipt
            if ($ack.threadId -cne $session.threadId -or $ack.solutionId -cne $s.solutionId -or $ack.pmIdentity -cne $s.pmIdentity -or $ack.profileHash -cne $profileHash) { throw 'BlockedRecovery: ProductThreadReceiptConflict' }
            $terminal=Read-LCReceipt $session.terminalReceipt
            if ($terminal.solutionId -cne $s.solutionId -or $terminal.pmIdentity -cne $s.pmIdentity -or $terminal.executionId -cne $session.executionId -or $terminal.completion.params.threadId -cne $session.threadId -or $terminal.completion.params.turn.id -cne $session.turnId) { throw 'BlockedRecovery: ProductTerminalReceiptConflict' }
            $resultReceipt=Read-LCReceipt $session.resultReceipt
            if ($resultReceipt.result.execution_id -cne $session.executionId -or $resultReceipt.result.thread_id -cne $session.threadId -or $resultReceipt.result.turn_id -cne $session.turnId) { throw 'BlockedRecovery: ProductResultReceiptConflict' }
            $session.state='Resuming'; Write-LCJournal $path $session
            $answer=& $Rpc 'thread/resume' @{threadId=$session.threadId};$reply=$answer.reply;$nativeRpc=$answer.rpc
            if ((Get-LCValue $answer 'failure') -or -not $reply) {
                if (-not $intent) {
                    # Save independent intent even without provider definitivity.
                    $bytes=[IO.File]::ReadAllBytes($path)
                    $plan=[ordered]@{kind='product-document-recovery-proposal-v1';solutionId=$s.solutionId;pmIdentity=$s.pmIdentity;configuration=$Binding.configuration;workItemId=$Job.work_item_id;workItemSnapshot=[ordered]@{storePath=[IO.Path]::GetFullPath($Job.work_item_store_path);revision=$snapshot.Revision;document=$snapshot.Document};reason='resume_observation_unclassified';priorSession=[ordered]@{path=$path;hash=(Get-LCHash $bytes);originalBase64=[Convert]::ToBase64String($bytes)};context=$context}
                    $ref=Save-ProductRecoveryIntent $plan $directory $path
                    $session=Read-LCArchive $path ([IO.File]::ReadAllText($path) | ConvertFrom-Json)
                    $intent=Read-LCReceipt $ref
                }
                $replacement=Invoke-ProductReplacement $Binding $DataDirectory $Job $Rpc $session $path $directory $intent $answer $snapshot
                $reply=$replacement.reply;$nativeRpc=$replacement.rpc;$context=$replacement.context
            } else {
                if ($reply.thread.id -cne $session.threadId) { throw 'BlockedRecovery: ProductResumeThreadMismatch' }
                $readAnswer=& $Rpc 'thread/read' @{threadId=$session.threadId;includeTurns=$true};$read=$readAnswer.reply
                if ((Get-LCValue $readAnswer 'failure') -or -not $read) { throw 'BlockedRecovery: ProductThreadReadUnknown' }
                if ($read.thread.id -cne $session.threadId -or $read.thread.status.type -cne 'idle') { throw 'BlockedRecovery: ProductThreadNotIdle' }
                $turns=@($read.thread.turns | Where-Object { $_.id -ceq $session.turnId })
                if ($turns.Count -ne 1 -or $turns[0].status -cne $terminal.completion.params.turn.status) { throw 'BlockedRecovery: ProductTerminalHistoryMissing' }
                $session.generation=[int]$session.generation+1
            }
        } else {
            $session=[pscustomobject]@{solutionId=$s.solutionId;pmIdentity=$s.pmIdentity;configuration=$Binding.configuration;profileHash=$profileHash;state='Starting';threadId=$null;threadReceipt=$null;generation=1;executionId=$Job.execution_id;workItemId=$Job.work_item_id;taskId=$Job.task_id;turnId=$null;terminalReceipt=$null}
            # Durable intent precedes the only thread/start. Unknown start is never repeated.
            Write-LCJournal $path $session
            $answer=& $Rpc 'thread/start' @{cwd=$Job.cwd;model=$Job.model;sandbox=$Job.sandbox;approvalPolicy=$Job.approval_policy;developerInstructions=$Job.developer_instructions;config=$Job.config};$reply=$answer.reply;$nativeRpc=$answer.rpc
            if ((Get-LCValue $answer 'failure') -or -not $reply) { throw 'BlockedRecovery: ProductStartUnknown; never repeat' }
            if (-not $reply.thread.id) { throw 'BlockedRecovery: ProductThreadACKMissing' }
            $session.threadId=[string]$reply.thread.id
            $session.threadReceipt=Save-LCImmutable (Join-Path $directory 'receipts') ([ordered]@{kind='product-thread-ack-v1';solutionId=$s.solutionId;pmIdentity=$s.pmIdentity;profileHash=$profileHash;configuration=$Binding.configuration;threadId=$session.threadId;reply=$reply;rpc=$nativeRpc})
        }
        $session.state='ActivationPrepared';$session.executionId=$Job.execution_id;$session.workItemId=$Job.work_item_id;$session.taskId=$Job.task_id;$session.turnId=$null
        Write-LCJournal $path $session
        return [pscustomobject]@{owner=$owner;path=$path;directory=$directory;session=$session;reply=$reply;rpc=$nativeRpc;context=$context}
    } catch { Exit-ProductLock $owner; throw }
    finally { Exit-ProductLock $storeOwner }
}

function Set-ProductTurn($Activation,[string]$TurnId) {
    if (-not $TurnId -or $Activation.session.state -cne 'ActivationPrepared') { throw 'ProductTurnBindingInvalid' }
    $Activation.session.turnId=$TurnId; $Activation.session.state='Running'
    Write-LCJournal $Activation.path $Activation.session
}
function Complete-ProductSession($Activation,$Completion) {
    $s=$Activation.session
    if ($Completion.params.threadId -cne $s.threadId -or $Completion.params.turn.id -cne $s.turnId -or $Completion.params.turn.status -notin @('completed','failed','interrupted')) { throw 'ProductTerminalBindingInvalid' }
    $s.terminalReceipt=Save-LCImmutable (Join-Path $Activation.directory 'receipts') ([ordered]@{kind='product-terminal-v1';solutionId=$s.solutionId;pmIdentity=$s.pmIdentity;generation=$s.generation;executionId=$s.executionId;workItemId=$s.workItemId;taskId=$s.taskId;completion=$Completion})
    $s.state='TerminalPendingTransfer';Write-LCJournal $Activation.path $s
}
function Publish-ProductSession($Activation,[string]$ResultPath) {
    if ($Activation.session.state -cne 'TerminalPendingTransfer') { throw 'ProductTerminalTransferUnresolved' }
    $bytes=[IO.File]::ReadAllBytes($ResultPath);$result=ConvertFrom-Json -InputObject ([Text.UTF8Encoding]::new($false,$true).GetString($bytes))
    if ($result.thread_id -cne $Activation.session.threadId -or $result.turn_id -cne $Activation.session.turnId -or (Get-LCValue $result 'transfer_error') -or $result.terminal_outcome -notin @('completed','failed','interrupted')) { throw 'ProductResultTransferConflict' }
    $Activation.session | Add-Member -NotePropertyName resultReceipt -NotePropertyValue (Save-LCImmutable (Join-Path $Activation.directory 'receipts') ([ordered]@{path=$ResultPath;hash=(Get-LCHash $bytes);result=$result})) -Force
    $Activation.session.state='Ready';Write-LCJournal $Activation.path $Activation.session
}

function Save-ProductDecision {
    [CmdletBinding()]
    param($Binding,[string]$DataDirectory,$Decision,[string]$ExpectedRevision,[string]$StorePath,[string]$RepositoryRoot,[string]$ReviewWorkItemId)
    $s=$Binding.solution
    foreach ($n in @('id','date','context','reasons','alternatives','consequences','status','sources','supersedes')) {
        if ($null -eq $Decision.PSObject.Properties[$n]) { throw ('ProductDecisionFieldMissing:'+ $n) }
    }
    if ($Decision.status -notin @('proposed','accepted','rejected') -or -not $Decision.id -or -not $Decision.context -or -not $Decision.reasons -or -not @($Decision.sources).Count) { throw 'ProductDecisionIncomplete' }
    [void][DateTimeOffset]::Parse([string]$Decision.date)
    foreach ($source in @($Decision.sources)) { [void](Read-LCReceipt $source) }
    $envelope=Get-ProductDecisionEnvelope $Binding $Decision
    $digest=Get-LCHash (Get-LCBytes $envelope)
    $review=$null
    if ($Decision.status -ne 'proposed') {
        # Existing Reader/CAS store remains authoritative; no fake owner or ACK.
        $snapshot=& (Join-Path $PSScriptRoot '../workitems/Get-WorkItems.ps1') -Path $StorePath -RepositoryRoot $RepositoryRoot
        $item=Assert-ProductReviewBinding $Binding $snapshot $ReviewWorkItemId $digest
        $review=[ordered]@{workItemId=$ReviewWorkItemId;storePath=$StorePath;revision=$snapshot.Revision;snapshot=$snapshot.Document;item=$item}
    }
    $directory=Initialize-ProductDirectory $DataDirectory $s.solutionId;$path=Join-Path $directory 'memory.json'
    $owner=Enter-ProductLock $path
    try {
        $revision='absent';$journal=[pscustomobject]@{entries=@()}
        if ([IO.File]::Exists($path)) { $bytes=[IO.File]::ReadAllBytes($path);$revision='sha256:'+(Get-LCHash $bytes);$journal=Read-LCArchive $path ([Text.UTF8Encoding]::new($false,$true).GetString($bytes) | ConvertFrom-Json) }
        if ($ExpectedRevision -cne $revision) { throw 'ProductMemoryRevisionConflict' }
        if ($Decision.supersedes -and @($journal.entries | Where-Object { $_.hash -ceq $Decision.supersedes }).Count -ne 1) { throw 'ProductDecisionPredecessorUnknown' }
        if ($Decision.supersedes) {
            $predecessorRef=@($journal.entries | Where-Object { $_.hash -ceq $Decision.supersedes })[0]
            $predecessor=Read-LCReceipt $predecessorRef
            if ($predecessor.solutionId -cne $s.solutionId -or $predecessor.pmIdentity -cne $s.pmIdentity -or $predecessor.id -cne $Decision.id) { throw 'ProductDecisionPredecessorIdentityConflict' }
        }
        if ($Decision.status -ceq 'accepted') {
            $records=@();$replaced=@{}
            foreach ($oldRef in @($journal.entries)) {
                $old=Read-LCReceipt $oldRef
                if ($old.status -ceq 'accepted' -and $old.supersedes) { $replaced[[string]$old.supersedes]=$true }
                $records+=[pscustomobject]@{reference=$oldRef;entry=$old}
            }
            $active=@($records | Where-Object { $_.entry.id -ceq $Decision.id -and $_.entry.status -ceq 'accepted' -and -not $replaced.ContainsKey([string]$_.reference.hash) })
            if ($active.Count -gt 1 -or ($active.Count -eq 1 -and $Decision.supersedes -cne $active[0].reference.hash)) { throw 'ProductDecisionNeedsExactActivePredecessor' }
            if ($Decision.supersedes -and $replaced.ContainsKey([string]$Decision.supersedes)) { throw 'ProductDecisionPredecessorAlreadyReplaced' }
        }
        $record=[ordered]@{solutionId=$s.solutionId;pmIdentity=$s.pmIdentity;configuration=$Binding.configuration;envelope=$envelope;id=$Decision.id;date=$Decision.date;context=$Decision.context;reasons=$Decision.reasons;alternatives=$Decision.alternatives;consequences=$Decision.consequences;status=$Decision.status;sources=$Decision.sources;supersedes=$Decision.supersedes;decisionHash=$digest;review=$review}
        $ref=Save-LCImmutable (Join-Path $directory 'decisions') $record
        if (@($journal.entries | Where-Object { $_.hash -ceq $ref.hash }).Count) { return $ref }
        $journal.entries=@($journal.entries)+@($ref);Write-LCJournal $path $journal
        return $ref
    } finally { Exit-ProductLock $owner }
}

Export-ModuleMember -Function Read-ProductConfiguration,Get-ProductBinding,Get-ProductContext,Initialize-ProductDirectory,Get-ProductDecisionEnvelope,Assert-ProductReviewBinding,Open-ProductSession,Set-ProductTurn,Complete-ProductSession,Publish-ProductSession,Exit-ProductLock,Save-ProductDecision,Save-ProductRecoveryIntent
