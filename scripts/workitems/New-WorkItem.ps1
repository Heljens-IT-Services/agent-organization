[CmdletBinding()]
param(
    [string]$Path,
    [Parameter(Mandatory = $true)]$Item,
    [Parameter(Mandatory = $true)][string]$ExpectedRevision,
    [string]$RepositoryRoot,
    [ValidateRange(0, 60000)][int]$TimeoutMilliseconds = 5000
)
$ErrorActionPreference = 'Stop'
if (-not $PSBoundParameters.ContainsKey('RepositoryRoot')) { $RepositoryRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot) }
Import-Module (Join-Path $PSScriptRoot 'WorkItemStore.psm1') -Force
Set-WorkItemStoreEntry -Path $Path -Id ([string]$Item.id) -Item $Item -IsNew $true -ExpectedRevision $ExpectedRevision -RepositoryRoot $RepositoryRoot -TimeoutMilliseconds $TimeoutMilliseconds
