# Test if #Requires -RunAsAdministrator causes the issue
#Requires -Version 5.1
#Requires -RunAsAdministrator
param()
[CmdletBinding()]
Write-Host "Test"