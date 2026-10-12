function Test-LCEventDue($Event,[DateTime]$Now) {
    $f=Get-LCValue $Event 'failureDisposition';if(-not $f){return $true}
    if($f.recoveryDisposition -cne 'RetryTechnical'){return $false}
    if($Now -lt [DateTimeOffset]::Parse([string]$f.lastAttemptUtc).UtcDateTime){return $false}
    return $Now -ge [DateTimeOffset]::Parse([string]$f.nextAttemptUtc).UtcDateTime
}
function Save-CoordinatorEventFailure {
    param([string]$Path,[string]$EventId,[string]$ClaimId,[string]$ErrorKind,[string]$ErrorText,$SourceBinding,[bool]$RetryTechnical,[int]$RetryBaseSeconds=5,[int]$RetryCeilingSeconds=3600,[int]$AttemptCeiling=256)
    if($RetryBaseSeconds -lt 1 -or $RetryCeilingSeconds -lt $RetryBaseSeconds -or $AttemptCeiling -lt 1){throw 'FailureParametersInvalid'}
    # Technical recovery of a returned dispatch never grants a model retry.
    $mode=Get-LCValue $SourceBinding 'recoveryMode'
    if($mode -ceq 'ReturnedTechnical' -and ((Get-LCValue $SourceBinding 'dispatchState') -cne 'Returned' -or -not (Get-LCValue $SourceBinding 'executionId') -or -not (Get-LCValue $SourceBinding 'requestId') -or -not (Get-LCValue $SourceBinding 'inputHash') -or (Get-LCValue $SourceBinding 'eventId') -cne $EventId)){throw 'ReturnedTechnicalFailureBindingConflict'}
    Invoke-CoordinatorEventStoreLock $Path {param($full,$store)
        $hits=@($store.events|Where-Object{$_.id -ceq $EventId});if($hits.Count -ne 1){throw 'EventFailureIdentityConflict'};$e=$hits[0]
        if($e.state -cne 'claimed' -or $e.claimId -cne $ClaimId){throw 'EventFailureClaimMismatch'}
        $old=Get-LCValue $e 'failureDisposition';$attempt=1+[int](Get-LCValue $old 'attempts' 0);$now=[DateTime]::UtcNow
        if($old -and $now -lt [DateTimeOffset]::Parse([string]$old.lastAttemptUtc).UtcDateTime){$RetryTechnical=$false;$ErrorKind='ClockRollback'}
        if($attempt -ge $AttemptCeiling){$RetryTechnical=$false}
        $disposition=if($RetryTechnical){'RetryTechnical'}else{'RecoveryRequired'}
        $delay=[Math]::Min($RetryCeilingSeconds,$RetryBaseSeconds*[Math]::Pow(2,[Math]::Min(30,$attempt-1)))
        $record=[ordered]@{kind='event-recovery-receipt-v1';eventId=$e.id;sourceId=$e.sourceId;payloadHash=$e.payloadHash;claimId=$ClaimId;sourceBinding=$SourceBinding;errorKind=$ErrorKind;errorText=$ErrorText;attempts=$attempt;lastAttemptUtc=$now.ToString('o');nextAttemptUtc=$(if($RetryTechnical){$now.AddSeconds($delay).ToString('o')}else{$null});recoveryDisposition=$disposition;previousReceipt=(Get-LCValue $old 'recoveryReceipt')}
        $ref=Save-LCImmutable ($full+'.recovery') $record
        Set-LCValue $e 'failureDisposition' ([pscustomobject]@{attempts=$attempt;lastAttemptUtc=$record.lastAttemptUtc;nextAttemptUtc=$record.nextAttemptUtc;recoveryDisposition=$disposition;errorKind=$ErrorKind;errorSourceBinding=$SourceBinding;recoveryReceipt=$ref})
        $e.state='pending';$e.claimId=$null;$e.claimedAtUtc=$null;$e.leaseUntilUtc=$null
        Write-CoordinatorEventStore $full $store
        return $e.failureDisposition
    }
}
