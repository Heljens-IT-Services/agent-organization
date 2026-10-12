[CmdletBinding()]
param(
 [Parameter(Mandatory)][string]$AccountingDirectory,
 [Parameter(Mandatory)][string]$StorePath,
 [Parameter(Mandatory)][string]$WorkItemId,
 [Parameter(Mandatory)][string]$ExecutionId,
 [Parameter(Mandatory)][string]$RepositoryRoot
)
$ErrorActionPreference='Stop'
Import-Module (Join-Path $PSScriptRoot 'WorkItemPrestartRecovery.psm1') -Force
Resume-PrestartReservation @PSBoundParameters
