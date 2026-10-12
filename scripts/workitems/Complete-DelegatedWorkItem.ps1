[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$StorePath,
    [Parameter(Mandatory)][string]$RepositoryRoot,
    [Parameter(Mandatory)][string]$WorkItemId,
    [Parameter(Mandatory)][string]$ExecutionId,
    [Parameter(Mandatory)][string]$ResultPath
)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '..\coordinator\Lifecycle.Persistence.ps1')
$utf8 = New-Object Text.UTF8Encoding($false, $true)
function Assert-PropertySet($Object, [string[]]$Allowed, [string[]]$Required, [string]$Label) {
    if ($null -eq $Object -or $Object -isnot [pscustomobject]) { throw "$Label must be a JSON object." }
    $actual = @($Object.PSObject.Properties | ForEach-Object { $_.Name })
    foreach ($name in $Required) { if ($actual -cnotcontains $name) { throw "$Label lacks $name." } }
    foreach ($name in $actual) { if ($Allowed -cnotcontains $name) { throw "$Label contains unsupported property $name." } }
}
function Write-AtomicJson([string]$File, $Value) {
    $temp = $File + '.' + [guid]::NewGuid().ToString('N') + '.tmp'
    [IO.File]::WriteAllText($temp, ($Value | ConvertTo-Json -Depth 30), $utf8)
    if ([IO.File]::Exists($File)) { [IO.File]::Replace($temp, $File, $null) } else { [IO.File]::Move($temp, $File) }
}
if ([string]::IsNullOrWhiteSpace($ExecutionId) -or $ExecutionId.Length -gt 128) { throw 'Invalid ExecutionId.' }
$resultPath = [IO.Path]::GetFullPath($ResultPath)
if (-not [IO.File]::Exists($resultPath)) { throw 'Runner result is not persisted; refusing WorkItem transfer.' }
$technical = ConvertFrom-Json -InputObject $utf8.GetString([IO.File]::ReadAllBytes($resultPath)) -ErrorAction Stop
if ($technical.work_item_id -cne $WorkItemId -or $technical.execution_id -cne $ExecutionId) { throw 'Runner result binding mismatch.' }
$canonicalStore = [IO.Path]::GetFullPath($StorePath)
if ([IO.Path]::GetFullPath([string]$technical.work_item_store_path) -cne $canonicalStore -or [string]::IsNullOrWhiteSpace([string]$technical.task_id) -or [string]::IsNullOrWhiteSpace([string]$technical.role) -or [string]::IsNullOrWhiteSpace([string]$technical.thread_id) -or [string]::IsNullOrWhiteSpace([string]$technical.turn_id) -or [string]::IsNullOrWhiteSpace([string]$technical.parent_job_path) -or [string]::IsNullOrWhiteSpace([string]$technical.parent_job_task_id)) { throw 'Technical result lacks task/thread/turn/role/store/parent binding.' }
$accounting = [IO.Path]::GetFullPath([string]$technical.accounting_directory)
$hash = [Security.Cryptography.SHA256]::Create().ComputeHash([Text.Encoding]::UTF8.GetBytes($ExecutionId))
$key = ([BitConverter]::ToString($hash)).Replace('-', '').ToLowerInvariant()
$reservationPath = Join-Path $accounting ('execution-' + $key + '.json')
if (-not [IO.File]::Exists($reservationPath)) { throw 'Global execution reservation missing.' }
$reservation = ConvertFrom-Json -InputObject $utf8.GetString([IO.File]::ReadAllBytes($reservationPath)) -ErrorAction Stop
if ($reservation.executionId -cne $ExecutionId -or $reservation.workItemId -cne $WorkItemId -or $reservation.task_id -cne $technical.task_id -or [IO.Path]::GetFullPath($reservation.store_path) -cne $canonicalStore -or $reservation.parent_task_id -cne $technical.parent_job_task_id -or [IO.Path]::GetFullPath($reservation.parent_job_path) -cne [IO.Path]::GetFullPath($technical.parent_job_path) -or [IO.Path]::GetFullPath($reservation.result_path) -cne $resultPath -or $reservation.parent_context_hash -cne $technical.parent_context_hash -or [IO.Path]::GetFullPath($reservation.parent_context_path) -cne [IO.Path]::GetFullPath($technical.parent_context_path) -or $reservation.start_intent_hash -cne $technical.start_intent_hash -or [IO.Path]::GetFullPath($reservation.start_intent_path) -cne [IO.Path]::GetFullPath($technical.start_intent_path) -or $reservation.payload_hash -cne $technical.payload_hash -or $reservation.request_hash -cne $technical.request_hash -or [IO.Path]::GetFullPath($reservation.request_path) -cne [IO.Path]::GetFullPath($technical.work_item_request_path)) { throw 'Reservation and technical result correlation mismatch.' }
if ($reservation.parent_thread_id -cne $technical.parent_thread_id -or $reservation.parent_turn_id -cne $technical.parent_turn_id) { throw 'Parent thread/turn differs from the execution reservation.' }
if ([string]$reservation.resume_assessment_path -cne [string]$technical.resume_assessment_path) { throw 'Resume assessment path differs from execution reservation.' }
if ($reservation.state -cne 'result_saved' -or [string]::IsNullOrWhiteSpace([string]$reservation.thread_id) -or [string]::IsNullOrWhiteSpace([string]$reservation.turn_id) -or $reservation.thread_id -cne $technical.thread_id -or $reservation.turn_id -cne $technical.turn_id) { throw 'Only a persisted result_saved reservation with matching thread/turn can be transferred.' }
$parentJobPath = [IO.Path]::GetFullPath([string]$technical.parent_job_path)
if (-not [IO.File]::Exists($parentJobPath)) { throw 'Persisted parent job missing.' }
$parentJob = ConvertFrom-Json -InputObject $utf8.GetString([IO.File]::ReadAllBytes($parentJobPath)) -ErrorAction Stop
if ($parentJob.task_id -cne $technical.parent_job_task_id -or [IO.Path]::GetFullPath($parentJob.accounting_directory) -cne $accounting -or $parentJob.role -notmatch '^(koordinator|teamleiter_[a-z][a-z0-9_]*)$') { throw 'Persisted parent job does not prove caller role/accounting/task binding.' }
$contextModule=Import-Module (Join-Path $PSScriptRoot 'CoordinatorExecutionContext.psm1') -PassThru -Force
if(-not $technical.parent_context_path -or -not $technical.parent_context_hash -or -not $technical.start_intent_path -or -not $technical.start_intent_hash){throw 'Historical parent context/start authority binding missing.'}
$parentContext=& $contextModule {param($p,$h,$j,$t,$s,$a)Assert-ExecutionContext $p $h $j $t $s $a} $technical.parent_context_path $technical.parent_context_hash $parentJobPath $technical.parent_job_task_id $canonicalStore $accounting
if($parentContext.threadId -cne $technical.parent_thread_id -or $parentContext.turnId -cne $technical.parent_turn_id){throw 'Parent edge differs from immutable context.'}
$historicalRoot=& $contextModule {param($p,$h,$s,$a)Assert-ExecutionAncestors $p $h $s $a -MaxLevels 2} $technical.parent_context_path $technical.parent_context_hash $canonicalStore $accounting
$startAuthority=& $contextModule {param($p,$h)Read-DelegatedStartAuthority $p $h} $technical.start_intent_path $technical.start_intent_hash
if($startAuthority.parentContextPath -cne [IO.Path]::GetFullPath($technical.parent_context_path) -or $startAuthority.parentContextHash -cne $technical.parent_context_hash -or $startAuthority.parentJobPath -cne $parentJobPath -or $startAuthority.parentJobHash -cne (& $contextModule {param($j)Get-ExecutionJobHash $j} $parentJob)){throw 'Start authority does not bind the historical parent/job group.'}
$chainJob = $parentJob; $agentLevels = 2
while ($chainJob.parent_task_id -and -not $technical.parent_context_path) {
    if ($chainJob.role -ceq 'koordinator' -or -not $chainJob.parent_job_path -or -not [IO.File]::Exists([string]$chainJob.parent_job_path)) { throw 'Delegation chain has an invalid root/ancestor link.' }
    $ancestorPath = [IO.Path]::GetFullPath([string]$chainJob.parent_job_path)
    $ancestor = ConvertFrom-Json -InputObject $utf8.GetString([IO.File]::ReadAllBytes($ancestorPath)) -ErrorAction Stop
    if ($ancestor.task_id -cne $chainJob.parent_task_id -or [IO.Path]::GetFullPath($ancestor.accounting_directory) -cne $accounting) { throw 'Ancestor job task/accounting binding mismatch.' }
    $ancestorActivePath = $ancestorPath + '.active.json'
    if (-not [IO.File]::Exists($ancestorActivePath)) { throw 'Ancestor active thread/turn proof missing.' }
    $ancestorActive = ConvertFrom-Json -InputObject $utf8.GetString([IO.File]::ReadAllBytes($ancestorActivePath)) -ErrorAction Stop
    if ($ancestorActive.task_id -cne $ancestor.task_id -or $ancestorActive.role -cne $ancestor.role -or [IO.Path]::GetFullPath($ancestorActive.accounting_directory) -cne $accounting -or [string]::IsNullOrWhiteSpace([string]$ancestorActive.thread_id) -or [string]::IsNullOrWhiteSpace([string]$ancestorActive.turn_id)) { throw 'Ancestor active thread/turn binding mismatch.' }
    if ($chainJob.role -match '^teamleiter_' -and $ancestor.role -cne 'koordinator') { throw 'Team leader must descend from coordinator.' }
    if ($chainJob.role -notmatch '^(koordinator|teamleiter_[a-z][a-z0-9_]*)$') { throw 'Operator cannot extend the delegation chain.' }
    $agentLevels++; if ($agentLevels -gt 3) { throw 'Delegation exceeds three agent levels.' }
    $chainJob = $ancestor
}
$rootRole=if($technical.parent_context_path){$historicalRoot.role}else{$chainJob.role}
if ($rootRole -cne 'koordinator') { throw 'Delegation chain does not terminate at coordinator.' }
$ledgerPath = Join-Path $accounting ([string]$technical.task_id + '.usage.json')
if (-not [IO.File]::Exists($ledgerPath)) { throw 'Persisted accounting ledger missing.' }
$ledger = ConvertFrom-Json -InputObject $utf8.GetString([IO.File]::ReadAllBytes($ledgerPath)) -ErrorAction Stop
if ($ledger.task_id -cne $technical.task_id -or $ledger.parent_task_id -cne $technical.parent_job_task_id -or $ledger.role -cne $technical.role -or $ledger.thread_id -cne $technical.thread_id -or $ledger.turn_id -cne $technical.turn_id -or $ledger.parent_thread_id -cne $technical.parent_thread_id -or $ledger.parent_turn_id -cne $technical.parent_turn_id -or $ledger.work_item_id -cne $WorkItemId -or $ledger.execution_id -cne $ExecutionId -or [IO.Path]::GetFullPath($ledger.work_item_store_path) -cne $canonicalStore) { throw 'Persisted ledger correlation mismatch.' }
$resumeRecord=$null
$assessment=[string](Get-LCValue $startAuthority.parameters 'ResumeAssessment')
if($assessment){
    $ref=ConvertFrom-Json -InputObject $assessment -ErrorAction Stop
    if([string]$ref.path -cne [string]$technical.resume_assessment_path -or [string]$ref.path -cne [string]$reservation.resume_assessment_path -or [string]$ref.hash -cne [string](Get-LCValue $technical 'resume_assessment_hash') -or [string]$ref.hash -cne [string](Get-LCValue $reservation 'resume_assessment_hash')){throw 'TransferResumeReceiptBindingConflict'}
    $resumeRecord=Assert-LCResume $assessment $reservation.startingSnapshot $reservation.startingRevision $canonicalStore $RepositoryRoot -BeforeCAS
    if($resumeRecord.nextExecutionId -cne $ExecutionId -or [int]$resumeRecord.generation -ne [int]$startAuthority.parameters.Generation){throw 'TransferResumeGenerationConflict'}
}elseif($technical.resume_assessment_path -or $reservation.resume_assessment_path){throw 'TransferResumeAuthorityMissing'}
$requestPath = [string]$technical.work_item_request_path
if (-not $requestPath -or -not [IO.File]::Exists($requestPath)) { throw 'Bound request file missing.' }
$request = ConvertFrom-Json -InputObject $utf8.GetString([IO.File]::ReadAllBytes($requestPath)) -ErrorAction Stop
Assert-PropertySet $request @('kind','workItemId','executionId') @('kind','workItemId','executionId') 'Request'
if ($request.kind -cne 'request' -or $request.workItemId -cne $WorkItemId -or $request.executionId -cne $ExecutionId) { throw 'Request/result correlation mismatch.' }
if((Get-ContextHash ([IO.File]::ReadAllBytes($requestPath))) -cne $startAuthority.requestPayloadHash -or $startAuthority.requestPayloadHash -cne $technical.request_hash -or $startAuthority.parentThreadId -cne $technical.parent_thread_id -or $startAuthority.parentTurnId -cne $technical.parent_turn_id){throw 'Pinned request locator/parent payload hash mismatch.'}
$outcome = 'failed'; $reason = 'Runner did not provide a structured final_answer.'; $payload = $null
if ($technical.final_answer) {
    try {
        $payload = ConvertFrom-Json -InputObject ([string]$technical.final_answer) -ErrorAction Stop
        Assert-PropertySet $payload @('kind','workItemId','executionId','outcome','result','reason') @('kind','workItemId','executionId','outcome','result','reason') 'Result'
        if ($payload.kind -cne 'result' -or $payload.workItemId -cne $WorkItemId -or $payload.executionId -cne $ExecutionId -or $payload.outcome -notin @('delivered','blocked','failed')) { throw 'Invalid result identity/outcome.' }
        if ($payload.outcome -isnot [string] -or ($null -ne $payload.reason -and $payload.reason -isnot [string])) { throw 'Invalid result outcome/reason types.' }
        if ($null -ne $payload.result) {
            Assert-PropertySet $payload.result @('summary','evidence','openPoints','humanInteraction') @('summary','evidence') 'Result.result'
            if ($payload.result.summary -isnot [string] -or $payload.result.evidence -isnot [array] -or @($payload.result.evidence | Where-Object { $_ -isnot [string] -or [string]::IsNullOrWhiteSpace($_) }).Count) { throw 'Invalid result summary/evidence types.' }
            if ($payload.result.PSObject.Properties['openPoints'] -and $payload.result.openPoints -isnot [array]) { throw 'openPoints must be a JSON array.' }
            if ($null -ne $payload.result.humanInteraction) {
                Assert-PropertySet $payload.result.humanInteraction @('kind','description') @('kind','description') 'Result humanInteraction'
                if ($payload.result.humanInteraction.kind -notin @('clarification','approval','action') -or $payload.result.humanInteraction.description -isnot [string] -or [string]::IsNullOrWhiteSpace($payload.result.humanInteraction.description)) { throw 'Invalid humanInteraction kind/description.' }
            }
        }
        $outcome = [string]$payload.outcome; $reason = [string]$payload.reason
    } catch {
        $payload = $null; $outcome = 'failed'; $reason = 'Structured final_answer is invalid or uncorrelated; no delivery accepted.'
    }
} elseif ($technical.error) { $reason = [string]$technical.error }
if ($outcome -eq 'delivered') {
    if (-not $payload.result -or [string]::IsNullOrWhiteSpace([string]$payload.result.summary) -or @($payload.result.evidence).Count -eq 0 -or $null -ne $payload.result.humanInteraction) {
        $outcome = 'failed'; $reason = 'Delivered result lacks valid summary/evidence or includes a human request.'; $payload = $null
    }
} elseif ([string]::IsNullOrWhiteSpace($reason)) { $reason = 'Structured blocked/failed result did not provide a reason.' }
$openPoints = @()
if ($null -ne $payload.result -and $null -ne $payload.result.openPoints) { $openPoints = @($payload.result.openPoints) }
$openPath = $resultPath + '.open-points.json'
$evidence = @(); $summary = ''
if ($outcome -eq 'delivered') {
    $summary = [string]$payload.result.summary; $evidence = @($payload.result.evidence)
    if ($openPoints.Count) { $evidence += $openPath }
}
elseif ($openPoints.Count) { $summary = $reason; $evidence = @($openPath) }
$contractResult = if ($summary -and $evidence.Count) { [pscustomobject]@{ summary=$summary; evidence=$evidence } } else { $null }
$ltc = [pscustomobject][ordered]@{ kind='result'; workItemId=$WorkItemId; executionId=$ExecutionId; outcome=$outcome; result=$(if ($null -ne $contractResult) { $contractResult } else { $null }); reason=$(if ($outcome -eq 'delivered') { $null } else { $reason }) }
$ltcPath = $resultPath + '.workitem-result.json'
Import-Module (Join-Path $PSScriptRoot 'WorkItemStore.psm1') -Force
Import-Module (Join-Path $PSScriptRoot 'WorkItemExecutionCorrelation.psm1') -Force
$storePath = [IO.Path]::GetFullPath($StorePath)
$correlationPath = Get-WorkItemExecutionCorrelationPath -AccountingDirectory $accounting -ExecutionId $ExecutionId
$bindingKey = ([BitConverter]::ToString(([Security.Cryptography.SHA256]::Create().ComputeHash([Text.Encoding]::UTF8.GetBytes($storePath.ToLowerInvariant() + "`n" + $WorkItemId)))).Replace('-', '').ToLowerInvariant()
$bindingPath = Join-Path $accounting ('workitem-current-' + $bindingKey + '.json')
function Set-CurrentBindingTerminal([string]$State) {
    $bound = ConvertFrom-Json -InputObject $utf8.GetString([IO.File]::ReadAllBytes($bindingPath)) -ErrorAction Stop
    if ($bound.kind -cne 'workitem-current-execution' -or $bound.executionId -cne $ExecutionId -or $bound.taskId -cne $technical.task_id -or $bound.workItemId -cne $WorkItemId -or $bound.storePath -cne $storePath) { throw 'Result is not the currently bound WorkItem execution.' }
    $expectedImplementedAt = if ($null -ne $correlation) { $correlation.sourceImplementedAt } else { $sourceImplementedAt }
    if ($bound.startingImplementedAt -cne $expectedImplementedAt) { throw 'WorkItem implementedAt differs from the registered starting value.' }
    $terminalState = if ($State -eq 'delivered') { 'completed' } else { $State }
    if ($bound.state -in @('completed','failed','blocked')) {
        if ($bound.state -cne $terminalState) { throw 'Current execution is terminal with a conflicting outcome.' }
        return
    }
    if ($bound.state -cne 'active') { throw 'Current execution binding is not active or matching terminal.' }
    $bound.state = $terminalState; $bound.finishedAt = [DateTime]::UtcNow.ToString('o')
    $temporary = $bindingPath + '.' + [guid]::NewGuid().ToString('N') + '.writing'
    [IO.File]::WriteAllText($temporary, ($bound | ConvertTo-Json -Depth 40 -Compress), $utf8)
    [IO.File]::Replace($temporary, $bindingPath, $null)
}
for ($attempt = 0; $attempt -lt 3; $attempt++) {
    $snapshot = Get-WorkItemStoreResult -Path $storePath -RepositoryRoot $RepositoryRoot
    $found = @($snapshot.Document.items | Where-Object { $_.id -ceq $WorkItemId })
    if ($found.Count -ne 1) { throw 'WorkItem missing or ambiguous.' }
    $item = $found[0]
    $sourceStatus = [string]$item.status
    $sourceImplementedAt = $item.implementedAt
    $sourceResult = ConvertFrom-Json -InputObject (ConvertTo-Json -InputObject $item.result -Depth 25 -Compress) -ErrorAction Stop
    $correlation = Read-WorkItemExecutionCorrelation -Path $correlationPath
    $resumeCandidate = $null
    if ($null -ne $correlation) {
        if ($correlation.kind -cne 'workitem-transfer' -or $correlation.executionId -cne $ExecutionId -or $correlation.taskId -cne $technical.task_id -or $correlation.threadId -cne $technical.thread_id -or $correlation.turnId -cne $technical.turn_id -or $correlation.workItemId -cne $WorkItemId -or $correlation.storePath -cne $storePath -or $correlation.resultPath -cne $resultPath -or $correlation.parentContextHash -cne $technical.parent_context_hash -or $correlation.startIntentHash -cne $technical.start_intent_hash -or $correlation.parentJobHash -cne $technical.parent_job_hash -or $correlation.parentThreadId -cne $technical.parent_thread_id -or $correlation.parentTurnId -cne $technical.parent_turn_id -or $correlation.resultHash -cne $technical.result_hash) { throw 'Existing transfer record belongs to a different execution binding.' }
        if ($correlation.complete -eq $true) {
            Set-CurrentBindingTerminal $outcome
            return $ltc
        }
        if ($snapshot.Revision -cne $correlation.sourceRevision -and $snapshot.Revision -ceq $correlation.predictedResultingRevision -and (ConvertTo-Json -InputObject $item -Depth 30 -Compress) -ceq (ConvertTo-Json -InputObject $correlation.candidate -Depth 30 -Compress)) {
            $correlation.complete = $true; $correlation.resultingRevision = $snapshot.Revision
            Write-WorkItemExecutionCorrelation -Path $correlationPath -Record $correlation -Create $false
            Set-CurrentBindingTerminal $outcome
            return $ltc
        }
        if ($snapshot.Revision -cne $correlation.sourceRevision -or $item.status -cne $correlation.sourceStatus -or $item.implementedAt -cne $correlation.sourceImplementedAt -or (ConvertTo-Json -InputObject $item.result -Depth 25 -Compress) -cne (ConvertTo-Json -InputObject $correlation.sourceResult -Depth 25 -Compress) -or $null -eq $correlation.candidate) { throw 'Incomplete transfer record cannot be reconciled uniquely; refusing another mutation.' }
        $resumeCandidate = ConvertFrom-Json -InputObject (ConvertTo-Json -InputObject $correlation.candidate -Depth 30 -Compress) -ErrorAction Stop
    }
    if ($item.owner.type -cne 'agent' -or $item.owner.id -cne $technical.role) { throw 'Technical result role no longer owns the WorkItem.' }
    if (-not [IO.File]::Exists($bindingPath)) { throw 'No current WorkItem execution binding exists.' }
    $currentBinding = ConvertFrom-Json -InputObject $utf8.GetString([IO.File]::ReadAllBytes($bindingPath)) -ErrorAction Stop
    if ($currentBinding.kind -cne 'workitem-current-execution' -or $currentBinding.state -cne 'active' -or $currentBinding.executionId -cne $ExecutionId -or $currentBinding.taskId -cne $technical.task_id -or $currentBinding.parentTaskId -cne $technical.parent_job_task_id -or [IO.Path]::GetFullPath($currentBinding.parentJobPath) -cne [IO.Path]::GetFullPath($technical.parent_job_path) -or $currentBinding.parentContextHash -cne $technical.parent_context_hash -or $currentBinding.startIntentHash -cne $technical.start_intent_hash -or $currentBinding.payloadHash -cne $technical.payload_hash -or $currentBinding.requestHash -cne $technical.request_hash -or $currentBinding.parentThreadId -cne $technical.parent_thread_id -or $currentBinding.parentTurnId -cne $technical.parent_turn_id -or $currentBinding.workItemId -cne $WorkItemId -or $currentBinding.storePath -cne $storePath -or $currentBinding.startingImplementedAt -cne $sourceImplementedAt) { throw 'Result does not match the active current WorkItem execution binding.' }
    $registeredSnapshot = ConvertFrom-Json -InputObject (ConvertTo-Json -InputObject $currentBinding.startingSnapshot -Depth 30 -Compress) -ErrorAction Stop
    foreach ($mutableField in @('status','updatedAt','blockReason')) { $registeredSnapshot.$mutableField = $item.$mutableField }
    if ((ConvertTo-Json -InputObject $item -Depth 30 -Compress) -cne (ConvertTo-Json -InputObject $registeredSnapshot -Depth 30 -Compress)) { throw 'Current WorkItem snapshot changed after this execution was registered.' }
    if ($null -ne $resumeRecord) {
        $currentRequestedAt = if ($item.humanInteraction) { $item.humanInteraction.requestedAt } else { $null }
        $currentResponse = if ($item.humanInteraction) { $item.humanInteraction.response } else { $null }
        if ($currentRequestedAt -cne $resumeRecord.requestedAt -or (Get-LCHash (Get-LCBytes $currentResponse)) -cne $resumeRecord.responseHash -or (Get-LCResumeContent $item) -cne $resumeRecord.contentHash) { throw 'Current WorkItem no longer matches the terminal resume receipt.' }
    }
    $seenAncestors = @{}
    $cursorId = [string]$item.id
    $parentFound = -not [string]$parentJob.work_item_id
    while ($cursorId) {
        if ($seenAncestors.ContainsKey($cursorId)) { throw 'WorkItem-Abstammung enthaelt einen Zyklus.' }
        $seenAncestors[$cursorId] = $true
        $cursorEntry = @($snapshot.Document.items | Where-Object { $_.id -ceq $cursorId })
        if ($cursorEntry.Count -ne 1) { throw 'WorkItem-Abstammung enthaelt eine fehlende oder mehrdeutige Referenz.' }
        $cursorId = [string]$cursorEntry[0].parentId
        if ($cursorId -and $cursorId -ceq [string]$parentJob.work_item_id) { $parentFound = $true }
    }
    if (-not $parentFound) { throw 'Persisted parent job WorkItem is not an ancestor of the transferred WorkItem.' }
    if ($item.status -in @('accepted','cancelled')) { throw "WorkItem is terminal: $($item.status)" }
    if ($outcome -ne 'delivered' -and $item.status -eq 'blocked' -and $item.blockReason -ceq $reason -and (-not $payload.result.humanInteraction) -and (-not $contractResult -or (ConvertTo-Json -InputObject $item.result -Depth 25 -Compress) -ceq (ConvertTo-Json -InputObject $contractResult -Depth 25 -Compress))) { return $ltc }
    if ($null -ne $item.humanInteraction -and $null -eq $item.humanInteraction.response -and $outcome -eq 'delivered') { throw 'Pending humanInteraction cannot be removed by delivery.' }
    $now = [DateTime]::UtcNow.ToString('yyyy-MM-ddTHH:mm:ss.fffffffZ')
    if ($outcome -eq 'delivered') {
        $startingStatus = [string]$currentBinding.startingSnapshot.status
        $reworkExecution = $startingStatus -ceq 'rework'
        $persistentBlockedResume = $null -ne $resumeRecord -and $resumeRecord.kind -ceq 'terminal-resume-decision-v1' -and $resumeRecord.disposition -ceq 'resume' -and $resumeRecord.nextExecutionId -ceq $ExecutionId -and [int]$resumeRecord.generation -eq [int]$startAuthority.parameters.Generation -and (Get-LCResumeContent $item) -ceq $resumeRecord.contentHash
        $returningExisting = $null -ne $item.implementedAt -and -not $reworkExecution -and $persistentBlockedResume
        if ($returningExisting -and (ConvertTo-Json -InputObject $item.result -Depth 25 -Compress) -cne (ConvertTo-Json -InputObject $contractResult -Depth 25 -Compress)) { throw 'Resume cannot replace an existing implementation result; route the change through explicit rework.' }
        if ($item.status -notin @('in_progress','rework') -and -not $returningExisting) { throw "Illegal implementation transition from $($item.status)." }
        $item.status = 'implemented'; $item.result = $contractResult; $item.blockReason = $null
        if (-not $returningExisting) { $item.implementedAt = $now }
    } else {
        if ($item.status -eq 'planned') { $item.status = 'blocked' }
        elseif ($item.status -ne 'blocked') { $item.status = 'blocked' }
        $item.blockReason = $reason
        if ($null -ne $payload.result.humanInteraction) {
            $human = $payload.result.humanInteraction
            if ($human.kind -notin @('clarification','approval','action') -or [string]::IsNullOrWhiteSpace([string]$human.description)) { throw 'Invalid humanInteraction request.' }
            if ($null -ne $item.humanInteraction) { throw 'An existing humanInteraction request is immutable and cannot be replaced.' }
            $item.humanInteraction = [pscustomobject]@{ kind=[string]$human.kind; description=[string]$human.description; requestedAt=$now; response=$null }
            $item.blockReason = $null
        }
        if ($contractResult) { $item.result = $contractResult }
    }
    if ($null -ne $resumeCandidate) { $item = $resumeCandidate }
    else { $item.updatedAt = $now }
    $candidateDocument = ConvertFrom-Json -InputObject (ConvertTo-Json -InputObject $snapshot.Document -Depth 100) -ErrorAction Stop
    for ($documentIndex = 0; $documentIndex -lt @($candidateDocument.items).Count; $documentIndex++) { if ($candidateDocument.items[$documentIndex].id -ceq $WorkItemId) { $candidateDocument.items[$documentIndex] = $item; break } }
    $candidateBytes = $utf8.GetBytes((ConvertTo-Json -InputObject $candidateDocument -Depth 100 -ErrorAction Stop))
    $predictedRevision = 'sha256:' + [BitConverter]::ToString(([Security.Cryptography.SHA256]::Create().ComputeHash($candidateBytes))).Replace('-', '').ToLowerInvariant()
    if ($null -ne $correlation -and $correlation.complete -ne $true -and $correlation.predictedResultingRevision -cne $predictedRevision) { throw 'Resumed candidate no longer matches its persisted resulting revision prediction.' }
    if ($openPoints.Count) { Write-AtomicJson $openPath @{ workItemId=$WorkItemId; executionId=$ExecutionId; openPoints=$openPoints } }
    Write-AtomicJson $ltcPath $ltc
    if ($null -eq $correlation) {
        $correlation = [pscustomobject][ordered]@{ kind='workitem-transfer'; complete=$false; executionId=$ExecutionId; taskId=[string]$technical.task_id; threadId=[string]$technical.thread_id; turnId=[string]$technical.turn_id; parentContextPath=$technical.parent_context_path;parentContextHash=$technical.parent_context_hash;startIntentPath=$technical.start_intent_path;startIntentHash=$technical.start_intent_hash;parentJobHash=$technical.parent_job_hash;parentThreadId=$technical.parent_thread_id;parentTurnId=$technical.parent_turn_id;resultHash=$technical.result_hash;storePath=$storePath; workItemId=$WorkItemId; resultPath=$resultPath; sourceRevision=$snapshot.Revision; sourceStatus=$sourceStatus; sourceImplementedAt=$sourceImplementedAt; sourceResult=$sourceResult; outcome=$outcome; result=$item.result; resultingStatus=[string]$item.status; implementedAt=$item.implementedAt; predictedResultingRevision=$predictedRevision; candidate=$item; recordedAt=[DateTime]::UtcNow.ToString('o') }
        try { Write-WorkItemExecutionCorrelation -Path $correlationPath -Record $correlation -Create $true }
        catch [System.IO.IOException] {
            $raced = Read-WorkItemExecutionCorrelation -Path $correlationPath
            if ($null -eq $raced) { throw }
            if ($raced.executionId -cne $ExecutionId -or $raced.taskId -cne $technical.task_id -or $raced.threadId -cne $technical.thread_id -or $raced.turnId -cne $technical.turn_id -or $raced.workItemId -cne $WorkItemId -or $raced.storePath -cne $storePath -or $raced.resultPath -cne $resultPath -or $raced.predictedResultingRevision -cne $predictedRevision -or (ConvertTo-Json -InputObject $raced.candidate -Depth 30 -Compress) -cne (ConvertTo-Json -InputObject $item -Depth 30 -Compress)) { throw 'Concurrent transfer record does not bind the exact candidate.' }
            $correlation = $raced
            if ($correlation.executionId -cne $ExecutionId -or $correlation.complete -ne $false -or $correlation.sourceRevision -cne $snapshot.Revision) { throw 'Concurrent transfer record conflicts with this source revision.' }
        }
    }
    try {
        $writeResult = Set-WorkItemStoreEntry -Path $storePath -Id $WorkItemId -Item $item -ExpectedRevision $snapshot.Revision -RepositoryRoot $RepositoryRoot
        if ($writeResult.Revision -cne $predictedRevision) { throw 'Published store revision differs from the persisted execution correlation prediction.' }
        $correlation.complete = $true
        $correlation.resultingRevision = [string]$writeResult.Revision
        $correlation.resultingStatus = [string]$item.status
        $correlation.implementedAt = $item.implementedAt
        Write-WorkItemExecutionCorrelation -Path $correlationPath -Record $correlation -Create $false
        Set-CurrentBindingTerminal $outcome
        return $ltc
    } catch {
        if ($_.FullyQualifiedErrorId -notmatch 'RevisionConflict') { throw }
    }
}
throw 'Store revision conflicts persisted; technical result remains saved for idempotent transfer.'
