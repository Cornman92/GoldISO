#Requires -Version 5.1
#Requires -RunAsAdministrator

# Import common module
Import-Module (Join-Path $PSScriptRoot "Modules\GoldISO-Common.psm1") -Force

<#
.SYNOPSIS
    Export system and application settings for GoldISO migration.

.DESCRIPTION
    Captures Windows registry settings, application configurations, user data,
    and hardware preferences into a migration package for unattended restoration.

.PARAMETER ExportPath
    Directory to save the migration package. Default: $PSScriptRoot\..\Config\SettingsMigration

.PARAMETER ExportUserData
    Include user folders (Documents, Downloads, Desktop, Pictures).

.PARAMETER MaxUserDataSizeGB
    Maximum size in GB for user data export. Default: 10

.PARAMETER ExcludeApps
    Array of application names to exclude from export.

.PARAMETER IncludeWifiPasswords
    Include WiFi passwords in export (security warning displayed).

.PARAMETER Compress
    Create compressed archive of the export. Default: $true

.EXAMPLE
    .\Export-Settings.ps1 -ExportUserData -MaxUserDataSizeGB 5

.EXAMPLE
    .\Export-Settings.ps1 -ExcludeApps @("Chrome", "Firefox")
#>

[CmdletBinding()]
param(
    [string]$ExportPath = (Resolve-Path (Join-Path $PSScriptRoot "..\Config\SettingsMigration") -ErrorAction SilentlyContinue),
    [switch]$ExportUserData,
    [int]$MaxUserDataSizeGB = 10,
    [string[]]$ExcludeApps = @(),
    [switch]$IncludeWifiPasswords,
    [switch]$Compress
)

#region """""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""
# Configuration & Setup
# """""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""

$ErrorActionPreference = "Stop"
$script:StartTime = Get-Date
$script:ExportedItems = [System.Collections.Generic.List[PSCustomObject]]::new()
$script:Warnings = [System.Collections.Generic.List[string]]::new()
$script:Errors = [System.Collections.Generic.List[string]]::new()

# Configuration constants
$script:JsonDepth = 5  # Depth for ConvertTo-Json serialization

# Create export directory with timestamp
$timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
$script:ExportDir = Join-Path $ExportPath "Settings-Migration-$timestamp"
$script:LogFile = Join-Path $script:ExportDir "export.log"

# Ensure export directory exists
if (-not (Test-Path $script:ExportDir)) {
    New-Item -ItemType Directory -Path $script:ExportDir -Force | Out-Null
}

# Initialize centralized logging
Initialize-Logging -LogPath $script:LogFile
Write-Log "Settings Export Started: $(Get-Date)"

# Wrapper to track warnings/errors for summary
function Write-ExportLog {
    param([string]$Message, [ValidateSet("INFO","WARN","ERROR","SUCCESS")][string]$Level = "INFO")
    Write-GoldISOLog -Message $Message -Level $Level
    if ($Level -eq "WARN") { $script:Warnings.Add($Message) }
    if ($Level -eq "ERROR") { $script:Errors.Add($Message) }
}

# Alias for backward compatibility within this script
Set-Alias -Name Write-Log -Value Write-ExportLog -Scope Script

Write-Log "Export directory: $script:ExportDir"
Write-Log "User data export: $ExportUserData (max: ${MaxUserDataSizeGB}GB)"
Write-Log "Excluded apps: $($ExcludeApps -join ', ')"

#region """""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""
# Registry Export Functions
# """""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""

function Export-RegistryKeys {
    Write-Log "Exporting registry settings..."
    
    $registryDir = Join-Path $script:ExportDir "registry"
    New-Item -ItemType Directory -Path $registryDir -Force | Out-Null
    
    # Define registry keys to export (system and application settings)
    $registryKeys = @{
        # Windows Explorer settings
        "explorer-settings" = @(
            "HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer"
            "HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced"
            "HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\ControlPanel"
        )
        
        # Taskbar and Start menu
        "taskbar-settings" = @(
            "HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\StuckRects3"
            "HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\StuckRectsLegacy"
            "HKCU\Software\Microsoft\Windows\CurrentVersion\CloudStore\Store\Cache\DefaultAccount"
        )
        
        # Desktop and themes
        "desktop-settings" = @(
            "HKCU\Control Panel\Desktop"
            "HKCU\Software\Microsoft\Windows\CurrentVersion\Themes"
            "HKCU\Software\Microsoft\Windows\CurrentVersion\ThemeManager"
        )
        
        # Search and Cortana
        "search-settings" = @(
            "HKCU\Software\Microsoft\Windows\CurrentVersion\Search"
            "HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\Search\Preferences"
        )
        
        # Input and accessibility
        "input-settings" = @(
            "HKCU\Control Panel\Input Method"
            "HKCU\Software\Microsoft\Accessibility"
        )
        
        # Regional and language
        "regional-settings" = @(
            "HKCU\Control Panel\International"
            "HKCU\Control Panel\Desktop\WindowMetrics"
        )
        
        # Power settings (current user)
        "power-settings" = @(
            "HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\ControlPanel\NameSpace\{025A5937-A6BE-4686-A844-36FE4BEC8B6D}"
        )
        
        # Mouse and keyboard
        "input-devices" = @(
            "HKCU\Control Panel\Mouse"
            "HKCU\Control Panel\Keyboard"
        )
        
        # Network settings (user-specific)
        "network-settings" = @(
            "HKCU\Software\Microsoft\Windows\CurrentVersion\Internet Settings"
        )
    }
    
    $exportedCount = 0
    $failedCount = 0
    
    foreach ($category in $registryKeys.Keys) {
        $outputFile = Join-Path $registryDir "$category.reg"
        $keys = $registryKeys[$category]
        
        try {
            # Export all keys in category to single file
            $success = $false
            foreach ($key in $keys) {
                if (Test-Path "Registry::$key") {
                    $tempFile = [System.IO.Path]::GetTempFileName()
                    reg export $key $tempFile /y 2>&1 | Out-Null
                    
                    if (Test-Path $tempFile) {
                        Get-Content $tempFile | Add-Content $outputFile
                        Remove-Item $tempFile
                        $success = $true
                    }
                }
            }
            
            if ($success) {
                $exportedCount++
                $script:ExportedItems.Add([PSCustomObject]@{
                    Category = "Registry"
                    Name = $category
                    Path = $outputFile
                    Size = (Get-Item $outputFile).Length
                    Status = "OK"
                })
            }
        }
        catch {
            $failedCount++
            Write-Log "Failed to export $category`: $_" "WARN"
        }
    }
    
    # Export power schemes
    try {
        $powerFile = Join-Path $registryDir "power-schemes.pow"
        powercfg /export $powerFile 8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c 2>&1 | Out-Null
        if (Test-Path $powerFile) {
            $script:ExportedItems.Add([PSCustomObject]@{
                Category = "Power"
                Name = "High Performance Power Scheme"
                Path = $powerFile
                Size = (Get-Item $powerFile).Length
                Status = "OK"
            })
        }
    }
    catch {
        Write-Log "Failed to export power scheme: $_" "WARN"
    }
    
    Write-Log "Registry export complete: $exportedCount categories exported, $failedCount failed" "SUCCESS"
}

#region """""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""
# Application Settings Export
# """""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""

function Export-AppSettings {
    Write-Log "Exporting application settings..."
    
    $appDataDir = Join-Path $script:ExportDir "appdata"
    New-Item -ItemType Directory -Path $appDataDir -Force | Out-Null
    
    # Application definitions with paths to export
    $applications = @{
        # Web Browsers
        "Chrome" = @{
            Paths = @(
                "$env:LOCALAPPDATA\Google\Chrome\User Data\Default\Bookmarks"
                "$env:LOCALAPPDATA\Google\Chrome\User Data\Default\Preferences"
                "$env:LOCALAPPDATA\Google\Chrome\User Data\Default\Extensions"  # Extension list only
                "$env:LOCALAPPDATA\Google\Chrome\User Data\Local State"
            )
            Exclude = @("Cache", "Code Cache", "GPUCache", "Service Worker")
            Notes = "Bookmarks, settings, extensions list (not passwords)"
        }
        
        "Edge" = @{
            Paths = @(
                "$env:LOCALAPPDATA\Microsoft\Edge\User Data\Default\Bookmarks"
                "$env:LOCALAPPDATA\Microsoft\Edge\User Data\Default\Preferences"
                "$env:LOCALAPPDATA\Microsoft\Edge\User Data\Local State"
            )
            Exclude = @("Cache", "Code Cache", "GPUCache")
            Notes = "Bookmarks, settings"
        }
        
        "Firefox" = @{
            Paths = @()
            CustomScript = {
                $profilesDir = "$env:APPDATA\Mozilla\Firefox\Profiles"
                if (Test-Path $profilesDir) {
                    $firefoxProfile = Get-ChildItem $profilesDir -Directory | Select-Object -First 1
                    if ($firefoxProfile) {
                        return @(
                            "$($firefoxProfile.FullName)\places.sqlite"  # Bookmarks/history
                            "$($firefoxProfile.FullName)\prefs.js"       # Preferences
                            "$($firefoxProfile.FullName)\extensions"     # Extensions folder
                        )
                    }
                }
                return @()
            }
            Notes = "Profile settings, bookmarks, extensions"
        }
        
        # Development Tools
        "VSCode" = @{
            Paths = @(
                "$env:APPDATA\Code\User\settings.json"
                "$env:APPDATA\Code\User\keybindings.json"
                "$env:APPDATA\Code\User\snippets"
            )
            ExtensionsList = "$env:APPDATA\Code\User\extensions"
            Notes = "Settings, keybindings, snippets, extensions list"
        }
        
        "Git" = @{
            Paths = @(
                "$env:USERPROFILE\.gitconfig"
                "$env:USERPROFILE\.gitignore_global"
            )
            Notes = "Global git config and ignore patterns"
        }
        
        # Game Launchers
        "Steam" = @{
            Paths = @(
                "$env:ProgramFiles(x86)\Steam\config"  # Config files
                "$env:ProgramFiles(x86)\Steam\steamapps\libraryfolders.vdf"
                "$env:ProgramFiles(x86)\Steam\userdata"  # User-specific configs
            )
            Exclude = @("steamapps\common")  # Exclude actual game files
            Notes = "Library paths, user configs (NOT game files)"
        }
        
        "EpicGames" = @{
            Paths = @(
                "$env:LOCALAPPDATA\EpicGamesLauncher\Saved\Config\Windows\GameUserSettings.ini"
                "$env:LOCALAPPDATA\EpicGamesLauncher\Saved\Config\Windows\Engine.ini"
            )
            Notes = "Launcher settings"
        }
        
        "GOGGalaxy" = @{
            Paths = @(
                "$env:LOCALAPPDATA\GOG.com\Galaxy\Configuration\config.json"
            )
            Notes = "GOG Galaxy configuration"
        }
        
        # Media & Communication
        "Discord" = @{
            Paths = @(
                "$env:APPDATA\discord\settings.json"
                "$env:APPDATA\discord\Local Storage"
            )
            Exclude = @("Cache", "Code Cache", "GPUCache", "Crashpad")
            Notes = "Settings, login tokens"
        }
        
        "Spotify" = @{
            Paths = @(
                "$env:APPDATA\Spotify\prefs"
            )
            Exclude = @("Storage", "Browser", "Data")
            Notes = "Preferences"
        }
        
        "VLC" = @{
            Paths = @(
                "$env:APPDATA\vlc\vlcrc"
            )
            Notes = "VLC configuration"
        }
        
        # Utilities
        "Everything" = @{
            Paths = @(
                "$env:LOCALAPPDATA\Everything\Everything.ini"
                "$env:LOCALAPPDATA\Everything\Bookmarks.csv"
            )
            Notes = "Search settings, bookmarks"
        }
        
        "7zip" = @{
            Paths = @(
                "$env:APPDATA\7-Zip\7zFM.ini"
            )
            Notes = "7-Zip settings"
        }
        
        "Notepad++" = @{
            Paths = @(
                "$env:APPDATA\Notepad++\config.xml"
                "$env:APPDATA\Notepad++\shortcuts.xml"
                "$env:APPDATA\Notepad++\userDefineLangs"
                "$env:APPDATA\Notepad++\themes"
            )
            Notes = "Configuration, themes, custom languages"
        }
        
        "WindowsTerminal" = @{
            Paths = @(
                "$env:LOCALAPPDATA\Packages\Microsoft.WindowsTerminal_8wekyb3d8bbwe\LocalState\settings.json"
                "$env:LOCALAPPDATA\Packages\Microsoft.WindowsTerminal_8wekyb3d8bbwe\LocalState\state.json"
            )
            Notes = "Terminal settings and state"
        }
        
        "PowerShell" = @{
            Paths = @(
                "$env:USERPROFILE\Documents\PowerShell\Microsoft.PowerShell_profile.ps1"
                "$env:USERPROFILE\Documents\PowerShell\profile.ps1"
                "$env:USERPROFILE\Documents\WindowsPowerShell\Microsoft.PowerShell_profile.ps1"
            )
            Notes = "PowerShell profiles"
        }
        
        "OhMyPosh" = @{
            Paths = @(
                "$env:LOCALAPPDATA\Programs\oh-my-posh\themes\*.omp.json"
                "$env:USERPROFILE\.oh-my-posh.json"
            )
            Notes = "Oh My Posh themes and config"
        }
    }
    
    $exportedCount = 0
    $skippedCount = 0
    
    foreach ($appName in $applications.Keys) {
        # Skip if excluded
        if ($ExcludeApps -contains $appName) {
            Write-Log "Skipping $appName (excluded)" "WARN"
            $skippedCount++
            continue
        }
        
        $app = $applications[$appName]
        $appExportDir = Join-Path $appDataDir $appName
        
        try {
            # Get paths to export
            $pathsToExport = if ($app.CustomScript) {
                & $app.CustomScript
            } else {
                $app.Paths
            }
            
            $anyExported = $false
            
            foreach ($path in $pathsToExport) {
                if (Test-Path $path) {
                    $item = Get-Item $path
                    $relativePath = $path.Substring($env:USERPROFILE.Length + 1)
                    $destPath = Join-Path $appExportDir $relativePath
                    
                    # Create directory structure
                    $destDir = Split-Path $destPath -Parent
                    if (-not (Test-Path $destDir)) {
                        New-Item -ItemType Directory -Path $destDir -Force | Out-Null
                    }
                    
                    # Copy item (file or directory)
                    if ($item.PSIsContainer) {
                        # For directories, use robocopy with exclusions
                        $excludeArgs = ""
                        if ($app.Exclude) {
                            $excludeArgs = "/XD " + ($app.Exclude -join " ")
                        }
                        robocopy $path $destPath /E /R:1 /W:1 /MT:8 $excludeArgs /NFL /NDL /NJH /NJS 2>&1 | Out-Null
                        if ($LASTEXITCODE -ge 8) {
                            Write-Log "Robocopy failed with exit code $LASTEXITCODE for $appName" "WARN"
                        }
                    } else {
                        Copy-Item $path $destPath -Force
                    }
                    
                    $anyExported = $true
                    
                    # For VS Code, also export extensions list
                    if ($appName -eq "VSCode" -and $app.ExtensionsList -and (Test-Path $app.ExtensionsList)) {
                        $extensionsJson = Join-Path $appExportDir "extensions-list.json"
                        $extensions = Get-ChildItem $app.ExtensionsList -Directory | Select-Object -ExpandProperty Name
                        $extensions | ConvertTo-Json | Set-Content $extensionsJson
                    }
                }
            }
            
            if ($anyExported) {
                $exportedCount++
                $size = (Get-ChildItem $appExportDir -Recurse -File | Measure-Object -Property Length -Sum).Sum
                $script:ExportedItems.Add([PSCustomObject]@{
                    Category = "Application"
                    Name = $appName
                    Path = $appExportDir
                    Size = $size
                    Status = "OK"
                    Notes = $app.Notes
                })
                Write-Log "Exported $appName ($([math]::Round($size/1MB, 2)) MB)"
            }
        }
        catch {
            Write-Log "Failed to export $appName`: $_" "WARN"
        }
    }
    
    Write-Log "Application export complete: $exportedCount apps, $skippedCount skipped" "SUCCESS"
}

#region """""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""
# User Data Export
# """""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""

function Export-UserData {
    if (-not $ExportUserData) {
        Write-Log "User data export skipped (use -ExportUserData to include)"
        return
    }
    
    Write-Log "Exporting user data (max: ${MaxUserDataSizeGB}GB)..."
    
    $userDataDir = Join-Path $script:ExportDir "user-folders"
    New-Item -ItemType Directory -Path $userDataDir -Force | Out-Null
    
    $folders = @{
        "Desktop" = "$env:USERPROFILE\Desktop"
        "Documents" = "$env:USERPROFILE\Documents"
        "Downloads" = "$env:USERPROFILE\Downloads"
        "Pictures" = "$env:USERPROFILE\Pictures"
        "Videos" = "$env:USERPROFILE\Videos"
        "Music" = "$env:USERPROFILE\Music"
    }
    
    $maxSizeBytes = $MaxUserDataSizeGB * 1GB
    $totalSize = 0
    $exportedCount = 0
    
    foreach ($folderName in $folders.Keys) {
        $sourcePath = $folders[$folderName]
        
        if (Test-Path $sourcePath) {
            $size = (Get-ChildItem $sourcePath -Recurse -File -ErrorAction SilentlyContinue | 
                     Measure-Object -Property Length -Sum).Sum
            
            if ($totalSize + $size -gt $maxSizeBytes) {
                Write-Log "$folderName ($([math]::Round($size/1MB, 2)) MB) exceeds limit, skipping" "WARN"
                continue
            }
            
            $destPath = Join-Path $userDataDir $folderName
            
            try {
                robocopy $sourcePath $destPath /E /R:1 /W:1 /MT:8 /NFL /NDL /NJH /NJS 2>&1 | Out-Null
                if ($LASTEXITCODE -ge 8) {
                    throw "Robocopy failed with exit code $LASTEXITCODE"
                }
                
                $totalSize += $size
                $exportedCount++
                $script:ExportedItems.Add([PSCustomObject]@{
                    Category = "UserData"
                    Name = $folderName
                    Path = $destPath
                    Size = $size
                    Status = "OK"
                })
                Write-Log "Exported $folderName ($([math]::Round($size/1MB, 2)) MB)"
            }
            catch {
                Write-Log "Failed to export $folderName`: $_" "WARN"
            }
        }
    }
    
    Write-Log "User data export complete: $exportedCount folders, $([math]::Round($totalSize/1MB, 2)) MB total" "SUCCESS"
}

#region """""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""
# Hardware Settings Export
# """""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""

function Export-HardwareSettings {
    Write-Log "Exporting hardware settings..."
    
    $hardwareDir = Join-Path $script:ExportDir "hardware"
    New-Item -ItemType Directory -Path $hardwareDir -Force | Out-Null
    
    # Display settings
    try {
        $displays = Get-CimInstance -Namespace root\wmi -ClassName WmiMonitorBasicDisplayParams -ErrorAction SilentlyContinue | 
            Select-Object InstanceName, SupportedDisplayFeatures
        
        $displaySettings = @{
            Displays = $displays
            ScreenResolutions = Get-CimInstance Win32_VideoController | 
                Select-Object Name, CurrentHorizontalResolution, CurrentVerticalResolution, CurrentRefreshRate
            Timestamp = Get-Date -Format "o"
        }
        
        $displaySettings | ConvertTo-Json -Depth $script:JsonDepth | 
            Set-Content (Join-Path $hardwareDir "display-settings.json")
        
        $script:ExportedItems.Add([PSCustomObject]@{
            Category = "Hardware"
            Name = "Display Settings"
            Path = Join-Path $hardwareDir "display-settings.json"
            Size = (Get-Item (Join-Path $hardwareDir "display-settings.json")).Length
            Status = "OK"
        })
        Write-Log "Exported display settings"
    }
    catch {
        Write-Log "Failed to export display settings: $_" "WARN"
    }
    
    # Audio devices
    try {
        $audioDevices = Get-CimInstance Win32_SoundDevice | 
            Select-Object Name, Status, Availability, DeviceID
        
        $audioSettings = @{
            Devices = $audioDevices
            DefaultDevice = "To be set post-install via restore script"
            Timestamp = Get-Date -Format "o"
        }
        
        $audioSettings | ConvertTo-Json | 
            Set-Content (Join-Path $hardwareDir "audio-devices.json")
        
        Write-Log "Exported audio device list"
    }
    catch {
        Write-Log "Failed to export audio settings: $_" "WARN"
    }
    
    # WiFi profiles
    if ($IncludeWifiPasswords) {
        Write-Host "`nWARNING: WiFi passwords will be exported in plain text!`n" -ForegroundColor Yellow
        $confirm = Read-Host "Type 'YES' to confirm including WiFi passwords"
        if ($confirm -eq "YES") {
            try {
                $profiles = netsh wlan show profiles | Select-String "All User Profile" | ForEach-Object {
                    $_ -match "All User Profile\s+:\s+(.+)$" | Out-Null
                    $Matches[1]
                }
                
                $wifiProfiles = @()
                foreach ($wifiProfile in $profiles) {
                    $details = netsh wlan show profile name="$wifiProfile" key=clear
                    $wifiProfiles += @{
                        Name = $wifiProfile
                        Details = $details
                    }
                }
                
                $wifiProfiles | ConvertTo-Json | 
                    Set-Content (Join-Path $hardwareDir "wifi-profiles.xml")
                
                Write-Log "Exported WiFi profiles with passwords"
            }
            catch {
                Write-Log "Failed to export WiFi profiles: $_" "WARN"
            }
        } else {
            Write-Log "WiFi password export cancelled by user"
        }
    }
    
    Write-Log "Hardware settings export complete" "SUCCESS"
}

#region """""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""
# Manifest & Compression
# """""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""

function Export-Manifest {
    Write-Log "Generating manifest..."
    
    $manifest = @{
        ExportDate = Get-Date -Format "o"
        SourceComputer = $env:COMPUTERNAME
        SourceUser = $env:USERNAME
        WindowsVersion = (Get-CimInstance Win32_OperatingSystem).Version
        TotalItems = $script:ExportedItems.Count
        TotalSize = ($script:ExportedItems | Measure-Object -Property Size -Sum).Sum
        Items = $script:ExportedItems
        Warnings = $script:Warnings
        Errors = $script:Errors
        Checksums = @{}
        Configuration = @{
            ExportUserData = $ExportUserData
            MaxUserDataSizeGB = $MaxUserDataSizeGB
            ExcludeApps = $ExcludeApps
            IncludeWifiPasswords = $IncludeWifiPasswords
        }
    }
    
    # Generate checksums for all files
    Write-Log "Generating file checksums..."
    $files = Get-ChildItem $script:ExportDir -Recurse -File
    foreach ($file in $files) {
        if ($file.Name -ne "manifest.json") {
            $hash = Get-FileHash $file.FullName -Algorithm SHA256
            $relativePath = $file.FullName.Substring($script:ExportDir.Length + 1)
            $manifest.Checksums[$relativePath] = $hash.Hash
        }
    }
    
    # Save manifest
    $manifestPath = Join-Path $script:ExportDir "manifest.json"
    $manifest | ConvertTo-Json -Depth 10 | Set-Content $manifestPath
    Write-Log "Manifest saved: $manifestPath"
    
    return $manifest
}

function Compress-Export {
    if (-not $Compress) {
        return
    }
    
    Write-Log "Compressing export package..."
    
    $archivePath = "$script:ExportDir.zip"
    
    try {
        # Use .NET compression for better compatibility
        Add-Type -Assembly System.IO.Compression.FileSystem
        [System.IO.Compression.ZipFile]::CreateFromDirectory(
            $script:ExportDir, 
            $archivePath,
            [System.IO.Compression.CompressionLevel]::Optimal,
            $false
        )
        
        $archiveSize = (Get-Item $archivePath).Length
        Write-Host "[$((Get-Date).ToString('yyyy-MM-dd HH:mm:ss'))] [SUCCESS] Archive created: $archivePath ($([math]::Round($archiveSize/1MB, 2)) MB)"
        
        # Optionally remove uncompressed directory
        $response = Read-Host "Remove uncompressed directory? (Y/N)"
        if ($response -eq "Y" -or $response -eq "y") {
            # Close the log file handle before deleting
            $script:LogFile = $null
            Start-Sleep -Milliseconds 100
            Remove-Item $script:ExportDir -Recurse -Force -ErrorAction SilentlyContinue
            Write-Host "[$((Get-Date).ToString('yyyy-MM-dd HH:mm:ss'))] [INFO] Uncompressed directory removed"
        }
    }
    catch {
        Write-Host "[$((Get-Date).ToString('yyyy-MM-dd HH:mm:ss'))] [WARN] Failed to compress: $_"
    }
}

function Show-Summary {
    $manifest = Export-Manifest
    
    Write-Host "`n---------------------------------------------------------------" -ForegroundColor Cyan
    Write-Host "              EXPORT SUMMARY" -ForegroundColor Cyan
    Write-Host "---------------------------------------------------------------" -ForegroundColor Cyan
    Write-Host "Export Location:  $script:ExportDir"
    Write-Host "Total Items:      $($manifest.TotalItems)"
    Write-Host "Total Size:       $([math]::Round($manifest.TotalSize/1MB, 2)) MB"
    Write-Host "Warnings:         $($script:Warnings.Count)"
    Write-Host "Errors:           $($script:Errors.Count)"
    Write-Host "---------------------------------------------------------------" -ForegroundColor Cyan
    
    # Category breakdown
    $categories = $script:ExportedItems | Group-Object -Property Category
    Write-Host "`nExport Breakdown:" -ForegroundColor Yellow
    foreach ($cat in $categories) {
        $catSize = ($cat.Group | Measure-Object -Property Size -Sum).Sum
        Write-Host "  - $($cat.Name): $($cat.Count) items ($([math]::Round($catSize/1MB, 2)) MB)"
    }
    
    if ($script:Warnings.Count -gt 0) {
        Write-Host "`nWarnings:" -ForegroundColor Yellow
        $script:Warnings | ForEach-Object { Write-Host "  - $_" -ForegroundColor Yellow }
    }
    
    if ($script:Errors.Count -gt 0) {
        Write-Host "`nErrors:" -ForegroundColor Red
        $script:Errors | ForEach-Object { Write-Host "  - $_" -ForegroundColor Red }
    }
    
    Write-Host "`nExport complete! Use this package with Build-ISO-With-Settings.ps1" -ForegroundColor Green
    Write-Host "---------------------------------------------------------------`n" -ForegroundColor Cyan
    
    # Return manifest for automation
    return $manifest
}

#region """""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""
# Main Execution
# """""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""

Write-Log "---------------------------------------------------------------"
Write-Log "Settings Export Starting"
Write-Log "---------------------------------------------------------------"

# Create directory structure
@("registry", "appdata", "hardware", "scripts") | ForEach-Object {
    New-Item -ItemType Directory -Path (Join-Path $script:ExportDir $_) -Force | Out-Null
}

# Execute exports
Export-RegistryKeys
Export-AppSettings
Export-UserData
Export-HardwareSettings

# Finalize
$manifest = Show-Summary

# Log completion BEFORE compression (in case directory gets deleted)
$duration = [math]::Round(((Get-Date) - $script:StartTime).TotalSeconds, 2)
Write-Host "[$((Get-Date).ToString('yyyy-MM-dd HH:mm:ss'))] [INFO] Export complete in $duration seconds"

# Now compress (directory may be deleted after this)
Compress-Export

# Return manifest object for pipeline usage
$manifest
