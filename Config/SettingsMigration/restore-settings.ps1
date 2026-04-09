#Requires -Version 5.1
<#
.SYNOPSIS
    Restore system and application settings from GoldISO migration package.

.DESCRIPTION
    Automatically restores Windows registry settings, application configurations,
    and user data exported by Export-Settings.ps1 during unattended installation.
    Called from autounattend.xml FirstLogonCommands.

.PARAMETER SettingsPath
    Path to the settings migration package. Default: C:\SettingsMigration

.PARAMETER LogPath
    Path for restore log file. Default: C:\SettingsMigration\restore.log

.EXAMPLE
    .\restore-settings.ps1

.EXAMPLE
    .\restore-settings.ps1 -SettingsPath "D:\Backup\Settings-Migration"
#>
[CmdletBinding()]
param(
    [string]$SettingsPath = "C:\SettingsMigration",
    [string]$LogPath = "C:\SettingsMigration\restore.log"
)

# Configuration & Setup
$ErrorActionPreference = "Continue"
$script:StartTime = Get-Date
$script:RestoredItems = [System.Collections.Generic.List[PSCustomObject]]::new()
$script:Warnings = [System.Collections.Generic.List[string]]::new()
$script:Errors = [System.Collections.Generic.List[string]]::new()

# Create log directory
$logDir = Split-Path $LogPath -Parent
if (-not (Test-Path $logDir)) { New-Item -ItemType Directory -Path $logDir -Force | Out-Null }

function Write-Log {
    param([string]$Message, [ValidateSet("INFO","WARN","ERROR","SUCCESS","SKIP")][string]$Level = "INFO")
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $entry = "[$timestamp] [$Level] $Message"
    Write-Host $entry -ForegroundColor $(switch($Level){ "ERROR"{"Red"} "WARN"{"Yellow"} "SUCCESS"{"Green"} "SKIP"{"DarkYellow"} default{"White"}})
    Add-Content -Path $LogPath -Value $entry -ErrorAction SilentlyContinue
    switch ($Level) { "WARN" { $script:Warnings.Add($Message) } "ERROR" { $script:Errors.Add($Message) } }
}

$script:ProgressCurrent = 0
$script:ProgressTotal = 5
function Write-ProgressPhase {
    param([string]$PhaseName)
    $script:ProgressCurrent++
    $percent = [math]::Round(($script:ProgressCurrent / $script:ProgressTotal) * 100)
    Write-Progress -Activity "Restoring Settings" -Status $PhaseName -PercentComplete $percent
    Write-Log "Phase $script:ProgressCurrent/$script:ProgressTotal`: $PhaseName"
}

function Test-SettingsPackage {
    Write-Log "Validating settings package..."
    if (-not (Test-Path $SettingsPath)) { Write-Log "Settings path not found: $SettingsPath" "ERROR"; return $false }
    
    $manifestPath = Join-Path $SettingsPath "manifest.json"
    if (-not (Test-Path $manifestPath)) {
        $subDirs = Get-ChildItem $SettingsPath -Directory | Select-Object -First 1
        if ($subDirs) { $script:SettingsPath = $subDirs.FullName; $manifestPath = Join-Path $script:SettingsPath "manifest.json" }
    }
    
    if (-not (Test-Path $manifestPath)) { Write-Log "Manifest not found" "ERROR"; return $false }
    
    try {
        $manifest = Get-Content $manifestPath -Raw | ConvertFrom-Json
        Write-Log "Manifest loaded: $($manifest.ExportDate) from $($manifest.SourceComputer)"
        Write-Log "Total items to restore: $($manifest.TotalItems)"
        $script:Manifest = $manifest
        return $true
    }
    catch { Write-Log "Failed to parse manifest: $_" "ERROR"; return $false }
}

function Restore-RegistrySettings {
    Write-ProgressPhase "Restoring Registry Settings"
    $registryDir = Join-Path $script:SettingsPath "registry"
    if (-not (Test-Path $registryDir)) { Write-Log "Registry directory not found, skipping" "SKIP"; return }
    
    $regFiles = Get-ChildItem $registryDir -Filter "*.reg" -ErrorAction SilentlyContinue
    if (-not $regFiles) { Write-Log "No .reg files found" "SKIP"; return }
    
    foreach ($regFile in $regFiles) {
        try {
            Write-Log "Importing: $($regFile.Name)"
            $process = Start-Process -FilePath "reg.exe" -ArgumentList "import `"$($regFile.FullName)`"" -Wait -PassThru -WindowStyle Hidden
            if ($process.ExitCode -eq 0) {
                $script:RestoredItems.Add([PSCustomObject]@{ Category = "Registry"; Name = $regFile.BaseName; Status = "OK" })
                Write-Log "Registry import successful: $($regFile.Name)" "SUCCESS"
            } else { throw "reg.exe returned exit code $($process.ExitCode)" }
        }
        catch { Write-Log "Failed to import $($regFile.Name): $_" "WARN" }
    }
    
    $powerFile = Join-Path $registryDir "power-schemes.pow"
    if (Test-Path $powerFile) { try { powercfg /import $powerFile 2>&1 | Out-Null; Write-Log "Power scheme restored" "SUCCESS" } catch { Write-Log "Failed to import power scheme: $_" "WARN" } }
}

function Copy-AppData {
    param([string]$Source, [string]$DestRoot, [string]$SubPath = "")
    $dest = if ($SubPath) { Join-Path $DestRoot $SubPath } else { $DestRoot }
    if (-not (Test-Path $dest)) { New-Item -ItemType Directory -Path $dest -Force | Out-Null }
    robocopy $Source $dest /E /R:3 /W:1 /MT:8 /NFL /NDL /NJH /NJS 2>&1 | Out-Null
}

function Restore-AppSettings {
    Write-ProgressPhase "Restoring Application Settings"
    $appDataDir = Join-Path $script:SettingsPath "appdata"
    if (-not (Test-Path $appDataDir)) { Write-Log "AppData directory not found, skipping" "SKIP"; return }
    
    $apps = Get-ChildItem $appDataDir -Directory -ErrorAction SilentlyContinue
    if (-not $apps) { Write-Log "No application directories found" "SKIP"; return }
    
    foreach ($appDir in $apps) {
        $appName = $appDir.Name
        Write-Log "Restoring $appName..."
        try {
            switch ($appName) {
                "Chrome" { Copy-AppData -Source $appDir.FullName -DestRoot $env:LOCALAPPDATA -SubPath "Google\Chrome\User Data\Default" }
                "Edge" { Copy-AppData -Source $appDir.FullName -DestRoot $env:LOCALAPPDATA -SubPath "Microsoft\Edge\User Data\Default" }
                "Firefox" {
                    $profilesDir = "$env:APPDATA\Mozilla\Firefox\Profiles"
                    if (Test-Path $profilesDir) { $prof = Get-ChildItem $profilesDir -Directory | Select-Object -First 1; if ($prof) { Copy-AppData -Source $appDir.FullName -DestRoot $prof.FullName } }
                }
                "VSCode" {
                    Copy-AppData -Source $appDir.FullName -DestRoot $env:APPDATA -SubPath "Code\User"
                    $extFile = Join-Path $appDir.FullName "extensions-list.json"
                    if ((Test-Path $extFile) -and (Get-Command code -ErrorAction SilentlyContinue)) {
                        $exts = Get-Content $extFile | ConvertFrom-Json
                        foreach ($ext in $exts) { Start-Process code -ArgumentList "--install-extension", $ext -WindowStyle Hidden -Wait }
                    }
                }
                "Git" { Copy-Item -Path (Join-Path $appDir.FullName "*") -Destination $env:USERPROFILE -Force -ErrorAction SilentlyContinue }
                "Steam" { Copy-AppData -Source $appDir.FullName -DestRoot "$env:ProgramFiles(x86)\Steam" }
                "EpicGames" { Copy-AppData -Source $appDir.FullName -DestRoot $env:LOCALAPPDATA -SubPath "EpicGamesLauncher\Saved\Config\Windows" }
                "GOGGalaxy" { Copy-AppData -Source $appDir.FullName -DestRoot $env:LOCALAPPDATA -SubPath "GOG.com\Galaxy\Configuration" }
                "Discord" { Copy-AppData -Source $appDir.FullName -DestRoot $env:APPDATA -SubPath "discord" }
                "Spotify" { Copy-AppData -Source $appDir.FullName -DestRoot $env:APPDATA -SubPath "Spotify" }
                "VLC" { Copy-AppData -Source $appDir.FullName -DestRoot $env:APPDATA -SubPath "vlc" }
                "Everything" { Copy-AppData -Source $appDir.FullName -DestRoot $env:LOCALAPPDATA -SubPath "Everything" }
                "7zip" { Copy-AppData -Source $appDir.FullName -DestRoot $env:APPDATA -SubPath "7-Zip" }
                "Notepad++" { Copy-AppData -Source $appDir.FullName -DestRoot $env:APPDATA -SubPath "Notepad++" }
                "WindowsTerminal" {
                    $wtDir = "$env:LOCALAPPDATA\Packages\Microsoft.WindowsTerminal_8wekyb3d8bbwe\LocalState"
                    if (-not (Test-Path $wtDir)) { $wtPkg = Get-ChildItem "$env:LOCALAPPDATA\Packages" -Filter "Microsoft.WindowsTerminal*" | Select-Object -First 1; if ($wtPkg) { $wtDir = Join-Path $wtPkg.FullName "LocalState" } }
                    if (Test-Path $wtDir) { Copy-AppData -Source $appDir.FullName -DestRoot $wtDir }
                }
                "PowerShell" {
                    $ps51 = "$env:USERPROFILE\Documents\WindowsPowerShell"; if (Test-Path $ps51) { Copy-AppData -Source $appDir.FullName -DestRoot $ps51 }
                    $ps7 = "$env:USERPROFILE\Documents\PowerShell"; if (Test-Path $ps7) { Copy-AppData -Source $appDir.FullName -DestRoot $ps7 }
                }
                "OhMyPosh" { Copy-AppData -Source $appDir.FullName -DestRoot "$env:LOCALAPPDATA\Programs\oh-my-posh\themes" }
                default { Write-Log "Skipping unknown app: $appName" "SKIP" }
            }
            $script:RestoredItems.Add([PSCustomObject]@{ Category = "Application"; Name = $appName; Status = "OK" })
        }
        catch { Write-Log "Failed to restore $appName`: $_" "WARN" }
    }
}

function Restore-UserData {
    Write-ProgressPhase "Restoring User Data"
    $userDataDir = Join-Path $script:SettingsPath "user-folders"
    if (-not (Test-Path $userDataDir)) { Write-Log "User data directory not found, skipping" "SKIP"; return }
    
    $folders = Get-ChildItem $userDataDir -Directory -ErrorAction SilentlyContinue
    foreach ($folder in $folders) {
        $dest = Join-Path $env:USERPROFILE $folder.Name
        Write-Log "Restoring $($folder.Name)..."
        try {
            if (-not (Test-Path $dest)) { New-Item -ItemType Directory -Path $dest -Force | Out-Null }
            robocopy $folder.FullName $dest /E /R:3 /W:1 /MT:8 /NFL /NDL /NJH /NJS 2>&1 | Out-Null
            $script:RestoredItems.Add([PSCustomObject]@{ Category = "UserData"; Name = $folder.Name; Status = "OK" })
            Write-Log "User data restored: $($folder.Name)" "SUCCESS"
        }
        catch { Write-Log "Failed to restore $($folder.Name)`: $_" "WARN" }
    }
}

function Restore-HardwareSettings {
    Write-ProgressPhase "Restoring Hardware Settings"
    $hardwareDir = Join-Path $script:SettingsPath "hardware"
    if (-not (Test-Path $hardwareDir)) { Write-Log "Hardware directory not found, skipping" "SKIP"; return }
    
    $displayFile = Join-Path $hardwareDir "display-settings.json"
    if (Test-Path $displayFile) { try { $ds = Get-Content $displayFile | ConvertFrom-Json; Write-Log "Display settings loaded (reference only): $($ds.Displays.Count) displays" } catch { } }
    
    $audioFile = Join-Path $hardwareDir "audio-devices.json"
    if (Test-Path $audioFile) { try { $ad = Get-Content $audioFile | ConvertFrom-Json; Write-Log "Audio devices loaded (reference only): $($ad.Devices.Count) devices" } catch { } }
    
    Write-Log "Hardware settings restored (informational only)" "SUCCESS"
}

function Show-Summary {
    Write-ProgressPhase "Restoration Complete"
    $duration = (Get-Date) - $script:StartTime
    Write-Host "`n═══════════════════════════════════════════════════════════════" -ForegroundColor Cyan
    Write-Host "              RESTORE SUMMARY" -ForegroundColor Cyan
    Write-Host "═══════════════════════════════════════════════════════════════" -ForegroundColor Cyan
    Write-Host "Duration:         $([math]::Round($duration.TotalMinutes, 2)) minutes"
    Write-Host "Items Restored:   $($script:RestoredItems.Count)"
    Write-Host "Warnings:         $($script:Warnings.Count)"
    Write-Host "Errors:           $($script:Errors.Count)"
    Write-Host "Log:              $LogPath"
    Write-Host "═══════════════════════════════════════════════════════════════`n" -ForegroundColor Cyan
    Write-Progress -Activity "Restoring Settings" -Completed
    
    # Restart Explorer
    try { Stop-Process -Name explorer -Force -ErrorAction SilentlyContinue; Start-Sleep 2; Start-Process explorer; Write-Log "Explorer restarted" "SUCCESS" }
    catch { Write-Log "Failed to restart Explorer" "WARN" }
}

# Main Execution
Write-Log "Settings Restore Starting"
Write-Log "Settings Path: $SettingsPath"

if (-not (Test-SettingsPackage)) { Write-Log "Settings package validation failed. Exiting." "ERROR"; exit 1 }

Restore-RegistrySettings
Restore-AppSettings
Restore-UserData
Restore-HardwareSettings
Show-Summary
Write-Log "Restore complete!" "SUCCESS"
