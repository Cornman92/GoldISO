#Requires -Version 5.1
<#
.SYNOPSIS
    Get GoldISO build manifest information
.DESCRIPTION
    Reads and displays the current build manifest from Config/build-manifest.json
.PARAMETER ShowDetails
    Show detailed component information
.EXAMPLE
    .\Get-BuildManifest.ps1
.EXAMPLE
    .\Get-BuildManifest.ps1 -ShowDetails
#>
[CmdletBinding()]
param(
    [switch]$ShowDetails
)

$ErrorActionPreference = "Stop"

if (Test-Path (Join-Path $PSScriptRoot "..\Modules\GoldISO-Common.psm1")) {
    Import-Module (Join-Path $PSScriptRoot "..\Modules\GoldISO-Common.psm1") -Force
}

$ProjectRoot = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
$ManifestPath = Join-Path $ProjectRoot "Config\build-manifest.json"

if (-not (Test-Path $ManifestPath)) {
    Write-Host "Build manifest not found: $ManifestPath" -ForegroundColor Red
    exit 1
}

$manifest = Get-Content $ManifestPath -Raw | ConvertFrom-Json

Write-Host "=== GoldISO Build Manifest ===" -ForegroundColor Cyan
Write-Host ""

if ($manifest.builds -and $manifest.builds.Count -gt 0) {
    $latest = $manifest.builds[-1]
    Write-Host "Current Build:" -ForegroundColor Yellow
    Write-Host "  Version:    $($latest.isoVersion)"
    Write-Host "  Date:       $($latest.date)"
    Write-Host "  Source:     $($latest.source)"
    Write-Host "  Notes:      $($latest.buildNotes)"
    
    if ($latest.components) {
        Write-Host "  Components:  $($latest.components.driverCategories) driver categories, $($latest.components.packages) packages, $($latest.components.apps) apps"
    }
}

Write-Host ""

if ($manifest.profiles -and $manifest.profiles.Count -gt 0) {
    Write-Host "Build Profiles:" -ForegroundColor Yellow
    foreach ($profile in $manifest.profiles) {
        Write-Host "  $($profile.name): $($profile.description)"
    }
}

if ($ShowDetails) {
    Write-Host ""
    Write-Host "All Builds:" -ForegroundColor Yellow
    foreach ($build in $manifest.builds) {
        Write-Host "  - $($build.isoVersion) ($($build.date)) - $($build.buildNotes)"
    }
}

Write-Host ""
Write-Host "Manifest Version: $($manifest.version)" -ForegroundColor Gray
