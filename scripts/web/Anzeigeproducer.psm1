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
    $text = (New-Object Text.UTF8Encoding($false, $true)).GetString($bytes)
    return [pscustomobject]@{ path = $fullPath; bytes = $bytes; text = $text; sourceReference = (Get-LocalWebSourceReference $fullPath $bytes) }
}

function New-LocalWebDisplayProjection {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$StorePath,
        [Parameter(Mandatory = $true)][string]$TeamSourcePath,
        [Parameter(Mandatory = $true)][string]$RoleRoot
    )
    if ([string]::IsNullOrWhiteSpace($TeamSourcePath) -or -not [IO.Path]::IsPathRooted($TeamSourcePath) -or
        [string]::IsNullOrWhiteSpace($RoleRoot) -or -not [IO.Path]::IsPathRooted($RoleRoot)) { throw 'DisplaySourcePathNotConfigured' }
    try { $teamSource = Read-LocalWebProjectionSource $TeamSourcePath }
    catch { throw 'TeamSourceUnavailable' }
    try { $sourceDocument = ConvertFrom-Json -InputObject $teamSource.text -ErrorAction Stop }
    catch { throw 'TeamSourceInvalid' }
    if ($null -eq $sourceDocument -or $sourceDocument -isnot [System.Management.Automation.PSCustomObject]) { throw 'TeamSourceInvalid' }
    $required = @('team_id','leader_id','agents')
    foreach ($name in $required) { if (-not $sourceDocument.PSObject.Properties[$name]) { throw 'TeamSourceInvalid' } }
    if ($sourceDocument.team_id -isnot [string] -or [string]::IsNullOrWhiteSpace($sourceDocument.team_id) -or
        $sourceDocument.leader_id -isnot [string] -or [string]::IsNullOrWhiteSpace($sourceDocument.leader_id) -or
        $sourceDocument.agents -isnot [System.Array]) { throw 'TeamSourceInvalid' }

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
            $agent.role_file -cnotmatch '^[A-Za-z0-9_.-]+\.toml$' -or -not $memberIds.Add($agent.agent_id)) { throw 'TeamSourceInvalid' }

        $rolePath = [IO.Path]::GetFullPath((Join-Path $roleRootPath $agent.role_file))
        if (-not $rolePath.StartsWith($roleRootPath.TrimEnd([IO.Path]::DirectorySeparatorChar) + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)) { throw 'TeamSourceInvalid' }
        $available = $null
        if ([IO.File]::Exists($rolePath)) {
            try {
                if (([IO.File]::GetAttributes($rolePath) -band [IO.FileAttributes]::ReparsePoint) -ne 0) { throw 'RoleSourceUnavailable' }
                $roleSource = Read-LocalWebProjectionSource $rolePath
                $sourceReferences.Add($roleSource.sourceReference)
                $roleText = $roleSource.text
                if (-not (Test-LocalWebRoleHeadIdentity $roleText $agent.agent_id)) { throw 'RoleIdentityMismatch' }
                $available = $true
                $roleReference = $roleSource.sourceReference
            } catch {
                $available = $null
                $roleReference = 'file:' + $rolePath + '#unavailable:' + [string]$_.Exception.Message
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
    return [pscustomobject][ordered]@{
        projectionVersion = '1'
        storePath = [IO.Path]::GetFullPath($StorePath)
        generatedAt = [DateTime]::UtcNow.ToString('o')
        sourceReferences = @($sourceReferences.ToArray())
        humans = @()
        attentionAssignments = @()
        teams = @($team)
    }
}

Export-ModuleMember -Function New-LocalWebDisplayProjection
