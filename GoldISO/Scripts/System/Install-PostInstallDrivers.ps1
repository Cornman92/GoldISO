#Requires -Version 5.1
#Requires -RunAsAdministrator

Import-Module (Join-Path $PSScriptRoot "Modules\GoldISO-Common.psm1") -Force

<#
.SYNOPSIS
    Install drivers during post-setup phase (FirstLogon).
.DESCRIPTION
    Installs drivers that should not be injected into WIM but instead
    installed after Windows setup completes. This includes:
    - Monitor sound/audio drivers
    - Sound, video and game controllers
    - Audio Processing Objects (APOs)
    - Software components
    - Extensions
    
    Uses pnputil to add drivers to the driver store and install them.
.PARAMETER DriverSourcePath
    Source path containing driver categories (default: USB drive or C:\Windows\Setup\Drivers\PostInstall)
.PARAMETER Categories
    Driver categories to install (default: all from driver-queue.json postInstall)
.PARAMETER LogPath
    Path for installation log
.EXAMPLE
    .\Install-PostInstallDrivers.ps1
.EXAMPLE
    .\Install-PostInstallDrivers.ps1 -DriverSourcePath "D:\Drivers" -Categories @("Sound, video and game controllers")
#>
[CmdletBinding()]
param(
    [string]$DriverSourcePath = "",
    
    [string[]]$Categories = @(
        "Sound, video and game controllers",
        "Audio Processing Objects (APOs)",
        "Software components", 
        "Extensions",
        "Monitors"
    ),
    
    [string]$LogPath = "$env:SystemDrive\`$WinREAgent\Logs\PostInstallDrivers.log"
)

$ErrorActionPreference = "Continue"

# Ensure logging directory exists
$logDir = Split-Path $LogPath -Parent
if (-not (Test-Path $logDir)) {
    New-Item -ItemType Directory -Path $logDir -Force | Out-Null
}

# Remove local Write-Log function - use centralized from module
# Function removed - using Write-GoldISOLog from GoldISO-Common module instead

# Find driver source
if (-not $DriverSourcePath) {
    # Check common USB drive letters
    $volumes = Get-Volume | Where-Object { 
        $_.DriveLetter -and $_.DriveType -eq 'Removable'
    }
    
    $usbDrives = $volumes | Where-Object { 
        Test-Path "$($_.DriveLetter):\Drivers" -ErrorAction SilentlyContinue
    }
    
    if ($usbDrives) {
        $DriverSourcePath = "$($usbDrives[0].DriveLetter):\Drivers"
        Write-Log "Found USB driver source: $DriverSourcePath"
    }
    else {
        # Check staged location
        $stagedPath = "C:\Windows\Setup\Drivers\PostInstall"
        if (Test-Path $stagedPath) {
            $DriverSourcePath = $stagedPath
            Write-Log "Using staged driver source: $DriverSourcePath"
        }
        else {
            Write-Log "No driver source found!" "ERROR"
            exit 1
        }
    }
}

Write-GoldISOLog -Message "=== Post-Install Driver Installation Started ===" -Level INFO
Write-GoldISOLog -Message "Source: $DriverSourcePath" -Level INFO
Write-GoldISOLog -Message "Categories: $($Categories -join ', ')" -Level INFO

$totalInstalled = 0
$totalFailed = 0

foreach ($category in $Categories) {
    $categoryPath = Join-Path $DriverSourcePath $category
    
    if (-not (Test-Path $categoryPath)) {
        Write-GoldISOLog -Message "Category not found: $category" -Level WARN
        continue
    }
    
    Write-GoldISOLog -Message "Processing category: $category" -Level INFO
    
    # Find all INF files in the category
    $infFiles = Get-ChildItem -Path $categoryPath -Filter "*.inf" -Recurse -ErrorAction SilentlyContinue
    
    if (-not $infFiles) {
        Write-GoldISOLog -Message "No INF files found in $category" -Level WARN
        continue
    }
    
    Write-GoldISOLog -Message "Found $($infFiles.Count) INF files in $category" -Level INFO
    
    foreach ($inf in $infFiles) {
        try {
            # Use pnputil to add and install driver
            Write-GoldISOLog -Message "Installing: $($inf.Name)" -Level INFO
            
            # pnputil /add-driver <inf> /install - adds to driver store AND installs
            $proc = Start-Process -FilePath "pnputil.exe" -ArgumentList "/add-driver `"$($inf.FullName)`" /install" -Wait -PassThru -WindowStyle Hidden
            
            if ($proc.ExitCode -eq 0) {
                Write-GoldISOLog -Message "Success: $($inf.Name)" -Level SUCCESS
                $totalInstalled++
            }
            else {
                # Try without /install flag (just add to store)
                $proc2 = Start-Process -FilePath "pnputil.exe" -ArgumentList "/add-driver `"$($inf.FullName)`"" -Wait -PassThru -WindowStyle Hidden
                if ($proc2.ExitCode -eq 0) {
                    Write-GoldISOLog -Message "Added to store (no install): $($inf.Name)" -Level SUCCESS
                    $totalInstalled++
                }
                else {
                    Write-GoldISOLog -Message "Failed with exit code $($proc2.ExitCode): $($inf.Name)" -Level ERROR
                    $totalFailed++
                }
            }
        }
        catch {
            Write-GoldISOLog -Message "Exception installing $($inf.Name): $_" -Level ERROR
            $totalFailed++
        }
    }
}

Write-GoldISOLog -Message "=== Installation Complete ===" -Level INFO
Write-GoldISOLog -Message "Total installed/added: $totalInstalled" -Level INFO
Write-GoldISOLog -Message "Total failed: $totalFailed" -Level INFO

# Trigger hardware rescan to pick up newly installed drivers
Write-GoldISOLog -Message "Triggering hardware rescan..." -Level INFO
Invoke-Command -ScriptBlock { 
    & pnputil /scan-devices 
} -ErrorAction SilentlyContinue

# Alias for backward compatibility
Set-Alias -Name Write-Log -Value Write-GoldISOLog -Scope Script

exit $totalFailed
