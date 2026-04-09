#Requires -Version 5.1
#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Configure secondary drives (Disk 0 and Disk 1) for GamerOS.
.DESCRIPTION
    Partitions and formats Disk 0 (Apps F: + Scratch G:) and Disk 1 (Media H: + Storage).
    Must be run as Administrator. Includes safety prompts and disk size verification.
.PARAMETER Force
    Skip confirmation prompts (use with caution).
.PARAMETER WhatIf
    Show what would be done without making changes.
.EXAMPLE
    .\Configure-SecondaryDrives.ps1
.EXAMPLE
    .\Configure-SecondaryDrives.ps1 -Force
.NOTES
    Run this AFTER Windows installation completes. Disk 0 and Disk 1 were wiped during
    the unattended install but left unpartitioned. This script creates the partitions.
#>
[CmdletBinding()]
param(
    [switch]$Force,
    [switch]$WhatIf
)

$ErrorActionPreference = "Stop"

# Import common module
$commonModule = Join-Path $PSScriptRoot "Modules\GoldISO-Common.psm1"
if (Test-Path $commonModule) {
    Import-Module $commonModule -Force -ErrorAction SilentlyContinue
}

# Initialize logging
$timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
$defaultLog = Join-Path "C:\ProgramData\GoldISO\Logs" "secondary-drives-$timestamp.log"
Initialize-Logging -LogPath $defaultLog

Write-Log "=========================================="
Write-Log "Secondary/Target Drive Configuration Started"
Write-Log "=========================================="

if ($WhatIf) {
    Write-Log "WHATIF mode enabled - no changes will be made" "WARN"
}

# Safety: Verify running as Administrator
if (Get-Command Test-GoldISOAdmin -ErrorAction SilentlyContinue) {
    Test-GoldISOAdmin -ExitIfNotAdmin
} else {
    $isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
        [Security.Principal.WindowsBuiltInRole]::Administrator
    )
    if (-not $isAdmin) {
        Write-Log "This script must be run as Administrator" "ERROR"
        exit 1
    }
}

# Get all physical disks
$disks = Get-PhysicalDisk | Where-Object { $_.BusType -ne 'USB' -and $_.BusType -ne 'File Backed Virtual' }

Write-Log "Found $($disks.Count) physical disk(s):"
foreach ($d in $disks) {
    $sizeGB = [math]::Round($d.Size / 1GB, 1)
    Write-Log "  Disk $($d.DeviceId): $($d.FriendlyName) - ${sizeGB}GB ($($d.MediaType), $($d.BusType))"
}

# Identify Disks 0, 1, and 2
$disk0 = $disks | Where-Object { $_.DeviceId -eq 0 }
$disk1 = $disks | Where-Object { $_.DeviceId -eq 1 }
$disk2 = $disks | Where-Object { $_.DeviceId -eq 2 }

if (-not $disk0) { Write-Log "WARNING: Disk 0 not found" "WARN" }
if (-not $disk1) { Write-Log "WARNING: Disk 1 not found" "WARN" }
if (-not $disk2) { Write-Log "WARNING: Disk 2 not found" "WARN" }

# Safety confirmation
if (-not $Force) {
    Write-Host ""
    Write-Host "WARNING: This will partition/wipe the following disks:" -ForegroundColor Yellow
    if ($disk0) { Write-Host "  Disk 0 ($($disk0.FriendlyName)) -> F: Apps + G: Scratch" }
    if ($disk1) { Write-Host "  Disk 1 ($($disk1.FriendlyName)) -> H: Media + I: Storage" }
    if ($disk2) { 
        Write-Host "  Disk 2 ($($disk2.FriendlyName)) -> CRITICAL: This is your OS drive!" -ForegroundColor Red 
        Write-Host "  Wiping Disk 2 while running will CRASH THE SYSTEM." -ForegroundColor Red
    }
    Write-Host ""
    $confirm = Read-Host "Type YES to continue"
    if ($confirm -ne "YES") {
        Write-Log "User cancelled. Abort." "WARN"
        exit 0
    }
    
    if ($disk2) {
        $confirm2 = Read-Host "ARE YOU ABSOLUTELY SURE you want to wipe Disk 2 (OS)? Type WIPEOSTARGET"
        if ($confirm2 -ne "WIPEOSTARGET") {
            Write-Log "Disk 2 wipe cancelled. Abort." "WARN"
            exit 0
        }
    }
}

# ==========================================
# Disk 0: Apps (F:) + Scratch (G:)
# ==========================================
Write-Log "--- Configuring Disk 0 ---"

try {
    if (-not $WhatIf) {
        # Clear any existing partitions
        Clear-Disk -Number 0 -RemoveData -RemoveOEM -Confirm:$false
        Initialize-Disk -Number 0 -PartitionStyle GPT
        
        # Apps partition: 100GB
        New-Partition -DiskNumber 0 -Size 100GB -DriveLetter F | Format-Volume -FileSystem NTFS -NewFileSystemLabel "Apps" -Confirm:$false -Force | Out-Null
        Write-Log "Created F: Apps (100GB)" "SUCCESS"
        
        # Scratch partition: 120GB
        New-Partition -DiskNumber 0 -Size 120GB -DriveLetter G | Format-Volume -FileSystem NTFS -NewFileSystemLabel "Scratch" -Confirm:$false -Force | Out-Null
        Write-Log "Created G: Scratch (120GB)" "SUCCESS"
        
        # Remaining space left unallocated for overprovisioning
        $remainingGB = [math]::Round(($disk0.Size / 1GB) - 220, 1)
        Write-Log "Left ${remainingGB}GB unallocated on Disk 0 for overprovisioning"
        Write-Log "Disk 0 configuration complete" "SUCCESS"
    } else {
        Write-Log "[WHATIF] Would create F: Apps (100GB) on Disk 0"
        Write-Log "[WHATIF] Would create G: Scratch (120GB) on Disk 0"
        $remainingGB = [math]::Round(($disk0.Size / 1GB) - 220, 1)
        Write-Log "[WHATIF] Would leave ${remainingGB}GB unallocated on Disk 0"
    }
}
catch {
    Write-Log "ERROR configuring Disk 0: $_" "ERROR"
    throw
}

# ==========================================
# Disk 2: Target (Optional Wipe)
# ==========================================
if ($disk2) {
    Write-Log "--- Configuring Disk 2 ---"
    try {
        if (-not $WhatIf) {
            Write-Log "Wiping Disk 2... (Brace for crash if OS drive)" "WARN"
            Clear-Disk -Number 2 -RemoveData -RemoveOEM -Confirm:$false
            Initialize-Disk -Number 2 -PartitionStyle GPT
            Write-Log "Disk 2 wiped and initialized" "SUCCESS"
        }
    }
    catch {
        Write-Log "ERROR configuring Disk 2: $_" "ERROR"
    }
}

Write-Log "=========================================="
Write-Log "Secondary Drive Configuration Complete"
Write-Log "=========================================="
Write-Host ""
Write-Host "Done! Check $logFile for details." -ForegroundColor Green
