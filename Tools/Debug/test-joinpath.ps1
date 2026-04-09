#Requires -Version 5.1
#Requires -RunAsAdministrator

$foo = Join-Path "C:\temp" "test.txt"

[CmdletBinding()]
param()

Write-Host "Test"