#Requires -Version 5.1
<#
.SYNOPSIS
    Scans the system for installed applications and generates GWIG-compatible app manifests.

.DESCRIPTION
    Performs comprehensive system scan to discover installed applications:
    - Win32 applications (Add/Remove Programs registry)
    - UWP/Store apps (PackageManager)
    - winget-available apps (if winget is installed)
    
    Generates categorized JSON files compatible with GWIG's winget-packages.json format.

.PARAMETER OutputPath
    Directory to save scan results. Default: C:\temp\gwig-scan

.PARAMETER IncludeWinget
    Also query winget for package availability (slower but more accurate matching).

.PARAMETER Categorize
    Auto-categorize apps based on known patterns and heuristics.

.PARAMETER GenerateReport
    Generate a text summary report. Default: true

.EXAMPLE
    .\Scan-InstalledApps.ps1 -OutputPath "C:\temp\my-apps" -IncludeWinget -Categorize

.NOTES
    FileName: Scan-InstalledApps.ps1
    Author: GoldISO Project
    Created: 2026
#>

[CmdletBinding()]
param(
    [string]$OutputPath = "C:\temp\gwig-scan",
    [switch]$IncludeWinget,
    [switch]$Categorize,
    [switch]$GenerateReport = $true
)

#region Configuration

# Category mappings based on app name patterns
$CategoryPatterns = @{
    'browsers'    = @('Chrome', 'Firefox', 'Edge', 'Opera', 'Brave', 'Vivaldi', 'Safari', 'Chromium')
    'dev_tools'   = @('Visual Studio', 'VS Code', 'Python', 'Node', 'Git', 'Docker', 'IntelliJ', 'Eclipse', 'PyCharm', 'Go ', 'Rust', 'Ruby', 'PHP', 'Java', 'JDK', 'SDK', 'JetBrains', 'Sublime', 'Vim', 'Neovim', 'Cursor', 'Windsurf')
    'gaming'      = @('Steam', 'Epic Games', 'GOG', 'Battle.net', 'EA ', 'Ubisoft', 'Xbox', 'Discord', 'NVIDIA GeForce', 'AMD Radeon', 'MSI Afterburner', 'OBS', 'Twitch', 'Overwolf', 'Rainmeter', 'Wallpaper Engine')
    'media'       = @('VLC', 'Spotify', 'iTunes', 'Winamp', 'foobar2000', 'HandBrake', 'Media Player', 'Plex', 'Kodi', 'Jellyfin', 'Audacity', 'Reaper', 'FL Studio', 'Ableton', 'Premiere', 'After Effects', 'DaVinci', 'Photoshop', 'Lightroom', 'GIMP', 'Blender', 'Maya', '3ds Max', 'Cinema 4D')
    'utilities'   = @('7-Zip', 'WinRAR', 'Everything', 'Notepad++', 'CPU-Z', 'GPU-Z', 'HWiNFO', 'CrystalDisk', 'PowerToys', 'Sysinternals', 'CCleaner', 'Teracopy', 'Directory Opus', 'Total Commander', 'f.lux', 'Lightshot', 'ShareX', 'Snipping Tool', 'PuTTY', 'MobaXterm', 'Terminal', 'PowerShell', 'AutoHotkey', 'Macro', 'Rainmeter', 'Ninite')
    'remote'      = @('AnyDesk', 'TeamViewer', 'Chrome Remote', 'Parsec', 'Sunshine', 'Moonlight', 'ZeroTier', 'Tailscale', 'WireGuard', 'OpenVPN', 'Radmin', 'Remote Desktop', 'Splashtop', 'LogMeIn')
}

# Known winget package mappings (Win32 app name -> winget ID)
$KnownWingetMappings = @{
    'Google Chrome'                      = 'Google.Chrome'
    'Opera GX'                           = 'Opera.OperaGX'
    'Mozilla Firefox'                    = 'Mozilla.Firefox'
    'Brave'                              = 'Brave.Brave'
    'Vivaldi'                            = 'Vivaldi.Vivaldi'
    'Microsoft Edge'                     = 'Microsoft.Edge'
    'Visual Studio Code'                 = 'Microsoft.VisualStudioCode'
    'Git'                                = 'Git.Git'
    'GitHub CLI'                         = 'GitHub.cli'
    'Python'                             = 'Python.Python.3.12'
    'Node.js'                            = 'OpenJS.NodeJS.LTS'
    'PowerShell'                         = 'Microsoft.PowerShell'
    'PowerToys'                          = 'Microsoft.PowerToys'
    'Oh My Posh'                         = 'JanDeDobbeleer.OhMyPosh'
    'Docker Desktop'                     = 'Docker.DockerDesktop'
    'Windows Terminal'                   = 'Microsoft.WindowsTerminal'
    'Steam'                              = 'Valve.Steam'
    'Epic Games Launcher'                = 'EpicGames.EpicGamesLauncher'
    'GOG Galaxy'                         = 'GOG.Galaxy'
    'Battle.net'                         = 'Blizzard.BattleNet'
    'Xbox'                               = 'Microsoft.Xbox'
    'Ubisoft Connect'                    = 'Ubisoft.Connect'
    'EA App'                             = 'EADesktop.EADesktop'
    'Parsec'                             = 'Parsec.Parsec'
    'VLC'                                = 'VideoLAN.VLC'
    'HandBrake'                          = 'HandBrake.HandBrake'
    'ShareX'                             = 'ShareX.ShareX'
    'Discord'                            = 'Discord.Discord'
    'Spotify'                            = 'Spotify.Spotify'
    '7-Zip'                              = '7zip.7zip'
    'WinRAR'                             = 'RARLab.WinRAR'
    'Everything'                         = 'voidtools.Everything'
    'Notepad++'                          = 'Notepad++.Notepad++'
    'WizTree'                            = 'WizTree.WizTree'
    'CPU-Z'                              = 'CPUID.CPU-Z'
    'GPU-Z'                              = 'TechPowerUp.GPU-Z'
    'HWiNFO'                             = 'REALiX.HWiNFO'
    'Rufus'                              = 'Rufus.Rufus'
    'Ventoy'                             = 'Ventoy.Ventoy'
    'AnyDesk'                            = 'AnyDeskSoftwareGmbH.AnyDesk'
    'TeamViewer'                         = 'TeamViewer.TeamViewer'
    'Tailscale'                          = 'Tailscale.Tailscale'
    'Logitech G HUB'                     = 'Logitech.GHUB'
}

#endregion

#region Helper Functions

function Test-IsInteractiveApp {
    param([string]$AppName)
    
    $interactivePatterns = @(
        'driver', 'runtime', 'redistributable', 'sdk', 'framework',
        'microsoft visual c++', 'visual studio', '.net', 'java se',
        'update for', 'security update', 'hotfix', 'service pack',
        'kb[0-9]', 'runtime package', 'support component',
        'locale', 'language pack', 'help content', 'documentation'
    )
    
    foreach ($pattern in $interactivePatterns) {
        if ($AppName -match $pattern) {
            return $false
        }
    }
    return $true
}

function Get-AppCategory {
    param([string]$AppName)
    
    foreach ($category in $CategoryPatterns.Keys) {
        foreach ($pattern in $CategoryPatterns[$category]) {
            if ($AppName -like "*$pattern*") {
                return $category
            }
        }
    }
    return 'utilities'  # Default category
}

function Find-WingetId {
    param([string]$AppName)
    
    # Check exact mappings first
    foreach ($known in $KnownWingetMappings.Keys) {
        if ($AppName -like "*$known*" -or $known -like "*$AppName*") {
            return $KnownWingetMappings[$known]
        }
    }
    
    return $null
}

function Get-Win32Apps {
    $apps = @()
    
    # 64-bit registry
    $regPath64 = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall'
    # 32-bit registry (WOW6432Node)
    $regPath32 = 'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall'
    # User registry
    $regPathUser = 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall'
    
    $searchPaths = @($regPath64, $regPath32)
    if (Test-Path $regPathUser) {
        $searchPaths += $regPathUser
    }
    
    foreach ($path in $searchPaths) {
        if (-not (Test-Path $path)) { continue }
        
        $items = Get-ChildItem $path -ErrorAction SilentlyContinue
        foreach ($item in $items) {
            try {
                $props = Get-ItemProperty $item.PSPath -ErrorAction SilentlyContinue
                
                # Skip entries without display name
                if (-not $props.DisplayName) { continue }
                
                # Skip Windows components and updates
                if ($props.IsMinorUpgrade -or $props.PSChildName -match '^{[0-9A-F-]+}$') {
                    if ($props.DisplayName -match 'update|patch|hotfix|kb[0-9]|security|component') {
                        continue
                    }
                }
                
                # Skip system components marked as such
                if ($props.SystemComponent -eq 1) { continue }
                
                $app = [PSCustomObject]@{
                    Name        = $props.DisplayName
                    Version     = $props.DisplayVersion
                    Publisher   = $props.Publisher
                    InstallDate = $props.InstallDate
                    InstallLocation = $props.InstallLocation
                    UninstallString = $props.UninstallString
                    IsInteractive = Test-IsInteractiveApp -AppName $props.DisplayName
                    Category = if ($Categorize) { Get-AppCategory -AppName $props.DisplayName } else $null
                    PotentialWingetId = if ($IncludeWinget) { Find-WingetId -AppName $props.DisplayName } else $null
                    Source = 'Win32'
                }
                
                $apps += $app
            }
            catch {
                Write-Verbose "Error reading registry entry: $($item.PSPath)"
            }
        }
    }
    
    return $apps | Sort-Object Name -Unique
}

function Get-UWPApps {
    try {
        $packages = Get-AppxPackage | Where-Object { 
            $_.IsFramework -eq $false -and 
            $_.SignatureKind -eq 'Store' -and
            $_.Name -notmatch '^Microsoft\.'  # Skip built-in Microsoft apps
        }
        
        $apps = $packages | ForEach-Object {
            [PSCustomObject]@{
                Name = if ($_.Name -match '^[^.]+\.') { ($_.Name -split '\.')[1] } else { $_.Name }
                PackageName = $_.Name
                Version = $_.Version
                Publisher = $_.Publisher
                InstallLocation = $_.InstallLocation
                IsInteractive = $true
                Category = if ($Categorize) { Get-AppCategory -AppName $_.Name } else $null
                PotentialWingetId = $null  # UWP apps use different IDs
                Source = 'UWP'
            }
        }
        
        return $apps
    }
    catch {
        Write-Warning "Failed to enumerate UWP apps: $_"
        return @()
    }
}

function Get-WingetApps {
    try {
        # Check if winget is available
        $winget = Get-Command winget -ErrorAction SilentlyContinue
        if (-not $winget) {
            Write-Warning "winget not found in PATH. Skipping winget query."
            return @()
        }
        
        # Export installed packages
        $tempExport = Join-Path $env:TEMP "winget-export-$(Get-Random).json"
        & winget export -o $tempExport --include-versions 2>$null
        
        if (Test-Path $tempExport) {
            $content = Get-Content $tempExport -Raw | ConvertFrom-Json
            Remove-Item $tempExport -Force
            
            $apps = $content.Sources.Packages | ForEach-Object {
                [PSCustomObject]@{
                    Name = $_.PackageIdentifier -replace '^[^.]+\.', ''
                    PackageIdentifier = $_.PackageIdentifier
                    Version = $_.Version
                    Source = 'winget'
                    IsInteractive = $true
                    Category = if ($Categorize) { 
                        $simpleName = $_.PackageIdentifier -replace '^[^.]+\.', ''
                        Get-AppCategory -AppName $simpleName 
                    } else { $null }
                }
            }
            
            return $apps
        }
    }
    catch {
        Write-Warning "Failed to query winget: $_"
    }
    
    return @()
}

#endregion

#region Main Execution

# Ensure output directory exists
if (-not (Test-Path $OutputPath)) {
    New-Item -ItemType Directory -Path $OutputPath -Force | Out-Null
    Write-Host "Created output directory: $OutputPath" -ForegroundColor Green
}

Write-Host "`nScanning system for installed applications..." -ForegroundColor Cyan
Write-Host "Output path: $OutputPath`n" -ForegroundColor Gray

# Scan Win32 apps
Write-Host "[1/3] Scanning Win32 applications (Add/Remove Programs)..." -ForegroundColor Yellow
$win32Apps = Get-Win32Apps
$interactiveWin32 = $win32Apps | Where-Object { $_.IsInteractive }
Write-Host "    Found $($win32Apps.Count) total Win32 apps ($($interactiveWin32.Count) interactive)" -ForegroundColor White

# Scan UWP apps
Write-Host "[2/3] Scanning UWP/Store apps..." -ForegroundColor Yellow
$uwpApps = Get-UWPApps
Write-Host "    Found $($uwpApps.Count) UWP apps" -ForegroundColor White

# Scan winget apps (if requested)
$wingetApps = @()
if ($IncludeWinget) {
    Write-Host "[3/3] Querying winget for installed packages..." -ForegroundColor Yellow
    $wingetApps = Get-WingetApps
    Write-Host "    Found $($wingetApps.Count) winget packages" -ForegroundColor White
}
else {
    Write-Host "[3/3] Skipping winget query (use -IncludeWinget to enable)" -ForegroundColor Gray
}

Write-Host "`nProcessing results..." -ForegroundColor Cyan

# Convert to GWIG winget format
$wingetPackages = @()
foreach ($app in $interactiveWin32) {
    if ($app.PotentialWingetId) {
        $wingetPackages += [PSCustomObject]@{
            PackageIdentifier = $app.PotentialWingetId
            Category = $app.Category
            Notes = "Detected: $($app.Name)"
            Optional = $true
        }
    }
}

foreach ($app in $wingetApps) {
    if (-not ($wingetPackages | Where-Object { $_.PackageIdentifier -eq $app.PackageIdentifier })) {
        $wingetPackages += [PSCustomObject]@{
            PackageIdentifier = $app.PackageIdentifier
            Category = $app.Category
            Notes = if ($app.Version) { "Version: $($app.Version)" } else { "winget package" }
            Optional = $true
        }
    }
}

# Build winget-packages.json structure
$wingetManifest = [PSCustomObject]@{
    '$schema' = "https://aka.ms/winget-packages.schema.2.0.json"
    CreationDate = (Get-Date -Format "yyyy-MM-ddTHH:mm:ss.fffffffZ")
    Description = "Auto-generated app manifest from system scan"
    Categories = @(
        @{ Name = "browsers"; Description = "Web browsers"; InstallPath = "C:\Program Files" }
        @{ Name = "dev_tools"; Description = "Development tools and runtimes"; InstallPath = "C:\Dev" }
        @{ Name = "gaming"; Description = "Game launchers and gaming platforms"; InstallPath = "C:\Gaming" }
        @{ Name = "media"; Description = "Media playback, recording, and streaming"; InstallPath = "C:\Media" }
        @{ Name = "utilities"; Description = "System utilities, archivers, and productivity tools"; InstallPath = "C:\Utils" }
        @{ Name = "remote"; Description = "Remote desktop and VPN tools"; InstallPath = "C:\Remote" }
    )
    Sources = @(
        [PSCustomObject]@{
            Packages = $wingetPackages
            SourceDetails = [PSCustomObject]@{
                Argument = "https://cdn.winget.microsoft.com/cache"
                Identifier = "Microsoft.Winget.Source_8wekyb3d8bbwe"
                Name = "winget"
                Type = "Microsoft.PreIndexed.Package"
            }
        }
    )
    WinGetVersion = "1.9.25200"
}

# Save winget-compatible manifest
$wingetOutput = Join-Path $OutputPath "installed-apps-winget.json"
$wingetManifest | ConvertTo-Json -Depth 10 | Set-Content $wingetOutput -Encoding UTF8
Write-Host "    Saved: $wingetOutput ($($wingetPackages.Count) winget-compatible packages)" -ForegroundColor Green

# Save Win32-only apps (non-winget)
$win32Only = $interactiveWin32 | Where-Object { -not $_.PotentialWingetId }
$win32Output = Join-Path $OutputPath "installed-apps-win32.json"
$win32Only | Select-Object Name, Version, Publisher, InstallLocation, Category, Source | ConvertTo-Json -Depth 5 | Set-Content $win32Output -Encoding UTF8
Write-Host "    Saved: $win32Output ($($win32Only.Count) Win32 apps without winget IDs)" -ForegroundColor Green

# Save UWP apps
$uwpOutput = Join-Path $OutputPath "installed-apps-uwp.json"
$uwpApps | Select-Object Name, PackageName, Version, Publisher, Category | ConvertTo-Json -Depth 5 | Set-Content $uwpOutput -Encoding UTF8
Write-Host "    Saved: $uwpOutput ($($uwpApps.Count) UWP apps)" -ForegroundColor Green

# Save full raw data
$fullOutput = Join-Path $OutputPath "installed-apps-full.json"
[PSCustomObject]@{
    ScanDate = Get-Date -Format "o"
    Win32Apps = $win32Apps
    UWPApps = $uwpApps
    WingetPackages = $wingetApps
} | ConvertTo-Json -Depth 10 | Set-Content $fullOutput -Encoding UTF8
Write-Host "    Saved: $fullOutput (complete scan data)" -ForegroundColor Green

# Generate text report
if ($GenerateReport) {
    $reportOutput = Join-Path $OutputPath "app-discovery-report.txt"
    $report = @"
================================================================================
           GOLDISO APP DISCOVERY REPORT
           Generated: $(Get-Date -Format "yyyy-MM-dd HH:mm:ss")
================================================================================

SUMMARY
-------
Total Win32 Apps Found:      $($win32Apps.Count)
Interactive Win32 Apps:    $($interactiveWin32.Count)
UWP/Store Apps:            $($uwpApps.Count)
winget Packages:           $($wingetApps.Count)
winget-Compatible Apps:    $($wingetPackages.Count)
Apps Requiring Manual:     $($win32Only.Count)

WINGET-COMPATIBLE APPS (Auto-Installable)
-----------------------------------------
$($wingetPackages | ForEach-Object { "- [$($_.Category)] $($_.PackageIdentifier)" } | Sort-Object | Out-String)

WIN32 APPS (Manual Configuration Required)
-----------------------------------------
$($win32Only | Select-Object -First 20 | ForEach-Object { "- [$($_.Category)] $($_.Name) v$($_.Version)" } | Out-String)
$(if ($win32Only.Count -gt 20) { "`n... and $($win32Only.Count - 20) more apps`n" })

UWP/STORE APPS (Microsoft Store)
--------------------------------
$($uwpApps | Select-Object -First 15 | ForEach-Object { "- [$($_.Category)] $($_.Name) ($($_.PackageName))" } | Out-String)
$(if ($uwpApps.Count -gt 15) { "`n... and $($uwpApps.Count - 15) more apps`n" })

CATEGORY BREAKDOWN
------------------
$((($interactiveWin32 + $uwpApps) | Group-Object Category | Sort-Object Count -Descending | ForEach-Object { "$($_.Count) apps`t: $($_.Name)" }) -join "`n")

RECOMMENDED ACTIONS
-----------------
1. Review 'installed-apps-winget.json' - these can be merged into Config/winget-packages.json
2. For Win32 apps without winget IDs, create custom installer configurations
3. UWP apps require manual installation or Store configuration in autounattend.xml

NEXT STEPS
----------
To convert winget export to GWIG format:
  .\Convert-WingetExport.ps1 -InputFile "$wingetOutput" -MergeWithExisting

To merge into existing GWIG config:
  Copy compatible packages from 'installed-apps-winget.json' to 'Config/winget-packages.json'

================================================================================
"@
    $report | Set-Content $reportOutput -Encoding UTF8
    Write-Host "    Saved: $reportOutput" -ForegroundColor Green
}

Write-Host "`nScan complete! Results saved to: $OutputPath" -ForegroundColor Cyan
Write-Host "`nNext steps:" -ForegroundColor Yellow
Write-Host "  1. Review: installed-apps-winget.json" -ForegroundColor White
Write-Host "  2. Merge into: Config/winget-packages.json" -ForegroundColor White
Write-Host "  3. For custom installers: see installed-apps-win32.json" -ForegroundColor White
Write-Host ""

#endregion
