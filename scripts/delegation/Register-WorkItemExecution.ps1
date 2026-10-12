[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$AccountingDirectory,
    [Parameter(Mandatory)][string]$StorePath,
    [Parameter(Mandatory)][string]$RepositoryRoot,
    [Parameter(Mandatory)][string]$WorkItemId,
    [Parameter(Mandatory)][string]$ExecutionId,
    [Parameter(Mandatory)][string]$TaskId,
    [Parameter(Mandatory)][string]$ParentTaskId,
    [Parameter(Mandatory)][string]$ParentJobPath,
    [Parameter(Mandatory)][string]$ParentContextPath,
    [Parameter(Mandatory)][string]$ParentContextHash,
    [Parameter(Mandatory)][string]$StartIntentPath,
    [Parameter(Mandatory)][string]$StartIntentHash,
    [Parameter(Mandatory)][string]$ParentThreadId,
    [Parameter(Mandatory)][string]$ParentTurnId,
    [Parameter(Mandatory)][string]$PayloadHash,
    [Parameter(Mandatory)][string]$RequestPath,
    [Parameter(Mandatory)][string]$RequestHash,
    [Parameter(Mandatory)][string]$StartAttemptPath,
    [Parameter(Mandatory)][string]$StartAttemptHash
)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '..\coordinator\Lifecycle.Persistence.ps1')
$utf8 = New-Object Text.UTF8Encoding($false, $true)
$accounting = [IO.Path]::GetFullPath($AccountingDirectory)
$store = [IO.Path]::GetFullPath($StorePath)
New-Item -ItemType Directory -Path $accounting -Force | Out-Null
$identity = [Text.Encoding]::UTF8.GetBytes($store.ToLowerInvariant() + "`n" + $WorkItemId)
$key = ([BitConverter]::ToString(([Security.Cryptography.SHA256]::Create().ComputeHash($identity)))).Replace('-', '').ToLowerInvariant()
$bindingPath = Join-Path $accounting ('workitem-current-' + $key + '.json')
$lockPath = Join-Path $accounting ('workitem-current-' + $key + '.lock')
$lock = $null
try {
    $lock = [IO.File]::Open($lockPath, [IO.FileMode]::OpenOrCreate, [IO.FileAccess]::ReadWrite, [IO.FileShare]::None)
    Import-Module (Join-Path $PSScriptRoot '..\workitems\WorkItemStore.psm1') -Force
    $snapshot = Get-WorkItemStoreResult -Path $store -RepositoryRoot $RepositoryRoot
    $matches = @($snapshot.Document.items | Where-Object { $_.id -ceq $WorkItemId })
    if ($matches.Count -ne 1) { throw 'Current WorkItem missing or ambiguous.' }
    $item = $matches[0]
    if ($item.status -notin @('planned','in_progress','rework','blocked')) { throw 'WorkItem is not executable.' }
    Import-Module (Join-Path $PSScriptRoot '..\workitems\WorkItemPrestartRecovery.psm1') -Force
    $rp=Get-PrestartRecoveryPaths $accounting $ExecutionId $store $WorkItemId
    $secured=Read-RecoveryJson $rp.reservation
    if($secured.state -cne 'reserved' -or $secured.task_id -cne $TaskId -or $secured.startingRevision -cne $snapshot.Revision -or $secured.current_binding_path -cne $bindingPath -or $secured.start_attempt_path -cne [IO.Path]::GetFullPath($StartAttemptPath) -or $secured.start_attempt_hash -cne $StartAttemptHash){throw 'SecuredReservationBindingConflict'}
    if($item.owner.type -cne 'agent' -or $item.owner.id -cne $secured.role -or (Get-RecoveryHash (ConvertTo-RecoveryBytes $item)) -cne (Get-RecoveryHash (ConvertTo-RecoveryBytes $secured.startingSnapshot))){throw 'SecuredStartingOwnerOrSnapshotConflict'}
    $old = $null
    if ([IO.File]::Exists($bindingPath)) { $old = ConvertFrom-Json -InputObject $utf8.GetString([IO.File]::ReadAllBytes($bindingPath)) -ErrorAction Stop }
    if ($old -and $old.state -notin @('completed','failed','blocked')) { throw 'A prior WorkItem execution is not conclusively terminal.' }
    $cm=Import-Module (Join-Path $PSScriptRoot '..\workitems\CoordinatorExecutionContext.psm1') -PassThru -Force
    $parentContext=& $cm {param($p,$h,$j,$t,$s,$a) Assert-ExecutionContext $p $h $j $t $s $a} $ParentContextPath $ParentContextHash $ParentJobPath $ParentTaskId $store $accounting
    if($parentContext.threadId -cne $ParentThreadId -or $parentContext.turnId -cne $ParentTurnId){throw 'Reservation parent thread/turn does not match immutable context.'}
    $authority=& $cm {param($p,$h)Read-DelegatedStartAuthority $p $h} $StartIntentPath $StartIntentHash
    if($authority.requestPayloadHash -cne $RequestHash -or $authority.parentContextHash -cne $ParentContextHash -or $authority.parentJobPath -cne [IO.Path]::GetFullPath($ParentJobPath)){throw 'Reservation start authority/context mismatch.'}
    $assessment=[string](Get-LCValue $authority.parameters 'ResumeAssessment');$rd=Assert-LCResume $assessment $item $snapshot.Revision $store $RepositoryRoot -BeforeCAS
    if($rd -and ($rd.nextExecutionId -cne $ExecutionId -or [int]$rd.generation -ne [int]$authority.parameters.Generation)){throw 'RegisterResumeGenerationConflict'}
    $preModule=Import-Module (Join-Path $PSScriptRoot '..\workitems\WorkItemPrestartIntent.psm1') -PassThru -Force;$attempt=& $preModule {param($p,$h)Read-WorkItemPrestartIntent $p $h} $StartAttemptPath $StartAttemptHash
    if($attempt.record.executionId -cne $ExecutionId -or $attempt.record.taskId -cne $TaskId -or $attempt.record.payloadHash -cne $PayloadHash -or $attempt.record.parentContextHash -cne $ParentContextHash -or $attempt.record.startIntentHash -cne $StartIntentHash -or $attempt.record.phase -cne 'Prepared'){throw 'Prepared prestart attempt does not match reservation.'}
    $parentJobHash=& $cm {param($p) Get-ExecutionJobHash (Read-ContextJson $p)} $ParentJobPath
    $record = [ordered]@{ kind='workitem-current-execution'; state='active'; executionId=$ExecutionId; taskId=$TaskId; parentTaskId=$ParentTaskId; parentJobPath=[IO.Path]::GetFullPath($ParentJobPath);parentJobHash=$parentJobHash;parentThreadId=$ParentThreadId;parentTurnId=$ParentTurnId;parentContextPath=[IO.Path]::GetFullPath($ParentContextPath);parentContextHash=$ParentContextHash;startIntentPath=[IO.Path]::GetFullPath($StartIntentPath);startIntentHash=$StartIntentHash;startAttemptPath=[IO.Path]::GetFullPath($StartAttemptPath);startAttemptHash=$StartAttemptHash;payloadHash=$PayloadHash;requestPath=[IO.Path]::GetFullPath($RequestPath);requestHash=$RequestHash;storePath=$store; workItemId=$WorkItemId; resumeAssessment=$assessment;resumeReceipt=$(if($rd){ConvertFrom-Json -InputObject $assessment}else{$null});startingRevision=$snapshot.Revision; startingImplementedAt=$item.implementedAt; startingSnapshot=$item; registeredAt=[DateTime]::UtcNow.ToString('o') }
    $temporary = $bindingPath + '.' + [guid]::NewGuid().ToString('N') + '.writing'
    [IO.File]::WriteAllText($temporary, ($record | ConvertTo-Json -Depth 40 -Compress), $utf8)
    if ([IO.File]::Exists($bindingPath)) { [IO.File]::Replace($temporary, $bindingPath, $null) } else { [IO.File]::Move($temporary, $bindingPath) }
    [pscustomobject]@{ path=$bindingPath; record=$record }
} finally {
    if ($lock) { $lock.Dispose() }
}
