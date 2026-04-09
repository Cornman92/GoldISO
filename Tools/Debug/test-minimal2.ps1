#Requires -Version 5.1

# Import common module
Import-Module (Join-Path $PSScriptRoot "Scripts\Modules\GoldISO-Common.psm1") -Force

<#
.SYNOPSIS
    Test
#>
[CmdletBinding()]
param(
    [string]$Test = ""
)

Write-Host "Hello world: $Test"