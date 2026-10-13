Set-StrictMode -Version Latest

$script:UsageFields = @('input_tokens','cached_input_tokens','cache_write_input_tokens','output_tokens','reasoning_output_tokens','total_tokens')
$script:MaximumUsageSnapshotBytes = 134217728L
$script:ProfileFields = @('role_id','roleId','model','modelId','effort','reasoning_effort','reasoningEffort')

function Get-UsagePropertyValue($Object, [string]$Name) {
    if ($null -eq $Object -or $Object -isnot [System.Management.Automation.PSCustomObject]) { return $null }
    $property = $Object.PSObject.Properties[$Name]
    if ($null -eq $property) { return $null }
    return $property.Value
}

function ConvertTo-UsageInt64($Value, [string]$FieldName) {
    if ($null -eq $Value -or $Value -is [bool] -or $Value -isnot [ValueType] -or
        $Value -is [DateTime] -or $Value -is [Guid] -or $Value -is [TimeSpan]) {
        throw "Invalid integer field: $FieldName"
    }
    try {
        $number = [decimal]$Value
        if ($number -lt 0 -or $number -gt [long]::MaxValue -or $number -ne [decimal]::Truncate($number)) { throw 'out of range' }
        return [long]$number
    } catch { throw "Invalid nonnegative Int64 field: $FieldName" }
}

function Get-UsageCounterSample($Usage) {
    $sample = [ordered]@{}
    foreach ($field in $script:UsageFields) {
        $property = if ($null -ne $Usage -and $Usage -is [System.Management.Automation.PSCustomObject]) { $Usage.PSObject.Properties[$field] } else { $null }
        if ($null -eq $property -and $field -ceq 'cache_write_input_tokens') { $value = 0 }
        elseif ($null -eq $property) { throw "Missing required usage counter: $field" }
        else { $value = $property.Value }
        $sample[$field] = ConvertTo-UsageInt64 $value $field
    }
    if ($sample.cached_input_tokens -gt $sample.input_tokens -or
        $sample.cache_write_input_tokens -gt $sample.input_tokens -or
        $sample.reasoning_output_tokens -gt $sample.output_tokens -or
        [decimal]$sample.total_tokens -ne ([decimal]$sample.input_tokens + [decimal]$sample.output_tokens)) {
        throw 'Usage counters violate subset or total invariants.'
    }
    return [pscustomobject]$sample
}

function Get-OriginalUsageSha256([byte[]]$Bytes) {
    $sha = [Security.Cryptography.SHA256]::Create()
    try { return ([BitConverter]::ToString($sha.ComputeHash($Bytes))).Replace('-','').ToLowerInvariant() }
    finally { $sha.Dispose() }
}

function ConvertTo-CanonicalNativeIdentity([string]$ThreadId,[string]$TurnId){
    if($ThreadId -notmatch '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$' -or $TurnId -notmatch '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$'){throw 'NativeIdentityInvalid'}
    $thread=([guid]$ThreadId).ToString('D');$turn=([guid]$TurnId).ToString('D')
    return [pscustomobject]@{Thread=$thread;Turn=$turn;Key=(Get-OriginalUsageSha256 (ConvertTo-PublicBytes @($thread,$turn)))}
}


$script:BindingNames=@('task_id','taskId','parent_task_id','parentTaskId','thread_id','threadId','turn_id','turnId','parent_thread_id','parentThreadId','parent_turn_id','parentTurnId','work_item_id','workItemId','execution_id','executionId','store_path','storePath','work_item_store_path')
function ConvertTo-PublicBytes($Value){return ,([Text.UTF8Encoding]::new($false).GetBytes(($Value|ConvertTo-Json -Depth 50 -Compress)+"`n"))}
function Read-PublicBytes([string]$Path,[long]$Limit=$script:MaximumUsageSnapshotBytes){
    $fs=[IO.File]::Open($Path,'Open','Read',([IO.FileShare]::ReadWrite -bor [IO.FileShare]::Delete))
    try{
        $n=$fs.Length; if($n -lt 0 -or $n -gt $Limit -or $n -gt [int]::MaxValue){throw 'CaptureLimit'}
        $b=[byte[]]::new([int]$n); $at=0
        while($at -lt $b.Length){$r=$fs.Read($b,$at,[Math]::Min(65536,$b.Length-$at));if($r -le 0){throw 'TruncatedCapture'};$at+=$r}
        return ,$b
    }finally{$fs.Dispose()}
}
function Write-PublicBytes([string]$Path,[byte[]]$Bytes){
    $fs=[IO.File]::Open($Path,'CreateNew','Write','None')
    try{$fs.Write($Bytes,0,$Bytes.Length);$fs.Flush($true)}finally{$fs.Dispose()}
}
function Read-PublicSource([string]$Path,[string]$ArchiveRoot){
    $full=[IO.Path]::GetFullPath($Path);$prefix=[IO.Path]::GetFullPath($ArchiveRoot).TrimEnd('\','/')+[IO.Path]::DirectorySeparatorChar
    $isArchive=$full.StartsWith($prefix,[StringComparison]::OrdinalIgnoreCase)
    $receiptPath="$full.receipt.json";$markerPath="$full.commit"
    # Inputs in our archive namespace ALWAYS require the complete recognized receipt.
    if([IO.File]::Exists("$full.manifest.json") -or [IO.File]::Exists([IO.Path]::ChangeExtension($full,'.manifest.json'))){throw 'ForeignArchiveSchemaRequiresExplicitHandoff'}
    $hasReceipt=[IO.File]::Exists($receiptPath);$hasMarker=[IO.File]::Exists($markerPath)
    if($isArchive -or $hasReceipt -or $hasMarker){
        if(-not $hasReceipt -or -not $hasMarker -or [IO.File]::Exists("$full.stage") -or [IO.File]::Exists("$receiptPath.stage") -or [IO.File]::Exists("$markerPath.stage")){throw 'RetainedInputIncompletePreserveStop'}
        $rb=Read-PublicBytes $receiptPath 1048576;$receipt=[Text.UTF8Encoding]::new($false,$true).GetString($rb)|ConvertFrom-Json -ErrorAction Stop
        $marker=Read-PublicBytes $markerPath 256
        if($receipt.schema -cne 'public-retention/v1' -or $receipt.path -cne $full -or [Text.UTF8Encoding]::new($false,$true).GetString($marker) -cne (Get-OriginalUsageSha256 $rb)){throw 'RetainedInputReceiptConflict'}
        $bytes=Read-PublicBytes $full
        if(($receipt.byteLength -isnot [int] -and $receipt.byteLength -isnot [long]) -or $receipt.byteLength -ne $bytes.Length -or $receipt.sha256 -cne (Get-OriginalUsageSha256 $bytes)){throw 'RetainedInputBlobConflict'}
        return [pscustomobject]@{Bytes=$bytes;OriginalReceipt=$receipt}
    }
    return [pscustomobject]@{Bytes=(Read-PublicBytes $full);OriginalReceipt=$null}
}
# Byte structural scanner: unknown/private values skipped without decoding strings.
function Get-PublicSpans([byte[]]$B,[int]$At=0,[int]$Length=-1){
    if($Length -lt 0){$Length=$B.Length-$At};$end=$At+$Length;$i=$At
    while($i -lt $end -and $B[$i] -in @(9,10,13,32)){$i++}
    if($i -ge $end -or $B[$i] -ne 123){throw 'ObjectRequired'};$i++;$out=[ordered]@{}
    while($i -lt $end){
        while($i -lt $end -and $B[$i] -in @(9,10,13,32)){$i++}
        if($i -lt $end -and $B[$i] -eq 125){if($out.Count -ne 0){throw 'MemberRequiredAfterComma'};$i++;while($i -lt $end -and $B[$i] -in @(9,10,13,32)){$i++};if($i -ne $end){throw 'ObjectSuffixBytes'};return $out}
        if($i -ge $end -or $B[$i] -ne 34){throw 'KeyRequired'};$ks=$i;$i++
        while($i -lt $end){if($B[$i] -eq 92){$i+=2;continue};if($B[$i] -eq 34){break};$i++}
        if($i -ge $end){throw 'TruncatedKey'};$i++
        $key=[Text.UTF8Encoding]::new($false,$true).GetString($B,$ks,$i-$ks)|ConvertFrom-Json
        if($out.Contains($key)){throw 'DuplicateKey'}
        while($i -lt $end -and $B[$i] -in @(9,10,13,32)){$i++}
        if($i -ge $end -or $B[$i] -ne 58){throw 'ColonRequired'};$i++
        while($i -lt $end -and $B[$i] -in @(9,10,13,32)){$i++}
        $start=$i;$depth=0;$quoted=$false
        while($i -lt $end){
            $c=$B[$i]
            if($quoted){if($c -eq 92){$i+=2;continue};if($c -eq 34){$quoted=$false}}
            else{if($c -eq 34){$quoted=$true}elseif($c -in @(123,91)){$depth++}elseif($c -in @(125,93)){if($depth -eq 0){break};$depth--}elseif($c -eq 44 -and $depth -eq 0){break}}
            $i++
        }
        if($quoted -or $depth -ne 0 -or $i -le $start -or $i -ge $end){throw 'TruncatedValue'}
        $out[$key]=[pscustomobject]@{Offset=$start;Length=$i-$start}
        if($B[$i] -eq 125){$i++;while($i -lt $end -and $B[$i] -in @(9,10,13,32)){$i++};if($i -ne $end){throw 'ObjectSuffixBytes'};return $out};if($B[$i] -ne 44){throw 'CommaRequired'};$i++
    };throw 'TruncatedObject'
}
function Get-PublicValue([byte[]]$B,$Spans,[string]$Name){
    if(-not $Spans.Contains($Name)){return $null};$s=$Spans[$Name]
    return ([Text.UTF8Encoding]::new($false,$true).GetString($B,$s.Offset,$s.Length)|ConvertFrom-Json -ErrorAction Stop)
}
function Test-PublicGuid([string]$Value){return $Value -cmatch '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$'}
function Select-PublicFields([byte[]]$B,$Spans,[string[]]$Names){
    $out=[ordered]@{};foreach($name in $Names){if($Spans.Contains($name)){$out[$name]=Get-PublicValue $B $Spans $name}};return $out
}
function Test-PublicRawRecord($B,$Top,[string]$Type,$PayloadSpans){
    $allowedTop=@('ordinal','type','payload','timestamp')
    foreach($key in $Top.Keys){if($key -cnotin $allowedTop){return 'unknown top-level field'} }
    if($Top.Count -lt 3 -or -not $Top.Contains('ordinal') -or -not $Top.Contains('type') -or -not $Top.Contains('payload')){return 'record envelope is incomplete'}
    if($Top.Contains('timestamp')){
        $timestamp=Get-PublicValue $B $Top 'timestamp'
        if($timestamp -isnot [string] -or $timestamp -cnotmatch '^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(\.\d{1,7})?(Z|[+-]\d{2}:\d{2})$'){return 'timestamp has no explicit ISO-8601 offset'}
        $formats=@("yyyy-MM-dd'T'HH:mm:ss'Z'","yyyy-MM-dd'T'HH:mm:sszzz")
        for($digits=1;$digits -le 7;$digits++){$formats+=("yyyy-MM-dd'T'HH:mm:ss."+('f'*$digits)+"'Z'");$formats+=("yyyy-MM-dd'T'HH:mm:ss."+('f'*$digits)+"zzz")}
        $parsed=[datetimeoffset]::MinValue;if(-not [datetimeoffset]::TryParseExact($timestamp,$formats,[Globalization.CultureInfo]::InvariantCulture,[Globalization.DateTimeStyles]::AssumeUniversal,[ref]$parsed)){return 'timestamp calendar value is invalid'}
    }
    $allowedPayload=@()
    if($Type -ceq 'session_meta'){$allowedPayload=@('id')}
    elseif($Type -ceq 'turn_context'){$allowedPayload=@('thread_id','threadId','turn_id','turnId','root_turn_id')+$script:ProfileFields}
    elseif($Type -ceq 'token_usage_record'){$allowedPayload=@('thread_id','turn_id','turn_token_usage')}
    elseif($Type -ceq 'event_msg'){$allowedPayload=@('type','thread_id','threadId','turn_id','turnId','task_id','taskId','parent_task_id','parentTaskId','work_item_id','workItemId','execution_id','executionId','parent_thread_id','parentThreadId','parent_turn_id','parentTurnId','turn_attribution')}
    else{return 'record type is not allowlisted'}
    foreach($key in $PayloadSpans.Keys){if($key -cnotin $allowedPayload){return "unreviewed payload field: $key"} }
    if($Type -ceq 'session_meta'){
        $v=Get-PublicValue $B $PayloadSpans 'id';if($v -isnot [string] -or -not (Test-PublicGuid $v)){return 'session id is not a GUID'}
    }elseif($Type -ceq 'turn_context'){
        foreach($key in $PayloadSpans.Keys){
            $v=Get-PublicValue $B $PayloadSpans $key
            if($key -cin $script:ProfileFields){if($null -ne $v -and ($v -isnot [string] -or $v -cnotmatch '^[A-Za-z0-9][A-Za-z0-9_.:/-]{0,255}$')){return "context profile value invalid: $key"}}
            elseif($v -isnot [string] -or -not (Test-PublicGuid $v)){return "context identity is not a GUID: $key"}
        }
    }elseif($Type -ceq 'token_usage_record'){
        foreach($key in @('thread_id','turn_id')){$v=Get-PublicValue $B $PayloadSpans $key;if($v -isnot [string] -or -not (Test-PublicGuid $v)){return "usage identity is not a GUID: $key"}}
        if($PayloadSpans.Contains('turn_token_usage') -and $null -ne (Get-PublicValue $B $PayloadSpans 'turn_token_usage')){
            $c=Get-PublicSpans $B $PayloadSpans.turn_token_usage.Offset $PayloadSpans.turn_token_usage.Length
            foreach($key in $c.Keys){if($key -cnotin $script:UsageFields){return "unreviewed usage field: $key"}}
            if($c.Count -ne 6){return 'usage counters are incomplete'}
            foreach($key in $c.Keys){$v=Get-PublicValue $B $c $key;if(($v -isnot [long] -and $v -isnot [int]) -or $v -lt 0){return "usage value is not a nonnegative integer: $key"}}
        }
    }elseif($Type -ceq 'event_msg'){
        $v=Get-PublicValue $B $PayloadSpans 'type';if($v -isnot [string] -or $v -cnotin @('task_started','task_complete')){return 'event is not a public lifecycle type'}
        foreach($key in $PayloadSpans.Keys){if($key -ceq 'type'){continue};$value=Get-PublicValue $B $PayloadSpans $key;if($key -ceq 'turn_attribution'){$nested=Get-PublicSpans $B $PayloadSpans[$key].Offset $PayloadSpans[$key].Length;foreach($nk in $nested.Keys){if($nk -cnotin @('thread_id','threadId','turn_id','turnId','root_turn_id')){return "unreviewed turn attribution field: $nk"};$nv=Get-PublicValue $B $nested $nk;if($nv -isnot [string] -or -not (Test-PublicGuid $nv)){return "turn attribution is not a GUID: $nk"}}}elseif($key -match '(^|_)(task|thread|turn|parent_task|work_item|execution)_id$' -or $key -match '^(taskId|threadId|turnId|parentTaskId|workItemId|executionId|parentThreadId|parentTurnId)$'){if($value -isnot [string] -or -not (Test-PublicGuid $value)){return "lifecycle identity is not a GUID: $key"}}else{return "unreviewed lifecycle value: $key"}
        }
    }
    return $null
}
function Get-PublicNative($Snapshot){
    $name=[IO.Path]::GetFileName($Snapshot.Path)
    if($name -notmatch '^rollout-\d{4}-\d{2}-\d{2}T\d{2}-\d{2}-\d{2}-([0-9a-fA-F-]{36})\.jsonl$'){throw 'NativeFilenameInvalid'}
    $originalThreadId=$Matches[1];$thread=([guid]$originalThreadId).ToString('D');$b=$Snapshot.Bytes;$start=0;$last=-1L;$sessions=0
    $rows=[Collections.Generic.List[object]]::new();$ranges=[Collections.Generic.List[object]]::new();$lines=[Collections.Generic.List[string]]::new();$missingUsage=[Collections.Generic.List[object]]::new()
    for($i=0;$i -lt $b.Length;$i++){
        if($b[$i] -ne 10){continue};$len=$i-$start;if($len -gt 0 -and $b[$i-1] -eq 13){$len--}
        if($len -le 0 -or $len -gt 1048576){throw 'NativeLineLimit'}
        $top=Get-PublicSpans $b $start $len;$ord=Get-PublicValue $b $top 'ordinal';$type=Get-PublicValue $b $top 'type'
        if(-not $top.Contains('ordinal') -or -not $top.Contains('type') -or -not $top.Contains('payload') -or $type -isnot [string]){throw 'NativeEnvelopeIncomplete'}
        if(($ord -isnot [int] -and $ord -isnot [long]) -or $ord -lt 0 -or $ord -le $last -or $type -isnot [string]){throw 'NativeEnvelopeInvalid'};$last=[long]$ord
        if($type -in @('session_meta','turn_context','event_msg','token_usage_record')){
            if(-not $top.Contains('payload')){throw 'NativePayloadMissing'};$ps=Get-PublicSpans $b $top.payload.Offset $top.payload.Length;$safe=$null
            if($type -ceq 'session_meta'){
                $safe=Select-PublicFields $b $ps @('id');$sessions++
                if($sessions -ne 1 -or -not $safe.Contains('id') -or $safe.id -isnot [string] -or ([guid]$safe.id).ToString('D') -cne $thread){throw 'NativeSessionInvalid'}
            }elseif($type -ceq 'turn_context'){
                $safe=Select-PublicFields $b $ps ($script:BindingNames+@('root_turn_id'))
                foreach($f in $script:ProfileFields){
                    if(-not $ps.Contains($f)){continue};$v=Get-PublicValue $b $ps $f
                    $safe[$f]=if($v -is [string] -and $v -cmatch '^[A-Za-z0-9][A-Za-z0-9_.:/-]{0,255}$'){$v}else{$null}
                }
            }
            elseif($type -ceq 'token_usage_record'){
                $safe=Select-PublicFields $b $ps @('thread_id','turn_id')
                if(-not $safe.Contains('thread_id')){throw 'NativeUsageIdentityMissing'}
                if($ps.Contains('turn_token_usage') -and $null -ne (Get-PublicValue $b $ps 'turn_token_usage')){
                    $cs=Get-PublicSpans $b $ps.turn_token_usage.Offset $ps.turn_token_usage.Length
                    $safe.turn_token_usage=Get-UsageCounterSample ([pscustomobject](Select-PublicFields $b $cs $script:UsageFields))
                }else{$safe.turn_token_usage=$null;$missingUsage.Add([ordered]@{sourcePath=$Snapshot.Path;ordinal=[long]$ord;threadId=$thread;turnId=([guid]$safe.turn_id).ToString('D');reason=$(if($ps.Contains('turn_token_usage')){'explicit-null'}else{'absent'})})}
            }elseif((Get-PublicValue $b $ps 'type') -in @('task_started','task_complete')){
                $safe=Select-PublicFields $b $ps ($script:BindingNames+@('type'))
                if($ps.Contains('turn_attribution')){
                    $ats=Get-PublicSpans $b $ps.turn_attribution.Offset $ps.turn_attribution.Length
                    $safe.turn_attribution=Select-PublicFields $b $ats ($script:BindingNames+@('root_turn_id'))
                }
            }
            $rangeCountBefore=$ranges.Count
            if($null -ne $safe){
                foreach($f in @('thread_id','threadId')){if($safe.Contains($f) -and ($safe[$f] -isnot [string] -or ([guid]$safe[$f]).ToString('D') -cne $thread)){throw 'NativeThreadConflict'}}
                $originalTurnId=if($safe.Contains('turn_id')){$safe.turn_id}else{$null}
                if($type -cne 'session_meta'){if(-not $safe.Contains('turn_id') -or $safe.turn_id -isnot [string]){throw 'NativeTurnMissing'};$safe.turn_id=([guid]$safe.turn_id).ToString('D')}
                $row=[pscustomobject][ordered]@{ordinal=[long]$ord;type=$type;payload=[pscustomobject]$safe}
                if($top.Contains('timestamp')){
                    $ts=Get-PublicValue $b $top 'timestamp'
                    $parsedTime=[datetimeoffset]::MinValue
                    if($ts -is [string] -and $ts -cmatch '^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(\.\d{1,7})?(Z|[+-]\d{2}:\d{2})$' -and [datetimeoffset]::TryParse($ts,[Globalization.CultureInfo]::InvariantCulture,[Globalization.DateTimeStyles]::AssumeUniversal,[ref]$parsedTime)){
                        $row | Add-Member -NotePropertyName timestamp -NotePropertyValue $ts
                    }
                }
                if($type -cne 'token_usage_record' -or $null -ne $safe.turn_token_usage){$rows.Add($row);$lines.Add(($row|ConvertTo-Json -Depth 20 -Compress))}
                $original=[byte[]]::new($i-$start+1);[Array]::Copy($b,$start,$original,0,$original.Length)
                $rawReason=Test-PublicRawRecord $b $top $type $ps
                $nativeFinalIdentity=$null
                if($type -ceq 'token_usage_record' -and $null -ne $safe.turn_token_usage){$nativeFinalIdentity=$null}
                $ranges.Add([pscustomobject]@{ordinal=[long]$ord;offset=[long]$start;length=[long]$original.Length;rangeSha256=(Get-OriginalUsageSha256 $original);originalPath=$Snapshot.Path;originalThreadId=$originalThreadId;originalTurnId=$originalTurnId;internalBytes=$(if($null -eq $rawReason){$original}else{$null});rawRangeAvailable=($null -eq $rawReason);rawUnavailableReason=$rawReason;threadId=$thread;turnId=$safe.turn_id;nativeFinalIdentity=$nativeFinalIdentity})
            }
            if($ranges.Count -eq $rangeCountBefore){$original=[byte[]]::new($i-$start+1);[Array]::Copy($b,$start,$original,0,$original.Length);$ranges.Add([pscustomobject]@{ordinal=[long]$ord;offset=[long]$start;length=[long]$original.Length;rangeSha256=(Get-OriginalUsageSha256 $original);originalPath=$Snapshot.Path;originalThreadId=$originalThreadId;originalTurnId=$null;internalBytes=$null;rawRangeAvailable=$false;rawUnavailableReason='record payload is not an allowlisted public lifecycle record';threadId=$thread;turnId=$null;nativeFinalIdentity=$null})}
        }else{
            $original=[byte[]]::new($i-$start+1);[Array]::Copy($b,$start,$original,0,$original.Length)
            $ranges.Add([pscustomobject]@{ordinal=[long]$ord;offset=[long]$start;length=[long]$original.Length;rangeSha256=(Get-OriginalUsageSha256 $original);originalPath=$Snapshot.Path;originalThreadId=$originalThreadId;originalTurnId=$null;internalBytes=$null;rawRangeAvailable=$false;rawUnavailableReason='record type is not allowlisted';threadId=$thread;turnId=$null;nativeFinalIdentity=$null})
        };$start=$i+1
    }
    if($sessions -ne 1){throw 'NativeSessionMissing'}
    return [pscustomobject]@{Thread=$thread;Rows=$rows.ToArray();Ranges=$ranges.ToArray();MissingUsage=$missingUsage.ToArray();Bytes=[Text.UTF8Encoding]::new($false).GetBytes(($lines -join "`n")+"`n");TailOffset=[long]$start;TailLength=[long]($b.Length-$start)}
}
function Get-OriginalFinalUsageRecords([object[]]$Snapshots){
    $result=[Collections.Generic.Dictionary[string,object]]::new([StringComparer]::Ordinal)
    foreach($snapshot in $Snapshots){
        $native=$snapshot.Native;$states=@{};$active=$null
        foreach($row in $native.Rows){
            if($row.type -ceq 'session_meta'){continue};$turn=$row.payload.turn_id
            if(-not $states.ContainsKey($turn)){$states[$turn]=[pscustomobject]@{Start=$null;Context=$null;Complete=$null;Samples=@()}}
            $s=$states[$turn]
            if($row.type -ceq 'turn_context'){if($null -ne $s.Context){throw 'DuplicateContext'};$s.Context=$row}
            elseif($row.type -ceq 'token_usage_record'){$s.Samples+=@($row)}
            elseif($row.payload.type -ceq 'task_started'){
                if($null -ne $active -or $null -ne $s.Start -or $null -ne $s.Complete){throw 'AmbiguousStart'}
                $attribution=Get-UsagePropertyValue $row.payload 'turn_attribution'
                $attributedTurn=if($attribution -is [System.Collections.IDictionary]){$attribution['turn_id']}else{Get-UsagePropertyValue $attribution 'turn_id'}
                if($null -ne $attributedTurn){$attributedTurn=(ConvertTo-CanonicalNativeIdentity $native.Thread $attributedTurn).Turn}
                if($null -eq $attributedTurn -or $attributedTurn -cne $turn){throw 'NativeStartAttributionMissingOrConflicting'}
                $s.Start=$row;$active=$turn
            }
            elseif($row.payload.type -ceq 'task_complete'){if($active -cne $turn -or $null -ne $s.Complete){throw 'UnmatchedComplete'};$s.Complete=$row;$active=$null}
        }
        foreach($turn in $states.Keys){
            $s=$states[$turn];if($null -eq $s.Start -or $null -eq $s.Context -or $null -eq $s.Complete -or $s.Samples.Count -eq 0){continue}
            $validSamples=@($s.Samples|Where-Object{$null -ne $_.payload.turn_token_usage});if($validSamples.Count -eq 0){continue}
            $prior=$null;foreach($sample in $s.Samples){
                if($null -eq $sample.payload.turn_token_usage){continue}
                if($sample.ordinal -le $s.Start.ordinal -or $sample.ordinal -ge $s.Complete.ordinal){throw 'UsageOutsideInterval'}
                if($null -ne $prior){foreach($f in $script:UsageFields){if($sample.payload.turn_token_usage.$f -lt $prior.$f){throw 'CounterReversal'}}};$prior=$sample.payload.turn_token_usage
            }
            $last=$validSamples[-1]
            $selectedRange=$native.Ranges|Where-Object{$_.ordinal -eq $last.ordinal}|Select-Object -First 1
            $canonical=ConvertTo-CanonicalNativeIdentity $native.Thread $turn
            if(-not ($s.Start.ordinal -lt $s.Context.ordinal -and $s.Context.ordinal -lt $last.ordinal -and $last.ordinal -lt $s.Complete.ordinal)){throw 'ContextIntervalInvalid'}
            if($null -ne $selectedRange){$selectedRange.nativeFinalIdentity=$canonical.Key}
            $key=$canonical.Key
            # Thread and turn define measurement identity; counters are compared for conflicts and ordinals remain provenance.
            $final=[ordered]@{schema='native-final/v2';threadId=$native.Thread;turnId=([guid]$turn).ToString('D');usage=$last.payload.turn_token_usage}
            $body=ConvertTo-PublicBytes $final
            if($result.ContainsKey($key)){if((Get-OriginalUsageSha256 $result[$key].Bytes) -cne (Get-OriginalUsageSha256 $body)){throw 'ConflictingNativeFinal'}}
            else{$result.Add($key,[pscustomobject]@{Relative="finals/$key/final.json";Bytes=$body;Source=[ordered]@{nativeFinalIdentity=$key;threadId=$canonical.Thread;turnId=$canonical.Turn;usage=$last.payload.turn_token_usage};Observations=[Collections.Generic.List[object]]::new()})}
            $range=$native.Ranges|Where-Object{$_.ordinal -eq $last.ordinal}|Select-Object -First 1
            $obs=[ordered]@{nativeFinalIdentity=$key;threadId=$canonical.Thread;turnId=$canonical.Turn;originalPath=$range.originalPath;originalRangeOffset=$range.offset;originalRangeLength=$range.length;originalRangeSha256=$range.rangeSha256;usageOrdinal=$range.ordinal}
            $obsBytes=ConvertTo-PublicBytes $obs;$obsKey=Get-OriginalUsageSha256 (ConvertTo-PublicBytes @($canonical.Thread,$canonical.Turn,$range.originalPath,$range.offset,$range.length,$range.rangeSha256))
            if(-not ($result[$key].Observations|Where-Object Relative -ceq "final-observations/$obsKey.json")){$result[$key].Observations.Add([pscustomobject]@{Relative="final-observations/$obsKey.json";Bytes=$obsBytes;Source=[ordered]@{nativeFinalIdentity=$key;originalPath=$range.originalPath;offset=$range.offset;length=$range.length;rangeSha256=$range.rangeSha256}})}
        }
    };foreach($item in $result.Values){$item}
}
function Get-PublicEventBytes($Snapshot){
    $b=$Snapshot.Bytes;$start=0;$lines=[Collections.Generic.List[string]]::new()
    for($i=0;$i -lt $b.Length;$i++){
        if($b[$i] -ne 10){continue};$len=$i-$start;if($len -gt 1048576){throw 'EventLineLimit'}
        if($len -gt 0){
            $top=Get-PublicSpans $b $start $len
            if((Get-PublicValue $b $top 'kind') -ceq 'notification' -and $top.Contains('data')){
                $ds=Get-PublicSpans $b $top.data.Offset $top.data.Length
                if((Get-PublicValue $b $ds 'method') -ceq 'thread/tokenUsage/updated' -and $ds.Contains('params')){
                    $ps=Get-PublicSpans $b $ds.params.Offset $ds.params.Length;$params=Select-PublicFields $b $ps @('threadId','turnId')
                    if($ps.Contains('tokenUsage')){$ts=Get-PublicSpans $b $ps.tokenUsage.Offset $ps.tokenUsage.Length;$params.tokenUsage=Select-PublicFields $b $ts @('total')}
                    $lines.Add(([ordered]@{kind='notification';data=[ordered]@{method='thread/tokenUsage/updated';params=$params}}|ConvertTo-Json -Depth 20 -Compress))
                }
            }
        };$start=$i+1
    };return [pscustomobject]@{Bytes=[Text.UTF8Encoding]::new($false).GetBytes(($lines -join "`n")+$(if($lines.Count){"`n"}else{''}));TailOffset=[long]$start;TailLength=[long]($b.Length-$start)}
}
function Get-PublicMetadataSources([byte[]]$B,$Top){
    # Scan array elements before decoding: unknown/private members never enter the projection.
    if(-not $Top.Contains('metadataSources')){return}
    $span=$Top['metadataSources'];$end=$span.Offset+$span.Length;$i=$span.Offset
    while($i -lt $end -and $B[$i] -in @(9,10,13,32)){$i++}
    if($i -ge $end -or $B[$i] -ne 91){return};$i++
    while($i -lt $end){
        while($i -lt $end -and $B[$i] -in @(9,10,13,32)){$i++}
        if($i -ge $end){throw 'MetadataSourcesTruncated'};if($B[$i] -eq 93){return}
        $start=$i;$depth=0;$quoted=$false
        while($i -lt $end){
            $c=$B[$i]
            if($quoted){if($c -eq 92){$i+=2;continue};if($c -eq 34){$quoted=$false}}
            else{if($c -eq 34){$quoted=$true}elseif($c -in @(123,91)){$depth++}elseif($c -in @(125,93)){if($depth -eq 0){break};$depth--}elseif($c -eq 44 -and $depth -eq 0){break}}
            $i++
        }
        if($quoted -or $depth -ne 0 -or $i -ge $end){throw 'MetadataSourcesTruncated'}
        if($B[$start] -eq 123){
            $fields=Get-PublicSpans $B $start ($i-$start)
            $field=Get-PublicValue $B $fields 'field';$value=Get-PublicValue $B $fields 'value'
            $valid=$field -cin @('roleId','modelId','reasoningEffort','measurementUTC')
            if($field -ceq 'measurementUTC'){
                $parsed=[datetimeoffset]::MinValue
                $valid=$valid -and $value -is [string] -and $value -cmatch '^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(\.\d{1,7})?(Z|[+-]\d{2}:\d{2})$' -and [datetimeoffset]::TryParse($value,[Globalization.CultureInfo]::InvariantCulture,[Globalization.DateTimeStyles]::AssumeUniversal,[ref]$parsed)
            }else{$valid=$valid -and $value -is [string] -and $value -cmatch '^[A-Za-z0-9][A-Za-z0-9_.:/-]{0,255}$'}
            if($valid){
                $source=Get-PublicValue $B $fields 'source'
                # Only concrete JSON/JSONL paths and the existing explicit historical assignment prefix.
                $safeSource=if($source -is [string] -and $source.Length -le 4096 -and $source -cnotmatch '[\x00-\x1f]' -and $source -cmatch '^(explicit historical import assignment; )?([A-Za-z]:[\\/]|/|\\\\).+\.jsonl?$'){$source}else{$null}
                $safe=[ordered]@{field=$field;value=$value;source=$safeSource}
                if($fields.Contains('sha256')){$hash=Get-PublicValue $B $fields 'sha256';$safe['sha256']=if($hash -is [string] -and $hash -cmatch '^[0-9a-fA-F]{64}$'){$hash}else{$null}}
                if($fields.Contains('basis')){$basis=Get-PublicValue $B $fields 'basis';$safe['basis']=if($basis -ceq 'resolved fresh thread defaults; turn/start has no model or effort override'){$basis}else{$null}}
                if($fields.Contains('authority')){$rank=Get-PublicValue $B $fields 'authority';if($rank -is [int] -and $rank -in @(10,20,30)){$safe['authority']=$rank}}
                [pscustomobject]$safe
            }
        }
        if($B[$i] -eq 93){return};if($B[$i] -ne 44){throw 'MetadataSourcesSeparator'};$i++
    }
    throw 'MetadataSourcesTruncated'
}
function Get-PublicDocumentBytes($Snapshot){
    $top=Get-PublicSpans $Snapshot.Bytes
    $names=if($Snapshot.Kind -ceq 'job'){$script:BindingNames+@('role')}elseif($Snapshot.Kind -ceq 'capture'){$script:BindingNames+@('role','initial_execution_turn')}elseif($Snapshot.Kind -ceq 'expected'){@('version','root_task_ids','coverage','tasks')}
        elseif($Snapshot.Kind -ceq 'ledger'){$script:BindingNames+@('role','token_usage','final','source','counter_kind','counterKind')}
        elseif($Snapshot.Kind -ceq 'profile'){@('schema','task_id','thread_id','turn_id')}
        else{$script:BindingNames+@('schema','initial_execution_turn','complete','startingSnapshot','candidate')}
    $public=Select-PublicFields $Snapshot.Bytes $top $names
    if($Snapshot.Kind -ceq 'capture'){$public['schema']='retained-capture-binding/v1'}
    if($Snapshot.Kind -ceq 'profile'){
        if($public['schema'] -cne 'native-token-profile/v1'){throw 'NativeProfileSchemaInvalid'}
        foreach($field in @('task_id','thread_id','turn_id')){
            $value=$public[$field]
            if($value -isnot [string] -or $value -cnotmatch '^([0-9a-fA-F]{32}|[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12})$'){throw 'NativeProfileIdentityInvalid'}
        }
    }
    if($Snapshot.Kind -cin @('ledger','profile')){
        foreach($field in @('roleId','modelId','reasoningEffort')){
            if(-not $top.Contains($field)){continue};$value=Get-PublicValue $Snapshot.Bytes $top $field
            $public[$field]=if($value -is [string] -and $value -cmatch '^[A-Za-z0-9][A-Za-z0-9_.:/-]{0,255}$'){$value}else{$null}
        }
        foreach($field in @('measurementUTC','importedAtUTC','measurementObservedAtUTC')){
            if(-not $top.Contains($field)){continue};$value=Get-PublicValue $Snapshot.Bytes $top $field;$parsed=[datetimeoffset]::MinValue
            $public[$field]=if($value -is [string] -and $value -cmatch '^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(\.\d{1,7})?(Z|[+-]\d{2}:\d{2})$' -and [datetimeoffset]::TryParse($value,[Globalization.CultureInfo]::InvariantCulture,[Globalization.DateTimeStyles]::AssumeUniversal,[ref]$parsed)){$value}else{$null}
        }
        $basis=Get-PublicValue $Snapshot.Bytes $top 'measurementTimeBasis'
        if($basis -cin @('native_record_timestamp','UTC receipt of last identity-matched native usage notification','native_time_unknown_notification_observation_only')){$public['measurementTimeBasis']=$basis}
        $rawConflicts=Get-PublicValue $Snapshot.Bytes $top 'metadataConflicts'
        $public['metadataConflicts']=@($rawConflicts | Where-Object { $_ -cin @('roleId','modelId','reasoningEffort','measurementUTC') })
        $rawAuthority=Get-PublicValue $Snapshot.Bytes $top 'metadataAuthority'
        $safeAuthority=[ordered]@{}
        foreach($field in @('roleId','modelId','reasoningEffort','measurementUTC')){
            $rank=Get-UsagePropertyValue $rawAuthority $field
            if($rank -is [int] -and $rank -in @(10,20,30)){$safeAuthority[$field]=$rank}
        }
        $public['metadataAuthority']=[pscustomobject]$safeAuthority
        $public['metadataSources']=@(Get-PublicMetadataSources $Snapshot.Bytes $top)
        $requested=if($Snapshot.Kind -ceq 'ledger'){Get-PublicValue $Snapshot.Bytes $top 'requestedProfile'}else{$null}
        if($Snapshot.Kind -ceq 'ledger' -and $null -ne $requested){
            $safeRequested=[ordered]@{effective=$false}
            foreach($field in @('modelId','reasoningEffort')){
                $value=Get-UsagePropertyValue $requested $field
                $safeRequested[$field]=if($value -is [string] -and $value -cmatch '^[A-Za-z0-9][A-Za-z0-9_.:/-]{0,255}$'){$value}else{$null}
            }
            $public['requestedProfile']=[pscustomobject]$safeRequested
        }
    }
    return ConvertTo-PublicBytes $public
}
function New-PublicPlan([string]$Root,$Item){
    $path=[IO.Path]::GetFullPath((Join-Path $Root $Item.Relative));$prefix=[IO.Path]::GetFullPath($Root).TrimEnd('\','/')+[IO.Path]::DirectorySeparatorChar
    if(-not $path.StartsWith($prefix,[StringComparison]::OrdinalIgnoreCase)){throw 'PublicationOutsideArchiveRoot'}
    $receipt=ConvertTo-PublicBytes ([ordered]@{schema='public-retention/v1';path=$path;byteLength=[long]$Item.Bytes.Length;sha256=(Get-OriginalUsageSha256 $Item.Bytes);source=$Item.Source})
    if($Item.Bytes.Length -gt $script:MaximumUsageSnapshotBytes -or $receipt.Length -gt 1048576){throw 'PreparedPublicationLimit'}
    return [pscustomobject]@{Path=$path;Bytes=$Item.Bytes;ReceiptPath="$path.receipt.json";Receipt=$receipt;MarkerPath="$path.commit";Marker=[Text.UTF8Encoding]::new($false).GetBytes((Get-OriginalUsageSha256 $receipt));Stage="$path.stage";StageReceipt="$path.receipt.json.stage";StageMarker="$path.commit.stage"}
}
function Read-PublicPlanState($Plan){
    $all=@($Plan.Path,$Plan.ReceiptPath,$Plan.MarkerPath,$Plan.Stage,$Plan.StageReceipt,$Plan.StageMarker)
    foreach($path in $all){if([IO.Directory]::Exists($path)){throw 'DestinationIsDirectory'}}
    foreach($path in @([IO.Path]::GetDirectoryName($Plan.Path),[IO.Path]::GetDirectoryName($Plan.ReceiptPath),[IO.Path]::GetDirectoryName($Plan.MarkerPath))){
        $cursor=$path
        while($cursor){if([IO.File]::Exists($cursor)){throw 'DestinationParentIsFile'};$parent=[IO.Path]::GetDirectoryName($cursor);if($parent -ceq $cursor){break};$cursor=$parent}
    }
    $present=@($all|Where-Object{[IO.File]::Exists($_)});if($present.Count -eq 0){return 'Absent'}
    if($present.Count -ne 3 -or -not ([IO.File]::Exists($Plan.Path) -and [IO.File]::Exists($Plan.ReceiptPath) -and [IO.File]::Exists($Plan.MarkerPath)) -or [IO.File]::Exists($Plan.Stage) -or [IO.File]::Exists($Plan.StageReceipt) -or [IO.File]::Exists($Plan.StageMarker)){throw 'IncompletePublicationRetainStop'}
    foreach($pair in @(@($Plan.Path,$Plan.Bytes,$script:MaximumUsageSnapshotBytes),@($Plan.ReceiptPath,$Plan.Receipt,1048576L),@($Plan.MarkerPath,$Plan.Marker,256L))){
        $saved=Read-PublicBytes $pair[0] $pair[2]
        if($saved.Length -ne $pair[1].Length -or (Get-OriginalUsageSha256 $saved) -cne (Get-OriginalUsageSha256 $pair[1])){throw 'ImmutableReplayConflictRetainStop'}
    };return 'Committed'
}
function Publish-PublicPlans([object[]]$Plans){
    foreach($plan in $Plans){[void](Read-PublicPlanState $plan)}
    foreach($plan in $Plans){
        if((Read-PublicPlanState $plan) -ceq 'Committed'){continue}
        [IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($plan.Path))|Out-Null
        foreach($pair in @(@($plan.Stage,$plan.Bytes),@($plan.StageReceipt,$plan.Receipt),@($plan.StageMarker,$plan.Marker))){
            Write-PublicBytes $pair[0] $pair[1];$rb=Read-PublicBytes $pair[0]
            if($rb.Length -ne $pair[1].Length -or (Get-OriginalUsageSha256 $rb) -cne (Get-OriginalUsageSha256 $pair[1])){throw 'StageReadbackConflictRetainStop'}
        }
        [IO.File]::Move($plan.Stage,$plan.Path);[IO.File]::Move($plan.StageReceipt,$plan.ReceiptPath);[IO.File]::Move($plan.StageMarker,$plan.MarkerPath)
        [void](Read-PublicPlanState $plan)
    }
}
function Invoke-OriginalUsageAccountingCaller {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$TaskId,[Parameter(Mandatory)][string]$AccountingDirectory,
        [Parameter(Mandatory)][AllowEmptyCollection()][string[]]$ExpectedJobArtifacts,[Parameter(Mandatory)][AllowEmptyCollection()][string[]]$NativeRolloutPaths,[string[]]$NativeEventLogPaths=@(),
        [string[]]$ExpectedTaskSources=@(),[switch]$ExactRootTasks,[switch]$IncludeOwnRecords,
        [Parameter(Mandatory)][string]$ArchiveDirectory,[Parameter(Mandatory)][string]$AccountingScriptsDirectory,
        [string[]]$RootTaskIds,[string[]]$BoundWorkItemIds,[string]$BoundStorePath,[string]$RepositoryRoot,[string]$WorkItemId)
    Import-Module (Join-Path $PSScriptRoot 'AccountingEvidence.psm1')
    [void]([guid]$TaskId)
    if(-not [IO.Path]::IsPathRooted($AccountingDirectory)){throw 'GenuineAccountingDirectoryRequired'}
    if(-not [IO.Path]::IsPathRooted($ArchiveDirectory) -or -not [IO.Path]::IsPathRooted($AccountingScriptsDirectory)){throw 'AbsoluteLocalPathsRequired'}
    if($WorkItemId -and ([string]::IsNullOrWhiteSpace($WorkItemId) -or -not [IO.Path]::IsPathRooted($RepositoryRoot))){throw 'GenuineWorkItemArgumentsRequired'}
    if(([bool]$BoundWorkItemIds) -xor (-not [string]::IsNullOrWhiteSpace($BoundStorePath))){throw 'PairedTaskScopeRequired'}
    if($BoundStorePath -and (-not [IO.Path]::IsPathRooted($BoundStorePath) -or -not [IO.File]::Exists($BoundStorePath))){throw 'GenuineStoreRequired'}
    if($WorkItemId -and (-not $BoundStorePath -or -not [IO.Directory]::Exists($RepositoryRoot) -or $BoundWorkItemIds -cnotcontains $WorkItemId)){throw 'GenuineWorkItemArgumentsRequired'}
    foreach($root in @($RootTaskIds)){[void]([guid]$root)}
    $taskReader=Join-Path $AccountingScriptsDirectory 'Get-TaskTokenUsage.ps1';$metricReader=Join-Path $AccountingScriptsDirectory 'Get-WorkItemMetrics.ps1'
    if(-not [IO.File]::Exists($taskReader) -or ($WorkItemId -and -not [IO.File]::Exists($metricReader))){throw 'ExistingReaderMissing'}
    $descriptors=[Collections.Generic.List[object]]::new()
    # Capture expectations exist before usage, and remain independent of the
    # ledger. Retain their public bindings as explicit job-reader inputs.
    $captures=@(Read-OriginalUsageCaptures $AccountingDirectory)
    foreach($capture in $captures){$descriptors.Add([pscustomobject]@{Kind='capture';Path=$capture.path})}
    $ExpectedJobArtifacts=@(@($ExpectedJobArtifacts)+@(Read-OriginalUsageTurnExpectations $AccountingDirectory | ForEach-Object { $_.sources }) | Select-Object -Unique)
    foreach($group in @(@('job',$ExpectedJobArtifacts),@('native',$NativeRolloutPaths),@('events',$NativeEventLogPaths),@('expected',$ExpectedTaskSources))){
        foreach($path in @($group[1])){$descriptors.Add([pscustomobject]@{Kind=$group[0];Path=[IO.Path]::GetFullPath($path)})}
    }
    foreach($pattern in @('*.usage.json','*.pending-usage.json','*.profile.json','execution-*.json','workitem-transfer-*.json','workitem-current-*.json','capture-binding-*.json')){
        foreach($file in Get-ChildItem -LiteralPath $AccountingDirectory -Filter $pattern -File){$descriptors.Add([pscustomobject]@{Kind=$(if($pattern -cin @('*.usage.json','*.pending-usage.json')){'ledger'}elseif($pattern -ceq '*.profile.json'){'profile'}else{'execution'});Path=$file.FullName})}
    }
    if($descriptors.Count -gt 4096){throw 'InputCountLimit'}
    $missing=@($descriptors|Where-Object{-not [IO.File]::Exists($_.Path)}|ForEach-Object Path)
    if($missing.Count){return [pscustomobject]@{State='blocked_missing_inputs';MissingExpectedSources=$missing;TaskProjection=$null;WorkItemProjection=$null;FamilyClosure='not_asserted'}}
    $snapshots=[Collections.Generic.List[object]]::new();$total=0L
    foreach($d in $descriptors){
        $capture=Read-PublicSource $d.Path $ArchiveDirectory;$b=$capture.Bytes;$total+=$b.Length;if($total -gt 536870912L){throw 'AggregateCaptureLimit'}
        $s=[pscustomobject]@{Kind=$d.Kind;Path=$d.Path;Bytes=$b;Sha256=(Get-OriginalUsageSha256 $b);Native=$null;PublicBytes=$null;TailOffset=$null;TailLength=0L;OriginalReceipt=$capture.OriginalReceipt}
        if($d.Kind -ceq 'native'){$s.Native=Get-PublicNative $s;$s.PublicBytes=$s.Native.Bytes;$s.TailOffset=$s.Native.TailOffset;$s.TailLength=$s.Native.TailLength}
        elseif($d.Kind -ceq 'events'){$e=Get-PublicEventBytes $s;$s.PublicBytes=$e.Bytes;$s.TailOffset=$e.TailOffset;$s.TailLength=$e.TailLength}
        else{$s.PublicBytes=Get-PublicDocumentBytes $s}
        $snapshots.Add($s)
    }
    $finals=@(Get-OriginalFinalUsageRecords @($snapshots|Where-Object Kind -ceq 'native'))
    $originalBindings=@(foreach($s in $snapshots){
        if($s.Kind -in @('job','ledger','execution','capture')){[Text.UTF8Encoding]::new($false,$true).GetString($s.PublicBytes)|ConvertFrom-Json}
        elseif($s.Kind -ceq 'expected'){$doc=[Text.UTF8Encoding]::new($false,$true).GetString($s.PublicBytes)|ConvertFrom-Json;$doc.tasks}
    })
    $genuineTask=$false;$genuineScope=$false
    foreach($binding in $originalBindings){
        $task=Get-UsagePropertyValue $binding 'task_id';if($null -eq $task){$task=Get-UsagePropertyValue $binding 'taskId'}
        if($null -ne $task -and ([guid]$task) -eq ([guid]$TaskId)){$genuineTask=$true}
        $wid=Get-UsagePropertyValue $binding 'work_item_id';if($null -eq $wid){$wid=Get-UsagePropertyValue $binding 'workItemId'}
        $store=Get-UsagePropertyValue $binding 'store_path';if($null -eq $store){$store=Get-UsagePropertyValue $binding 'storePath'};if($null -eq $store){$store=Get-UsagePropertyValue $binding 'work_item_store_path'}
        if($WorkItemId -and $wid -ceq $WorkItemId -and $store -is [string] -and [IO.Path]::GetFullPath($store).Equals([IO.Path]::GetFullPath($BoundStorePath),[StringComparison]::OrdinalIgnoreCase)){$genuineScope=$true}
    }
    if(-not $genuineTask -or ($WorkItemId -and -not $genuineScope)){throw 'RequestedTaskOrWorkItemHasNoOriginalBinding; retain input sources'}
    $index=@($snapshots|ForEach-Object{[ordered]@{kind=$_.Kind;sourcePath=$_.Path;observedLength=[long]$_.Bytes.Length;observedSha256=$_.Sha256;publicSha256=(Get-OriginalUsageSha256 $_.PublicBytes);tailOffset=$_.TailOffset;tailLength=$_.TailLength}})
    $id=Get-OriginalUsageSha256 (ConvertTo-PublicBytes $index);$base="retained/$id";$items=[Collections.Generic.List[object]]::new();$map=@{job=@();native=@();events=@();expected=@()}
    foreach($s in $snapshots){
        $slot=Get-OriginalUsageSha256 ([Text.UTF8Encoding]::new($false).GetBytes($s.Path));$name=[IO.Path]::GetFileName($s.Path)
        $relative=if($s.Kind -ceq 'capture'){"$base/accounting/capture-binding-$slot.json"}elseif($s.Kind -in @('ledger','execution','profile')){"$base/accounting/$name"}else{"$base/$($s.Kind)/$slot/$name"}
        $source=[ordered]@{path=$s.Path;observedLength=[long]$s.Bytes.Length;observedSha256=$s.Sha256;tailOffset=$s.TailOffset;tailLength=$s.TailLength;originalReceipt=$s.OriginalReceipt}
        if($s.Kind -ceq 'native'){
            $source.ranges=@($s.Native.Ranges|ForEach-Object{[ordered]@{ordinal=$_.ordinal;offset=$_.offset;length=$_.length;rangeSha256=$_.rangeSha256;originalPath=$_.originalPath;originalThreadId=$_.originalThreadId;originalTurnId=$_.originalTurnId;rawRangeAvailable=$_.rawRangeAvailable;rawUnavailableReason=$_.rawUnavailableReason;threadId=$_.threadId;turnId=$_.turnId;nativeFinalIdentity=$_.nativeFinalIdentity}})
            foreach($range in $s.Native.Ranges){
                if($range.rawRangeAvailable){$items.Add([pscustomobject]@{Relative="$base/raw-ranges/$slot-$($range.ordinal)-$($range.rangeSha256).jsonl-record";Bytes=$range.internalBytes;Source=[ordered]@{kind='native-original-record';originalPath=$range.originalPath;offset=$range.offset;length=$range.length;ordinal=$range.ordinal;rangeSha256=$range.rangeSha256;originalThreadId=$range.originalThreadId;originalTurnId=$range.originalTurnId;threadId=$range.threadId;turnId=$range.turnId;nativeFinalIdentity=$range.nativeFinalIdentity}})}
            }
        }
        $items.Add([pscustomobject]@{Relative=$relative;Bytes=$s.PublicBytes;Source=$source})
        if($map.ContainsKey($s.Kind)){$map[$s.Kind]+=@([IO.Path]::GetFullPath((Join-Path $ArchiveDirectory $relative)))}
        if($s.Kind -ceq 'capture'){$map.job+=@([IO.Path]::GetFullPath((Join-Path $ArchiveDirectory $relative)))}
    }
    foreach($f in $finals){$items.Add([pscustomobject]@{Relative=$f.Relative;Bytes=$f.Bytes;Source=$f.Source});foreach($observation in $f.Observations){$items.Add($observation)}}
    $registrations=@($finals|ForEach-Object{[ordered]@{path=$_.Relative;sha256=(Get-OriginalUsageSha256 $_.Bytes)}})
    $missingUsage=@(foreach($s in $snapshots){if($s.Kind -ceq 'native'){$s.Native.MissingUsage}})
    $items.Add([pscustomobject]@{Relative="$base/missing-usage.json";Bytes=(ConvertTo-PublicBytes $missingUsage);Source=$null})
    $snapshotObservationProvenance=@(foreach($s in $snapshots){if($s.Kind -ceq 'native'){[ordered]@{sourcePath=$s.Path;sourceSnapshotSha256=$s.Sha256;finalRanges=@($s.Native.Ranges|Where-Object{$null -ne $_.nativeFinalIdentity}|ForEach-Object{[ordered]@{ordinal=$_.ordinal;offset=$_.offset;length=$_.length;rangeSha256=$_.rangeSha256;nativeFinalIdentity=$_.nativeFinalIdentity}})}}})
    $items.Add([pscustomobject]@{Relative="$base/bundle.json";Bytes=(ConvertTo-PublicBytes ([ordered]@{schema='observed-public-bundle/v1';inputs=$index;readerPaths=$map;finalRegistrations=$registrations;observationSnapshotProvenance=$snapshotObservationProvenance;missingUsagePath="$base/missing-usage.json";familyComplete=$false}));Source=$null})
    $plans=@($items|ForEach-Object{New-PublicPlan $ArchiveDirectory $_})
    $accountingTarget=[IO.Path]::GetFullPath((Join-Path $ArchiveDirectory "$base/accounting"))
    if([IO.File]::Exists($accountingTarget)){throw 'AccountingDirectoryIsFile'}
    $accountingParent=[IO.Path]::GetDirectoryName($accountingTarget);while($accountingParent){if([IO.File]::Exists($accountingParent)){throw 'PublicationParentIsFile'};$next=[IO.Path]::GetDirectoryName($accountingParent);if($next -ceq $accountingParent){break};$accountingParent=$next}
    foreach($plan in $plans){foreach($target in @($plan.Path,$plan.ReceiptPath,$plan.MarkerPath,$plan.Stage,$plan.StageReceipt,$plan.StageMarker)){
        if([IO.Directory]::Exists($target)){throw 'PublicationDestinationIsDirectory'}
        if($target.Equals($accountingTarget,[StringComparison]::OrdinalIgnoreCase) -or $accountingTarget.StartsWith($target+[IO.Path]::DirectorySeparatorChar,[StringComparison]::OrdinalIgnoreCase)){throw 'AccountingDirectoryPublicationOverlap'}
        $parent=[IO.Path]::GetDirectoryName($target);while($parent){if([IO.File]::Exists($parent)){throw 'PublicationParentIsFile'};$next=[IO.Path]::GetDirectoryName($parent);if($next -ceq $parent){break};$parent=$next}
    }}
    $allPaths=[Collections.Generic.List[string]]::new()
    foreach($plan in $plans){foreach($path in @($plan.Path,$plan.ReceiptPath,$plan.MarkerPath,$plan.Stage,$plan.StageReceipt,$plan.StageMarker)){$allPaths.Add($path)}}
    for($i=0;$i -lt $allPaths.Count;$i++){for($j=$i+1;$j -lt $allPaths.Count;$j++){
        if($allPaths[$i].Equals($allPaths[$j],[StringComparison]::OrdinalIgnoreCase) -or $allPaths[$i].StartsWith($allPaths[$j]+[IO.Path]::DirectorySeparatorChar,[StringComparison]::OrdinalIgnoreCase) -or $allPaths[$j].StartsWith($allPaths[$i]+[IO.Path]::DirectorySeparatorChar,[StringComparison]::OrdinalIgnoreCase)){throw 'PublicationTargetOverlap'}
    }}
    foreach($plan in $plans){[void](Read-PublicPlanState $plan)}
    Publish-PublicPlans $plans
    foreach($plan in $plans){[void](Read-PublicPlanState $plan)}
    $retainedAccounting=[IO.Path]::GetFullPath((Join-Path $ArchiveDirectory "$base/accounting"));[IO.Directory]::CreateDirectory($retainedAccounting)|Out-Null
    $shared=@{AccountingDirectory=$retainedAccounting;ExpectedTaskSources=[string[]]$map.expected;ExpectedJobArtifacts=[string[]]$map.job;NativeRolloutPaths=[string[]]$map.native;NativeEventLogPaths=[string[]]$map.events}
    $taskArgs=@{TaskId=$TaskId;ExactRootTasks=$ExactRootTasks;IncludeOwnRecords=$IncludeOwnRecords};foreach($key in $shared.Keys){$taskArgs[$key]=$shared[$key]}
    if($RootTaskIds){$taskArgs.RootTaskIds=$RootTaskIds};if($BoundWorkItemIds){$taskArgs.BoundWorkItemIds=$BoundWorkItemIds;$taskArgs.BoundStorePath=$BoundStorePath}
    $storeBefore=if($WorkItemId){Get-OriginalUsageSha256 (Read-PublicBytes $BoundStorePath)}else{$null}
    $taskProjection=& $taskReader @taskArgs;$workItemProjection=$null
    if($WorkItemId -and (Get-OriginalUsageSha256 (Read-PublicBytes $BoundStorePath)) -cne $storeBefore){throw 'StoreChangedDuringTaskProjection; preserve bundle, reject joint result'}
    foreach($plan in $plans){[void](Read-PublicPlanState $plan)}
    if($WorkItemId){
        $metricsArgs=@{StorePath=$BoundStorePath;WorkItemId=$WorkItemId;RepositoryRoot=$RepositoryRoot};foreach($key in $shared.Keys){$metricsArgs[$key]=$shared[$key]}
        $workItemProjection=& $metricReader @metricsArgs
        if((Get-OriginalUsageSha256 (Read-PublicBytes $BoundStorePath)) -cne $storeBefore){throw 'StoreChangedDuringProjection; preserve bundle, reject joint result'}
    }
    foreach($plan in $plans){[void](Read-PublicPlanState $plan)}
    return [pscustomobject]@{State='observed_projection';BundleId=$id;TaskProjection=$taskProjection;WorkItemProjection=$workItemProjection;RetainedInputs=$map;ObservedInputs=$index;MissingUsage=$missingUsage;ArchivedFinalMeasurements=@($finals|ForEach-Object Relative);FamilyClosure='not_asserted';OwnerAuthentication='not_asserted'}
}
Export-ModuleMember -Function Invoke-OriginalUsageAccountingCaller
