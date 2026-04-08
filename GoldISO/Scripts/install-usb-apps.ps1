#Requires -Version 5.1
#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Installs applications using winget from USB drive or online sources.
.DESCRIPTION
    Reads winget-packages.json and installs applications by category.
    Creates category folders (C:\Dev, C:\Gaming, etc.) and installs apps to appropriate locations.
    Falls back to online installation if USB source not available.
.PARAMETER ConfigPath
    Path to winget-packages.json configuration file.
.PARAMETER Categories
    Array of categories to install (default: all).
.PARAMETER SkipCategories
    Array of categories to skip.
.PARAMETER WhatIf
    Show what would be installed without actually installing.
.EXAMPLE
    .\install-usb-apps.ps1
    Install all apps from default config path
.EXAMPLE
    .\install-usb-apps.ps1 -Categories @("browsers", "utilities")
    Install only browsers and utilities
.EXAMPLE
    .\install-usb-apps.ps1 -WhatIf
    Preview what would be installed
#>
[CmdletBinding()]
param(
    [string]$ConfigPath = (Join-Path $PSScriptRoot "..\Config\winget-packages.json"),
    [string[]]$Categories = @(),
    [string[]]$SkipCategories = @(),
    [switch]$WhatIf
)

$ErrorActionPreference = "Continue"
$logFile = "C:\ProgramData\Winhance\Unattend\Logs\usb-apps-install.log"

function Write-Log {
    param(
        [string]$Message,
        [ValidateSet("INFO","SUCCESS","WARNING","ERROR","SKIP")][string]$Level = "INFO"
    )
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $entry = "[$timestamp] [$Level] $Message"

    $color = switch ($Level) {
        "ERROR" { "Red" }
        "WARNING" { "Yellow" }
        "SUCCESS" { "Green" }
        "SKIP" { "Cyan" }
        default { "White" }
    }
    Write-Host $entry -ForegroundColor $color

    $logDir = Split-Path $logFile -Parent
    if (-not (Test-Path $logDir)) {
        New-Item -ItemType Directory -Path $logDir -Force | Out-Null
    }
    Add-Content -Path $logFile -Value $entry -Encoding UTF8
}

function Test-WingetAvailable {
    try {
        $winget = Get-Command winget -ErrorAction SilentlyContinue
        if (-not $winget) {
            # Try to find winget in common locations
            $wingetPaths = @(
                "$env:LOCALAPPDATA\Microsoft\WindowsApps\winget.exe",
                "C:\Program Files\WindowsApps\Microsoft.DesktopAppInstaller*_x64__8wekyb3d8bbwe\winget.exe"
            )
            foreach ($path in $wingetPaths) {
                $resolved = Resolve-Path $path -ErrorAction SilentlyContinue
                if ($resolved) { return $resolved.Path }
            }
            return $null
        }
        return $winget.Source
    }
    catch {
        return $null
    }
}

function Install-AppWithWinget {
    param(
        [string]$PackageId,
        [string]$InstallLocation = $null,
        [switch]$WhatIf
    )

    if ($WhatIf) {
        Write-Log "[WhatIf] Would install: $PackageId" "SKIP"
        return $true
    }

    try {
        $wingetArgs = @("install", "--id", $PackageId, "--accept-package-agreements", "--accept-source-agreements", "--silent")

        if ($InstallLocation) {
            # Ensure install location exists
            if (-not (Test-Path $InstallLocation)) {
                New-Item -ItemType Directory -Path $InstallLocation -Force | Out-Null
            }
            $wingetArgs += "--location"
            $wingetArgs += $InstallLocation
        }

        Write-Log "Installing $PackageId..." "INFO"
        $process = Start-Process -FilePath "winget" -ArgumentList $wingetArgs -Wait -PassThru -WindowStyle Hidden -ErrorAction Stop

        if ($process.ExitCode -eq 0) {
            Write-Log "Successfully installed: $PackageId" "SUCCESS"
            return $true
        }
        elseif ($process.ExitCode -eq -1978335189) {
            # Already installed
            Write-Log "Already installed: $PackageId" "SUCCESS"
            return $true
        }
        else {
            Write-Log "Installation failed for $PackageId (exit code: $($process.ExitCode))" "WARNING"
            return $false
        }
    }
    catch {
        Write-Log "Error installing $PackageId`: $_" "ERROR"
        return $false
    }
}

function New-CategoryFolders {
    param([hashtable]$CategoryMap)

    foreach ($category in $CategoryMap.Keys) {
        $installPath = $CategoryMap[$category]
        if ($installPath -and -not (Test-Path $installPath)) {
            try {
                New-Item -ItemType Directory -Path $installPath -Force | Out-Null
                Write-Log "Created folder: $installPath" "SUCCESS"
            }
            catch {
                Write-Log "Could not create folder $installPath`: $_" "WARNING"
            }
        }
    }
}

# Main execution
Write-Log "=========================================="
Write-Log "Application Installation Script Started"
Write-Log "Config: $ConfigPath"
Write-Log "WhatIf: $WhatIf"
Write-Log "=========================================="

# Check admin
$isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    Write-Log "ERROR: This script must be run as Administrator" "ERROR"
    exit 1
}

# Check winget availability
$wingetPath = Test-WingetAvailable
if (-not $wingetPath) {
    Write-Log "ERROR: winget not found. Please install App Installer from Microsoft Store." "ERROR"
    exit 1
}
Write-Log "Found winget at: $wingetPath" "SUCCESS"

# Load configuration
if (-not (Test-Path $ConfigPath)) {
    Write-Log "ERROR: Configuration file not found: $ConfigPath" "ERROR"
    exit 1
}

try {
    $config = Get-Content $ConfigPath -Raw | ConvertFrom-Json -ErrorAction Stop
    Write-Log "Loaded configuration: $($config.Description)" "SUCCESS"
}
catch {
    Write-Log "ERROR: Failed to parse configuration: $_" "ERROR"
    exit 1
}

# Build category map
$categoryMap = @{}
foreach ($cat in $config.Categories) {
    $categoryMap[$cat.Name] = $cat.InstallPath
}

# Create category folders
Write-Log "Creating category folders..."
New-CategoryFolders -CategoryMap $categoryMap

# Filter packages
$packagesToInstall = @()
$sourcePackages = $config.Sources[0].Packages

foreach ($pkg in $sourcePackages) {
    $category = $pkg.Category

    # Skip if category is in SkipCategories
    if ($SkipCategories -contains $category) {
        Write-Log "Skipping (excluded category ${category}): $($pkg.PackageIdentifier)" "SKIP"
        continue
    }

    # If Categories specified, only include matching
    if ($Categories.Count -gt 0 -and $Categories -notcontains $category) {
        continue
    }

    $packagesToInstall += $pkg
}

Write-Log "Found $($packagesToInstall.Count) packages to install"

# Install packages
$successCount = 0
$failCount = 0
$skipCount = 0

foreach ($pkg in $packagesToInstall) {
    $installPath = $categoryMap[$pkg.Category]

    Write-Log "[$($pkg.Category)] $($pkg.PackageIdentifier) - $($pkg.Notes)" "INFO"

    $result = Install-AppWithWinget -PackageId $pkg.PackageIdentifier -InstallLocation $installPath -WhatIf:$WhatIf

    if ($result) {
        $successCount++
    }
    else {
        $failCount++
    }

    # Small delay between installs
    Start-Sleep -Milliseconds 500
}

# Summary
Write-Log "=========================================="
Write-Log "Installation Complete" "SUCCESS"
Write-Log "Success: $successCount" "SUCCESS"
Write-Log "Failed: $failCount" $(if ($failCount -gt 0) { "WARNING" } else { "SUCCESS" })
Write-Log "Skipped: $skipCount" "SKIP"
Write-Log "=========================================="

if ($failCount -gt 0) {
    exit 1
}
exit 0
