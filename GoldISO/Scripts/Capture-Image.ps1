#Requires -Version 5.1
#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Captures a Windows image from the current system in WinPE.
.DESCRIPTION
    This script runs in WinPE to capture the current Windows installation
    to a WIM file. It handles disk wiping, capturing to C:\Capture.wim,
    and optionally moving to USB.
.PARAMETER TargetDisk
    The disk number to capture from. Default: 2
.PARAMETER CapturePath
    Where to save the captured WIM. Default: C:\Capture.wim
.PARAMETER MoveToUSB
    Move the captured WIM to USB drive after capture. Default: $true
.PARAMETER USBDrive
    USB drive letter to move WIM to. Default: Auto-detect
.EXAMPLE
    .\Capture-Image.ps1
    Captures Disk 2 to C:\Capture.wim and moves to USB
.EXAMPLE
    .\Capture-Image.ps1 -TargetDisk 0 -CapturePath D:\Custom.wim
    Captures Disk 0 to custom location without moving to USB
#>
[CmdletBinding()]
param(
    [int]$TargetDisk = 2,
    [string]$CapturePath = "",
    [bool]$MoveToUSB = $false,
    [string]$USBDrive = $null
)

$ErrorActionPreference = "Stop"
$StartTime = Get-Date

function Write-Log {
    param([string]$Message, [ValidateSet("INFO","WARN","ERROR","SUCCESS")][string]$Level = "INFO")
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $colorMap = @{ INFO = "White"; WARN = "Yellow"; ERROR = "Red"; SUCCESS = "Green" }
    Write-Host "[$timestamp] [$Level] $Message" -ForegroundColor $colorMap[$Level]
}

function Find-WindowsPartition {
    param([int]$DiskNumber)
    
    try {
        $disk = Get-Disk -Number $DiskNumber -ErrorAction SilentlyContinue
        if (-not $disk) {
            Write-Log "Disk $DiskNumber not found" "ERROR"
            return $null
        }
        
        $partitions = Get-Partition -DiskNumber $DiskNumber | Where-Object { 
            $_.Type -eq "Basic" -and $_.Size -gt 50GB 
        } | Sort-Object Size -Descending
        
        if (-not $partitions) {
            Write-Log "No suitable Windows partition found on Disk $DiskNumber" "ERROR"
            return $null
        }
        
        $windowsPart = $partitions | Select-Object -First 1
        $driveLetter = $windowsPart.DriveLetter
        
        if (-not $driveLetter) {
            $availableLetters = 67..90 | ForEach-Object { [char]$_ } | Where-Object { 
                -not (Get-Partition | Where-Object { $_.DriveLetter -eq $_ })
            }
            if ($availableLetters) {
                $driveLetter = $availableLetters | Select-Object -First 1
                Add-PartitionAccessPath -DiskNumber $DiskNumber `
                    -PartitionNumber $windowsPart.PartitionNumber `
                    -AccessPath "$driveLetter`:" -ErrorAction SilentlyContinue
                Write-Log "Assigned temporary drive letter $driveLetter`:" "INFO"
            }
        }
        
        return "${driveLetter}:`"
    }
    catch {
        $errMsg = $_.Exception.Message
        Write-Log ("Error finding Windows partition: " + $errMsg) "ERROR"
        return $null
    }
}

function Find-USBdrive {
    try {
        $usbDrives = Get-Disk | Where-Object { $_.BusType -eq "USB" -and $_.Size -gt 10GB }
        
        foreach ($usb in $usbDrives) {
            $partitions = Get-Partition -DiskNumber $usb.Number | Where-Object { $_.DriveLetter }
            foreach ($part in $partitions) {
                $driveLetter = $part.DriveLetter
                $driveInfo = Get-Volume -DriveLetter $driveLetter
                if ($driveInfo.SizeRemaining -gt 5GB) {
                    return $driveLetter
                }
            }
        }
        
        $potentialUSB = Get-Volume | Where-Object { 
            $_.DriveLetter -and 
            $_.DriveType -eq "Removable" -and
            $_.SizeRemaining -gt 5GB
        } | Select-Object -First 1
        
        if ($potentialUSB) {
            return $potentialUSB.DriveLetter
        }
        
        return $null
    }
    catch {
        $errMsg = $_.Exception.Message
        Write-Log "Error finding USB drive: $errMsg" "WARN"
        return $null
    }
}

Write-Host "============================================================" -ForegroundColor Cyan
Write-Host "  WinPE Image Capture Tool                                  " -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host ""

Write-Log "Starting capture process..."
Write-Log "Target Disk: $TargetDisk"
Write-Log "Capture Path: $CapturePath"

$isWinPE = Test-Path "X:\Windows\System32\WinPE.exe" -ErrorAction SilentlyContinue
if (-not $isWinPE) {
    $isWinPE = (Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion" -Name "EditionID" -ErrorAction SilentlyContinue).EditionID -eq "WindowsPE"
}

if ($isWinPE) {
    Write-Log "Running in Windows PE environment" "SUCCESS"
} else {
    Write-Log "Not in Windows PE - some operations may fail" "WARN"
}

Write-Host "`n[Step 1] Locating Windows partition on Disk $TargetDisk..." -ForegroundColor Yellow
$windowsDrive = Find-WindowsPartition -DiskNumber $TargetDisk

if (-not $windowsDrive) {
    Write-Log "Failed to locate Windows partition" "ERROR"
    exit 1
}

Write-Log "Windows partition found at $windowsDrive" "SUCCESS"

$windowsDir = Join-Path $windowsDrive "Windows"
if (-not (Test-Path $windowsDir)) {
    Write-Log "Windows directory not found at $windowsDir" "ERROR"
    exit 1
}

Write-Host "`n[Step 2] Preparing capture destination..." -ForegroundColor Yellow

$captureDir = Split-Path $CapturePath -Parent
$captureFile = Split-Path $CapturePath -Leaf

if ($captureDir -eq "C:\" -and $windowsDrive -eq "C:\") {
    $altDrive = Get-Volume | Where-Object { 
        $_.DriveLetter -and 
        $_.DriveLetter -ne "C" -and
        $_.SizeRemaining -gt 10GB
    } | Select-Object -First 1
    
    if ($altDrive) {
        $CapturePath = "$($altDrive.DriveLetter):\Capture.wim"
        $captureDir = "$($altDrive.DriveLetter):\"
        Write-Log "Changed capture path to $CapturePath (avoiding Windows drive)" "WARN"
    } else {
        Write-Log "Capturing to Windows drive - ensure sufficient space!" "WARN"
    }
}

if (-not (Test-Path $captureDir)) {
    try {
        New-Item -ItemType Directory -Path $captureDir -Force | Out-Null
        Write-Log "Created capture directory: $captureDir" "SUCCESS"
    }
    catch {
        $errMsg = $_.Exception.Message
        Write-Log "Failed to create capture directory: $errMsg" "ERROR"
        exit 1
    }
}

$destDrive = Get-Volume -FilePath $captureDir
$sourceSize = (Get-ChildItem $windowsDrive -Recurse -File -ErrorAction SilentlyContinue | Measure-Object -Property Length -Sum).Sum
$neededSpace = $sourceSize * 0.4

if ($destDrive.SizeRemaining -lt $neededSpace) {
    Write-Log "Insufficient space on destination drive" "ERROR"
    Write-Log "  Available: $([math]::Round($destDrive.SizeRemaining / 1GB, 2)) GB" "ERROR"
    Write-Log "  Estimated needed: $([math]::Round($neededSpace / 1GB, 2)) GB" "ERROR"
    exit 1
}

Write-Log "Destination has sufficient space" "SUCCESS"

Write-Host "`n[Step 3] Capturing Windows image..." -ForegroundColor Yellow
Write-Log "This may take 10-30 minutes depending on system size..."
Write-Log "Source: $windowsDrive"
Write-Log "Destination: $CapturePath"

try {
    $dismArgs = @(
        "/Capture-Image",
        "/ImageFile:`"$CapturePath`"",
        "/CaptureDir:$windowsDrive",
        "/Name:`"GoldISO Capture`"",
        "/Description:`"Captured $(Get-Date -Format 'yyyy-MM-dd HH:mm')`"",
        "/Compress:maximum"
    )
    
    Write-Log "Running: dism.exe $dismArgs"
    $dismProcess = Start-Process -FilePath "dism.exe" -ArgumentList $dismArgs -Wait -PassThru -NoNewWindow
    
    if ($dismProcess.ExitCode -ne 0) {
        Write-Log "DISM capture failed with exit code $($dismProcess.ExitCode)" "ERROR"
        exit 1
    }
    
    Write-Log "Image captured successfully" "SUCCESS"
    
    $wimSize = (Get-Item $CapturePath).Length
    Write-Log "Captured WIM size: $([math]::Round($wimSize / 1MB, 2)) MB"
}
catch {
    $errMsg = $_.Exception.Message
    Write-Log "Error during capture: $errMsg" "ERROR"
    exit 1
}

if ($MoveToUSB) {
    Write-Host "`n[Step 4] Moving to USB drive..." -ForegroundColor Yellow
    
    if (-not $USBDrive) {
        $USBDrive = Find-USBdrive
    }
    
    if (-not $USBDrive) {
        Write-Log "USB drive not found" "WARN"
        Write-Log "Capture remains at: $CapturePath"
    } else {
        $usbPath = "$USBDrive`:\GoldISO\Capture.wim"
        $usbDir = "$USBDrive`:\GoldISO"
        
        if (-not (Test-Path $usbDir)) {
            New-Item -ItemType Directory -Path $usbDir -Force | Out-Null
        }
        
        Write-Log "Moving WIM to USB: $usbPath"
        
        try {
            Move-Item $CapturePath $usbPath -Force
            Write-Log "WIM moved to USB successfully" "SUCCESS"
            $CapturePath = $usbPath
        }
        catch {
            $errMsg = $_.Exception.Message
            Write-Log "Failed to move to USB: $errMsg" "WARN"
            Write-Log "Capture remains at: $CapturePath"
        }
    }
}

$endTime = Get-Date
$duration = $endTime - $StartTime

Write-Host "============================================================" -ForegroundColor Green
Write-Host "  CAPTURE COMPLETE                                            " -ForegroundColor Green
Write-Host "============================================================" -ForegroundColor Green
Write-Host "Source:        Disk $TargetDisk ($windowsDrive)" -ForegroundColor White
Write-Host "Destination:   $CapturePath" -ForegroundColor White
Write-Host "Duration:      $([math]::Round($duration.TotalMinutes, 2)) minutes" -ForegroundColor White
Write-Host "============================================================" -ForegroundColor Green

$CapturePath