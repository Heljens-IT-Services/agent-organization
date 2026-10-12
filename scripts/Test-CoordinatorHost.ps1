[CmdletBinding()]
param([Parameter(Mandatory=$true)][string]$ResultPath,[Parameter(Mandatory=$true)][string]$DeliveryReport)
& (Join-Path $PSScriptRoot 'tests/coordinator/HostHarness.ps1') -ResultPath $ResultPath -DeliveryReport $DeliveryReport
exit $LASTEXITCODE