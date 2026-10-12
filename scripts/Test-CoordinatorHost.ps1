[CmdletBinding()]
param([Parameter(Mandatory=$true)][string]$ResultPath,[Parameter(Mandatory=$true)][string]$DeliveryReport,[Parameter(Mandatory=$true)][string[]]$Gate)
& (Join-Path $PSScriptRoot 'tests/coordinator/HostHarness.ps1') -ResultPath $ResultPath -DeliveryReport $DeliveryReport -Gate $Gate
exit $LASTEXITCODE
