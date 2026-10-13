# Internal admission primitives. No native completion token is manufactured here.
. (Join-Path $PSScriptRoot 'ManagedOperations.Persistence.ps1')
$script:AdmissionUtf8=[Text.UTF8Encoding]::new($false,$true)
$script:AdmissionAllSources=@('cli','vscode','exec','appServer','subAgent','subAgentReview','subAgentCompact','subAgentThreadSpawn','subAgentOther','unknown')
function Get-AdmissionField($Value,[string]$Name,$Default=$null) {
    if($null -eq $Value){return $Default}
    if($Value -is [Collections.IDictionary]){if($Value.Contains($Name)){return $Value[$Name]};return $Default}
    $p=$Value.PSObject.Properties[$Name];if($p){return $p.Value};return $Default
}
function Get-AdmissionHash([byte[]]$Bytes) {
    $h=[Security.Cryptography.SHA256]::Create();try{([BitConverter]::ToString($h.ComputeHash($Bytes))).Replace('-','').ToLowerInvariant()}finally{$h.Dispose()}
}
function Get-AdmissionObjectHash($Value){Get-AdmissionHash $script:AdmissionUtf8.GetBytes((ConvertTo-Json -InputObject $Value -Depth 80 -Compress))}
function Read-AdmissionJson([string]$Path){ConvertFrom-Json -InputObject $script:AdmissionUtf8.GetString([IO.File]::ReadAllBytes($Path)) -ErrorAction Stop}
function Write-AdmissionJson([string]$Path,$Value,[switch]$Immutable) {
    [void][IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($Path))
    $bytes=$script:AdmissionUtf8.GetBytes((ConvertTo-Json -InputObject $Value -Depth 80 -Compress))
    if($Immutable){$tmp=$Path}else{$tmp=$Path+'.'+[guid]::NewGuid().ToString('N')+'.writing'}
    $s=[IO.File]::Open($tmp,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::None)
    try{$s.Write($bytes,0,$bytes.Length);$s.Flush($true)}finally{$s.Dispose()}
    if(-not $Immutable){if([IO.File]::Exists($Path)){[IO.File]::Replace($tmp,$Path,$null)}else{[IO.File]::Move($tmp,$Path)}}
    Get-AdmissionHash $bytes
}
function New-AdmissionBudget([int]$Milliseconds=10000) {
    if($Milliseconds -le 0){throw 'AdmissionBudgetInvalid'}
    [pscustomobject]@{Watch=[Diagnostics.Stopwatch]::StartNew();Limit=$Milliseconds;StartedUtc=[DateTime]::UtcNow;LastUtc=[DateTime]::UtcNow}
}
function Get-AdmissionRemainingMilliseconds($Budget) {
    $now=[DateTime]::UtcNow;if($now -lt $Budget.LastUtc){throw 'AdmissionClockRollback'};$Budget.LastUtc=$now
    $r=[long]$Budget.Limit-$Budget.Watch.ElapsedMilliseconds;if($r -le 0){throw 'AdmissionScanBudgetExceeded'}
    [int][Math]::Min([int]::MaxValue,$r)
}
function Get-AdmissionGuid([string]$Value){$g=[guid]::Empty;if([guid]::TryParse($Value,[ref]$g)){return $g.ToString('D')};$Value}
function Test-AdmissionTerminalRelease($Entry) {
    try{
        if((Get-AdmissionField $Entry 'state') -cne 'terminal' -or -not (Get-AdmissionField $Entry 'terminalAt') -or -not (Get-AdmissionField $Entry 'resultPath')){return $false}
        if((Get-AdmissionField (Get-AdmissionField $Entry 'admission') 'kind') -ceq 'managed-local-v1'){
            $release=Get-AdmissionField $Entry 'releaseWake'
            if(-not $release -or $release.payload.resultHash -cne (Get-AdmissionHash ([IO.File]::ReadAllBytes($Entry.resultPath)))){return $false}
        }
        $r=Read-AdmissionJson $Entry.resultPath
        if((Get-AdmissionGuid $r.task_id) -cne (Get-AdmissionGuid $Entry.taskId) -or $r.terminal_outcome -notin @('completed','failed','interrupted')){return $false}
        $journal=[string](Get-AdmissionField $Entry 'dispatchJournalPath')
        if($journal){$j=Read-AdmissionJson $journal;$d=@($j.executions|Where-Object{(Get-AdmissionGuid $_.executionId) -ceq (Get-AdmissionGuid $Entry.dispatchId)});if($d.Count -ne 1 -or $d[0].state -cne 'Returned' -or $d[0].input.payloadHash -cne $Entry.payloadHash -or $d[0].input.resultPath -cne $Entry.resultPath){return $false}}
        else{$jp=[string](Get-AdmissionField $Entry 'jobPath');if(-not $jp){$jp=$Entry.resultPath+'.job.json'};$job=Read-AdmissionJson $jp;if((Get-AdmissionGuid $job.task_id) -cne (Get-AdmissionGuid $Entry.taskId) -or $job.payload_hash -cne $Entry.payloadHash -or $job.result_file -cne $Entry.resultPath){return $false}}
        return $true
    }catch{return $false}
}
function Get-AdmissionCount([object[]]$Entries) {
    # Union all matching components, including bridges. Thread keys never cross providers.
    $rows=@(foreach($e in $Entries){if(-not (Test-AdmissionTerminalRelease $e)){if((Get-AdmissionField $e 'state') -ceq 'terminal'){$copy=$e|Select-Object *;$copy|Add-Member -NotePropertyName state -NotePropertyValue 'unknown' -Force;$copy}else{$e}}})
    $parent=@{};$alias=@{};$unknown=$false;$reasons=[Collections.Generic.List[string]]::new()
    for($i=0;$i -lt $rows.Count;$i++){
        $parent[$i]=$i;$e=$rows[$i];$keys=[Collections.Generic.List[string]]::new()
        foreach($n in @('taskId','dispatchId','executionId')){$v=[string](Get-AdmissionField $e $n);if($v){$keys.Add($n+':'+(Get-AdmissionGuid $v))}}
        $thread=[string](Get-AdmissionField $e 'nativeThreadId');$binding=Get-AdmissionField $e 'providerBinding'
        if($thread){$origin=[string](Get-AdmissionField $binding 'origin');$generation=[string](Get-AdmissionField $binding 'generation');if(-not $origin -or -not $generation){$unknown=$true;$reasons.Add('UnqualifiedNativeThread')}else{$keys.Add('thread:'+$origin+'|'+$generation+'|'+$thread)}}
        if(-not $keys.Count -or ((Get-AdmissionField $e 'state') -notin @('reserved','active') -and -not ((Get-AdmissionField (Get-AdmissionField $e 'admission') 'kind') -ceq 'managed-local-v1' -and (Get-AdmissionField $e 'state') -ceq 'unknown'))){$unknown=$true;$reasons.Add('PersistedAdmittedWorkUnknown')}
        foreach($k in $keys){if($alias.ContainsKey($k)){$a=$i;$b=[int]$alias[$k];while($parent[$a] -ne $a){$a=$parent[$a]};while($parent[$b] -ne $b){$b=$parent[$b]};if($a -ne $b){$parent[$b]=$a}};$alias[$k]=$i}
    }
    $groups=@{};for($i=0;$i -lt $rows.Count;$i++){$p=$i;while($parent[$p] -ne $p){$p=$parent[$p]};if(-not $groups.ContainsKey($p)){$groups[$p]=[Collections.ArrayList]::new()};[void]$groups[$p].Add($rows[$i])}
    foreach($group in $groups.Values){foreach($n in @('taskId','dispatchId','executionId')){$ids=@($group|ForEach-Object{$v=[string](Get-AdmissionField $_ $n);if($v){Get-AdmissionGuid $v}}|Sort-Object -Unique);if($ids.Count -gt 1){$unknown=$true;$reasons.Add('ConflictingAlias:'+ $n)}}}
    $roleCounts=@{};$teamCounts=@{};$workItemIds=@{}
    foreach($group in $groups.Values){
        $roles=@($group|ForEach-Object{Get-AdmissionField $_ 'role'}|Where-Object{$_}|Sort-Object -Unique)
        if($roles.Count -eq 0){$unknown=$true;$reasons.Add('ExecutionRoleUnknown')}
        if($roles.Count -gt 1){$unknown=$true;$reasons.Add('ConflictingExecutionRoles')}
        if($roles.Count -eq 1){$role=[string]$roles[0];if(-not $roleCounts.ContainsKey($role)){$roleCounts[$role]=0};$roleCounts[$role]++}
        $teams=@($group|ForEach-Object{Get-AdmissionField $_ 'teamKey'}|Where-Object{$_}|Sort-Object -Unique)
        if($teams.Count -gt 1 -or ($roles.Count -eq 1 -and $roles[0] -cne 'koordinator' -and $teams.Count -ne 1)){$unknown=$true;$reasons.Add('ExecutionTeamUnknownOrConflict')}
        if($teams.Count -eq 1){$team=[string]$teams[0];if(-not $teamCounts.ContainsKey($team)){$teamCounts[$team]=0};$teamCounts[$team]++}
        $groupWorkIds=@($group|ForEach-Object{Get-AdmissionField $_ 'workItemId'}|Where-Object{$_}|Sort-Object -Unique)
        if($groupWorkIds.Count -gt 1){$unknown=$true;$reasons.Add('ConflictingExecutionWorkItems')}
        if($roles.Count -eq 1 -and [string]$roles[0] -like 'teamleiter_*' -and $groupWorkIds.Count -ne 1){$unknown=$true;$reasons.Add('TeamExecutionWorkItemUnknown')}
        foreach($id in $groupWorkIds){$workItemIds[[string]$id]=$true}
    }
    [pscustomobject]@{Count=$groups.Count;Executions=$rows;RoleCounts=$roleCounts;TeamCounts=$teamCounts;WorkItemIds=@($workItemIds.Keys);CapacityKnown=(-not $unknown);CapacityUnknown=$unknown;Reasons=@($reasons.ToArray())}
}
function Add-AdmissionPin([Collections.IDictionary]$Pins,[string]$Path) {
    if(-not $Path -or -not [IO.Path]::IsPathRooted($Path)){throw 'AdmissionBindingPathMissing'}
    $p=[IO.Path]::GetFullPath($Path);$bytes=[IO.File]::ReadAllBytes($p);$Pins[$p]=Get-AdmissionHash $bytes
    ConvertFrom-Json -InputObject $script:AdmissionUtf8.GetString($bytes) -ErrorAction Stop
}
function Get-AdmissionRoot([string]$JobPath) {
    $visited=@{};$chain=[Collections.ArrayList]::new();$path=$JobPath
    while($path){$path=[IO.Path]::GetFullPath($path);if($visited.ContainsKey($path)){throw 'AdmissionAncestorCycle'};$visited[$path]=$true;$j=Read-AdmissionJson $path;[void]$chain.Add($path)
        if(-not $j.parent_job_path){if($j.role -cne 'koordinator' -or $j.parent_task_id -or -not $j.coordinator_launch){throw 'ActualAdmissionRootMissing'};return [pscustomobject]@{Path=$path;Job=$j;Chain=@($chain)}}
        $pj=Read-AdmissionJson ([string]$j.parent_job_path);if((Get-AdmissionGuid $pj.task_id) -cne (Get-AdmissionGuid $j.parent_task_id)){throw 'AdmissionAncestorIdentityMismatch'};$path=[string]$j.parent_job_path
    }
    throw 'ActualAdmissionRootMissing'
}
function Get-AdmissionScope([string]$RootJobPath,[string]$SessionPath,[object[]]$Entries,$Target,[switch]$ManagedLocal) {
    $pins=[ordered]@{};$unknown=[Collections.Generic.List[string]]::new();$providers=[ordered]@{}
    $root=Add-AdmissionPin $pins $RootJobPath
    if($root.role -cne 'koordinator' -or $root.parent_job_path -or $root.parent_task_id -or -not $root.task_id){throw 'ActualRootJobRequired'}
    $launchPath=[string]$root.coordinator_launch.inputPath;$launch=Add-AdmissionPin $pins $launchPath
    if($pins[[IO.Path]::GetFullPath($launchPath)] -cne $root.coordinator_launch.inputHash){throw 'AdmissionLaunchHashMismatch'}
    $session=Add-AdmissionPin $pins $SessionPath
    if($ManagedLocal -and $session.State -cne 'Ready'){throw 'AdmissionUnknown: ManagedHostNotReady'}
    if($session.RootTaskId -cne $root.task_id -or $session.CoordinatorJobPath -cne [IO.Path]::GetFullPath($RootJobPath) -or $session.CoordinatorLaunchConfigHash -cne $root.coordinator_launch.inputHash -or -not $session.LogicalSessionId){throw 'AdmissionSessionBindingMismatch'}
    $policy=Get-AdmissionField $launch 'admissionPolicy';$limit=Get-AdmissionField $policy 'scanBudgetMilliseconds' 10000
    if((Get-AdmissionField $policy 'snapshotReuse' $false) -ne $false -or [int]$limit -le 0){throw 'AdmissionPolicyInvalid'}
    $jobPolicy=Get-AdmissionField $root.coordinator_launch 'admissionPolicy'
    if(-not $jobPolicy -or $jobPolicy.snapshotReuse -ne $false -or [int]$jobPolicy.scanBudgetMilliseconds -ne [int]$limit){throw 'AdmissionUnknown: RootPolicyGroupUnbound'}
    if([int]$root.admission_capacity -ne [int]$root.coordinator_launch.capacity -or [int]$root.admission_capacity -lt 1){throw 'AdmissionCapacityBindingMismatch'}
    foreach($n in @('workItemStorePath','eventJournalPath')){[void](Add-AdmissionPin $pins ([string](Get-AdmissionField $launch $n)))}
    if([IO.Path]::GetFullPath($root.coordinator_data_directory) -cne [IO.Path]::GetFullPath([string]$launch.registryDirectory) -or $session.StorePath -cne $launch.workItemStorePath -or $session.AccountingDirectory -cne $root.accounting_directory){throw 'AdmissionRootScopeMismatch'}
    $work=@((Get-AdmissionCount $Entries).Executions)
    if(-not $ManagedLocal){
    try{
        foreach($item in @(Get-ChildItem -LiteralPath $root.accounting_directory -Filter 'execution-*.json' -File)){
            $reservation=Read-AdmissionJson $item.FullName
            $registered=@($Entries|Where-Object{(Get-AdmissionGuid (Get-AdmissionField $_ 'taskId')) -ceq (Get-AdmissionGuid $reservation.task_id)})
            if(-not $registered.Count){
                # Only positively proven foreign ancestry is excluded; uncertainty stays relevant.
                $ancestor=[string](Get-AdmissionField $reservation 'parent_job_path')
                try{if($ancestor -and (Get-AdmissionRoot $ancestor).Path -cne [IO.Path]::GetFullPath($RootJobPath)){continue}}catch{}
                [void](Add-AdmissionPin $pins $item.FullName)
                $unknown.Add('PersistedAdmittedReservationUnregistered:'+ $item.FullName)
            }else{[void](Add-AdmissionPin $pins $item.FullName)}
        }
    }catch{$unknown.Add('PinnedAccountingReservationUnreadable')}
    foreach($resultRoot in @($launch.resultDirectories)){
        try{
            foreach($item in @(Get-ChildItem -LiteralPath $resultRoot -Filter '*.job.json' -File)){
                $job=Read-AdmissionJson $item.FullName
                $registered=@($Entries|Where-Object{(Get-AdmissionGuid (Get-AdmissionField $_ 'taskId')) -ceq (Get-AdmissionGuid $job.task_id)})
                if(-not $registered.Count){
                    try{if((Get-AdmissionRoot $item.FullName).Path -cne [IO.Path]::GetFullPath($RootJobPath)){continue}}catch{}
                    [void](Add-AdmissionPin $pins $item.FullName)
                    $unknown.Add('PersistedAdmittedJobUnregistered:'+ $item.FullName)
                }else{[void](Add-AdmissionPin $pins $item.FullName)}
            }
        }catch{$unknown.Add('PinnedResultRootUnreadable:'+ [string]$resultRoot)}
    }
    # Existing root-bound journals are authorities, not an independently configurable provider list.
    $journalPaths=@((Join-Path ([IO.Path]::GetDirectoryName($SessionPath)) 'dispatch-journal.json'))
    $journalPaths+=@($work|ForEach-Object{[string](Get-AdmissionField $_ 'dispatchJournalPath')}|Where-Object{$_})
    foreach($journalPath in @($journalPaths|Sort-Object -Unique)){
        if([IO.File]::Exists($journalPath)){
            try{$journal=Add-AdmissionPin $pins $journalPath
                foreach($dispatch in @($journal.executions|Where-Object{$_.state -ne 'Returned'})){
                    # Prepared has no native start authority yet. A denied
                    # admission for one root must not occupy another root's slot.
                    if($dispatch.state -ceq 'Prepared' -and -not $dispatch.launchBinding -and -not $dispatch.runningAtUtc -and -not (Get-AdmissionField $dispatch 'launchIntentAtUtc')){continue}
                    $registered=@($work|Where-Object{(Get-AdmissionGuid (Get-AdmissionField $_ 'dispatchId')) -ceq (Get-AdmissionGuid $dispatch.executionId)})
                    $isTarget=$Target -and (Get-AdmissionGuid $Target.dispatchId) -ceq (Get-AdmissionGuid $dispatch.executionId) -and $dispatch.input.payloadHash -ceq $Target.payloadHash
                    if(-not $registered.Count -and -not $isTarget){$unknown.Add('UnresolvedAdmittedDispatch:'+ $dispatch.executionId)}
                }
            }catch{$unknown.Add('AdmittedJournalUnreadable:'+ $journalPath)}
        }
    }
    foreach($e in $work){
        # A threadless slot stays counted, but without its durable job/receipt
        # and provably unclaimed prestart state it remains unknown to admission.
        try{
            $jp=[string](Get-AdmissionField $e 'jobPath');if(-not $jp){$rp=[string](Get-AdmissionField $e 'resultPath');if($rp){$jp=$rp+'.job.json'}}
            if(-not $jp){throw 'AdmittedJobBindingMissing'}
            $job=Add-AdmissionPin $pins $jp;$r=Get-AdmissionRoot $jp
            foreach($ancestor in $r.Chain){[void](Add-AdmissionPin $pins $ancestor)}
            if($r.Path -cne [IO.Path]::GetFullPath($RootJobPath) -or (Get-AdmissionGuid $job.task_id) -cne (Get-AdmissionGuid (Get-AdmissionField $e 'taskId'))){throw 'AdmittedRootOrTaskConflict'}
            foreach($pair in @(@('start_intent_path','start_intent_hash'),@('parent_context_path','parent_context_hash'))){$p=[string](Get-AdmissionField $job $pair[0]);if($p){[void](Add-AdmissionPin $pins $p);if($pins[[IO.Path]::GetFullPath($p)] -cne (Get-AdmissionField $job $pair[1])){throw 'AdmittedAuthorityHashMismatch'}}elseif($job.role -cne 'koordinator'){throw 'AdmittedAuthorityMissing'}}
            $journal=[string](Get-AdmissionField $job 'dispatch_journal_path');if($journal){$d=Add-AdmissionPin $pins $journal;$matches=@($d.executions|Where-Object{(Get-AdmissionGuid $_.executionId) -ceq (Get-AdmissionGuid $job.dispatch_id)});if($matches.Count -ne 1 -or (Get-AdmissionGuid $matches[0].taskId) -cne (Get-AdmissionGuid $job.task_id) -or $matches[0].input.payloadHash -cne $job.payload_hash){throw 'AdmittedDispatchBindingMismatch'}}
            $pb=Get-AdmissionField $e 'providerBinding';if(-not $pb){throw 'AdmittedProviderBindingMissing'}
            $receipt=Add-AdmissionPin $pins ([string]$pb.receiptPath);if($pins[[IO.Path]::GetFullPath($pb.receiptPath)] -cne $pb.receiptHash -or $receipt.origin -cne [IO.Path]::GetFullPath($jp) -or $receipt.rootJobPath -cne [IO.Path]::GetFullPath($RootJobPath) -or $receipt.logicalSessionId -cne $session.LogicalSessionId -or $receipt.generation -cne $pb.generation){throw 'AdmittedConnectionBindingMismatch'}
            $process=[Diagnostics.Process]::GetProcessById([int]$receipt.processId)
            try{if($process.HasExited -or $process.StartTime.ToUniversalTime().ToString('o') -cne $receipt.processStartedUtc -or $receipt.generation -cne ($receipt.processId.ToString()+'@'+$receipt.processStartedUtc)){throw 'AdmittedProcessGenerationUnknown'}}finally{$process.Dispose()}
            if($receipt.executable -cne $launch.runtimeExecutable -or $receipt.codexHome -cne $launch.codexHome -or (Get-AdmissionObjectHash @($receipt.arguments)) -cne (Get-AdmissionObjectHash @($launch.runtimeArguments)) -or (Get-AdmissionHash ([IO.File]::ReadAllBytes($receipt.executable))) -cne $receipt.executableHash){throw 'AdmittedEffectiveRuntimeMismatch'}
            $key=$receipt.origin+'|'+$receipt.generation;if($providers.Contains($key) -and (Get-AdmissionObjectHash $providers[$key]) -cne (Get-AdmissionObjectHash $receipt)){throw 'ConflictingProviderBinding'};$providers[$key]=$receipt
            $activePath=$jp+'.active.json';if([IO.File]::Exists($activePath)){[void](Add-AdmissionPin $pins $activePath)}
        }catch{$unknown.Add($_.Exception.Message)}
    }
    } # Legacy inventory is diagnostic, not the managed-host membership source.
    if($Target){
        try{
            if(-not $Target.taskId -or -not $Target.dispatchId -or -not $Target.payloadHash -or -not $Target.resultPath){throw 'AdmissionTargetIncomplete'}
            $a=Add-AdmissionPin $pins $Target.startIntentPath
            if($pins[[IO.Path]::GetFullPath($Target.startIntentPath)] -cne $Target.startIntentHash){throw 'AdmissionTargetAuthorityHashMismatch'}
            if([IO.Path]::GetFullPath([string]$Target.parentJobPath) -cne [IO.Path]::GetFullPath([string]$a.parentJobPath)){throw 'AdmissionTargetParentJobMismatch'}
            if([IO.Path]::GetFullPath([string]$Target.parentContextPath) -cne [IO.Path]::GetFullPath([string]$a.parentContextPath) -or [string]$Target.parentContextHash -cne [string]$a.parentContextHash){throw 'AdmissionTargetParentContextMismatch'}
            if($a.kind -ceq 'admission-legacy-start-authority-v1'){
                if($a.payloadHash -cne $Target.payloadHash){throw 'AdmissionLegacyPayloadMismatch'}
            }elseif($a.kind -ceq 'delegated-start-authority-v1'){
                if($Target.payloadHash -cne $Target.startIntentHash){throw 'AdmissionSSOTAuthorityFileHashMismatch'}
            }else{throw 'AdmissionTargetAuthorityKindUnknown'}
            $ap=$a.parameters
            foreach($pair in @(@('StableTaskId','taskId'),@('DispatchId','dispatchId'),@('ResultPath','resultPath'),@('Role','role'),@('DispatchJournalPath','dispatchJournalPath'))){if([string](Get-AdmissionField $ap $pair[0]) -cne [string](Get-AdmissionField $Target $pair[1])){throw ('AdmissionTargetMismatch:'+ $pair[0])}}
            $parentJob=Read-AdmissionJson $a.parentJobPath;$cm=Import-Module (Join-Path $PSScriptRoot '..\workitems\CoordinatorExecutionContext.psm1') -PassThru -Force
            if($a.kind -ceq 'delegated-start-authority-v1'){
                $parentJobHash=& $cm {param($j)Get-ExecutionJobHash $j} $parentJob
                if($parentJobHash -cne $a.parentJobHash -or $ap.ParentTaskId -cne $parentJob.task_id -or [IO.Path]::GetFullPath([string]$ap.WorkItemStorePath) -cne [IO.Path]::GetFullPath([string]$launch.workItemStorePath) -or [IO.Path]::GetFullPath([string]$ap.AccountingDirectory) -cne [IO.Path]::GetFullPath([string]$root.accounting_directory) -or [IO.Path]::GetFullPath([string]$a.parentContextPath) -cne [IO.Path]::GetFullPath([string]$Target.parentContextPath) -or [string]$a.parentContextHash -cne [string]$Target.parentContextHash){throw 'AdmissionSSOTParentAuthorityBindingMismatch'}
            }
            if([int]$ap.AdmissionCapacity -ne [int]$root.admission_capacity -or $ap.CoordinatorDataDirectory -cne $launch.registryDirectory){throw 'AdmissionTargetScopeMismatch'}
            if($a.kind -ceq 'delegated-start-authority-v1' -and ($ap.WorkItemStorePath -cne $launch.workItemStorePath -or $ap.AccountingDirectory -cne $root.accounting_directory)){throw 'AdmissionTargetStoreOrAccountingMismatch'}
            $targetResult=[IO.Path]::GetFullPath($Target.resultPath);$inRoot=$false
            foreach($r in @($launch.resultDirectories)){$prefix=[IO.Path]::GetFullPath($r).TrimEnd('\')+'\';if($targetResult.StartsWith($prefix,[StringComparison]::OrdinalIgnoreCase)){$inRoot=$true}}
            if(-not $inRoot){throw 'AdmissionTargetResultRootMismatch'}
            $pr=Get-AdmissionRoot $a.parentJobPath;if($pr.Path -cne [IO.Path]::GetFullPath($RootJobPath)){throw 'AdmissionTargetAncestorMismatch'};foreach($p in $pr.Chain){[void](Add-AdmissionPin $pins $p)}
            [void](Add-AdmissionPin $pins $a.parentContextPath);if($pins[[IO.Path]::GetFullPath($a.parentContextPath)] -cne $a.parentContextHash){throw 'AdmissionHistoricalContextMismatch'}
            $parentContext=& $cm {param($p,$h,$j,$t,$s,$acc)Assert-ExecutionContext -ContextPath $p -ContextHash $h -JobPath $j -TaskId $t -StorePath $s -AccountingDirectory $acc} $a.parentContextPath $a.parentContextHash $a.parentJobPath $parentJob.task_id $launch.workItemStorePath $root.accounting_directory
            & $cm {param($p,$h,$s,$acc)Assert-ExecutionAncestors -ContextPath $p -ContextHash $h -StorePath $s -AccountingDirectory $acc|Out-Null} $a.parentContextPath $a.parentContextHash $launch.workItemStorePath $root.accounting_directory
            if($Target.dispatchJournalPath){$j=Add-AdmissionPin $pins $Target.dispatchJournalPath;$match=@($j.executions|Where-Object{(Get-AdmissionGuid $_.executionId) -ceq (Get-AdmissionGuid $Target.dispatchId)});if($match.Count -ne 1 -or $match[0].input.payloadHash -cne $Target.payloadHash -or $match[0].state -notin @('Prepared','LaunchIntent')){throw 'AdmissionTargetDispatchMismatch'}}elseif($a.kind -cne 'admission-legacy-start-authority-v1'){throw 'AdmissionTargetDispatchMissing'}
        }catch{$unknown.Add($_.Exception.Message)}
    }
    [pscustomobject]@{RootJobPath=[IO.Path]::GetFullPath($RootJobPath);SessionPath=[IO.Path]::GetFullPath($SessionPath);RootTaskId=$root.task_id;LogicalSessionId=$session.LogicalSessionId;Capacity=[int]$root.admission_capacity;BudgetMilliseconds=[int]$limit;Directory=[IO.Path]::GetFullPath($launch.registryDirectory);Pins=$pins;Providers=@($providers.Values);Unknown=@($unknown.ToArray());Hash=(Get-AdmissionObjectHash $pins)}
}
function Get-AdmissionRegistryHash([string]$File){if([IO.File]::Exists($File)){return Get-AdmissionHash ([IO.File]::ReadAllBytes($File))};'absent'}
function Invoke-AdmissionRegistryLocked {
    param([string]$Action,[string]$Directory,[object[]]$Entries,$Target,[string]$RootJobPath,[string]$SessionPath,[string]$RequestHash,$Budget,$ProviderBinding)
    # Called ONLY while the caller owns Global\AgentOrganizationCoordinatorExecutions.
    $file=Join-Path $Directory 'executions.json';$metaPath=Join-Path $Directory 'execution-inventory.json'
    $meta=if([IO.File]::Exists($metaPath)){Read-AdmissionJson $metaPath}else{$null}
    $revision=[long](Get-AdmissionField $meta 'mutationRevision' 0)
    foreach($record in $Entries){$revision=[Math]::Max($revision,[long](Get-AdmissionField (Get-AdmissionField $record 'admission') 'revision' 0))}
    [void](Get-AdmissionRemainingMilliseconds $Budget)
    if($Action -eq 'Count'){return Get-AdmissionCount $Entries}
    if($Action -eq 'ConfirmInventory'){throw 'AdmissionUnknown: LegacyCompleteEpochCannotGrantOrRelease'}
    if($Action -eq 'ReadAdmissionReservation'){
        $matches=@($Entries|Where-Object{(Get-AdmissionGuid $_.taskId) -ceq (Get-AdmissionGuid $Target.taskId) -and (Get-AdmissionGuid $_.dispatchId) -ceq (Get-AdmissionGuid $Target.dispatchId)})
        if($matches.Count -ne 1 -or $matches[0].state -cne 'reserved' -or $matches[0].payloadHash -cne $Target.payloadHash -or $matches[0].resultPath -cne $Target.resultPath -or $matches[0].admission.requestHash -cne $RequestHash -or $matches[0].admission.targetHash -cne (Get-AdmissionObjectHash $Target)){throw 'AdmissionUnknown: ReservationReadbackMismatch'}
        if(Get-AdmissionField $matches[0] 'startClaim'){throw 'AdmissionUnknown: ExistingReservationRequiresReceiptOnlyRecovery'}
        $callerProcess=[Diagnostics.Process]::GetProcessById($PID)
        try{$callerStartedUtc=$callerProcess.StartTime.ToUniversalTime().ToString('o')}finally{$callerProcess.Dispose()}
        $matches[0]|Add-Member -NotePropertyName startClaim -NotePropertyValue @{callerPid=$PID;callerStartedUtc=$callerStartedUtc;targetHash=(Get-AdmissionObjectHash $Target);requestHash=$RequestHash;claimedAtUtc=[DateTime]::UtcNow.ToString('o')} -Force
        [void](Get-AdmissionRemainingMilliseconds $Budget)
        [void](Write-AdmissionJson $file @($Entries))
        [void](Write-AdmissionJson $metaPath @{mutationRevision=($revision+1);inFlight=$null;invalidated='ExactReservationStartClaim';snapshotReuse=$false})
        $matches[0]|Add-Member -NotePropertyName Reused -NotePropertyValue $false -Force
        return $matches[0]
    }
    if($Action -eq 'BindProvider'){
        $binding=Read-AdmissionJson $ProviderBinding.receiptPath
        if((Get-AdmissionHash ([IO.File]::ReadAllBytes($ProviderBinding.receiptPath))) -cne $ProviderBinding.receiptHash -or -not $binding.origin -or -not $binding.generation){throw 'AdmissionProviderReceiptMismatch'}
        $matches=@($Entries|Where-Object{(Get-AdmissionGuid $_.taskId) -ceq (Get-AdmissionGuid $Target.taskId) -and $_.state -ne 'terminal'})
        if($matches.Count -ne 1){throw 'AdmissionProviderReservationRequired'}
        $prior=Get-AdmissionField $matches[0] 'providerBinding'
        if($prior -and $prior.generation -cne $binding.generation){
            if((Get-AdmissionField $matches[0].admission 'kind') -cne 'managed-local-v1'){throw 'AdmissionUnknown: ExactProviderOwnershipTransferRequired'}
            try{$oldProcess=[Diagnostics.Process]::GetProcessById([int]$prior.processId)}catch [ArgumentException]{$oldProcess=$null}
            if($oldProcess){try{if(-not $oldProcess.HasExited -and $oldProcess.StartTime.ToUniversalTime().ToString('o') -ceq $prior.processStartedUtc){throw 'AdmissionUnknown: PriorManagedProviderStillAlive'}}finally{$oldProcess.Dispose()}}
            if(@(Get-AdmissionField $matches[0] 'managedOperations' @()|Where-Object{$_.state -cne 'Acknowledged'}).Count){throw 'AdmissionUnknown: PriorManagedOperationUnresolved'}
        }
        $job=Read-AdmissionJson $binding.origin;$root=Get-AdmissionRoot $binding.origin;$session=Read-AdmissionJson $binding.sessionPath
        if((Get-AdmissionGuid $job.task_id) -cne (Get-AdmissionGuid $Target.taskId) -or $root.Path -cne $binding.rootJobPath -or $session.LogicalSessionId -cne $binding.logicalSessionId -or $session.RootTaskId -cne $root.Job.task_id){throw 'AdmissionProviderRootMismatch'}
        $matches[0].admission.logicalSessionId=$session.LogicalSessionId
        $matches[0]|Add-Member -NotePropertyName jobPath -NotePropertyValue $binding.origin -Force
        $matches[0]|Add-Member -NotePropertyName providerBinding -NotePropertyValue $binding -Force
        $matches[0].providerBinding|Add-Member -NotePropertyName receiptPath -NotePropertyValue $ProviderBinding.receiptPath -Force
        $matches[0].providerBinding|Add-Member -NotePropertyName receiptHash -NotePropertyValue $ProviderBinding.receiptHash -Force
        [void](Write-AdmissionJson $file @($Entries));[void](Write-AdmissionJson $metaPath @{mutationRevision=($revision+1);inFlight=$null;invalidated='ProviderBindingChanged'})
        return $matches[0]
    }
    if($Action -eq 'EnrollRoot'){
        # Enrollment reserves the explicit host root; it certifies no foreign provider membership.
        $root=Read-AdmissionJson $RootJobPath;$launch=Read-AdmissionJson $root.coordinator_launch.inputPath
        if($root.role -cne 'koordinator' -or $root.parent_task_id -or $root.parent_job_path -or -not $root.task_id -or (Get-AdmissionHash ([IO.File]::ReadAllBytes($root.coordinator_launch.inputPath))) -cne $root.coordinator_launch.inputHash -or [IO.Path]::GetFullPath($Directory) -cne [IO.Path]::GetFullPath($launch.registryDirectory)){throw 'ActualRootEnrollmentBindingRequired'}
        $existing=@($Entries|Where-Object{(Get-AdmissionGuid $_.taskId) -ceq (Get-AdmissionGuid $root.task_id)})
        if($existing.Count){if($existing.Count -ne 1 -or $existing[0].jobPath -cne [IO.Path]::GetFullPath($RootJobPath)){throw 'RootEnrollmentConflict'};throw 'AdmissionUnknown: ExistingRootRequiresReceiptOnlyRecovery'}
        if((Get-AdmissionCount $Entries).Count){throw 'AdmissionUnknown: RootEnrollmentNeedsExistingMembershipReconciliation'}
        # Empty managed ledger permits this new root only; existing unknown work remains a barrier.
        $entry=[pscustomobject]@{taskId=(Get-AdmissionGuid $root.task_id);executionId=(Get-AdmissionGuid $root.task_id);dispatchId=$root.dispatch_id;nativeThreadId=$null;role='koordinator';jobPath=[IO.Path]::GetFullPath($RootJobPath);resultPath=$root.result_file;payloadHash=$root.payload_hash;state='reserved';teamKey=$null;enrollment='managed-local';AdmissionAllowed=$true;Reused=$false;admission=@{kind='managed-local-v1';rootJobPath=[IO.Path]::GetFullPath($RootJobPath);logicalSessionId=$null;revision=($revision+1)};reason='ManagedHostScopeOnly'}
        [void](Write-AdmissionJson $file @($Entries+$entry));[void](Write-AdmissionJson $metaPath @{mutationRevision=($revision+1);inFlight=$null;invalidated=$entry.reason});return $entry
    }
    if($Action -eq 'ReserveManaged'){
        $scope=Get-AdmissionScope $RootJobPath $SessionPath $Entries $Target -ManagedLocal
        if($scope.Unknown.Count){throw ('AdmissionUnknown: '+($scope.Unknown -join ','))}
        $root=Read-AdmissionJson $RootJobPath;$launch=Read-AdmissionJson $root.coordinator_launch.inputPath
        foreach($e in $Entries){
            if(Test-AdmissionTerminalRelease $e){continue}
            if((Get-AdmissionField (Get-AdmissionField $e 'admission') 'kind') -cne 'managed-local-v1' -or $e.admission.rootJobPath -cne $scope.RootJobPath -or ($e.admission.logicalSessionId -and $e.admission.logicalSessionId -cne $scope.LogicalSessionId)){throw 'AdmissionUnknown: ManagedBaselineUnbound'}
        }
        $existing=@($Entries|Where-Object{(Get-AdmissionGuid $_.taskId) -ceq (Get-AdmissionGuid $Target.taskId) -or (Get-AdmissionGuid $_.dispatchId) -ceq (Get-AdmissionGuid $Target.dispatchId)})
        if($existing.Count){throw 'AdmissionUnknown: ExistingReservationRequiresReceiptOnlyRecovery'}
        $parentJob=Read-AdmissionJson $Target.parentJobPath
        $parents=@($Entries|Where-Object{(Get-AdmissionGuid $_.taskId) -ceq (Get-AdmissionGuid $parentJob.task_id) -and $_.state -in @('reserved','active')})
        if($parents.Count -ne 1){throw 'AdmissionUnknown: ManagedParentReservationRequired'}
        if($parentJob.role -ceq 'koordinator'){
            if($Target.role -notmatch '^teamleiter_[a-z][a-z0-9_]*$'){throw 'AdmissionUnknown: CoordinatorMustStartTeamLeader'}
            $team=[string]$Target.role
        }else{
            $team=[string](Get-AdmissionField $parents[0] 'teamKey')
            if(-not $team -or $parentJob.role -cne $team -or $Target.role -like 'teamleiter_*' -or $Target.role -ceq 'koordinator'){throw 'AdmissionUnknown: SpecialistParentAuthorityRequired'}
        }
        $count=Get-AdmissionCount $Entries
        if($count.CapacityUnknown){throw 'AdmissionUnknown: ManagedCapacityUnknown'}
        $waitPath=Join-Path (Join-Path $Directory 'managed-waiting') ((Get-AdmissionGuid $Target.dispatchId)+'.json')
        $wait=[ordered]@{target=$Target;targetHash=(Get-AdmissionObjectHash $Target);rootJobPath=$scope.RootJobPath;teamKey=$team;state='waiting';reason='capacity'}
        if($count.Count -ge $scope.Capacity){[void](Write-AdmissionJson $waitPath $wait);throw 'CoordinatorCapacityFull'}
        $limits=Get-AdmissionField $launch 'teamCapacities'
        if($limits){foreach($property in $limits.PSObject.Properties){$limit=0;if(-not [int]::TryParse([string]$property.Value,[ref]$limit) -or $property.Name -notmatch '^teamleiter_[a-z][a-z0-9_]*$' -or $limit -lt 1 -or $limit -gt $scope.Capacity){throw 'AdmissionTeamCapacityInvalid'}}}
        $teamLimit=Get-AdmissionField $limits $team $scope.Capacity
        if($count.TeamCounts.ContainsKey($team) -and [int]$count.TeamCounts[$team] -ge [int]$teamLimit){$wait.reason='team-capacity';[void](Write-AdmissionJson $waitPath $wait);throw 'CoordinatorCapacityFull:TeamCapacity'}
        # Team parents retain their slot while a specialist executes. Keep one
        # unallocated child slot available for each newly admitted team parent.
        $minimum=if($Target.role -like 'teamleiter_*' -and [int]$teamLimit -gt 1){2}else{1}
        $headroom=Get-ManagedChildHeadroom $count.Executions
        $required=$minimum
        $workingSpecialists=@($count.Executions|Where-Object{(Get-AdmissionField $_ 'role') -cne 'koordinator' -and (Get-AdmissionField $_ 'role') -notlike 'teamleiter_*' -and $_.state -ceq 'active' -and (Get-AdmissionField $_ 'nativeThreadId')})
        if($scope.Capacity -ge 4 -and $workingSpecialists.Count){$required=1}
        if($Target.role -like 'teamleiter_*' -and $count.Count+$headroom+$required -gt $scope.Capacity){$wait.reason='child-headroom';[void](Write-AdmissionJson $waitPath $wait);throw 'CoordinatorCapacityFull:ChildHeadroom'}
        $authority=Read-AdmissionJson $Target.startIntentPath
        $requestHash=Get-AdmissionObjectHash @{target=$Target;scope=$scope.Hash;registry=(Get-AdmissionRegistryHash $file)}
        $entry=[pscustomobject]@{taskId=(Get-AdmissionGuid $Target.taskId);dispatchId=(Get-AdmissionGuid $Target.dispatchId);executionId=(Get-AdmissionGuid $Target.dispatchId);nativeThreadId=$null;role=$Target.role;teamKey=$team;minimumConcurrentExecutions=$minimum;workItemId=(Get-AdmissionField $authority.parameters 'WorkItemId');resultPath=$Target.resultPath;jobPath=$null;payloadHash=$Target.payloadHash;dispatchJournalPath=$Target.dispatchJournalPath;parentJobPath=$Target.parentJobPath;parentContextPath=$Target.parentContextPath;parentContextHash=$Target.parentContextHash;startIntentPath=$Target.startIntentPath;startIntentHash=$Target.startIntentHash;state='reserved';terminalAt=$null;createdAt=[DateTime]::UtcNow.ToString('o');admission=@{kind='managed-local-v1';requestHash=$requestHash;targetHash=(Get-AdmissionObjectHash $Target);scopeHash=$scope.Hash;rootJobPath=$scope.RootJobPath;logicalSessionId=$scope.LogicalSessionId;revision=($revision+1)};Reused=$false}
        foreach($pin in $scope.Pins.Keys){if((Get-AdmissionHash ([IO.File]::ReadAllBytes($pin))) -cne $scope.Pins[$pin]){throw 'AdmissionUnknown: ManagedAuthorityChangedBeforeCommit'}}
        [void](Write-AdmissionJson $file @($Entries+$entry))
        return $entry
    }
    if($Action -eq 'BeginAdmission'){
        $scope=Get-AdmissionScope $RootJobPath $SessionPath $Entries $Target
        $count=Get-AdmissionCount $Entries
        $nonce=[guid]::NewGuid().ToString('N') # transport correlation, never execution identity
        $threads=@($Entries|Where-Object{$_.nativeThreadId}|ForEach-Object{@{origin=(Get-AdmissionField (Get-AdmissionField $_ 'providerBinding') 'origin');generation=(Get-AdmissionField (Get-AdmissionField $_ 'providerBinding') 'generation');id=$_.nativeThreadId}})
        $sessionForThreads=Read-AdmissionJson $SessionPath
        foreach($p in @($scope.Providers|Where-Object{$_.kind -ceq 'host'})){if($sessionForThreads.NativeThreadId){$threads+=@{origin=$p.origin;generation=$p.generation;id=$sessionForThreads.NativeThreadId}}}
        $request=[ordered]@{kind='admission-request-v1';nonce=$nonce;rootJobPath=$RootJobPath;sessionPath=$SessionPath;scope=$scope;target=$Target;boundThreads=$threads;targetHash=(Get-AdmissionObjectHash $Target);registryHash=(Get-AdmissionRegistryHash $file);mutationRevision=$revision;startedUtc=$Budget.StartedUtc.ToString('o');remainingMilliseconds=(Get-AdmissionRemainingMilliseconds $Budget);expiresUtc=$Budget.StartedUtc.AddMilliseconds($Budget.Limit).ToString('o');unknown=@($scope.Unknown)+@($count.Reasons)}
        $hash=Get-AdmissionObjectHash $request
        [void](Write-AdmissionJson $metaPath @{mutationRevision=$revision;inFlight=@{hash=$hash;request=$request;state='Collecting'};snapshotReuse=$false})
        return [pscustomobject]@{Hash=$hash;Request=$request}
    }
    if($Action -eq 'InvalidateAdmission'){
        if($meta -and (Get-AdmissionField $meta.inFlight 'hash') -ceq $RequestHash){[void](Write-AdmissionJson $metaPath @{mutationRevision=$revision;inFlight=@{hash=$RequestHash;state='Invalidated'};reason=(Get-AdmissionField $Target 'reason' 'AdmissionUnknown')})};return
    }
    if($Action -notin @('Reserve','CommitAdmissionReserve')){throw 'UnsupportedAdmissionRegistryAction'}
    $pending=Get-AdmissionField $meta 'inFlight';$request=Get-AdmissionField $pending 'request'
    if(-not $RequestHash -or (Get-AdmissionField $pending 'hash') -cne $RequestHash -or (Get-AdmissionField $pending 'state') -cne 'Collecting' -or (Get-AdmissionObjectHash $request) -cne $RequestHash){throw 'AdmissionUnknown: FreshSingleUseRequestRequired'}
    if((Get-AdmissionObjectHash $Target) -cne $request.targetHash -or $revision -ne $request.mutationRevision -or (Get-AdmissionRegistryHash $file) -cne $request.registryHash){throw 'AdmissionUnknown: RevisionOrTargetChanged'}
    # Preserve every new real native observation before evaluating completeness. No absence release.
    $newObservations=@()
    foreach($p in @($request.scope.Providers)){
        $path=Join-Path ($p.origin+'.inventory') ($RequestHash+'.answer.json')
        if([IO.File]::Exists($path)){
            $answer=Read-AdmissionJson $path
            if($answer.requestHash -cne $RequestHash -or $answer.providerHash -cne (Get-AdmissionObjectHash $p) -or $answer.scopeHash -cne $request.scope.Hash){throw 'AdmissionUnknown: ObservationAnswerBindingMismatch'}
            foreach($o in @($answer.observations)){
                if(-not $o.threadId -or $o.origin -cne $p.origin -or $o.generation -cne $p.generation){throw 'AdmissionUnknown: ObservationProviderIdentityMissing'}
                $bound=@($Entries+$newObservations|Where-Object{(Get-AdmissionField $_ 'nativeThreadId') -ceq $o.threadId -and (Get-AdmissionField (Get-AdmissionField $_ 'providerBinding') 'origin') -ceq $p.origin -and (Get-AdmissionField (Get-AdmissionField $_ 'providerBinding') 'generation') -ceq $p.generation})
                if(-not $bound.Count -and @($request.boundThreads|Where-Object{$_.id -ceq $o.threadId -and $_.origin -ceq $p.origin -and $_.generation -ceq $p.generation}).Count){$newObservations+=[pscustomobject]@{taskId=$null;dispatchId=$null;executionId=$null;nativeThreadId=$o.threadId;providerBinding=$p;state='unknown';role=$null;source='native-observation';observation=$o;requestHash=$RequestHash;resultPath=$null;terminalAt=$null;inventoryAbsentAt=$null}}
            }
        }
    }
    if($newObservations.Count){[void](Write-AdmissionJson $file @($Entries+$newObservations));[void](Write-AdmissionJson $metaPath @{mutationRevision=($revision+1);inFlight=@{hash=$RequestHash;state='Invalidated'};reason='NativeOnlyAdmittedWorkUnknown'});throw 'AdmissionUnknown: NativeOnlyAdmittedWorkUnknown'}
    $scope=Get-AdmissionScope $request.rootJobPath $request.sessionPath $Entries $Target
    if($scope.Hash -cne $request.scope.Hash -or $scope.Unknown.Count -or @($request.unknown).Count){throw 'AdmissionUnknown: ScopeOrMembershipChanged'}
    $count=Get-AdmissionCount $Entries;if($count.CapacityUnknown){throw 'AdmissionUnknown: PersistedAdmittedWorkUnknown'}
    $answers=@();foreach($p in $scope.Providers){
        $path=Join-Path ($p.origin+'.inventory') ($RequestHash+'.answer.json');$answer=Read-AdmissionJson $path
        if($answer.requestHash -cne $RequestHash -or $answer.providerHash -cne (Get-AdmissionObjectHash $p) -or $answer.generation -cne $p.generation -or $answer.scopeHash -cne $scope.Hash -or @($answer.errors).Count -or $answer.pageCompletion -ne 'BothArchivedAndLoadedAndRead' -or $answer.gapBefore -ne $answer.gapAfter -or $answer.mutationBefore -ne $answer.mutationAfter){throw 'AdmissionUnknown: ProviderResponseIncompleteOrChanged'}
        # Concrete capability decision lives in code bound to installed sources; no caller boolean enables A/B.
        $contract=Get-AdmissionInstalledContract $p
        if($contract.completionMode -notin @('AtomicProviderFence','InstrumentedNativeBirthFence')){throw ('AdmissionUnknown: MissingExternalAccess:'+($contract.missing -join ','))}
        $answers+=$answer
    }
    if(-not $scope.Providers.Count){throw 'AdmissionUnknown: NoBoundReader'}
    # Unknown native observations count and close admission, never fabricate a TaskId.
    foreach($answer in $answers){foreach($o in @($answer.observations)){
        $bound=@($Entries|Where-Object{$_.nativeThreadId -ceq $o.threadId -and $_.providerBinding.origin -ceq $answer.origin -and $_.providerBinding.generation -ceq $answer.generation})
        if(-not $bound.Count -and $o.status -ne 'idle'){throw 'AdmissionUnknown: NativeOnlyUnboundWork'}
        if($o.status -in @('notLoaded','systemError','unknown')){throw 'AdmissionUnknown: NativeStatusUnknown'}
    }}
    $existing=@($Entries|Where-Object{(Get-AdmissionGuid $_.taskId) -ceq (Get-AdmissionGuid $Target.taskId) -or (Get-AdmissionGuid $_.dispatchId) -ceq (Get-AdmissionGuid $Target.dispatchId)})
    if($existing.Count){throw 'AdmissionUnknown: ExistingReservationRequiresReceiptOnlyRecovery'}
    if($count.Count -ge $scope.Capacity){throw 'CoordinatorCapacityFull'}
    $rootForLimits=Read-AdmissionJson $scope.RootJobPath
    $launchForLimits=Read-AdmissionJson $rootForLimits.coordinator_launch.inputPath
    foreach($pinPath in @($scope.RootJobPath,$rootForLimits.coordinator_launch.inputPath)){if((Get-AdmissionHash ([IO.File]::ReadAllBytes($pinPath))) -cne $scope.Pins[[IO.Path]::GetFullPath($pinPath)]){throw 'AdmissionLimitSourceChangedBeforeReserve'}}
    $teamLimits=Get-AdmissionField $launchForLimits 'teamCapacities'
    if($teamLimits){
        foreach($property in $teamLimits.PSObject.Properties){$limit=0;if(-not [int]::TryParse([string]$property.Value,[ref]$limit) -or $property.Name -notmatch '^teamleiter_[a-z][a-z0-9_]*$' -or $limit -lt 1 -or $limit -gt $scope.Capacity){throw 'AdmissionTeamCapacityInvalid'}}
        $teamLimit=Get-AdmissionField $teamLimits ([string]$Target.role)
        if($null -ne $teamLimit){$used=if($count.RoleCounts.ContainsKey([string]$Target.role)){[int]$count.RoleCounts[[string]$Target.role]}else{0};if($used -ge [int]$teamLimit){throw 'CoordinatorCapacityFull:TeamCapacity'}}
    }
    [void](Get-AdmissionRemainingMilliseconds $Budget)
    $entry=[pscustomobject]@{taskId=(Get-AdmissionGuid $Target.taskId);dispatchId=(Get-AdmissionGuid $Target.dispatchId);executionId=(Get-AdmissionGuid $Target.dispatchId);nativeThreadId=$null;role=$Target.role;resultPath=$Target.resultPath;jobPath=$null;payloadHash=$Target.payloadHash;dispatchJournalPath=$Target.dispatchJournalPath;parentJobPath=$Target.parentJobPath;parentContextPath=$Target.parentContextPath;parentContextHash=$Target.parentContextHash;startIntentPath=$Target.startIntentPath;startIntentHash=$Target.startIntentHash;state='reserved';createdAt=[DateTime]::UtcNow.ToString('o');terminalAt=$null;inventoryAbsentAt=$null;admission=@{requestHash=$RequestHash;scopeHash=$scope.Hash;targetHash=$request.targetHash;revision=($revision+1);consumedBy=$request.targetHash;rootJobPath=$scope.RootJobPath;logicalSessionId=$scope.LogicalSessionId}}
    if($Target.startIntentPath){
        $authorityBytes=[IO.File]::ReadAllBytes($Target.startIntentPath)
        if((Get-AdmissionHash $authorityBytes) -cne $Target.startIntentHash){throw 'AdmissionAuthorityChangedBeforeReserve'}
        $authority=ConvertFrom-Json -InputObject $script:AdmissionUtf8.GetString($authorityBytes) -ErrorAction Stop
        $entry|Add-Member -NotePropertyName workItemId -NotePropertyValue (Get-AdmissionField $authority.parameters 'WorkItemId')
    }
    $bytesHash=Write-AdmissionJson $file @($Entries+$entry) # leading durable commit
    [void](Get-AdmissionRemainingMilliseconds $Budget) # late write is ambiguous, reservation retained
    [void](Write-AdmissionJson $metaPath @{mutationRevision=($revision+1);inFlight=@{hash=$RequestHash;state='Consumed';consumedBy=$request.targetHash};committedRegistryHash=$bytesHash;snapshotReuse=$false})
    $entry|Add-Member -NotePropertyName Reused -NotePropertyValue $false;$entry
}
function Get-AdmissionInstalledContract($Provider) {
    # Static readback artifact supplies installation hashes; API knowledge must be code-reviewed.
    $manifestPath=Join-Path $PSScriptRoot 'AdmissionInstalledContract.json';$manifestBytes=[IO.File]::ReadAllBytes($manifestPath);$manifest=Read-AdmissionJson $manifestPath
    $errors=[Collections.Generic.List[string]]::new()
    foreach($p in @($manifest.files)){if(-not [IO.File]::Exists($p.path) -or (Get-AdmissionHash ([IO.File]::ReadAllBytes($p.path))) -cne $p.sha256){$errors.Add('InstalledSourceOrBinaryChanged')}}
    if($Provider.executable -cne $manifest.binaryPath -or $Provider.executableHash -cne $manifest.binaryHash -or $Provider.version -cne $manifest.version){$errors.Add('EffectiveBinaryVersionUnbound')}
    if(-not $Provider.installationContractHash -or $Provider.installationContractHash -cne (Get-AdmissionHash $manifestBytes)){$errors.Add('EffectiveInstallationContractUnbound')}
    $api=$null
    $sourceCommit='092d3acd6bec3e3a14bdc7e7a2810ab628ab759d'
    $sourceHashes=[ordered]@{thread='553d99d01eed0c7a9073f481938f7dd68ef633879be0e1ffd8373778c937b158';common='e25ebb90bf79be79def79ebf2dd704057577fa9806710fbea0ee240a909d0dc1';protocol='499bd1fd429418778d26998c48da2a5a22fe2965f4684e69fdf99e6b4c7e4330'}
    if(-not $errors.Count -and $manifest.version -ceq '0.162.1' -and $manifest.binaryPath -ceq 'C:\nvm4w\nodejs\node_modules\@openai\codex\node_modules\@openai\codex-win32-x64\vendor\x86_64-pc-windows-msvc\bin\codex.exe' -and $manifest.binaryHash -ceq 'dd13bdb162a184fa04039488b234a8258ef9b76f84e926c505d5742b19249a6a'){
        $api=[pscustomobject]@{threadList='thread/list';threadLoadedList='thread/loaded/list';threadRead='thread/read';loadedIdsField='data';sourceKinds=@($script:AdmissionAllSources);threadReadIncludeTurns=$false;sourceCommit=$sourceCommit;sourceHashes=$sourceHashes}
    }
    # Read capability is source-pinned; completion and native birth fencing are
    # separate contracts and remain unknown even when metadata reads are usable.
    $errors.Add('AtomicProviderCompletionMissing');$errors.Add('NativeBirthFenceMissing')
    [pscustomobject]@{version=$manifest.version;api=$api;completionMode='Unknown';sourceCommit=$(if($api){$sourceCommit}else{$null});sourceHashes=$(if($api){$sourceHashes}else{$null});missing=@($errors.ToArray())}
}
function New-AdmissionProviderReceipt($Process,[string]$JobPath,[string]$RootJobPath,[string]$SessionPath,[string]$Executable,[string[]]$Arguments,[string]$CodexHome,$InitializeReply,[string]$Kind='cli') {
    $job=Read-AdmissionJson $JobPath;$session=Read-AdmissionJson $SessionPath;$manifest=Read-AdmissionJson (Join-Path $PSScriptRoot 'AdmissionInstalledContract.json')
    $started=$Process.StartTime.ToUniversalTime().ToString('o');$origin=[IO.Path]::GetFullPath($JobPath)
    $r=[ordered]@{kind=$Kind;origin=$origin;rootJobPath=[IO.Path]::GetFullPath($RootJobPath);sessionPath=[IO.Path]::GetFullPath($SessionPath);logicalSessionId=$session.LogicalSessionId;taskId=$job.task_id;processId=$Process.Id;processStartedUtc=$started;generation=($Process.Id.ToString()+'@'+$started);executable=[IO.Path]::GetFullPath($Executable);executableHash=(Get-AdmissionHash ([IO.File]::ReadAllBytes($Executable)));arguments=@($Arguments);codexHome=[IO.Path]::GetFullPath($CodexHome);version=$manifest.version;installationContractHash=(Get-AdmissionHash ([IO.File]::ReadAllBytes((Join-Path $PSScriptRoot 'AdmissionInstalledContract.json'))));initializeReply=$InitializeReply;initializeReplyHash=(Get-AdmissionObjectHash $InitializeReply)}
    $path=Join-Path ($origin+'.inventory') ((Get-AdmissionObjectHash $r)+'.connection.json');$hash=Write-AdmissionJson $path $r -Immutable
    [pscustomobject]@{receiptPath=$path;receiptHash=$hash;receipt=[pscustomobject]$r}
}
function Add-AdmissionRpcReceipt($Receipts,[string]$Method,$Provider,[scriptblock]$Markers) {
    $markersValue=& $Markers;$wire=Get-AdmissionField $markersValue 'rpc'
    if(-not $wire -or $wire.method -cne $Method -or -not $wire.requestBytesHash -or -not $wire.replyBytesHash -or -not $wire.requestBase64 -or -not $wire.replyBase64){throw 'ActualReaderRpcByteReceiptMissing'}
    if((Get-AdmissionHash ([Convert]::FromBase64String($wire.requestBase64))) -cne $wire.requestBytesHash -or (Get-AdmissionHash ([Convert]::FromBase64String($wire.replyBase64))) -cne $wire.replyBytesHash){throw 'ActualReaderRpcByteReceiptConflict'}
    [void]$Receipts.Add(@{kind='actual-rpc-wire';method=$Method;generation=$Provider.generation;origin=$Provider.origin;wire=$wire})
}
function Invoke-AdmissionProviderCollection {
    param($Envelope,$Provider,$Budget,[scriptblock]$Rpc,[scriptblock]$Markers)
    $before=& $Markers;$receipts=[Collections.ArrayList]::new();$observations=[Collections.ArrayList]::new();$errors=[Collections.Generic.List[string]]::new();$completion='Incomplete'
    try{
        $contract=Get-AdmissionInstalledContract $Provider
        if(-not $contract.api){throw ('MissingExternalAccess:'+($contract.missing -join ','))}
        $api=$contract.api
        if((Get-AdmissionObjectHash @($api.sourceKinds|Sort-Object)) -cne (Get-AdmissionObjectHash @($script:AdmissionAllSources|Sort-Object))){throw 'VersionBoundAllSourceEnumIncomplete'}
        $ids=@{};$catalogRecords=@{};foreach($t in @($Envelope.Request.boundThreads)) {if($t.origin -ceq $Provider.origin -and $t.generation -ceq $Provider.generation -and $t.id){$ids[[string]$t.id]=$true}}
        foreach($archived in @($false,$true)){
            $cursor=$null;$seen=@{}
            do{
                $params=@{limit=100;archived=$archived;sortKey='updated_at';modelProviders=@();sourceKinds=@($script:AdmissionAllSources);useStateDbOnly=$true};if($null -ne $cursor){$params.cursor=$cursor}
                $start=[DateTime]::UtcNow.ToString('o');$page=& $Rpc 'thread/list' $params (Get-AdmissionRemainingMilliseconds $Budget)
                Add-AdmissionRpcReceipt $receipts 'thread/list' $Provider $Markers
                [void](Get-AdmissionRemainingMilliseconds $Budget)
                if(-not $page.PSObject.Properties['data'] -or -not $page.PSObject.Properties['nextCursor']){throw 'ThreadListPageFieldsMissing'}
                [void]$receipts.Add(@{method='thread/list';request=$params;requestHash=(Get-AdmissionObjectHash $params);reply=$page;replyHash=(Get-AdmissionObjectHash $page);startedUtc=$start;endedUtc=[DateTime]::UtcNow.ToString('o');generation=$Provider.generation})
                foreach($t in @($page.data)){
                    if(-not $t.id){throw 'ThreadCatalogIdMissing'}
                    $id=[string]$t.id;$fingerprint=Get-AdmissionObjectHash $t
                    if($catalogRecords.ContainsKey($id) -and $catalogRecords[$id] -cne $fingerprint){throw 'ThreadListPaginationRecordConflict'}
                    $catalogRecords[$id]=$fingerprint # Catalog presence never enrolls foreign threads.
                }
                $cursor=$page.nextCursor;if($null -ne $cursor){if(-not [string]$cursor -or $seen.ContainsKey([string]$cursor)){throw 'ThreadListCursorCycle'};$seen[[string]$cursor]=$true}
            }while($null -ne $cursor)
        }
        $cursor=$null;$seenLoaded=@{}
        do{
            $params=@{};if($null -ne $cursor){$params.cursor=$cursor}
            $loaded=& $Rpc 'thread/loaded/list' $params (Get-AdmissionRemainingMilliseconds $Budget)
            Add-AdmissionRpcReceipt $receipts 'thread/loaded/list' $Provider $Markers
            if(-not $loaded.PSObject.Properties[$api.loadedIdsField] -or -not $loaded.PSObject.Properties['nextCursor']){throw 'LoadedThreadIdsOrCursorMissing'}
            foreach($id in @($loaded.($api.loadedIdsField))){if(-not $id){throw 'LoadedThreadIdMissing'}}
            [void]$receipts.Add(@{method='thread/loaded/list';request=$params;requestHash=(Get-AdmissionObjectHash $params);reply=$loaded;replyHash=(Get-AdmissionObjectHash $loaded);generation=$Provider.generation})
            $cursor=$loaded.nextCursor;if($null -ne $cursor){if(-not [string]$cursor -or $seenLoaded.ContainsKey([string]$cursor)){throw 'LoadedThreadCursorCycle'};$seenLoaded[[string]$cursor]=$true}
        }while($null -ne $cursor)
        foreach($id in @($ids.Keys)){
            $params=@{threadId=$id;includeTurns=[bool]$api.threadReadIncludeTurns};$read=& $Rpc 'thread/read' $params (Get-AdmissionRemainingMilliseconds $Budget)
            Add-AdmissionRpcReceipt $receipts 'thread/read' $Provider $Markers
            if($read.thread.id -cne $id -or -not $read.thread.status.type){throw 'ThreadReadIdentityOrStatusMissing'}
            [void]$receipts.Add(@{method='thread/read';request=$params;requestHash=(Get-AdmissionObjectHash $params);reply=$read;replyHash=(Get-AdmissionObjectHash $read);generation=$Provider.generation})
            [void]$observations.Add(@{threadId=$id;status=$read.thread.status.type;origin=$Provider.origin;generation=$Provider.generation})
        }
        $completion='BothArchivedAndLoadedAndRead'
        if($contract.completionMode -eq 'Unknown'){$errors.Add('MissingExternalAccess:ProviderCompletionAndNativeBirthFence')}
    }catch{$errors.Add($_.Exception.Message)}
    $after=& $Markers
    if($before.mutation -ne $after.mutation -or $before.gap -ne $after.gap){$errors.Add('NotificationMutationOrGap')}
    [pscustomobject]@{kind='admission-answer-v1';requestHash=$Envelope.Hash;scopeHash=$Envelope.Request.scope.Hash;origin=$Provider.origin;providerHash=(Get-AdmissionObjectHash $Provider);generation=$Provider.generation;pageCompletion=$completion;receipts=@($receipts);observations=@($observations);mutationBefore=$before.mutation;mutationAfter=$after.mutation;gapBefore=$before.gap;gapAfter=$after.gap;errors=@($errors.ToArray());completedUtc=[DateTime]::UtcNow.ToString('o')}
}
function Invoke-AdmissionCallerPump {
    param([string]$Directory,$Provider,$Budget,[scriptblock]$Rpc,[scriptblock]$Markers,[bool]$Busy=$false,[string]$LocallyOwnedDiagnosticRequestHash)
    $path=Join-Path $Directory 'execution-inventory.json';if(-not [IO.File]::Exists($path)){return}
    $meta=Read-AdmissionJson $path;$pending=Get-AdmissionField $meta 'inFlight';if((Get-AdmissionField $pending 'state') -cne 'Collecting'){return}
    $request=Get-AdmissionField $pending 'request';$hash=[string](Get-AdmissionField $pending 'hash')
    if(-not $hash -or (Get-AdmissionObjectHash $request) -cne $hash){throw 'CallerAdmissionRequestHashMismatch'}
    $bound=@($request.scope.Providers|Where-Object{$_.origin -ceq $Provider.origin -and $_.generation -ceq $Provider.generation})
    if($bound.Count -ne 1){return} # not this reader's request; host cannot read its stdio
    $provider=$bound[0];$answerPath=Join-Path ($provider.origin+'.inventory') ($hash+'.answer.json')
    if([IO.File]::Exists($answerPath)){return} # immutable answer for this request; never reused by a different request
    $expires=[DateTimeOffset]::Parse([string]$request.expiresUtc).UtcDateTime
    $started=[DateTimeOffset]::Parse([string]$request.startedUtc).UtcDateTime
    $now=[DateTime]::UtcNow
    if($now -lt $started -or $now -ge $expires){throw 'AdmissionUnknown: CallerRequestExpiredOrClockRollback'}
    $local=New-AdmissionBudget ([int][Math]::Min((Get-AdmissionRemainingMilliseconds $Budget),[Math]::Min([int]$request.remainingMilliseconds,($expires-$now).TotalMilliseconds)))
    if($Busy){if($LocallyOwnedDiagnosticRequestHash -ceq $hash){return};$answer=@{requestHash=$hash;scopeHash=$request.scope.Hash;providerHash=(Get-AdmissionObjectHash $provider);origin=$provider.origin;generation=$provider.generation;pageCompletion='Incomplete';errors=@('ReaderBusyNoSafeReentrantCollection')}}
    else{$envlp=[pscustomobject]@{Hash=$hash;Request=$request};$answer=Invoke-AdmissionProviderCollection $envlp $provider $local $Rpc $Markers}
    [void](Write-AdmissionJson $answerPath $answer -Immutable)
}
function Invoke-AdmissionReadDiagnostics {
    param([string]$Directory,[string]$RootJobPath,[string]$SessionPath,[string]$RegistryScript,$Provider,[int]$BudgetMilliseconds,[scriptblock]$Rpc,[scriptblock]$Markers,[scriptblock]$SetLocalOwnership)
    $budget=New-AdmissionBudget $BudgetMilliseconds;$envelope=$null
    try{
        $envelope=& $RegistryScript -Action BeginAdmission -DataDirectory $Directory -RootJobPath $RootJobPath -SessionPath $SessionPath -TargetJson 'null' -AdmissionBudget $budget
        $bound=@($envelope.Request.scope.Providers|Where-Object{$_.origin -ceq $Provider.origin -and $_.generation -ceq $Provider.generation})
        if($bound.Count -ne 1){throw 'AdmissionDiagnosticProviderNotBound'}
        if($SetLocalOwnership){& $SetLocalOwnership ([string]$envelope.Hash)}
        $answerPath=Join-Path ($Provider.origin+'.inventory') ($envelope.Hash+'.answer.json')
        if(-not [IO.File]::Exists($answerPath)){
            $answer=Invoke-AdmissionProviderCollection ([pscustomobject]@{Hash=$envelope.Hash;Request=$envelope.Request}) $bound[0] $budget $Rpc $Markers
            [void](Write-AdmissionJson $answerPath $answer -Immutable)
        }
    }catch{
        # Read diagnostics never authorize work; retain any already written
        # answer/observations and let the caller's normal gate report unknown.
        return $_.Exception.Message
    }finally{
        if($SetLocalOwnership){try{& $SetLocalOwnership $null}catch{}}
        if($envelope){try{& $RegistryScript -Action InvalidateAdmission -DataDirectory $Directory -AdmissionRequestHash $envelope.Hash -TargetJson (ConvertTo-Json -InputObject @{reason='ReadDiagnosticsCompleteNoGrant'} -Compress) -AdmissionBudget (New-AdmissionBudget 1000)|Out-Null}catch{}}
    }
}
function Invoke-CoordinatorAdmission {
    param($Runtime,$Session,[string]$SessionPath,$Target,[string]$RegistryScript,[int]$CallerRemainingMilliseconds=2147483647,[Parameter(Mandatory=$true)][scriptblock]$HostRpc,[Parameter(Mandatory=$true)][scriptblock]$HostMarkers)
    $budget=New-AdmissionBudget $CallerRemainingMilliseconds
    $root=Read-AdmissionJson $Session.CoordinatorJobPath;$launch=Read-AdmissionJson $root.coordinator_launch.inputPath
    $policy=Get-AdmissionField $launch 'admissionPolicy';$budget.Limit=[int][Math]::Min($CallerRemainingMilliseconds,[int](Get-AdmissionField $policy 'scanBudgetMilliseconds' 10000));$envlp=$null
    & $RegistryScript -Action ReserveManaged -DataDirectory $launch.registryDirectory -RootJobPath $Session.CoordinatorJobPath -SessionPath $SessionPath -TargetJson (ConvertTo-Json -InputObject $Target -Depth 50 -Compress) -AdmissionBudget $budget

}
function Request-CoordinatorAdmission([string]$RootJobPath,$Target,[int]$BudgetMilliseconds=10000) {
    $budget=New-AdmissionBudget $BudgetMilliseconds;$root=Read-AdmissionJson $RootJobPath;$dir=[IO.Path]::GetFullPath($root.coordinator_data_directory)
    $session=Read-AdmissionJson (Join-Path $dir 'session.json');if(-not $session.LogicalSessionId){throw 'AdmissionUnknown: HostSessionMissing'}
    $name='agent-coordinator-'+([Convert]::ToBase64String([Security.Cryptography.SHA256]::Create().ComputeHash([Text.Encoding]::UTF8.GetBytes($dir))).TrimEnd('=').Replace('+','_').Replace('/','_').Substring(0,24))
    $writer=$null;$reader=$null
    $pipe=[IO.Pipes.NamedPipeClientStream]::new('.',$name,[IO.Pipes.PipeDirection]::InOut,[IO.Pipes.PipeOptions]::Asynchronous)
    try{
        $pipe.Connect((Get-AdmissionRemainingMilliseconds $budget));$reader=[IO.StreamReader]::new($pipe,$script:AdmissionUtf8,$false,4096,$true);$writer=[IO.StreamWriter]::new($pipe,$script:AdmissionUtf8,4096,$true);$writer.AutoFlush=$true
        $writer.WriteLine((ConvertTo-Json -InputObject @{operation='AdmissionRequest';logicalSessionId=$session.LogicalSessionId;target=$Target;budgetMilliseconds=(Get-AdmissionRemainingMilliseconds $budget)} -Depth 50 -Compress))
        $read=$reader.ReadLineAsync();if(-not $read.Wait((Get-AdmissionRemainingMilliseconds $budget))){throw 'AdmissionUnknown: SerializedHostAdmissionTimeout'}
        $reply=ConvertFrom-Json -InputObject $read.Result -ErrorAction Stop;[void](Get-AdmissionRemainingMilliseconds $budget)
        if($reply.status -cne 'Reserved' -or -not $reply.reservation.admission.requestHash){throw ('AdmissionUnknown: '+$reply.reason)};$reply.reservation
    }finally{if($writer){$writer.Dispose()};if($reader){$reader.Dispose()};$pipe.Dispose()}
}
Export-ModuleMember -Function Resume-ManagedSpecialistWaits,Get-ManagedChildHeadroom,Save-ManagedTurnCompletion,Begin-ManagedOperation,Complete-ManagedOperation,Assert-ManagedRelease,Publish-ManagedReleaseWake,Get-AdmissionField,Get-AdmissionHash,Get-AdmissionObjectHash,Read-AdmissionJson,Write-AdmissionJson,New-AdmissionBudget,Get-AdmissionRemainingMilliseconds,Get-AdmissionGuid,Get-AdmissionCount,Get-AdmissionRoot,Get-AdmissionScope,Invoke-AdmissionRegistryLocked,Get-AdmissionInstalledContract,New-AdmissionProviderReceipt,Invoke-AdmissionProviderCollection,Invoke-AdmissionCallerPump,Invoke-AdmissionReadDiagnostics,Invoke-CoordinatorAdmission,Request-CoordinatorAdmission
