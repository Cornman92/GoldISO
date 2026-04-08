#Requires -Version 5.1
#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Applies a captured Windows image to a disk.
.DESCRIPTION
    Applies a WIM image to a target disk, configures boot, and handles
    post-installation setup. Designed to run in WinPE.
.PARAMETER ImagePath
    Path to the WIM file to apply. Default: Auto-detect from USB
.PARAMETER TargetDisk
    Disk number to apply image to. Default: 2
.PARAMETER ImageIndex
    Index of image in WIM to apply. Default: 1
.PARAMETER BootMode
    Boot mode (UEFI or BIOS). Default: Auto-detect
.EXAMPLE
    .\Apply-Image.ps1 -ImagePath "D:\GoldISO\Capture.wim"
    Applies the captured image to Disk 2
.EXAMPLE
    .\Apply-Image.ps1 -ImagePath "E:\Custom.wim" -TargetDisk 0
    Applies custom image to Disk 0
#>
[CmdletBinding()]
param(
    [string]$ImagePath = "",
    [int]$TargetDisk = 2,
    [int]$ImageIndex = 1,
    [ValidateSet("UEFI", "BIOS", "Auto")][string]$BootMode = "Auto",
    [string]$UnattendPath = "I:\GoldISO\autounattend.xml"
)

# Script Configuration
$ErrorActionPreference = "Stop"
$StartTime = Get-Date

function Write-Log {
    param([string]$Message, [ValidateSet("INFO","WARN","ERROR","SUCCESS")][string]$Level = "INFO")
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $colorMap = @{ INFO = "White"; WARN = "Yellow"; ERROR = "Red"; SUCCESS = "Green" }
    Write-Host "[$timestamp] [$Level] $Message" -ForegroundColor $colorMap[$Level]
}

function Find-ImagePath {
    # Try to find capture.wim on portable drive (I: first)
    $searchPaths = @(
        "I:\GoldISO\Capture.wim",
        "D:\GoldISO\Capture.wim",
        "E:\GoldISO\Capture.wim",
        "F:\GoldISO\Capture.wim",
        "G:\GoldISO\Capture.wim",
        "H:\GoldISO\Capture.wim",
        "J:\GoldISO\Capture.wim",
        "K:\GoldISO\Capture.wim"
    )
    
    foreach ($path in $searchPaths) {
        if (Test-Path $path) {
            Write-Log "Found image at: $path" "SUCCESS"
            return $path
        }
    }
    
    return $null
}

function Find-UnattendPath {
    # Look for autounattend.xml
    $searchPaths = @(
        "I:\GoldISO\autounattend.xml",
        "I:\GoldISO\Config\autounattend.xml",
        "D:\GoldISO\autounattend.xml",
        "E:\GoldISO\autounattend.xml"
    )
    
    foreach ($path in $searchPaths) {
        if (Test-Path $path) {
            Write-Log "Found unattend.xml at: $path" "SUCCESS"
            return $path
        }
    }
    
    return $null
}

function Get-BootMode {
    param([string]$Mode)
    
    if ($Mode -eq "Auto") {
        # Detect boot mode
        if (Test-Path "HKLM:\SYSTEM\CurrentControlSet\Control\SecureBoot\State") {
            return "UEFI"
        }
        # Check for EFI system partition
        $efiPart = Get-Partition | Where-Object { $_.GptType -eq "{c12a7328-f81f-11d2-ba4b-00a0c93ec93b}" }
        if ($efiPart) {
            return "UEFI"
        }
        return "BIOS"
    }
    return $Mode
}

function Clear-DiskAndCreatePartitions {
    param(
        [int]$DiskNumber,
        [string]$BootMode
    )
    
    Write-Log "Preparing Disk $DiskNumber for $BootMode boot..."
    
    try {
        # Clear the disk
        Clear-Disk -Number $DiskNumber -RemoveData -RemoveOEM -Confirm:$false -ErrorAction Stop
        Write-Log "Disk $DiskNumber cleared" "SUCCESS"
        
        if ($BootMode -eq "UEFI") {
            # UEFI: EFI + MSR + Windows + Recovery
            
            # Create EFI System Partition (100MB)
            $efiPart = New-Partition -DiskNumber $DiskNumber -Size 100MB -GptType "{c12a7328-f81f-11d2-ba4b-00a0c93ec93b}" -ErrorAction Stop
            Format-Volume -Partition $efiPart -FileSystem FAT32 -NewFileSystemLabel "System" -Confirm:$false | Out-Null
            Write-Log "Created EFI System Partition" "SUCCESS"
            
            # Create MSR (16MB) - variable intentionally unused but needed for partition creation
            $null = New-Partition -DiskNumber $DiskNumber -Size 16MB -GptType "{e3c9e316-0b5c-4db8-817d-f92df00215ae}" -ErrorAction Stop
            Write-Log "Created MSR partition" "SUCCESS"
            
            # Create Windows partition (uses rest of disk minus recovery)
            $diskSize = (Get-Disk -Number $DiskNumber).Size
            $recoverySize = 15GB
            $windowsSize = $diskSize - 100MB - 16MB - $recoverySize - 1GB  # 1GB buffer
            
            $windowsPart = New-Partition -DiskNumber $DiskNumber -Size $windowsSize -ErrorAction Stop
            Format-Volume -Partition $windowsPart -FileSystem NTFS -NewFileSystemLabel "Windows" -Confirm:$false | Out-Null
            Write-Log "Created Windows partition ($([math]::Round($windowsSize / 1GB, 2)) GB)" "SUCCESS"
            
            # Create Recovery partition
            $recoveryPart = New-Partition -DiskNumber $DiskNumber -GptType "{de94bba4-06d1-4d40-a16a-bfd50179d6ac}" -UseMaximumSize -ErrorAction Stop
            Format-Volume -Partition $recoveryPart -FileSystem NTFS -NewFileSystemLabel "Recovery" -Confirm:$false | Out-Null
            Write-Log "Created Recovery partition" "SUCCESS"
            
            return @{
                Windows = $windowsPart
                EFI = $efiPart
                Recovery = $recoveryPart
            }
        }
        else {
            # BIOS: System Reserved + Windows
            
            # Create System Reserved (350MB)
            $systemPart = New-Partition -DiskNumber $DiskNumber -Size 350MB -IsActive -ErrorAction Stop
            Format-Volume -Partition $systemPart -FileSystem NTFS -NewFileSystemLabel "System Reserved" -Confirm:$false | Out-Null
            Write-Log "Created System Reserved partition" "SUCCESS"
            
            # Create Windows partition (rest of disk)
            $windowsPart = New-Partition -DiskNumber $DiskNumber -UseMaximumSize -ErrorAction Stop
            Format-Volume -Partition $windowsPart -FileSystem NTFS -NewFileSystemLabel "Windows" -Confirm:$false | Out-Null
            Write-Log "Created Windows partition" "SUCCESS"
            
            return @{
                Windows = $windowsPart
                System = $systemPart
            }
        }
    }
    catch {
        Write-Log "Failed to create partitions: $_" "ERROR"
        return $null
    }
}

# Main Execution
Write-Host "═══════════════════════════════════════════════════════════════" -ForegroundColor Cyan
Write-Host "  WinPE Image Apply Tool                                       " -ForegroundColor Cyan
Write-Host "═══════════════════════════════════════════════════════════════" -ForegroundColor Cyan
Write-Host ""

# Check if we're in WinPE
$isWinPE = Test-Path "X:\Windows\System32\WinPE.exe" -ErrorAction SilentlyContinue
if (-not $isWinPE) {
    $isWinPE = (Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion" -Name "EditionID" -ErrorAction SilentlyContinue).EditionID -eq "WindowsPE"
}

if ($isWinPE) {
    Write-Log "Running in Windows PE environment" "SUCCESS"
} else {
    Write-Log "WARNING: Not in Windows PE - some operations may be limited" "WARN"
}

# Step 1: Find image path if not specified
Write-Host "`n[Step 1] Locating WIM image..." -ForegroundColor Yellow

if (-not $ImagePath) {
    $ImagePath = Find-ImagePath
}

if (-not $ImagePath -or -not (Test-Path $ImagePath)) {
    Write-Log "WIM image not found" "ERROR"
    Write-Log "Please specify -ImagePath parameter" "ERROR"
    exit 1
}

Write-Log "Found image: $ImagePath" "SUCCESS"

# Find unattend.xml if not specified or doesn't exist
if (-not (Test-Path $UnattendPath)) {
    $foundUnattend = Find-UnattendPath
    if ($foundUnattend) {
        $UnattendPath = $foundUnattend
    }
}

# Get image info (logged for debugging)
Write-Log "Reading image information..."
& dism.exe /Get-ImageInfo /ImageFile:$ImagePath 2>&1 | Out-String | Write-Verbose
Write-Log "Image info retrieved"

# Step 2: Prepare target disk
Write-Host "`n[Step 2] Preparing target disk..." -ForegroundColor Yellow

# Detect boot mode
$detectedBootMode = Get-BootMode -Mode $BootMode
Write-Log "Boot mode: $detectedBootMode"

# Get target disk
$targetDiskObj = Get-Disk -Number $TargetDisk -ErrorAction SilentlyContinue
if (-not $targetDiskObj) {
    Write-Log "Target disk $TargetDisk not found" "ERROR"
    exit 1
}

Write-Log "Target disk: $($targetDiskObj.FriendlyName) ($([math]::Round($targetDiskObj.Size / 1GB, 2)) GB)"

# Create partitions
$partitions = Clear-DiskAndCreatePartitions -DiskNumber $TargetDisk -BootMode $detectedBootMode
if (-not $partitions) {
    Write-Log "Failed to prepare disk" "ERROR"
    exit 1
}

$windowsDrive = "$($partitions.Windows.DriveLetter):\"
Write-Log "Windows will be applied to: $windowsDrive"

# Step 3: Apply the image
Write-Host "`n[Step 3] Applying image..." -ForegroundColor Yellow
Write-Log "This may take 15-45 minutes depending on image size..."

try {
    $dismArgs = @(
        "/Apply-Image",
        "/ImageFile:`"$ImagePath`"",
        "/Index:$ImageIndex",
        "/ApplyDir:$windowsDrive"
    )
    
    Write-Log "Running: dism.exe $dismArgs"
    $dismProcess = Start-Process -FilePath "dism.exe" -ArgumentList $dismArgs -Wait -PassThru -NoNewWindow
    
    if ($dismProcess.ExitCode -ne 0) {
        Write-Log "DISM apply failed with exit code $($dismProcess.ExitCode)" "ERROR"
        exit 1
    }
    
    Write-Log "Image applied successfully" "SUCCESS"
    
    # Step 4: Copy unattend.xml
    Write-Host "`n[Step 4] Copying unattend.xml..." -ForegroundColor Yellow
    
    $unattendDest = "$windowsDrive\Windows\Panther\unattend.xml"
    $unattendDir = Split-Path $unattendDest -Parent
    
    if (Test-Path $unattendDir) {
        if (Test-Path $UnattendPath) {
            Copy-Item -Path $UnattendPath -Destination $unattendDest -Force
            Write-Log "unattend.xml copied to: $unattendDest" "SUCCESS"
        } else {
            Write-Log "unattend.xml not found at: $UnattendPath" "WARN"
        }
    } else {
        New-Item -ItemType Directory -Path $unattendDir -Force | Out-Null
        if (Test-Path $UnattendPath) {
            Copy-Item -Path $UnattendPath -Destination $unattendDest -Force
            Write-Log "unattend.xml copied to: $unattendDest" "SUCCESS"
        }
    }
}
catch {
    Write-Log "Error applying image: $_" "ERROR"
    exit 1
}

# Step 4: Configure boot
Write-Host "`n[Step 4] Configuring boot..." -ForegroundColor Yellow

try {
    if ($detectedBootMode -eq "UEFI") {
        $efiDrive = "$($partitions.EFI.DriveLetter):\"
        
        # Use bcdboot to configure boot
        $bcdbootArgs = @(
            "$windowsDrive\Windows",
            "/s", $efiDrive,
            "/f", "UEFI"
        )
        
        Write-Log "Running: bcdboot.exe $bcdbootArgs"
        $bcdbootProcess = Start-Process -FilePath "bcdboot.exe" -ArgumentList $bcdbootArgs -Wait -PassThru -NoNewWindow
        
        if ($bcdbootProcess.ExitCode -ne 0) {
            Write-Log "BCDBoot failed with exit code $($bcdbootProcess.ExitCode)" "WARN"
        } else {
            Write-Log "UEFI boot configured successfully" "SUCCESS"
        }
        
        # Hide EFI partition
        Remove-PartitionAccessPath -DiskNumber $TargetDisk -PartitionNumber $partitions.EFI.PartitionNumber -AccessPath $efiDrive -ErrorAction SilentlyContinue
    }
    else {
        $systemDrive = "$($partitions.System.DriveLetter):\"
        
        # Use bcdboot for BIOS
        $bcdbootArgs = @(
            "$windowsDrive\Windows",
            "/s", $systemDrive
        )
        
        Write-Log "Running: bcdboot.exe $bcdbootArgs"
        $bcdbootProcess = Start-Process -FilePath "bcdboot.exe" -ArgumentList $bcdbootArgs -Wait -PassThru -NoNewWindow
        
        if ($bcdbootProcess.ExitCode -ne 0) {
            Write-Log "BCDBoot failed with exit code $($bcdbootProcess.ExitCode)" "WARN"
        } else {
            Write-Log "BIOS boot configured successfully" "SUCCESS"
        }
    }
}
catch {
    Write-Log "Error configuring boot: $_" "WARN"
    Write-Log "Boot configuration may need manual repair" "WARN"
}

# Step 5: Set recovery partition (if exists)
if ($partitions.Recovery) {
    Write-Host "`n[Step 5] Configuring recovery partition..." -ForegroundColor Yellow
    
    try {
        $recoveryDrive = "$($partitions.Recovery.DriveLetter):\"
        
        # Copy WinRE if available
        $winRESource = "$windowsDrive\Windows\System32\Recovery\WinRE.wim"
        if (Test-Path $winRESource) {
            Copy-Item $winRESource "$recoveryDrive\WinRE.wim" -Force
            Write-Log "WinRE copied to recovery partition" "SUCCESS"
        }
        
        # Reconfigure WinRE
        & reagentc.exe /setreimage /path "$recoveryDrive\WinRE.wim" /target $windowsDrive\Windows 2>&1 | Out-Null
        Write-Log "Recovery environment configured" "SUCCESS"
        
        # Hide recovery partition
        Remove-PartitionAccessPath -DiskNumber $TargetDisk -PartitionNumber $partitions.Recovery.PartitionNumber -AccessPath $recoveryDrive -ErrorAction SilentlyContinue
    }
    catch {
        Write-Log "Error configuring recovery: $_" "WARN"
    }
}

# Summary
$endTime = Get-Date
$duration = $endTime - $StartTime

Write-Host "`n═══════════════════════════════════════════════════════════════" -ForegroundColor Green
Write-Host "  IMAGE APPLY COMPLETE                                         " -ForegroundColor Green
Write-Host "═══════════════════════════════════════════════════════════════" -ForegroundColor Green
Write-Host "Source Image:  $ImagePath" -ForegroundColor White
Write-Host "Target Disk:   Disk $TargetDisk" -ForegroundColor White
Write-Host "Windows Drive: $windowsDrive" -ForegroundColor White
Write-Host "Boot Mode:     $detectedBootMode" -ForegroundColor White
Write-Host "Duration:      $([math]::Round($duration.TotalMinutes, 2)) minutes" -ForegroundColor White
Write-Host "═══════════════════════════════════════════════════════════════" -ForegroundColor Green
Write-Host "`nSystem ready to boot. Remove WinPE media and restart." -ForegroundColor Cyan
