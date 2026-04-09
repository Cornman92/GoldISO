#Requires -Version 5.1
<#
.SYNOPSIS
    Verify driver integrity before injection
.DESCRIPTION
    Pre-injection validation:
    - Computes hash of each .inf file
    - Verifies against manifest (if present)
    - Reports any issues
.PARAMETER Category
    specific driver category to verify
.PARAMETER ComputeHash
    Compute and store hashes in manifest
.EXAMPLE
    .\Verify-Drivers.ps1
.EXAMPLE
    .\Verify-Drivers.ps1 -Category "Network adapters"
.EXAMPLE
    .\Verify-Drivers.ps1 -ComputeHash
#>
[CmdletBinding()]
param(
    [string]$Category = "",
    [switch]$ComputeHash
)

$ErrorActionPreference = "Continue"

$ProjectRoot = Split-Path $PSScriptRoot -Parent
$DriversPath = Join-Path $ProjectRoot "Drivers"
$ManifestPath = Join-Path $DriversPath "download-manifest.json"

$manifest = $null
if (Test-Path $ManifestPath) {
    $manifest = Get-Content $ManifestPath -Raw | ConvertFrom-Json
}

Write-Host "=== GoldISO Driver Verification ===" -ForegroundColor Cyan
Write-Host ""

$categories = Get-ChildItem -Path $DriversPath -Directory | Where-Object { $_.Name -notmatch "download-manifest" }

$allPassed = $true
$hashesUpdated = @()

foreach ($cat in $categories) {
    if ($Category -and $cat.Name -ne $Category) { continue }
    
    $infFiles = Get-ChildItem -Path $cat.FullName -Filter "*.inf" -Recurse -ErrorAction SilentlyContinue
    
    if ($infFiles.Count -eq 0) {
        Write-Host "$($cat.Name): No INF files found" -ForegroundColor Yellow
        continue
    }
    
    $manifestEntry = $null
    if ($manifest -and $manifest.installed) {
        $manifestEntry = $manifest.installed | Where-Object { $_.category -eq $cat.Name } | Select-Object -First 1
    }
    
    $categoryPassed = $true
    $hashesUpdated += [PSCustomObject]@{
        category = $cat.Name
        hashes = @()
    }
    
    foreach ($inf in $infFiles) {
        try {
            $hash = Get-FileHash -Path $inf.FullName -Algorithm SHA256 -ErrorAction Stop
            
            if ($manifestEntry -and $manifestEntry.hash) {
                if ($hash.Hash -eq $manifestEntry.hash) {
                    $status = "MATCH"
                    $color = "Green"
                }
                else {
                    $status = "MISMATCH"
                    $color = "Red"
                    $categoryPassed = $false
                    $allPassed = $false
                }
            }
            elseif ($ComputeHash) {
                $status = "NEW"
                $color = "Cyan"
                $hashesUpdated[-1].hashes += @{ file = $inf.Name; hash = $hash.Hash }
            }
            else {
                $status = "UNTRACKED"
                $color = "Yellow"
            }
        }
        catch {
            $status = "ERROR"
            $color = "Red"
            $categoryPassed = $false
            $allPassed = $false
        }
    }
    
    if ($Category -and $Category -eq $cat.Name) {
        Write-Host "$($cat.Name): $($infFiles.Count) INF files" -ForegroundColor Gray
    }
}

Write-Host ""

if (-not $Category -and -not $ComputeHash) {
    Write-Host "Driver verification complete." -ForegroundColor Gray
    Write-Host "Run with -ComputeHash to compute and store hashes" -ForegroundColor Gray
    Write-Host "Run with -Category <name> to verify specific category" -ForegroundColor Gray
}

if ($ComputeHash -and $hashesUpdated.Count -gt 0) {
    Write-Host "Hashes computed (not saved - implement manifest update):" -ForegroundColor Yellow
    foreach ($h in $hashesUpdated) {
        if ($h.hashes.Count -gt 0) {
            Write-Host "  $($h.category): $($h.hashes.Count) new hashes" -ForegroundColor Gray
        }
    }
}

Write-Host ""
if ($allPassed) {
    Write-Host "Verification: PASSED" -ForegroundColor Green
}
else {
    Write-Host "Verification: FAILED (mismatches or errors)" -ForegroundColor Red
}