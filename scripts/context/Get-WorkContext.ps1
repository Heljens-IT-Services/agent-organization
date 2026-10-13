[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$RepositoryRoot,
    [Parameter(Mandatory = $true)][ValidateSet('knowledge', 'workflow', 'all')][string]$Kind,
    [string[]]$Terms,
    [string]$Path
)

$root = [IO.Path]::GetFullPath($RepositoryRoot)
if (-not [IO.Directory]::Exists($root)) { throw 'RepositoryRootNotFound' }
$modulePath = Join-Path $root 'scripts/context/WorkContext.psm1'
if (-not [IO.File]::Exists($modulePath)) { throw 'WorkContextModuleNotFoundInRepositoryRoot' }
Import-Module -Name $modulePath -Force -ErrorAction Stop

if (-not [string]::IsNullOrWhiteSpace($Path)) {
    if ($Kind -eq 'all') { throw 'ReadingRequiresOneIndexedKind' }
    Read-WorkContext -RepositoryRoot $root -Kind $Kind -Path $Path
}
else {
    if (-not $Terms -or @($Terms | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }).Count -eq 0) { throw 'DiscoveryRequiresSearchTerms' }
    Find-WorkContext -RepositoryRoot $root -Kind $Kind -Terms $Terms
}
