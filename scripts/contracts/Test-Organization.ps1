[CmdletBinding()]
param([string]$RepositoryRoot)
$ErrorActionPreference = 'Stop'
if (-not $PSBoundParameters.ContainsKey('RepositoryRoot')) { $RepositoryRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot) }
. (Join-Path $PSScriptRoot 'ContractValidation.ps1')
$RepositoryRoot = (Resolve-Path -LiteralPath $RepositoryRoot).Path
$schemas = Join-Path (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)) 'schemas'
$central = Read-ContractJson (Join-Path $RepositoryRoot 'koordinator\teams.json')
Assert-ContractDocument $central (Join-Path $schemas 'teams.schema.json')
$null = Assert-ContractRelativeFile $RepositoryRoot 'koordinator/koordinator.toml'
Assert-ContractRole (Join-Path $RepositoryRoot 'koordinator\koordinator.toml') 'koordinator'
$ids = @{ koordinator = $true }; $teamIds = @{}; $unavailable = @(); $agentCount = 0
foreach ($team in $central.teams) {
    if ($teamIds.ContainsKey($team.team_id)) { throw "Duplicate team ID: $($team.team_id)" }
    $teamIds[$team.team_id] = $true
    if ($team.leader_id -cne ('teamleiter_' + $team.team_id)) { throw "Team leader mismatch: $($team.team_id)" }
    if ($ids.ContainsKey($team.leader_id)) { throw "Duplicate role ID: $($team.leader_id)" }
    $ids[$team.leader_id] = $true
    $teamFolder = Join-Path $RepositoryRoot ('teams/' + $team.team_id)
    if ($null -ne $team.role_file) {
        if ($team.role_file -cne ($team.leader_id + '.toml')) { throw "Role file mismatch: $($team.leader_id)" }
        $file = Assert-ContractRelativeFile $RepositoryRoot ('teams/' + $team.team_id + '/teamleiter.toml')
        Assert-ContractRole $file $team.leader_id
    } else { $unavailable += $team.leader_id }
    $indexFile = Assert-ContractRelativeFile $RepositoryRoot ('teams/' + $team.team_id + '/agenten.json')
    $index = Read-ContractJson $indexFile
    Assert-ContractDocument $index (Join-Path $schemas 'agents.schema.json')
    if ($index.team_id -cne $team.team_id -or $index.leader_id -cne $team.leader_id) { throw "Agent index team mismatch: $($team.team_id)" }
    foreach ($agent in $index.agents) {
        if (-not $agent.agent_id.StartsWith($team.team_id + '_', [StringComparison]::Ordinal)) { throw "Agent team mismatch: $($agent.agent_id)" }
        if ($ids.ContainsKey($agent.agent_id)) { throw "Duplicate role ID: $($agent.agent_id)" }
        $ids[$agent.agent_id] = $true; $agentCount++
        if ($null -ne $agent.role_file) {
            if ($agent.role_file -cne ($agent.agent_id + '.toml')) { throw "Role file mismatch: $($agent.agent_id)" }
            $roleReference = 'teams/' + $team.team_id + '/agenten/' + $agent.role_file
            if (-not (Test-Path -LiteralPath (Join-Path $RepositoryRoot $roleReference))) {
                $shortName = $agent.agent_id.Substring($team.team_id.Length + 1)
                $roleReference = 'teams/' + $team.team_id + '/agenten/' + $shortName + '.toml'
            }
            $file = Assert-ContractRelativeFile $RepositoryRoot $roleReference
            Assert-ContractRole $file $agent.agent_id
        } else { $unavailable += $agent.agent_id }
    }
}
foreach ($folder in Get-ChildItem -LiteralPath (Join-Path $RepositoryRoot 'teams') -Directory) {
    if ((Test-Path -LiteralPath (Join-Path $folder.FullName 'agenten.json')) -and -not $teamIds.ContainsKey($folder.Name)) { throw "Unindexed team: $($folder.Name)" }
}
[pscustomobject]@{ valid = $true; teamCount = $central.teams.Count; agentCount = $agentCount; unavailableRoles = @($unavailable) }
