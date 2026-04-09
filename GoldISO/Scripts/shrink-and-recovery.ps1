#Requires -Version 5.1
#Requires -RunAsAdministrator

# Import common module (may not exist in WinPE/target environment, so wrap in try/catch)
try {
    Import-Module (Join-Path $PSScriptRoot "Modules\GoldISO-Common.psm1") -Force -ErrorAction Stop
} catch {
    # Module not available in target environment, logging initialized below
}

<#
.SYNOPSIS
    Shrinks Windows partition by 105 GB, creates 15 GB Recovery partition, leaves rest as unallocated for Samsung NVMe overprovisioning.
.DESCRIPTION
    Runs during specialize phase. Targets Disk 2 by DeviceId.
    Shrinks C: by 107,520 MB (105 GB), creates 15,360 MB Recovery partition,
    and leaves ~92,160 MB (~90 GB) unallocated for Samsung overprovisioning.
    Designed to never fail — logs errors and continues gracefully.
.PARAMETER DiskNumber
    The disk number to target (default: 2)
.PARAMETER ShrinkGB
    Amount to shrink C: drive in GB (default: 105)
.PARAMETER RecoveryGB
    Size of Recovery partition in GB (default: 15)
.EXAMPLE
    .\shrink-and-recovery.ps1
    Shrinks C: by 105GB, creates 15GB Recovery, leaves rest unallocated
.EXAMPLE
    .\shrink-and-recovery.ps1 -DiskNumber 0 -ShrinkGB 80 -RecoveryGB 20
    Custom configuration for different disk
#>
[CmdletBinding()]
param(
    [int]$DiskNumber = 2,
    [int]$ShrinkGB = 105,
    [int]$RecoveryGB = 15
)

$ErrorActionPreference = "Continue"

# Initialize centralized logging (or use local fallback)
$logFile = "C:\ProgramData\Winhance\Unattend\Logs\disk-config.log"
Initialize-Logging -LogPath $logFile

Write-Log "=========================================="
Write-Log "Disk Partition Resize Script Started"
Write-Log "Parameters: Disk=$DiskNumber, Shrink=${ShrinkGB}GB, Recovery=${RecoveryGB}GB"
Write-Log "=========================================="

try {
    # Validate we're running as admin
    $isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    if (-not $isAdmin) {
        Write-Log "ERROR: This script must be run as Administrator" "ERROR"
        exit 1
    }

    # Idempotency guard: skip if Recovery partition already exists on the target disk.
    # This happens when the modular build (GamerOS-3Disk layout) already created the
    # full partition structure during windowsPE — no shrink is needed.
    $recoveryTypeId = "de94bba4-06d1-4d40-a16a-bfd50179d6ac"
    $existingRecovery = Get-Partition -DiskNumber $DiskNumber -ErrorAction SilentlyContinue |
        Where-Object { $_.GptType -and $_.GptType -eq "{$recoveryTypeId}" }
    if (-not $existingRecovery) {
        # Also check by partition count: GamerOS-3Disk layout creates 5 partitions on Disk 2
        $partCount = (Get-Partition -DiskNumber $DiskNumber -ErrorAction SilentlyContinue).Count
        if ($partCount -ge 4) {
            Write-Log "Disk $DiskNumber already has $partCount partitions (Recovery/OP layout detected). Skipping shrink." "INFO"
            exit 0
        }
    } else {
        Write-Log "Recovery partition already exists on Disk $DiskNumber. Skipping shrink (layout already applied)." "INFO"
        exit 0
    }

    # Get target disk by DeviceId
    $disk = Get-PhysicalDisk | Where-Object { $_.DeviceId -eq $DiskNumber }
    if (-not $disk) {
        Write-Log "ERROR: Disk $DiskNumber (DeviceId=$DiskNumber) not found. Skipping." "ERROR"
        exit 0
    }

    $diskSizeMB = [math]::Floor($disk.Size / 1MB)
    Write-Log "Disk $DiskNumber found: $($disk.FriendlyName) — Total: ${diskSizeMB} MB ($([math]::Round($disk.Size/1GB, 1)) GB)"

    # Get C: partition
    $winPart = Get-Partition -DriveLetter C -ErrorAction SilentlyContinue
    if (-not $winPart) {
        Write-Log "ERROR: C: partition not found. Skipping." "ERROR"
        exit 0
    }

    $currentSizeMB = [math]::Floor($winPart.Size / 1MB)
    Write-Log "Current C: partition size: ${currentSizeMB} MB ($([math]::Round($winPart.Size/1GB, 1)) GB)"

    # Calculate sizes
    $shrinkMB = $ShrinkGB * 1024
    $recoveryMB = $RecoveryGB * 1024
    $opMB = $shrinkMB - $recoveryMB

    $newWinSizeMB = $currentSizeMB - $shrinkMB
    if ($newWinSizeMB -lt 51200) {
        Write-Log "ERROR: New Windows partition would be too small (${newWinSizeMB} MB). Minimum is 51200 MB (50 GB). Skipping." "ERROR"
        exit 0
    }

    Write-Log "Shrinking C: by ${shrinkMB} MB ($([math]::Round($shrinkMB/1024, 1)) GB)"
    Write-Log "  New C: size: ${newWinSizeMB} MB ($([math]::Round($newWinSizeMB/1024, 1)) GB)"
    Write-Log "  Recovery: ${recoveryMB} MB (${RecoveryGB} GB)"
    Write-Log "  Unallocated (OP): ${opMB} MB ($([math]::Round($opMB/1024, 1)) GB)"

    # Check if C: is on the target disk
    $cDisk = Get-Partition -DriveLetter C | Get-Disk
    if ($cDisk.Number -ne $DiskNumber) {
        Write-Log "WARNING: C: drive is on Disk $($cDisk.Number), not Disk $DiskNumber. Adjusting target..." "WARNING"
        $DiskNumber = $cDisk.Number
    }

    # Defrag and optimize before shrink (only on HDD, skip on SSD)
    $isSSD = $disk.MediaType -eq "SSD"
    if (-not $isSSD) {
        Write-Log "Optimizing C: before shrink (HDD detected)..."
        try {
            Optimize-Volume -DriveLetter C -Defrag -ErrorAction SilentlyContinue
            Write-Log "Optimization complete"
        } catch {
            Write-Log "Defrag skipped (non-critical): $_" "WARNING"
        }
    } else {
        Write-Log "SSD detected, skipping defrag"
    }

    # Shrink C: partition
    $newWinSize = $newWinSizeMB * 1MB
    Write-Log "Resizing C: partition to ${newWinSizeMB} MB..."

    try {
        Resize-Partition -DriveLetter C -Size $newWinSize -ErrorAction Stop
        Write-Log "C: partition resized successfully" "SUCCESS"
    }
    catch {
        Write-Log "ERROR: Failed to resize partition: $_" "ERROR"
        Write-Log "This may happen if there are unmovable files. Consider running with -ShrinkGB value." "ERROR"
        exit 0
    }

    # Create Recovery partition in unallocated space
    Write-Log "Creating Recovery partition (${recoveryMB} MB)..."
    try {
        $recoveryPart = New-Partition -DiskNumber $DiskNumber -Size ($recoveryMB * 1MB) -ErrorAction Stop
        Write-Log "Recovery partition created (Partition $($recoveryPart.PartitionNumber))" "SUCCESS"
    }
    catch {
        Write-Log "ERROR: Failed to create Recovery partition: $_" "ERROR"
        exit 0
    }

    # Format Recovery partition
    Write-Log "Formatting Recovery partition as NTFS..."
    try {
        Format-Volume -Partition $recoveryPart -FileSystem NTFS -NewFileSystemLabel "Recovery" -Confirm:$false -Force -ErrorAction Stop
        Write-Log "Recovery partition formatted" "SUCCESS"
    }
    catch {
        Write-Log "ERROR: Failed to format Recovery partition: $_" "ERROR"
        exit 0
    }

    # Set GPT type to Microsoft Recovery (hidden, protected)
    Write-Log "Setting Recovery partition GPT type..."
    try {
        Set-Partition -DiskNumber $DiskNumber -PartitionNumber $recoveryPart.PartitionNumber -GptType '{de94bba4-06d1-4d40-a16a-bfd50179d6ac}' -ErrorAction Stop
        Write-Log "Recovery partition GPT type set (hidden)" "SUCCESS"
    }
    catch {
        Write-Log "WARNING: Could not set GPT type (non-critical): $_" "WARNING"
    }

    # Remove drive letter if assigned (Recovery partitions should not be visible)
    if ($recoveryPart.DriveLetter) {
        try {
            Remove-PartitionAccessPath -DiskNumber $DiskNumber -PartitionNumber $recoveryPart.PartitionNumber -AccessPath "$($recoveryPart.DriveLetter):" -ErrorAction SilentlyContinue
            Write-Log "Removed drive letter from Recovery partition"
        }
        catch {
            Write-Log "Could not remove drive letter (non-critical): $_" "WARNING"
        }
    }

    $opGB = [math]::Round($opMB / 1024, 1)
    $newWinSizeGB = [math]::Round($newWinSizeMB/1024, 1)
    Write-Log "==========================================" "SUCCESS"
    Write-Log "Disk Partition Resize Complete" "SUCCESS"
    Write-Log "  C: = $newWinSizeMB MB ($newWinSizeGB GB)" "SUCCESS"
    Write-Log "  Recovery = $recoveryMB MB ($RecoveryGB GB, hidden)" "SUCCESS"
    Write-Log "  Unallocated (Samsung OP) = $opMB MB (~$opGB GB)" "SUCCESS"
    Write-Log "==========================================" "SUCCESS"
}
catch {
    Write-Log "ERROR during disk partition resize: $_" "ERROR"
    Write-Log "ScriptStackTrace: $($_.ScriptStackTrace)" "ERROR"
    Write-Log "Continuing — this is non-fatal." "WARNING"
}
