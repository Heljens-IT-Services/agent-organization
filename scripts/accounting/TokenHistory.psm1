# AR-108: metadata projection only; existing accounting owns identity/counters.
Set-StrictMode -Version 2
function Get-HistoryField($Value, [string]$Name) {
    if ($null -eq $Value) { return $null }
    $property = $Value.PSObject.Properties[$Name]
    if ($null -ne $property) { return $property.Value }
    return $null
}
function ConvertTo-HistoryUTC($Value) {
    if ($Value -isnot [string] -or $Value -cnotmatch '^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(\.\d{1,7})?(Z|[+-]\d{2}:\d{2})$') { return $null }
    $parsed = [DateTimeOffset]::MinValue
    if (-not [DateTimeOffset]::TryParse($Value, [Globalization.CultureInfo]::InvariantCulture, [Globalization.DateTimeStyles]::AssumeUniversal, [ref]$parsed)) { return $null }
    return $parsed.UtcDateTime.ToString("yyyy-MM-dd'T'HH:mm:ss.fffffff'Z'")
}
function Get-TokenHistory([object[]]$Records, [string[]]$Sources) {
    $result = [ordered]@{}; $evidence = @(); $conflicts = @(); $authority = [ordered]@{}
    foreach ($name in @('roleId','modelId','reasoningEffort','measurementUTC')) {
        $values = @(); $blocked = $false; $best = 0
        for ($i = 0; $i -lt $Records.Count; $i++) {
            $record = $Records[$i]
            # Authority is preserved across normalized profile/merge boundaries.
            # Exact effective turn context outranks resolved fresh-thread defaults.
            $rank = Get-HistoryField (Get-HistoryField $record 'metadataAuthority') $name
            if ($rank -isnot [int] -or $rank -notin @(10,20,30)) {
                $rank = if ($name -ceq 'roleId') { 10 }
                    elseif ($name -ceq 'measurementUTC' -and (Get-HistoryField $record 'measurementTimeBasis') -ceq 'native_record_timestamp') { 30 }
                    elseif ((Get-HistoryField $record 'schema') -ceq 'native-token-profile/v1' -or (Get-HistoryField $record 'source') -cin @('local_rollout_native_turn_usage','local_rollout_completed_turn_delta')) { 30 }
                    elseif ((Get-HistoryField $record 'source') -ceq 'app_server_fresh_thread_single_turn' -and $name -cne 'measurementUTC') { 20 }
                    else { 0 }
            }
            if ($name -ceq 'measurementUTC' -and (Get-HistoryField $record 'measurementTimeBasis') -cne 'native_record_timestamp') { continue }
            $hasConflict = @(Get-HistoryField $record 'metadataConflicts') -ccontains $name
            $value = Get-HistoryField $record $name
            # Legacy role is a recorded assignment, never a current role profile.
            if ($name -ceq 'roleId' -and $null -eq $value) { $value = Get-HistoryField $record 'role' }
            if ($rank -eq 0) { continue }
            if ($hasConflict) {
                if ($rank -gt $best) { $values=@(); $blocked=$false; $best=$rank }
                if ($rank -eq $best) { $blocked=$true }
            }
            if ($value -isnot [string] -or [string]::IsNullOrWhiteSpace($value) -or $value -cin @('unknown','native_rollout')) { continue }
            if ($name -cne 'measurementUTC' -and $value -cnotmatch '^[A-Za-z0-9][A-Za-z0-9_.:/-]{0,255}$') { continue }
            if ($name -ceq 'measurementUTC') { $value = ConvertTo-HistoryUTC $value; if ($null -eq $value) { continue } }
            $source = if ($i -lt $Sources.Count) { $Sources[$i] } else { $null }
            $evidence += @([pscustomobject]@{field=$name; value=$value; source=$source; authority=$rank})
            if ($rank -gt $best) { $values=@(); $blocked=$false; $best=$rank }
            if ($rank -eq $best) { $values+=@($value); if ($hasConflict) { $blocked=$true } }
        }
        $unique = @($values | Sort-Object -Unique -CaseSensitive)
        if ($blocked -or $unique.Count -gt 1) { $result[$name]=$null; $conflicts+=@($name) }
        elseif ($unique.Count -eq 1) { $result[$name]=$unique[0] }
        else { $result[$name]=$null }
        $authority[$name]=$best
    }
    $imports = @($Records | ForEach-Object { ConvertTo-HistoryUTC (Get-HistoryField $_ 'importedAtUTC') } | Where-Object { $null -ne $_ } | Sort-Object -Unique)
    $result['importedAtUTC'] = if ($imports.Count) { $imports[0] } else { $null }
    $result['importObservationsUTC'] = $imports
    $result['measurementObservationsUTC'] = @($Records | ForEach-Object {
        ConvertTo-HistoryUTC (Get-HistoryField $_ 'measurementObservedAtUTC')
        if ((Get-HistoryField $_ 'measurementTimeBasis') -ceq 'UTC receipt of last identity-matched native usage notification') { ConvertTo-HistoryUTC (Get-HistoryField $_ 'measurementUTC') }
    } | Where-Object { $null -ne $_ } | Sort-Object -Unique)
    $result['requestedProfiles'] = @($Records | ForEach-Object { Get-HistoryField $_ 'requestedProfile' } | Where-Object { $null -ne $_ })
    $result['measurementTimeBasis'] = if (@($Records | Where-Object { (Get-HistoryField $_ 'measurementTimeBasis') -ceq 'native_record_timestamp' -and $null -ne (ConvertTo-HistoryUTC (Get-HistoryField $_ 'measurementUTC')) }).Count -gt 0) { 'native_record_timestamp' } else { 'recorded_measurement_observation_or_unknown' }
    $result['metadataConflicts'] = $conflicts
    $result['metadataAuthority'] = [pscustomobject]$authority
    $result['metadataSources'] = @($evidence)+@($Records | ForEach-Object { Get-HistoryField $_ 'metadataSources' })
    $result['missingMetadata'] = @(@('roleId','modelId','reasoningEffort','measurementUTC') | Where-Object { $null -eq $result[$_] })
    return [pscustomobject]$result
}
function Get-TurnContextHistory($Payload, [string]$Source) {
    # Only identity-bound native turn_context values. Requested job/TOML model
    # defaults are deliberately excluded: they do not prove effective runtime.
    $records = @()
    foreach ($pair in @(@('roleId','role_id'),@('roleId','roleId'),@('modelId','model'),@('modelId','modelId'),@('reasoningEffort','effort'),@('reasoningEffort','reasoning_effort'),@('reasoningEffort','reasoningEffort'))) {
        $value = Get-HistoryField $Payload $pair[1]
        $one = @{}; $one[$pair[0]] = $value; $one['metadataAuthority']=[pscustomobject]@{roleId=30;modelId=30;reasoningEffort=30}
        $records += @([pscustomobject]$one)
    }
    return Get-TokenHistory $records @($records | ForEach-Object { $Source })
}
function Get-EntryTokenHistory($Entry) {
    # Every duplicate contributes evidence, never another token measurement.
    $records = @(Get-HistoryField $Entry 'records')
    # Merged records and unique path sets are not positional arrays. Embedded
    # metadataSources retain exact provenance; the projection exposes all paths.
    return Get-TokenHistory $records @()
}
function Get-TokenHistoryProjection($Entries, [string[]]$EligibleNativeKeys, $Coverage) {
    $rows = @(); $excluded = @()
    foreach ($entry in @($Entries)) {
        $id = $entry.identity; $history = Get-EntryTokenHistory $entry
        $eligible = $EligibleNativeKeys -ccontains $entry.native_key
        $kind = Get-HistoryField $entry 'counterKind'
        $reason = if (-not $id.final) { 'provisional' } elseif ($null -eq $id.tokenUsage) { 'measurement_missing' }
            elseif (-not $eligible) { 'accounting_identity_or_correlation_conflict' }
            elseif ($kind -cne 'turn_token_usage') { 'own_native_counter_semantics_unproven' } else { $null }
        # Decimal strings preserve Int64 precision across the JSON/JS boundary.
        $displayUsage=$null
        $observedUsage=$null
        if ($null -ne $id.tokenUsage) {
            $observedUsage=[ordered]@{}
            foreach ($field in @('totalTokens','inputTokens','outputTokens','cachedInputTokens','reasoningOutputTokens','cacheWriteInputTokens')) { $observedUsage[$field]=$id.tokenUsage.$field.ToString([Globalization.CultureInfo]::InvariantCulture) }
        }
        if ($null -eq $reason) {
            $displayUsage=[ordered]@{}
            foreach ($field in @('totalTokens','inputTokens','outputTokens','cachedInputTokens','reasoningOutputTokens','cacheWriteInputTokens')) { $displayUsage[$field]=$id.tokenUsage.$field.ToString([Globalization.CultureInfo]::InvariantCulture) }
        }
        $row = [pscustomobject]@{
            nativeKey=$(if ($null -ne $id.threadId -and $null -ne $id.turnId) { $entry.native_key } else { $null }); taskId=$id.taskId; aliasTaskIds=@($entry.AliasTaskIds)
            workItemId=$id.workItemId; executionId=$id.executionId; threadId=$id.threadId; turnId=$id.turnId
            roleId=$history.roleId; modelId=$history.modelId; reasoningEffort=$history.reasoningEffort
            measurementUTC=$history.measurementUTC; importedAtUTC=$history.importedAtUTC
            measurementTimeBasis=$history.measurementTimeBasis
            importObservationsUTC=$history.importObservationsUTC; metadataSources=$history.metadataSources
            measurementObservationsUTC=$history.measurementObservationsUTC; requestedProfiles=$history.requestedProfiles
            metadataConflicts=$history.metadataConflicts; missingMetadata=$history.missingMetadata
            metadataAuthority=$history.metadataAuthority
            tokenUsage=$displayUsage
            diagnosticTokenUsage=$(if ($null -ne $reason) { $observedUsage } else { $null })
            eligible=($null -eq $reason); exclusionReason=$reason; sources=@($entry.paths)
        }
        $rows+=@($row)
        if ($null -ne $reason) { $excluded+=@([pscustomobject]@{nativeKey=$row.nativeKey;taskId=$id.taskId;reason=$reason;sources=@($entry.paths)}) }
    }
    return [pscustomobject]@{
        version=1; records=$rows; excluded=$excluded; coverage=$Coverage
        semantics='Dedupliziert je Thread/Turn; nur finale eigene native Turnzähler. Cached Input und Reasoning Output sind Teilmengen. Summen sind bekannte Teilsummen, keine vollständige Familienabrechnung.'
        timeBasis='Verbrauch nach finalem Messzeitpunkt (UTC). measurementUTC ist letzte finale native Messung; Empfangsbeobachtung und importedAtUTC sind getrennt. Keine zeitproportionale Aufteilung. Unbekannte Verbrauchszeit wird keiner Zeit-Säule zugeordnet.'
    }
}
Export-ModuleMember -Function Get-TokenHistory,Get-TurnContextHistory,Get-EntryTokenHistory,Get-TokenHistoryProjection,ConvertTo-HistoryUTC
