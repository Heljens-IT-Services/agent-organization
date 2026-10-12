[CmdletBinding()]
param([string]$ResultPath)
$ErrorActionPreference = 'Stop'
$repo = Split-Path -Parent $PSScriptRoot
. (Join-Path $PSScriptRoot 'contracts\ContractValidation.ps1')
$temp = Join-Path ([IO.Path]::GetTempPath()) ('agent-org-contracts-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $temp | Out-Null
$utf8 = New-Object System.Text.UTF8Encoding($false)
$checks = New-Object 'System.Collections.Generic.List[object]'

function Save-TestJson($Value, [string]$Name = 'current.json') {
    $file = Join-Path $temp $Name
    [IO.File]::WriteAllText($file, (ConvertTo-Json -InputObject $Value -Depth 100), $utf8)
    return $file
}
function Copy-TestDocument($Value) { return ,((Get-ContractCanonicalJson $Value) | ConvertFrom-Json) }
function Assert-Pass([string]$Name, [scriptblock]$Action) {
    $result = & $Action
    if (-not $result.valid) { throw "Expected valid result: $Name" }
    $checks.Add([pscustomobject]@{ name = $Name; passed = $true })
}
function Assert-Reject([string]$Name, [scriptblock]$Action, [string]$Message) {
    $failure = $null
    try { $null = & $Action } catch { $failure = $_.Exception.Message }
    if ($null -eq $failure -or $failure -notmatch [regex]::Escape($Message)) { throw "Expected rejection '$Message' for ${Name}; got: $failure" }
    $checks.Add([pscustomobject]@{ name = $Name; passed = $true })
}
function Check-WorkItems($Value, $Previous = $null) {
    $file = Save-TestJson $Value
    if ($null -ne $Previous) {
        $prior = Save-TestJson $Previous 'previous.json'
        return (& (Join-Path $PSScriptRoot 'Test-WorkItems.ps1') -Path $file -PreviousPath $prior)
    }
    return (& (Join-Path $PSScriptRoot 'Test-WorkItems.ps1') -Path $file)
}
function Check-Invalid([string]$Name, [scriptblock]$Mutation, [string]$Message) {
    $d = Copy-TestDocument $planned
    & $Mutation $d
    Assert-Reject $Name { Check-WorkItems $d } $Message
}
function Set-Implemented($Item, [string]$At) {
    $Item.status = 'implemented'; $Item.implementedAt = $At; $Item.updatedAt = $At
    $Item.result = [pscustomobject]@{ summary = 'Result available'; evidence = @('test execution evidence') }
}
function Add-Verification($Item, [string]$At, [bool]$Passed) {
    $results = @($Item.acceptanceCriteria | ForEach-Object { [pscustomobject]@{ criterionId = $_.id; passed = $Passed; evidence = 'Independent criterion outcome' } })
    $Item.verifications = @($Item.verifications) + [pscustomobject]@{
        implementedAt = $Item.implementedAt; checkedAt = $At
        reviewer = [pscustomobject]@{ type = 'human'; id = 'reviewer' }; passed = $Passed; results = $results
    }
    $Item.updatedAt = $At
}

try {
    $planned = Read-ContractJson (Join-Path $repo 'examples\workitems\goal-with-children.json')
    $blocked = Read-ContractJson (Join-Path $repo 'examples\workitems\human-blocked.json')
    $accepted = Read-ContractJson (Join-Path $repo 'examples\workitems\accepted-parent.json')
    Assert-Pass 'Goal with two subtasks' { Check-WorkItems $planned }
    Assert-Pass 'Human-blocked WorkItem' { Check-WorkItems $blocked }
    Assert-Pass 'Parent with own successful business verification' { Check-WorkItems $accepted }
    foreach ($file in Get-ChildItem -LiteralPath (Join-Path $repo 'examples\workitems\invalid') -Filter '*.json') {
        Assert-Reject ('Invalid fixture ' + $file.Name) { & (Join-Path $PSScriptRoot 'Test-WorkItems.ps1') -Path $file.FullName } ''
    }
    Check-Invalid 'Duplicate IDs' { param($d) $d.items[2].id = $d.items[1].id } 'Duplicate WorkItem ID'
    Check-Invalid 'Missing parent' { param($d) $d.items[1].parentId = 'missing' } 'Missing parent'
    Check-Invalid 'Missing dependency' { param($d) $d.items[1].dependencies = @('missing') } 'Missing dependency'
    Check-Invalid 'Parent cycle' { param($d) $d.items[0].parentId = $d.items[1].id } 'Parent cycle'
    Check-Invalid 'Dependency cycle' { param($d) $d.items[1].dependencies = @('task-b'); $d.items[2].dependencies = @('task-a') } 'Dependency cycle'
    Check-Invalid 'Mixed completion deadlock' { param($d) $d.items[1].dependencies = @('goal') } 'Completion dependency cycle'
    Check-Invalid 'Duplicate dependencies' { param($d) $d.items[1].dependencies = @('task-b','task-b') } 'Schema uniqueItems'
    Check-Invalid 'Wrong JSON type' { param($d) $d.items[0].title = $false } 'Schema type'
    Check-Invalid 'Unknown status' { param($d) $d.items[0].status = 'done' } 'Schema enum'
    Check-Invalid 'Missing required field' { param($d) $d.items[0].PSObject.Properties.Remove('goal') } 'Schema required'
    Check-Invalid 'Unknown field' { param($d) $d.items[0] | Add-Member unknown 'value' } 'Schema additional property'
    Check-Invalid 'Whitespace title' { param($d) $d.items[0].title = '   ' } 'Schema pattern'
    Check-Invalid 'Invalid timestamp' { param($d) $d.items[0].updatedAt = '2026-02-30T10:00:00Z' } 'Schema date-time'
    Check-Invalid 'Timestamp regression' { param($d) $d.items[0].updatedAt = '2026-10-11T10:00:00Z' } 'Timestamp order'
    Check-Invalid 'Duplicate criteria' { param($d) $d.items[0].acceptanceCriteria += $d.items[0].acceptanceCriteria[0] } 'Duplicate criterion'
    Check-Invalid 'Missing criteria' { param($d) $d.items[0].acceptanceCriteria = @() } 'Schema minItems'
    Check-Invalid 'Implemented without evidence' { param($d) $d.items[0].status = 'implemented' } 'Missing implementedAt'
    Check-Invalid 'Accepted without own verification' { param($d) Set-Implemented $d.items[0] '2026-10-12T10:02:00Z'; $d.items[0].status = 'accepted' } 'Missing acceptance evidence'
    Check-Invalid 'Rework without failed verification' { param($d) Set-Implemented $d.items[0] '2026-10-12T10:02:00Z'; $d.items[0].status = 'rework' } 'Rework requires failed'
    Check-Invalid 'Missing actor role' { param($d) $d.items[0].owner = [pscustomobject]@{ type = 'agent'; id = 'not_installed' } } 'Missing actor role'
    Check-Invalid 'Missing Markdown reference' { param($d) $d.items[0].specification = [pscustomobject]@{ markdown = 'docs/absent.md' } } 'Missing referenced file'
    Check-Invalid 'Markdown path traversal' { param($d) $d.items[0].specification = [pscustomobject]@{ markdown = '../README.md' } } 'Unsafe relative reference'
    Check-Invalid 'Two specification variants' { param($d) $d.items[0].specification | Add-Member markdown 'README.md' } 'Schema anyOf'
    $markdown = Copy-TestDocument $planned
    $markdown.items[0].specification = [pscustomobject]@{ markdown = 'README.md' }
    Assert-Pass 'Existing Markdown reference' { Check-WorkItems $markdown }
    $agentOwned = Copy-TestDocument $planned; $agentOwned.items[0].owner = [pscustomobject]@{ type = 'agent'; id = 'koordinator' }
    Assert-Pass 'Registered agent owner' { Check-WorkItems $agentOwned }
    $active = Copy-TestDocument $planned
    foreach ($item in $active.items) { $item.status = 'in_progress'; $item.updatedAt = '2026-10-12T10:01:00Z' }
    Assert-Pass 'planned to in_progress' { Check-WorkItems $active $planned }
    $implemented = Copy-TestDocument $active
    foreach ($item in $implemented.items) { Set-Implemented $item '2026-10-12T10:02:00Z' }
    Assert-Pass 'Implementation stays open without verification' { Check-WorkItems $implemented $active }
    Assert-Reject 'Cannot skip implementation' { Check-WorkItems $accepted $planned } 'Invalid status transition'
    $childrenAccepted = Copy-TestDocument $implemented
    foreach ($item in $childrenAccepted.items[1..2]) {
        Add-Verification $item '2026-10-12T10:03:00Z' $true
        $item.status = 'accepted'; $item.acceptedAt = '2026-10-12T10:03:00Z'
    }
    Assert-Pass 'Accepted children leave parent open' { Check-WorkItems $childrenAccepted $implemented }
    $uncheckedParent = Copy-TestDocument $childrenAccepted
    $uncheckedParent.items[0].status = 'accepted'; $uncheckedParent.items[0].acceptedAt = '2026-10-12T10:04:00Z'; $uncheckedParent.items[0].updatedAt = '2026-10-12T10:04:00Z'
    Assert-Reject 'Children cannot replace parent acceptance' { Check-WorkItems $uncheckedParent $childrenAccepted } 'Missing acceptance evidence'
    $rework = Copy-TestDocument $childrenAccepted
    Add-Verification $rework.items[0] '2026-10-12T10:04:00Z' $false
    $rework.items[0].status = 'rework'
    Assert-Pass 'Failed parent business criteria require rework' { Check-WorkItems $rework $childrenAccepted }
    $wrongFailure = Copy-TestDocument $rework; $wrongFailure.items[0].status = 'implemented'
    Assert-Reject 'Failure cannot stay implemented' { Check-WorkItems $wrongFailure } 'Failed verification requires rework'
    $reimplemented = Copy-TestDocument $rework
    Set-Implemented $reimplemented.items[0] '2026-10-12T10:05:00Z'
    Assert-Pass 'Rework to new implementation retains history' { Check-WorkItems $reimplemented $rework }
    $finished = Copy-TestDocument $reimplemented
    Add-Verification $finished.items[0] '2026-10-12T10:06:00Z' $true
    $finished.items[0].status = 'accepted'; $finished.items[0].acceptedAt = '2026-10-12T10:06:00Z'
    Assert-Pass 'Independent parent acceptance after rework' { Check-WorkItems $finished $reimplemented }
    Assert-Pass 'Idempotent snapshot' { Check-WorkItems $finished $finished }
    $bad = Copy-TestDocument $finished; $bad.items[0].title = 'Changed'; $bad.items[0].updatedAt = '2026-10-12T10:07:00Z'
    Assert-Reject 'Accepted task is immutable' { Check-WorkItems $bad $finished } 'Terminal WorkItem is immutable'
    $bad = Copy-TestDocument $finished; $bad.items = @($bad.items[0..1])
    Assert-Reject 'Stable IDs cannot disappear' { Check-WorkItems $bad $finished } 'WorkItem removal'
    $bad = Copy-TestDocument $childrenAccepted; $bad.items[0].createdAt = '2026-10-12T09:59:00Z'; $bad.items[0].updatedAt = '2026-10-12T10:04:00Z'
    Assert-Reject 'Creation timestamp is immutable' { Check-WorkItems $bad $childrenAccepted } 'Immutable createdAt'
    $bad = Copy-TestDocument $childrenAccepted; $bad.items[0].title = 'Changed'
    Assert-Reject 'Updates must advance timestamp' { Check-WorkItems $bad $childrenAccepted } 'Update must advance'
    $bad = Copy-TestDocument $reimplemented; $bad.items[0].verifications = @()
    Assert-Reject 'Verification history cannot be removed' { Check-WorkItems $bad $rework } 'Verification history removed'
    $bad = Copy-TestDocument $reimplemented; $bad.items[0].verifications[0].results[0].evidence = 'Changed history'
    Assert-Reject 'Verification history cannot be altered' { Check-WorkItems $bad $rework } 'Verification history changed'
    $bad = Copy-TestDocument $reimplemented; $bad.items[0].implementedAt = '2026-10-12T10:02:00Z'
    Assert-Reject 'Failed implementation cannot be reused' { Check-WorkItems $bad } 'Failed verification requires rework'
    $bad = Copy-TestDocument $childrenAccepted; $bad.items[0].specification.inline = 'New scope'; $bad.items[0].updatedAt = '2026-10-12T10:04:00Z'
    Assert-Reject 'Implementation cannot change scope while closing' { Check-WorkItems $bad $childrenAccepted } 'Specification change requires rework'
    $bad = Copy-TestDocument $planned; $bad.items[1].dependencies = @('task-b'); $bad.items[1].status = 'in_progress'; $bad.items[1].updatedAt = '2026-10-12T10:01:00Z'
    Assert-Reject 'Dependency must be accepted before work' { Check-WorkItems $bad } 'Unaccepted dependency'
    $bad = Copy-TestDocument $blocked; $bad.items[0].status = 'in_progress'; $bad.items[0].updatedAt = '2026-10-12T10:02:00Z'
    Assert-Reject 'Pending human response blocks work' { Check-WorkItems $bad } 'Pending human interaction'
    $answered = Copy-TestDocument $blocked
    $answered.items[0].humanInteraction.response = [pscustomobject]@{ description = 'Approved'; respondedAt = '2026-10-12T10:02:00Z'; respondentId = 'tom' }
    $answered.items[0].status = 'in_progress'; $answered.items[0].updatedAt = '2026-10-12T10:02:00Z'
    Assert-Pass 'Human response permits resumption' { Check-WorkItems $answered $blocked }
    $bad = Copy-TestDocument $answered; $bad.items[0].humanInteraction = $null
    Assert-Reject 'Human request cannot be erased to unblock' { Check-WorkItems $bad $blocked } 'Human request removed'
    $bad = Copy-TestDocument $answered; $bad.items[0].humanInteraction.response.respondedAt = '2026-10-12T09:00:00Z'
    Assert-Reject 'Human response cannot predate request' { Check-WorkItems $bad } 'Human response timestamp'
    $bad = Copy-TestDocument $finished; $bad.items[0].verifications[-1].results[0].passed = $false
    Assert-Reject 'Verification summary must match criteria' { Check-WorkItems $bad } 'Inconsistent verification outcome'
    $bad = Copy-TestDocument $finished; $bad.items[0].acceptanceCriteria += [pscustomobject]@{ id = 'extra'; description = 'Another criterion' }
    Assert-Reject 'Acceptance must cover every own criterion' { Check-WorkItems $bad } 'Incomplete successful verification'
    $bad = Copy-TestDocument $finished; $bad.items[0].verifications[-1].results += $bad.items[0].verifications[-1].results[0]
    Assert-Reject 'Verification criterion IDs must be unique' { Check-WorkItems $bad } 'Duplicate verification criterion'
    $bad = Copy-TestDocument $finished; $bad.items[0].verifications[-1].results[0].criterionId = 'foreign'
    Assert-Reject 'Acceptance cannot use foreign criteria' { Check-WorkItems $bad } 'Unknown verification criterion'
    $bad = Copy-TestDocument $childrenAccepted; $bad.items[1].status = 'in_progress'; $bad.items[1].acceptedAt = $null
    $bad.items[0].status = 'accepted'; Add-Verification $bad.items[0] '2026-10-12T10:04:00Z' $true; $bad.items[0].acceptedAt = '2026-10-12T10:04:00Z'
    Assert-Reject 'Open child blocks parent acceptance' { Check-WorkItems $bad } 'Open child of accepted parent'
    $bad = Copy-TestDocument $finished; $bad.items[0].acceptedAt = '2026-10-12T10:02:30Z'; $bad.items[0].verifications[-1].checkedAt = $bad.items[0].acceptedAt
    $bad.items[0].verifications = @($bad.items[0].verifications[-1]); $bad.items[0].implementedAt = '2026-10-12T10:02:00Z'; $bad.items[0].verifications[0].implementedAt = $bad.items[0].implementedAt
    Assert-Reject 'Parent cannot predate child acceptance' { Check-WorkItems $bad } 'Parent accepted before child'
    $bad = Copy-TestDocument $childrenAccepted; $bad.items[0].result.summary = 'Changed after implementation'; $bad.items[0].updatedAt = '2026-10-12T10:04:00Z'
    Assert-Reject 'Changed result cannot reuse verification basis' { Check-WorkItems $bad $childrenAccepted } 'Changed result requires new implementation'
    $deep = Copy-TestDocument $planned; $deep.items = @($deep.items[0]); $last = $deep.items[0].id
    for ($i = 1; $i -le 120; $i++) {
        $child = Copy-TestDocument $planned.items[1]; $child.id = 'depth-' + $i; $child.parentId = $last; $last = $child.id
        $deep.items += $child
    }
    Assert-Pass '121 task levels independent of agent depth' { Check-WorkItems $deep }
    Assert-Pass 'All current organization indices' { & (Join-Path $PSScriptRoot 'Test-Organization.ps1') }
    $org = Join-Path $temp 'organization'
    New-Item -ItemType Directory -Path $org | Out-Null
    Copy-Item -LiteralPath (Join-Path $repo 'koordinator'),(Join-Path $repo 'teams') -Destination $org -Recurse
    $centralPath = Join-Path $org 'koordinator\teams.json'
    $originalCentral = Read-ContractJson $centralPath
    $central = Copy-TestDocument $originalCentral; $central.teams[0] | Add-Member status 'ready'
    [IO.File]::WriteAllText($centralPath, ($central | ConvertTo-Json -Depth 50), $utf8)
    Assert-Reject 'Organization status field forbidden' { & (Join-Path $PSScriptRoot 'Test-Organization.ps1') -RepositoryRoot $org } 'Schema additional property'
    $central = Copy-TestDocument $originalCentral; $central.teams[0].role_file = '../outside.toml'
    [IO.File]::WriteAllText($centralPath, ($central | ConvertTo-Json -Depth 50), $utf8)
    Assert-Reject 'Role reference traversal forbidden' { & (Join-Path $PSScriptRoot 'Test-Organization.ps1') -RepositoryRoot $org } 'Schema anyOf'
    $central = Copy-TestDocument $originalCentral; $central.teams += $central.teams[0]
    [IO.File]::WriteAllText($centralPath, ($central | ConvertTo-Json -Depth 50), $utf8)
    Assert-Reject 'Duplicate organization teams' { & (Join-Path $PSScriptRoot 'Test-Organization.ps1') -RepositoryRoot $org } 'Duplicate team ID'
    [IO.File]::WriteAllText($centralPath, ($originalCentral | ConvertTo-Json -Depth 50), $utf8)
    $roleFile = Join-Path $org 'teams\softwareentwicklung\teamleiter.toml'
    $roleText = [IO.File]::ReadAllText($roleFile)
    [IO.File]::WriteAllText($roleFile, $roleText.Replace('name = "teamleiter_softwareentwicklung"','name = "wrong"'), $utf8)
    Assert-Reject 'Referenced role must declare matching ID' { & (Join-Path $PSScriptRoot 'Test-Organization.ps1') -RepositoryRoot $org } 'Role name mismatch'
    [IO.File]::WriteAllText($roleFile, $roleText, $utf8)
    $agentPath = Join-Path $org 'teams\softwareentwicklung\agenten.json'
    $index = Read-ContractJson $agentPath; $originalIndex = Copy-TestDocument $index
    $index.agents[0] | Add-Member status 'ready'
    [IO.File]::WriteAllText($agentPath, ($index | ConvertTo-Json -Depth 50), $utf8)
    Assert-Reject 'Nested agent status field forbidden' { & (Join-Path $PSScriptRoot 'Test-Organization.ps1') -RepositoryRoot $org } 'Schema additional property'
    $index = Copy-TestDocument $originalIndex; $index.agents[0].role_file = 'softwareentwicklung_missing.toml'
    [IO.File]::WriteAllText($agentPath, ($index | ConvertTo-Json -Depth 50), $utf8)
    Assert-Reject 'Wrong role file rejected' { & (Join-Path $PSScriptRoot 'Test-Organization.ps1') -RepositoryRoot $org } 'Role file mismatch'
    [IO.File]::WriteAllText($agentPath, ($originalIndex | ConvertTo-Json -Depth 50), $utf8)
    $operativeFile = Join-Path $org 'teams\softwareentwicklung\agenten\architektur.toml'
    Remove-Item -LiteralPath $operativeFile
    Assert-Reject 'Missing referenced role rejected' { & (Join-Path $PSScriptRoot 'Test-Organization.ps1') -RepositoryRoot $org } 'Missing referenced file'
    $index = Copy-TestDocument $originalIndex; $index.agents[0].role_file = $null
    [IO.File]::WriteAllText($agentPath, ($index | ConvertTo-Json -Depth 50), $utf8)
    Assert-Pass 'Null role reference marks unavailability' { & (Join-Path $PSScriptRoot 'Test-Organization.ps1') -RepositoryRoot $org }
    $unavailableOwner = Copy-TestDocument $planned
    $unavailableOwner.items[0].owner = [pscustomobject]@{ type = 'agent'; id = 'softwareentwicklung_architektur' }
    $ownerFile = Save-TestJson $unavailableOwner 'unavailable-owner.json'
    Assert-Reject 'Unavailable indexed role cannot own work' { & (Join-Path $PSScriptRoot 'Test-WorkItems.ps1') -Path $ownerFile -RepositoryRoot $org } 'Missing actor role'
    $index.team_id = 'foreign'
    [IO.File]::WriteAllText($agentPath, ($index | ConvertTo-Json -Depth 50), $utf8)
    Assert-Reject 'Wrong index team rejected' { & (Join-Path $PSScriptRoot 'Test-Organization.ps1') -RepositoryRoot $org } 'Agent index team mismatch'
    $schema = Read-ContractJson (Join-Path $repo 'schemas\agents.schema.json')
    $schema | Add-Member unimplementedKeyword $true
    Assert-Reject 'Unsupported schema keywords fail closed' { Assert-ContractSchemaVocabulary $schema } 'Unsupported schema keyword'
    $schema = Read-ContractJson (Join-Path $repo 'schemas\workitems.schema.json')
    $schema.'$defs'.workItem.properties.result.anyOf[1].'$ref' = '#/$defs/not_defined'
    Assert-Reject 'Unvisited nullable references still need definitions' { Assert-ContractSchemaVocabulary $schema } 'Missing schema definition'
    $report = [pscustomobject]@{ passed = $true; checkCount = $checks.Count; checks = @($checks.ToArray()); powershellVersion = $PSVersionTable.PSVersion.ToString() }
    if ($ResultPath) { [IO.File]::WriteAllText([IO.Path]::GetFullPath($ResultPath), ($report | ConvertTo-Json -Depth 8), $utf8) }
    Write-Output $report
} finally {
    $base = [IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\') + '\'
    $full = [IO.Path]::GetFullPath($temp)
    if (-not $full.StartsWith($base, [StringComparison]::OrdinalIgnoreCase) -or [IO.Path]::GetFileName($full) -notmatch '^agent-org-contracts-[a-f0-9]{32}$') { throw 'Unsafe test cleanup path.' }
    Remove-Item -LiteralPath $full -Recurse -Force
}
