. (Join-Path $PSScriptRoot 'Lifecycle.Persistence.ps1')
. (Join-Path $PSScriptRoot '..\workitems\HumanInteraction.ps1')
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'CoordinatorAdmission.psm1') -Force

function Get-PlanningValue($Object,[string]$Name,$Default=$null) {
    if($null -eq $Object){return $Default}
    if($Object -is [Collections.IDictionary]){if($Object.Contains($Name)){return $Object[$Name]};return $Default}
    $property=$Object.PSObject.Properties[$Name]
    if($property){return $property.Value}
    return $Default
}

function Get-PlanningRoot($Item,$ById) {
    $root=$Item;$seen=@{}
    while($root){
        $id=[string]$root.id
        if($seen.ContainsKey($id)){throw ('PlanningParentCycle:'+ $id)}
        $seen[$id]=$true
        $parentId=[string](Get-PlanningValue $root 'parentId')
        if(-not $parentId){return $root}
        if(-not $ById.ContainsKey($parentId)){return $null}
        $root=$ById[$parentId]
    }
}

function Get-CoordinatorPlanningDecision {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][object[]]$WorkItems,
        [Parameter(Mandatory=$true)][ValidateRange(1,100)][int]$Capacity,
        [object[]]$ActiveExecutions = @(),
        [string[]]$WakeEventIds = @(),
        [string[]]$ResumeRequiredWorkItemIds = @(),
        [Collections.IDictionary]$ResumeAssessments = @{},
        [Collections.IDictionary]$TeamCapacities = @{},
        [string]$StateDirectory,
        [DateTime]$NowUtc = [DateTime]::UtcNow
    )
    $items = @($WorkItems); $byId = @{}
    foreach ($item in $items) {
        $id = [string]$item.id
        if (-not $id -or $byId.ContainsKey($id)) { throw 'InvalidOrDuplicateWorkItemId' }
        $byId[$id] = $item
    }
    $admissionCount=Get-AdmissionCount @($ActiveExecutions)
    $unknown=$admissionCount.CapacityUnknown
    if($unknown){$available=0}else{$available=[Math]::Max(0,$Capacity-$admissionCount.Count)}
    $wakeSet=@{}; foreach($id in $WakeEventIds){$wakeSet[[string]$id]=$true}
    $roots=@{};foreach($item in $items){$roots[[string]$item.id]=Get-PlanningRoot $item $byId}
    $teamActive=$admissionCount.RoleCounts
    foreach($role in $TeamCapacities.Keys){$limit=[int]$TeamCapacities[$role];if($role -notmatch '^teamleiter_[a-z][a-z0-9_]*$' -or $limit -lt 1 -or $limit -gt $Capacity){throw 'PlanningTeamCapacityInvalid'}}
    $activeIds=@{};foreach($workId in $admissionCount.WorkItemIds){$activeIds[[string]$workId]=$true}
    $ready=@(); $waiting=@()
    foreach($item in $items){
        if($item.status -ceq 'blocked'){
            $due=Get-PlanningValue $item 'dueAt';$wake=$null
            if($due -and (Test-HISatisfied (Get-PlanningValue $item 'humanInteraction'))){$wake=[DateTimeOffset]::Parse([string]$due).UtcDateTime}
            $waiting += [pscustomobject]@{item=$item;reason='blocked';wake=$wake};continue
        }
        if ($item.status -notin @('planned','rework','in_progress')) { continue }
        if($activeIds.ContainsKey([string]$item.id)){$waiting += [pscustomobject]@{item=$item;reason='active-execution';wake=$null};continue}
        if ((Get-PlanningValue (Get-PlanningValue $item 'owner') 'type') -ceq 'human') { $waiting += [pscustomobject]@{item=$item;reason='human-owner';wake=$null}; continue }
        $owner=Get-PlanningValue $item 'owner';$role=[string](Get-PlanningValue $owner 'id')
        if((Get-PlanningValue $owner 'type') -cne 'agent' -or $role -notmatch '^teamleiter_[a-z][a-z0-9_]*$'){$waiting += [pscustomobject]@{item=$item;reason='coordinator-disposition';wake=$null};continue}
        if($item.status -ceq 'in_progress' -and $ResumeRequiredWorkItemIds -cnotcontains [string]$item.id){continue}
        if($ResumeRequiredWorkItemIds -ccontains [string]$item.id -and (-not $ResumeAssessments.Contains([string]$item.id) -or -not $ResumeAssessments[[string]$item.id])){$waiting+=[pscustomobject]@{item=$item;reason='resume-receipt';wake=$null};continue}
        $root=$roots[[string]$item.id]; $parent=$item; $valid=($null -ne $root)
        while((Get-PlanningValue $parent 'parentId')){
            $pid=[string](Get-PlanningValue $parent 'parentId')
            if(-not $byId.ContainsKey($pid)){ $valid=$false; break }
            $parent=$byId[$pid]; $root=$parent
            if($parent.status -in @('cancelled','accepted','completed') -or ($parent.status -ceq 'blocked' -and -not (Test-HIOnlyWaiting $parent))){$valid=$false;break}
        }
        if(-not $valid){continue}
        # Human waiting belongs to the affected item; dependencies bind follow-up work.
        # A shared parent alone must not stop independent siblings.
        $rootInteraction=Get-PlanningValue $item 'humanInteraction';$humanBlocked= -not (Test-HISatisfied $rootInteraction)
        if($humanBlocked){$waiting += [pscustomobject]@{item=$item;reason='human-response';wake=$null};continue}
        $dueProp=$item.PSObject.Properties['dueAt']; $due=$null
        if($dueProp -and $dueProp.Value){$due=[DateTimeOffset]::Parse([string]$dueProp.Value).UtcDateTime;if($due -gt $NowUtc.ToUniversalTime()){$waiting += [pscustomobject]@{item=$item;reason='due';wake=$due};continue}}
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
    $cursorPath=if($StateDirectory){Join-Path $StateDirectory 'planning-root-cursors.json'}else{$null};$cursors=@{};if($cursorPath -and (Test-Path -LiteralPath $cursorPath)){try{$oldCursor=([IO.File]::ReadAllText($cursorPath,[Text.Encoding]::UTF8)|ConvertFrom-Json);foreach($p in $oldCursor.PSObject.Properties){$cursors[$p.Name]=[string]$p.Value}}catch{throw 'PlanningRootCursorUnreadable'}}
    $fair=@(); foreach($band in 0..4){$bandItems=@($ordered | Where-Object { $p=[string](Get-PlanningValue $_ 'priority'); $n=if($rank.ContainsKey($p)){$rank[$p]}else{4}; $n -eq $band }); $groups=@{}; foreach($x in $bandItems){$r=$roots[[string]$x.id];$k=[string]$r.id;if(-not $groups.ContainsKey($k)){$groups[$k]=[System.Collections.Generic.Queue[object]]::new()};$groups[$k].Enqueue($x)}; $keys=@($groups.Keys | Sort-Object);if($keys.Count -and $cursors.ContainsKey([string]$band)){$last=[array]::IndexOf($keys,$cursors[[string]$band]);if($last -ge 0 -and $keys.Count -gt 1){$tail=@();if($last -lt $keys.Count - 1){$tail=@($keys[($last+1)..($keys.Count-1)])};$keys=$tail+@($keys[0..$last])}}; do{$progress=$false;foreach($k in $keys){if($groups[$k].Count){$fair += $groups[$k].Dequeue();$progress=$true}}}while($progress)}
    $selected=@();$teamSelected=@{};$teamWaiting=@{}
    foreach($item in $fair){
        $role=[string](Get-PlanningValue (Get-PlanningValue $item 'owner') 'id')
        $limit=if($TeamCapacities.Contains($role)){[int]$TeamCapacities[$role]}else{$Capacity}
        $used=if($teamActive.ContainsKey($role)){[int]$teamActive[$role]}else{0}
        $reserved=if($teamSelected.ContainsKey($role)){[int]$teamSelected[$role]}else{0}
        if($used+$reserved -ge $limit){$teamWaiting[[string]$item.id]=$true;continue}
        if($selected.Count -ge $available){continue}
        $selected+=$item;$teamSelected[$role]=$reserved+1
    }
    $selectedIds=@{};foreach($item in $selected){$selectedIds[[string]$item.id]=$true}
    foreach($item in $fair){
        if(-not $selectedIds.ContainsKey([string]$item.id)){
            $waiting += [pscustomobject]@{item=$item;reason=$(if($unknown){'capacity-unknown'}elseif($teamWaiting.ContainsKey([string]$item.id)){'team-capacity'}else{'capacity'});wake=$null}
        }
    }
    if($StateDirectory){
        [void][IO.Directory]::CreateDirectory($StateDirectory)
        $sidecar=Join-Path $StateDirectory 'planning-waiting.json'
        $reminderPath=Join-Path $StateDirectory 'planning-reminders.json';$reminders=@{}
        if(Test-Path -LiteralPath $reminderPath){try{$old=([IO.File]::ReadAllText($reminderPath,[Text.Encoding]::UTF8)|ConvertFrom-Json);foreach($p in $old.PSObject.Properties){$reminders[$p.Name]=$p.Value}}catch{throw 'PlanningReminderStateUnreadable; reminders fail closed'}}
        $dueReminders=@();$eventDirectory=Join-Path $StateDirectory 'planning-wake-events'
        foreach($item in $items){
            if($item.status -notin @('planned','rework','in_progress','blocked') -or -not $roots[[string]$item.id]){continue}
            $interaction=Get-PlanningValue $item 'humanInteraction';$due=Get-PlanningValue $item 'dueAt'
            if(-not (Test-HISatisfied $interaction) -or -not $due -or [DateTimeOffset]::Parse([string]$due).UtcDateTime -gt $NowUtc.ToUniversalTime()){continue}
            $generation=[string](Get-PlanningValue $item 'revision' '0')
            $key=[string]$item.id+':'+$generation+':'+[string]$due
            $sha=[Security.Cryptography.SHA256]::Create()
            try{$digest=([BitConverter]::ToString($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($key)))).Replace('-','').ToLowerInvariant()}finally{$sha.Dispose()}
            $eventId='reminder-'+$digest
            $eventFile=Join-Path $eventDirectory ($eventId+'.json')
            # Publish before recording the cursor; import resumes after a crash.
            if($reminders.ContainsKey($key)){continue}
            $event=[ordered]@{eventId=$eventId;workItemId=[string]$item.id;generation=$generation;dueAt=[string]$due}
            [void][IO.Directory]::CreateDirectory($eventDirectory)
            if(-not [IO.File]::Exists($eventFile)){Write-LCJournal $eventFile $event}
            $published=ConvertFrom-Json -InputObject ([IO.File]::ReadAllText($eventFile,[Text.Encoding]::UTF8)) -ErrorAction Stop
            if($published.eventId -cne $eventId -or $published.workItemId -cne [string]$item.id -or $published.generation -cne $generation -or $published.dueAt -cne [string]$due){throw 'PlanningReminderIdentityConflict'}
            $reminders[$key]=$true;$dueReminders+=$event
        }
        if($dueReminders.Count){$reminderBytes=[Text.UTF8Encoding]::new($false).GetBytes((ConvertTo-Json -InputObject $reminders -Depth 5 -Compress));$reminderTemp=$reminderPath+'.'+[guid]::NewGuid().ToString('N')+'.tmp';[IO.File]::WriteAllBytes($reminderTemp,$reminderBytes);if([IO.File]::Exists($reminderPath)){[IO.File]::Replace($reminderTemp,$reminderPath,$null)}else{[IO.File]::Move($reminderTemp,$reminderPath)}}
        $state=[ordered]@{items=@($waiting | ForEach-Object {[ordered]@{workItemId=[string]$_.item.id;reason=$_.reason;wakeAt=$(if($null -ne $_.wake){$_.wake.ToString('o')}else{$null})}});selected=@($selected|ForEach-Object{[string]$_.id});availableSlots=$available;capacityUnknown=$unknown;wakeEvents=$dueReminders}
        $json=($state|ConvertTo-Json -Depth 8);$oldJson=if(Test-Path -LiteralPath $sidecar){[IO.File]::ReadAllText($sidecar,[Text.Encoding]::UTF8)}else{$null}
        if($oldJson -cne $json){$tmp=$sidecar+'.'+[guid]::NewGuid().ToString('N')+'.tmp';[IO.File]::WriteAllText($tmp,$json,[Text.UTF8Encoding]::new($false));if(Test-Path -LiteralPath $sidecar){[IO.File]::Replace($tmp,$sidecar,$null)}else{[IO.File]::Move($tmp,$sidecar)}}
    }
    $nextWake=$null;$nextWakeEntry=$waiting|Where-Object{$null -ne $_.wake}|Sort-Object wake|Select-Object -First 1;if($null -ne $nextWakeEntry){$nextWake=$nextWakeEntry.wake}
    return [pscustomobject]@{Capacity=$Capacity;ActiveExecutions=$admissionCount.Count;AvailableSlots=$available;CapacityUnknown=$unknown;ReadyWorkItemIds=@($fair|ForEach-Object{[string]$_.id});SelectedWorkItemIds=@($selected|ForEach-Object{[string]$_.id});WaitingWorkItemIds=@($waiting|ForEach-Object{[string]$_.item.id});NextWakeUtc=$nextWake}
}
function Get-CoordinatorReadyWork { [CmdletBinding()] param([Parameter(Mandatory=$true)][object[]]$WorkItems,[Parameter(Mandatory=$true)][ValidateRange(1,100)][int]$Capacity,[object[]]$ActiveExecutions=@(),[string[]]$WakeEventIds=@(),[string[]]$ResumeRequiredWorkItemIds=@(),[Collections.IDictionary]$ResumeAssessments=@{},[Collections.IDictionary]$TeamCapacities=@{},[string]$StateDirectory); Get-CoordinatorPlanningDecision @PSBoundParameters }
function Advance-CoordinatorRootCursor { [CmdletBinding()] param([Parameter(Mandatory=$true)][string]$StateDirectory,[Parameter(Mandatory=$true)][string]$Priority,[Parameter(Mandatory=$true)][string]$StartedRootId);$rank=@{urgent=0;high=1;normal=2;low=3};$band=if($rank.ContainsKey($Priority)){$rank[$Priority]}else{4};[void][IO.Directory]::CreateDirectory($StateDirectory);$path=Join-Path $StateDirectory 'planning-root-cursors.json';$state=[ordered]@{};if(Test-Path -LiteralPath $path){$old=([IO.File]::ReadAllText($path,[Text.Encoding]::UTF8)|ConvertFrom-Json);foreach($p in $old.PSObject.Properties){$state[$p.Name]=[string]$p.Value}};$state[[string]$band]=$StartedRootId;$tmp=$path+'.'+[guid]::NewGuid().ToString('N')+'.tmp';[IO.File]::WriteAllText($tmp,(ConvertTo-Json -InputObject $state -Compress),[Text.UTF8Encoding]::new($false));if(Test-Path -LiteralPath $path){[IO.File]::Replace($tmp,$path,$null)}else{[IO.File]::Move($tmp,$path)} }
Export-ModuleMember -Function Get-CoordinatorPlanningDecision,Get-CoordinatorReadyWork,Advance-CoordinatorRootCursor
