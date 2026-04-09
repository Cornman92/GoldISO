#Requires -Version 5.1
#Requires -RunAsAdministrator

if (-not (Get-Module GoldISO-Common)) {
    Import-Module (Join-Path $PSScriptRoot "Scripts\Modules\GoldISO-Common.psm1") -Force
}

[CmdletBinding()]
param()

Write-Host "Test"