Set-StrictMode -Version 2

function Get-LocalWebSourceReference {
    param([string]$Path, [byte[]]$Bytes)
    $sha = [Security.Cryptography.SHA256]::Create()
    try { $hash = ([BitConverter]::ToString($sha.ComputeHash($Bytes))).Replace('-', '').ToLowerInvariant() }
    finally { $sha.Dispose() }
    return 'file:' + [IO.Path]::GetFullPath($Path) + '#sha256:' + $hash
}

function Test-LocalWebRoleHeadIdentity {
    param([string]$Text, [string]$AgentId)
    $lines = $Text -split "`r?`n"
    $head = New-Object 'System.Collections.Generic.List[string]'
    $foundInstructions = $false
    foreach ($line in $lines) {
        if ($line -cmatch '^\s*developer_instructions\s*=') { $foundInstructions = $true; break }
        $head.Add($line)
    }
    if (-not $foundInstructions) { return $false }
    $nameLines = @($head | Where-Object { $_ -cmatch '^\s*name\s*=' })
    if ($nameLines.Count -ne 1) { return $false }
    if ($nameLines[0] -cnotmatch '^\s*name\s*=\s*"(?<value>[^"\r\n]+)"\s*$') { return $false }
    return [String]::Equals($Matches.value, $AgentId, [StringComparison]::Ordinal)
}

function Read-LocalWebProjectionSource {
    param([string]$Path)
    if ([string]::IsNullOrWhiteSpace($Path) -or -not [IO.Path]::IsPathRooted($Path)) { throw 'DisplaySourcePathNotConfigured' }
    $fullPath = [IO.Path]::GetFullPath($Path)
    if (-not [IO.File]::Exists($fullPath) -or (([IO.File]::GetAttributes($fullPath) -band [IO.FileAttributes]::ReparsePoint) -ne 0)) { throw 'DisplaySourceUnavailable' }
    $bytes = [IO.File]::ReadAllBytes($fullPath)
    $sourceReference = Get-LocalWebSourceReference $fullPath $bytes
    try { $text = (New-Object Text.UTF8Encoding($false, $true)).GetString($bytes) } catch {
        $invalid = [InvalidOperationException]::new('SourceDecodeInvalid')
        $invalid.Data['LocalWebSourceReference'] = $sourceReference
        throw $invalid
    }
    return [pscustomobject]@{ path = $fullPath; bytes = $bytes; text = $text; sourceReference = $sourceReference }
}

function New-LocalWebTeamProjection {
    param([string]$TeamSourcePath, [string]$RoleRoot)
    $teamSource = Read-LocalWebProjectionSource $TeamSourcePath
    try { $sourceDocument = ConvertFrom-Json -InputObject $teamSource.text -ErrorAction Stop } catch {
        $invalid = [InvalidOperationException]::new('TeamSourceInvalid'); $invalid.Data['LocalWebSourceReference'] = $teamSource.sourceReference; throw $invalid
    }
    if ($null -eq $sourceDocument -or $sourceDocument -isnot [System.Management.Automation.PSCustomObject]) { $invalid = [InvalidOperationException]::new('TeamSourceInvalid'); $invalid.Data['LocalWebSourceReference'] = $teamSource.sourceReference; throw $invalid }
    $required = @('team_id','leader_id','agents')
    foreach ($name in $required) { if (-not $sourceDocument.PSObject.Properties[$name]) { $invalid = [InvalidOperationException]::new('TeamSourceInvalid'); $invalid.Data['LocalWebSourceReference'] = $teamSource.sourceReference; throw $invalid } }
    if ($sourceDocument.team_id -isnot [string] -or [string]::IsNullOrWhiteSpace($sourceDocument.team_id) -or
        $sourceDocument.leader_id -isnot [string] -or [string]::IsNullOrWhiteSpace($sourceDocument.leader_id) -or
        $sourceDocument.agents -isnot [System.Array]) { $invalid = [InvalidOperationException]::new('TeamSourceInvalid'); $invalid.Data['LocalWebSourceReference'] = $teamSource.sourceReference; throw $invalid }

    $roleRootPath = [IO.Path]::GetFullPath($RoleRoot)
    $sourceReferences = [System.Collections.Generic.List[string]]::new()
    $sourceReferences.Add($teamSource.sourceReference)
    $members = [System.Collections.Generic.List[object]]::new()
    $memberIds = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    foreach ($agent in $sourceDocument.agents) {
        if ($null -eq $agent -or $agent -isnot [System.Management.Automation.PSCustomObject] -or
            -not $agent.PSObject.Properties['agent_id'] -or -not $agent.PSObject.Properties['name'] -or -not $agent.PSObject.Properties['role_file'] -or
            $agent.agent_id -isnot [string] -or [string]::IsNullOrWhiteSpace($agent.agent_id) -or
            $agent.name -isnot [string] -or [string]::IsNullOrWhiteSpace($agent.name) -or
            $agent.role_file -isnot [string] -or [string]::IsNullOrWhiteSpace($agent.role_file) -or
            $agent.role_file -cnotmatch '^[A-Za-z0-9_.-]+\.toml$' -or -not $memberIds.Add($agent.agent_id)) { $invalid = [InvalidOperationException]::new('TeamSourceInvalid'); $invalid.Data['LocalWebSourceReference'] = $teamSource.sourceReference; $invalid.Data['LocalWebSourceReferences'] = @($sourceReferences.ToArray()); throw $invalid }

        $rolePath = [IO.Path]::GetFullPath((Join-Path $roleRootPath $agent.role_file))
        if (-not $rolePath.StartsWith($roleRootPath.TrimEnd([IO.Path]::DirectorySeparatorChar) + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)) { $invalid = [InvalidOperationException]::new('TeamSourceInvalid'); $invalid.Data['LocalWebSourceReference'] = $teamSource.sourceReference; $invalid.Data['LocalWebSourceReferences'] = @($sourceReferences.ToArray()); throw $invalid }
        $available = $null
        if ([IO.File]::Exists($rolePath)) {
            try {
                if (([IO.File]::GetAttributes($rolePath) -band [IO.FileAttributes]::ReparsePoint) -ne 0) { throw 'RoleSourceUnavailable' }
                $roleSource = Read-LocalWebProjectionSource $rolePath
                $sourceReferences.Add($roleSource.sourceReference)
                $roleText = $roleSource.text
                if (-not (Test-LocalWebRoleHeadIdentity $roleText $agent.agent_id)) { throw [InvalidOperationException]::new('RoleIdentityMismatch') }
                $available = $true
                $roleReference = $roleSource.sourceReference
            } catch {
                $available = $null
                $roleCode = switch ([string]$_.Exception.Message) {
                    'RoleIdentityMismatch' { 'RoleIdentityMismatch'; break }
                    'SourceDecodeInvalid' { 'RoleContentInvalid'; break }
                    default { 'RoleSourceUnavailable' }
                }
                $roleReference = if ($_.Exception.Data['LocalWebSourceReference']) { [string]$_.Exception.Data['LocalWebSourceReference'] + '#unavailable:' + $roleCode } else { 'file:' + $rolePath + '#unavailable:' + $roleCode }
                $sourceReferences.Add($roleReference)
            }
        } else {
            $roleReference = 'file:' + $rolePath + '#missing'
            $sourceReferences.Add($roleReference)
        }
        $members.Add([pscustomobject]@{ id = $agent.agent_id; label = $agent.name; available = $available; sourceReference = $roleReference })
    }
    $leaderId = [string]$sourceDocument.leader_id
    if (-not $memberIds.Contains($leaderId)) {
        $members.Add([pscustomobject]@{ id = $leaderId; label = $leaderId; available = $null; sourceReference = $teamSource.sourceReference })
        [void]$memberIds.Add($leaderId)
    }
    $team = [pscustomobject]@{
        teamId = [string]$sourceDocument.team_id
        label = [string]$sourceDocument.team_id
        leaderId = $leaderId
        members = @($members.ToArray())
        sourceReference = $teamSource.sourceReference
    }
    return [pscustomobject]@{ team = $team; sourceReferences = @($sourceReferences.ToArray()) }
}

function New-LocalWebDisplayProjection {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$StorePath,
        [string]$TeamSourcePath,
        [string]$RoleRoot,
        [object[]]$TeamSources
    )
    $pairs = @()
    $hasTeamSources = $PSBoundParameters.ContainsKey('TeamSources')
    $hasTeamSourcePath = $PSBoundParameters.ContainsKey('TeamSourcePath')
    $hasRoleRoot = $PSBoundParameters.ContainsKey('RoleRoot')
    if ($hasTeamSources -and ($hasTeamSourcePath -or $hasRoleRoot)) { throw [InvalidOperationException]::new('ProjectionSourceConflict') }
    if ($hasTeamSources) {
        if ($null -eq $TeamSources -or $TeamSources.Count -eq 0) { throw 'DisplayTeamSourcesInvalid' }
        $pairs = @($TeamSources)
    } elseif (-not [string]::IsNullOrWhiteSpace($TeamSourcePath) -and -not [string]::IsNullOrWhiteSpace($RoleRoot)) {
        $pairs = @([pscustomobject]@{ teamSourcePath = $TeamSourcePath; roleRoot = $RoleRoot })
    } else { throw 'DisplaySourcePathNotConfigured' }

    $teams = [System.Collections.Generic.List[object]]::new()
    $references = [System.Collections.Generic.List[string]]::new()
    $errors = [System.Collections.Generic.List[object]]::new()
    $paths = [System.Collections.Generic.Dictionary[string, int]]::new([StringComparer]::OrdinalIgnoreCase)
    $teamSourcesById = [System.Collections.Generic.Dictionary[string, object]]::new([StringComparer]::Ordinal)
    for ($i = 0; $i -lt $pairs.Count; $i++) {
        $pair = $pairs[$i]
        $pairProperties = if ($null -eq $pair) { @() } else { @($pair.PSObject.Properties) }
        if ($null -eq $pair -or $pairProperties.Count -ne 2 -or -not $pair.PSObject.Properties['teamSourcePath'] -or -not $pair.PSObject.Properties['roleRoot'] -or
            $pair.teamSourcePath -isnot [string] -or $pair.roleRoot -isnot [string] -or
            [string]::IsNullOrWhiteSpace($pair.teamSourcePath) -or [string]::IsNullOrWhiteSpace($pair.roleRoot) -or
            -not [IO.Path]::IsPathRooted($pair.teamSourcePath) -or -not [IO.Path]::IsPathRooted($pair.roleRoot)) {
            $errors.Add([pscustomobject]@{ code = 'DisplayTeamSourcesInvalid'; sourcePath = "pair[$i]"; sourceReference = $null }); continue
        }
        try { $path = [IO.Path]::GetFullPath($pair.teamSourcePath); $normalizedRoleRoot = [IO.Path]::GetFullPath($pair.roleRoot) } catch {
            $errors.Add([pscustomobject]@{ code = 'DisplayTeamSourcesInvalid'; sourcePath = "pair[$i]"; sourceReference = $null }); continue
        }
        $pathKey = $path
        if ($paths.ContainsKey($pathKey)) {
            $errors.Add([pscustomobject]@{ code = 'DuplicateTeamSource'; sourcePath = $path; sourceReference = $null; positions = @($paths[$pathKey], $i) }); continue
        }
        $paths[$pathKey] = $i
        try {
            $result = New-LocalWebTeamProjection -TeamSourcePath $path -RoleRoot $normalizedRoleRoot
            foreach ($reference in $result.sourceReferences) { if (-not $references.Contains($reference)) { $references.Add($reference) } }
            $teams.Add([pscustomobject]@{ team = $result.team; position = $i; path = $path })
            $id = [string]$result.team.teamId
            if (-not $teamSourcesById.ContainsKey($id)) { $teamSourcesById[$id] = [System.Collections.Generic.List[object]]::new() }
            $teamSourcesById[$id].Add([pscustomobject]@{ position = $i; path = $path; team = $result.team })
        } catch {
            $code = if ($_.Exception.Message -eq 'TeamSourceInvalid') { 'TeamSourceInvalid' } else { 'TeamSourceUnavailable' }
            $ref = [string]$_.Exception.Data['LocalWebSourceReference']
            foreach ($knownReference in @($_.Exception.Data['LocalWebSourceReferences'])) { if (-not [string]::IsNullOrWhiteSpace([string]$knownReference) -and -not $references.Contains([string]$knownReference)) { $references.Add([string]$knownReference) } }
            if ($_.Exception.Message -eq 'SourceDecodeInvalid') { $code = 'TeamSourceInvalid' }
            if ([string]::IsNullOrWhiteSpace($ref)) { $ref = 'file:' + $path + $(if ($code -eq 'TeamSourceInvalid') { '#unavailable:TeamSourceInvalid' } else { '#unavailable:TeamSourceUnavailable' }) }
            if ($code -eq 'TeamSourceUnavailable' -and -not [IO.File]::Exists($path)) { $ref = 'file:' + $path + '#missing' }
            if (-not $references.Contains($ref)) { $references.Add($ref) }
            $errors.Add([pscustomobject]@{ code = $code; sourcePath = $path; sourceReference = $ref })
        }
    }
    foreach ($id in @($teamSourcesById.Keys)) {
        $collisions = @($teamSourcesById[$id])
        if ($collisions.Count -gt 1) {
            $errors.Add([pscustomobject]@{ code = 'TeamIdentityConflict'; teamId = $id; sources = @($collisions | ForEach-Object { [pscustomobject]@{ path = $_.path; sourceReference = $_.team.sourceReference } }) })
        }
    }
    if ($errors.Count -gt 0) {
        $conflictedPaths = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
        foreach ($errorRecord in $errors) { if ($errorRecord.code -eq 'TeamIdentityConflict') { foreach ($source in $errorRecord.sources) { [void]$conflictedPaths.Add($source.path) } } }
        $safeTeams = @($teams | Where-Object { -not $conflictedPaths.Contains($_.path) } | ForEach-Object { $_.team })
        $report = [pscustomobject]@{ requestedCount = $pairs.Count; successfulCount = $teams.Count; teams = $safeTeams; errors = @($errors.ToArray()); sourceReferences = @($references.ToArray()) }
        $exception = [InvalidOperationException]::new('DisplayTeamSourcesIncomplete')
        $exception.Data['LocalWebDisplaySourceReport'] = $report
        throw $exception
    }
    $teamItems = @($teams | ForEach-Object { $_.team })
    return [pscustomobject][ordered]@{
        projectionVersion = '1'
        storePath = [IO.Path]::GetFullPath($StorePath)
        generatedAt = [DateTime]::UtcNow.ToString('o')
        sourceReferences = @($references.ToArray())
        humans = @()
        attentionAssignments = @()
        teams = @($teamItems)
    }
}

Export-ModuleMember -Function New-LocalWebDisplayProjection
