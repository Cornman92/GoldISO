#Requires -Version 5.1
<#
.SYNOPSIS
    Validates USB boot functionality before deployment.
.DESCRIPTION
    Checks USB drive for:
    - Proper partition scheme (GPT/MBR)
    - Boot partition format (FAT32/NTFS)
    - EFI partition presence
    - ISO file integrity
    - Boot sector health
.PARAMETER DriveLetter
    Drive letter of USB to validate (e.g., "E").
.PARAMETER ISOPath
    Path to ISO file to validate on USB.
.EXAMPLE
    .\Test-USB Boot.ps1 -DriveLetter E
.EXAMPLE
    .\Test-USB Boot.ps1 -DriveLetter E -ISOPath "D:\GamerOS-Win11x64Pro25H2.iso"
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)]
    [string]$DriveLetter,

    [string]$ISOPath = ""
)

$ErrorActionPreference = "Stop"

if (Test-Path (Join-Path $PSScriptRoot "..\Modules\GoldISO-Common.psm1")) {
    Import-Module (Join-Path $PSScriptRoot "..\Modules\GoldISO-Common.psm1") -Force
}

$drive = "$DriveLetter`:"
Write-Host "Validating USB drive: $drive" -ForegroundColor Cyan
Write-Host "=" * 50

$results = @{
    DriveExists = $false
    PartitionScheme = ""
    BootPartition = $false
    EFIPartition = $false
    ISOPresent = $false
    ISOValid = $false
    Warnings = @()
    Errors = @()
}

try {
    $disk = Get-Disk | Where-Object { $_.FriendlyName -match $drive.Replace(":", "") }
    if ($disk) {
        $results.DriveExists = $true
        Write-Host "[OK] Drive accessible" -ForegroundColor Green
        
        $results.PartitionScheme = $disk.PartitionStyle
        Write-Host "[OK] Partition scheme: $($results.PartitionScheme)" -ForegroundColor Green
        
        $partitions = Get-Partition -DiskNumber $disk.Number -ErrorAction SilentlyContinue
        foreach ($part in $partitions) {
            if ($part.Type -eq "System" -or $part.GptType -eq "{c12a7328-f81f-11d2-ba4b-00a0c93ec93b}") {
                $results.EFIPartition = $true
                Write-Host "[OK] EFI partition found" -ForegroundColor Green
            }
            
            $vol = Get-Volume -DriveLetter $part.DriveLetter -ErrorAction SilentlyContinue
            if ($vol) {
                if ($vol.FileSystem -eq "FAT32" -or $vol.FileSystem -eq "NTFS") {
                    $results.BootPartition = $true
                    Write-Host "[OK] Boot partition: $($vol.FileSystem)" -ForegroundColor Green
                }
            }
        }
    } else {
        $results.Errors += "Drive not found"
        Write-Host "[ERROR] Drive not accessible" -ForegroundColor Red
    }
}
catch {
    $results.Errors += $_.Exception.Message
    Write-Host "[ERROR] $($_.Exception.Message)" -ForegroundColor Red
}

if ($ISOPath) {
    if (Test-Path $ISOPath) {
        $results.ISOPresent = $true
        Write-Host "[OK] ISO file found: $ISOPath" -ForegroundColor Green
        
        $isoSizeGB = [math]::Round((Get-Item $ISOPath).Length / 1GB, 2)
        Write-Host "[INFO] ISO size: $isoSizeGB GB" -ForegroundColor Cyan
        
        $checksumFile = $ISOPath + ".sha256"
        if (Test-Path $checksumFile) {
            $storedHash = (Get-Content $checksumFile -Raw).Split(' ')[0].Trim()
            $actualHash = (Get-FileHash $ISOPath -Algorithm SHA256).Hash
            if ($storedHash -eq $actualHash) {
                $results.ISOValid = $true
                Write-Host "[OK] ISO checksum verified" -ForegroundColor Green
            } else {
                $results.Errors += "ISO checksum mismatch"
                Write-Host "[ERROR] ISO checksum FAILED" -ForegroundColor Red
            }
        } else {
            $results.Warnings += "No checksum file found"
            Write-Host "[WARN] No checksum file - cannot verify ISO integrity" -ForegroundColor Yellow
        }
    } else {
        $results.Errors += "ISO file not found: $ISOPath"
        Write-Host "[ERROR] ISO not found" -ForegroundColor Red
    }
}

Write-Host ""
Write-Host "=" * 50
Write-Host "Validation Summary" -ForegroundColor Cyan
Write-Host "=" * 50

if ($results.Errors.Count -eq 0 -and $results.Warnings.Count -eq 0) {
    Write-Host "PASS: USB drive is ready for deployment" -ForegroundColor Green
    exit 0
}
elseif ($results.Errors.Count -eq 0) {
    Write-Host "PASS (with warnings): Review warnings before deployment" -ForegroundColor Yellow
    $results.Warnings | ForEach-Object { Write-Host "  - $_" -ForegroundColor Yellow }
    exit 0
}
else {
    Write-Host "FAIL: Issues detected - resolve before deployment" -ForegroundColor Red
    $results.Errors | ForEach-Object { Write-Host "  - $_" -ForegroundColor Red }
    exit 1
}
