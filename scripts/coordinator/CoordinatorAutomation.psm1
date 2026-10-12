Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Invoke-CoordinatorPrivate($Module, [string]$Name, [object[]]$Arguments) {
    & $Module { param($n, $a) $command = Get-Command $n -CommandType Function -ErrorAction Stop; & $command @a } $Name $Arguments
}

function Get-AutomationValue($Object, [string]$Name, $Default = $null) {
    if ($null -eq $Object) { return $Default }
    if ($Object -is [System.Collections.IDictionary]) {
        if ($Object.Contains($Name)) { return $Object[$Name] }
        return $Default
    }
    $property = $Object.PSObject.Properties[$Name]
    if ($null -ne $property) { return $property.Value }
    return $Default
}

function Get-AutomationHash([string]$Text) {
    $sha = [Security.Cryptography.SHA256]::Create()
    try { return ([BitConverter]::ToString($sha.ComputeHash([Text.UTF8Encoding]::new($false).GetBytes($Text)))).Replace('-', '').ToLowerInvariant() }
    finally { $sha.Dispose() }
}

function Get-AutomationBytesHash([byte[]]$Bytes) {
    $sha = [Security.Cryptography.SHA256]::Create()
    try { return ([BitConverter]::ToString($sha.ComputeHash($Bytes))).Replace('-', '').ToLowerInvariant() }
    finally { $sha.Dispose() }
}

function Write-AutomationJson([string]$Path, $Value) {
    $directory = [IO.Path]::GetDirectoryName([IO.Path]::GetFullPath($Path))
    [void][IO.Directory]::CreateDirectory($directory)
    $temporary = $Path + '.' + [guid]::NewGuid().ToString('N') + '.tmp'
    try {
        [IO.File]::WriteAllText($temporary, (ConvertTo-Json -InputObject $Value -Depth 80 -Compress), [Text.UTF8Encoding]::new($false))
        if ([IO.File]::Exists($Path)) { [IO.File]::Replace($temporary, $Path, $null) }
        else { [IO.File]::Move($temporary, $Path) }
    } finally { if ([IO.File]::Exists($temporary)) { [IO.File]::Delete($temporary) } }
}

function Read-AutomationJson([string]$Path, $Default) {
    if (-not [IO.File]::Exists($Path)) { return $Default }
    return [IO.File]::ReadAllText($Path, [Text.UTF8Encoding]::new($false, $true)) | ConvertFrom-Json -ErrorAction Stop
}

function Get-AutomationStoreModule($Config) {
    $module = Import-Module (Join-Path $Config.RepositoryRoot 'scripts/workitems/WorkItemStore.psm1') -PassThru -Force
    return $module
}

function Get-AutomationStoreSnapshot($Config) {
    $module = Get-AutomationStoreModule $Config
    $path = Invoke-CoordinatorPrivate $module 'Resolve-WorkItemStorePath' @($Config.WorkItemStorePath, $Config.RepositoryRoot)
    $lock = Invoke-CoordinatorPrivate $module 'Enter-WorkItemStoreLock' @($path, 5000)
    try { return Invoke-CoordinatorPrivate $module 'Get-WorkItemStoreSnapshot' @($path, $Config.RepositoryRoot) }
    finally { Invoke-CoordinatorPrivate $module 'Exit-WorkItemStoreLock' @($lock) }
}

function Import-CoordinatorWorkItemOutbox($Config) {
    $module = Get-AutomationStoreModule $Config
    $path = Invoke-CoordinatorPrivate $module 'Resolve-WorkItemStorePath' @($Config.WorkItemStorePath, $Config.RepositoryRoot)
    $lock = Invoke-CoordinatorPrivate $module 'Enter-WorkItemStoreLock' @($path, 5000)
    try {
        $snapshot = Invoke-CoordinatorPrivate $module 'Get-WorkItemStoreSnapshot' @($path, $Config.RepositoryRoot)
        Invoke-CoordinatorPrivate $module 'Resolve-WorkItemStoreOutbox' @($path, $snapshot)
        $outbox = Invoke-CoordinatorPrivate $module 'Get-WorkItemStoreOutbox' @($path)
        foreach ($intent in @($outbox.intents | Where-Object { $_.state -ceq 'published' } | Sort-Object createdAtUtc, intentId)) {
            $item = Get-AutomationValue $intent 'item'
            if (-not $item) { throw "Published outbox intent '$($intent.intentId)' lacks immutable item." }
            $revision = [string](Get-AutomationValue $intent 'candidateRevision' (Get-AutomationValue $intent 'revision'))
            $id = [string](Get-AutomationValue $intent 'workItemId' (Get-AutomationValue $intent 'sourceId'))
            $source = [string](Get-AutomationValue $intent 'intentId')
            if (-not $source) { $source = 'workitem:' + $id + ':' + $revision }
            Add-CoordinatorEvent -Path $Config.EventJournalPath -Kind workitem_changed -SourceId $source -Payload @{ workItemId = $id; revision = $revision; item = $item } | Out-Null
            $response = Get-AutomationValue (Get-AutomationValue $item 'humanInteraction') 'response'
            if ($response) {
                $responseHash = Get-AutomationHash (ConvertTo-Json -InputObject $response -Depth 30 -Compress)
                Add-CoordinatorEvent -Path $Config.EventJournalPath -Kind human_response -SourceId ('human:' + $id + ':' + $revision + ':' + $responseHash) -Payload @{ workItemId = $id; revision = $revision; response = $response } | Out-Null
            }
        }
    } finally { Invoke-CoordinatorPrivate $module 'Exit-WorkItemStoreLock' @($lock) }
}

function Import-CoordinatorReminderFiles($Config) {
    $directory = Join-Path $Config.DataDirectory 'planning-wake-events'
    if (-not (Test-Path -LiteralPath $directory -PathType Container)) { return }
    foreach ($file in @(Get-ChildItem -LiteralPath $directory -Filter '*.json' -File | Sort-Object Name)) {
        $record = Read-AutomationJson $file.FullName $null
        $eventId = [string](Get-AutomationValue $record 'eventId')
        if ($eventId) { Add-CoordinatorEvent -Path $Config.EventJournalPath -Kind reminder_due -SourceId $eventId -Payload $record | Out-Null }
    }
}

function Get-AutomationResultFiles($Config) {
    $files = @()
    foreach ($directory in @($Config.ResultDirectories)) {
        if ($directory -and (Test-Path -LiteralPath $directory -PathType Container)) {
            $files += @(Get-ChildItem -LiteralPath $directory -Filter '*.json' -File | Where-Object { $_.Name -notlike '*.job.json' -and $_.Name -notlike '*.window.json' -and $_.Name -notlike '*.go.json' })
        }
    }
    return ,@($files | Sort-Object FullName -Unique)
}

function Import-CoordinatorNativeResults($Config) {
    $cursorPath = Join-Path $Config.DataDirectory 'result-import-cursor.json'
    $cursor = Read-AutomationJson $cursorPath ([pscustomobject]@{ results = @() })
    $seen = @{}
    foreach ($entry in @($cursor.results)) { $seen[[string]$entry.key] = $true }
    $changed = $false
    foreach ($file in @(Get-AutomationResultFiles $Config)) {
        $jobPath = $file.FullName + '.job.json'
        if (-not (Test-Path -LiteralPath $jobPath -PathType Leaf)) { continue }
        $result = Read-AutomationJson $file.FullName $null
        $job = Read-AutomationJson $jobPath $null
        if (-not $result -or -not $job) { continue }
        $task = [string](Get-AutomationValue $job 'task_id')
        $dispatch = [string](Get-AutomationValue $job 'dispatch_id')
        if (-not $task -or -not $dispatch -or (Get-AutomationValue $result 'task_id') -cne $task) { continue }
        $resultDispatch = [string](Get-AutomationValue $result 'dispatch_id')
        if ($resultDispatch -and $resultDispatch -cne $dispatch) { continue }
        if (-not ((Get-AutomationValue $result 'terminal_outcome') -or (Get-AutomationValue $result 'success') -or (Get-AutomationValue $result 'error'))) { continue }
        $hash = Get-AutomationHash ([Convert]::ToBase64String([IO.File]::ReadAllBytes($file.FullName)))
        $key = $task + '/' + $dispatch + '/' + $hash
        $registry = Join-Path $Config.RepositoryRoot 'scripts/coordinator/Register-CoordinatorExecution.ps1'
        try { & $registry -Action Release -DataDirectory $Config.RegistryDirectory -TaskId $task -DispatchId $dispatch -ResultPath $file.FullName | Out-Null }
        catch { if ($_.Exception.Message -notlike 'ExecutionReservationNotFound*') { continue } }
        if (-not $seen.ContainsKey($key)) {
            Add-CoordinatorEvent -Path $Config.EventJournalPath -Kind return_received -SourceId ('starter:' + $key) -Payload @{ taskId = $task; dispatchId = $dispatch; resultPath = $file.FullName; resultHash = $hash; result = $result; workItemId = (Get-AutomationValue $job 'work_item_id') } | Out-Null
            $seen[$key] = $true
            $changed = $true
        }
    }
    if ($changed) { Write-AutomationJson $cursorPath @{ results = @($seen.Keys | Sort-Object | ForEach-Object { @{ key = $_ } }) } }
}

function ConvertTo-AutomationGuid([string]$Value) {
    if ([string]::IsNullOrWhiteSpace($Value)) { return $null }
    $parsed = [guid]::Empty
    if ([guid]::TryParse($Value, [ref]$parsed)) { return $parsed.ToString('D') }
    return $Value
}

function Get-AutomationInventory($Config, $Session) {
    $unknown = $false
    $entries = @()
    $registryPath = Join-Path $Config.RegistryDirectory 'executions.json'
    $registered = @()
    if (Test-Path -LiteralPath $registryPath -PathType Leaf) { $registered = @(Read-AutomationJson $registryPath @()) }
    else { $unknown = $true }
    foreach ($entry in $registered) {
        $entries += @{ executionId = (ConvertTo-AutomationGuid ([string]$entry.executionId)); taskId = (ConvertTo-AutomationGuid ([string]$entry.taskId)); dispatchId = (ConvertTo-AutomationGuid ([string](Get-AutomationValue $entry 'dispatchId'))); nativeThreadId = [string](Get-AutomationValue $entry 'nativeThreadId'); role = [string](Get-AutomationValue $entry 'role' 'unknown'); resultPath = [string](Get-AutomationValue $entry 'resultPath'); payloadHash = [string](Get-AutomationValue $entry 'payloadHash'); state = [string](Get-AutomationValue $entry 'state') }
    }
    if ($Config.NativeInventoryPath -and (Test-Path -LiteralPath $Config.NativeInventoryPath -PathType Leaf)) {
        try {
            $native = Read-AutomationJson $Config.NativeInventoryPath $null
            $rawEntries = Get-AutomationValue $native 'executions' $native
            foreach ($entry in @($rawEntries)) {
                $entries += @{ executionId = (ConvertTo-AutomationGuid ([string](Get-AutomationValue $entry 'executionId'))); taskId = (ConvertTo-AutomationGuid ([string](Get-AutomationValue $entry 'taskId'))); dispatchId = (ConvertTo-AutomationGuid ([string](Get-AutomationValue $entry 'dispatchId'))); nativeThreadId = [string](Get-AutomationValue $entry 'nativeThreadId'); role = [string](Get-AutomationValue $entry 'role' 'unknown'); resultPath = [string](Get-AutomationValue $entry 'resultPath'); payloadHash = [string](Get-AutomationValue $entry 'payloadHash'); state = [string](Get-AutomationValue $entry 'state' 'unknown') }
            }
        } catch { $unknown = $true }
    } else { $unknown = $true }
    if (-not $Config.ResultDirectories.Count -or -not $Config.CompleteEpoch) { $unknown = $true }
    foreach ($directory in @($Config.ResultDirectories)) { if (-not $directory -or -not (Test-Path -LiteralPath $directory -PathType Container)) { $unknown = $true } }
    foreach ($file in @(Get-AutomationResultFiles $Config)) {
        $jobPath = $file.FullName + '.job.json'
        if (-not (Test-Path -LiteralPath $jobPath -PathType Leaf)) { continue }
        try {
            $job = Read-AutomationJson $jobPath $null
            $task = ConvertTo-AutomationGuid ([string](Get-AutomationValue $job 'task_id'))
            $dispatch = ConvertTo-AutomationGuid ([string](Get-AutomationValue $job 'dispatch_id'))
            $matches = @($entries | Where-Object { $_.taskId -ceq $task -or ($dispatch -and $_.dispatchId -ceq $dispatch) })
            if (-not $matches.Count) { $entries += @{ executionId = $(if ($dispatch) { $dispatch } else { $task }); taskId = $task; dispatchId = $dispatch; nativeThreadId = $null; role = [string](Get-AutomationValue $job 'role' 'unknown'); resultPath = [string](Get-AutomationValue $job 'result_file'); payloadHash = [string](Get-AutomationValue $job 'payload_hash'); state = 'unknown' } }
        } catch { $unknown = $true }
    }
    if ($Config.AccountingDirectory -and (Test-Path -LiteralPath $Config.AccountingDirectory -PathType Container)) {
        foreach ($file in @(Get-ChildItem -LiteralPath $Config.AccountingDirectory -Filter '*.json' -File)) {
            try {
                $record = Read-AutomationJson $file.FullName $null
                $task = ConvertTo-AutomationGuid ([string](Get-AutomationValue $record 'task_id'))
                $thread = [string](Get-AutomationValue $record 'thread_id')
                if (-not $task -or -not $thread) { continue }
                foreach ($entry in @($entries | Where-Object { $_.taskId -ceq $task -or ($_.nativeThreadId -and $_.nativeThreadId -ceq $thread) })) {
                    if ($entry.taskId -and $entry.taskId -cne $task) { $entry.state = 'unknown'; $unknown = $true }
                    else { $entry.taskId = $task; $entry.nativeThreadId = $thread }
                }
            } catch { $unknown = $true }
        }
    }
    if ($Session.NativeThreadId) {
        $task = ConvertTo-AutomationGuid ([string]$Config.TaskId)
        if (-not $task) {
            $bindingPath = Join-Path $Config.RegistryDirectory 'coordinator-task-binding.json'
            $binding = Read-AutomationJson $bindingPath $null
            if (-not $binding) { $task = [guid]::NewGuid().ToString('D'); Write-AutomationJson $bindingPath @{ logicalSessionId = $Session.LogicalSessionId; taskId = $task } }
            else { $task = ConvertTo-AutomationGuid ([string]$binding.taskId); if ($binding.logicalSessionId -cne $Session.LogicalSessionId) { $unknown = $true } }
        }
        $Config.TaskId = $task
        $registryScript = Join-Path $Config.RepositoryRoot 'scripts/coordinator/Register-CoordinatorExecution.ps1'
        try { & $registryScript -Action RegisterNative -DataDirectory $Config.RegistryDirectory -TaskId $task -NativeThreadId $Session.NativeThreadId -Role koordinator -State active | Out-Null }
        catch { $unknown = $true }
        $entries = @($entries | Where-Object { (ConvertTo-AutomationGuid ([string]$_.taskId)) -cne $task })
        $entries += @{ executionId = $task; taskId = $task; dispatchId = $null; nativeThreadId = [string]$Session.NativeThreadId; role = 'koordinator'; resultPath = $null; payloadHash = $null; state = 'active' }
    } else { $unknown = $true }

    $unique = @{}
    $aliases = @{}
    foreach ($entry in $entries) {
        $entry.executionId = ConvertTo-AutomationGuid ([string]$entry.executionId)
        $entry.taskId = ConvertTo-AutomationGuid ([string]$entry.taskId)
        $entry.dispatchId = ConvertTo-AutomationGuid ([string]$entry.dispatchId)
        if (-not $entry.executionId -or -not $entry.taskId) { $unknown = $true; continue }
        $keys = @('exec:' + $entry.executionId, 'task:' + $entry.taskId)
        if ($entry.dispatchId) { $keys += 'dispatch:' + $entry.dispatchId }
        if ($entry.nativeThreadId) { $keys += 'thread:' + $entry.nativeThreadId }
        $target = $null
        foreach ($key in $keys) { if ($aliases.ContainsKey($key)) { $target = $aliases[$key]; break } }
        if ($target) {
            $prior = $unique[$target]
            if (($prior.taskId -and $entry.taskId -and $prior.taskId -cne $entry.taskId) -or ($prior.nativeThreadId -and $entry.nativeThreadId -and $prior.nativeThreadId -cne $entry.nativeThreadId) -or ($prior.dispatchId -and $entry.dispatchId -and $prior.dispatchId -cne $entry.dispatchId)) { $prior.state = 'unknown'; $unknown = $true }
            else {
                foreach ($field in @('dispatchId', 'nativeThreadId', 'resultPath', 'payloadHash')) { if (-not $prior[$field] -and $entry[$field]) { $prior[$field] = $entry[$field] } }
                if ($entry.state -eq 'unknown') { $prior.state = 'unknown' }
            }
        } else { $target = [string]$entry.executionId; $unique[$target] = $entry }
        foreach ($key in $keys) { $aliases[$key] = $target }
    }
    if ($Config.NativeInventoryPath -and $Config.CompleteEpoch -and (Test-Path -LiteralPath $Config.NativeInventoryPath -PathType Leaf)) {
        $registryScript = Join-Path $Config.RepositoryRoot 'scripts/coordinator/Register-CoordinatorExecution.ps1'
        $confirm = @($unique.Values | Where-Object { $_.state -ne 'terminal' })
        try {
            & $registryScript -Action ConfirmInventory -DataDirectory $Config.RegistryDirectory -InventoryEpoch $Config.CompleteEpoch -InventoryJson (ConvertTo-Json -InputObject $confirm -Depth 20) | Out-Null
            $count = & $registryScript -Action Count -DataDirectory $Config.RegistryDirectory -Capacity $Config.Capacity
            if (-not $count.CapacityKnown) { $unknown = $true }
        } catch { $unknown = $true }
    }
    return [pscustomobject]@{ Entries = @($unique.Values); Unknown = $unknown }
}

function Get-AutomationTaskSpecification($Config, $Item) {
    $spec = Get-AutomationValue $Item 'specification'
    if ($spec -is [string]) { return $spec }
    if ($spec -and (Get-AutomationValue $spec 'inline')) { return [string]$spec.inline }
    $file = [string](Get-AutomationValue $spec 'path')
    if (-not $file) { $file = [string](Get-AutomationValue $Item 'specificationPath') }
    if ($file) {
        $path = if ([IO.Path]::IsPathRooted($file)) { $file } else { Join-Path $Config.RepositoryRoot $file }
        return [IO.File]::ReadAllText([IO.Path]::GetFullPath($path), [Text.UTF8Encoding]::new($false, $true))
    }
    return ''
}

function Get-AutomationLiveSpecHash($Config, $Item) {
    $owner = Get-AutomationValue $Item 'owner'
    $value = [ordered]@{ id = [string](Get-AutomationValue $Item 'id'); owner = $owner; description = [string](Get-AutomationValue $Item 'description'); specificationText = (Get-AutomationTaskSpecification $Config $Item); acceptanceCriteria = (Get-AutomationValue $Item 'acceptanceCriteria' @()) }
    return Get-AutomationHash (ConvertTo-Json -InputObject $value -Depth 50 -Compress)
}

function Get-AutomationGeneration($Config, $Item, [string]$Purpose) {
    $path = Join-Path $Config.DataDirectory 'workitem-generations.json'
    $state = Read-AutomationJson $path ([pscustomobject]@{ items = @(); appliedReworks = @() })
    $items = @(Get-AutomationValue $state 'items' @())
    $appliedReworks = @(Get-AutomationValue $state 'appliedReworks' @())
    $records = @($items | Where-Object { $_.workItemId -ceq [string]$Item.id -and $_.purpose -ceq $Purpose })
    if ($records.Count -gt 1) { throw 'GenerationIdentityConflict' }
    $liveHash = Get-AutomationLiveSpecHash $Config $Item
    if ($records.Count -eq 0) {
        $record = @{ workItemId = [string]$Item.id; purpose = $Purpose; generation = 1; contentHash = $liveHash; updatedAtUtc = [DateTime]::UtcNow.ToString('o') }
        Write-AutomationJson $path @{ items = @($items) + @($record); appliedReworks = @($appliedReworks) }
        return 1
    }
    if ([string]$records[0].contentHash -cne $liveHash) { throw 'DispatchInputConflict: specification changed without explicit rework.' }
    return [int]$records[0].generation
}

function Request-CoordinatorRework($Config, [string]$WorkItemId, [string]$Purpose, [int]$PriorGeneration, [string]$PriorExecutionId, [string]$Reason, $EffectContext) {
    if ($Purpose -cne 'teamleiter-workitem' -or [string]::IsNullOrWhiteSpace($Reason)) { throw 'ReworkRequestInvalid' }
    $dispatchModule = Import-Module (Join-Path $PSScriptRoot 'CoordinatorDispatch.psm1') -PassThru -Force
    $identity = & $dispatchModule { param($w, $p, $g) Get-CoordinatorDispatchIdentity $w $p $g } $WorkItemId $Purpose $PriorGeneration
    if ($identity.ExecutionId -cne $PriorExecutionId) { throw 'ReworkPriorExecutionMismatch' }
    $dispatchPath = Join-Path $Config.DataDirectory 'dispatch-journal.json'
    $prior = & $dispatchModule { param($p, $id) Get-CoordinatorDispatch -JournalPath $p -ExecutionId $id } $dispatchPath $PriorExecutionId
    if (-not $prior -or $prior.state -cne 'Returned' -or -not $prior.terminalDecision) { throw 'ReworkPriorExecutionNotTerminal' }
    $path = Join-Path $Config.DataDirectory 'workitem-generations.json'
    $state = Read-AutomationJson $path ([pscustomobject]@{ items = @(); appliedReworks = @() })
    $items = @(Get-AutomationValue $state 'items' @())
    $appliedReworks = @(Get-AutomationValue $state 'appliedReworks' @())
    $matches = @($items | Where-Object { $_.workItemId -ceq $WorkItemId -and $_.purpose -ceq $Purpose })
    if ($matches.Count -ne 1) { throw 'ReworkGenerationConflict' }
    $effectId = [string](Get-AutomationValue $EffectContext 'effectId')
    $boundContext = [ordered]@{ effectId = $effectId; executionId = [string](Get-AutomationValue $EffectContext 'executionId'); requestId = [string](Get-AutomationValue $EffectContext 'requestId'); threadId = [string](Get-AutomationValue $EffectContext 'threadId'); turnId = [string](Get-AutomationValue $EffectContext 'turnId'); eventId = [string](Get-AutomationValue $EffectContext 'eventId'); inputHash = [string](Get-AutomationValue $EffectContext 'inputHash'); planHash = [string](Get-AutomationValue $EffectContext 'planHash'); ordinal = [int](Get-AutomationValue $EffectContext 'ordinal'); baseRevision = [string](Get-AutomationValue $EffectContext 'baseRevision') }
    $operation = [ordered]@{ workItemId = $WorkItemId; purpose = $Purpose; priorGeneration = $PriorGeneration; priorExecutionId = $PriorExecutionId; reason = $Reason; sourceEventId = [string](Get-AutomationValue $EffectContext 'eventId'); effectId = $effectId; context = $boundContext }
    $operationHash = Get-AutomationHash (ConvertTo-Json -InputObject $operation -Depth 30 -Compress)
    $receipts = @($appliedReworks | Where-Object { $_.effectId -ceq $effectId })
    if ($receipts.Count) {
        if ($receipts.Count -ne 1 -or $receipts[0].operationHash -cne $operationHash) { throw 'EffectIdentityConflict' }
        return $receipts[0]
    }
    if ([int]$matches[0].generation -ne $PriorGeneration) { throw 'ReworkGenerationConflict' }
    $item = @(Get-AutomationStoreSnapshot $Config).Document.items | Where-Object { $_.id -ceq $WorkItemId } | Select-Object -First 1
    if (-not $item) { throw 'ReworkWorkItemMissing' }
    $nextGeneration = $PriorGeneration + 1
    $newIdentity = & $dispatchModule { param($w, $p, $g) Get-CoordinatorDispatchIdentity $w $p $g } $WorkItemId $Purpose $nextGeneration
    $revision = [string](Get-AutomationValue $EffectContext 'baseRevision')
    $receipt = [pscustomobject]@{ effectId = $effectId; state = 'published'; workItemId = $WorkItemId; purpose = $Purpose; priorExecutionId = $PriorExecutionId; previousGeneration = $PriorGeneration; nextGeneration = $nextGeneration; contentHash = (Get-AutomationLiveSpecHash $Config $item); sourceEventId = $operation.sourceEventId; reason = $Reason; operationHash = $operationHash; nextExecutionId = $newIdentity.ExecutionId; previousRevision = $revision; candidateRevision = $revision; executionId = [string](Get-AutomationValue $EffectContext 'executionId'); requestId = [string](Get-AutomationValue $EffectContext 'requestId'); threadId = [string](Get-AutomationValue $EffectContext 'threadId'); turnId = [string](Get-AutomationValue $EffectContext 'turnId'); eventId = [string](Get-AutomationValue $EffectContext 'eventId'); inputHash = [string](Get-AutomationValue $EffectContext 'inputHash'); planHash = [string](Get-AutomationValue $EffectContext 'planHash'); ordinal = [int](Get-AutomationValue $EffectContext 'ordinal') }
    $matches[0].generation = $nextGeneration
    $matches[0].contentHash = $receipt.contentHash
    $matches[0].updatedAtUtc = [DateTime]::UtcNow.ToString('o')
    Write-AutomationJson $path @{ items = @($items); appliedReworks = @($appliedReworks) + @($receipt) }
    return $receipt
}

function Get-AutomationEffectPlan($Dispatch, $Decision, $Session) {
    if ((Get-AutomationValue $Decision 'effectPlanStatus') -cne 'Complete') { throw 'EffectPlanMissingOrInvalid' }
    $plan = Get-AutomationValue $Decision 'effectPlan'
    $payload = [string](Get-AutomationValue $Decision 'planPayloadBase64')
    if (-not $plan -or -not $payload) { throw 'EffectPlanMissingOrInvalid' }
    $bytes = [Convert]::FromBase64String($payload)
    $text = [Text.UTF8Encoding]::new($false, $true).GetString($bytes)
    $decoded = ConvertFrom-Json -InputObject $text -ErrorAction Stop
    foreach ($pair in @(@('executionId', $Dispatch.executionId), @('requestId', $Dispatch.requestId), @('inputHash', $Dispatch.inputHash), @('eventId', [string]$Dispatch.input.eventId))) {
        if ([string](Get-AutomationValue $plan $pair[0]) -cne [string]$pair[1]) { throw "EffectPlanBindingMismatch:$($pair[0])" }
    }
    if ([string]$plan.baseRevision -cne [string]$Dispatch.input.storeRevision -or [string]$plan.logicalSessionId -cne [string]$Dispatch.input.logicalSessionId -or [string]$plan.threadId -cne [string]$Session.NativeThreadId) { throw 'EffectPlanBindingMismatch:baseRevision/session/thread' }
    $body = [ordered]@{ version = [string]$plan.version; logicalSessionId = [string]$plan.logicalSessionId; threadId = [string]$plan.threadId; turnId = [string]$plan.turnId; requestId = [string]$plan.requestId; eventId = [string]$plan.eventId; executionId = [string]$plan.executionId; inputHash = [string]$plan.inputHash; baseRevision = [string]$plan.baseRevision; disposition = [string]$plan.disposition; reason = [string]$plan.reason; commands = @($plan.commands) }
    if ((ConvertTo-Json -InputObject $decoded -Depth 70 -Compress) -cne (ConvertTo-Json -InputObject $body -Depth 70 -Compress)) { throw 'EffectPlanPayloadMismatch' }
    if ((Get-AutomationBytesHash $bytes) -cne [string]$plan.planHash) { throw 'EffectPlanHashMismatch' }
    if ((Get-AutomationValue $plan 'disposition') -notin @('apply', 'no_change')) { throw 'EffectPlanDispositionInvalid' }
    if ([string]::IsNullOrWhiteSpace([string]$plan.reason)) { throw 'EffectPlanReasonMissing' }
    $commands = @($plan.commands)
    if (($plan.disposition -ceq 'no_change' -and $commands.Count) -or ($plan.disposition -ceq 'apply' -and -not $commands.Count)) { throw 'EffectPlanDispositionInvalid' }
    for ($index = 0; $index -lt $commands.Count; $index++) {
        if ([int]$commands[$index].ordinal -ne $index) { throw 'EffectPlanOrdinalInvalid' }
        $expected = Get-AutomationHash ([string]$Dispatch.executionId + "`n" + [string]$Dispatch.inputHash + "`n" + $index)
        if ([string]$commands[$index].effectId -cne $expected) { throw 'EffectPlanEffectIdInvalid' }
        if ($commands[$index].kind -ceq 'set_workitem') {
            if ([string]::IsNullOrWhiteSpace([string]$commands[$index].id) -or $commands[$index].isNew -isnot [bool] -or $null -eq $commands[$index].item -or [string]$commands[$index].item.id -cne [string]$commands[$index].id) { throw 'EffectSetWorkItemInvalid' }
        } elseif ($commands[$index].kind -ceq 'request_rework') {
            if ([string]$commands[$index].purpose -cne 'teamleiter-workitem' -or [string]::IsNullOrWhiteSpace([string]$commands[$index].reason) -or [string]::IsNullOrWhiteSpace([string]$commands[$index].workItemId) -or [string]::IsNullOrWhiteSpace([string]$commands[$index].priorExecutionId) -or [int]$commands[$index].priorGeneration -lt 1) { throw 'EffectRequestReworkInvalid' }
        } else { throw 'EffectCommandKindUnsupported' }
    }
    return [pscustomobject]@{ Plan = $plan; Payload = $payload; PayloadHash = Get-AutomationBytesHash $bytes }
}

function Get-AutomationHistoryDecision($Session, $Dispatch, [string]$Fingerprint) {
    $matches = @($Session.RequestHistory | Where-Object { (Get-AutomationValue $_ 'requestId') -ceq [string]$Dispatch.requestId })
    if ($matches.Count -eq 0) { throw 'RequestHistoryMissing' }
    if ($matches.Count -ne 1) { throw 'RequestHistoryAmbiguous' }
    $entry = $matches[0]
    if ([string]::IsNullOrWhiteSpace([string](Get-AutomationValue $entry 'fingerprint')) -or [string](Get-AutomationValue $entry 'fingerprint') -cne $Fingerprint) { throw 'RequestHistoryFingerprintMismatch' }
    $thread = [string](Get-AutomationValue $entry 'threadId')
    $turn = [string](Get-AutomationValue $entry 'turnId')
    $decision = Get-AutomationValue $entry 'decision'
    $outcome = [string](Get-AutomationValue $entry 'outcome')
    if (-not $thread -or -not $turn -or -not $decision -or $outcome -notin @('completed', 'failed', 'interrupted')) { throw 'RequestHistoryNotTerminal' }
    if ([string](Get-AutomationValue $decision 'requestId') -cne [string]$Dispatch.requestId -or [string](Get-AutomationValue $decision 'turnId') -cne $turn -or [string](Get-AutomationValue $decision 'outcome') -cne $outcome -or $thread -cne [string]$Session.NativeThreadId) { throw 'RequestHistoryDecisionBindingMismatch' }
    if ((Get-AutomationValue $entry 'effectMode') -cne 'coordinator-effects-v1' -or (Get-AutomationValue $entry 'executionId') -cne $Dispatch.executionId -or (Get-AutomationValue $entry 'eventId') -cne $Dispatch.input.eventId -or (Get-AutomationValue $entry 'inputHash') -cne $Dispatch.inputHash -or (Get-AutomationValue $entry 'baseRevision') -cne $Dispatch.input.storeRevision) { throw 'RequestHistoryEffectBindingMismatch' }
    return [pscustomobject]@{ Entry = $entry; Decision = $decision; Outcome = $outcome; ThreadId = $thread; TurnId = $turn }
}

function Get-AutomationEffectState($Config) {
    $path = Join-Path $Config.DataDirectory 'automation-effects.json'
    return [pscustomobject]@{ Path = $path; Data = (Read-AutomationJson $path ([pscustomobject]@{ executions = @() })) }
}

function Get-AutomationEffectRecord($Config, $Dispatch, $PlanInfo) {
    $state = Get-AutomationEffectState $Config
    $records = @(Get-AutomationValue $state.Data 'executions' @() | Where-Object { $_.executionId -ceq $Dispatch.executionId })
    if ($records.Count -gt 1) { throw 'AutomationEffectIdentityConflict' }
    if (-not $records.Count) {
        $record = [pscustomobject]@{ executionId = [string]$Dispatch.executionId; inputHash = [string]$Dispatch.inputHash; eventId = [string]$Dispatch.input.eventId; planHash = [string]$PlanInfo.Plan.planHash; planPayloadBase64 = $PlanInfo.Payload; commands = @($PlanInfo.Plan.commands); receipts = @(); noChangeReceipt = $null; state = 'Prepared'; lastError = $null; updatedAtUtc = [DateTime]::UtcNow.ToString('o') }
        Write-AutomationJson $state.Path @{ executions = @(Get-AutomationValue $state.Data 'executions' @()) + @($record) }
        return $record
    }
    $record = $records[0]
    if (-not $record.PSObject.Properties['receipts']) { $record | Add-Member -NotePropertyName receipts -NotePropertyValue @() }
    if (-not $record.PSObject.Properties['noChangeReceipt']) { $record | Add-Member -NotePropertyName noChangeReceipt -NotePropertyValue $null }
    if (-not $record.PSObject.Properties['lastError']) { $record | Add-Member -NotePropertyName lastError -NotePropertyValue $null }
    if (-not $record.PSObject.Properties['updatedAtUtc']) { $record | Add-Member -NotePropertyName updatedAtUtc -NotePropertyValue $null }
    if ($record.inputHash -cne $Dispatch.inputHash -or $record.eventId -cne $Dispatch.input.eventId -or $record.planHash -cne $PlanInfo.Plan.planHash -or $record.planPayloadBase64 -cne $PlanInfo.Payload) { throw 'AutomationEffectIdentityConflict' }
    return $record
}

function Save-AutomationEffectRecord($Config, $Record) {
    $state = Get-AutomationEffectState $Config
    $records = @(Get-AutomationValue $state.Data 'executions' @() | Where-Object { $_.executionId -cne $Record.executionId })
    $Record.updatedAtUtc = [DateTime]::UtcNow.ToString('o')
    Write-AutomationJson $state.Path @{ executions = @($records) + @($Record) }
}

function Get-AutomationStoreEffectReceipt($Config, [string]$EffectId) {
    $module = Get-AutomationStoreModule $Config
    $receipt = & $module { param($path, $id, $root) Get-WorkItemStoreEffectReceipt -Path $path -EffectId $id -RepositoryRoot $root -TimeoutMilliseconds 5000 } $Config.WorkItemStorePath $EffectId $Config.RepositoryRoot
    return $receipt
}

function Assert-AutomationStoreReceipt($Receipt, $Command, $Plan, [string]$ExpectedRevision) {
    if (-not $Receipt -or $Receipt.state -cne 'published' -or $Receipt.previousRevision -cne $ExpectedRevision) { throw 'EffectReceiptBindingMismatch' }
    if ([string](Get-AutomationValue $Command 'kind') -ceq 'set_workitem' -and ($Receipt.workItemId -cne [string]$Command.id -or [string]$Receipt.context.executionId -cne [string]$Plan.executionId -or [string]$Receipt.context.requestId -cne [string]$Plan.requestId -or [string]$Receipt.context.threadId -cne [string]$Plan.threadId -or [string]$Receipt.context.turnId -cne [string]$Plan.turnId -or [string]$Receipt.context.eventId -cne [string]$Plan.eventId -or [string]$Receipt.context.inputHash -cne [string]$Plan.inputHash -or [string]$Receipt.context.planHash -cne [string]$Plan.planHash -or [int]$Receipt.context.ordinal -ne [int]$Command.ordinal)) { throw 'EffectReceiptBindingMismatch' }
    if ([string](Get-AutomationValue $Command 'kind') -ceq 'request_rework' -and ($Receipt.workItemId -cne [string]$Command.workItemId -or [string]$Receipt.executionId -cne [string]$Plan.executionId -or [string]$Receipt.requestId -cne [string]$Plan.requestId -or [string]$Receipt.threadId -cne [string]$Plan.threadId -or [string]$Receipt.turnId -cne [string]$Plan.turnId -or [string]$Receipt.eventId -cne [string]$Plan.eventId -or [string]$Receipt.inputHash -cne [string]$Plan.inputHash -or [string]$Receipt.planHash -cne [string]$Plan.planHash -or [int]$Receipt.ordinal -ne [int]$Command.ordinal)) { throw 'EffectReceiptBindingMismatch' }
    if ([string](Get-AutomationValue $Command 'kind') -ceq 'set_workitem') {
        $itemBytes = [Convert]::FromBase64String([string]$Receipt.itemPayloadBase64)
        $savedItem = ConvertFrom-Json -InputObject ([Text.UTF8Encoding]::new($false, $true).GetString($itemBytes)) -ErrorAction Stop
        if ([string]$savedItem.id -cne [string]$Command.id -or (ConvertTo-Json -InputObject $savedItem -Depth 70 -Compress) -cne (ConvertTo-Json -InputObject $Command.item -Depth 70 -Compress)) { throw 'EffectReceiptItemMismatch' }
    }
    return $Receipt
}

function Get-AutomationReceiptOrdinal($Receipt, [string]$Kind) {
    if ($Kind -ceq 'set_workitem') { $v = Get-AutomationValue (Get-AutomationValue $Receipt 'context') 'ordinal' } elseif ($Kind -ceq 'request_rework') { $v = Get-AutomationValue $Receipt 'ordinal' } else { return $null }
    if ($null -eq $v) { return $null }; return [int]$v
}

function Apply-AutomationEffectPlan($Config, $DispatchModule, $Dispatch, $PlanInfo, $Result) {
    $record = Get-AutomationEffectRecord $Config $Dispatch $PlanInfo
    $record.state = 'Applying'
    Save-AutomationEffectRecord $Config $record
    $plan = $PlanInfo.Plan
    $expectedRevision = [string]$plan.baseRevision
    foreach ($command in @($plan.commands)) {
        $prior = @($record.receipts | Where-Object { (Get-AutomationReceiptOrdinal $_ ([string]$command.kind)) -eq [int]$command.ordinal })
        if ($prior.Count -gt 1) { throw 'AutomationEffectReceiptConflict' }
        if ($command.kind -ceq 'set_workitem') {
            $receipt = Get-AutomationStoreEffectReceipt $Config ([string]$command.effectId)
            if (-not $receipt) {
                $context = @{ effectId = [string]$command.effectId; executionId = [string]$plan.executionId; requestId = [string]$plan.requestId; threadId = [string]$plan.threadId; turnId = [string]$plan.turnId; eventId = [string]$plan.eventId; inputHash = [string]$plan.inputHash; planHash = [string]$plan.planHash; ordinal = [int]$command.ordinal }
                $store = Import-Module (Join-Path $Config.RepositoryRoot 'scripts/workitems/WorkItemStore.psm1') -PassThru -Force
                $resultStore = & $store { param($path, $id, $item, $isNew, $revision, $root, $effect) Set-WorkItemStoreEntry -Path $path -Id $id -Item $item -IsNew $isNew -ExpectedRevision $revision -RepositoryRoot $root -TimeoutMilliseconds 5000 -EffectContext $effect } $Config.WorkItemStorePath ([string]$command.id) $command.item ([bool]$command.isNew) $expectedRevision $Config.RepositoryRoot $context
                $receipt = Get-AutomationValue $resultStore 'EffectReceipt'
            }
            Assert-AutomationStoreReceipt $receipt $command $plan $expectedRevision | Out-Null
            if ($prior.Count -and (ConvertTo-Json -InputObject $prior[0] -Depth 50 -Compress) -cne (ConvertTo-Json -InputObject $receipt -Depth 50 -Compress)) { throw 'AutomationEffectReceiptConflict' }
            if (-not $prior.Count) { $record.receipts = @($record.receipts) + @($receipt) }
            $expectedRevision = [string]$receipt.candidateRevision
        } elseif ($command.kind -ceq 'request_rework') {
            $receipt = Request-CoordinatorRework $Config ([string]$command.workItemId) ([string]$command.purpose) ([int]$command.priorGeneration) ([string]$command.priorExecutionId) ([string]$command.reason) @{ effectId = $command.effectId; eventId = $plan.eventId; executionId = $plan.executionId; requestId = $plan.requestId; threadId = $plan.threadId; turnId = $plan.turnId; inputHash = $plan.inputHash; planHash = $plan.planHash; ordinal = $command.ordinal; baseRevision = $expectedRevision }
            Assert-AutomationStoreReceipt $receipt $command $plan $expectedRevision | Out-Null
            if ($prior.Count -and (ConvertTo-Json -InputObject $prior[0] -Depth 50 -Compress) -cne (ConvertTo-Json -InputObject $receipt -Depth 50 -Compress)) { throw 'AutomationEffectReceiptConflict' }
            if (-not $prior.Count) { $record.receipts = @($record.receipts) + @($receipt) }
        } else { throw 'EffectCommandKindUnsupported' }
        Save-AutomationEffectRecord $Config $record
    }
    if ($plan.disposition -ceq 'no_change') {
        if (@($plan.commands).Count -ne 0 -or @($record.receipts).Count -ne 0) { throw 'NoChangeReceiptHasEffects' }
        $noChange = [ordered]@{ state = 'published'; disposition = 'no_change'; executionId = [string]$plan.executionId; inputHash = [string]$plan.inputHash; eventId = [string]$plan.eventId; requestId = [string]$plan.requestId; threadId = [string]$plan.threadId; turnId = [string]$plan.turnId; baseRevision = [string]$plan.baseRevision; planHash = [string]$plan.planHash; reason = [string]$plan.reason }
        $record.noChangeReceipt = [pscustomobject]@{ state = 'published'; disposition = 'no_change'; executionId = $noChange.executionId; inputHash = $noChange.inputHash; eventId = $noChange.eventId; requestId = $noChange.requestId; threadId = $noChange.threadId; turnId = $noChange.turnId; baseRevision = $noChange.baseRevision; planHash = $noChange.planHash; reason = $noChange.reason; receiptHash = (Get-AutomationHash (ConvertTo-Json -InputObject $noChange -Depth 20 -Compress)) }
        Save-AutomationEffectRecord $Config $record
    }
    if (@($record.receipts).Count -ne @($plan.commands).Count) { throw 'AutomationEffectReceiptSetIncomplete' }
    $record.state = 'Complete'
    $record.lastError = $null
    Save-AutomationEffectRecord $Config $record
    return $record
}

function Test-AutomationEffectComplete($Config, $Record, $Dispatch) {
    if ($Record.state -cne 'Complete' -or $Record.executionId -cne $Dispatch.executionId -or $Record.inputHash -cne $Dispatch.inputHash -or $Record.eventId -cne $Dispatch.input.eventId) { return $false }
    $planBytes = [Convert]::FromBase64String([string]$Record.planPayloadBase64)
    $planHash = [string](Get-AutomationValue $Record 'planHash')
    if (-not $planHash -or (Get-AutomationBytesHash $planBytes) -cne $planHash) { return $false }
    $plan = ConvertFrom-Json -InputObject ([Text.UTF8Encoding]::new($false, $true).GetString($planBytes)) -ErrorAction Stop
    if ($plan.disposition -ceq 'no_change') {
        $receipt = Get-AutomationValue $Record 'noChangeReceipt'
        if (@($plan.commands).Count -ne 0 -or @($Record.receipts).Count -ne 0 -or -not $receipt -or $receipt.state -cne 'published') { return $false }
        $body = [ordered]@{ state = 'published'; disposition = 'no_change'; executionId = [string]$plan.executionId; inputHash = [string]$plan.inputHash; eventId = [string]$plan.eventId; requestId = [string]$plan.requestId; threadId = [string]$plan.threadId; turnId = [string]$plan.turnId; baseRevision = [string]$plan.baseRevision; planHash = $planHash; reason = [string]$plan.reason }
        if ($receipt.receiptHash -cne (Get-AutomationHash (ConvertTo-Json -InputObject $body -Depth 20 -Compress))) { return $false }
        foreach ($name in $body.Keys) { if ([string](Get-AutomationValue $receipt $name) -cne [string]$body[$name]) { return $false } }
        return $true
    }
    if (@($plan.commands).Count -ne @($Record.receipts).Count) { return $false }
    foreach ($command in @($plan.commands)) {
        $receipts = @($Record.receipts | Where-Object { (Get-AutomationReceiptOrdinal $_ ([string]$command.kind)) -eq [int]$command.ordinal })
        if ($receipts.Count -ne 1) { return $false }
        if ($command.kind -ceq 'set_workitem') {
            $storeReceipt = Get-AutomationStoreEffectReceipt $Config ([string]$command.effectId)
            if (-not $storeReceipt -or (ConvertTo-Json -InputObject $storeReceipt -Depth 50 -Compress) -cne (ConvertTo-Json -InputObject $receipts[0] -Depth 50 -Compress)) { return $false }
        } elseif ($command.kind -ceq 'request_rework') {
            $state = Read-AutomationJson (Join-Path $Config.DataDirectory 'workitem-generations.json') ([pscustomobject]@{ appliedReworks = @() })
            $receipt = @(Get-AutomationValue $state 'appliedReworks' @() | Where-Object { $_.effectId -ceq $command.effectId })
            if ($receipts.Count -ne 1 -or $receipt.Count -ne 1 -or (ConvertTo-Json -InputObject $receipt[0] -Depth 50 -Compress) -cne (ConvertTo-Json -InputObject $receipts[0] -Depth 50 -Compress)) { return $false }
        } else { return $false }
    }
    return $true
}

function Get-CoordinatorEventDispatch($Config, $DispatchModule, $Event, $Snapshot, [string]$LogicalSessionId) {
    if ([string]::IsNullOrWhiteSpace([string](Get-AutomationValue $Event 'id'))) { throw 'EventIdentityMissing' }
    $dispatchPath = Join-Path $Config.DataDirectory 'dispatch-journal.json'
    $journal = Read-AutomationJson $dispatchPath ([pscustomobject]@{ executions = @() })
    $bound = @($journal.executions | Where-Object { @($_.eventIds | Where-Object { $_ -ceq [string]$Event.id }).Count -gt 0 })
    if ($bound.Count -gt 1) { throw 'EventDispatchBindingConflict' }
    $dispatch = $null
    $purpose = 'coordinator-event'
    $workId = 'event-' + [string]$Event.id
    if ($bound.Count -eq 1) {
        $dispatch = & $DispatchModule { param($p, $id) Get-CoordinatorDispatch -JournalPath $p -ExecutionId $id } $dispatchPath ([string]$bound[0].executionId)
        if (-not $dispatch -or @($dispatch.eventIds | Where-Object { $_ -ceq [string]$Event.id }).Count -eq 0 -or [string](Get-AutomationValue $dispatch.input 'eventId') -cne [string]$Event.id) { throw 'EventDispatchBindingConflict' }
    } else {
        $turnInput = [ordered]@{
            eventId = [string]$Event.id; kind = [string]$Event.kind; sourceId = [string]$Event.sourceId; payload = $Event.payload
            storeRevision = [string]$Snapshot.Revision; workItems = @($Snapshot.Document.items); logicalSessionId = $LogicalSessionId
            effectProtocol = @{
                version = '1'; disposition = 'apply|no_change'; finalResponse = 'Emit exactly one final agentMessage JSON object; no markdown.'
                schema = @{ version = '1'; disposition = 'apply|no_change'; reason = 'non-empty string'; commands = @('set_workitem{id,isNew,item}', 'request_rework{workItemId,purpose,priorExecutionId,priorGeneration,reason}') }
                rules = @('no_change requires commands=[] and an event-specific reason', 'apply requires at least one command', 'Only these command kinds are allowed', 'Do not execute store or filesystem writes; report intended effects as commands only')
            }
        }
        $dispatch = & $DispatchModule { param($p, $id, $pur, $gen, $input, $events) Start-CoordinatorDispatch -JournalPath $p -WorkItemId $id -Purpose $pur -Generation $gen -Input $input -EventIds $events } $dispatchPath $workId $purpose 1 $turnInput @([string]$Event.id)
    }
    $serialized = ConvertTo-Json -InputObject $dispatch.input -Depth 50 -Compress
    if ((Get-AutomationHash $serialized) -cne [string]$dispatch.inputHash) { throw 'DispatchInputIntegrityMismatch' }
    return $dispatch
}

function Invoke-CoordinatorEventTurn($Config, $Runtime, $Session, [string]$SessionPath, $Event, $Snapshot, $DispatchModule) {
    if (-not $Event -or $Event.state -cne 'claimed' -or -not $Event.claimId) { return $false }
    $dispatchPath = Join-Path $Config.DataDirectory 'dispatch-journal.json'
    $dispatch = Get-CoordinatorEventDispatch $Config $DispatchModule $Event $Snapshot ([string]$Session.LogicalSessionId)
    if (@($dispatch.eventIds | Where-Object { $_ -ceq [string]$Event.id }).Count -eq 0) { throw 'EventDispatchBindingConflict' }
    $inputJson = ConvertTo-Json -InputObject $dispatch.input -Depth 50 -Compress
    $fingerprint = [Convert]::ToBase64String([Security.Cryptography.SHA256]::Create().ComputeHash([Text.UTF8Encoding]::new($false).GetBytes($inputJson)))
    $decision = $null
    $result = $null
    if ($dispatch.state -eq 'Returned') {
        $decision = Get-AutomationValue $dispatch 'terminalDecision'
        $result = Get-AutomationValue $dispatch 'returnValue'
    } else {
        try { $history = Get-AutomationHistoryDecision $Session $dispatch $fingerprint }
        catch {
            if ($_.Exception.Message -notlike 'RequestHistoryMissing*') { throw }
            if ($dispatch.state -in @('LaunchIntent', 'Running', 'RecoveryRequired')) { throw 'DispatchRecoveryRequired: request history not found; relaunch prohibited.' }
            if ($dispatch.state -ne 'Prepared') { throw 'DispatchStateUnsupported' }
            $dispatch = & $DispatchModule { param($p, $id) Set-CoordinatorDispatchState -JournalPath $p -ExecutionId $id -State LaunchIntent } $dispatchPath $dispatch.executionId
            $dispatch = & $DispatchModule { param($p, $id, $binding) Set-CoordinatorDispatchState -JournalPath $p -ExecutionId $id -State Running -LaunchBinding $binding } $dispatchPath $dispatch.executionId ('coordinator-event:' + $Session.LogicalSessionId + ':' + $dispatch.executionId)
            $request = [pscustomobject]@{
                operation = 'SubmitInput'; requestId = [string]$dispatch.requestId; logicalSessionId = [string]$Session.LogicalSessionId; inputText = $inputJson
                source = 'coordinator-event'; accountingDirectory = $Config.AccountingDirectory; parentTaskId = $Config.ParentTaskId
                effectMode = 'coordinator-effects-v1'; executionId = [string]$dispatch.executionId; eventId = [string]$Event.id; inputHash = [string]$dispatch.inputHash
                baseRevision = [string]$dispatch.input.storeRevision; threadId = [string]$Session.NativeThreadId
            }
            $result = Invoke-CoordinatorTurn $Runtime $Session $SessionPath $request
            if ((Get-AutomationValue $result 'status') -eq 'AccountingError') {
                $history = Get-AutomationHistoryDecision $Session $dispatch $fingerprint
                $decision = $history.Decision
            } elseif ((Get-AutomationValue $result 'classification') -eq 'Terminal') {
                $decision = Get-AutomationValue $result 'decision'
            } else { throw 'CoordinatorTurnNotTerminal' }
        }
        if (-not $decision) { $decision = $history.Decision }
        if ($dispatch.state -in @('Prepared', 'LaunchIntent')) {
            $dispatch = & $DispatchModule { param($p, $id) Set-CoordinatorDispatchState -JournalPath $p -ExecutionId $id -State RecoveryRequired } $dispatchPath $dispatch.executionId
        }
        if ($dispatch.state -ne 'Returned') {
            $effectList = @()
            if ((Get-AutomationValue $decision 'effectPlanStatus') -eq 'Complete') { $effectList = @(@{ kind = 'coordinator-effect-plan'; planHash = $decision.effectPlan.planHash; planPayloadBase64 = $decision.planPayloadBase64 }) }
            $dispatch = & $DispatchModule { param($p, $id, $d, $effects, $value) Set-CoordinatorDispatchState -JournalPath $p -ExecutionId $id -State Returned -TerminalDecision $d -Effects $effects -ReturnValue $value } $dispatchPath $dispatch.executionId $decision $effectList $result
        }
    }
    if (-not $decision) { throw 'CoordinatorTerminalDecisionMissing' }
    $history = Get-AutomationHistoryDecision $Session $dispatch $fingerprint
    if ((ConvertTo-Json -InputObject $history.Decision -Depth 70 -Compress) -cne (ConvertTo-Json -InputObject $decision -Depth 70 -Compress)) { throw 'RequestHistoryDecisionMismatch' }
    try {
        $planInfo = Get-AutomationEffectPlan $dispatch $decision $Session
        $record = Apply-AutomationEffectPlan $Config $DispatchModule $dispatch $planInfo $result
        if (-not (Test-AutomationEffectComplete $Config $record $dispatch)) { throw 'AutomationEffectReadbackIncomplete' }
    } catch {
        $state = Get-AutomationEffectState $Config
        $record = @(Get-AutomationValue $state.Data 'executions' @() | Where-Object { $_.executionId -ceq $dispatch.executionId })
        if ($record.Count -eq 1) { $record[0].state = 'RecoveryRequired'; $record[0].lastError = $_.Exception.Message; Save-AutomationEffectRecord $Config $record[0] }
        else { Write-AutomationJson $state.Path @{ executions = @(Get-AutomationValue $state.Data 'executions' @()) + @([pscustomobject]@{ executionId = $dispatch.executionId; inputHash = $dispatch.inputHash; eventId = $dispatch.input.eventId; planHash = $null; planPayloadBase64 = $null; commands = @(); receipts = @(); noChangeReceipt = $null; state = 'RecoveryRequired'; lastError = $_.Exception.Message; updatedAtUtc = [DateTime]::UtcNow.ToString('o') }) } }
        return $false
    }
    if (-not (Test-AutomationEffectComplete $Config $record $dispatch)) { return $false }
    Complete-CoordinatorEvent -Path $Config.EventJournalPath -EventId $Event.id -ClaimId $Event.claimId | Out-Null
    return $true
}

function Get-AutomationRoot($Items, $Item) {
    $byId = @{}
    foreach ($candidate in $Items) { $byId[[string]$candidate.id] = $candidate }
    $root = $Item
    $seen = @{}
    while ($parentId = [string](Get-AutomationValue $root 'parentId')) {
        if (-not $byId.ContainsKey($parentId) -or $seen.ContainsKey($parentId)) { break }
        $seen[$parentId] = $true
        $root = $byId[$parentId]
    }
    return $root
}

function Get-AutomationStartState($Config) {
    $path = Join-Path $Config.DataDirectory 'automation-start-effects.json'
    return [pscustomobject]@{ Path = $path; Data = (Read-AutomationJson $path ([pscustomobject]@{ effects = @(); diagnostics = @(); nextSequence = 1 })) }
}

function Save-AutomationStartEffect($Config, $Effect) {
    $state = Get-AutomationStartState $Config
    $effects = @(Get-AutomationValue $state.Data 'effects' @())
    $diagnostics = @(Get-AutomationValue $state.Data 'diagnostics' @())
    $sequence = [int](Get-AutomationValue $state.Data 'nextSequence' 1)
    $remaining = @($effects | Where-Object { $_.executionId -cne $Effect.executionId })
    Write-AutomationJson $state.Path @{ effects = @($remaining) + @($Effect); diagnostics = $diagnostics; nextSequence = $sequence }
}

function Add-AutomationStartDiagnostic($Config, $Dispatch, $Item, [string]$Reason) {
    $state = Get-AutomationStartState $Config
    $diagnostics = @(Get-AutomationValue $state.Data 'diagnostics' @())
    if (@($diagnostics | Where-Object { $_.executionId -ceq [string]$Dispatch.executionId }).Count) { return }
    $diagnostic = [pscustomobject]@{ executionId = [string]$Dispatch.executionId; workItemId = [string]$Item.id; generation = [int]$Dispatch.generation; dispatchState = [string]$Dispatch.state; reason = $Reason; createdAtUtc = [DateTime]::UtcNow.ToString('o') }
    Write-AutomationJson $state.Path @{ effects = @(Get-AutomationValue $state.Data 'effects' @()); diagnostics = @($diagnostics) + @($diagnostic); nextSequence = [int](Get-AutomationValue $state.Data 'nextSequence' 1) }
}

function Get-AutomationStartEvidence($Config, $Effect, $Dispatch) {
    $resultPath = [IO.Path]::GetFullPath([string]$Effect.resultPath)
    $jobPath = $resultPath + '.job.json'
    $goPath = $resultPath + '.go.json'
    $windowPath = $resultPath + '.window.json'
    foreach ($path in @($jobPath, $goPath, $windowPath)) { if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { return $null } }
    try { $job = Read-AutomationJson $jobPath $null; $go = Read-AutomationJson $goPath $null; $window = Read-AutomationJson $windowPath $null }
    catch { return $null }
    $taskIdN = ([guid]$Effect.taskId).ToString('N')
    $dispatchIdD = ([guid]$Effect.executionId).ToString('D')
    $jobResult = [IO.Path]::GetFullPath([string](Get-AutomationValue $job 'result_file'))
    if (((ConvertTo-AutomationGuid ([string]$Dispatch.taskId)) -cne $Effect.taskId) -or [string]$Dispatch.workItemId -cne $Effect.workItemId -or [string]$Dispatch.purpose -cne $Effect.purpose -or [int]$Dispatch.generation -ne [int]$Effect.generation -or (ConvertTo-AutomationGuid ([string](Get-AutomationValue $job 'task_id'))) -cne $Effect.taskId -or (ConvertTo-AutomationGuid ([string](Get-AutomationValue $job 'dispatch_id'))) -cne $Effect.executionId -or [string](Get-AutomationValue $job 'work_item_id') -cne $Effect.workItemId -or [string](Get-AutomationValue $job 'purpose') -cne $Effect.purpose -or [int](Get-AutomationValue $job 'generation') -ne [int]$Effect.generation -or $jobResult -cne $resultPath -or [string](Get-AutomationValue $job 'task') -cne [string]$Effect.taskText -or [string](Get-AutomationValue $job 'dispatch_journal_path') -cne (Join-Path $Config.DataDirectory 'dispatch-journal.json') -or [string](Get-AutomationValue $job 'payload_hash') -cne [string]$Effect.payloadHash -or [string](Get-AutomationValue $job 'payload_hash') -cne [string]$Dispatch.input.payloadHash -or [string]$Dispatch.input.task -cne [string]$Effect.taskText -or [IO.Path]::GetFullPath([string]$Dispatch.input.resultPath) -cne $resultPath -or [string]$Dispatch.input.role -cne [string](Get-AutomationValue $job 'role')) { return $null }
    if ((ConvertTo-AutomationGuid ([string](Get-AutomationValue $go 'task_id'))) -cne $Effect.taskId -or (ConvertTo-AutomationGuid ([string](Get-AutomationValue $window 'task_id'))) -cne $Effect.taskId -or -not [bool](Get-AutomationValue $go 'visible') -or -not [bool](Get-AutomationValue $go 'console_binding_verified')) { return $null }
    $runner = [string](Get-AutomationValue $go 'runner_pid')
    $handle = [string](Get-AutomationValue $go 'window_handle')
    $title = [string](Get-AutomationValue $go 'title')
    if (-not $runner -or -not $handle -or -not $title -or [string](Get-AutomationValue $go 'title') -cne ([string]$Effect.roleDisplayName + ' - ' + [string]$Effect.taskTitle) -or [string](Get-AutomationValue $window 'runner_pid') -cne $runner -or [string](Get-AutomationValue $window 'window_handle') -cne $handle -or [string](Get-AutomationValue $window 'title') -cne $title) { return $null }
    if ($Dispatch.state -notin @('Running', 'Returned') -or -not $Dispatch.runningAtUtc -or -not $Dispatch.launchBinding) { return $null }
    try { $binding = $Dispatch.launchBinding | ConvertFrom-Json -ErrorAction Stop } catch { return $null }
    if ((ConvertTo-AutomationGuid ([string](Get-AutomationValue $binding 'taskId'))) -cne $Effect.taskId -or [string](Get-AutomationValue $binding 'runnerPid') -cne $runner -or [string](Get-AutomationValue $binding 'windowHandle') -cne $handle -or [string](Get-AutomationValue $binding 'title') -cne $title) { return $null }
    $hashes = @{}
    foreach ($path in @($jobPath, $goPath, $windowPath)) { $hashes[[IO.Path]::GetFileName($path)] = Get-AutomationHash ([Convert]::ToBase64String([IO.File]::ReadAllBytes($path))) }
    if ($Effect.jobBinding.taskId -cne $taskIdN -or $Effect.jobBinding.dispatchId -cne $dispatchIdD -or $Effect.jobBinding.workItemId -cne [string]$Effect.workItemId -or $Effect.jobBinding.purpose -cne [string]$Effect.purpose -or [int]$Effect.jobBinding.generation -ne [int]$Effect.generation -or $Effect.jobBinding.payloadHash -cne [string]$Effect.payloadHash -or [IO.Path]::GetFullPath([string]$Effect.jobBinding.resultPath) -cne $resultPath) { return $null }
    return [pscustomobject]@{ taskId = $Effect.taskId; dispatchId = $Effect.executionId; resultPath = $resultPath; runnerPid = $runner; windowHandle = $handle; title = $title; hashes = $hashes }
}

function Reconcile-AutomationStartEffects($Config, $DispatchModule, $PlanningModule) {
    $state = Get-AutomationStartState $Config
    $effects = @(Get-AutomationValue $state.Data 'effects' @() | Sort-Object sequence)
    foreach ($effect in $effects) {
        if ($effect.state -eq 'Applied') { continue }
        $dispatchPath = Join-Path $Config.DataDirectory 'dispatch-journal.json'
        $dispatch = & $DispatchModule { param($p, $id) Get-CoordinatorDispatch -JournalPath $p -ExecutionId $id } $dispatchPath $effect.executionId
        if (-not $dispatch) {
            if ($effect.state -eq 'Prepared') { continue }
            $effect.state = 'RecoveryRequired'; Save-AutomationStartEffect $Config $effect; return $true
        }
        $evidence = Get-AutomationStartEvidence $Config $effect $dispatch
        if (-not $evidence) {
            if ($effect.state -in @('AwaitingEvidence', 'RecoveryRequired', 'StartConfirmed')) { $effect.state = 'RecoveryRequired'; Save-AutomationStartEffect $Config $effect; return $true }
            continue
        }
        $cursorPriority = [string]$effect.priority
        if ([string]::IsNullOrWhiteSpace($cursorPriority)) {
            if ([string]$effect.band -cne '4' -or [string]::IsNullOrWhiteSpace([string]$effect.rootId) -or [string]$effect.workItemId -cne [string]$dispatch.workItemId) {
                $effect.state = 'RecoveryRequired'; $effect.lastError = 'AutomationStartRecoveryRequired: pinned root/work-item binding is missing or inconsistent.'; Save-AutomationStartEffect $Config $effect; return $true
            }
            $cursorPriority = 'unspecified'
        }
        if ($effect.state -ne 'Applied') {
            $effect.state = 'StartConfirmed'; $effect.startEvidence = $evidence; Save-AutomationStartEffect $Config $effect
            & $PlanningModule { param($dir, $priority, $rootId) Advance-CoordinatorRootCursor -StateDirectory $dir -Priority $priority -StartedRootId $rootId } $Config.DataDirectory $cursorPriority $effect.rootId | Out-Null
            $cursorPath = Join-Path $Config.DataDirectory 'planning-root-cursors.json'
            $cursor = Read-AutomationJson $cursorPath $null
            if (-not $cursor -or [string](Get-AutomationValue $cursor $effect.band) -cne [string]$effect.rootId) { $effect.state = 'RecoveryRequired'; Save-AutomationStartEffect $Config $effect; return $true }
            $effect.state = 'Applied'; $effect.appliedAtUtc = [DateTime]::UtcNow.ToString('o'); Save-AutomationStartEffect $Config $effect
        }
    }
    return @($effects | Where-Object { $_.state -notin @('Applied', 'Prepared') }).Count -gt 0
}

function Prepare-AutomationStartEffect($Config, $Item, $Identity, [string]$TaskText, [string]$ResultPath, [string]$RootId, [string]$Priority, [int]$Generation) {
    $state = Get-AutomationStartState $Config
    $existing = @(Get-AutomationValue $state.Data 'effects' @() | Where-Object { $_.executionId -ceq $Identity.ExecutionId })
    $textHash = Get-AutomationHash $TaskText
    $role = [string](Get-AutomationValue (Get-AutomationValue $Item 'owner') 'id')
    $words = @($TaskText -split '\s+' | Where-Object { $_ })
    $title = if ($words.Count -ge 3) { $words[0..2] -join ' ' } else { 'Auftrag jetzt bearbeiten' }
    $workdir = (Resolve-Path -LiteralPath $Config.WorkingDirectory).Path
    $resultFullPath = [IO.Path]::GetFullPath($ResultPath)
    $parentTask = if ($Config.TaskId) { ([guid]$Config.TaskId).ToString('N') } else { '' }
    $payloadText = ($role + "`n" + $TaskText + "`n`n" + $workdir + "`n" + $resultFullPath + "`n" + $parentTask + "`n" + $title + "`n" + $role + "`n120`nFalse")
    $payloadText += "`n" + [string]$Item.id + "`nteamleiter-workitem`n" + $Generation + "`n" + (Join-Path $Config.DataDirectory 'dispatch-journal.json')
    $payloadHash = Get-AutomationHash $payloadText
    if ($existing.Count) {
        $effect = $existing[0]
        if ($existing.Count -ne 1 -or $effect.taskTextHash -cne $textHash -or $effect.payloadHash -cne $payloadHash -or $effect.taskTitle -cne $title -or $effect.roleDisplayName -cne $role -or [IO.Path]::GetFullPath($effect.resultPath) -cne $resultFullPath -or $effect.rootId -cne $RootId -or $effect.priority -cne $Priority) { throw 'AutomationStartIntentConflict' }
        return $effect
    }
    $bands = @{ urgent = '0'; high = '1'; normal = '2'; low = '3' }
    $band = if ($bands.ContainsKey($Priority)) { $bands[$Priority] } else { '4' }
    $taskIdD = ([guid]$Identity.TaskId).ToString('D')
    $taskIdN = ([guid]$Identity.TaskId).ToString('N')
    $jobBinding = [pscustomobject]@{ taskId = $taskIdN; dispatchId = [string]$Identity.ExecutionId; workItemId = [string]$Item.id; purpose = 'teamleiter-workitem'; generation = $Generation; payloadHash = $payloadHash; resultPath = $resultFullPath }
    $nextSequence = [int](Get-AutomationValue $state.Data 'nextSequence' 1)
    $effect = [pscustomobject]@{ effectId = 'cursor:' + $Identity.ExecutionId; executionId = $Identity.ExecutionId; taskId = $taskIdD; workItemId = [string]$Item.id; purpose = 'teamleiter-workitem'; generation = $Generation; resultPath = $resultFullPath; taskText = $TaskText; taskTextHash = $textHash; payloadHash = $payloadHash; taskTitle = $title; roleDisplayName = $role; rootId = $RootId; priority = $Priority; band = $band; sequence = $nextSequence; state = 'Prepared'; jobBinding = $jobBinding; startEvidence = $null; appliedAtUtc = $null; lastError = $null }
    Write-AutomationJson $state.Path @{ effects = @(Get-AutomationValue $state.Data 'effects' @()) + @($effect); diagnostics = @(Get-AutomationValue $state.Data 'diagnostics' @()); nextSequence = ($nextSequence + 1) }
    return $effect
}

function Invoke-CoordinatorDelegation($Config, $Snapshot, $Decision, $Inventory, $DispatchModule, $PlanningModule) {
    if ($Inventory.Unknown -or $Decision.CapacityUnknown -or $Decision.AvailableSlots -lt 1) { return }
    if (Reconcile-AutomationStartEffects $Config $DispatchModule $PlanningModule) { return }
    $items = @($Snapshot.Document.items)
    $startState = Get-AutomationStartState $Config
    $pendingStarts = @(Get-AutomationValue $startState.Data 'effects' @() | Where-Object { $_.state -eq 'Prepared' })
    if ($pendingStarts.Count -gt 1) { return }
    if ($pendingStarts.Count -eq 1 -and @($Decision.SelectedWorkItemIds | Where-Object { $_ -ceq $pendingStarts[0].workItemId }).Count -eq 0) { return }
    foreach ($id in $Decision.SelectedWorkItemIds) {
        if ($pendingStarts.Count -eq 1 -and [string]$id -cne [string]$pendingStarts[0].workItemId) { continue }
        $selected = @($items | Where-Object { $_.id -ceq $id } | Select-Object -First 1)
        if (-not $selected.Count) { continue }
        $item = $selected[0]
        $owner = Get-AutomationValue $item 'owner'
        $role = [string](Get-AutomationValue $owner 'id')
        if ((Get-AutomationValue $owner 'type') -cne 'agent' -or $role -notlike 'teamleiter_*') { continue }
        $purpose = 'teamleiter-workitem'
        try { $generation = Get-AutomationGeneration $Config $item $purpose } catch { continue }
        $dispatchPath = Join-Path $Config.DataDirectory 'dispatch-journal.json'
        $identity = & $DispatchModule { param($w, $p, $g) Get-CoordinatorDispatchIdentity $w $p $g } ([string]$item.id) $purpose $generation
        $prior = & $DispatchModule { param($p, $exec) Get-CoordinatorDispatch -JournalPath $p -ExecutionId $exec } $dispatchPath $identity.ExecutionId
        if ($prior) {
            if ($prior.state -in @('Running', 'Returned')) {
                $startState = Get-AutomationStartState $Config
                if (-not @(Get-AutomationValue $startState.Data 'effects' @() | Where-Object { $_.executionId -ceq $identity.ExecutionId }).Count) { Add-AutomationStartDiagnostic $Config $prior $item 'Legacy dispatch has no persisted pinned start/cursor intent; automatic restart and cursor reconstruction are prohibited.' }
            }
            if ($prior.state -eq 'Returned') { continue }
            if ($prior.state -in @('Prepared', 'LaunchIntent', 'Running', 'RecoveryRequired')) { continue }
        }
        if (-not $Config.ResultDirectories.Count) { return }
        $taskText = ([string]$item.description + "`n`nSpezifikation:`n" + (Get-AutomationTaskSpecification $Config $item) + "`n`nAbnahmekriterien:`n" + (ConvertTo-Json -InputObject (Get-AutomationValue $item 'acceptanceCriteria' @()) -Depth 30 -Compress)).Trim()
        $taskId = ([guid]$identity.TaskId).ToString('N')
        $resultPath = Join-Path $Config.ResultDirectories[0] ($taskId + '.json')
        $root = Get-AutomationRoot $items $item
    $priority = [string](Get-AutomationValue $item 'priority' 'unspecified')
    if ([string]::IsNullOrWhiteSpace($priority)) { $priority = 'unspecified' }
        $intent = Prepare-AutomationStartEffect $Config $item $identity $taskText $resultPath ([string]$root.id) $priority $generation
        if ($intent.state -in @('AwaitingEvidence', 'StartConfirmed', 'RecoveryRequired', 'Applied')) { continue }
        $jobPath = $resultPath + '.job.json'
        $goPath = $resultPath + '.go.json'
        if ((Test-Path -LiteralPath $jobPath) -or (Test-Path -LiteralPath $goPath)) { $intent.state = 'RecoveryRequired'; Save-AutomationStartEffect $Config $intent; return }
    $intent.state = 'AwaitingEvidence'
        Save-AutomationStartEffect $Config $intent
        $starter = Join-Path $Config.RepositoryRoot 'scripts/delegation/Start-DelegatedCodexTask.ps1'
        try {
            & $starter -Role $role -RoleDisplayName $intent.roleDisplayName -TaskTitle $intent.taskTitle -Task $taskText -WorkingDirectory (Resolve-Path -LiteralPath $Config.WorkingDirectory).Path -ResultPath $intent.resultPath -ParentTaskId $Config.TaskId -AccountingDirectory $Config.AccountingDirectory -CoordinatorDataDirectory $Config.RegistryDirectory -AdmissionCapacity $Config.Capacity -StableTaskId $taskId -DispatchId ([guid]$identity.ExecutionId).ToString('D') -WorkItemId ([string]$item.id) -Purpose $purpose -Generation $generation -DispatchJournalPath $dispatchPath -DetachedAfterVisibleAck | Out-Null
        } catch {
            if ($_.Exception.Message -like 'CoordinatorCapacityFull*' -or $_.Exception.Message -like 'NativeInventoryUnconfirmed*' -or $_.Exception.Message -like 'NativeInventoryIncomplete*') { $intent.state = 'Prepared'; Save-AutomationStartEffect $Config $intent; continue }
            $intent.lastError = $_.Exception.Message; $intent.state = 'RecoveryRequired'; Save-AutomationStartEffect $Config $intent; return
        }
        [void](Reconcile-AutomationStartEffects $Config $DispatchModule $PlanningModule)
        return
    }
}

function Invoke-CoordinatorAutomationIdle {
    param($Config, $Runtime, $Session, [string]$SessionPath)
    Import-CoordinatorWorkItemOutbox $Config
    Import-CoordinatorReminderFiles $Config
    Import-CoordinatorNativeResults $Config
    $planning = Import-Module (Join-Path $PSScriptRoot 'CoordinatorPlanning.psm1') -PassThru -Force
    $dispatch = Import-Module (Join-Path $PSScriptRoot 'CoordinatorDispatch.psm1') -PassThru -Force
    $startRecoveryPending = Reconcile-AutomationStartEffects $Config $dispatch $planning
    $snapshot = Get-AutomationStoreSnapshot $Config
    $inventory = Get-AutomationInventory $Config $Session
    $active = @($inventory.Entries)
    $event = Get-CoordinatorNextEvent -Path $Config.EventJournalPath -LeaseSeconds 3600
    if ($event) {
        try {
            if (-not (Invoke-CoordinatorEventTurn $Config $Runtime $Session $SessionPath $event $snapshot $dispatch)) { return }
        } catch { return }
        $snapshot = Get-AutomationStoreSnapshot $Config
    }
    $wake = @()
    if ($event) {
        $wakeId = [string](Get-AutomationValue $event.payload 'workItemId')
        if ($wakeId) { $wake = @($wakeId) }
    }
    $planningItems = @($snapshot.Document.items)
    $plan = & $planning { param($items, $capacity, $running, $wakeIds, $directory) Get-CoordinatorPlanningDecision -WorkItems $items -Capacity $capacity -ActiveExecutions $running -WakeEventIds $wakeIds -StateDirectory $directory } $planningItems ([int]$Config.Capacity) $active $wake $Config.DataDirectory
    if ($startRecoveryPending -or $inventory.Unknown -or (Get-AutomationValue $plan 'CapacityUnknown') -or [int](Get-AutomationValue $plan 'AvailableSlots' 0) -lt 1) { return }
    Invoke-CoordinatorDelegation $Config $snapshot $plan $inventory $dispatch $planning
}

Export-ModuleMember -Function Invoke-CoordinatorAutomationIdle
