[CmdletBinding()]
param(
    [string]$Path,
    [string]$RepositoryRoot,
    [ValidateRange(0, 60000)][int]$TimeoutMilliseconds = 5000
)
$ErrorActionPreference = 'Stop'
if (-not $PSBoundParameters.ContainsKey('RepositoryRoot')) { $RepositoryRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot) }
Import-Module (Join-Path $PSScriptRoot 'WorkItemStore.psm1') -Force
Get-WorkItemStoreResult -Path $Path -RepositoryRoot $RepositoryRoot -TimeoutMilliseconds $TimeoutMilliseconds
