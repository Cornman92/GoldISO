#Requires -Version 5.1
#Requires -RunAsAdministrator

Get-Module GoldISO-Common | Out-Null
Import-Module (Join-Path $PSScriptRoot "Scripts\Modules\GoldISO-Common.psm1") -Force

[CmdletBinding()]
param()

Write-Host "Test"