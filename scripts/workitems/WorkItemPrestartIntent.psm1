$ErrorActionPreference='Stop'
$script:PrestartIntentEncoding=New-Object Text.UTF8Encoding($false,$true)
function Get-WorkItemPrestartIntentPath([string]$AccountingDirectory,[string]$ExecutionId){$h=[Security.Cryptography.SHA256]::Create();try{$k=([BitConverter]::ToString($h.ComputeHash([Text.Encoding]::UTF8.GetBytes($ExecutionId)))).Replace('-','').ToLowerInvariant()}finally{$h.Dispose()};Join-Path ([IO.Path]::GetFullPath($AccountingDirectory)) ('prestart-intent-'+$k+'.json')}
function Get-WorkItemPrestartPayloadHash($Value){if($Value -is [byte[]]){$b=$Value}else{$b=$script:PrestartIntentEncoding.GetBytes((ConvertTo-Json -InputObject $Value -Depth 50 -Compress))};$h=[Security.Cryptography.SHA256]::Create();try{return ([BitConverter]::ToString($h.ComputeHash($b))).Replace('-','').ToLowerInvariant()}finally{$h.Dispose()}}
function Read-WorkItemPrestartIntent([string]$Path,[string]$ExpectedHash){if(-not [IO.File]::Exists($Path)){return $null};try{$b=[IO.File]::ReadAllBytes($Path);if($ExpectedHash -and (Get-WorkItemPrestartPayloadHash $b) -cne $ExpectedHash){throw 'intent hash mismatch'};$r=ConvertFrom-Json -InputObject $script:PrestartIntentEncoding.GetString($b) -ErrorAction Stop;if($r.kind -cne 'workitem-prestart-attempt-v1' -or $r.phase -notin @('Prepared','LaunchIntent','NoSpawnConfirmed','FailurePersisted','Returned','Released')){throw 'invalid intent contract'};return [pscustomobject]@{record=$r;hash=(Get-WorkItemPrestartPayloadHash $b)}}catch{throw 'Persisted prestart intent is invalid; execution remains recovery-closed.'}}
function Write-WorkItemPrestartBytes([string]$Path,[byte[]]$Bytes,[switch]$Create){if($Create){$s=New-Object IO.FileStream($Path,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::None);try{$s.Write($Bytes,0,$Bytes.Length);$s.Flush($true)}finally{$s.Dispose()};return};$tmp=$Path+'.'+[guid]::NewGuid().ToString('N')+'.writing';$s=New-Object IO.FileStream($tmp,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::None);try{$s.Write($Bytes,0,$Bytes.Length);$s.Flush($true)}finally{$s.Dispose()};try{[IO.File]::Replace($tmp,$Path,$null)}finally{if([IO.File]::Exists($tmp)){[IO.File]::Delete($tmp)}}}
function Save-WorkItemPrestartIntent([string]$Path,$Intent,[string]$ExpectedHash,[switch]$Create){$lock=$null;try{$lock=[IO.File]::Open($Path+'.lock',[IO.FileMode]::OpenOrCreate,[IO.FileAccess]::ReadWrite,[IO.FileShare]::None);$bytes=$script:PrestartIntentEncoding.GetBytes((ConvertTo-Json -InputObject $Intent -Depth 50 -Compress));if($Create){if($Intent.kind -cne 'workitem-prestart-attempt-v1' -or $Intent.phase -cne 'Prepared'){throw 'Only a Prepared intent may be created.'};Write-WorkItemPrestartBytes $Path $bytes -Create;return (Get-WorkItemPrestartPayloadHash $bytes)};$old=Read-WorkItemPrestartIntent $Path $ExpectedHash;if(-not $old){throw 'Prestart intent missing.'};if($old.record.executionId -cne $Intent.executionId -or $old.record.payloadHash -cne $Intent.payloadHash -or $old.record.parentContextHash -cne $Intent.parentContextHash -or $old.record.startIntentHash -cne $Intent.startIntentHash){throw 'Prestart intent immutable binding changed.'};$allowed=@{Prepared=@('Prepared','LaunchIntent','NoSpawnConfirmed');LaunchIntent=@('LaunchIntent','NoSpawnConfirmed','FailurePersisted');NoSpawnConfirmed=@('NoSpawnConfirmed','FailurePersisted');FailurePersisted=@('FailurePersisted','Returned');Returned=@('Returned','Released');Released=@('Released')};if($allowed[$old.record.phase] -notcontains $Intent.phase){throw 'Prestart intent terminal phase cannot be replaced or regressed.'};if($Intent.phase -eq 'NoSpawnConfirmed' -and ($Intent.noSpawnProof.kind -cne 'synchronous-launcher-exception' -or $Intent.noSpawnProof.spawnCallEntered -ne $false -or $Intent.noSpawnProof.launcherProcessId -ne $PID -or $Intent.noSpawnProof.launcherStartedAtUtc -cne ([Diagnostics.Process]::GetCurrentProcess().StartTime.ToUniversalTime().ToString('o')) -or $old.record.phase -notin @('Prepared','LaunchIntent','NoSpawnConfirmed'))){throw 'No-spawn requires positive same-process proof before process creation.'};Write-WorkItemPrestartBytes $Path $bytes;return (Get-WorkItemPrestartPayloadHash $bytes)}finally{if($lock){$lock.Dispose()}}}

function Get-PreparedReplayValue($Record,[string]$Name,$Default=$null) { $property=$Record.PSObject.Properties[$Name];if($property){return $property.Value};return $Default }
function Open-WorkItemPreparedAttempt([string]$Path,$Expected,[string]$RegistryDirectory,[switch]$RequireExisting) {
    # This narrow replay never resets phases or manufactures a NoSpawn receipt.
    $registryLock=[Threading.Mutex]::new($false,'Global\AgentOrganizationCoordinatorExecutions')
    $locked=$false;$intentLock=$null
    try {
        $locked=$registryLock.WaitOne(10000)
        if(-not $locked){throw 'PreparedReplayRegistryBusy'}
        $intentLock=[IO.File]::Open($Path+'.lock',[IO.FileMode]::OpenOrCreate,[IO.FileAccess]::ReadWrite,[IO.FileShare]::None)
        $exists=[IO.File]::Exists($Path)
        if($RequireExisting -and -not $exists){throw 'PreparedReplayOriginalIntentRequired'}
        $snapshot=$Path+'.prepared.json'
        if($exists){
            $old=Read-WorkItemPrestartIntent $Path $null
            if($old.record.phase -cne 'Prepared' -or $old.record.noSpawnProof -or -not $old.record.createdAtUtc){throw 'PreparedReplayReceiptOnly'}
            # Compare the entire pinned group, with only the original creation time retained.
            $names=@($Expected.Keys)
            if(@($old.record.PSObject.Properties).Count -ne $names.Count){throw 'PreparedReplayContractConflict'}
            foreach($name in $names){
                if($name -ceq 'createdAtUtc'){continue}
                if((Get-WorkItemPrestartPayloadHash $old.record.$name) -cne (Get-WorkItemPrestartPayloadHash $Expected[$name])){throw ('PreparedReplayBindingConflict:'+ $name)}
            }
            if(-not [IO.File]::Exists($snapshot) -or (Get-WorkItemPrestartPayloadHash ([IO.File]::ReadAllBytes($snapshot))) -cne $old.hash){throw 'PreparedReplayImmutableBytesRequired'}
            $journal=ConvertFrom-Json -InputObject ([IO.File]::ReadAllText($Expected.dispatchJournalPath,$script:PrestartIntentEncoding)) -ErrorAction Stop
            $dispatch=@($journal.executions|Where-Object{$_.executionId -ceq $Expected.executionId})
            if($dispatch.Count -ne 1){throw 'PreparedReplayDispatchRequired'}
            $d=$dispatch[0]
            if($d.state -cne 'Prepared' -or $d.launchBinding -or $d.runningAtUtc -or $d.launchIntentAtUtc -or $d.returnedAtUtc -or $d.terminalDecision -or @($d.effects).Count -or $d.returnValue){throw 'PreparedReplayDispatchConsumed'}
            if(([guid]$d.taskId).ToString('N') -cne $Expected.taskId -or $d.workItemId -cne $Expected.workItemId -or $d.input.authorityHash -cne $Expected.startIntentHash -or $d.input.authorityPath -cne $Expected.startIntentPath -or $d.input.payloadHash -cne $Expected.payloadHash -or $d.input.parentJobPath -cne $Expected.parentJobPath -or $d.input.parentJobHash -cne $Expected.parentJobHash -or $d.input.parentContextPath -cne $Expected.parentContextPath -or $d.input.parentContextHash -cne $Expected.parentContextHash -or $d.input.resultPath -cne $Expected.resultPath -or $d.input.role -cne $Expected.role){throw 'PreparedReplayDispatchBindingConflict'}
        }elseif([IO.File]::Exists($snapshot)){throw 'PreparedReplayOrphanSnapshot'}
        $registryPath=Join-Path $RegistryDirectory 'executions.json'
        $entries=if([IO.File]::Exists($registryPath)){@(ConvertFrom-Json -InputObject ([IO.File]::ReadAllText($registryPath,$script:PrestartIntentEncoding)) -ErrorAction Stop)}else{@()}
        $bound=@($entries|Where-Object{([string]$_.taskId).Replace('-','') -ceq ([string]$Expected.taskId).Replace('-','') -or ([string]$_.dispatchId).Replace('-','') -ceq ([string]$Expected.dispatchId).Replace('-','')})
        if($RequireExisting -and $bound.Count){throw 'PreparedReplayAlreadyReserved; receipt-only recovery required'}
        if($bound.Count -gt 1){throw 'PreparedReplayRegistryAmbiguous'}
        foreach($entry in $bound){
            if($entry.state -cne 'reserved' -or (Get-PreparedReplayValue $entry 'startClaim') -or @(Get-PreparedReplayValue $entry 'managedOperations' @()).Count -or (Get-PreparedReplayValue $entry 'nativeThreadId') -or (Get-PreparedReplayValue $entry 'providerBinding') -or (Get-PreparedReplayValue $entry 'releaseWake') -or (Get-PreparedReplayValue $entry 'jobPath') -or $entry.admission.kind -cne 'managed-local-v1' -or ([string]$entry.taskId).Replace('-','') -cne ([string]$Expected.taskId).Replace('-','') -or ([string]$entry.dispatchId).Replace('-','') -cne ([string]$Expected.dispatchId).Replace('-','') -or $entry.role -cne $Expected.role -or $entry.dispatchJournalPath -cne $Expected.dispatchJournalPath -or $entry.payloadHash -cne $Expected.payloadHash -or $entry.startIntentPath -cne $Expected.startIntentPath -or $entry.startIntentHash -cne $Expected.startIntentHash -or $entry.resultPath -cne $Expected.resultPath -or $entry.parentJobPath -cne $Expected.parentJobPath -or $entry.parentContextPath -cne $Expected.parentContextPath -or $entry.parentContextHash -cne $Expected.parentContextHash){throw 'PreparedReplayRegistryConsumedOrUnbound'}
        }
        $accounting=[IO.Path]::GetDirectoryName($Path)
        $key=Get-WorkItemPrestartPayloadHash ([Text.Encoding]::UTF8.GetBytes($Expected.executionId))
        $artifacts=@($Expected.requestPath,($Path+'.nospawn.json'),(Join-Path $accounting ('execution-'+$key+'.json')),(Join-Path $accounting ('prestart-failure-'+$key+'.json')),(Join-Path $accounting ('prestart-commit-'+$key+'.json')))
        foreach($suffix in @('','.job.json','.job.json.active.json','.window.json','.go.json','.events.jsonl','.public.txt')){$artifacts+=($Expected.resultPath+$suffix)}
        foreach($artifact in $artifacts){if([IO.File]::Exists($artifact)){throw ('PreparedReplayEffectArtifact:'+ $artifact)}}
        $bindingKey=Get-WorkItemPrestartPayloadHash ([Text.Encoding]::UTF8.GetBytes([IO.Path]::GetFullPath($Expected.storePath).ToLowerInvariant()+"`n"+$Expected.workItemId))
        $bindingPath=Join-Path $accounting ('workitem-current-'+$bindingKey+'.json')
        if([IO.File]::Exists($bindingPath)){
            $binding=ConvertFrom-Json -InputObject ([IO.File]::ReadAllText($bindingPath,$script:PrestartIntentEncoding)) -ErrorAction Stop
            if($binding.storePath -cne $Expected.storePath -or $binding.workItemId -cne $Expected.workItemId -or $binding.state -notin @('completed','failed','blocked')){throw 'PreparedReplayPriorBindingUnresolved'}
            if($binding.executionId -ceq $Expected.executionId -or $binding.taskId -ceq $Expected.taskId -or $binding.startIntentHash -ceq $Expected.startIntentHash){throw 'PreparedReplayCurrentBindingConsumed'}
        }
        if($exists){
            $record=[ordered]@{};foreach($property in $old.record.PSObject.Properties){$record[$property.Name]=$property.Value}
            return [pscustomobject]@{record=$record;hash=$old.hash;bytes=[IO.File]::ReadAllBytes($snapshot)}
        }
        $bytes=$script:PrestartIntentEncoding.GetBytes((ConvertTo-Json -InputObject $Expected -Depth 50 -Compress))
        Write-WorkItemPrestartBytes $Path $bytes -Create
        # The first immutable snapshot is these exact bytes, never a reserialization on replay.
        Write-WorkItemPrestartBytes $snapshot $bytes -Create
        return [pscustomobject]@{record=$Expected;hash=(Get-WorkItemPrestartPayloadHash $bytes);bytes=$bytes}
    }finally{if($intentLock){$intentLock.Dispose()};if($locked){$registryLock.ReleaseMutex()};$registryLock.Dispose()}
}
Export-ModuleMember -Function Get-WorkItemPrestartIntentPath,Get-WorkItemPrestartPayloadHash,Read-WorkItemPrestartIntent,Save-WorkItemPrestartIntent,Open-WorkItemPreparedAttempt
