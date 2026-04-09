#Requires -Version 5.1

<#
.SYNOPSIS
    Invoke ISO Build with Offline Image Modification Mode
.DESCRIPTION
    Flexible ISO builder with optional offline WIM modification:
    - Standard mode: Quick ISO build without modifications
    - OfflineModify mode: Mount WIM, apply registry/drivers/AppX changes, then build ISO
    
    Offline modifications include:
    - Registry tweaks (telemetry, gaming, power settings)
    - Driver injection from specified path
    - AppX package removal with configurable keep list
    - Capability removal
    - Feature disablement
.PARAMETER SourceISO
    Path to source Windows ISO (default: ..\Win11-25H2x64v2.iso)
.PARAMETER OutputISO
    Path for output ISO (default: ..\GamerOS-Custom.iso)
.PARAMETER OfflineModify
    Enable offline image modification mode
.PARAMETER DriversPath
    Path to drivers for injection (default: ..\Drivers)
.PARAMETER RegistryTweaksPath
    Path to registry tweaks JSON (default: ..\Config\queued-registry.json)
.PARAMETER AppXKeepListPath
    Path to AppX keep list JSON (default: ..\Config\appx-keep-list.json)
.PARAMETER DebloatListPath
    Path to debloat list JSON (default: ..\Config\debloat-list.json)
.PARAMETER WorkingDir
    Working directory (default: C:\GoldISO_Work)
.PARAMETER MountDir
    WIM mount directory (default: C:\Mount)
.PARAMETER SkipCleanup
    Skip cleanup of working directory
.PARAMETER Compression
    WIM compression level: Fast, Maximum, None (default: Maximum)
.PARAMETER WIMIndex
    WIM index to modify (default: 6 for Windows 11 Pro)
.EXAMPLE
    .\Invoke-ISOBuild.ps1
.EXAMPLE
    .\Invoke-ISOBuild.ps1 -OfflineModify -DriversPath "C:\CustomDrivers"
.EXAMPLE
    .\Invoke-ISOBuild.ps1 -SourceISO "D:\ISOs\Win11.iso" -OutputISO "C:\Output\Custom.iso" -OfflineModify
#>
[CmdletBinding()]
param(
    [Parameter()]
    [string]$SourceISO = "",
    
    [Parameter()]
    [string]$OutputISO = "",
    
    [Parameter()]
    [switch]$OfflineModify,
    
    [Parameter()]
    [string]$DriversPath = "",
    
    [Parameter()]
    [string]$RegistryTweaksPath = "",
    
    [Parameter()]
    [string]$AppXKeepListPath = "",
    
    [Parameter()]
    [string]$DebloatListPath = "",
    
    [Parameter()]
    [string]$WorkingDir = "C:\GoldISO_Work",
    
    [Parameter()]
    [string]$MountDir = "C:\Mount",
    
    [Parameter()]
    [switch]$SkipCleanup,
    
    [Parameter()]
    [ValidateSet("Fast", "Maximum", "None")]
    [string]$Compression = "Maximum",
    
    [Parameter()]
    [int]$WIMIndex = 6
)

# Initialize
$ErrorActionPreference = "Stop"
$script:ProjectRoot = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
$script:LogFile = "$WorkingDir\iso-build.log"

if (Test-Path (Join-Path $PSScriptRoot "..\Modules\GoldISO-Common.psm1")) {
    Import-Module (Join-Path $PSScriptRoot "..\Modules\GoldISO-Common.psm1") -Force
}

# Default path resolution
if ([string]::IsNullOrEmpty($SourceISO)) {
    $SourceISO = Join-Path $script:ProjectRoot "Win11-25H2x64v2.iso"
}
if ([string]::IsNullOrEmpty($OutputISO)) {
    $OutputISO = Join-Path $script:ProjectRoot "GamerOS-Custom.iso"
}
if ([string]::IsNullOrEmpty($DriversPath)) {
    $DriversPath = Join-Path $script:ProjectRoot "Drivers"
}
if ([string]::IsNullOrEmpty($RegistryTweaksPath)) {
    $RegistryTweaksPath = Join-Path $script:ProjectRoot "Config\queued-registry.json"
}
if ([string]::IsNullOrEmpty($AppXKeepListPath)) {
    $AppXKeepListPath = Join-Path $script:ProjectRoot "Config\appx-keep-list.json"
}
if ([string]::IsNullOrEmpty($DebloatListPath)) {
    $DebloatListPath = Join-Path $script:ProjectRoot "Config\debloat-list.json"
}

# ==========================================
# LOGGING
# ==========================================
function Write-BuildLog {
    param(
        [string]$Message,
        [ValidateSet("INFO", "SUCCESS", "WARN", "ERROR", "STEP")]
        [string]$Level = "INFO"
    )
    
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logEntry = "[$timestamp] [$Level] $Message"
    
    # Ensure log directory exists
    $logDir = Split-Path $script:LogFile -Parent
    if ($logDir -and -not (Test-Path $logDir)) {
        New-Item -ItemType Directory -Path $logDir -Force | Out-Null
    }
    
    if (Test-Path (Split-Path $script:LogFile -Parent)) {
        Add-Content -Path $script:LogFile -Value $logEntry -ErrorAction SilentlyContinue
    }
    
    $colors = @{
        "INFO" = "White"
        "SUCCESS" = "Green"
        "WARN" = "Yellow"
        "ERROR" = "Red"
        "STEP" = "Cyan"
    }
    Write-Host $logEntry -ForegroundColor $colors[$Level]
}

# ==========================================
# PREREQUISITE CHECKS
# ==========================================
function Test-Administrator {
    $isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    if (-not $isAdmin) {
        Write-BuildLog "This script must be run as Administrator" "ERROR"
        exit 1
    }
    Write-BuildLog "Administrator privileges confirmed" "SUCCESS"
}

function Test-Prerequisites {
    Write-BuildLog "Checking prerequisites..." "STEP"
    
    # Check source ISO
    if (-not (Test-Path $SourceISO)) {
        Write-BuildLog "Source ISO not found: $SourceISO" "ERROR"
        exit 1
    }
    Write-BuildLog "Source ISO: $SourceISO" "SUCCESS"
    
    # Check oscdimg
    $script:OscdimgPath = Resolve-Oscdimg
    if (-not $script:OscdimgPath) {
        Write-BuildLog "oscdimg.exe not found. Install Windows ADK." "ERROR"
        exit 1
    }
    Write-BuildLog "oscdimg: $($script:OscdimgPath)" "SUCCESS"
    
    # Check DISM
    $dism = Get-Command dism -ErrorAction SilentlyContinue
    if (-not $dism) {
        Write-BuildLog "DISM not found" "ERROR"
        exit 1
    }
    Write-BuildLog "DISM: Available" "SUCCESS"
    
    # Validate offline modify paths if enabled
    if ($OfflineModify) {
        if (-not (Test-Path $RegistryTweaksPath)) {
            Write-BuildLog "Registry tweaks file not found: $RegistryTweaksPath" "WARN"
        }
        if (-not (Test-Path $DriversPath)) {
            Write-BuildLog "Drivers path not found: $DriversPath" "WARN"
        }
    }
}

function Resolve-Oscdimg {
    $inPath = Get-Command oscdimg -ErrorAction SilentlyContinue
    if ($inPath) { return $inPath.Source }
    
    $adkPaths = @(
        'C:\Program Files (x86)\Windows Kits\10\Assessment and Deployment Kit\Deployment Tools\amd64\Oscdimg\oscdimg.exe',
        'C:\Program Files\Windows Kits\10\Assessment and Deployment Kit\Deployment Tools\amd64\Oscdimg\oscdimg.exe'
    )
    foreach ($path in $adkPaths) {
        if (Test-Path $path) { return $path }
    }
    return $null
}

# ==========================================
# ISO OPERATIONS
# ==========================================
function Mount-SourceISO {
    param([string]$ISOPath)
    
    Write-BuildLog "Mounting source ISO..." "STEP"
    
    $existing = Get-DiskImage -ImagePath $ISOPath -ErrorAction SilentlyContinue
    if ($existing) {
        $letter = ($existing | Get-Volume).DriveLetter
        if ($letter) {
            Write-BuildLog "ISO already mounted at ${letter}:" "WARN"
            return $letter
        }
    }
    
    try {
        $image = Mount-DiskImage -ImagePath $ISOPath -PassThru -ErrorAction Stop
        $driveLetter = ($image | Get-Volume).DriveLetter
        Write-BuildLog "ISO mounted at ${driveLetter}:" "SUCCESS"
        return $driveLetter
    }
    catch {
        Write-BuildLog "Failed to mount ISO: $_" "ERROR"
        exit 1
    }
}

function Dismount-SourceISO {
    param([string]$ISOPath)
    
    try {
        $image = Get-DiskImage -ImagePath $ISOPath -ErrorAction SilentlyContinue
        if ($image) {
            Dismount-DiskImage -ImagePath $ISOPath | Out-Null
            Write-BuildLog "ISO dismounted" "SUCCESS"
        }
    }
    catch {
        Write-BuildLog "Could not dismount ISO: $_" "WARN"
    }
}

function Copy-ISOContents {
    param(
        [string]$SourceDrive,
        [string]$DestDir
    )
    
    Write-BuildLog "Copying ISO contents to working directory..." "STEP"
    
    if (Test-Path $DestDir) {
        Remove-Item -Path $DestDir -Recurse -Force -ErrorAction SilentlyContinue
    }
    New-Item -ItemType Directory -Path $DestDir -Force | Out-Null
    
    $source = "$SourceDrive`:\"
    robocopy $source $DestDir /E /R:3 /W:5 /NDL /NFL /NP | Out-Null
    
    $wimPath = Join-Path $DestDir "sources\install.wim"
    if (-not (Test-Path $wimPath)) {
        Write-BuildLog "install.wim not found after copy" "ERROR"
        exit 1
    }
    
    Write-BuildLog "ISO contents copied successfully" "SUCCESS"
}

# ==========================================
# WIM OPERATIONS
# ==========================================
function Mount-WIMImage {
    param(
        [string]$WIMPath,
        [string]$MountPath,
        [int]$Index
    )
    
    Write-BuildLog "Mounting WIM (Index: $Index)..." "STEP"
    
    # Cleanup existing mount
    if (Test-Path $MountPath) {
        Write-BuildLog "Cleaning existing mount point..." "WARN"
        Dismount-WindowsImage -Path $MountPath -Discard -ErrorAction SilentlyContinue | Out-Null
        Remove-Item -Path $MountPath -Recurse -Force -ErrorAction SilentlyContinue
    }
    
    New-Item -ItemType Directory -Path $MountPath -Force | Out-Null
    
    try {
        Mount-WindowsImage -ImagePath $WIMPath -Path $MountPath -Index $Index -ErrorAction Stop | Out-Null
        Write-BuildLog "WIM mounted successfully" "SUCCESS"
    }
    catch {
        Write-BuildLog "Failed to mount WIM: $_" "ERROR"
        exit 1
    }
}

function Dismount-WIMImage {
    param(
        [string]$MountPath,
        [switch]$Save
    )
    
    Write-BuildLog "Dismounting WIM..." "STEP"
    
    if (-not (Test-Path $MountPath)) {
        Write-BuildLog "Mount point does not exist" "WARN"
        return
    }
    
    try {
        if ($Save) {
            Dismount-WindowsImage -Path $MountPath -Save -ErrorAction Stop | Out-Null
            Write-BuildLog "WIM changes saved and dismounted" "SUCCESS"
        }
        else {
            Dismount-WindowsImage -Path $MountPath -Discard -ErrorAction SilentlyContinue | Out-Null
            Write-BuildLog "WIM dismounted (discarded)" "WARN"
        }
    }
    catch {
        Write-BuildLog "Error dismounting WIM: $_" "ERROR"
        # Emergency cleanup
        dism /Cleanup-Wim 2>&1 | Out-Null
    }
}

# ==========================================
# OFFLINE MODIFICATION FUNCTIONS
# ==========================================
function Invoke-RegistryTweaks {
    param(
        [string]$MountPath,
        [string]$TweaksPath
    )
    
    Write-BuildLog "Applying offline registry tweaks..." "STEP"
    
    if (-not (Test-Path $TweaksPath)) {
        Write-BuildLog "Registry tweaks file not found, skipping" "WARN"
        return
    }
    
    try {
        $tweaks = Get-Content $TweaksPath -Raw | ConvertFrom-Json
    }
    catch {
        Write-BuildLog "Failed to parse registry tweaks JSON: $_" "ERROR"
        return
    }
    
    $hives = @{
        "SYSTEM" = "$MountPath\Windows\System32\config\SYSTEM"
        "SOFTWARE" = "$MountPath\Windows\System32\config\SOFTWARE"
        "DEFAULT" = "$MountPath\Windows\System32\config\DEFAULT"
        "NTUSER" = "$MountPath\Users\Default\NTUSER.DAT"
    }
    
    $successCount = 0
    $failCount = 0
    
    foreach ($hiveName in $hives.Keys) {
        $hivePath = $hives[$hiveName]
        if (-not (Test-Path $hivePath)) {
            Write-BuildLog "  Hive not found: $hivePath" "WARN"
            continue
        }
        
        $mountPoint = "HKLM\OFFLINE_$hiveName"
        
        try {
            # Load hive
            $result = reg load $mountPoint $hivePath 2>&1
            if ($LASTEXITCODE -ne 0) {
                Write-BuildLog "  Failed to load hive $hiveName" "WARN"
                continue
            }
            
            # Apply tweaks for this hive
            $hiveTweaks = $tweaks | Where-Object { $_.Hive -eq $hiveName -or $_.Hive -eq "HKLM" }
            
            foreach ($tweak in $hiveTweaks) {
                try {
                    $regPath = "$mountPoint\$($tweak.Path)"
                    $regType = if ($tweak.Type) { $tweak.Type } else { "REG_DWORD" }
                    
                    reg add $regPath /v $tweak.Name /t $regType /d $tweak.Data /f 2>&1 | Out-Null
                    $successCount++
                }
                catch {
                    Write-BuildLog "    Failed to apply $($tweak.Name): $_" "WARN"
                    $failCount++
                }
            }
            
            # Unload hive
            reg unload $mountPoint 2>&1 | Out-Null
        }
        catch {
            Write-BuildLog "  Error processing hive $hiveName`: $_" "WARN"
            reg unload $mountPoint 2>$null | Out-Null
            $failCount++
        }
    }
    
    Write-BuildLog "Registry tweaks applied: $successCount successful, $failCount failed" "SUCCESS"
}

function Invoke-DriverInjection {
    param(
        [string]$MountPath,
        [string]$DriversDir
    )
    
    Write-BuildLog "Injecting drivers..." "STEP"
    
    if (-not (Test-Path $DriversDir)) {
        Write-BuildLog "Drivers directory not found: $DriversDir" "WARN"
        return
    }
    
    $infFiles = Get-ChildItem $DriversDir -Recurse -Filter "*.inf" -ErrorAction SilentlyContinue
    if ($infFiles.Count -eq 0) {
        Write-BuildLog "No .inf files found in drivers directory" "WARN"
        return
    }
    
    Write-BuildLog "Found $($infFiles.Count) driver INF files"
    
    try {
        $result = dism /Image:$MountPath /Add-Driver /Driver:$DriversDir /Recurse /ForceUnsigned 2>&1 | Out-String
        
        if ($result -match "(\d+) driver\(s\) installed") {
            $count = $matches[1]
            Write-BuildLog "$count drivers installed successfully" "SUCCESS"
        }
        else {
            Write-BuildLog "Driver injection completed" "SUCCESS"
        }
    }
    catch {
        Write-BuildLog "Driver injection failed: $_" "ERROR"
    }
}

function Invoke-AppXRemoval {
    param(
        [string]$MountPath,
        [string]$KeepListPath,
        [string]$DebloatListPath
    )
    
    Write-BuildLog "Processing AppX package removal..." "STEP"
    
    # Load keep list
    $keepList = @()
    if (Test-Path $KeepListPath) {
        try {
            $keepData = Get-Content $KeepListPath -Raw | ConvertFrom-Json
            $keepList = $keepData.keep
            Write-BuildLog "Loaded keep list with $($keepList.Count) packages"
        }
        catch {
            Write-BuildLog "Failed to load keep list" "WARN"
        }
    }
    
    # Load debloat list
    $removeList = @()
    if (Test-Path $DebloatListPath) {
        try {
            $debloatData = Get-Content $DebloatListPath -Raw | ConvertFrom-Json
            $removeList = $debloatData.packages | Where-Object { $_.risk -eq "safe" -or $_.IsSelected }
        }
        catch {
            Write-BuildLog "Failed to load debloat list" "WARN"
        }
    }
    
    # Get provisioned packages
    try {
        $provisioned = Get-AppxProvisionedPackage -Path $MountPath
    }
    catch {
        Write-BuildLog "Failed to get provisioned packages: $_" "ERROR"
        return
    }
    
    $removedCount = 0
    $skippedCount = 0
    
    foreach ($package in $provisioned) {
        $packageName = $package.DisplayName
        
        # Check if in keep list
        $shouldKeep = $keepList | Where-Object { $packageName -like "*$_*" }
        if ($shouldKeep) {
            Write-BuildLog "  Keeping: $packageName" "INFO"
            $skippedCount++
            continue
        }
        
        # Check if in remove list (if debloat list provided)
        if ($removeList.Count -gt 0) {
            $shouldRemove = $removeList | Where-Object { $packageName -eq $_.name }
            if (-not $shouldRemove) {
                continue
            }
        }
        
        # Remove package
        try {
            Write-BuildLog "  Removing: $packageName"
            Remove-AppxProvisionedPackage -Path $MountPath -PackageName $package.PackageName -ErrorAction Stop | Out-Null
            $removedCount++
        }
        catch {
            Write-BuildLog "    Failed to remove: $_" "WARN"
        }
    }
    
    Write-BuildLog "AppX processing complete: $removedCount removed, $skippedCount kept" "SUCCESS"
}

function Invoke-CapabilityRemoval {
    param([string]$MountPath)
    
    Write-BuildLog "Checking capabilities..." "STEP"
    
    try {
        $capabilities = Get-WindowsCapability -Path $MountPath
        
        $optionalCapabilities = $capabilities | Where-Object { 
            $_.State -eq "Installed" -and 
            $_.Name -match "(MediaPlayer|Paint|Notepad|Calculator|App.StepsRecorder)"
        }
        
        $removedCount = 0
        foreach ($cap in $optionalCapabilities) {
            try {
                Write-BuildLog "  Removing capability: $($cap.Name)"
                Remove-WindowsCapability -Path $MountPath -Name $cap.Name | Out-Null
                $removedCount++
            }
            catch {
                Write-BuildLog "    Failed: $_" "WARN"
            }
        }
        
        Write-BuildLog "Capabilities removed: $removedCount" "SUCCESS"
    }
    catch {
        Write-BuildLog "Capability processing failed: $_" "WARN"
    }
}

function Optimize-WIMImage {
    param([string]$MountPath)
    
    Write-BuildLog "Optimizing image..." "STEP"
    
    # Optimize AppX provisioned packages
    try {
        dism /Image:$MountPath /Optimize-AppProvisionedPackages 2>&1 | Out-Null
        Write-BuildLog "  AppX packages optimized" "SUCCESS"
    }
    catch {
        Write-BuildLog "  AppX optimization not available" "WARN"
    }
    
    # Component cleanup
    try {
        dism /Image:$MountPath /Cleanup-Image /StartComponentCleanup /ResetBase 2>&1 | Out-Null
        Write-BuildLog "  Component cleanup completed" "SUCCESS"
    }
    catch {
        Write-BuildLog "  Component cleanup had warnings" "WARN"
    }
}

# ==========================================
# ISO BUILD
# ==========================================
function Export-OptimizedWIM {
    param(
        [string]$SourceWIM,
        [string]$DestWIM,
        [int]$SourceIndex,
        [string]$Compression
    )
    
    Write-BuildLog "Exporting optimized WIM..." "STEP"
    
    if (Test-Path $DestWIM) {
        Remove-Item $DestWIM -Force
    }
    
    try {
        Export-WindowsImage -SourceImagePath $SourceWIM `
            -SourceIndex $SourceIndex `
            -DestinationImagePath $DestWIM `
            -Compression $Compression `
            -ErrorAction Stop | Out-Null
        
        $size = [math]::Round((Get-Item $DestWIM).Length / 1GB, 2)
        Write-BuildLog "WIM exported: $size GB" "SUCCESS"
    }
    catch {
        Write-BuildLog "WIM export failed: $_" "ERROR"
        throw
    }
}

function New-ISOImage {
    param(
        [string]$SourceDir,
        [string]$OutputPath
    )
    
    Write-BuildLog "Building final ISO..." "STEP"
    
    $oscdimg = $script:OscdimgPath
    
    $efiBoot = Join-Path $SourceDir "efi\microsoft\boot\efisys.bin"
    $etfsBoot = Join-Path $SourceDir "boot\etfsboot.com"
    
    if (-not (Test-Path $efiBoot)) {
        Write-BuildLog "EFI boot file not found: $efiBoot" "ERROR"
        return $false
    }
    
    if (-not (Test-Path $etfsBoot)) {
        Write-BuildLog "ETFS boot file not found: $etfsBoot" "ERROR"
        return $false
    }
    
    $label = "GAMEROS"
    
    & $oscdimg "-bootdata:2#p0,e,b$etfsBoot#pEF,e,b$efiBoot" -o -u2 -udfver102 "-l$label" $SourceDir $OutputPath 2>&1 | Out-Null
    
    if (Test-Path $OutputPath) {
        $size = [math]::Round((Get-Item $OutputPath).Length / 1GB, 2)
        Write-BuildLog "ISO created: $OutputPath ($size GB)" "SUCCESS"
        return $true
    }
    else {
        Write-BuildLog "ISO creation failed" "ERROR"
        return $false
    }
}

# ==========================================
# CLEANUP
# ==========================================
function Invoke-EmergencyCleanup {
    Write-BuildLog "Emergency cleanup running..." "WARN"
    
    $mounts = Get-WindowsImage -Mounted -ErrorAction SilentlyContinue
    foreach ($mount in $mounts) {
        try {
            Dismount-WindowsImage -Path $mount.MountPath -Discard -ErrorAction Stop | Out-Null
            Write-BuildLog "  Unmounted: $($mount.MountPath)" "SUCCESS"
        }
        catch {
            Write-BuildLog "  Failed to unmount: $($mount.MountPath)" "WARN"
        }
    }
    
    dism /Cleanup-Wim 2>&1 | Out-Null
}

function Invoke-Cleanup {
    param([string]$WorkingDir)
    
    if ($SkipCleanup) {
        Write-BuildLog "Cleanup skipped (SkipCleanup specified)" "WARN"
        return
    }
    
    Write-BuildLog "Cleaning up working directory..." "STEP"
    
    try {
        if (Test-Path $WorkingDir) {
            Remove-Item -Path $WorkingDir -Recurse -Force -ErrorAction SilentlyContinue
            Write-BuildLog "Working directory cleaned" "SUCCESS"
        }
    }
    catch {
        Write-BuildLog "Cleanup incomplete: $_" "WARN"
    }
}

# ==========================================
# MAIN EXECUTION
# ==========================================

try {
    Write-BuildLog "=========================================="
    Write-BuildLog "ISO Build - Invoke-ISOBuild.ps1"
    if ($OfflineModify) {
        Write-BuildLog "MODE: Offline Modification Enabled"
    }
    else {
        Write-BuildLog "MODE: Standard (No Modifications)"
    }
    Write-BuildLog "=========================================="
    
    # Validate environment
    Test-Administrator
    Test-Prerequisites
    
    # Setup working directory
    $isoContentDir = Join-Path $WorkingDir "ISOContent"
    $tempWIM = Join-Path $WorkingDir "temp-install.wim"
    $finalWIM = Join-Path $isoContentDir "sources\install.wim"
    
    # Mount and copy ISO
    $driveLetter = Mount-SourceISO -ISOPath $SourceISO
    Copy-ISOContents -SourceDrive $driveLetter -DestDir $isoContentDir
    Dismount-SourceISO -ISOPath $SourceISO
    
    $sourceWIM = Join-Path $isoContentDir "sources\install.wim"
    
    # Offline Modification Phase
    if ($OfflineModify) {
        Write-BuildLog "=========================================="
        Write-BuildLog "OFFLINE MODIFICATION PHASE"
        Write-BuildLog "=========================================="
        
        # Mount WIM
        Mount-WIMImage -WIMPath $sourceWIM -MountPath $MountDir -Index $WIMIndex
        
        # Apply modifications
        Invoke-RegistryTweaks -MountPath $MountDir -TweaksPath $RegistryTweaksPath
        Invoke-DriverInjection -MountPath $MountDir -DriversDir $DriversPath
        Invoke-AppXRemoval -MountPath $MountDir -KeepListPath $AppXKeepListPath -DebloatListPath $DebloatListPath
        Invoke-CapabilityRemoval -MountPath $MountDir
        Optimize-WIMImage -MountPath $MountDir
        
        # Save changes
        Dismount-WIMImage -MountPath $MountDir -Save
        
        # Export optimized WIM
        Export-OptimizedWIM -SourceWIM $sourceWIM -DestWIM $tempWIM -SourceIndex $WIMIndex -Compression $Compression
        
        # Replace original WIM
        if (Test-Path $tempWIM) {
            Remove-Item $sourceWIM -Force
            Move-Item $tempWIM $finalWIM
            Write-BuildLog "WIM replaced with optimized version" "SUCCESS"
        }
    }
    
    # Build ISO
    $success = New-ISOImage -SourceDir $isoContentDir -OutputPath $OutputISO
    
    # Cleanup
    Invoke-Cleanup -WorkingDir $WorkingDir
    
    # Final status
    Write-BuildLog "=========================================="
    if ($success) {
        Write-BuildLog "BUILD COMPLETED SUCCESSFULLY" "SUCCESS"
        Write-BuildLog "Output: $OutputISO" "SUCCESS"
    }
    else {
        Write-BuildLog "BUILD FAILED" "ERROR"
        exit 1
    }
}
catch {
    Write-BuildLog "CRITICAL ERROR: $_" "ERROR"
    Write-BuildLog "Stack: $($_.ScriptStackTrace)" "ERROR"
    Invoke-EmergencyCleanup
    exit 1
}
finally {
    # Final safety cleanup
    if (-not $SkipCleanup) {
        Invoke-Cleanup -WorkingDir $WorkingDir
    }
}
