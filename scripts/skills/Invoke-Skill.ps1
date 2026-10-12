[CmdletBinding()]
param(
    [string]$SkillId,
    [string]$ParametersJson = '{}',
    [string]$WorkItemRef,
    [string]$ExecutionRef,
    [string]$RepositoryRoot = (Resolve-Path (Join-Path $PSScriptRoot '../..')).Path,
    [string[]]$AccountingRoots = @(),
    [string[]]$TrustedSourceRoots = @(),
    [string]$SourcePath,
    [string]$LogPath,
    [int]$TimeoutSeconds = 60,
    [string]$CoreInterpreterPath,
    [hashtable]$InterpreterBindings = @{}
)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'PS-Bootstrap.ps1')
$request = [ordered]@{
    repositoryRoot = $RepositoryRoot
    skillId = $SkillId
    workItemRef = $WorkItemRef
    executionRef = $ExecutionRef
    accountingRoots = @($AccountingRoots)
    trustedSourceRoots = @($TrustedSourceRoots)
    timeoutSeconds = $TimeoutSeconds
    interpreterBindings = @{}
}
if ($PSBoundParameters.ContainsKey('SourcePath')) { $request.sourcePath = $SourcePath }
if ($PSBoundParameters.ContainsKey('LogPath')) { $request.logPath = $LogPath }
Invoke-SkillRuntimeBootstrap -Operation 'run' -Request $request -RawParametersJson $ParametersJson `
    -CallerInterpreterBindings $InterpreterBindings -CoreInterpreterPath $CoreInterpreterPath -ExecutionRef $ExecutionRef
