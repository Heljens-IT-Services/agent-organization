# Shared production semantics; dot-sourced without creating another store.
function Get-HIValue($Object, [string]$Name, $Default = $null) {
    if ($null -eq $Object) { return $Default }
    if ($Object -is [Collections.IDictionary]) { if ($Object.Contains($Name)) { return $Object[$Name] }; return $Default }
    $property = $Object.PSObject.Properties[$Name]
    if ($null -ne $property) { return $property.Value }
    return $Default
}

function Get-HIHash([byte[]]$Bytes) {
    $sha = [Security.Cryptography.SHA256]::Create()
    try { return ([BitConverter]::ToString($sha.ComputeHash($Bytes))).Replace('-', '').ToLowerInvariant() }
    finally { $sha.Dispose() }
}

function Get-HIRequestId($Item) {
    $human = Get-HIValue $Item 'humanInteraction'
    $id = Get-HIValue $human 'requestId'
    if ($id) { return [string]$id }
    # Deterministic legacy key, scoped to the real WorkItem and exact timestamp.
    return 'legacy-' + (Get-HIHash ([Text.Encoding]::UTF8.GetBytes([string]$Item.id + "`n" + [string](Get-HIValue $human 'requestedAt'))))
}

function Test-HISatisfied($Human) {
    if ($null -eq $Human) { return $true }
    $response = Get-HIValue $Human 'response'
    if ($null -eq $response) { return $false }
    $requestId = Get-HIValue $Human 'requestId'
    if (-not $requestId) { return (Get-HIValue $Human 'kind') -cne 'approval' }
    if ((Get-HIValue $Human 'resolution') -cne 'satisfied' -or (Get-HIValue $response 'requestId') -cne $requestId) { return $false }
    if ((Get-HIValue $response 'respondentId') -cne (Get-HIValue $Human 'humanId') -or -not (Get-HIValue $response 'evidence')) { return $false }
    $decision = Get-HIValue $response 'decision'
    if ((Get-HIValue $Human 'kind') -ceq 'approval') {
        $proposal = Get-HIValue $Human 'proposal'
        return $null -ne $proposal -and $decision -ceq 'approved' -and (Get-HIValue $response 'proposalSha256') -ceq (Get-HIValue $proposal 'sha256')
    }
    return $decision -ceq 'provided'
}

function Get-HIResponseBlockReason($Human) {
    $response=Get-HIValue $Human 'response'
    if ($null -eq $response) { return $null }
    $decision=Get-HIValue $response 'decision'
    if ($decision -cin @('rejected','insufficient')) { return 'Human ' + $decision + ': ' + (Get-HIValue $response 'description') + ' | ' + (Get-HIValue $response 'evidence') }
    return 'Human response persisted; awaiting bound resume assessment.'
}

function Test-HIOnlyWaiting($Item) {
    $human=Get-HIValue $Item 'humanInteraction'
    if ((Get-HIValue $Item 'status') -cne 'blocked' -or $null -eq $human -or (Test-HISatisfied $human)) { return $false }
    $response=Get-HIValue $human 'response'; $reason=Get-HIValue $Item 'blockReason'
    if ($null -eq $response) { return $null -eq (Get-HIValue $human 'resolution') -and $null -eq $reason }
    # A rejected/insufficient request still blocks only its own work while awaiting
    # explicit renewal. Preserve independent siblings only for its exact marker.
    $resolution=Get-HIValue $human 'resolution'
    return $resolution -cin @('rejected','insufficient') -and $resolution -ceq (Get-HIValue $response 'decision') -and $reason -ceq (Get-HIResponseBlockReason $human)
}

function Assert-HIProposal($Proposal, [bool]$RequirePath = $true) {
    if ($null -eq $Proposal -or [string]::IsNullOrWhiteSpace([string](Get-HIValue $Proposal 'reference')) -or [string](Get-HIValue $Proposal 'sha256') -cnotmatch '^[a-f0-9]{64}$') { throw 'A proposal requires its concrete reference and SHA-256.' }
    if ($RequirePath -and ((Get-HIValue $Proposal 'path') -isnot [string] -or [string]::IsNullOrWhiteSpace([string](Get-HIValue $Proposal 'path')))) { throw 'A bound proposal requires an explicit local byte-source path; renew legacy requests without one.' }
}

function Assert-HIProposalCurrent($Human) {
    $proposal=Get-HIValue $Human 'proposal'
    if ($null -eq $proposal) { return }
    Assert-HIProposal $proposal
    $path=Get-HIValue $proposal 'path'
    if ((Get-HIHash ([IO.File]::ReadAllBytes([IO.Path]::GetFullPath([string]$path)))) -cne (Get-HIValue $proposal 'sha256')) { throw 'Proposal bytes changed; renew the request before continuing.' }
}

function New-HIRequest([string]$Kind, [string]$Description, [string]$HumanId, $Proposal, [string]$RequestedAt) {
    if ($Kind -cnotin @('clarification','approval','action') -or [string]::IsNullOrWhiteSpace($Description)) { throw 'Invalid human request.' }
    if ($HumanId -cnotmatch '^[a-z0-9][a-z0-9_-]{0,127}$') { throw 'A responsible human actor ID is required.' }
    if ($Kind -ceq 'approval' -or $null -ne $Proposal) {
        Assert-HIProposal $Proposal
        $Proposal=[pscustomobject]@{reference=(Get-HIValue $Proposal 'reference'); sha256=(Get-HIValue $Proposal 'sha256'); path=[IO.Path]::GetFullPath([string](Get-HIValue $Proposal 'path'))}
        Assert-HIProposalCurrent ([pscustomobject]@{proposal=$Proposal})
    }
    return [pscustomobject][ordered]@{kind=$Kind; description=$Description; requestedAt=$RequestedAt; response=$null; requestId=('human-' + [guid]::NewGuid().ToString('N')); required=$true; humanId=$HumanId; proposal=$Proposal; resolution=$null}
}

function Assert-HIInteraction($Human) {
    if ($null -eq $Human -or -not (Get-HIValue $Human 'requestId')) { return }
    if ((Get-HIValue $Human 'required') -ne $true -or [string](Get-HIValue $Human 'humanId') -cnotmatch '^[a-z0-9][a-z0-9_-]{0,127}$') { throw 'Human request lacks responsible human/required binding.' }
    $proposal = Get-HIValue $Human 'proposal'
    # Snapshot/history readability includes pathless legacy bindings; new writes
    # and every byte-consuming operation require the explicit source separately.
    if ((Get-HIValue $Human 'kind') -ceq 'approval' -or $proposal) { Assert-HIProposal $proposal $false }
    $response = Get-HIValue $Human 'response'
    if ($null -eq $response) { if ($null -ne (Get-HIValue $Human 'resolution')) { throw 'Resolution requires an actual human response.' }; return }
    if ((Get-HIValue $response 'requestId') -cne (Get-HIValue $Human 'requestId') -or (Get-HIValue $response 'respondentId') -cne (Get-HIValue $Human 'humanId') -or [string]::IsNullOrWhiteSpace([string](Get-HIValue $response 'evidence'))) { throw 'Human response identity/request/source mismatch.' }
    $decision = Get-HIValue $response 'decision'
    if ($decision -cnotin @('provided','approved','rejected','insufficient')) { throw 'Explicit human response decision required.' }
    if ($proposal -and (Get-HIValue $response 'proposalSha256') -cne (Get-HIValue $proposal 'sha256')) { throw 'Human response proposal version mismatch.' }
    if ($decision -cin @('provided','approved')) {
        if (-not (Test-HISatisfied $Human)) { throw 'Human response does not satisfy this request.' }
    } elseif ((Get-HIValue $Human 'resolution') -cne $decision) { throw 'Negative response resolution mismatch.' }
}

function Assert-HITransition($Old, $New, [bool]$HumanResponseWrite) {
    $before = Get-HIValue $Old 'humanInteraction'; $after = Get-HIValue $New 'humanInteraction'
    $oldHistory = @(Get-HIValue $Old 'humanInteractionHistory' @()); $newHistory = @(Get-HIValue $New 'humanInteractionHistory' @())
    if ($newHistory.Count -lt $oldHistory.Count) { throw 'Human request history removed.' }
    for ($i=0; $i -lt $oldHistory.Count; $i++) { if ((ConvertTo-Json $oldHistory[$i] -Depth 30 -Compress) -cne (ConvertTo-Json $newHistory[$i] -Depth 30 -Compress)) { throw 'Human request history changed.' } }
    $renewed = $null -ne $before -and $null -ne $after -and (Get-HIRequestId $Old) -cne (Get-HIRequestId $New)
    if ($null -ne $after -and ($null -eq $before -or $renewed)) {
        $proposal=Get-HIValue $after 'proposal'
        if ((Get-HIValue $after 'kind') -ceq 'approval' -and (Get-HIValue $after 'requestId') -or $null -ne $proposal) { Assert-HIProposal $proposal; Assert-HIProposalCurrent $after }
    }
    if ($renewed) {
        foreach ($historical in $oldHistory) {
            $historicalId=Get-HIValue $historical 'requestId'
            if ($historicalId -and $historicalId -ceq (Get-HIValue $after 'requestId')) { throw 'A renewed request ID cannot reuse history.' }
        }
        if ($newHistory.Count -ne $oldHistory.Count+1 -or (ConvertTo-Json $newHistory[-1] -Depth 30 -Compress) -cne (ConvertTo-Json $before -Depth 30 -Compress) -or $null -ne (Get-HIValue $after 'response') -or $New.status -cne 'blocked' -or -not (Get-HIValue $after 'requestId') -or [DateTimeOffset]::Parse($after.requestedAt) -le [DateTimeOffset]::Parse($before.requestedAt)) { throw 'Renewal requires a new open request and exact archived predecessor.' }
    } else {
        if ($newHistory.Count -ne $oldHistory.Count) { throw 'History append requires request renewal.' }
        if ($null -ne $before) {
            if ($null -eq $after) { throw 'Human request cannot be removed, including on cancellation.' }
            foreach ($field in @('kind','description','requestedAt','proposal','required')) {
                if ($field -ceq 'required' -and $null -eq (Get-HIValue $before $field) -and $HumanResponseWrite) { continue }
                if ((ConvertTo-Json (Get-HIValue $before $field) -Depth 30 -Compress) -cne (ConvertTo-Json (Get-HIValue $after $field) -Depth 30 -Compress)) { throw "Human request changed: $field" }
            }
            foreach ($field in @('requestId','humanId')) {
                $value=Get-HIValue $before $field
                if ($value -and $value -cne (Get-HIValue $after $field)) { throw "Human request binding changed: $field" }
                if (-not $value -and (Get-HIValue $after $field) -and -not $HumanResponseWrite) { throw 'Legacy request enrichment requires human response or explicit renewal.' }
            }
            $oldResponse=Get-HIValue $before 'response'; $newResponse=Get-HIValue $after 'response'
            if ($null -ne $oldResponse -and (ConvertTo-Json $before -Depth 30 -Compress) -cne (ConvertTo-Json $after -Depth 30 -Compress)) { throw 'Persisted human response is immutable; renew the request.' }
            if ($null -eq $oldResponse -and $null -ne $newResponse -and -not $HumanResponseWrite) { throw 'Human responses must use the dedicated human input command.' }
            if ($null -eq $oldResponse -and ((Get-HIValue $before 'resolution') -cne (Get-HIValue $after 'resolution')) -and -not $HumanResponseWrite) { throw 'Status cannot resolve a human request.' }
        } elseif ($null -ne $after -and $null -ne (Get-HIValue $after 'response')) { throw 'A new request cannot contain an answer.' }
    }
    if ($null -ne $before) {
        foreach ($field in @('parentId','title','description','owner','goal','specification','acceptanceCriteria','dependencies')) { if ((ConvertTo-Json $Old.$field -Depth 30 -Compress) -cne (ConvertTo-Json $New.$field -Depth 30 -Compress)) { throw "Requested WorkItem scope changed: $field; plan a separate WorkItem." } }
    }
    if ($null -ne $after -and $New.status -cnotin @('blocked','cancelled')) {
        if (-not (Test-HISatisfied $after)) { throw 'Unresolved or rejected human request blocks this work.' }
        Assert-HIProposalCurrent $after
    }
    Assert-HIInteraction $after
}
