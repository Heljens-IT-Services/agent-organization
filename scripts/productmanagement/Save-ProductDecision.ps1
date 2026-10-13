[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)][string]$ConfigurationPath,
    [Parameter(Mandatory=$true)][string]$ConfigurationHash,
    [Parameter(Mandatory=$true)][string]$SolutionId,
    [Parameter(Mandatory=$true)][string]$DataDirectory,
    [Parameter(Mandatory=$true)][string]$DecisionPath,
    [Parameter(Mandatory=$true)][string]$ExpectedRevision,
    [string]$StorePath,
    [string]$ReviewWorkItemId,
    [string]$RepositoryRoot=(Split-Path -Parent (Split-Path -Parent $PSScriptRoot))
)
Import-Module (Join-Path $PSScriptRoot 'ProductManagement.psm1')
$reference=[pscustomobject]@{path=$ConfigurationPath;hash=$ConfigurationHash}
$configuration=Read-ProductConfiguration $reference
$solutions=@($configuration.solutions | Where-Object { $_.solutionId -ceq $SolutionId })
if ($solutions.Count -ne 1) { throw 'ProductSolutionAssignmentMissing' }
$binding=[pscustomobject]@{configuration=$reference;solution=$solutions[0]}
$decision=ConvertFrom-Json -InputObject ([IO.File]::ReadAllText($DecisionPath,[Text.UTF8Encoding]::new($false,$true)))
Save-ProductDecision -Binding $binding -DataDirectory $DataDirectory -Decision $decision -ExpectedRevision $ExpectedRevision -StorePath $StorePath -RepositoryRoot $RepositoryRoot -ReviewWorkItemId $ReviewWorkItemId
