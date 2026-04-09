#Requires -Version 5.1
<#
.SYNOPSIS
    Scan Drivers directory and report driver versions
.DESCRIPTION
    Scans each driver category folder in Drivers/ and reports:
    - Category name
    - INFs found
    - Version info (from .inf files)
    - Date added (from folder name or manifest)
.PARAMETER Category
    specific category to scan
.EXAMPLE
    .\Get-DriverVersions.ps1
.EXAMPLE
    .\Get-DriverVersions.ps1 -Category "Network adapters"
#>
[CmdletBinding()]
param(
    [string]$Category = ""
)

$ErrorActionPreference = "Continue"

if (Test-Path (Join-Path $PSScriptRoot "..\Modules\GoldISO-Common.psm1")) {
    Import-Module (Join-Path $PSScriptRoot "..\Modules\GoldISO-Common.psm1") -Force
}

$ProjectRoot = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
$DriversPath = Join-Path $ProjectRoot "Drivers"
$ManifestPath = Join-Path $DriversPath "download-manifest.json"

$manifest = $null
if (Test-Path $ManifestPath) {
    $manifest = Get-Content $ManifestPath -Raw | ConvertFrom-Json
}

Write-Host "=== GoldISO Driver Versions ===" -ForegroundColor Cyan
Write-Host ""

$categories = Get-ChildItem -Path $DriversPath -Directory | Where-Object { $_.Name -notmatch "download-manifest" }

$results = @()

foreach ($cat in $categories) {
    if ($Category -and $cat.Name -ne $Category) { continue }
    
    $infFiles = Get-ChildItem -Path $cat.FullName -Filter "*.inf" -Recurse -ErrorAction SilentlyContinue
    
    $versions = @()
    $infCount = 0
    
    foreach ($inf in $infFiles) {
        $infCount++
        $version = "unknown"
        try {
            $content = Get-Content $inf.FullName -Raw -ErrorAction SilentlyContinue
            if ($content -match 'DriverVersion\s*=\s*(\d+\.\d+\.\d+\.\d+)') {
                $version = $matches[1]
            }
            elseif ($inf.Name -match '_(\d+\.\d+\.\d+\.\d+)') {
                $version = $matches[1]
            }
        }
        catch { }
        if ($version -and $versions -notcontains $version) {
            $versions += $version
        }
    }
    
    $manifestEntry = $null
    if ($manifest -and $manifest.installed) {
        $manifestEntry = $manifest.installed | Where-Object { $_.category -eq $cat.Name } | Select-Object -First 1
    }
    
    $results += [PSCustomObject]@{
        Category = $cat.Name
        InfCount = $infCount
        Versions = ($versions | Select-Object -First 3) -join ", "
        ManifestVersion = if ($manifestEntry) { $manifestEntry.version } else { "-" }
        DateAdded = if ($manifestEntry) { $manifestEntry.dateAdded } else { "-" }
        Source = if ($manifestEntry) { $manifestEntry.source } else { "-" }
    }
}

$results | Format-Table -AutoSize

Write-Host ""
Write-Host "Total categories: $($results.Count)" -ForegroundColor Gray
Write-Host "Total INF files: $($results | Measure-Object -Property InfCount -Sum).Sum" -ForegroundColor Gray
