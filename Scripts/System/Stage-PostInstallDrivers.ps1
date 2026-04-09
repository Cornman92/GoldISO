#Requires -Version 5.1
<#
.SYNOPSIS
    Stage post-install drivers for FirstLogon installation.
.DESCRIPTION
    Copies drivers that should be installed post-setup (not injected into WIM)
    to a staging location within the mounted image. These drivers will be
    installed via FirstLogonCommands using Install-PostInstallDrivers.ps1.
    
    Categories staged for post-install:
    - Sound, video and game controllers
    - Audio Processing Objects (APOs)
    - Software components
    - Extensions
    - Monitors
.PARAMETER DriverQueuePath
    Path to driver-queue.json (default: ..\Config\driver-queue.json)
.PARAMETER DriversSourcePath
    Path to source Drivers folder (default: ..\Drivers)
.PARAMETER MountPath
    Path to mounted WIM image (default: C:\Mount)
.PARAMETER StagePath
    Relative path within mounted image to stage drivers (default: Windows\Setup\Drivers\PostInstall)
.EXAMPLE
    .\Stage-PostInstallDrivers.ps1 -MountPath "C:\Mount"
.EXAMPLE
    .\Stage-PostInstallDrivers.ps1 -MountPath "C:\Mount" -DriversSourcePath "D:\Drivers"
#>
[CmdletBinding()]
param(
    [string]$DriverQueuePath = "",
    
    [string]$DriversSourcePath = "",
    
    [Parameter(Mandatory = $true)]
    [string]$MountPath,
    
    [string]$StagePath = "Windows\Setup\Drivers\PostInstall"
)

$ErrorActionPreference = "Stop"

if (Test-Path (Join-Path $PSScriptRoot "..\Modules\GoldISO-Common.psm1")) {
    Import-Module (Join-Path $PSScriptRoot "..\Modules\GoldISO-Common.psm1") -Force
}

# Resolve paths
$script:ProjectRoot = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent

if (-not $DriverQueuePath) {
    $DriverQueuePath = Join-Path $script:ProjectRoot "Config\driver-queue.json"
}

if (-not $DriversSourcePath) {
    $DriversSourcePath = Join-Path $script:ProjectRoot "Drivers"
}

$fullStagePath = Join-Path $MountPath $StagePath

function Write-Status {
    param(
        [string]$Message,
        [ValidateSet("Info", "Success", "Warning", "Error")]
        [string]$Level = "Info"
    )
    $colorMap = @{
        "Info"    = "White"
        "Success" = "Green"
        "Warning" = "Yellow"
        "Error"   = "Red"
    }
    Write-Host "[$Level] $Message" -ForegroundColor $colorMap[$Level]
}

# Validate paths
if (-not (Test-Path $DriverQueuePath)) {
    Write-Status "Driver queue not found: $DriverQueuePath" "Error"
    exit 1
}

if (-not (Test-Path $DriversSourcePath)) {
    Write-Status "Drivers source not found: $DriversSourcePath" "Error"
    exit 1
}

if (-not (Test-Path $MountPath)) {
    Write-Status "Mount path not found: $MountPath" "Error"
    exit 1
}

# Load driver queue
$driverQueue = Get-Content $DriverQueuePath -Raw | ConvertFrom-Json

# Get post-install driver categories
$postInstallCategories = $driverQueue.postInstall | Where-Object { $_.path -and $_.enabled -ne $false }

if (-not $postInstallCategories) {
    Write-Status "No post-install driver categories configured in driver-queue.json" "Warning"
    exit 0
}

Write-Status "==========================================" "Info"
Write-Status "Staging Post-Install Drivers" "Info"
Write-Status "==========================================" "Info"
Write-Status "Source: $DriversSourcePath" "Info"
Write-Status "Destination: $fullStagePath" "Info"
Write-Status "Categories: $($postInstallCategories.path -join ', ')" "Info"

# Create staging directory
if (-not (Test-Path $fullStagePath)) {
    New-Item -ItemType Directory -Path $fullStagePath -Force | Out-Null
    Write-Status "Created staging directory" "Success"
}

$totalStaged = 0
$totalFiles = 0

foreach ($category in $postInstallCategories) {
    $categoryName = $category.path
    $sourceCategoryPath = Join-Path $DriversSourcePath $categoryName
    
    if (-not (Test-Path $sourceCategoryPath)) {
        Write-Status "Category not found: $categoryName" "Warning"
        continue
    }
    
    $destCategoryPath = Join-Path $fullStagePath $categoryName
    
    Write-Status "Staging: $categoryName" "Info"
    Write-Status "  Source: $sourceCategoryPath" "Info"
    Write-Status "  Destination: $destCategoryPath" "Info"
    
    # Copy driver files (INF, SYS, CAT, DLL)
    $driverFiles = Get-ChildItem -Path $sourceCategoryPath -Recurse -File | Where-Object {
        $_.Extension -in @('.inf', '.sys', '.cat', '.dll', '.exe', '.cab')
    }
    
    foreach ($file in $driverFiles) {
        $relativePath = $file.FullName.Substring($sourceCategoryPath.Length).TrimStart('\')
        $destFilePath = Join-Path $destCategoryPath $relativePath
        $destFileDir = Split-Path $destFilePath -Parent
        
        if (-not (Test-Path $destFileDir)) {
            New-Item -ItemType Directory -Path $destFileDir -Force | Out-Null
        }
        
        Copy-Item -Path $file.FullName -Destination $destFilePath -Force
        $totalFiles++
    }
    
    $infCount = ($driverFiles | Where-Object { $_.Extension -eq '.inf' }).Count
    Write-Status "  Staged $infCount INF files ($totalFiles total files)" "Success"
    $totalStaged++
}

# Also copy the installation script
$installScriptSource = Join-Path $PSScriptRoot "Install-PostInstallDrivers.ps1"
$installScriptDest = Join-Path $fullStagePath ".."  # Parent of PostInstall

if (Test-Path $installScriptSource) {
    Copy-Item -Path $installScriptSource -Destination (Join-Path $installScriptDest "Install-PostInstallDrivers.ps1") -Force
    Write-Status "Copied installation script" "Success"
}

Write-Status "==========================================" "Info"
Write-Status "Staging Complete" "Success"
Write-Status "Categories staged: $totalStaged" "Success"
Write-Status "Total files copied: $totalFiles" "Success"
Write-Status "==========================================" "Info"

exit 0
