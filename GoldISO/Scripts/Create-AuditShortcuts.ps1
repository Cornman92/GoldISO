#Requires -Version 5.1
<#
.SYNOPSIS
    Create desktop shortcut to continue installation from Audit mode
.DESCRIPTION
    Creates a desktop shortcut that runs Apply-Image.ps1 to apply captured WIM
    and continue Windows setup. Designed to be run from Audit mode desktop.
.EXAMPLE
    .\Create-AuditShortcuts.ps1
    Creates the desktop shortcut
#>
[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"

function Write-Log {
    param([string]$Message, [string]$Level = "INFO")
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $entry = "[$timestamp] [$Level] $Message"
    switch ($Level) {
        "ERROR" { Write-Host $entry -ForegroundColor Red }
        "SUCCESS" { Write-Host $entry -ForegroundColor Green }
        "WARNING" { Write-Host $entry -ForegroundColor Yellow }
        default { Write-Host $entry }
    }
}

Write-Log "=========================================="
Write-Log "Creating Audit Mode Desktop Shortcuts" "INFO"
Write-Log "=========================================="

$desktopPath = [Environment]::GetFolderPath("Desktop")
$scriptsPath = "C:\Scripts"

# Ensure Scripts directory exists
if (-not (Test-Path $scriptsPath)) {
    New-Item -ItemType Directory -Path $scriptsPath -Force | Out-Null
}

# Copy scripts to C:\Scripts
$sourceScripts = @(
    "Apply-Image.ps1",
    "Capture-Image.ps1",
    "Configure-SecondaryDrives.ps1"
)

foreach ($script in $sourceScripts) {
    $src = "I:\GoldISO\Scripts\$script"
    $dst = "$scriptsPath\$script"
    if (Test-Path $src) {
        Copy-Item -Path $src -Destination $dst -Force
        Write-Log "Copied: $script" "SUCCESS"
    }
}

# Create Apply Image shortcut
$shortcutName = "Continue Setup.lnk"
$shortcutPath = Join-Path $desktopPath $shortcutName

$shell = New-Object -ComObject WScript.Shell
$shortcut = $shell.CreateShortcut($shortcutPath)
$shortcut.TargetPath = "powershell.exe"
$shortcut.Arguments = "-NoProfile -ExecutionPolicy Bypass -File `"C:\Scripts\Apply-Image.ps1`""
$shortcut.WorkingDirectory = "C:\Scripts"
$shortcut.Description = "Apply captured Windows image and continue installation"
$shortcut.IconLocation = "%SystemRoot%\System32\shell32.dll,109"
$shortcut.Save()

Write-Log "Created desktop shortcut: $shortcutName" "SUCCESS"

# Create secondary drives shortcut
$secondaryShortcutName = "Configure Secondary Drives.lnk"
$secondaryShortcutPath = Join-Path $desktopPath $secondaryShortcutName

$shortcut2 = $shell.CreateShortcut($secondaryShortcutPath)
$shortcut2.TargetPath = "powershell.exe"
$shortcut2.Arguments = "-NoProfile -ExecutionPolicy Bypass -File `"C:\Scripts\Configure-SecondaryDrives.ps1`""
$shortcut2.WorkingDirectory = "C:\Scripts"
$shortcut2.Description = "Configure Disk 0 and Disk 1 partitions"
$shortcut2.IconLocation = "%SystemRoot%\System32\shell32.dll,8"
$shortcut2.Save()

Write-Log "Created desktop shortcut: $secondaryShortcutName" "SUCCESS"

# Create sysprep shortcut (for re-capturing)
$sysprepShortcutName = "Sysprep & Capture.lnk"
$sysprepShortcutPath = Join-Path $desktopPath $sysprepShortcutName

$shortcut3 = $shell.CreateShortcut($sysprepShortcutPath)
$shortcut3.TargetPath = "powershell.exe"
$shortcut3.Arguments = "-NoProfile -ExecutionPolicy Bypass -File `"C:\Scripts\Audit-Sysprep.ps1`""
$shortcut3.WorkingDirectory = "C:\Scripts"
$shortcut3.Description = "Run sysprep and prepare for image capture"
$shortcut3.IconLocation = "%SystemRoot%\System32\shell32.dll,17"
$shortcut3.Save()

Write-Log "Created desktop shortcut: $sysprepShortcutName" "SUCCESS"

Write-Log "=========================================="
Write-Log "Desktop shortcuts created" "SUCCESS"
Write-Log "=========================================="
Write-Log "Available shortcuts:" "INFO"
Write-Log "  - Continue Setup (apply captured image)" "INFO"
Write-Log "  - Configure Secondary Drives" "INFO"
Write-Log "  - Sysprep & Capture" "INFO"
Write-Log "=========================================="