#Requires -Version 5.1
#Requires -RunAsAdministrator

<#
.SYNOPSIS
    Configures reserved drive letters for GamerOS-3Disk layout.

.DESCRIPTION
    Assigns permanent drive letters to USB drives, network drives, RamDisk, and mounts.
    Run this after FirstLogonCommands to claim your reserved letters.

.RESERVED LETTERS
    U, V, W - USB Drives
    Y, Z    - Network Drives  
    R       - RamDisk
    M       - First mount point
    T       - Temp mounts

.EXAMPLE
    .\Setup-DriveLetters.ps1 -UsbU "USB Drive Label" -NetworkY "\\server\share"
#>

[CmdletBinding()]
param(
    [string]$UsbU,          # Label of USB drive to assign to U:
    [string]$UsbV,          # Label of USB drive to assign to V:
    [string]$UsbW,          # Label of USB drive to assign to W:
    [string]$NetworkY,      # UNC path for Y: drive
    [string]$NetworkZ,      # UNC path for Z: drive
    [switch]$CreateRamDiskR,# Create RamDisk at R:
    [int]$RamDiskSizeGB = 4,# Size of RamDisk in GB
    [switch]$SetupMountM    # Claim M: as mount point
)

$ErrorActionPreference = "Stop"

if (Test-Path (Join-Path $PSScriptRoot "..\Modules\GoldISO-Common.psm1")) {
    Import-Module (Join-Path $PSScriptRoot "..\Modules\GoldISO-Common.psm1") -Force
}

function Write-Status {
    param([string]$Message, [string]$Status = "INFO")
    $timestamp = Get-Date -Format "HH:mm:ss"
    $color = switch ($Status) {
        "SUCCESS" { "Green" }
        "WARN"    { "Yellow" }
        "ERROR"   { "Red" }
        default   { "Cyan" }
    }
    Write-Host "[$timestamp] [$Status] $Message" -ForegroundColor $color
}

function Get-AvailableLetter {
    # Return first unprotected available letter
    $protected = @('D','E','F','C','U','V','W','X','Y','Z','R','T','M')
    $used = (Get-Volume).DriveLetter | ForEach-Object { $_.ToString().ToUpper() }
    $available = 'A'..'Z' | Where-Object { $_ -notin $protected -and $_ -notin $used }
    return $available | Select-Object -First 1
}

function Set-UsbDriveLetter {
    param([string]$Label, [string]$Letter)
    
    if (-not $Label) { return }
    
    Write-Status "Looking for USB drive: $Label" "INFO"
    
    # Find volume by label
    $volume = Get-Volume | Where-Object { 
        $_.FileSystemLabel -eq $Label -and $_.DriveType -eq 'Removable' 
    } | Select-Object -First 1
    
    if (-not $volume) {
        Write-Status "USB drive '$Label' not found. Skipping $Letter" "WARN"
        return
    }
    
    # Check if already assigned correctly
    if ($volume.DriveLetter -eq $Letter) {
        Write-Status "$Letter is already assigned to '$Label'" "SUCCESS"
        return
    }
    
    # Check if target letter is occupied
    $existing = Get-Volume | Where-Object { $_.DriveLetter -eq $Letter }
    if ($existing) {
        $fallback = Get-AvailableLetter
        Write-Status "$Letter is occupied. Reassigning to $fallback" "WARN"
        Get-WmiObject -Class Win32_Volume | 
            Where-Object { $_.DriveLetter -eq "$Letter`:" } |
            ForEach-Object { $_.DriveLetter = "$fallback`:"; $_.Put() | Out-Null }
    }
    
    # Assign the USB drive to target letter
    $vol = Get-WmiObject -Class Win32_Volume | 
        Where-Object { $_.DeviceID -eq $volume.Path }
    
    if ($vol) {
        $vol.DriveLetter = "$Letter`:"
        $vol.Put() | Out-Null
        Write-Status "Assigned $Letter to USB drive '$Label'" "SUCCESS"
    }
}

function Set-NetworkDrive {
    param([string]$Path, [string]$Letter, [pscredential]$Credential)
    
    if (-not $Path) { return }
    
    Write-Status "Mapping network drive $Letter to $Path" "INFO"
    
    # Remove existing mapping if present
    if (Test-Path "$Letter`:") {
        net use "$Letter`:" /delete /y 2>$null
    }
    
    # Create new mapping
    $result = if ($Credential) {
        net use "$Letter`:" $Path /persistent:yes $Credential.GetNetworkCredential().Password /user:$($Credential.UserName) 2>&1
    } else {
        net use "$Letter`:" $Path /persistent:yes 2>&1
    }
    
    if ($LASTEXITCODE -eq 0) {
        Write-Status "Mapped $Letter to $Path" "SUCCESS"
    } else {
        Write-Status "Failed to map $Letter. Result: $result" "ERROR"
    }
}

function New-RamDiskR {
    param([int]$SizeGB)
    
    Write-Status "Creating RamDisk R: (${SizeGB}GB)" "INFO"
    
    # Check if ImDisk is installed
    $imdisk = Get-Command imdisk.exe -ErrorAction SilentlyContinue
    if (-not $imdisk) {
        Write-Status "ImDisk not found. Install from http://www.ltr-data.se/opencode.html#/ImDisk" "WARN"
        return
    }
    
    # Check if R: already exists
    if (Test-Path "R:\") {
        Write-Status "R: already exists. Remove existing RamDisk first." "WARN"
        return
    }
    
    # Create RamDisk
    $sizeBytes = $SizeGB * 1GB
    imdisk.exe -a -s "$sizeBytes" -m R: -p "/fs:ntfs /q /y" 2>&1 | Out-Null
    
    if (Test-Path "R:\") {
        Write-Status "RamDisk R: created (${SizeGB}GB)" "SUCCESS"
    } else {
        Write-Status "Failed to create RamDisk R:" "ERROR"
    }
}

function Claim-MountPoint {
    Write-Status "Claiming M: as mount point" "INFO"
    
    # Check if M: is occupied
    if (Test-Path "M:\") {
        $fallback = Get-AvailableLetter
        Write-Status "M: is occupied. Reassigning to $fallback" "WARN"
        
        Get-WmiObject -Class Win32_Volume | 
            Where-Object { $_.DriveLetter -eq "M`:`" } |
            ForEach-Object { 
                $_.DriveLetter = "$fallback`:" 
                $_.Put() | Out-Null 
            }
    }
    
    # Create placeholder directory structure
    New-Item -ItemType Directory -Path "M:\Mounts" -Force -ErrorAction SilentlyContinue | Out-Null
    New-Item -ItemType Directory -Path "M:\ISOs" -Force -ErrorAction SilentlyContinue | Out-Null
    New-Item -ItemType Directory -Path "M:\VHDs" -Force -ErrorAction SilentlyContinue | Out-Null
    
    Write-Status "M: is ready for mounts (subsequent mounts will use next available)" "SUCCESS"
}

# ==================== MAIN ====================

Write-Status "=== Drive Letter Setup for GamerOS-3Disk ===" "INFO"
Write-Status "Reserved: D,E,F,C (system), U,V,W (USB), Y,Z (network), R (RamDisk), M,T (mounts)" "INFO"
Write-Host ""

# USB Drives
if ($UsbU) { Set-UsbDriveLetter -Label $UsbU -Letter "U" }
if ($UsbV) { Set-UsbDriveLetter -Label $UsbV -Letter "V" }
if ($UsbW) { Set-UsbDriveLetter -Label $UsbW -Letter "W" }

# Network Drives  
if ($NetworkY) { Set-NetworkDrive -Path $NetworkY -Letter "Y" }
if ($NetworkZ) { Set-NetworkDrive -Path $NetworkZ -Letter "Z" }

# RamDisk
if ($CreateRamDiskR) { New-RamDiskR -SizeGB $RamDiskSizeGB }

# Mount Point
if ($SetupMountM) { Claim-MountPoint }

Write-Host ""
Write-Status "=== Setup Complete ===" "SUCCESS"
Write-Status "Available letters for additional mounts: $(Get-AvailableLetter) and following" "INFO"
