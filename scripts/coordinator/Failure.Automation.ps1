function Get-LCSourceFailureState($Config){return Read-AutomationJson (Join-Path $Config.DataDirectory 'source-failures.json') ([pscustomobject]@{sources=@()})}
function Test-LCSourceDue($Config,[string]$Key,[string]$SourceHash) {
    $state=Get-LCSourceFailureState $Config;$found=@($state.sources|Where-Object{$_.key -ceq $Key})
    if($found.Count -gt 1){throw 'SourceFailureIdentityAmbiguous'};if(-not $found.Count){return $true};$f=$found[0]
    if($f.sourceHash -cne $SourceHash){return $true}
    if($f.recoveryDisposition -cne 'RetryTechnical' -or [DateTime]::UtcNow -lt [DateTimeOffset]::Parse([string]$f.lastAttemptUtc).UtcDateTime){return $false}
    return [DateTime]::UtcNow -ge [DateTimeOffset]::Parse([string]$f.nextAttemptUtc).UtcDateTime
}
function Save-LCSourceFailure($Config,[string]$Key,[string]$SourceHash,$ErrorRecord) {
    $state=Get-LCSourceFailureState $Config;$prior=@($state.sources|Where-Object{$_.key -ceq $Key})
    if($prior.Count -gt 1){throw 'SourceFailureIdentityAmbiguous'}
    $attempt=1;if($prior.Count -and $prior[0].sourceHash -ceq $SourceHash){$attempt+= [int]$prior[0].attempts}
    $basis=[int](Get-AutomationValue $Config 'RetryBaseSeconds' 5);$ceiling=[int](Get-AutomationValue $Config 'RetryCeilingSeconds' 3600);$max=[int](Get-AutomationValue $Config 'RetryAttemptCeiling' 256)
    if($basis -lt 1 -or $ceiling -lt $basis -or $max -lt 1){throw 'SourceRetryParametersInvalid'}
    $now=[DateTime]::UtcNow;$retry=($ErrorRecord.Exception -is [IO.IOException]) -and $attempt -lt $max
    if($prior.Count -and $now -lt [DateTimeOffset]::Parse([string]$prior[0].lastAttemptUtc).UtcDateTime){$retry=$false}
    $body=[ordered]@{kind='source-recovery-receipt-v1';key=$Key;sourceHash=$SourceHash;attempts=$attempt;errorKind=$ErrorRecord.Exception.GetType().FullName;errorText=$ErrorRecord.Exception.Message;lastAttemptUtc=$now.ToString('o');nextAttemptUtc=$(if($retry){$now.AddSeconds([Math]::Min($ceiling,$basis*[Math]::Pow(2,[Math]::Min(30,$attempt-1)))).ToString('o')}else{$null});recoveryDisposition=$(if($retry){'RetryTechnical'}else{'RecoveryRequired'});previousReceipt=$(if($prior.Count){$prior[0].recoveryReceipt}else{$null})}
    $ref=Save-LCImmutable (Join-Path $Config.DataDirectory 'source-recovery-receipts') $body
    $projection=[pscustomobject]@{key=$Key;sourceHash=$SourceHash;attempts=$attempt;lastAttemptUtc=$body.lastAttemptUtc;nextAttemptUtc=$body.nextAttemptUtc;recoveryDisposition=$body.recoveryDisposition;recoveryReceipt=$ref}
    Write-AutomationJson (Join-Path $Config.DataDirectory 'source-failures.json') @{sources=@($state.sources|Where-Object{$_.key -cne $Key})+@($projection)}
}
function Complete-LCSourceFailure($Config,[string]$Key) {
    $state=Get-LCSourceFailureState $Config
    # Recovery receipts are retained forever; only the retry projection changes.
    if(@($state.sources|Where-Object{$_.key -ceq $Key}).Count){Write-AutomationJson (Join-Path $Config.DataDirectory 'source-failures.json') @{sources=@($state.sources|Where-Object{$_.key -cne $Key})}}
}
function Invoke-LCImport($Config,[string]$Name,[string]$SourcePath) {
    $key='import:'+ $Name;$sourceHash='unreadable'
    try{
        $sourceHash=if([IO.File]::Exists($SourcePath)){Get-LCHash ([IO.File]::ReadAllBytes($SourcePath))}else{Get-LCHash (Get-LCBytes ([ordered]@{path=$SourcePath;exists=$false}))}
        if(-not (Test-LCSourceDue $Config $key $sourceHash)){return}
        & (Get-Command $Name -CommandType Function -ErrorAction Stop) $Config
        Complete-LCSourceFailure $Config $key
    }catch{Save-LCSourceFailure $Config $key $sourceHash $_}
}
