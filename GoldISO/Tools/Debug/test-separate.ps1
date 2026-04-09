#Requires -Version 5.1
#Requires -RunAsAdministrator

$modPath = Join-Path $PSScriptRoot "Scripts\Modules\GoldISO-Common.psm1"
Import-Module $modPath -Force

[CmdletBinding()]
param()

Write-Host "Test"