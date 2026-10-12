Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Get-PlanningValue($Object,[string]$Name,$Default=$null) {
    if($null -eq $Object){return $Default}
    $property=$Object.PSObject.Properties[$Name]
    if($property){return $property.Value}
    return $Default
}

function Get-CoordinatorPlanningDecision {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][object[]]$WorkItems,
        [Parameter(Mandatory=$true)][ValidateRange(1,100)][int]$Capacity,
        [object[]]$ActiveExecutions = @(),
        [string[]]$WakeEventIds = @(),
        [string]$StateDirectory,
        [DateTime]$NowUtc = [DateTime]::UtcNow
    )
    $items = @($WorkItems); $byId = @{}
    foreach ($item in $items) {
        $id = [string]$item.id
        if (-not $id -or $byId.ContainsKey($id)) { throw 'InvalidOrDuplicateWorkItemId' }
        $byId[$id] = $item
    }
    $executions = @{}; $executionAliases=@{}; $unknown = $false
    foreach ($entry in @($ActiveExecutions)) {
        if (-not $entry -or -not $entry.executionId -or $entry.state -eq 'unknown') { $unknown=$true; continue }
        $aliases=@([string]$entry.executionId); if($entry.taskId){$aliases+='task:'+[string]$entry.taskId};if($entry.nativeThreadId){$aliases+='thread:'+[string]$entry.nativeThreadId}
        $canonical=$null;foreach($alias in $aliases){if($executionAliases.ContainsKey($alias)){$canonical=$executionAliases[$alias];break}};if(-not $canonical){$canonical=[string]$entry.executionId;$executions[$canonical]=$true};foreach($alias in $aliases){$executionAliases[$alias]=$canonical}
    }
    if ($unknown) { $available=0 } else { $available=[Math]::Max(0,$Capacity-$executions.Count) }
    $wakeSet=@{}; foreach($id in $WakeEventIds){$wakeSet[[string]$id]=$true}
    $ready=@(); $waiting=@()
    foreach($item in $items){
        if ($item.status -notin @('planned','rework')) { continue }
        $root=$item; $parent=$item; $valid=$true
        while((Get-PlanningValue $parent 'parentId')){
            $pid=[string](Get-PlanningValue $parent 'parentId')
            if(-not $byId.ContainsKey($pid)){ $valid=$false; break }
            $parent=$byId[$pid]; $root=$parent
            if($parent.status -in @('blocked','cancelled','accepted','completed')){$valid=$false;break}
        }
        if(-not $valid){continue}
        $rootInteraction=Get-PlanningValue $root 'humanInteraction';$humanBlocked=($rootInteraction -and $rootInteraction.status -eq 'pending')
        $dueProp=$item.PSObject.Properties['dueAt']; $due=$null
        if($dueProp -and $dueProp.Value){$due=[DateTimeOffset]::Parse([string]$dueProp.Value).UtcDateTime;if($due -gt $NowUtc.ToUniversalTime()){$waiting += [pscustomobject]@{item=$item;reason='due';wake=$due};continue}}
        if($humanBlocked){$waiting += [pscustomobject]@{item=$item;reason='human-response';wake=$null};continue}
        $deps=@(Get-PlanningValue $item 'dependencies' @()); $depsReady=$true
        foreach($dep in $deps){if(-not $byId.ContainsKey([string]$dep) -or $byId[[string]$dep].status -ne 'accepted'){$depsReady=$false;break}}
        if(-not $depsReady){$waiting += [pscustomobject]@{item=$item;reason='dependency';wake=$null};continue}
        if((Get-PlanningValue $item 'blockReason') -and -not $wakeSet.ContainsKey([string]$item.id)){$waiting += [pscustomobject]@{item=$item;reason='event';wake=$null};continue}
        $ready += $item
    }
    $rank=@{urgent=0;high=1;normal=2;low=3}
    $ordered=@($ready | Sort-Object @{Expression={$p=[string](Get-PlanningValue $_ 'priority');if($rank.ContainsKey($p)){$rank[$p]}else{4}}},@{Expression={[string]$_.id}})
    # Stable round-robin among roots within each priority band prevents one root
    # with many ready children from monopolizing the available slots.
    $fair=@(); foreach($band in 0..4){$bandItems=@($ordered | Where-Object { $p=[string](Get-PlanningValue $_ 'priority'); $n=if($rank.ContainsKey($p)){$rank[$p]}else{4}; $n -eq $band }); $groups=@{}; foreach($x in $bandItems){$r=$x;while((Get-PlanningValue $r 'parentId') -and $byId.ContainsKey([string](Get-PlanningValue $r 'parentId'))){$r=$byId[[string](Get-PlanningValue $r 'parentId')]};$k=[string]$r.id;if(-not $groups.ContainsKey($k)){$groups[$k]=[System.Collections.Generic.Queue[object]]::new()};$groups[$k].Enqueue($x)}; $keys=@($groups.Keys | Sort-Object); do{$progress=$false;foreach($k in $keys){if($groups[$k].Count){$fair += $groups[$k].Dequeue();$progress=$true}}}while($progress)}
    $selected=@($fair | Select-Object -First $available)
    if($StateDirectory){
        [void][IO.Directory]::CreateDirectory($StateDirectory)
        $sidecar=Join-Path $StateDirectory 'planning-waiting.json'
        $reminderPath=Join-Path $StateDirectory 'planning-reminders.json';$reminders=@{}
        if(Test-Path -LiteralPath $reminderPath){try{$old=([IO.File]::ReadAllText($reminderPath,[Text.Encoding]::UTF8)|ConvertFrom-Json);foreach($p in $old.PSObject.Properties){$reminders[$p.Name]=$p.Value}}catch{throw 'PlanningReminderStateUnreadable; reminders fail closed'}}
        $dueReminders=@();$eventDirectory=Join-Path $StateDirectory 'planning-wake-events';foreach($item in $items){$root=$item;while((Get-PlanningValue $root 'parentId') -and $byId.ContainsKey([string](Get-PlanningValue $root 'parentId'))){$root=$byId[[string](Get-PlanningValue $root 'parentId')]};$interaction=Get-PlanningValue $root 'humanInteraction';$due=Get-PlanningValue $item 'dueAt';if($interaction -and $interaction.status -eq 'pending' -and $due -and [DateTimeOffset]::Parse([string]$due).UtcDateTime -le $NowUtc.ToUniversalTime()){$generation=[string](Get-PlanningValue $item 'revision' '0');$key=[string]$item.id+':'+$generation+':'+[string]$due;$eventId='reminder-'+$key;$eventFile=Join-Path $eventDirectory ($eventId -replace '[^a-zA-Z0-9_.-]','_')+'.json';if(-not $reminders.ContainsKey($key) -and -not (Test-Path -LiteralPath $eventFile)){$reminders[$key]=$NowUtc.ToUniversalTime().ToString('o');$dueReminders += [ordered]@{eventId=$eventId;workItemId=[string]$item.id;generation=$generation;dueAt=[string]$due;createdAt=$NowUtc.ToUniversalTime().ToString('o')}}}}
        if($dueReminders.Count){$eventDirectory=Join-Path $StateDirectory 'planning-wake-events';[void][IO.Directory]::CreateDirectory($eventDirectory);foreach($event in $dueReminders){$bytes=[Text.UTF8Encoding]::new($false).GetBytes((ConvertTo-Json -InputObject $event -Compress));$eventFile=Join-Path $eventDirectory ($event.eventId -replace '[^a-zA-Z0-9_.-]','_')+'.json';try{$stream=[IO.File]::Open($eventFile,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::None);try{$stream.Write($bytes,0,$bytes.Length);$stream.Flush($true)}finally{$stream.Dispose()}}catch [IO.IOException]{} };$rt=$reminderPath+'.tmp';[IO.File]::WriteAllText($rt,($reminders|ConvertTo-Json -Depth 5),[Text.UTF8Encoding]::new($false));[IO.File]::Move($rt,$reminderPath,$true)}
        $state=[ordered]@{updatedAt=$NowUtc.ToUniversalTime().ToString('o');items=@($waiting | ForEach-Object {[ordered]@{workItemId=[string]$_.item.id;reason=$_.reason;wakeAt=$(if($_.wake){$_.wake.ToString('o')}else{$null})}});selected=@($selected|ForEach-Object{[string]$_.id});availableSlots=$available;capacityUnknown=$unknown;wakeEvents=$dueReminders}
        $tmp=$sidecar+'.tmp';[IO.File]::WriteAllText($tmp,($state|ConvertTo-Json -Depth 8),[Text.UTF8Encoding]::new($false));[IO.File]::Move($tmp,$sidecar,$true)
    }
    return [pscustomobject]@{Capacity=$Capacity;ActiveExecutions=$executions.Count;AvailableSlots=$available;CapacityUnknown=$unknown;ReadyWorkItemIds=@($fair|ForEach-Object{[string]$_.id});SelectedWorkItemIds=@($selected|ForEach-Object{[string]$_.id});WaitingWorkItemIds=@($waiting|ForEach-Object{[string]$_.item.id});NextWakeUtc=$(($waiting|Where-Object{$_.wake}|Sort-Object wake|Select-Object -First 1).wake)}
}
function Get-CoordinatorReadyWork { [CmdletBinding()] param([Parameter(Mandatory=$true)][object[]]$WorkItems,[Parameter(Mandatory=$true)][ValidateRange(1,100)][int]$Capacity,[object[]]$ActiveExecutions=@(),[string[]]$WakeEventIds=@(),[string]$StateDirectory); Get-CoordinatorPlanningDecision @PSBoundParameters }
Export-ModuleMember -Function Get-CoordinatorPlanningDecision,Get-CoordinatorReadyWork
