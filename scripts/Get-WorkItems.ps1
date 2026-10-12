[CmdletBinding()]
param(
    [string]$Path,
    [string]$RepositoryRoot = (Split-Path -Parent $PSScriptRoot),
    [ValidateRange(0, 60000)][int]$TimeoutMilliseconds = 5000
)
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'workitems\WorkItemStore.psm1') -Force
Get-WorkItemStoreResult -Path $Path -RepositoryRoot $RepositoryRoot -TimeoutMilliseconds $TimeoutMilliseconds
