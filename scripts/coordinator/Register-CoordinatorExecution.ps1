[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)][ValidateSet('Count','Reserve','Release','RegisterNative','ConfirmInventory','BeginAdmission','CommitAdmissionReserve','InvalidateAdmission','BindProvider','EnrollRoot','ReadAdmissionReservation')][string]$Action,
    [Parameter(Mandatory=$true)][string]$DataDirectory,
    [string]$TaskId,[string]$DispatchId,[string]$NativeThreadId,[string]$Role,[string]$ResultPath,[string]$PayloadHash,
    [string]$InventoryEpoch,[string]$InventoryJson,
    [string]$RootJobPath,[string]$SessionPath,[string]$TargetJson,[string]$AdmissionRequestHash,
    [string]$ProviderBindingJson,[object]$AdmissionBudget,[string]$NativeAckPath,[string]$NativeAckHash,
    [string]$DispatchJournalPath,
    [string]$NoSpawnReceiptPath,[string]$NoSpawnReceiptHash,[string]$FailureCommitHash,[string]$FailureCommitPath,[string]$RepositoryRoot,
    [ValidateRange(1,100)][int]$Capacity=4,
    [ValidateSet('reserved','active','unknown','terminal')][string]$State='reserved'
)
$ErrorActionPreference='Stop'
Import-Module (Join-Path $PSScriptRoot 'CoordinatorAdmission.psm1') -Force
if(-not $AdmissionBudget){$AdmissionBudget=New-AdmissionBudget 10000}
$target=if($TargetJson){ConvertFrom-Json -InputObject $TargetJson -ErrorAction Stop}else{[pscustomobject]@{taskId=$TaskId;dispatchId=$DispatchId;payloadHash=$PayloadHash;resultPath=$ResultPath;role=$Role;dispatchJournalPath=$DispatchJournalPath}}
$providerBinding=if($ProviderBindingJson){ConvertFrom-Json -InputObject $ProviderBindingJson -ErrorAction Stop}else{$null}
function Convert-RegistryGuid([string]$Value,[string]$Format){$parsed=[guid]::Empty;if([guid]::TryParse($Value,[ref]$parsed)){return $parsed.ToString($Format)};return $Value}
if($TaskId){$TaskId=Convert-RegistryGuid $TaskId 'D'};if($DispatchId){$DispatchId=Convert-RegistryGuid $DispatchId 'D'}
$root=[IO.Path]::GetFullPath($DataDirectory);[void][IO.Directory]::CreateDirectory($root)
$file=Join-Path $root 'executions.json';$inventoryFile=Join-Path $root 'execution-inventory.json';$mutex=New-Object Threading.Mutex($false,'Global\AgentOrganizationCoordinatorExecutions')
if(-not $mutex.WaitOne((Get-AdmissionRemainingMilliseconds $AdmissionBudget))){$mutex.Dispose();throw 'AdmissionUnknown: ExecutionRegistryLockUnavailable'}
try {
    $entries=@();if(Test-Path -LiteralPath $file){try{$parsed=[IO.File]::ReadAllText($file,[Text.Encoding]::UTF8)|ConvertFrom-Json;$entries=@($parsed)}catch{throw 'ExecutionRegistryUnreadable; capacity remains closed'}}
    foreach($e in $entries){foreach($name in @('inventoryAbsentAt','terminalAt')){if(-not $e.PSObject.Properties[$name]){$e|Add-Member -NotePropertyName $name -NotePropertyValue $null}}}
    if($Action -ne 'RegisterNative' -and $Action -ne 'Release'){
        Invoke-AdmissionRegistryLocked -Action $Action -Directory $root -Entries $entries -Target $target -RootJobPath $RootJobPath -SessionPath $SessionPath -RequestHash $AdmissionRequestHash -Budget $AdmissionBudget -ProviderBinding $providerBinding
        return
    }
    if($Action -eq 'RegisterNative'){
        if(-not $NativeThreadId -or -not $TaskId){throw 'NativeThreadIdAndTaskIdRequired'};$match=@($entries|Where-Object{(Convert-RegistryGuid ([string]$_.taskId) 'D') -eq $TaskId});if($match.Count){foreach($e in $match){if(-not $e.PSObject.Properties['providerBinding'] -or -not $e.providerBinding.origin -or -not $e.providerBinding.generation){throw 'AdmissionUnknown: NativeACKRequiresBoundReader'};if(-not $NativeAckPath -or -not $NativeAckHash -or (Get-AdmissionHash ([IO.File]::ReadAllBytes($NativeAckPath))) -cne $NativeAckHash){throw 'AdmissionUnknown: NativeACKByteBindingRequired'};$nativeAck=Read-AdmissionJson $NativeAckPath;if($nativeAck.threadId -cne $NativeThreadId -or (Get-AdmissionGuid $nativeAck.taskId) -cne $TaskId -or $nativeAck.origin -cne $e.providerBinding.origin -or $nativeAck.generation -cne $e.providerBinding.generation -or -not $nativeAck.reply.thread.id -or $nativeAck.reply.thread.id -cne $NativeThreadId){throw 'AdmissionUnknown: NativeACKProviderMismatch'};$e|Add-Member -NotePropertyName nativeAckPath -NotePropertyValue $NativeAckPath -Force;$e|Add-Member -NotePropertyName nativeAckHash -NotePropertyValue $NativeAckHash -Force;if((Convert-RegistryGuid ([string]$e.taskId) 'D') -ne $TaskId -or ($e.nativeThreadId -and $e.nativeThreadId -cne $NativeThreadId)){throw 'ExecutionIdentityConflict'};$e.nativeThreadId=$NativeThreadId;$e.state=$State};$entry=$match[0]}else{$id=if($DispatchId){$DispatchId}else{$TaskId};$entry=[pscustomobject]@{executionId=$id;taskId=$TaskId;dispatchId=$DispatchId;nativeThreadId=$NativeThreadId;role=$Role;resultPath=$ResultPath;payloadHash=$PayloadHash;state='unknown';source='native-registration';createdAt=[DateTime]::UtcNow.ToString('o')};$entries+= $entry}
    } elseif($Action -eq 'Release'){
        $entry=@($entries|Where-Object{(Convert-RegistryGuid ([string]$_.dispatchId) 'D') -eq $DispatchId -and (Convert-RegistryGuid ([string]$_.taskId) 'D') -eq $TaskId})|Select-Object -First 1;if(-not $entry){throw 'ExecutionReservationNotFound'}
        if(-not $ResultPath -or [IO.Path]::GetFullPath($ResultPath) -cne [IO.Path]::GetFullPath([string]$entry.resultPath) -or -not (Test-Path -LiteralPath $ResultPath -PathType Leaf)){throw 'BoundTerminalResultRequiredToRelease'}
        try{$result=[IO.File]::ReadAllText($ResultPath,[Text.Encoding]::UTF8)|ConvertFrom-Json}catch{throw 'TerminalResultUnreadable; reservation retained'}
        if((Convert-RegistryGuid ([string]$result.task_id) 'D') -cne $TaskId -or ($result.dispatch_id -and (Convert-RegistryGuid ([string]$result.dispatch_id) 'D') -cne $DispatchId)){throw 'TerminalResultBindingMismatch; reservation retained'}
        if($result.model_started -eq $false -and -not $NoSpawnReceiptPath){throw 'NoSpawnReleaseRequiresFullReceiptGroup'}
        if($NoSpawnReceiptPath){
            if(-not $NoSpawnReceiptHash -or -not $FailureCommitPath -or -not $FailureCommitHash -or -not $RepositoryRoot -or $entry.nativeThreadId -or $entry.state -notin @('reserved','terminal')){throw 'NativeOrUnknownExecutionCannotNoSpawnRelease'}
            $sameEntries=@($entries|Where-Object{(Convert-RegistryGuid ([string]$_.taskId) 'D') -ceq $TaskId -or (Convert-RegistryGuid ([string]$_.dispatchId) 'D') -ceq $DispatchId})
            if($sameEntries.Count -ne 1){throw 'AmbiguousRegistryOwnerNoSpawnClosed'}
            $rm=Import-Module (Join-Path $PSScriptRoot '..\workitems\WorkItemPrestartRecovery.psm1') -PassThru -Force
            $group=& $rm {param($p,$h,$c,$ch,$repo)Assert-PrestartFailureCommit $p $h $c $ch $repo} $NoSpawnReceiptPath $NoSpawnReceiptHash $FailureCommitPath $FailureCommitHash $RepositoryRoot
            $receipt=$group.receipt
            if((Convert-RegistryGuid $receipt.taskId 'D') -cne $TaskId -or $receipt.executionId -cne $DispatchId -or $receipt.payloadHash -cne $entry.payloadHash -or $receipt.childRole -cne $entry.role -or (Convert-RegistryGuid ([string]$entry.executionId) 'D') -cne $DispatchId -or $receipt.resultPath -cne [IO.Path]::GetFullPath($ResultPath) -or $receipt.registryDirectory -cne $root -or $receipt.dispatchJournalPath -cne [IO.Path]::GetFullPath($entry.dispatchJournalPath)){throw 'RegistryReceiptIdentityConflict'}
            if($entry.state -ceq 'terminal' -and ($entry.noSpawnReceiptHash -cne $NoSpawnReceiptHash -or $entry.failureCommitHash -cne $FailureCommitHash)){throw 'RegistryTerminalReplayConflict'}
        }
        $boundJournal=[string]$entry.dispatchJournalPath; if(-not $boundJournal){$jobPath=[string]$ResultPath+'.job.json';if(-not (Test-Path -LiteralPath $jobPath -PathType Leaf)){throw 'BoundJobRequired; reservation retained'};try{$boundJob=[IO.File]::ReadAllText($jobPath,[Text.Encoding]::UTF8)|ConvertFrom-Json}catch{throw 'BoundJobUnreadable; reservation retained'};if((Convert-RegistryGuid ([string]$boundJob.task_id) 'D') -cne $TaskId -or (Convert-RegistryGuid ([string]$boundJob.dispatch_id) 'D') -cne $DispatchId -or [string]$boundJob.payload_hash -cne [string]$entry.payloadHash -or -not $boundJob.result_file -or [IO.Path]::GetFullPath([string]$boundJob.result_file) -cne [IO.Path]::GetFullPath([string]$entry.resultPath) -or -not $boundJob.PSObject.Properties['dispatch_journal_path']){throw 'BoundJobMismatch; reservation retained'};$boundJournal=[string]$boundJob.dispatch_journal_path};if($DispatchJournalPath -and $boundJournal -and [IO.Path]::GetFullPath($DispatchJournalPath) -cne [IO.Path]::GetFullPath($boundJournal)){throw 'DispatchJournalBindingMismatch; reservation retained'};if($boundJournal){$DispatchJournalPath=$boundJournal};if($DispatchJournalPath){$dm=Import-Module (Join-Path $PSScriptRoot 'CoordinatorDispatch.psm1') -PassThru -Force;$dispatch=& $dm {param($j,$id)Get-CoordinatorDispatch -JournalPath $j -ExecutionId $id} $DispatchJournalPath $DispatchId;if(-not $dispatch -or $dispatch.state -cne 'Returned' -or ($NoSpawnReceiptPath -and $dispatch.terminalDecision -cne 'prestart-failed') -or (Convert-RegistryGuid ([string]$dispatch.taskId) 'D') -cne $TaskId -or (Convert-RegistryGuid ([string]$dispatch.executionId) 'D') -cne $DispatchId -or -not $dispatch.input.resultPath -or [IO.Path]::GetFullPath([string]$dispatch.input.resultPath) -cne [IO.Path]::GetFullPath($ResultPath)){throw 'DispatchNotSafelyReturned; reservation retained'}}else{if($DispatchJournalPath -or $result.terminal_outcome -notin @('completed','failed','interrupted') -or (($result.PSObject.Properties['result_path'] -and ([string]::IsNullOrWhiteSpace([string]$result.result_path) -or [IO.Path]::GetFullPath([string]$result.result_path) -cne [IO.Path]::GetFullPath($ResultPath))) -or (-not $result.PSObject.Properties['result_path'] -and (-not $boundJob -or -not $boundJob.result_file -or [IO.Path]::GetFullPath([string]$boundJob.result_file) -cne [IO.Path]::GetFullPath($ResultPath))))){throw 'ExplicitBoundTerminalOutcomeRequired; reservation retained'}}
        if($NoSpawnReceiptPath){
            if(-not $dispatch -or $dispatch.terminalDecision -cne 'prestart-failed' -or $dispatch.returnValue.noSpawnReceiptHash -cne $NoSpawnReceiptHash -or $dispatch.returnValue.failureCommitHash -cne $FailureCommitHash -or $dispatch.returnValue.failureCommitPath -cne [IO.Path]::GetFullPath($FailureCommitPath) -or $dispatch.returnValue.resultHash -cne $receipt.resultHash -or $dispatch.returnValue.parentContextHash -cne $receipt.parentContextHash -or $dispatch.returnValue.startIntentHash -cne $receipt.startIntentHash -or $dispatch.returnValue.startAttemptHash -cne $receipt.startAttemptHash -or $dispatch.returnValue.noSpawnAttemptHash -cne $receipt.noSpawnAttemptHash){throw 'ReturnedReceiptGroupRequired'}
            foreach($pair in @(@('noSpawnReceiptPath',[IO.Path]::GetFullPath($NoSpawnReceiptPath)),@('noSpawnReceiptHash',$NoSpawnReceiptHash),@('failureCommitPath',[IO.Path]::GetFullPath($FailureCommitPath)),@('failureCommitHash',$FailureCommitHash),@('resultHash',$receipt.resultHash))){$entry|Add-Member -NotePropertyName $pair[0] -NotePropertyValue $pair[1] -Force}
        }
        $entry.state='terminal';$entry.resultPath=$ResultPath;if(-not $NoSpawnReceiptPath -or -not $entry.terminalAt){$entry.terminalAt=[DateTime]::UtcNow.ToString('o')}
    }
    if($Action -ceq 'Release' -and $NoSpawnReceiptPath){
        & $rm {param($p,$e)Write-RecoveryBytes $p (ConvertTo-RecoveryBytes $e)} $file @($entries)
        return $entry
    }
    [void](Get-AdmissionRemainingMilliseconds $AdmissionBudget)
    $oldMeta=if([IO.File]::Exists($inventoryFile)){Read-AdmissionJson $inventoryFile}else{$null}
    $revision=[long](Get-AdmissionField $oldMeta 'mutationRevision' 0)+1
    [void](Write-AdmissionJson $file @($entries))
    [void](Write-AdmissionJson $inventoryFile @{mutationRevision=$revision;inFlight=$null;invalidated=('RegistryMutation:'+ $Action);snapshotReuse=$false})
    $entry
} finally {$mutex.ReleaseMutex();$mutex.Dispose()}
