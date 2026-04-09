#Requires -Version 5.1
<#
.SYNOPSIS
    Validate GoldISO after build
.DESCRIPTION
    Post-build validation to ensure ISO is properly constructed:
    - ISO mounts without error
    - Required files present
    - Bootable structure
    - Size within expected range
.PARAMETER ISOPath
    Path to ISO to validate (auto-detected if not provided)
.EXAMPLE
    .\Test-ISO.ps1
.EXAMPLE
    .\Test-ISO.ps1 -ISOPath "C:\Build\GamerOS.iso"
#>
[CmdletBinding()]
param(
    [string]$ISOPath = ""
)

$ErrorActionPreference = "Stop"

$ProjectRoot = Split-Path $PSScriptRoot -Parent

if (-not $ISOPath) {
    $isoFiles = Get-ChildItem -Path $ProjectRoot -Filter "*.iso" -ErrorAction SilentlyContinue
    if ($isoFiles) {
        $ISOPath = $isoFiles[0].FullName
    }
}

if (-not $ISOPath -or -not (Test-Path $ISOPath)) {
    Write-Host "ISO not found. Please specify -ISOPath" -ForegroundColor Red
    exit 1
}

Write-Host "=== GoldISO Validation ===" -ForegroundColor Cyan
Write-Host "ISO: $ISOPath" -ForegroundColor Gray
Write-Host ""

$results = [PSCustomObject]@{
    Test = "ISO Exists"
    Status = "PASS"
    Details = ""
}

$iso = Get-Item $ISOPath
$results | Add-Member -NotePropertyName "SizeGB" -NotePropertyValue ([math]::Round($iso.Length / 1GB, 2))

if ($iso.Length -lt 1GB) {
    $results[0].Status = "FAIL"
    $results[0].Details = "ISO too small (< 1GB)"
}
elseif ($iso.Length -gt 20GB) {
    $results[0].Status = "FAIL"
    $results[0].Details = "ISO too large (> 20GB)"
}
else {
    $results[0].Details = "$([math]::Round($iso.Length / 1GB, 2)) GB"
}

Write-Host "$($results[0].Test): $($results[0].Status) ($($results[0].Details))" -ForegroundColor $(if ($results[0].Status -eq "PASS") { "Green" } else { "Red" })

Write-Host ""
Write-Host "Mounting ISO..." -ForegroundColor Yellow

try {
    $mount = Mount-DiskImage -ImagePath $ISOPath -PassThru -ErrorAction Stop
    $driveLetter = $mount.ImageLetter
    
    Write-Host "Mounted as: $driveLetter" -ForegroundColor Gray
    
    $tests = @(
        @{ Test = "autounattend.xml"; Path = "$driveLetter\autounattend.xml" },
        @{ Test = "sources/install.wim"; Path = "$driveLetter\sources\install.wim" },
        @{ Test = "sources/boot.wim"; Path = "$driveLetter\sources\boot.wim" },
        @{ Test = "boot/bootfilelist.txt"; Path = "$driveLetter\boot\bootfilelist.txt" },
        @{ Test = "efi/microsoft/boot"; Path = "$driveLetter\efi\microsoft\boot" }
    )
    
    $allPassed = $true
    
    foreach ($t in $tests) {
        $exists = Test-Path $t.Path
        $status = if ($exists) { "PASS" } else { "FAIL" }
        $color = if ($exists) { "Green" } else { "Red" }
        if (-not $exists) { $allPassed = $false }
        
        Write-Host "  $($t.Test): $status" -ForegroundColor $color
    }
    
    Dismount-DiskImage -ImagePath $ISOPath | Out-Null
    
    Write-Host ""
    if ($allPassed) {
        Write-Host "ISO Validation: PASSED" -ForegroundColor Green
        exit 0
    }
    else {
        Write-Host "ISO Validation: FAILED" -ForegroundColor Red
        exit 1
    }
}
catch {
    Write-Host "Failed to mount ISO: $_" -ForegroundColor Red
    exit 1
}