# Technical design; backend owns adoption. No organizational contract changes.
Set-StrictMode -Version 2
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
function Read-UsageEntries([string]$Directory) {
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
                native_key=$key; identity=$identity; signature=$signature
                AliasTaskIds=@($identity.taskId); paths=@($file.FullName); records=@($record)
            }
        }
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
        if ($Kind -in @('reservation','transfer') -and $null -ne $Identity.turnId) {
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
Export-ModuleMember -Function *
