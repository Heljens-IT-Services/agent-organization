[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)][ValidateSet('Count','Reserve','Release','RegisterNative')][string]$Action,
    [Parameter(Mandatory=$true)][string]$DataDirectory,
    [string]$TaskId,
    [string]$DispatchId,
    [string]$NativeThreadId,
    [string]$Role,
    [string]$ResultPath,
    [string]$PayloadHash,
    [ValidateRange(1,100)][int]$Capacity=4,
    [ValidateSet('reserved','active','unknown','terminal')][string]$State='reserved'
)
$ErrorActionPreference='Stop'
$root=[IO.Path]::GetFullPath($DataDirectory);[void][IO.Directory]::CreateDirectory($root)
$file=Join-Path $root 'executions.json';$mutex=New-Object Threading.Mutex($false,'Local\AgentOrganizationCoordinatorExecutions')
if(-not $mutex.WaitOne([TimeSpan]::FromSeconds(30))){throw 'ExecutionRegistryLockUnavailable'}
try {
    $entries=@();if(Test-Path -LiteralPath $file){try{$entries=@([IO.File]::ReadAllText($file,[Text.Encoding]::UTF8)|ConvertFrom-Json)}catch{throw 'ExecutionRegistryUnreadable; capacity remains closed'}}
    if($Action -eq 'Count'){
        $active=@($entries|Where-Object{$_.state -ne 'terminal'});$aliases=@{};$unique=@{}
        foreach($e in $active){if(-not $e.executionId -or (-not $e.taskId -and -not $e.nativeThreadId)){throw 'ExecutionRegistryAmbiguous; capacity remains closed'};$keys=@([string]$e.executionId);if($e.taskId){$keys+='task:'+[string]$e.taskId};if($e.nativeThreadId){$keys+='thread:'+[string]$e.nativeThreadId};$key=$null;foreach($k in $keys){if($aliases.ContainsKey($k)){$key=$aliases[$k];break}};if(-not $key){$key=[string]$e.executionId;$unique[$key]=$e};foreach($k in $keys){$aliases[$k]=$key}}
        [pscustomobject]@{Count=$unique.Count;Executions=@($unique.Values);CapacityKnown=$true};return
    }
    if($Action -eq 'RegisterNative'){
        if(-not $NativeThreadId -or -not $TaskId){throw 'NativeThreadIdAndTaskIdRequired'}
        $match=@($entries|Where-Object{$_.taskId -eq $TaskId -or $_.nativeThreadId -eq $NativeThreadId})
        if($match.Count){foreach($e in $match){if($e.taskId -ne $TaskId -or ($e.nativeThreadId -and $e.nativeThreadId -ne $NativeThreadId)){throw 'ExecutionIdentityConflict'};$e.nativeThreadId=$NativeThreadId;$e.state=$State};$entry=$match[0]}
        else{$entry=[pscustomobject]@{executionId=([guid]::NewGuid().ToString('N'));taskId=$TaskId;dispatchId=$DispatchId;nativeThreadId=$NativeThreadId;role=$Role;resultPath=$ResultPath;payloadHash=$PayloadHash;state=$State;createdAt=[DateTime]::UtcNow.ToString('o')};$entries+= $entry}
    } elseif($Action -eq 'Reserve') {
        if(-not $TaskId -or -not $DispatchId -or -not $PayloadHash){throw 'TaskIdDispatchIdAndPayloadHashRequired'}
        $entry=@($entries|Where-Object{$_.dispatchId -eq $DispatchId -or $_.taskId -eq $TaskId})|Select-Object -First 1
        if($entry){if($entry.taskId -ne $TaskId -or $entry.dispatchId -ne $DispatchId -or $entry.payloadHash -ne $PayloadHash){throw 'ExecutionIdentityConflict'};$copy=$entry|Select-Object *;$copy|Add-Member -NotePropertyName Reused -NotePropertyValue $true;return $copy}
        $active=@($entries|Where-Object{$_.state -ne 'terminal'});$aliases=@{};$known=@{};foreach($e in $active){if(-not $e.executionId -or (-not $e.taskId -and -not $e.nativeThreadId)){throw 'ExecutionRegistryAmbiguous; admission denied'};$keys=@([string]$e.executionId);if($e.taskId){$keys+='task:'+[string]$e.taskId};if($e.nativeThreadId){$keys+='thread:'+[string]$e.nativeThreadId};$key=$null;foreach($k in $keys){if($aliases.ContainsKey($k)){$key=$aliases[$k];break}};if(-not $key){$key=[string]$e.executionId;$known[$key]=$true};foreach($k in $keys){$aliases[$k]=$key}}
        if($known.Count -ge $Capacity){throw 'CoordinatorCapacityFull'}
        $entry=[pscustomobject]@{executionId=$DispatchId;taskId=$TaskId;dispatchId=$DispatchId;nativeThreadId=$null;role=$Role;resultPath=$ResultPath;payloadHash=$PayloadHash;state='reserved';createdAt=[DateTime]::UtcNow.ToString('o')};$entries+= $entry;$entry|Add-Member -NotePropertyName Reused -NotePropertyValue $false
    } elseif($Action -eq 'Release') {
        $entry=@($entries|Where-Object{$_.dispatchId -eq $DispatchId -or $_.taskId -eq $TaskId})|Select-Object -First 1
        if(-not $entry){throw 'ExecutionReservationNotFound'}
        # A slot is released only by persisted terminal result evidence.
        if(-not $ResultPath -or -not (Test-Path -LiteralPath $ResultPath -PathType Leaf)){throw 'TerminalResultRequiredToRelease'}
        $result=[IO.File]::ReadAllText($ResultPath,[Text.Encoding]::UTF8)|ConvertFrom-Json
        if(-not $result.terminal_outcome -and -not $result.success -and -not $result.error){throw 'TerminalResultUnclear; reservation retained'}
        $entry.state='terminal';$entry.resultPath=$ResultPath;$entry.terminalAt=[DateTime]::UtcNow.ToString('o')
    }
    $temp=$file+'.tmp';[IO.File]::WriteAllText($temp,(@($entries)|ConvertTo-Json -Depth 12),[Text.UTF8Encoding]::new($false));Move-Item -LiteralPath $temp -Destination $file -Force
    $entry
} finally {$mutex.ReleaseMutex();$mutex.Dispose()}
