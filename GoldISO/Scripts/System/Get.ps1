#Requires -Version 5.1

# Import common module
Import-Module (Join-Path $PSScriptRoot "Modules\GoldISO-Common.psm1") -Force

<#
.SYNOPSIS
    Get GoldISO components and configuration.

.DESCRIPTION
    Retrieves various GoldISO components including drivers, packages, settings,
    and build manifests. Can be run in CLI mode for automation.

.PARAMETER CLI
    Run in CLI mode without interactive prompts.

.PARAMETER Silent
    Suppress non-essential output.

.PARAMETER Verbose
    Enable verbose output.

.PARAMETER Sysprep
    Execute sysprep operations.

.PARAMETER LogPath
    Path to log file.

.PARAMETER User
    Target user context.

.PARAMETER NoRestartExplorer
    Do not restart Windows Explorer.

.PARAMETER CreateRestorePoint
    Create a system restore point before operations.

.PARAMETER RunAppsListGenerator
    Run the applications list generator.

.PARAMETER RunDefaults
    Run default configuration.

.PARAMETER RunDefaultsLite
    Run lite default configuration.

.PARAMETER RunSavedSettings
    Run saved settings.

.EXAMPLE
    .\Get.ps1 -CLI -RunDefaults

.EXAMPLE
    .\Get.ps1 -Sysprep -Verbose
#>
[CmdletBinding()]
param (
    [Parameter()]
    [switch]$CLI,

    [Parameter()]
    [switch]$Silent,

    [Parameter()]
    [switch]$Verbose,

    [Parameter()]
    [switch]$Sysprep,

    [Parameter()]
    [ValidateScript({
        if (-not $_) { return $true }
        $parent = Split-Path $_ -Parent
        if (-not $parent -or (Test-Path $parent)) { return $true }
        throw "Directory for LogPath does not exist: $parent"
    })]
    [string]$LogPath,

    [Parameter()]
    [string]$User,

    [Parameter()]
    [switch]$NoRestartExplorer,

    [Parameter()]
    [switch]$CreateRestorePoint,

    [Parameter()]
    [switch]$RunAppsListGenerator,

    [Parameter(ParameterSetName="RunDefaults")]
    [switch]$RunDefaults,

    [Parameter(ParameterSetName="RunDefaultsLite")]
    [switch]$RunDefaultsLite,

    [Parameter(ParameterSetName="RunSavedSettings")]
    [switch]$RunSavedSettings,

    [Parameter()]
    [ValidateScript({
        if (-not $_) { return $true }
        if (Test-Path $_) { return $true }
        throw "Config file not found: $_"
    })]
    [string]$Config,

    [Parameter()]
    [ValidateScript({
        if (-not $_) { return $true }
        if (Test-Path $_) { return $true }
        throw "Apps file not found: $_"
    })]
    [string]$Apps,

    [Parameter()]
    [ValidateSet("AllUsers", "CurrentUser")]
    [string]$AppRemovalTarget,

    [Parameter()]
    [switch]$RemoveApps,

    [Parameter()]
    [switch]$RemoveAppsCustom,

    [Parameter()]
    [switch]$RemoveGamingApps,

    [Parameter()]
    [switch]$RemoveCommApps,

    [Parameter()]
    [switch]$RemoveHPApps,

    [Parameter()]
    [switch]$RemoveW11Outlook,

    [Parameter()]
    [switch]$ForceRemoveEdge,

    [Parameter()]
    [switch]$DisableDVR,

    [Parameter()]
    [switch]$DisableGameBarIntegration,

    [Parameter()]
    [switch]$EnableWindowsSandbox,

    [Parameter()]
    [switch]$EnableWindowsSubsystemForLinux,

    [Parameter()]
    [switch]$DisableTelemetry,

    [Parameter()]
    [switch]$DisableSearchHistory,

    [Parameter()]
    [switch]$DisableFastStartup,

    [Parameter()]
    [switch]$DisableBitlockerAutoEncryption,

    [Parameter()]
    [switch]$DisableModernStandbyNetworking,

    [Parameter()]
    [switch]$DisableStorageSense,

    [Parameter()]
    [switch]$DisableUpdateASAP,

    [Parameter()]
    [switch]$PreventUpdateAutoReboot,

    [Parameter()]
    [switch]$DisableDeliveryOptimization,

    [Parameter()]
    [switch]$DisableBing,

    [Parameter()]
    [switch]$DisableStoreSearchSuggestions,

    [Parameter()]
    [switch]$DisableDesktopSpotlight,

    [Parameter()]
    [switch]$DisableLockscreenTips,

    [Parameter()]
    [switch]$DisableSuggestions,

    [Parameter()]
    [switch]$DisableLocationServices,

    [Parameter()]
    [switch]$DisableFindMyDevice,

    [Parameter()]
    [switch]$DisableEdgeAds,

    [Parameter()]
    [switch]$DisableBraveBloat,

    [Parameter()]
    [switch]$DisableSettings365Ads,

    [Parameter()]
    [switch]$DisableSettingsHome,

    [Parameter()]
    [switch]$ShowHiddenFolders,

    [Parameter()]
    [switch]$ShowKnownFileExt,

    [Parameter()]
    [switch]$HideDupliDrive,

    [Parameter()]
    [switch]$EnableDarkMode,

    [Parameter()]
    [switch]$DisableTransparency,

    [Parameter()]
    [switch]$DisableAnimations,

    [Parameter()]
    [switch]$TaskbarAlignLeft,

    [Parameter(ParameterSetName="CombineAlways")]
    [switch]$CombineTaskbarAlways,

    [Parameter(ParameterSetName="CombineWhenFull")]
    [switch]$CombineTaskbarWhenFull,

    [Parameter(ParameterSetName="CombineNever")]
    [switch]$CombineTaskbarNever,

    [Parameter(ParameterSetName="CombineMMAlways")]
    [switch]$CombineMMTaskbarAlways,

    [Parameter(ParameterSetName="CombineMMWhenFull")]
    [switch]$CombineMMTaskbarWhenFull,

    [Parameter(ParameterSetName="CombineMMNever")]
    [switch]$CombineMMTaskbarNever,

    [Parameter(ParameterSetName="MMModeAll")]
    [switch]$MMTaskbarModeAll,

    [Parameter(ParameterSetName="MMModeMainActive")]
    [switch]$MMTaskbarModeMainActive,

    [Parameter(ParameterSetName="MMModeActive")]
    [switch]$MMTaskbarModeActive,

    [Parameter(ParameterSetName="SearchHide")]
    [switch]$HideSearchTb,

    [Parameter(ParameterSetName="SearchIcon")]
    [switch]$ShowSearchIconTb,

    [Parameter(ParameterSetName="SearchLabel")]
    [switch]$ShowSearchLabelTb,

    [Parameter(ParameterSetName="SearchBox")]
    [switch]$ShowSearchBoxTb,

    [Parameter()]
    [switch]$HideTaskview,

    [Parameter()]
    [switch]$DisableStartRecommended,

    [Parameter()]
    [switch]$DisableStartAllApps,

    [Parameter()]
    [switch]$DisableStartPhoneLink,

    [Parameter()]
    [switch]$DisableCopilot,

    [Parameter()]
    [switch]$DisableRecall,

    [Parameter()]
    [switch]$DisableClickToDo,

    [Parameter()]
    [switch]$DisableAISvcAutoStart,

    [Parameter()]
    [switch]$DisablePaintAI,

    [Parameter()]
    [switch]$DisableNotepadAI,

    [Parameter()]
    [switch]$DisableEdgeAI,

    [Parameter()]
    [switch]$DisableSearchHighlights,

    [Parameter()]
    [switch]$DisableWidgets,

    [Parameter()]
    [switch]$HideChat,

    [Parameter()]
    [switch]$EnableEndTask,

    [Parameter()]
    [switch]$EnableLastActiveClick,

    [Parameter()]
    [switch]$ClearStart,

    [Parameter()]
    [ValidateScript({
        if (-not $_) { return $true }
        if (Test-Path $_) { return $true }
        throw "ReplaceStart file not found: $_"
    })]
    [string]$ReplaceStart,

    [Parameter()]
    [switch]$ClearStartAllUsers,

    [Parameter()]
    [ValidateScript({
        if (-not $_) { return $true }
        if (Test-Path $_) { return $true }
        throw "ReplaceStartAllUsers file not found: $_"
    })]
    [string]$ReplaceStartAllUsers,

    [Parameter()]
    [switch]$RevertContextMenu,

    [Parameter()]
    [switch]$DisableDragTray,

    [Parameter()]
    [switch]$DisableMouseAcceleration,

    [Parameter()]
    [switch]$DisableStickyKeys,

    [Parameter()]
    [switch]$DisableWindowSnapping,

    [Parameter()]
    [switch]$DisableSnapAssist,

    [Parameter()]
    [switch]$DisableSnapLayouts,

    [Parameter(ParameterSetName="AltTabHide")]
    [switch]$HideTabsInAltTab,

    [Parameter(ParameterSetName="AltTab3")]
    [switch]$Show3TabsInAltTab,

    [Parameter(ParameterSetName="AltTab5")]
    [switch]$Show5TabsInAltTab,

    [Parameter(ParameterSetName="AltTab20")]
    [switch]$Show20TabsInAltTab,

    [Parameter()]
    [switch]$HideHome,

    [Parameter()]
    [switch]$HideGallery,

    [Parameter(ParameterSetName="ExplorerHome")]
    [switch]$ExplorerToHome,

    [Parameter(ParameterSetName="ExplorerThisPC")]
    [switch]$ExplorerToThisPC,

    [Parameter(ParameterSetName="ExplorerDownloads")]
    [switch]$ExplorerToDownloads,

    [Parameter(ParameterSetName="ExplorerOneDrive")]
    [switch]$ExplorerToOneDrive,

    [Parameter()]
    [switch]$AddFoldersToThisPC,

    [Parameter()]
    [switch]$HideOnedrive,

    [Parameter()]
    [switch]$Hide3dObjects,

    [Parameter()]
    [switch]$HideMusic,

    [Parameter()]
    [switch]$HideIncludeInLibrary,

    [Parameter()]
    [switch]$HideGiveAccessTo,

    [Parameter()]
    [switch]$HideShare,

    [Parameter(ParameterSetName="DriveFirst")]
    [switch]$ShowDriveLettersFirst,

    [Parameter(ParameterSetName="DriveLast")]
    [switch]$ShowDriveLettersLast,

    [Parameter(ParameterSetName="DriveNetFirst")]
    [switch]$ShowNetworkDriveLettersFirst,

    [Parameter(ParameterSetName="DriveHide")]
    [switch]$HideDriveLetters
)

# Show error if current powershell environment does not have LanguageMode set to FullLanguage 
if ($ExecutionContext.SessionState.LanguageMode -ne "FullLanguage") {
   Write-Host "Error: Win11Debloat is unable to run on your system. PowerShell execution is restricted by security policies" -ForegroundColor Red
   Write-Output ""
   Write-Output "Press enter to exit..."
   Read-Host | Out-Null
   Exit
}

Clear-Host
Write-Output "-------------------------------------------------------------------------------------------"
Write-Output " Win11Debloat Script - Get"
Write-Output "-------------------------------------------------------------------------------------------"

Write-Output "> Downloading Win11Debloat..."

# Download latest version of Win11Debloat from GitHub as zip archive
try {
    $LatestReleaseUri = (Invoke-RestMethod https://api.github.com/repos/Raphire/Win11Debloat/releases/latest).zipball_url
    Invoke-RestMethod $LatestReleaseUri -OutFile "$env:TEMP/win11debloat.zip"
}
catch {
    Write-Host "Error: Unable to fetch latest release from GitHub. Please check your internet connection and try again." -ForegroundColor Red
    Write-Output ""
    Write-Output "Press enter to exit..."
    Read-Host | Out-Null
    Exit
}

Write-Output ""
Write-Output "> Cleaning up old Win11Debloat folder..."

# Remove old script folder if it exists, but keep config and log files
if (Test-Path "$env:TEMP/Win11Debloat") {
    Get-ChildItem -Path "$env:TEMP/Win11Debloat" -Exclude CustomAppsList,LastUsedSettings.json,Win11Debloat.log,Config,Logs | Remove-Item -Recurse -Force
}

$configDir = "$env:TEMP/Win11Debloat/Config"
$backupDir = "$env:TEMP/Win11Debloat/ConfigOld"

# Temporarily move existing config files if they exist to prevent them from being overwritten by the new script files, will be moved back after the new script is unpacked
if (Test-Path "$configDir") {
    New-Item -ItemType Directory -Path "$backupDir" -Force | Out-Null

    $filesToKeep = @(
        'CustomAppsList',
        'LastUsedSettings.json'
    )

    Get-ChildItem -Path "$configDir" -Recurse | Where-Object { $_.Name -in $filesToKeep } | Move-Item -Destination "$backupDir"

    Remove-Item "$configDir" -Recurse -Force
}

Write-Output ""
Write-Output "> Unpacking..."

# Unzip archive to Win11Debloat folder
Expand-Archive "$env:TEMP/win11debloat.zip" "$env:TEMP/Win11Debloat"

# Remove archive
Remove-Item "$env:TEMP/win11debloat.zip"

# Move files
Get-ChildItem -Path "$env:TEMP/Win11Debloat/Raphire-Win11Debloat-*" -Recurse | Move-Item -Destination "$env:TEMP/Win11Debloat"

# Add existing config files back to Config folder
if (Test-Path "$backupDir") {
    if (-not (Test-Path "$configDir")) {
        New-Item -ItemType Directory -Path "$configDir" -Force | Out-Null
    }

    Get-ChildItem -Path "$backupDir" -Recurse | Move-Item -Destination "$configDir"
    Remove-Item "$backupDir" -Recurse -Force
}

# Make list of arguments to pass on to the script
$arguments = $($PSBoundParameters.GetEnumerator() | ForEach-Object {
    if ($_.Value -eq $true) {
        "-$($_.Key)"
    } 
    else {
         "-$($_.Key) ""$($_.Value)"""
    }
})

Write-Output ""
Write-Output "> Running Win11Debloat..."

# Minimize the powershell window when no parameters are provided
if ($arguments.Count -eq 0) {
    $windowStyle = "Minimized"
}
else {
    $windowStyle = "Normal"
}

# Remove Powershell 7 modules from path to prevent module loading issues in the script
if ($PSVersionTable.PSVersion.Major -ge 7) {
    $NewPSModulePath = $env:PSModulePath -split ';' | Where-Object -FilterScript { $_ -like '*WindowsPowerShell*' }
    $env:PSModulePath = $NewPSModulePath -join ';'
}

# Run Win11Debloat script with the provided arguments
$debloatProcess = Start-Process powershell.exe -WindowStyle $windowStyle -PassThru -ArgumentList "-executionpolicy bypass -File $env:TEMP\Win11Debloat\Win11Debloat.ps1 $arguments" -Verb RunAs

# Wait for the process to finish before continuing
if ($null -ne $debloatProcess) {
    $debloatProcess.WaitForExit()
}

# Remove all remaining script files, except for CustomAppsList and LastUsedSettings.json files
if (Test-Path "$env:TEMP/Win11Debloat") {
    Write-Output ""
    Write-Output "> Cleaning up..."

    # Cleanup, remove Win11Debloat directory
    Get-ChildItem -Path "$env:TEMP/Win11Debloat" -Exclude CustomAppsList,LastUsedSettings.json,Win11Debloat.log,Win11Debloat-Run.log,Config,Logs | Remove-Item -Recurse -Force
}

Write-Output ""
