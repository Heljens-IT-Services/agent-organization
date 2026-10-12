[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$Path,
    [string]$PreviousPath,
    [string]$RepositoryRoot = (Split-Path -Parent $PSScriptRoot)
)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'contracts\ContractValidation.ps1')
$RepositoryRoot = (Resolve-Path -LiteralPath $RepositoryRoot).Path
$schemaPath = Join-Path (Split-Path -Parent $PSScriptRoot) 'schemas\workitems.schema.json'
$schema = Read-ContractJson $schemaPath

function Get-WorkItemMap($Document) {
    Assert-ContractDocument $Document $schemaPath
    $map = @{}
    foreach ($item in $Document.items) {
        if ($map.ContainsKey($item.id)) { throw "Duplicate WorkItem ID: $($item.id)" }
        $map[$item.id] = $item
    }
    return ,$map
}

function Assert-WorkItemSnapshot($Document) {
    $map = Get-WorkItemMap $Document
    $parents = @{}; $dependencies = @{}; $completion = @{}
    $availableRoles = @{}
    $actorList = @($Document.items | ForEach-Object { $_.owner; foreach ($check in $_.verifications) { $check.reviewer } })
    if (@($actorList | Where-Object { $_.type -ceq 'agent' }).Count -gt 0) {
        $organization = & (Join-Path $PSScriptRoot 'Test-Organization.ps1') -RepositoryRoot $RepositoryRoot
        $availableRoles['koordinator'] = $true
        $teams = Read-ContractJson (Join-Path $RepositoryRoot 'koordinator\teams.json')
        foreach ($team in $teams.teams) {
            if ($null -ne $team.role_file) { $availableRoles[$team.leader_id] = $true }
            $index = Read-ContractJson (Join-Path $RepositoryRoot ('teams/' + $team.team_id + '/agenten.json'))
            foreach ($agent in $index.agents) {
                if ($null -ne $agent.role_file) { $availableRoles[$agent.agent_id] = $true }
            }
        }
    }
    foreach ($item in $Document.items) {
        $parents[$item.id] = @(); $dependencies[$item.id] = @($item.dependencies); $completion[$item.id] = @($item.dependencies)
        if ($null -ne $item.parentId) {
            if (-not $map.ContainsKey($item.parentId)) { throw "Missing parent: $($item.parentId)" }
            $parents[$item.id] = @($item.parentId)
        }
        foreach ($dependency in $item.dependencies) {
            if (-not $map.ContainsKey($dependency)) { throw "Missing dependency: $dependency" }
            if ($item.status -cin @('in_progress','implemented','accepted') -and $map[$dependency].status -cne 'accepted') {
                throw "Unaccepted dependency: $dependency"
            }
        }
        foreach ($actor in @($item.owner) + @($item.verifications | ForEach-Object { $_.reviewer })) {
            if ($actor.type -ceq 'agent' -and -not $availableRoles.ContainsKey($actor.id)) { throw "Missing actor role: $($actor.id)" }
        }
        if (Test-ContractProperty $item.specification 'markdown') {
            $null = Assert-ContractRelativeFile $RepositoryRoot $item.specification.markdown
        }
        $created = [DateTimeOffset]::Parse($item.createdAt)
        $updated = [DateTimeOffset]::Parse($item.updatedAt)
        if ($updated -lt $created) { throw "Timestamp order: $($item.id)" }
        if ($null -ne $item.implementedAt) {
            $implemented = [DateTimeOffset]::Parse($item.implementedAt)
            if ($implemented -lt $created -or $implemented -gt $updated -or $null -eq $item.result) { throw "Invalid implementation evidence: $($item.id)" }
        } elseif ($item.status -cin @('implemented','rework','accepted') -or $item.verifications.Count -gt 0) {
            throw "Missing implementedAt: $($item.id)"
        }
        $criteria = @{}
        foreach ($criterion in $item.acceptanceCriteria) {
            if ($criteria.ContainsKey($criterion.id)) { throw "Duplicate criterion: $($item.id)/$($criterion.id)" }
            $criteria[$criterion.id] = $true
        }
        $lastChecked = $created
        foreach ($check in $item.verifications) {
            $checked = [DateTimeOffset]::Parse($check.checkedAt)
            $checkImplementation = [DateTimeOffset]::Parse($check.implementedAt)
            if ($checkImplementation -lt $created -or $checkImplementation -gt $checked -or $checked -lt $lastChecked -or $checked -gt $updated) {
                throw "Verification timestamp order: $($item.id)"
            }
            if ($checkImplementation -gt [DateTimeOffset]::Parse($item.implementedAt)) { throw "Unknown implementation attempt: $($item.id)" }
            $lastChecked = $checked
            $resultIds = @{}
            foreach ($outcome in $check.results) {
                if ($resultIds.ContainsKey($outcome.criterionId)) { throw "Duplicate verification criterion: $($item.id)" }
                $resultIds[$outcome.criterionId] = $true
            }
            $allPassed = @($check.results | Where-Object { -not $_.passed }).Count -eq 0
            if ($check.passed -ne $allPassed) { throw "Inconsistent verification outcome: $($item.id)" }
            if ($check.implementedAt -ceq $item.implementedAt -and $item.status -cin @('implemented','accepted')) {
                foreach ($criterionId in $resultIds.Keys) {
                    if (-not $criteria.ContainsKey($criterionId)) { throw "Unknown verification criterion: $($item.id)/$criterionId" }
                }
                if ($check.passed -and $resultIds.Count -ne $criteria.Count) { throw "Incomplete successful verification: $($item.id)" }
            }
        }
        $pendingHuman = $null -ne $item.humanInteraction -and $null -eq $item.humanInteraction.response
        if ($pendingHuman -and $item.status -cnotin @('blocked','cancelled')) { throw "Pending human interaction: $($item.id)" }
        if ($item.status -ceq 'blocked' -and -not $pendingHuman -and $null -eq $item.blockReason) { throw "Missing block reason: $($item.id)" }
        if ($item.status -cnotin @('blocked','cancelled') -and $null -ne $item.blockReason) { throw "Stale block reason: $($item.id)" }
        if ($null -ne $item.humanInteraction) {
            $request = [DateTimeOffset]::Parse($item.humanInteraction.requestedAt)
            if ($request -lt $created -or $request -gt $updated) { throw "Human request timestamp: $($item.id)" }
            if ($null -ne $item.humanInteraction.response) {
                $response = [DateTimeOffset]::Parse($item.humanInteraction.response.respondedAt)
                if ($response -lt $request -or $response -gt $updated) { throw "Human response timestamp: $($item.id)" }
            }
        }
        if ($item.status -ceq 'accepted') {
            if ($null -eq $item.acceptedAt -or $item.verifications.Count -eq 0) { throw "Missing acceptance evidence: $($item.id)" }
            $latest = $item.verifications[-1]
            if (-not $latest.passed -or $latest.implementedAt -cne $item.implementedAt -or $latest.checkedAt -cne $item.acceptedAt) {
                throw "Missing current successful verification: $($item.id)"
            }
        } elseif ($null -ne $item.acceptedAt) { throw "acceptedAt without acceptance: $($item.id)" }
        if ($item.status -ceq 'rework' -and ($item.verifications.Count -eq 0 -or $item.verifications[-1].passed -or $item.verifications[-1].implementedAt -cne $item.implementedAt)) {
            throw "Rework requires failed current verification: $($item.id)"
        }
        if ($item.status -ceq 'implemented' -and $item.verifications.Count -gt 0 -and -not $item.verifications[-1].passed -and $item.verifications[-1].implementedAt -ceq $item.implementedAt) {
            throw "Failed verification requires rework: $($item.id)"
        }
    }
    foreach ($item in $Document.items) {
        if ($null -ne $item.parentId) {
            $completion[$item.parentId] = @($completion[$item.parentId]) + $item.id
            if ($map[$item.parentId].status -ceq 'accepted') {
                if ($item.status -cnotin @('accepted','cancelled')) { throw "Open child of accepted parent: $($item.id)" }
                $finished = if ($item.status -ceq 'accepted') { $item.acceptedAt } else { $item.updatedAt }
                if ([DateTimeOffset]::Parse($map[$item.parentId].acceptedAt) -lt [DateTimeOffset]::Parse($finished)) { throw "Parent accepted before child: $($item.id)" }
            }
        }
    }
    Assert-ContractGraph $parents 'Parent'
    Assert-ContractGraph $dependencies 'Dependency'
    Assert-ContractGraph $completion 'Completion dependency'
    return ,$map
}

$document = Read-ContractJson $Path
$current = Assert-WorkItemSnapshot $document
if ($PreviousPath) {
    $previousDocument = Read-ContractJson $PreviousPath
    $previous = Assert-WorkItemSnapshot $previousDocument
    foreach ($id in $previous.Keys) {
        if (-not $current.ContainsKey($id)) { throw "WorkItem removal is not a lifecycle transition: $id" }
        $old = $previous[$id]; $new = $current[$id]
        $oldJson = Get-ContractCanonicalJson $old
        $newJson = Get-ContractCanonicalJson $new
        if ($oldJson -ceq $newJson) { continue }
        if ($old.createdAt -cne $new.createdAt) { throw "Immutable createdAt: $id" }
        if ([DateTimeOffset]::Parse($new.updatedAt) -le [DateTimeOffset]::Parse($old.updatedAt)) { throw "Update must advance updatedAt: $id" }
        if ($old.status -cin @('accepted','cancelled')) { throw "Terminal WorkItem is immutable: $id" }
        if ($old.status -cne $new.status -and @($schema.'x-statusTransitions'.($old.status)) -cnotcontains $new.status) {
            throw "Invalid status transition: $id $($old.status) -> $($new.status)"
        }
        if ($new.verifications.Count -lt $old.verifications.Count) { throw "Verification history removed: $id" }
        for ($i = 0; $i -lt $old.verifications.Count; $i++) {
            if ((Get-ContractCanonicalJson $old.verifications[$i]) -cne (Get-ContractCanonicalJson $new.verifications[$i])) { throw "Verification history changed: $id" }
        }
        if ($old.implementedAt -cne $new.implementedAt) {
            if ($new.status -cne 'implemented' -or $old.status -cnotin @('in_progress','rework')) { throw "Implementation timestamp transition: $id" }
            if ($null -ne $old.implementedAt -and [DateTimeOffset]::Parse($new.implementedAt) -le [DateTimeOffset]::Parse($old.implementedAt)) { throw "Reimplementation must advance implementedAt: $id" }
            if ($old.verifications.Count -gt 0 -and [DateTimeOffset]::Parse($new.implementedAt) -le [DateTimeOffset]::Parse($old.verifications[-1].checkedAt)) { throw "Reimplementation must follow verification: $id" }
            if ([DateTimeOffset]::Parse($new.implementedAt) -lt [DateTimeOffset]::Parse($old.updatedAt)) { throw "Implementation predates previous state: $id" }
        } elseif ($null -ne $old.implementedAt -and (Get-ContractCanonicalJson $old.result) -cne (Get-ContractCanonicalJson $new.result)) {
            throw "Changed result requires new implementation: $id"
        }
        if ($old.status -ceq 'blocked' -and $new.status -ceq 'implemented' -and $null -eq $old.implementedAt) { throw "Blocked task cannot skip implementation: $id" }
        if ($null -ne $old.implementedAt -and $old.status -cne 'rework') {
            foreach ($field in @('parentId','title','description','goal','specification','acceptanceCriteria')) {
                if ((Get-ContractCanonicalJson $old.$field) -cne (Get-ContractCanonicalJson $new.$field)) { throw "Specification change requires rework first: $id/$field" }
            }
        }
        if ($null -ne $old.humanInteraction -and $null -eq $old.humanInteraction.response -and $new.status -cne 'cancelled') {
            if ($null -eq $new.humanInteraction) { throw "Human request removed: $id" }
            foreach ($field in @('kind','description','requestedAt')) {
                if ($old.humanInteraction.$field -cne $new.humanInteraction.$field) { throw "Pending human request changed: $id" }
            }
        }
    }
    foreach ($id in $current.Keys) {
        if (-not $previous.ContainsKey($id) -and $current[$id].status -cne 'planned') { throw "New WorkItem must start planned: $id" }
    }
}
[pscustomobject]@{ valid = $true; workItemCount = $current.Count; transitionsChecked = [bool]$PreviousPath }
