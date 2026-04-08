#Requires -Version 5.1
#Requires -RunAsAdministrator

<#
.SYNOPSIS
    Enforces application installation locations using Directory Junctions.
.DESCRIPTION
    Winget and some installers ignore the --location flag. This script moves
    installed applications to their intended category drives (e.g., Gaming -> C:\Gaming)
    and creates a junction from the original path (C:\Program Files\...) to the new one.
#>

$ErrorActionPreference = "Continue"

# Import common module
$commonModule = Join-Path $PSScriptRoot "Modules\GoldISO-Common.psm1"
if (Test-Path $commonModule) { Import-Module $commonModule -Force }

Write-Log "=========================================="
Write-Log "Application Location Enforcement Started"
Write-Log "=========================================="

# 1. Load Categories and Paths
$manifestPath = Join-Path $script:SystemDataDir "Config\build-manifest.json"
if (-not (Test-Path $manifestPath)) {
    Write-Log "Build manifest not found. Using defaults." "WARN"
    $config = @{
        drives = @{ gaming = "C"; apps = "F"; media = "H"; dev = "C" }
    }
} else {
    $config = Get-Content $manifestPath -Raw | ConvertFrom-Json
}

function Move-And-Junction {
    param(
        [string]$OriginalPath,
        [string]$TargetCategoryPath
    )

    if (-not (Test-Path $OriginalPath)) {
        Write-Log "  Source not found: $OriginalPath" "INFO"
        return
    }

    $appName = Split-Path $OriginalPath -Leaf
    $newPath = Join-Path $TargetCategoryPath $appName

    if (Test-Path $newPath) {
        Write-Log "  Target path already exists: $newPath" "WARN"
        return
    }

    if (-not (Test-Path $TargetCategoryPath)) {
        New-Item -ItemType Directory -Path $TargetCategoryPath -Force | Out-Null
    }

    Write-Log "  Moving $appName to $newPath ..." "INFO"
    try {
        # Stop potential processes
        $proc = Get-Process $appName -ErrorAction SilentlyContinue | Where-Object { $_.Path -like "$OriginalPath*" }
        if ($proc) { $proc | Stop-Process -Force }

        Move-Item -Path $OriginalPath -Destination $newPath -Force
        
        Write-Log "  Creating junction: $OriginalPath -> $newPath" "SUCCESS"
        cmd /c "mklink /J ""$OriginalPath"" ""$newPath"""
    }
    catch {
        Write-Log "  Failed to move $appName : $_" "ERROR"
    }
}

# Define mapping (Common Path -> Category)
$mappings = @(
    @{ Path = "C:\Program Files (x86)\Steam"; Drive = $config.drives.gaming; SubDir = "Gaming" }
    @{ Path = "C:\Program Files\Epic Games"; Drive = $config.drives.gaming; SubDir = "Gaming" }
    @{ Path = "C:\Program Files\GOG Galaxy"; Drive = $config.drives.gaming; SubDir = "Gaming" }
    @{ Path = "C:\Program Files\Microsoft VS Code"; Drive = $config.drives.apps; SubDir = "Dev" }
)

foreach ($map in $mappings) {
    if ($map.Drive) {
        $driveLetterVal = $map.Drive
        $targetBase = Join-Path "${driveLetterVal}:\" $map.SubDir
        Move-And-Junction -OriginalPath $map.Path -TargetCategoryPath $targetBase
    }
}

Write-Log "Application location enforcement complete." "SUCCESS"
