[CmdletBinding(DefaultParameterSetName='Id')]
param(
    [Parameter(ParameterSetName='Id')][string]$SkillId,
    [Parameter(ParameterSetName='Purpose')][string]$Purpose,
    [string]$RepositoryRoot = (Resolve-Path (Join-Path $PSScriptRoot '../..')).Path,
    [string]$CoreInterpreterPath,
    [hashtable]$Configuration = @{}
)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'PS-Bootstrap.ps1')
$request = [ordered]@{}
foreach ($key in $Configuration.Keys) { $request[$key] = $Configuration[$key] }
$request.repositoryRoot = $RepositoryRoot
if ($PSCmdlet.ParameterSetName -eq 'Id') { $request.skillId = $SkillId } else { $request.purpose = $Purpose }
Invoke-SkillRuntimeBootstrap -Operation 'discover' -Request $request -CoreInterpreterPath $CoreInterpreterPath -ExecutionRef $null
