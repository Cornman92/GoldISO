#Requires -Version 5.1

Write-Host "PSVersion:" $PSVersionTable.PSVersion.ToString()
Write-Host "PSEdition:" $PSVersionTable.PSEdition
Write-Host "CLRVersion:" $PSVersionTable.CLRVersion.ToString()

# List PowerShell locations
$paths = $env:PSModulePath -split ';'
Write-Host ""
Write-Host "Module paths:"
foreach ($p in $paths) {
    Write-Host "  $p"
}