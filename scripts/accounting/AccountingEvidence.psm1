# Technical design; backend owns adoption. No organizational contract changes.
Set-StrictMode -Version 2
Import-Module (Join-Path $PSScriptRoot 'TokenHistory.psm1') -Force
$script:TokenFields = @('inputTokens','cachedInputTokens','outputTokens','reasoningOutputTokens','totalTokens','cacheWriteInputTokens')
function Get-Field($Object, [string]$Name) {
    if ($null -eq $Object) { return $null }
    $property = $Object.PSObject.Properties[$Name]
    if ($null -ne $property) { return $property.Value }
    return $null
}
function Get-PairedField($Object, [string]$Snake, [string]$Camel) {
    $a = Get-Field $Object $Snake
    $b = Get-Field $Object $Camel
    if ($null -ne $a -and $null -ne $b) {
        $left = $a; $right = $b
        if ($Snake -in @('task_id','parent_task_id','thread_id','turn_id','parent_thread_id','parent_turn_id')) {
            $left = Get-CanonicalId $a; $right = Get-CanonicalId $b
        } elseif ($Snake -ceq 'store_path') {
            $left = Get-CanonicalPath $a; $right = Get-CanonicalPath $b
        }
        if ($left -cne $right) {
        # Do not silently pick one spelling of a contradictory artifact.
            throw "Conflicting identity spellings: $Snake / $Camel"
        }
    }
    if ($null -ne $a) { return $a }
    return $b
}
function Get-CanonicalId($Value, [switch]$Optional) {
    if ($null -eq $Value -and $Optional) { return $null }
    if ($Value -isnot [string] -or [string]::IsNullOrWhiteSpace($Value)) { throw 'Identity must be a nonempty GUID string or actual null.' }
    $parsed = [guid]::Empty
    if (-not [guid]::TryParse($Value, [ref]$parsed)) { throw 'Invalid GUID identity.' }
    return $parsed.ToString('N')
}
function Get-CanonicalPath($Value, [switch]$Optional) {
    if ($null -eq $Value -and $Optional) { return $null }
    if ($Value -isnot [string] -or [string]::IsNullOrWhiteSpace($Value)) { throw 'Invalid store path.' }
    if (-not [IO.Path]::IsPathRooted($Value)) { throw 'Store path must be absolute.' }
    return [IO.Path]::GetFullPath($Value).ToUpperInvariant()
}
function Get-Text($Value, [switch]$Optional) {
    if ($null -eq $Value -and $Optional) { return $null }
    if ($Value -isnot [string] -or [string]::IsNullOrWhiteSpace($Value)) { throw 'Nonempty string required.' }
    return $Value
}
function Get-UsageFinal($Record) {
    if ($null -ne $Record.PSObject.Properties['status']) { throw 'Ledger status is forbidden.' }
    $property = $Record.PSObject.Properties['final']
    if ($null -eq $property) { return $true } # Existing immutable legacy format.
    if ($property.Value -isnot [bool]) { throw 'Explicit final must be a boolean.' }
    return $property.Value
}
function Get-NormalizedUsage($Value) {
    if ($null -eq $Value) { return $null }
    if ($Value -isnot [pscustomobject]) { throw 'Invalid usage object.' }
    foreach ($property in $Value.PSObject.Properties) {
        if ($script:TokenFields -cnotcontains $property.Name) { throw 'Unknown token field.' }
    }
    $result = [ordered]@{}
    foreach ($name in $script:TokenFields) {
        $property = $Value.PSObject.Properties[$name]
        if ($null -eq $property -and $name -ceq 'cacheWriteInputTokens') { $result[$name] = [long]0; continue }
        if ($null -eq $property) { throw "Missing token field: $name" }
        $number = $property.Value
        if ($number -isnot [int] -and $number -isnot [long] -and $number -isnot [decimal] -and $number -isnot [double]) { throw "Invalid numeric token field: $name" }
        try { $decimal = [decimal]$number } catch { throw 'Invalid finite token number.' }
        if ($decimal -lt 0 -or $decimal -gt [long]::MaxValue -or [decimal]::Truncate($decimal) -ne $decimal) { throw 'Token range/integrality violation.' }
        $result[$name] = [long]$decimal
    }
    if ($result.cachedInputTokens -gt $result.inputTokens -or $result.reasoningOutputTokens -gt $result.outputTokens) { throw 'Token subset violation.' }
    return [pscustomobject]$result
}
function Get-UsageIdentity($Record) {
    foreach ($name in @('task_id','parent_task_id','role','thread_id','turn_id','token_usage')) {
        if ($null -eq $Record.PSObject.Properties[$name]) { throw "Missing ledger field: $name" }
    }
    $task = Get-CanonicalId (Get-Field $Record 'task_id')
    $parent = Get-CanonicalId (Get-Field $Record 'parent_task_id') -Optional
    if ($parent -ceq $task) { throw 'Self-parent task.' }
    $thread = Get-CanonicalId (Get-Field $Record 'thread_id') -Optional
    $turn = Get-CanonicalId (Get-Field $Record 'turn_id') -Optional
    $usage = Get-NormalizedUsage (Get-Field $Record 'token_usage')
    if ($null -ne $turn -and $null -eq $thread) { throw 'Turn without thread.' }
    if ($null -ne $usage -and ($null -eq $thread -or $null -eq $turn)) { throw 'Measured usage needs thread and turn.' }
    $wid = Get-Text (Get-Field $Record 'work_item_id') -Optional
    $eid = Get-Text (Get-Field $Record 'execution_id') -Optional
    $store = Get-CanonicalPath (Get-Field $Record 'work_item_store_path') -Optional
    $present = @(@($wid,$eid,$store) | Where-Object { $null -ne $_ }).Count
    if ($present -ne 0 -and $present -ne 3) { throw 'Partial WorkItem execution binding.' }
    $parentThread = Get-CanonicalId (Get-Field $Record 'parent_thread_id') -Optional
    $parentTurn = Get-CanonicalId (Get-Field $Record 'parent_turn_id') -Optional
    if ($null -ne $parentTurn -and $null -eq $parentThread) { throw 'Parent turn without parent thread.' }
    return [pscustomobject]@{
        taskId=$task; parentTaskId=$parent; role=(Get-Text (Get-Field $Record 'role'))
        threadId=$thread; turnId=$turn
        parentThreadId=$parentThread; parentTurnId=$parentTurn
        workItemId=$wid; executionId=$eid; storePath=$store
        tokenUsage=$usage; final=(Get-UsageFinal $Record)
    }
}
function Get-BindingIdentity($Record) {
    return [pscustomobject]@{
        taskId=(Get-CanonicalId (Get-PairedField $Record 'task_id' 'taskId') -Optional)
        parentTaskId=(Get-CanonicalId (Get-PairedField $Record 'parent_task_id' 'parentTaskId') -Optional)
        threadId=(Get-CanonicalId (Get-PairedField $Record 'thread_id' 'threadId') -Optional)
        turnId=(Get-CanonicalId (Get-PairedField $Record 'turn_id' 'turnId') -Optional)
        parentThreadId=(Get-CanonicalId (Get-PairedField $Record 'parent_thread_id' 'parentThreadId') -Optional)
        parentTurnId=(Get-CanonicalId (Get-PairedField $Record 'parent_turn_id' 'parentTurnId') -Optional)
        workItemId=(Get-Text (Get-PairedField $Record 'work_item_id' 'workItemId'))
        executionId=(Get-Text (Get-PairedField $Record 'execution_id' 'executionId'))
        storePath=(Get-CanonicalPath (Get-PairedField $Record 'store_path' 'storePath'))
    }
}
function Get-TaskBindingSignature($Identity) {
    # Excludes turn; task/execution may have multiple turns. Includes parent native identities.
    return ConvertTo-Json -Compress -InputObject @(
        $Identity.parentTaskId, $Identity.role, $Identity.workItemId,
        $Identity.executionId, $Identity.storePath, $Identity.threadId,
        $Identity.parentThreadId, $Identity.parentTurnId
    )
}
function Get-NativeSignature($Identity) {
    return ConvertTo-Json -Depth 10 -Compress -InputObject @(
        (Get-TaskBindingSignature $Identity), $Identity.tokenUsage, $Identity.final
    )
}
function Read-UsageEntries([string]$Directory, [switch]$HistoryDiagnostics) {
    if ($HistoryDiagnostics) { return Read-HistoryAccountingEvidence $Directory }
    $native = @{}
    $tasks = @{}
    foreach ($file in Get-ChildItem -LiteralPath $Directory -Filter '*.usage.json' -File -ErrorAction SilentlyContinue) {
        $record = Get-Content -LiteralPath $file.FullName -Raw -Encoding UTF8 | ConvertFrom-Json
        $identity = Get-UsageIdentity $record
        $taskSignature = Get-TaskBindingSignature $identity
        if ($tasks.ContainsKey($identity.taskId)) {
            if ($tasks[$identity.taskId].signature -cne $taskSignature) { throw 'Conflicting cross-turn task binding.' }
        } else {
            $tasks[$identity.taskId] = [pscustomobject]@{ signature=$taskSignature; parent=$identity.parentTaskId }
        }
        $key = if ($null -eq $identity.turnId) { $identity.taskId + '/unknown' } else { $identity.threadId + '/' + $identity.turnId }
        $signature = Get-NativeSignature $identity
        if ($native.ContainsKey($key)) {
            $prior = $native[$key]
            if ($prior.signature -cne $signature) { throw "Conflicting native measurement: $key" }
            if ($prior.AliasTaskIds -cnotcontains $identity.taskId) { $prior.AliasTaskIds += @($identity.taskId) }
            $prior.paths += @($file.FullName)
            $prior.records += @($record)
        } else {
            $native[$key] = [pscustomobject]@{
                native_key=$key; identity=$identity; signature=$signature; counterKind=(Get-LedgerCounterKind ([pscustomobject]@{records=@($record)})); projected=$false
                AliasTaskIds=@($identity.taskId); paths=@($file.FullName); records=@($record)
            }
        }
    }
    # Immutable enrichment does not add usage or alter accepted accounting identity.
    foreach ($file in Get-ChildItem -LiteralPath $Directory -Filter '*.profile.json' -File -ErrorAction SilentlyContinue) {
        $profile = Get-Content -LiteralPath $file.FullName -Raw -Encoding UTF8 | ConvertFrom-Json
        if ((Get-Field $profile 'schema') -cne 'native-token-profile/v1') { continue }
        $key = (Get-CanonicalId (Get-Field $profile 'thread_id')) + '/' + (Get-CanonicalId (Get-Field $profile 'turn_id'))
        if (-not $native.ContainsKey($key)) { continue }
        $entry = $native[$key]
        if ($entry.AliasTaskIds -cnotcontains (Get-CanonicalId (Get-Field $profile 'task_id'))) { continue }
        $entry.records += @($profile); $entry.paths += @($file.FullName)
    }
    foreach ($id in @($tasks.Keys)) {
        $seen = @{}; $cursor = $id
        while ($null -ne $cursor -and $tasks.ContainsKey($cursor)) {
            if ($seen.ContainsKey($cursor)) { throw 'Parent task cycle.' }
            $seen[$cursor] = $true; $cursor = $tasks[$cursor].parent
        }
    }
    return @($native.Values)
}
function Get-UsageSourceHash([byte[]]$Bytes) {
    $sha=[Security.Cryptography.SHA256]::Create()
    try { return ([BitConverter]::ToString($sha.ComputeHash($Bytes))).Replace('-','').ToLowerInvariant() }
    finally { $sha.Dispose() }
}
function Read-OriginalUsageCaptures([string]$Directory) {
    $captures=@()
    foreach ($file in Get-ChildItem -LiteralPath $Directory -Filter '*.capture.json' -File -ErrorAction SilentlyContinue) {
        $record=Get-Content -LiteralPath $file.FullName -Raw -Encoding UTF8 | ConvertFrom-Json
        if ((Get-Field $record 'schema') -cne 'original-usage-capture/v1') { throw 'Unknown original capture schema.' }
        $binding=New-AccountingBinding $record @($file.FullName)
        if ($null -eq $binding.taskId -or $null -eq $binding.threadId -or $null -eq $binding.turnId) { throw 'Original capture identity missing.' }
        $documents=@{}
        foreach ($name in @('job','nativeAck','turnAck')) {
            $path=Get-Field $record ($name+'Path'); $hash=Get-Field $record ($name+'Sha256')
            if ($hash -isnot [string] -or $hash -cnotmatch '^[0-9a-f]{64}$') { throw 'Original capture pin missing.' }
            $full=Get-CanonicalPath $path
            $bytes=[IO.File]::ReadAllBytes($full)
            if ((Get-UsageSourceHash $bytes) -cne $hash) { throw 'Original capture source changed; preserve capture.' }
            $documents[$name]=[Text.UTF8Encoding]::new($false,$true).GetString($bytes) | ConvertFrom-Json
            $binding.sources+=@($full)
        }
        $job=New-AccountingBinding $documents.job @()
        foreach ($field in @('taskId','parentTaskId','parentThreadId','parentTurnId','workItemId','executionId','storePath')) {
            if ($job.$field -cne $binding.$field) { throw 'Original capture job binding conflict.' }
        }
        $ack=$documents.nativeAck
        if ((Get-CanonicalId $ack.taskId) -cne $binding.taskId -or (Get-CanonicalId $ack.threadId) -cne $binding.threadId -or
            (Get-CanonicalId $ack.reply.thread.id) -cne $binding.threadId -or (Get-CanonicalId $documents.turnAck.turn.id) -cne $binding.turnId -or
            $ack.origin -cne $record.provider -or $ack.generation -cne $record.generation) { throw 'Original capture native ACK conflict.' }
        $captures+=@([pscustomobject]@{binding=$binding;path=$file.FullName;jobPath=$record.jobPath;role=$documents.job.role;record=$record})
    }
    return $captures
}
function Read-OriginalUsageTurnExpectations([string]$Directory) {
    foreach ($file in Get-ChildItem -LiteralPath $Directory -Filter '*.turn-expectation.json' -File -ErrorAction SilentlyContinue) {
        $record=Get-Content -LiteralPath $file.FullName -Raw -Encoding UTF8 | ConvertFrom-Json
        if ((Get-Field $record 'schema') -cne 'observed-usage-turn/v1') { throw 'Unknown observed turn expectation.' }
        $binding=New-AccountingBinding $record @($file.FullName)
        if ($null -eq $binding.taskId -or $null -eq $binding.threadId -or $null -eq $binding.turnId) { throw 'Observed turn binding missing.' }
        $binding
    }
}
function Read-ExpectedTaskFamily([string[]]$SourcePaths) {
    # Each source declares an exact root set and a complete snapshot bound to a
    # real evidence file. Rows represent task-turn identities, not one row per task.
    $tasks = @{}; $conflicts = @(); $coverage = @(); $complete = $false
    foreach ($path in $SourcePaths) {
        $fullPath = Get-CanonicalPath $path
        $document = Get-Content -LiteralPath $fullPath -Raw -Encoding UTF8 | ConvertFrom-Json
        if ($document -isnot [pscustomobject] -or $document.version -ne 1 -or $document.tasks -isnot [array] -or $document.root_task_ids -isnot [array] -or $document.coverage -isnot [pscustomobject]) {
            throw "Invalid expected-task source: $fullPath"
        }
        $c=$document.coverage
        $coveredRoots=@($c.root_task_ids | ForEach-Object { Get-CanonicalId $_ } | Sort-Object -Unique)
        $declaredRoots=@($document.root_task_ids | ForEach-Object { Get-CanonicalId $_ } | Sort-Object -Unique)
        # A declared path/flag is not an independently readable complete inventory.
        $evidence=Get-CanonicalPath (Get-Field $c 'source') -Optional
        if ($((Get-Field $c 'complete')) -isnot [bool] -or $((Get-Field $c 'coveredThrough')) -isnot [string] -or (Get-Field $c 'coveredThrough') -notmatch 'Z$' -or $coveredRoots.Count -eq 0 -or (Compare-Object $declaredRoots $coveredRoots -SyncWindow 0)) { $complete=$false }
        $coverageStore=Get-Field $c 'store_path'; $coverageItems=Get-Field $c 'work_item_ids'
        if ((Get-Field $c 'scope') -ceq 'workitem' -and (-not $coverageStore -or -not $coverageItems)) { $complete=$false }
        if ((Get-Field $c 'scope') -cne 'task' -and (Get-Field $c 'scope') -cne 'workitem') { $complete=$false }
        if (-not (Get-Field $c 'complete')) { $complete=$false }
        $coverage += @([pscustomobject]@{roots=$coveredRoots; source=$evidence; through=(Get-Field $c 'coveredThrough'); scope=(Get-Field $c 'scope'); storePath=$(if($coverageStore){Get-CanonicalPath $coverageStore}else{$null}); workItemIds=@($coverageItems); identities=@((Get-Field $c 'identities')); complete=$false})
        foreach ($row in $document.tasks) {
            $taskId = Get-CanonicalId (Get-PairedField $row 'task_id' 'taskId')
            $identity = [pscustomobject]@{
                taskId=$taskId
                parentTaskId=(Get-CanonicalId (Get-PairedField $row 'parent_task_id' 'parentTaskId') -Optional)
                threadId=(Get-CanonicalId (Get-PairedField $row 'thread_id' 'threadId') -Optional)
                turnId=(Get-CanonicalId (Get-PairedField $row 'turn_id' 'turnId') -Optional)
                workItemId=(Get-Text (Get-PairedField $row 'work_item_id' 'workItemId') -Optional)
                executionId=(Get-Text (Get-PairedField $row 'execution_id' 'executionId') -Optional)
                storePath=(Get-CanonicalPath (Get-PairedField $row 'store_path' 'storePath') -Optional)
                source=$fullPath
            }
            if ((@($identity.workItemId,$identity.executionId,$identity.storePath | Where-Object { $null -ne $_ }).Count) -notin @(0,3)) { throw "Partial expected WorkItem execution binding: $fullPath" }
            if ($null -ne $identity.turnId -and $null -eq $identity.threadId) { throw "Expected turn without thread: $fullPath" }
            $key=('{0}/{1}/{2}/{3}/{4}/{5}' -f $taskId,$identity.threadId,$identity.turnId,$identity.executionId,$identity.storePath,$identity.workItemId)
            if ($null -eq $identity.threadId -or $null -eq $identity.turnId) { $complete=$false }
            if ($tasks.ContainsKey($key)) { $prior=$tasks[$key]; if ($prior.parentTaskId -cne $identity.parentTaskId) { $conflicts += @([pscustomobject]@{taskId=$taskId;reason='conflicting_expected_parent';sources=@($prior.sources)+@($fullPath)}) }; if($prior.sources -cnotcontains $fullPath){$prior.sources+=@($fullPath)} }
            else { $tasks[$key]=[pscustomobject]@{taskId=$taskId; parentTaskId=$identity.parentTaskId; threadId=$identity.threadId; turnId=$identity.turnId; workItemId=$identity.workItemId; executionId=$identity.executionId; storePath=$identity.storePath; sources=@($fullPath)} }
        }
    }
    foreach($cov in $coverage) {
        $rows=@($tasks.Values | Where-Object { ($_.taskId -in $cov.roots -or $null -ne $_.parentTaskId) -and ($cov.scope -cne 'workitem' -or ($_.storePath -ceq $cov.storePath -and $_.workItemId -in $cov.workItemIds)) })
        if($cov.identities -isnot [array] -or $cov.identities.Count -ne $rows.Count){$complete=$false;continue}
        foreach($row in $rows){
            $matches=@($cov.identities|Where-Object{(Get-CanonicalId (Get-PairedField $_ 'task_id' 'taskId')) -ceq $row.taskId -and (Get-CanonicalId (Get-PairedField $_ 'parent_task_id' 'parentTaskId') -Optional) -ceq $row.parentTaskId -and (Get-CanonicalId (Get-PairedField $_ 'thread_id' 'threadId') -Optional) -ceq $row.threadId -and (Get-CanonicalId (Get-PairedField $_ 'turn_id' 'turnId') -Optional) -ceq $row.turnId -and (Get-Text (Get-PairedField $_ 'execution_id' 'executionId') -Optional) -ceq $row.executionId -and (Get-Text (Get-PairedField $_ 'work_item_id' 'workItemId') -Optional) -ceq $row.workItemId -and (Get-CanonicalPath (Get-PairedField $_ 'store_path' 'storePath') -Optional) -ceq $row.storePath})
            if($matches.Count -ne 1){$complete=$false}
        }
    }
    $taskParents=@{}
    foreach($item in $tasks.Values) {
        if($item.parentTaskId -ceq $item.taskId){$conflicts+=@([pscustomobject]@{taskId=$item.taskId;reason='expected_self_parent'})}
        if(-not $taskParents.ContainsKey($item.taskId)){$taskParents[$item.taskId]=@()}
        if($taskParents[$item.taskId] -cnotcontains $item.parentTaskId){$taskParents[$item.taskId]+=@($item.parentTaskId)}
    }
    foreach($id in @($taskParents.Keys)) { $parents=@($tasks.Values | Where-Object taskId -ceq $id | ForEach-Object parentTaskId | Select-Object -Unique); if($parents.Count -gt 1){$conflicts+=@([pscustomobject]@{taskId=$id;reason='conflicting_expected_parent_across_turns'})} }
    foreach($root in @($coverage | ForEach-Object roots | Select-Object -Unique)) {
        if (@($tasks.Values | Where-Object taskId -ceq $root).Count -eq 0) { $conflicts+=@([pscustomobject]@{taskId=$root;reason='expected_root_missing'}) }
        foreach($item in $tasks.Values) { if($item.taskId -ceq $root -and $null -ne $item.parentTaskId){$conflicts+=@([pscustomobject]@{taskId=$root;reason='root_parent_not_null'})} }
    }
    $rootSet=@($coverage | ForEach-Object roots | Select-Object -Unique)
    foreach($item in $tasks.Values) {
        $stack=New-Object 'System.Collections.Generic.Stack[object]'; $stack.Push([pscustomobject]@{id=$item.taskId; path=@()}); $reachable=$false; $cycle=$false
        while($stack.Count -gt 0){$node=$stack.Pop(); if($node.id -in $rootSet){$reachable=$true;continue}; if($node.id -in $node.path){$cycle=$true;continue}; if(-not $taskParents.ContainsKey($node.id)){continue}; foreach($parent in $taskParents[$node.id]){if($null -ne $parent){$stack.Push([pscustomobject]@{id=$parent;path=@($node.path)+@($node.id)})}} }
        if($cycle){$conflicts+=@([pscustomobject]@{taskId=$item.taskId;reason='expected_parent_cycle'})}; if(-not $reachable){$conflicts+=@([pscustomobject]@{taskId=$item.taskId;reason='expected_task_unreachable'})}
    }
    return [pscustomobject]@{tasks=@($tasks.Values); familyComplete=$false; completenessReason='family_inventory_verification_unavailable'; conflicts=$conflicts; coverage=$coverage; sources=@($SourcePaths)}
}
# SOURCE DESIGN ONLY. Replace Read-ObservedAccountingFamily through
# Merge-NativeAccountingMeasurements in AccountingEvidence.psm1 with this text.
# Existing Get-Field/canonicalization/usage/identity/sum helpers are retained.
function New-AccountingBinding($Value, [string[]]$Sources) {
    $store = Get-PairedField $Value 'store_path' 'storePath'
    $other = Get-Field $Value 'work_item_store_path'
    if ($null -ne $store -and $null -ne $other -and
        (Get-CanonicalPath $store) -cne (Get-CanonicalPath $other)) { throw 'Conflicting store spellings.' }
    if ($null -eq $store) { $store = $other }
    return [pscustomobject]@{
        taskId=Get-CanonicalId (Get-PairedField $Value 'task_id' 'taskId') -Optional
        parentTaskId=Get-CanonicalId (Get-PairedField $Value 'parent_task_id' 'parentTaskId') -Optional
        threadId=Get-CanonicalId (Get-PairedField $Value 'thread_id' 'threadId') -Optional
        turnId=Get-CanonicalId (Get-PairedField $Value 'turn_id' 'turnId') -Optional
        parentThreadId=Get-CanonicalId (Get-PairedField $Value 'parent_thread_id' 'parentThreadId') -Optional
        parentTurnId=Get-CanonicalId (Get-PairedField $Value 'parent_turn_id' 'parentTurnId') -Optional
        workItemId=Get-Text (Get-PairedField $Value 'work_item_id' 'workItemId') -Optional
        executionId=Get-Text (Get-PairedField $Value 'execution_id' 'executionId') -Optional
        storePath=Get-CanonicalPath $store -Optional
        sources=@($Sources); evidenceKind='observed_binding'
    }
}
function New-AccountingConflict($Binding, [string]$Reason, [string[]]$Sources) {
    $task=Get-Field $Binding 'taskId'; $thread=Get-Field $Binding 'threadId'; $turn=Get-Field $Binding 'turnId'
    $scope=if ($Reason -match '^conflicting_task_|^observed_(self_parent|parent_cycle|root_missing)$') { 'task' }
        elseif ($null -ne $thread -and $null -ne $turn) { 'native' }
        elseif ($null -ne $thread) { 'thread' } else { 'task' }
    return [pscustomobject]@{
        taskId=$task; taskIds=@($task | Where-Object { $null -ne $_ })
        threadId=$thread; turnId=$turn; executionId=Get-Field $Binding 'executionId'
        nativeKeys=@($(if ($null -ne $thread -and $null -ne $turn) { $thread+'/'+$turn }))
        reason=$Reason; sources=@($Sources); scope=$scope
    }
}
function Resolve-AccountingBindings($Rows) {
    # Raw observations remain visible; infer only unanimous non-null values.
    # Task metadata never copies a turn ID: a task can have additional turns.
    $rows=@($Rows); $conflicts=@()
    $metadata=@('parentTaskId','parentThreadId','parentTurnId','workItemId','executionId','storePath')
    do {
        $changed=$false
        foreach ($row in $rows) {
            $peers=@()
            if ($null -ne $row.taskId) { $peers+=@($rows | Where-Object taskId -ceq $row.taskId) }
            if ($null -eq $row.threadId -and $null -ne $row.turnId) {
                $peers+=@($rows | Where-Object turnId -ceq $row.turnId)
            }
            if ($null -ne $row.threadId -and $null -ne $row.turnId) {
                $peers+=@($rows | Where-Object { $_.threadId -ceq $row.threadId -and $_.turnId -ceq $row.turnId })
            }
            foreach ($field in $metadata+@('threadId')) {
                $values=@($peers | ForEach-Object { Get-Field $_ $field } | Where-Object { $null -ne $_ } | Select-Object -Unique)
                if ($null -eq $row.$field -and $values.Count -eq 1) { $row.$field=$values[0]; $changed=$true }
            }
            if ($null -eq $row.taskId -and $null -ne $row.threadId) {
                $exact=@($rows | Where-Object { $_.threadId -ceq $row.threadId -and $null -ne $row.turnId -and $_.turnId -ceq $row.turnId })
                $ids=@($exact | ForEach-Object taskId | Where-Object { $null -ne $_ } | Select-Object -Unique)
                if ($ids.Count -eq 0) {
                    $ids=@($rows | Where-Object threadId -ceq $row.threadId | ForEach-Object taskId | Where-Object { $null -ne $_ } | Select-Object -Unique)
                }
                if ($ids.Count -eq 1) { $row.taskId=$ids[0]; $changed=$true }
            }
            # Sources of inferred task-level fields are part of the binding evidence.
            foreach ($peer in $peers) { foreach ($source in $peer.sources) { if ($row.sources -cnotcontains $source) { $row.sources+=@($source) } } }
        }
    } while ($changed)
    foreach ($row in $rows) {
        $taskPeers=@($rows | Where-Object { $null -ne $row.taskId -and $_.taskId -ceq $row.taskId })
        $nativePeers=@($rows | Where-Object { $null -ne $row.threadId -and $null -ne $row.turnId -and $_.threadId -ceq $row.threadId -and $_.turnId -ceq $row.turnId })
        foreach ($field in $metadata+@('threadId')) {
            $values=@($taskPeers | ForEach-Object { Get-Field $_ $field } | Where-Object { $null -ne $_ } | Select-Object -Unique)
            if ($values.Count -gt 1) { $conflicts+=@(New-AccountingConflict $row ('conflicting_task_'+$field) @($taskPeers | ForEach-Object sources)) }
        }
        foreach ($field in $metadata+@('taskId')) {
            $values=@($nativePeers | ForEach-Object { Get-Field $_ $field } | Where-Object { $null -ne $_ } | Select-Object -Unique)
            if ($values.Count -gt 1) { $conflicts+=@(New-AccountingConflict $row ('conflicting_native_'+$field) @($nativePeers | ForEach-Object sources)) }
        }
        # Validation deliberately follows inference.
        $count=@(@($row.workItemId,$row.executionId,$row.storePath) | Where-Object { $null -ne $_ }).Count
        if ($count -notin @(0,3)) { $conflicts+=@(New-AccountingConflict $row 'partial_workitem_binding_after_inference' $row.sources) }
        if ($null -ne $row.turnId -and $null -eq $row.threadId) { $conflicts+=@(New-AccountingConflict $row 'turn_without_thread_after_inference' $row.sources) }
        if ($null -ne $row.parentTurnId -and $null -eq $row.parentThreadId) { $conflicts+=@(New-AccountingConflict $row 'parent_turn_without_thread_after_inference' $row.sources) }
        if ($null -ne $row.taskId -and $row.taskId -ceq $row.parentTaskId) { $conflicts+=@(New-AccountingConflict $row 'observed_self_parent' $row.sources) }
    }
    $canonical=@{}
    foreach ($row in $rows) {
        if ($null -eq $row.turnId -and $null -ne $row.taskId -and
            @($rows | Where-Object { $_.taskId -ceq $row.taskId -and $null -ne $_.turnId }).Count -gt 0) { continue }
        # Include conflicting metadata variants so no scope claim disappears.
        $key=ConvertTo-Json -Compress -InputObject @($row.taskId,$row.threadId,$row.turnId,$row.parentTaskId,$row.parentThreadId,$row.parentTurnId,$row.workItemId,$row.executionId,$row.storePath)
        if (-not $canonical.ContainsKey($key)) { $canonical[$key]=$row }
        else { $canonical[$key].sources=@(@($canonical[$key].sources)+@($row.sources) | Select-Object -Unique) }
    }
    foreach ($row in $canonical.Values) {
        $cursor=$row.taskId; $seen=@{}
        while ($null -ne $cursor) {
            if ($seen.ContainsKey($cursor)) { $conflicts+=@(New-AccountingConflict $row 'observed_parent_cycle' $row.sources); break }
            $seen[$cursor]=$true
            $parents=@($canonical.Values | Where-Object taskId -ceq $cursor | ForEach-Object parentTaskId | Where-Object { $null -ne $_ } | Select-Object -Unique)
            if ($parents.Count -ne 1) { break }; $cursor=$parents[0]
        }
    }
    return [pscustomobject]@{rows=@($canonical.Values); conflicts=$conflicts}
}
function Get-NormalizedNativeUsage($Value) {
    if ($Value -isnot [pscustomobject]) { throw 'Unknown native snapshot.' }
    $map=[ordered]@{input_tokens='inputTokens';cached_input_tokens='cachedInputTokens';output_tokens='outputTokens';reasoning_output_tokens='reasoningOutputTokens';total_tokens='totalTokens';cache_write_input_tokens='cacheWriteInputTokens'}
    foreach ($property in $Value.PSObject.Properties) { if (-not $map.Contains($property.Name)) { throw 'Unknown native token field.' } }
    $normalized=[ordered]@{}
    foreach ($name in $map.Keys) {
        # Only the historically absent cache-write property defaults to zero.
        # An explicit null is never converted into a measurement.
        $property=$Value.PSObject.Properties[$name]
        if ($null -eq $property -and $name -ceq 'cache_write_input_tokens') { $normalized[$map[$name]]=[long]0; continue }
        $normalized[$map[$name]]=Get-Field $Value $name
    }
    return Get-NormalizedUsage ([pscustomobject]$normalized)
}
function Compare-AccountingUsage($Left, $Right, [switch]$Dominates) {
    foreach ($field in $script:TokenFields) {
        if ($Dominates) { if ((Get-Field $Left $field) -lt (Get-Field $Right $field)) { return $false } }
        elseif ((Get-Field $Left $field) -ne (Get-Field $Right $field)) { return $false }
    }
    return $true
}
function Get-LedgerCounterKind($Entry) {
    $kind=Get-Field $Entry 'counterKind'
    if ($kind -ceq 'turn_token_usage') { return $kind }
    $kinds=@(@(foreach ($record in @(Get-Field $Entry 'records')) {
        $explicit=Get-Field $record 'counter_kind'
        if ($null -eq $explicit) { $explicit=Get-Field $record 'counterKind' }
        $source=Get-Field $record 'source'
        if ($explicit -ceq 'turn_token_usage' -or $source -cin @('local_rollout_native_turn_usage','local_rollout_completed_turn_delta')) { 'turn_token_usage' }
        elseif ($explicit -cin @('thread_total','thread_total_without_baseline')) { 'thread_total_without_baseline' }
        else { 'unknown' }
    }) | Select-Object -Unique)
    if ($kinds.Count -eq 1) { return $kinds[0] }
    return 'unknown'
}
function Read-ObservedAccountingFamily([string[]]$JobArtifactPaths, [string[]]$RolloutPaths, [string[]]$RootTaskIds, [string[]]$EventLogPaths, $SupplementalBindings=@()) {
    $rows=@(); $lifecycles=@(); $sources=@(); $conflicts=@(); $diagnostics=@()
    $jobProfiles=@()
    $roots=@($RootTaskIds | ForEach-Object { Get-CanonicalId $_ } | Select-Object -Unique)
    foreach ($path in @($JobArtifactPaths | Select-Object -Unique)) {
        $full=Get-CanonicalPath $path; $sources+=@($full)
        $document=Get-Content -LiteralPath $full -Raw -Encoding UTF8 | ConvertFrom-Json
        $jobBinding=New-AccountingBinding $document @($full)
        $rows+=@($jobBinding)
        $jobProfiles+=@([pscustomobject]@{binding=$jobBinding;roleId=(Get-Field $document 'role');source=$full})
    }
    foreach ($binding in @($SupplementalBindings)) { $rows+=@(New-AccountingBinding $binding @(Get-Field $binding 'sources')) }
    foreach ($path in @($RolloutPaths | Select-Object -Unique)) {
        $full=Get-CanonicalPath $path; $sources+=@($full); $file=Get-Item -LiteralPath $full
        if ($file.PSIsContainer -or $file.Name -notmatch '^rollout-\d{4}-\d{2}-\d{2}T\d{2}-\d{2}-\d{2}-([0-9a-fA-F-]{36})\.jsonl$') { throw 'Unknown rollout filename.' }
        $thread=Get-CanonicalId $Matches[1]
        $local=@{}; $last=[long]-1; $seen=@{}; $sessions=0; $active=$null
        $reader=New-Object System.IO.StreamReader($file.FullName,(New-Object System.Text.UTF8Encoding($false,$true)),$false)
        try {
            while ($null -ne ($line=$reader.ReadLine())) {
                try {
                    $record=$line | ConvertFrom-Json; $payload=Get-Field $record 'payload'; $type=Get-Field $record 'type'
                    $ordinal=Get-Field $record 'ordinal'
                    if ($ordinal -isnot [int] -and $ordinal -isnot [long]) { throw 'Invalid ordinal.' }
                    if ($ordinal -lt 0 -or $ordinal -le $last -or $seen.ContainsKey($ordinal)) { throw 'Duplicate or unordered ordinal.' }
                    $seen[$ordinal]=$true; $last=[long]$ordinal
                    if ($payload -isnot [pscustomobject] -or $type -isnot [string]) { throw 'Invalid envelope.' }
                    if ($type -ceq 'session_meta') {
                        $sessions++
                        if ($sessions -ne 1 -or (Get-CanonicalId (Get-Field $payload 'id')) -cne $thread) { throw 'Ambiguous session identity.' }
                        continue
                    }
                    $turn=Get-CanonicalId (Get-Field $payload 'turn_id') -Optional
                    if ($null -eq $turn) { continue }
                    if (-not $local.ContainsKey($turn)) {
                        $binding=New-AccountingBinding ([pscustomobject]@{thread_id=$thread;turn_id=$turn}) @($full)
                        $local[$turn]=[pscustomobject]@{binding=$binding;source=$full;startOrdinal=$null;completeOrdinal=$null;context=$false;profiles=@();snapshots=@();issues=@()}
                        $rows+=@($binding)
                    }
                    $state=$local[$turn]
                    if ($type -ceq 'turn_context') {
                        $ctx=New-AccountingBinding $payload @($full)
                        if ($null -ne $ctx.threadId -and $ctx.threadId -cne $thread) { throw 'Foreign context thread.' }
                        $ctx.threadId=$thread; $rows+=@($ctx); $state.context=$true
                        $state.profiles+=@(Get-TurnContextHistory $payload ($full+'#ordinal='+$ordinal))
                    } elseif ($type -ceq 'token_usage_record') {
                        if ((Get-CanonicalId (Get-Field $payload 'thread_id')) -cne $thread) { throw 'Foreign token thread.' }
                        $state.snapshots+=@([pscustomobject]@{ordinal=[long]$ordinal;usage=Get-NormalizedNativeUsage (Get-Field $payload 'turn_token_usage');measurementUTC=(ConvertTo-HistoryUTC (Get-Field $record 'timestamp'));source=$full})
                    } elseif ($type -ceq 'event_msg') {
                        $eventType=Get-Field $payload 'type'
                        if ($eventType -ceq 'task_started') {
                            if ($sessions -ne 1 -or $null -ne $active -or $null -ne $state.startOrdinal -or $null -ne $state.completeOrdinal) { throw 'Ambiguous turn start.' }
                            $state.startOrdinal=[long]$ordinal; $active=$turn
                        } elseif ($eventType -ceq 'task_complete') {
                            if ($active -cne $turn -or $null -ne $state.completeOrdinal) { throw 'Unmatched turn completion.' }
                            $state.completeOrdinal=[long]$ordinal; $active=$null
                        }
                    }
                } catch {
                    # Conservatively mask this source's whole thread; later sources
                    # cannot repair an invalid lifecycle by supplying boundaries.
                    $conflicts+=@(New-AccountingConflict ([pscustomobject]@{threadId=$thread}) ('invalid_native_source: '+$_.Exception.Message) @($full))
                }
            }
        } finally { $reader.Dispose() }
        if ($sessions -ne 1) { $conflicts+=@(New-AccountingConflict ([pscustomobject]@{threadId=$thread}) 'native_session_missing_or_ambiguous' @($full)) }
        $lifecycles+=@($local.Values)
    }
    # Canonicalization and task/thread inference precede ANY final projection.
    $resolved=Resolve-AccountingBindings $rows; $tasks=@($resolved.rows); $conflicts+=@($resolved.conflicts)
    foreach ($root in $roots) {
        if (@($tasks | Where-Object taskId -ceq $root).Count -eq 0) { $conflicts+=@(New-AccountingConflict ([pscustomobject]@{taskId=$root}) 'observed_root_missing' $sources) }
    }
    $turns=@(); $candidates=@()
    foreach ($group in @($lifecycles | Group-Object { $_.binding.threadId+'/'+$_.binding.turnId })) {
        $sample=$group.Group[0].binding
        $bindings=@($tasks | Where-Object { $_.threadId -ceq $sample.threadId -and $_.turnId -ceq $sample.turnId })
        $ids=@($bindings | ForEach-Object taskId | Where-Object { $null -ne $_ } | Select-Object -Unique)
        $turn=[pscustomobject]@{
            taskId=$sample.taskId;parentTaskId=$sample.parentTaskId;parentThreadId=$sample.parentThreadId;parentTurnId=$sample.parentTurnId
            threadId=$sample.threadId;turnId=$sample.turnId;workItemId=$sample.workItemId;executionId=$sample.executionId;storePath=$sample.storePath
            sources=@($group.Group | ForEach-Object source);source=$group.Group[0].source
            started=$false;completed=$false;startOrdinal=$null;completeOrdinal=$null;snapshots=@();eventObservations=@();lifecycleIssues=@();sourceLifecycles=@($group.Group)
        }
        # Do not manufacture combined ordinals or a combined source lifecycle.
        if ($group.Count -eq 1) { $turn.startOrdinal=$group.Group[0].startOrdinal; $turn.completeOrdinal=$group.Group[0].completeOrdinal }
        $turn.started=@($group.Group | Where-Object { $null -ne $_.startOrdinal }).Count -gt 0
        $turn.completed=@($group.Group | Where-Object { $_.context -and $null -ne $_.startOrdinal -and $null -ne $_.completeOrdinal -and $_.startOrdinal -lt $_.completeOrdinal }).Count -gt 0
        if (-not $turn.completed) { $conflicts+=@(New-AccountingConflict $sample 'observed_native_final_closure_missing' $turn.sources) }
        if ($ids.Count -ne 1) { $conflicts+=@(New-AccountingConflict $sample 'native_turn_task_binding_missing_or_ambiguous' $turn.sources) }
        $turns+=@($turn)
        foreach ($state in $group.Group) {
            if (-not $state.context -or $null -eq $state.startOrdinal -or $null -eq $state.completeOrdinal) { continue }
            if ($state.startOrdinal -ge $state.completeOrdinal) { $conflicts+=@(New-AccountingConflict $sample 'invalid_native_interval' @($state.source)); continue }
            $outside=@($state.snapshots | Where-Object { $_.ordinal -le $state.startOrdinal -or $_.ordinal -ge $state.completeOrdinal })
            if ($outside.Count -gt 0) { $conflicts+=@(New-AccountingConflict $sample 'native_usage_outside_source_interval' @($state.source)); continue }
            $inside=@($state.snapshots | Sort-Object ordinal); $monotone=$true
            for ($i=1; $i -lt $inside.Count; $i++) { if (-not (Compare-AccountingUsage $inside[$i].usage $inside[$i-1].usage -Dominates)) { $monotone=$false } }
            if (-not $monotone) { $conflicts+=@(New-AccountingConflict $sample 'native_turn_counter_reversal' @($state.source)); continue }
            if ($inside.Count -eq 0 -or $ids.Count -ne 1) { continue }
            $chosen=$inside[-1]
            $assignments=@($jobProfiles | Where-Object {
                $null -ne $_.binding.taskId -and $_.binding.taskId -ceq $sample.taskId -and
                ($null -eq $_.binding.threadId -or $_.binding.threadId -ceq $sample.threadId) -and
                ($null -eq $_.binding.turnId -or $_.binding.turnId -ceq $sample.turnId)
            })
            $history=Get-TokenHistory (@($state.profiles)+@($assignments)) (@($state.profiles | ForEach-Object { $state.source })+@($assignments | ForEach-Object source))
            $candidates+=@([pscustomobject]@{
                taskId=$sample.taskId;parentTaskId=$sample.parentTaskId;parentThreadId=$sample.parentThreadId;parentTurnId=$sample.parentTurnId
                threadId=$sample.threadId;turnId=$sample.turnId;workItemId=$sample.workItemId;executionId=$sample.executionId;storePath=$sample.storePath
                tokenUsage=$chosen.usage;final=$true;role='native_rollout';source=$state.source;sources=@($state.source)
                usageOrdinal=$chosen.ordinal;startOrdinal=$state.startOrdinal;completeOrdinal=$state.completeOrdinal;counterKind='turn_token_usage'
                roleId=$history.roleId;modelId=$history.modelId;reasoningEffort=$history.reasoningEffort;measurementUTC=$chosen.measurementUTC
                metadataConflicts=$history.metadataConflicts;metadataSources=$history.metadataSources;metadataAuthority=$history.metadataAuthority
                measurementTimeBasis='native_record_timestamp'
            })
        }
    }
    $measurements=@()
    foreach ($group in @($candidates | Group-Object { $_.threadId+'/'+$_.turnId })) {
        $first=$group.Group[0]; $same=$true
        foreach ($candidate in $group.Group) { if (-not (Compare-AccountingUsage $first.tokenUsage $candidate.tokenUsage)) { $same=$false } }
        if (-not $same) { $conflicts+=@(New-AccountingConflict $first 'conflicting_source_final_native_measurements' @($group.Group | ForEach-Object source)); continue }
        $first.sources=@($group.Group | ForEach-Object source | Select-Object -Unique)
        $history=Get-TokenHistory @($group.Group) @($group.Group | ForEach-Object source)
        foreach ($field in @('roleId','modelId','reasoningEffort','measurementUTC','metadataConflicts','metadataSources','metadataAuthority')) { $first.$field=$history.$field }
        $measurements+=@($first)
    }
    # Event totals are diagnostic only, even after turn/completed.
    foreach ($path in @($EventLogPaths | Select-Object -Unique)) {
        $full=Get-CanonicalPath $path; $sources+=@($full)
        foreach ($line in Get-Content -LiteralPath $full -Encoding UTF8) {
            try {
                $event=$line | ConvertFrom-Json; $data=Get-Field $event 'data'; $params=Get-Field $data 'params'
                if ((Get-Field $event 'kind') -cne 'notification' -or (Get-Field $data 'method') -cne 'thread/tokenUsage/updated') { continue }
                $thread=Get-CanonicalId (Get-Field $params 'threadId') -Optional; $turn=Get-CanonicalId (Get-Field $params 'turnId') -Optional
                $total=Get-Field (Get-Field $params 'tokenUsage') 'total'
                $diagnostic=[pscustomobject]@{threadId=$thread;turnId=$turn;source=$full;tokenUsage=$total;provisional=$true;counterKind='thread_total_without_baseline'}
                $diagnostics+=@($diagnostic)
                foreach ($native in $turns | Where-Object { $_.threadId -ceq $thread -and $_.turnId -ceq $turn }) { $native.eventObservations+=@($diagnostic) }
            } catch { $diagnostics+=@([pscustomobject]@{source=$full;reason='unreadable_event_diagnostic';message=$_.Exception.Message}) }
        }
    }
    $mask=Get-AccountingConflictMask $tasks @() $conflicts
    $measurements=@($measurements | Where-Object { $mask.nativeKeys -cnotcontains ($_.threadId+'/'+$_.turnId) -and $mask.taskIds -cnotcontains $_.taskId })
    return [pscustomobject]@{tasks=$tasks;nativeTurns=$turns;measurements=$measurements;roots=$roots;familyComplete=$false;completenessReason='authoritative_dispatch_inventory_and_bound_capture_boundary_unavailable';conflicts=$conflicts;sources=@($sources | Select-Object -Unique);diagnostics=$diagnostics}
}
function Merge-NativeAccountingMeasurements($Entries, $Measurements) {
    $all=@($Entries); $conflicts=@(); $diagnostics=@()
    foreach ($measurement in @($Measurements)) {
        $key=$measurement.threadId+'/'+$measurement.turnId
        $matches=@($all | Where-Object native_key -ceq $key)
        if ($null -eq $measurement.taskId -or $matches.Count -gt 1) { $conflicts+=@(New-AccountingConflict $measurement 'ambiguous_measurement_identity' $measurement.sources); continue }
        $record=[pscustomobject]@{task_id=$measurement.taskId;parent_task_id=$measurement.parentTaskId;parent_thread_id=$measurement.parentThreadId;parent_turn_id=$measurement.parentTurnId;role=$measurement.role;thread_id=$measurement.threadId;turn_id=$measurement.turnId;work_item_id=$measurement.workItemId;execution_id=$measurement.executionId;work_item_store_path=$measurement.storePath;token_usage=$measurement.tokenUsage;final=$true;source='local_rollout_native_turn_usage'}
        foreach ($field in @('roleId','modelId','reasoningEffort','measurementUTC','measurementTimeBasis','metadataConflicts','metadataSources','metadataAuthority')) { $record | Add-Member -NotePropertyName $field -NotePropertyValue (Get-Field $measurement $field) }
        $identity=Get-UsageIdentity $record; $aliases=@($measurement.taskId); $paths=@($measurement.sources); $records=@($record); $blocked=$false
        if ($matches.Count -eq 1) {
            $prior=$matches[0]; $old=$prior.identity
            foreach ($field in @('parentTaskId','parentThreadId','parentTurnId','workItemId','executionId','storePath')) {
                if ($null -ne $old.$field -and $null -ne $identity.$field -and $old.$field -cne $identity.$field) { $conflicts+=@(New-AccountingConflict $measurement ('native_ledger_'+$field+'_conflict') (@($prior.paths)+@($paths))); $blocked=$true }
                elseif ($null -eq $identity.$field) { $identity.$field=$old.$field }
            }
            # Aliases are native identity equivalence, not separate measurements.
            $aliases=@(@($prior.AliasTaskIds)+@($aliases) | Select-Object -Unique)
            $paths=@(@($paths)+@($prior.paths) | Select-Object -Unique); $records=@($records)+@($prior.records)
            $kind=Get-LedgerCounterKind $prior
            if ($null -ne $old.tokenUsage -and $kind -ceq 'turn_token_usage') {
                if ($old.final -and -not (Compare-AccountingUsage $identity.tokenUsage $old.tokenUsage)) { $conflicts+=@(New-AccountingConflict $measurement 'conflicting_final_native_measurement' $paths); $blocked=$true }
                elseif (-not $old.final -and -not (Compare-AccountingUsage $identity.tokenUsage $old.tokenUsage -Dominates)) { $conflicts+=@(New-AccountingConflict $measurement 'provisional_counter_reversal' $paths); $blocked=$true }
            } elseif ($null -ne $old.tokenUsage) {
                $diagnostics+=@([pscustomobject]@{nativeKey=$key;counterKind=$kind;tokenUsage=$old.tokenUsage;sources=@($prior.paths);reason='not_comparable_to_native_turn_counter'})
            }
        }
        if ($blocked) { continue }
        # The primary record exposes the effective final, while the old records
        # remain available as source evidence, with their original semantics.
        $record.parent_task_id=$identity.parentTaskId; $record.parent_thread_id=$identity.parentThreadId; $record.parent_turn_id=$identity.parentTurnId
        $record.work_item_id=$identity.workItemId; $record.execution_id=$identity.executionId; $record.work_item_store_path=$identity.storePath
        $replacement=[pscustomobject]@{native_key=$key;identity=$identity;signature=Get-NativeSignature $identity;AliasTaskIds=$aliases;paths=$paths;records=$records;projected=$true;counterKind='turn_token_usage'}
        if ($matches.Count -eq 0) { $all+=@($replacement) }
        else { $all[[array]::IndexOf($all,$matches[0])]=$replacement }
    }
    return [pscustomobject]@{entries=$all;conflicts=$conflicts;diagnostics=$diagnostics}
}
function Get-AccountingConflictMask($Expectations, $Entries, $Conflicts) {
    $keys=@(); $ids=@(); $executions=@(); $threads=@()
    foreach ($conflict in @($Conflicts)) {
        $nativeKeys=@(Get-Field $conflict 'nativeKeys' | Where-Object { $_ })
        $keys+=@($nativeKeys)
        $thread=Get-Field $conflict 'threadId'; $turn=Get-Field $conflict 'turnId'
        $scope=Get-Field $conflict 'scope'
        $nativeScoped=($scope -ceq 'native' -or ($null -eq $scope -and ($nativeKeys.Count -gt 0 -or ($null -ne $thread -and $null -ne $turn))))
        if (-not $nativeScoped -and ($scope -ceq 'task' -or $null -eq $thread)) {
            $ids+=@(Get-Field $conflict 'taskId')+@(Get-Field $conflict 'taskIds')
            $executions+=@(Get-Field $conflict 'executionId')
        }
        if ($null -ne $thread -and $null -ne $turn) { $keys+=@($thread+'/'+$turn) }
        elseif ($null -ne $thread) { $threads+=@($thread) }
    }
    # Map against expectations as well as entries; missing measurements cannot
    # hide a task/thread/execution conflict from own or its expected closure.
    $rows=@($Expectations)+@($Entries | ForEach-Object identity)
    foreach ($row in $rows) {
        $task=Get-Field $row 'taskId'; $thread=Get-Field $row 'threadId'; $turn=Get-Field $row 'turnId'; $execution=Get-Field $row 'executionId'
        if (($null -ne $task -and $ids -ccontains $task) -or ($null -ne $thread -and $threads -ccontains $thread) -or ($null -ne $execution -and $executions -ccontains $execution)) {
            if ($null -ne $thread -and $null -ne $turn) { $keys+=@($thread+'/'+$turn) }
        }
    }
    # Resolve aliases without broadening a turn-only conflict to another turn.
    foreach ($entry in @($Entries)) {
        if (@($entry.AliasTaskIds | Where-Object { $ids -ccontains $_ }).Count -gt 0) { $keys+=@($entry.native_key) }
    }
    return [pscustomobject]@{nativeKeys=@($keys | Where-Object { $_ } | Select-Object -Unique);taskIds=@($ids | Where-Object { $_ } | Select-Object -Unique);executionIds=@($executions | Where-Object { $_ } | Select-Object -Unique);threadIds=@($threads | Where-Object { $_ } | Select-Object -Unique)}
}
function Get-AccountingExpectedClosure($Expectations, $Entries, $Conflicts) {
    $expected=@($Expectations); $mask=Get-AccountingConflictMask $expected $Entries $Conflicts
    $known=@($Entries | Where-Object { $_.identity.final -and $null -ne $_.identity.tokenUsage -and $mask.nativeKeys -cnotcontains $_.native_key -and $mask.taskIds -cnotcontains $_.identity.taskId -and $mask.executionIds -cnotcontains $_.identity.executionId })
    $missing=@(); $seen=@{}
    foreach ($row in $expected) {
        $signature=ConvertTo-Json -Compress -InputObject @($row.taskId,$row.threadId,$row.turnId,$row.workItemId,$row.executionId,$row.storePath)
        if ($seen.ContainsKey($signature)) { continue }; $seen[$signature]=$true
        $matches=@($known | Where-Object {
            $identity=$_.identity
            ($null -eq $row.taskId -or $_.AliasTaskIds -ccontains $row.taskId) -and
            ($null -eq $row.threadId -or $identity.threadId -ceq $row.threadId) -and
            ($null -eq $row.turnId -or $identity.turnId -ceq $row.turnId) -and
            ($null -eq $row.workItemId -or $identity.workItemId -ceq $row.workItemId) -and
            ($null -eq $row.executionId -or $identity.executionId -ceq $row.executionId) -and
            ($null -eq $row.storePath -or $identity.storePath -ceq $row.storePath) -and
            ($null -eq (Get-Field $row 'parentTaskId') -or $identity.parentTaskId -ceq $row.parentTaskId)
        })
        if ($null -eq $row.taskId -or $null -eq $row.threadId -or $null -eq $row.turnId -or $matches.Count -ne 1) { $missing+=@($row) }
    }
    return [pscustomobject]@{known=$known;missing=$missing;mask=$mask;complete=($expected.Count -gt 0 -and $missing.Count -eq 0)}
}
function Get-AccountingScopeExpectations($ScopedBindings, $NativeTurns) {
    $result=@($ScopedBindings)
    foreach ($turn in @($NativeTurns)) {
        $anchors=@($ScopedBindings | Where-Object {
            ($null -ne $turn.taskId -and $_.taskId -ceq $turn.taskId) -or
            ($null -eq $turn.taskId -and $null -ne $turn.threadId -and $_.threadId -ceq $turn.threadId)
        })
        foreach ($anchor in $anchors) {
            # Scope claims for an unresolved native identity affect closure but
            # are never used as an invented measurement binding.
            $expected=New-AccountingBinding $turn (@($anchor.sources)+@($turn.sources))
            foreach ($field in @('workItemId','executionId','storePath')) { if ($null -eq $expected.$field) { $expected.$field=$anchor.$field } }
            $expected.evidenceKind='scoped_native_expectation'; $result+=@($expected)
        }
    }
    return @($result)
}

function Get-UsageSum($Entries) {
    $sum = [ordered]@{}
    foreach ($name in $script:TokenFields) { $sum[$name] = [long]0 }
    foreach ($entry in @($Entries)) {
        foreach ($name in $script:TokenFields) {
            $number = [decimal]$sum[$name] + [decimal]$entry.identity.tokenUsage.$name
            if ($number -gt [long]::MaxValue) { throw 'Token sum overflow.' }
            $sum[$name] = [long]$number
        }
    }
    return [pscustomobject]$sum
}
function Add-ExecutionEvidence($State, $Identity, [string]$Kind, [string]$Source, $Complete) {
    $eid = $Identity.executionId
    if (-not $State.ContainsKey($eid)) {
        $State[$eid] = [pscustomobject]@{
            executionId=$eid; workItemId=$Identity.workItemId; storePath=$Identity.storePath
            taskId=$null; parentTaskId=$null; threadId=$null; parentThreadId=$null; parentTurnId=$null
            initialTurns=@(); usageTurns=@(); sources=@(); conflicts=@(); incompleteTransfers=@()
            usageEntries=@(); artifactCount=0; scopeClaims=@(); versionSnapshots=@()
        }
    }
    $execution = $State[$eid]
    $execution.scopeClaims += @([pscustomobject]@{workItemId=$Identity.workItemId; storePath=$Identity.storePath; source=$Source})
    # Execution uniqueness includes usage-only evidence, even outside selected subtree.
    foreach ($name in @('workItemId','storePath','taskId','parentTaskId','threadId','parentThreadId','parentTurnId')) {
        $value = $Identity.$name
        if ($null -eq $value) { continue }
        if ($null -ne $execution.$name -and $execution.$name -cne $value) {
            $execution.conflicts += @([pscustomobject]@{ executionId=$eid; identity=$name; source=$Source; reason='conflicting_execution_identity' })
        } else { $execution.$name = $value }
    }
    if ($Kind -ceq 'usage') {
        if ($null -ne $Identity.turnId) { $execution.usageTurns += @($Identity.turnId) }
    } else {
        $execution.artifactCount++
        # Reservation and transfer carry initial identities; current may point at a later turn.
        if ($Kind -in @('reservation','transfer','capture_initial') -and $null -ne $Identity.turnId) {
            $execution.initialTurns += @($Identity.turnId)
        }
        if ($Kind -ceq 'transfer' -and ($Complete -isnot [bool] -or -not $Complete)) {
            $execution.incompleteTransfers += @($Source)
        }
    }
    $execution.sources += @($Source)
}
function Read-ExecutionEvidence([string]$Directory, $Entries) {
    $state = New-Object System.Collections.Hashtable ([StringComparer]::Ordinal)
    foreach ($capture in @(Read-OriginalUsageCaptures $Directory)) {
        if ($null -eq $capture.binding.executionId) { continue }
        $kind=if ((Get-Field $capture.record 'initial_execution_turn') -ceq $true) { 'capture_initial' } else { 'current' }
        Add-ExecutionEvidence $state $capture.binding $kind $capture.path $null
    }
    # Public retained bindings have no live-source/auth capability. Their bytes
    # are checked by the retention caller's receipts before and after reading.
    foreach ($file in Get-ChildItem -LiteralPath $Directory -Filter 'capture-binding-*.json' -File -ErrorAction SilentlyContinue) {
        $record=Get-Content -LiteralPath $file.FullName -Raw -Encoding UTF8 | ConvertFrom-Json
        if ((Get-Field $record 'schema') -cne 'retained-capture-binding/v1') { throw 'Unknown retained capture binding.' }
        $binding=New-AccountingBinding $record @($file.FullName)
        if ($null -eq $binding.executionId) { continue }
        $kind=if ((Get-Field $record 'initial_execution_turn') -ceq $true) { 'capture_initial' } else { 'current' }
        Add-ExecutionEvidence $state $binding $kind $file.FullName $null
    }
    foreach ($pattern in @('execution-*.json','workitem-transfer-*.json','workitem-current-*.json')) {
        foreach ($file in Get-ChildItem -LiteralPath $Directory -Filter $pattern -File -ErrorAction SilentlyContinue) {
            $record = Get-Content -LiteralPath $file.FullName -Raw -Encoding UTF8 | ConvertFrom-Json
            $identity = Get-BindingIdentity $record
            $kind = if ($pattern -ceq 'execution-*.json') { 'reservation' } elseif ($pattern -ceq 'workitem-transfer-*.json') { 'transfer' } else { 'current' }
            Add-ExecutionEvidence $state $identity $kind $file.FullName (Get-Field $record 'complete')
            # Integrated #18 records preserve full source/candidate WorkItem snapshots.
            # A sourceResult alone is not a criteria snapshot and is never substituted.
            foreach ($field in @('startingSnapshot','candidate')) {
                $document = Get-Field $record $field
                if ($null -ne $document) {
                    $state[$identity.executionId].versionSnapshots += @([pscustomobject]@{
                        document=$document; workItemId=$identity.workItemId; storePath=$identity.storePath
                        source=$file.FullName+'#'+$field
                    })
                }
            }
        }
    }
    foreach ($entry in @($Entries)) {
        foreach ($record in $entry.records) {
            # Counter-free PR112 enrichment does not declare execution identity.
            if ((Get-Field $record 'schema') -ceq 'native-token-profile/v1') { continue }
            $identity = Get-UsageIdentity $record
            if ($null -eq $identity.executionId) { continue }
            # Aliases for ONE native measurement are legitimate task aliases. Preserve
            # canonical execution task if it is an alias; do not mask other task changes.
            if ($state.ContainsKey($identity.executionId)) {
                $existingTask = $state[$identity.executionId].taskId
                if ($null -ne $existingTask -and $entry.AliasTaskIds -ccontains $existingTask) { $identity.taskId = $existingTask }
            }
            Add-ExecutionEvidence $state $identity 'usage' $entry.paths[0] $null
        }
        if ($null -ne $entry.identity.executionId) { $state[$entry.identity.executionId].usageEntries += @($entry) }
    }
    foreach ($execution in $state.Values) {
        $initial = @($execution.initialTurns | Select-Object -Unique)
        if ($initial.Count -gt 1) {
            $execution.conflicts += @([pscustomobject]@{executionId=$execution.executionId; identity='initialTurn'; reason='reservation_transfer_initial_turn_conflict'; source=@($execution.sources)})
        }
        $execution.initialTurns = $initial
    }
    return ,$state
}
function Get-EvidenceJson($Line, [string]$Prefix) {
    if ($Line -isnot [string] -or -not $Line.StartsWith($Prefix,[StringComparison]::Ordinal)) { return $null }
    $value = ConvertFrom-Json -InputObject $Line.Substring($Prefix.Length) -ErrorAction Stop
    if ($value -isnot [pscustomobject]) { throw 'Evidence must be an object.' }
    $version = Get-Field $value 'version'
    if (($version -isnot [int] -and $version -isnot [long]) -or $version -ne 1) { throw 'Evidence version must be integer 1.' }
    return $value
}
function Get-UtcTime($Value) {
    $text = Get-Text $Value
    if ($text -notmatch '(Z|\+00:00)$') { throw 'Explicit UTC timestamp required.' }
    $time = [DateTimeOffset]::MinValue
    if (-not [DateTimeOffset]::TryParse($text,[Globalization.CultureInfo]::InvariantCulture,[Globalization.DateTimeStyles]::None,[ref]$time) -or $time.Offset -ne [TimeSpan]::Zero) { throw 'Invalid UTC timestamp.' }
    return $time
}
function Get-CanonicalJson($Value) {
    # Stable property-order-independent equality for evidence, not a numeric coercion.
    if ($null -eq $Value) { return 'null' }
    if ($Value -is [pscustomobject]) {
        $parts = @()
        foreach ($name in @($Value.PSObject.Properties.Name | Sort-Object -CaseSensitive)) {
            $parts += ((ConvertTo-Json -InputObject $name -Compress) + ':' + (Get-CanonicalJson $Value.$name))
        }
        return '{' + ($parts -join ',') + '}'
    }
    if ($Value -is [array]) { return '[' + (@($Value | ForEach-Object { Get-CanonicalJson $_ }) -join ',') + ']' }
    return ConvertTo-Json -InputObject $Value -Compress -Depth 20
}
# Additive diagnostic reader. Strict family readers above keep their defaults.
function Read-HistoryAccountingEvidence([string]$Directory) {
    $native=@{}; $blocked=@{}; $taskThreads=@{}; $taskBindings=@{}; $taskFamilyClaims=@{}; $blockedTasks=@{}
    $diagnostics=@(); $sources=@(); $artifacts=@()
    $executions=New-Object System.Collections.Hashtable ([StringComparer]::Ordinal)
    # Failure of the root is unavailable, never an observed zero inventory.
    $root=Get-Item -LiteralPath $Directory -ErrorAction Stop
    if (-not $root.PSIsContainer) { throw 'Accounting root unavailable.' }
    $patterns=@('*.usage.json','*.profile.json','execution-*.json','workitem-transfer-*.json','workitem-current-*.json')
    foreach ($pattern in $patterns) {
        $files=@(Get-ChildItem -LiteralPath $Directory -Filter $pattern -File -ErrorAction Stop | Sort-Object FullName)
        foreach ($file in $files) {
            $sources+=@($file.FullName); $record=$null; $key=$null
            try {
                $record=Get-Content -LiteralPath $file.FullName -Raw -Encoding UTF8 -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
                if ($record -isnot [pscustomobject]) { throw 'Invalid record.' }
                # Recover a trustworthy key even when another field is invalid.
                try {
                    $thread=Get-CanonicalId (Get-PairedField $record 'thread_id' 'threadId')
                    $turn=Get-CanonicalId (Get-PairedField $record 'turn_id' 'turnId')
                    $key=$thread+'/'+$turn
                } catch { $key=$null }
                if ($pattern -ceq '*.usage.json') {
                    # Reuse strict native/counter normalization with family fields
                    # removed. Nullable family claims never establish own usage.
                    $plain=[ordered]@{}
                    foreach ($property in $record.PSObject.Properties) { $plain[$property.Name]=$property.Value }
                    foreach ($field in @('work_item_id','execution_id','work_item_store_path')) { $plain[$field]=$null }
                    $plain['role']='unknown'
                    foreach ($pair in @(@('task_id','taskId'),@('thread_id','threadId'),@('turn_id','turnId'),@('parent_task_id','parentTaskId'),@('parent_thread_id','parentThreadId'),@('parent_turn_id','parentTurnId'))) {
                        $plain[$pair[0]]=Get-PairedField $record $pair[0] $pair[1]
                    }
                    $identity=Get-UsageIdentity ([pscustomobject]$plain)
                    if ($null -eq $identity.threadId -or $null -eq $identity.turnId) {
                        $diagnostics+=@([pscustomobject]@{reason='native_identity_missing';source=$file.FullName;nativeKey=$null}); continue
                    }
                    $key=$identity.threadId+'/'+$identity.turnId
                    $claim=Get-HistoryFamilyClaim $record $file.FullName
                    $diagnostics+=@($claim.diagnostics)
                    if (-not $taskFamilyClaims.ContainsKey($identity.taskId)) { $taskFamilyClaims[$identity.taskId]=@() }
                    $taskFamilyClaims[$identity.taskId]+=@($claim)
                    $kind=Get-LedgerCounterKind ([pscustomobject]@{records=@($record)})
                    if ($kind -cne 'turn_token_usage') {
                        $diagnostics+=@([pscustomobject]@{reason='not_comparable_to_native_turn_counter';nativeKey=$key;counterKind=$kind;tokenUsage=$identity.tokenUsage;source=$file.FullName})
                    }
                    $finalMeasurementRecords=@()
                    if ($kind -ceq 'turn_token_usage' -and $identity.final -and $null -ne $identity.tokenUsage) { $finalMeasurementRecords=@($record) }
                    if ($taskThreads.ContainsKey($identity.taskId) -and $taskThreads[$identity.taskId] -cne $identity.threadId) { $blockedTasks[$identity.taskId]=$true }
                    else { $taskThreads[$identity.taskId]=$identity.threadId }
                    if (-not $taskBindings.ContainsKey($identity.taskId)) {
                        $taskBindings[$identity.taskId]=[pscustomobject]@{parentTaskId=$identity.parentTaskId;parentThreadId=$identity.parentThreadId;parentTurnId=$identity.parentTurnId}
                    } else {
                        foreach ($field in @('parentTaskId','parentThreadId','parentTurnId')) {
                            $priorBinding=$taskBindings[$identity.taskId]
                            if ($null -ne $priorBinding.$field -and $null -ne $identity.$field -and $priorBinding.$field -cne $identity.$field) { $blockedTasks[$identity.taskId]=$true }
                            elseif ($null -eq $priorBinding.$field) { $priorBinding.$field=$identity.$field }
                        }
                    }
                    if (-not $native.ContainsKey($key)) {
                        $native[$key]=[pscustomobject]@{native_key=$key;identity=$identity;counterKind=$kind;AliasTaskIds=@($identity.taskId);paths=@($file.FullName);records=@($record);finalMeasurementRecords=$finalMeasurementRecords;familyClaims=@($claim);familyEligible=$false;familyDiagnostics=@()}
                    } else {
                        $prior=$native[$key]; $old=$prior.identity
                        # Aliases are accepted only with consistent native/parent
                        # evidence, as in the existing strict native signature.
                        foreach ($field in @('parentTaskId','parentThreadId','parentTurnId')) {
                            if ($null -ne $old.$field -and $null -ne $identity.$field -and $old.$field -cne $identity.$field) { $blocked[$key]=$true }
                            elseif ($null -eq $old.$field) { $old.$field=$identity.$field }
                        }
                        # Only proven own counters are comparable. Legacy observations
                        # retain identity/metadata claims but cannot replace or veto own.
                        if ($kind -ceq 'turn_token_usage' -and $prior.counterKind -cne 'turn_token_usage') {
                            foreach ($field in @('parentTaskId','parentThreadId','parentTurnId')) {
                                if ($null -eq $identity.$field) { $identity.$field=$old.$field }
                            }
                            $prior.identity=$identity; $prior.counterKind=$kind
                        } elseif ($kind -ceq 'turn_token_usage' -and $prior.counterKind -ceq 'turn_token_usage') {
                        if ($null -ne $old.tokenUsage -and $null -ne $identity.tokenUsage) {
                            if ($old.final -and $identity.final) {
                                if (-not (Compare-AccountingUsage $old.tokenUsage $identity.tokenUsage)) { $blocked[$key]=$true }
                            } elseif ($old.final) {
                                if (-not (Compare-AccountingUsage $old.tokenUsage $identity.tokenUsage -Dominates)) { $blocked[$key]=$true }
                            } elseif ($identity.final) {
                                if (-not (Compare-AccountingUsage $identity.tokenUsage $old.tokenUsage -Dominates)) { $blocked[$key]=$true }
                                $prior.identity=$identity
                            } elseif (Compare-AccountingUsage $identity.tokenUsage $old.tokenUsage -Dominates) { $prior.identity=$identity }
                            elseif (-not (Compare-AccountingUsage $old.tokenUsage $identity.tokenUsage -Dominates)) { $blocked[$key]=$true }
                        } elseif ($null -ne $identity.tokenUsage -and (-not $old.final -or $identity.final)) { $prior.identity=$identity }
                        elseif ($identity.final -and $null -eq $old.tokenUsage) { $prior.identity=$identity }
                        }
                        $prior.finalMeasurementRecords+=@($finalMeasurementRecords)
                        $prior.AliasTaskIds=@(@($prior.AliasTaskIds)+@($identity.taskId) | Sort-Object -Unique)
                        $prior.paths+=@($file.FullName); $prior.records+=@($record); $prior.familyClaims+=@($claim)
                    }
                } elseif ($pattern -ceq '*.profile.json') {
                    if ((Get-Field $record 'schema') -cne 'native-token-profile/v1') { throw 'Unsupported profile.' }
                    $task=Get-CanonicalId (Get-PairedField $record 'task_id' 'taskId')
                    if ($null -eq $key -or -not $native.ContainsKey($key) -or $native[$key].AliasTaskIds -cnotcontains $task) {
                        $diagnostics+=@([pscustomobject]@{reason='profile_without_measurement_anchor';source=$file.FullName;nativeKey=$key}); continue
                    }
                    $native[$key].records+=@($record); $native[$key].paths+=@($file.FullName)
                    # Exact native profiles remain independent final-time evidence.
                    $native[$key].finalMeasurementRecords+=@($record)
                } else {
                    # Partial execution artifacts are metadata/claims, never counters.
                    $claim=Get-HistoryFamilyClaim $record $file.FullName
                    $diagnostics+=@($claim.diagnostics)
                    $nativeRecord=[ordered]@{}
                    foreach ($property in $record.PSObject.Properties) {
                        if ($property.Name -cnotin @('work_item_id','workItemId','execution_id','executionId','work_item_store_path','store_path','storePath')) { $nativeRecord[$property.Name]=$property.Value }
                    }
                    $binding=New-AccountingBinding ([pscustomobject]$nativeRecord) @($file.FullName)
                    $artifacts+=@([pscustomobject]@{binding=$binding;claim=$claim;record=$record;source=$file.FullName;kind=$pattern;complete=(Get-Field $record 'complete')})
                }
            } catch {
                $reason=if ($null -eq $record) { 'source_unavailable' } else { 'invalid_record' }
                $diagnostics+=@([pscustomobject]@{reason=$reason;code='read_or_normalization_failed';source=$file.FullName;nativeKey=$key})
                # Broken sidecars cannot invalidate independently proven counters.
                if ($pattern -ceq '*.usage.json' -and $null -ne $key) { $blocked[$key]=$true }
                if ($pattern -cne '*.profile.json' -and $null -ne $record) {
                    # Contradictory spellings quarantine every recoverable key,
                    # including a key also present in an otherwise valid alias.
                    foreach ($threadField in @('thread_id','threadId')) {
                        foreach ($turnField in @('turn_id','turnId')) {
                            try {
                                $badThread=Get-CanonicalId (Get-Field $record $threadField)
                                $badTurn=Get-CanonicalId (Get-Field $record $turnField)
                                $blocked[$badThread+'/'+$badTurn]=$true
                            } catch { }
                        }
                    }
                    $taskAmbiguous=$false
                    try { $null=Get-PairedField $record 'task_id' 'taskId' } catch { $taskAmbiguous=$true }
                    if ($null -eq $key -or $taskAmbiguous) {
                        foreach ($taskField in @('task_id','taskId')) {
                            try { $badTask=Get-CanonicalId (Get-Field $record $taskField); $blockedTasks[$badTask]=$true } catch { }
                        }
                    }
                }
            }
        }
    }
    # Correlate against the entire source set before family selection. Execution
    # reuse/transfer gaps block family admission only, not an independent own turn.
    foreach ($artifact in $artifacts) {
        $b=$artifact.binding; $eid=$artifact.claim.executionId; $matched=$false
        if ($null -ne $eid) {
            if (-not $executions.ContainsKey($eid)) { $executions[$eid]=@() }
            $executions[$eid]+=@($artifact)
        }
        foreach ($entry in $native.Values) {
            $id=$entry.identity
            $taskMatch=$null -ne $b.taskId -and $entry.AliasTaskIds -ccontains $b.taskId
            $nativeMatch=$null -ne $b.threadId -and $null -ne $b.turnId -and $entry.native_key -ceq ($b.threadId+'/'+$b.turnId)
            if ($taskMatch -and $null -ne $b.threadId -and $b.threadId -cne $id.threadId) { $blockedTasks[$b.taskId]=$true }
            if ($taskMatch) {
                $taskFamilyClaims[$b.taskId]+=@($artifact.claim)
                foreach ($field in @('parentTaskId','parentThreadId','parentTurnId')) {
                    $priorBinding=$taskBindings[$b.taskId]
                    if ($null -ne $b.$field -and $null -ne $priorBinding.$field -and $b.$field -cne $priorBinding.$field) { $blockedTasks[$b.taskId]=$true }
                    elseif ($null -eq $priorBinding.$field) { $priorBinding.$field=$b.$field }
                }
            }
            if ($nativeMatch -and $null -ne $b.taskId -and -not $taskMatch) { $blocked[$entry.native_key]=$true }
            if ($taskMatch -or $nativeMatch) {
                $matched=$true
                $entry.familyClaims+=@($artifact.claim); $entry.paths+=@($artifact.source)
                # Recorded role assignment may enrich a task-bound turn. Effective
                # model/effort/time evidence requires an exact native turn anchor;
                # a reservation's first turn must not profile later turns.
                if ($nativeMatch) {
                    $entry.records+=@($artifact.record)
                    if ((Get-Field $artifact.record 'final') -ceq $true) { $entry.finalMeasurementRecords+=@($artifact.record) }
                }
                elseif ($taskMatch) { $entry.records+=@([pscustomobject]@{role=(Get-Field $artifact.record 'role');roleId=(Get-Field $artifact.record 'roleId');metadataSources=@($artifact.source)}) }
                if ($artifact.kind -ceq 'workitem-transfer-*.json' -and ($artifact.complete -isnot [bool] -or -not $artifact.complete)) {
                    $entry.familyDiagnostics+=@('incomplete_transfer')
                }
            }
        }
        if (-not $matched) {
            $diagnostics+=@([pscustomobject]@{
                reason='artifact_without_measurement_anchor';source=$artifact.source;kind=$artifact.kind
                nativeKey=$(if ($null -ne $b.threadId -and $null -ne $b.turnId) { $b.threadId+'/'+$b.turnId } else { $null })
                taskId=$b.taskId;threadId=$b.threadId;turnId=$b.turnId
                parentTaskId=$b.parentTaskId;parentThreadId=$b.parentThreadId;parentTurnId=$b.parentTurnId
                workItemId=$artifact.claim.workItemId;executionId=$eid;storePath=$artifact.claim.storePath
            })
        }
    }
    foreach ($task in $taskBindings.Keys) {
        $seen=@{}; $cursor=$task
        while ($null -ne $cursor -and $taskBindings.ContainsKey($cursor)) {
            if ($seen.ContainsKey($cursor)) { foreach ($member in $seen.Keys) { $blockedTasks[$member]=$true }; break }
            $seen[$cursor]=$true; $cursor=$taskBindings[$cursor].parentTaskId
        }
    }
    # Include usage-only execution claims in global execution uniqueness checks.
    foreach ($entry in $native.Values) {
        foreach ($claim in $entry.familyClaims) {
            if ($null -eq $claim.executionId) { continue }
            if (-not $executions.ContainsKey($claim.executionId)) { $executions[$claim.executionId]=@() }
            $executions[$claim.executionId]+=@([pscustomobject]@{binding=$entry.identity;claim=$claim;kind='usage';source=$claim.source})
        }
    }
    foreach ($entry in $native.Values) {
        $id=$entry.identity
        foreach ($alias in $entry.AliasTaskIds) {
            foreach ($field in @('workItemId','executionId','storePath')) {
                $values=@($taskFamilyClaims[$alias] | ForEach-Object { $_.$field } | Where-Object { $null -ne $_ } | Sort-Object -Unique -CaseSensitive)
                if ($values.Count -gt 1) { $entry.familyDiagnostics+=@('conflicting_task_family_'+$field) }
            }
        }
        foreach ($field in @('workItemId','executionId','storePath')) {
            $values=@($entry.familyClaims | ForEach-Object { $_.$field } | Where-Object { $null -ne $_ } | Sort-Object -Unique -CaseSensitive)
            if ($values.Count -eq 1) { $id.$field=$values[0] }
            elseif ($values.Count -gt 1) { $id.$field=$null; $entry.familyDiagnostics+=@('conflicting_'+$field) }
        }
        if (@($entry.familyClaims | Where-Object { $_.diagnostics.Count -gt 0 }).Count -gt 0) { $entry.familyDiagnostics+=@('invalid_family_claim') }
        if ($null -ne $id.executionId) {
            $rows=@($executions[$id.executionId])
            foreach ($field in @('workItemId','storePath')) {
                $values=@($rows | ForEach-Object { $_.claim.$field } | Where-Object { $null -ne $_ } | Sort-Object -Unique -CaseSensitive)
                if ($values.Count -gt 1) { $id.$field=$null; $entry.familyDiagnostics+=@('conflicting_execution_'+$field) }
                elseif ($values.Count -eq 1 -and $null -eq $id.$field -and $entry.familyDiagnostics -cnotcontains ('conflicting_'+$field)) { $id.$field=$values[0] }
            }
            if (@($rows | Where-Object { $_.claim.diagnostics.Count -gt 0 }).Count -gt 0) { $entry.familyDiagnostics+=@('invalid_execution_family_claim') }
            if (@($rows | Where-Object { $_.kind -ceq 'workitem-transfer-*.json' -and ((Get-Field $_ 'complete') -isnot [bool] -or -not (Get-Field $_ 'complete')) }).Count -gt 0) { $entry.familyDiagnostics+=@('incomplete_transfer') }
            $threads=@($rows | ForEach-Object { $_.binding.threadId } | Where-Object { $null -ne $_ } | Sort-Object -Unique)
            $foreignTasks=@($rows | Where-Object { $null -ne $_.binding.taskId -and $entry.AliasTaskIds -cnotcontains $_.binding.taskId })
            $initial=@($rows | Where-Object { $_.kind -cin @('execution-*.json','workitem-transfer-*.json') } | ForEach-Object { $_.binding.turnId } | Where-Object { $null -ne $_ } | Sort-Object -Unique)
            if ($threads.Count -gt 1 -or $foreignTasks.Count -gt 0 -or $initial.Count -gt 1) { $entry.familyDiagnostics+=@('execution_identity_conflict') }
        }
        $entry.familyEligible=($null -ne $id.workItemId -and $null -ne $id.executionId -and $null -ne $id.storePath -and $entry.familyDiagnostics.Count -eq 0)
        if ($null -ne $id.parentTaskId -and -not $taskBindings.ContainsKey($id.parentTaskId)) {
            $diagnostics+=@([pscustomobject]@{reason='parent_binding_unregistered';nativeKey=$entry.native_key;parentTaskId=$id.parentTaskId;sources=@($entry.paths)})
        }
        if (-not $entry.familyEligible) {
            foreach ($field in @('workItemId','executionId','storePath')) { if ($null -eq $id.$field) { $entry.familyDiagnostics+=@('missing_'+$field) } }
            $diagnostics+=@([pscustomobject]@{reason='family_binding_unresolved';nativeKey=$entry.native_key;sources=@($entry.paths);details=@($entry.familyDiagnostics)})
        }
        if ($blocked.ContainsKey($entry.native_key) -or @($entry.AliasTaskIds | Where-Object { $blockedTasks.ContainsKey($_) }).Count -gt 0) {
            $blocked[$entry.native_key]=$true
            $diagnostics+=@([pscustomobject]@{reason='native_task_or_counter_conflict';nativeKey=$entry.native_key;sources=@($entry.paths)})
        }
        $entry.paths=@($entry.paths | Sort-Object -Unique -CaseSensitive)
        $entry.familyDiagnostics=@($entry.familyDiagnostics | Sort-Object -Unique -CaseSensitive)
    }
    # Reuse the shared accounting mask. Only true own/native/task conflicts enter
    # it; family claim conflicts above remain separately diagnostic.
    $ownConflicts=@()
    foreach ($nativeKey in $blocked.Keys) {
        $parts=$nativeKey.Split('/')
        $ownConflicts+=@(New-AccountingConflict ([pscustomobject]@{threadId=$parts[0];turnId=$parts[1]}) 'history_native_conflict' @())
    }
    foreach ($task in $blockedTasks.Keys) { $ownConflicts+=@(New-AccountingConflict ([pscustomobject]@{taskId=$task}) 'conflicting_task_history_binding' @()) }
    $mask=Get-AccountingConflictMask @() @($native.Values) $ownConflicts
    $diagnostics=@($diagnostics | Sort-Object { Get-Field $_ 'reason' }, { Get-Field $_ 'nativeKey' }, { Get-Field $_ 'source' })
    return [pscustomobject]@{entries=@($native.Values | Sort-Object native_key);eligibleNativeKeys=@($native.Keys | Where-Object { $mask.nativeKeys -cnotcontains $_ } | Sort-Object);diagnostics=$diagnostics;sourcePaths=$sources;sourcePatterns=$patterns}
}
function Get-HistoryFamilyClaim($Record, [string]$Source) {
    $claim=[ordered]@{workItemId=$null;executionId=$null;storePath=$null;source=$Source;diagnostics=@()}
    foreach ($pair in @(@('workItemId','work_item_id','workItemId'),@('executionId','execution_id','executionId'))) {
        try {
            $value=Get-PairedField $Record $pair[1] $pair[2]
            $claim[$pair[0]]=Get-Text $value -Optional
        } catch { $claim.diagnostics+=@([pscustomobject]@{reason='invalid_family_claim';field=$pair[0];source=$Source}) }
    }
    $stores=@()
    foreach ($field in @('work_item_store_path','store_path','storePath')) {
        try { $value=Get-CanonicalPath (Get-Field $Record $field) -Optional; if ($null -ne $value) { $stores+=@($value) } }
        catch { $claim.diagnostics+=@([pscustomobject]@{reason='invalid_family_claim';field='storePath';source=$Source}) }
    }
    $stores=@($stores | Sort-Object -Unique -CaseSensitive)
    if ($stores.Count -eq 1) { $claim.storePath=$stores[0] }
    elseif ($stores.Count -gt 1) { $claim.diagnostics+=@([pscustomobject]@{reason='invalid_family_claim';field='storePath';source=$Source}) }
    return [pscustomobject]$claim
}
Export-ModuleMember -Function *
