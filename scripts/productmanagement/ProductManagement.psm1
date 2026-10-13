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

function Open-ProductSession($Binding,[string]$DataDirectory,$Job,$Rpc) {
    $s=$Binding.solution
    $parent=ConvertFrom-Json -InputObject ([IO.File]::ReadAllText($Job.parent_job_path))
    if ($Job.role -cne 'produktmanagement_pm_strategie' -or -not $Job.work_item_id -or $parent.role -cne 'teamleiter_produktmanagement') { throw 'ProductSessionRequiresOwnedPMWorkItem' }
    $directory=Initialize-ProductDirectory $DataDirectory $s.solutionId
    $path=Join-Path $directory 'session.json'
    $owner=Enter-ProductLock $path
    try {
        $profile=[ordered]@{role=$Job.role;cwd=$Job.cwd;model=$Job.model;sandbox=$Job.sandbox;approvalPolicy=$Job.approval_policy;developerInstructions=$Job.developer_instructions;config=$Job.config;runtime=$Job.admission_runtime}
        $profileHash=Get-LCHash (Get-LCBytes $profile)
        $session=$null
        if ([IO.File]::Exists($path)) { $session=Read-LCArchive $path ([IO.File]::ReadAllText($path) | ConvertFrom-Json) }
        if ($session) {
            if ($session.solutionId -cne $s.solutionId -or $session.pmIdentity -cne $s.pmIdentity -or $session.profileHash -cne $profileHash -or $session.configuration.hash -cne $Binding.configuration.hash) { throw 'BlockedRecovery: ProductSessionBindingChanged' }
            if ($session.state -cne 'Ready' -or -not $session.threadId) { throw 'BlockedRecovery: ProductPriorActivationUnresolved; document recovery requires owner review' }
            if ($session.executionId -ceq $Job.execution_id) { throw 'ProductExecutionAlreadyTerminal; use existing result and receipts' }
            $ack=Read-LCReceipt $session.threadReceipt
            if ($ack.threadId -cne $session.threadId -or $ack.solutionId -cne $s.solutionId -or $ack.pmIdentity -cne $s.pmIdentity -or $ack.profileHash -cne $profileHash) { throw 'BlockedRecovery: ProductThreadReceiptConflict' }
            $terminal=Read-LCReceipt $session.terminalReceipt
            if ($terminal.solutionId -cne $s.solutionId -or $terminal.pmIdentity -cne $s.pmIdentity -or $terminal.executionId -cne $session.executionId -or $terminal.completion.params.threadId -cne $session.threadId -or $terminal.completion.params.turn.id -cne $session.turnId) { throw 'BlockedRecovery: ProductTerminalReceiptConflict' }
            $resultReceipt=Read-LCReceipt $session.resultReceipt
            if ($resultReceipt.result.execution_id -cne $session.executionId -or $resultReceipt.result.thread_id -cne $session.threadId -or $resultReceipt.result.turn_id -cne $session.turnId) { throw 'BlockedRecovery: ProductResultReceiptConflict' }
            $session.state='Resuming'; Write-LCJournal $path $session
            $answer=& $Rpc 'thread/resume' @{threadId=$session.threadId};$reply=$answer.reply;$nativeRpc=$answer.rpc
            if ($reply.thread.id -cne $session.threadId) { throw 'BlockedRecovery: ProductResumeThreadMismatch' }
            $readAnswer=& $Rpc 'thread/read' @{threadId=$session.threadId;includeTurns=$true};$read=$readAnswer.reply
            if ($read.thread.id -cne $session.threadId -or $read.thread.status.type -cne 'idle') { throw 'BlockedRecovery: ProductThreadNotIdle' }
            $turns=@($read.thread.turns | Where-Object { $_.id -ceq $session.turnId })
            if ($turns.Count -ne 1 -or $turns[0].status -cne $terminal.completion.params.turn.status) { throw 'BlockedRecovery: ProductTerminalHistoryMissing' }
            $session.generation=[int]$session.generation+1
        } else {
            $session=[pscustomobject]@{solutionId=$s.solutionId;pmIdentity=$s.pmIdentity;configuration=$Binding.configuration;profileHash=$profileHash;state='Starting';threadId=$null;threadReceipt=$null;generation=1;executionId=$Job.execution_id;workItemId=$Job.work_item_id;taskId=$Job.task_id;turnId=$null;terminalReceipt=$null}
            # Durable intent precedes the only thread/start. Unknown start is never repeated.
            Write-LCJournal $path $session
            $answer=& $Rpc 'thread/start' @{cwd=$Job.cwd;model=$Job.model;sandbox=$Job.sandbox;approvalPolicy=$Job.approval_policy;developerInstructions=$Job.developer_instructions;config=$Job.config};$reply=$answer.reply;$nativeRpc=$answer.rpc
            if (-not $reply.thread.id) { throw 'BlockedRecovery: ProductThreadACKMissing' }
            $session.threadId=[string]$reply.thread.id
            $session.threadReceipt=Save-LCImmutable (Join-Path $directory 'receipts') ([ordered]@{kind='product-thread-ack-v1';solutionId=$s.solutionId;pmIdentity=$s.pmIdentity;profileHash=$profileHash;configuration=$Binding.configuration;threadId=$session.threadId;reply=$reply;rpc=$nativeRpc})
        }
        $session.state='ActivationPrepared';$session.executionId=$Job.execution_id;$session.workItemId=$Job.work_item_id;$session.taskId=$Job.task_id;$session.turnId=$null
        Write-LCJournal $path $session
        return [pscustomobject]@{owner=$owner;path=$path;directory=$directory;session=$session;reply=$reply;rpc=$nativeRpc}
    } catch { Exit-ProductLock $owner; throw }
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

Export-ModuleMember -Function Read-ProductConfiguration,Get-ProductBinding,Get-ProductContext,Initialize-ProductDirectory,Get-ProductDecisionEnvelope,Assert-ProductReviewBinding,Open-ProductSession,Set-ProductTurn,Complete-ProductSession,Publish-ProductSession,Exit-ProductLock,Save-ProductDecision
