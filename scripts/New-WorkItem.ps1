[CmdletBinding()]
param(
    [string]$Path,
    [Parameter(Mandatory = $true)]$Item,
    [Parameter(Mandatory = $true)][string]$ExpectedRevision,
    [string]$RepositoryRoot = (Split-Path -Parent $PSScriptRoot),
    [ValidateRange(0, 60000)][int]$TimeoutMilliseconds = 5000
)
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'workitems\WorkItemStore.psm1') -Force
Set-WorkItemStoreEntry -Path $Path -Id ([string]$Item.id) -Item $Item -IsNew $true -ExpectedRevision $ExpectedRevision -RepositoryRoot $RepositoryRoot -TimeoutMilliseconds $TimeoutMilliseconds
