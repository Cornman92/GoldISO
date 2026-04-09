#Requires -Version 5.1
<#
.SYNOPSIS
    Converts winget export JSON to GWIG-compatible winget-packages.json format.

.DESCRIPTION
    Takes a winget export file and converts it to the structured format used by
    GoldISO's winget-packages.json. Supports:
    - Auto-categorization based on app name patterns
    - Merging with existing GWIG configuration
    - Install path assignment per category
    - Optional flagging for non-essential apps

.PARAMETER InputFile
    Path to the winget export JSON file.

.PARAMETER OutputFile
    Path for the output JSON. Default: winget-packages-converted.json

.PARAMETER MergeWithExisting
    Merge with existing Config/winget-packages.json instead of creating new.

.PARAMETER ExistingConfigPath
    Path to existing winget-packages.json. Default: ..\..\Config\winget-packages.json

.PARAMETER AutoCategorize
    Automatically categorize apps based on name patterns.

.PARAMETER CategoryInstallPaths
    Hashtable of category -> install path mappings.

.EXAMPLE
    .\Convert-WingetExport.ps1 -InputFile "my-winget-apps.json" -AutoCategorize

.EXAMPLE
    .\Convert-WingetExport.ps1 -InputFile "my-winget-apps.json" -MergeWithExisting

.NOTES
    FileName: Convert-WingetExport.ps1
    Author: GoldISO Project
    Created: 2026
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$InputFile,
    
    [string]$OutputFile = "winget-packages-converted.json",
    
    [switch]$MergeWithExisting,
    
    [string]$ExistingConfigPath = "",
    
    [switch]$AutoCategorize,
    
    [hashtable]$CategoryInstallPaths = @{
        'browsers'    = 'C:\Program Files'
        'dev_tools'   = 'C:\Dev'
        'gaming'      = 'C:\Gaming'
        'media'       = 'C:\Media'
        'utilities'   = 'C:\Utils'
        'remote'      = 'C:\Remote'
        'productivity'= 'C:\Program Files'
        'uncategorized' = 'C:\Program Files'
    }
)

$ErrorActionPreference = "Stop"

if (Test-Path (Join-Path $PSScriptRoot "..\Modules\GoldISO-Common.psm1")) {
    Import-Module (Join-Path $PSScriptRoot "..\Modules\GoldISO-Common.psm1") -Force
}

#region Configuration

# Category detection patterns
$CategoryPatterns = @{
    'browsers' = @{
        patterns = @('Chrome', 'Firefox', 'Edge', 'Opera', 'Brave', 'Vivaldi', 'Safari', 'Chromium', 'TorBrowser')
        description = 'Web browsers'
    }
    'dev_tools' = @{
        patterns = @(
            'VisualStudio', 'VSCode', 'Code', 'Git', 'GitHub', 'Python', 'Node', 'npm', 'yarn', 'pnpm',
            'Docker', 'Kubernetes', 'kubectl', 'Helm', 'IntelliJ', 'WebStorm', 'PyCharm', 'Eclipse',
            'Sublime', 'Vim', 'Neovim', 'Cursor', 'Windsurf', 'DevToys', 'Postman', 'Insomnia',
            'Go', 'Golang', 'Rust', 'Cargo', 'Ruby', 'JRuby', 'PHP', 'Composer', 'Java', 'JDK', 'JRE',
            'Maven', 'Gradle', 'Ant', 'SDK', 'CMake', 'Ninja', 'MSYS', 'MinGW', 'Cygwin',
            'PowerShell', 'PWSH', 'WindowsTerminal', 'Windows Terminal', 'OhMyPosh', 'Oh-My-Posh', 'zoxide',
            'Fiddler', 'Wireshark', 'Nmap', 'Putty', 'WinSCP', 'FileZilla', 'MobaXterm',
            'SQLServer', 'MySQL', 'PostgreSQL', 'MongoDB', 'Redis', 'SQLite', 'DBeaver'
        )
        description = 'Development tools and runtimes'
    }
    'gaming' = @{
        patterns = @(
            'Steam', 'EpicGames', 'Epic Games', 'GOG', 'Galaxy', 'Battle.net', 'Blizzard',
            'Ubisoft', 'Connect', 'EA', 'EADesktop', 'Origin', 'Xbox', 'GameBar',
            'Discord', 'Teamspeak', 'Mumble', 'Ventrilo', 'CurseForge', 'Overwolf',
            'GeForce', 'NVIDIA', 'AMD', 'MSI Afterburner', 'RTSS', 'OBS Studio', 'Streamlabs',
            'Twitch', 'Rainmeter', 'WallpaperEngine', 'NexusMods', 'Vortex', 'ModOrganizer'
        )
        description = 'Game launchers and gaming platforms'
    }
    'media' = @{
        patterns = @(
            'VLC', 'Spotify', 'iTunes', 'Music', 'Winamp', 'foobar2000', 'Audacious',
            'Plex', 'Kodi', 'Jellyfin', 'Emby', 'MediaServer', 'PlexMediaServer',
            'HandBrake', 'MakeMKV', 'DVDFab', 'Makemkv', 'ffmpeg', 'FFmpeg',
            'Audacity', 'Reaper', 'FLStudio', 'Ableton', 'Bitwig', 'Cubase', 'Reason',
            'Adobe Premiere', 'Premiere Pro', 'After Effects', 'DaVinci Resolve', 'Resolve', 'Final Cut',
            'Adobe Photoshop', 'Photoshop', 'Lightroom', 'GIMP', 'Krita', 'Paint.NET', 'Affinity',
            'Blender', 'Maya', '3dsMax', '3ds Max', 'Cinema4D', 'Cinema 4D', 'Houdini', 'ZBrush',
            'Capture One', 'Darktable', 'RawTherapee', 'LightZone', 'digiKam'
        )
        description = 'Media playback, recording, and streaming'
    }
    'utilities' = @{
        patterns = @(
            '7zip', '7-Zip', 'WinRAR', 'PeaZip', 'Bandizip', 'NanaZip',
            'Everything', 'Listary', 'Wox', 'Keypirinha', 'Launchy', 'FlowLauncher', 'Albert',
            'Notepad++', 'NotepadPlusPlus', 'Sublime Text', 'UltraEdit', 'EmEditor',
            'CPU-Z', 'GPU-Z', 'HWiNFO', 'HWMonitor', 'AIDA64', 'Speccy', 'Core Temp',
            'CrystalDisk', 'DiskInfo', 'DiskMark', 'AS SSD', 'HD Tune',
            'PowerToys', 'Sysinternals', 'ProcessExplorer', 'AutoRuns', 'TCPView',
            'CCleaner', 'BleachBit', 'WiseDiskCleaner', 'Glary Utilities',
            'Teracopy', 'FastCopy', 'RichCopy', 'Robocopy GUI',
            'Directory Opus', 'Total Commander', 'Double Commander', 'One Commander',
            'f.lux', 'LightBulb', 'Lightshot', 'ShareX', 'Greenshot', 'Snipping Tool',
            'AutoHotkey', 'AutoIt', 'Macro', 'TinyTask', 'Pulover Macro Creator',
            'Rufus', 'Ventoy', 'Etcher', 'UNetbootin', 'YUMI',
            'Rainmeter', 'Samurize', 'XWidget', '8GadgetPack',
            'Logitech', 'Razer', 'Corsair', 'SteelSeries', 'Roccat', 'ASUS Armoury'
        )
        description = 'System utilities, archivers, and productivity tools'
    }
    'remote' = @{
        patterns = @(
            'AnyDesk', 'TeamViewer', 'Chrome Remote', 'Splashtop', 'LogMeIn',
            'Parsec', 'Sunshine', 'Moonlight', 'Steam Link', 'AMD Link',
            'ZeroTier', 'Tailscale', 'Headscale', 'WireGuard', 'OpenVPN', 'Pritunl',
            'Radmin', 'Remote Desktop', 'mRemoteNG', 'Terminals', 'RoyalTS',
            'PuTTY', 'KiTTY', 'MobaXterm', 'Tabby', 'Hyper', 'Alacritty', 'WezTerm'
        )
        description = 'Remote desktop and VPN tools'
    }
    'productivity' = @{
        patterns = @(
            'Office', 'Microsoft 365', 'LibreOffice', 'OpenOffice', 'OnlyOffice', 'WPS Office',
            'Notion', 'Evernote', 'OneNote', 'Obsidian', 'Joplin', 'Logseq', 'RemNote',
            'Todoist', 'TickTick', 'Microsoft To Do', 'Any.do', 'Things', 'OmniFocus',
            'Slack', 'Teams', 'Zoom', 'Webex', 'Google Meet', 'Jitsi',
            'Trello', 'Asana', 'Monday', 'ClickUp', 'Notion', 'Linear', 'Jira'
        )
        description = 'Productivity and office applications'
    }
}

#endregion

#region Helper Functions

function Get-AppCategory {
    param([string]$PackageId)
    
    # Extract app name from PackageId (Vendor.AppName format)
    $parts = $PackageId -split '\.'
    $appName = if ($parts.Count -gt 1) { $parts[1] } else { $parts[0] }
    $fullName = $PackageId -replace '\.', ''
    
    foreach ($category in $CategoryPatterns.Keys) {
        foreach ($pattern in $CategoryPatterns[$category].patterns) {
            if ($appName -like "*$pattern*" -or $fullName -like "*$pattern*") {
                return $category
            }
        }
    }
    
    return 'uncategorized'
}

function Get-CategoryDescription {
    param([string]$Category)
    
    if ($CategoryPatterns.ContainsKey($Category)) {
        return $CategoryPatterns[$Category].description
    }
    return 'Uncategorized applications'
}

function Import-WingetExport {
    param([string]$Path)
    
    if (-not (Test-Path $Path)) {
        throw "Input file not found: $Path"
    }
    
    $content = Get-Content $Path -Raw -Encoding UTF8 | ConvertFrom-Json
    
    # Handle both winget native export format and our scan format
if ($content.Sources) {
        if ($content.Categories) {
            # GWIG format (from Scan-InstalledApps)
            return $content.Sources[0].Packages | ForEach-Object {
                [PSCustomObject]@{
                    PackageIdentifier = $_.PackageIdentifier
                    Version = $null
                    Source = 'winget'
                    Category = $_.Category
                    Notes = $_.Notes
                }
            }
        }

        # winget native format
        $packages = @()
        foreach ($source in $content.Sources) {
            foreach ($pkg in $source.Packages) {
                $packages += [PSCustomObject]@{
                    PackageIdentifier = $pkg.PackageIdentifier
                    Version = $pkg.Version
                    Source = if ($source.SourceDetails) { $source.SourceDetails.Name } else { 'winget' }
                }
            }
        }
        return $packages
    }
    else {
        throw "Unknown file format. Expected winget export or GWIG scan output."
    }
}

function Import-ExistingConfig {
    param([string]$Path)
    
    if (-not (Test-Path $Path)) {
        Write-Warning "Existing config not found: $Path"
        return $null
    }
    
    return Get-Content $Path -Raw -Encoding UTF8 | ConvertFrom-Json
}

function Merge-Packages {
    param(
        [array]$ExistingPackages,
        [array]$NewPackages
    )
    
    $merged = [System.Collections.Generic.List[object]]::new()
    $seenIds = [System.Collections.Generic.HashSet[string]]::new()
    
    # Add existing packages first
    foreach ($pkg in $ExistingPackages) {
        $id = if ($pkg.PackageIdentifier) { $pkg.PackageIdentifier } else { $pkg.packageIdentifier }
        if ($id -and $seenIds.Add($id)) {
            $merged.Add($pkg)
        }
    }
    
    # Add new packages
    foreach ($pkg in $NewPackages) {
        $id = $pkg.PackageIdentifier
        if ($id -and $seenIds.Add($id)) {
            $merged.Add($pkg)
        }
    }
    
    return $merged | Sort-Object { $_.PackageIdentifier }
}

#endregion

#region Main Execution

# Resolve paths
$InputFile = Resolve-Path $InputFile -ErrorAction Stop | Select-Object -ExpandProperty Path
$OutputFile = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($OutputFile)

# Determine existing config path
if ($MergeWithExisting -and -not $ExistingConfigPath) {
    $scriptDir = Split-Path $PSScriptRoot -Parent
    $possiblePaths = @(
        (Join-Path $scriptDir "..\Config\winget-packages.json"),
        (Join-Path $scriptDir "..\..\Config\winget-packages.json"),
        (Join-Path (Get-Location) "Config\winget-packages.json")
    )
    
    foreach ($path in $possiblePaths) {
        $resolved = Resolve-Path $path -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Path
        if ($resolved -and (Test-Path $resolved)) {
            $ExistingConfigPath = $resolved
            break
        }
    }
    
    if (-not $ExistingConfigPath) {
        throw "Could not find existing Config/winget-packages.json. Specify -ExistingConfigPath explicitly."
    }
}

Write-Host "`nConverting winget export to GWIG format..." -ForegroundColor Cyan
Write-Host "Input: $InputFile" -ForegroundColor Gray

# Import winget packages
$importedPackages = Import-WingetExport -Path $InputFile
Write-Host "Imported $($importedPackages.Count) packages from export" -ForegroundColor White

# Convert to GWIG format with categorization
$gwigPackages = foreach ($pkg in $importedPackages) {
    $category = if ($AutoCategorize -or -not $pkg.Category) { 
        Get-AppCategory -PackageId $pkg.PackageIdentifier 
    } else { 
        $pkg.Category 
    }
    
    $notes = if ($pkg.Notes) { 
        $pkg.Notes 
    } elseif ($pkg.Version) { 
        "Version: $($pkg.Version)" 
    } else { 
        "Converted from winget export" 
    }
    
    [PSCustomObject]@{
        PackageIdentifier = $pkg.PackageIdentifier
        Category = $category
        Notes = $notes
        Optional = $true
    }
}

# Determine categories present
$presentCategories = $gwigPackages | Group-Object Category | Select-Object -ExpandProperty Name

# Build categories configuration
$categoriesConfig = foreach ($cat in $presentCategories) {
    $installPath = if ($CategoryInstallPaths.ContainsKey($cat)) { 
        $CategoryInstallPaths[$cat] 
    } else { 
        'C:\Program Files' 
    }
    
    [PSCustomObject]@{
        Name = $cat
        Description = Get-CategoryDescription -Category $cat
        InstallPath = $installPath
    }
}

# Sort categories in preferred order
$categoryOrder = @('browsers', 'dev_tools', 'gaming', 'media', 'utilities', 'remote', 'productivity', 'uncategorized')
$sortedCategories = $categoriesConfig | Sort-Object { 
    $index = $categoryOrder.IndexOf($_.Name)
    if ($index -eq -1) { 999 } else { $index }
}

# Build final manifest
$manifest = $null

if ($MergeWithExisting -and $ExistingConfigPath) {
    Write-Host "Merging with existing config: $ExistingConfigPath" -ForegroundColor Yellow
    
    $existing = Import-ExistingConfig -Path $ExistingConfigPath
    if ($existing) {
        $existingPackages = $existing.Sources[0].Packages
        $mergedPackages = Merge-Packages -ExistingPackages $existingPackages -NewPackages $gwigPackages
        
        # Merge categories
        $existingCategories = $existing.Categories
        $mergedCategories = @()
        $seenCatNames = [System.Collections.Generic.HashSet[string]]::new()
        
        foreach ($cat in ($existingCategories + $sortedCategories)) {
            if ($seenCatNames.Add($cat.Name)) {
                $mergedCategories += $cat
            }
        }
        
        $manifest = [PSCustomObject]@{
            '$schema' = $existing.'$schema'
            CreationDate = (Get-Date -Format "yyyy-MM-ddTHH:mm:ss.fffffffZ")
            Description = "GamerOS Full Windows image merged with $((($gwigPackages | Measure-Object).Count)) additional packages"
            Categories = $mergedCategories
            Sources = @(
                [PSCustomObject]@{
                    Packages = $mergedPackages
                    SourceDetails = $existing.Sources[0].SourceDetails
                }
            )
            WinGetVersion = $existing.WinGetVersion
        }
        
        Write-Host "Merged into $($mergedPackages.Count) total packages ($($mergedPackages.Count - $existingPackages.Count) new)" -ForegroundColor Green
    }
    else {
        Write-Warning "Failed to load existing config, creating new manifest instead"
        $MergeWithExisting = $false
    }
}

if (-not $MergeWithExisting -or -not $manifest) {
    $manifest = [PSCustomObject]@{
        '$schema' = "https://aka.ms/winget-packages.schema.2.0.json"
        CreationDate = (Get-Date -Format "yyyy-MM-ddTHH:mm:ss.fffffffZ")
        Description = "GamerOS Full Windows image converted from winget export"
        Categories = $sortedCategories
        Sources = @(
            [PSCustomObject]@{
                Packages = ($gwigPackages | Sort-Object Category, PackageIdentifier)
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
}

# Save output
$manifest | ConvertTo-Json -Depth 10 | Set-Content $OutputFile -Encoding UTF8
Write-Host "Output: $OutputFile" -ForegroundColor Green
Write-Host "Total packages: $($manifest.Sources[0].Packages.Count)" -ForegroundColor White

# Print summary by category
Write-Host "`nCategory Summary:" -ForegroundColor Cyan
$manifest.Sources[0].Packages | Group-Object Category | Sort-Object Count -Descending | ForEach-Object {
    Write-Host "  $($_.Count) apps : $($_.Name)" -ForegroundColor Gray
}

# Print action items
Write-Host "`nNext steps:" -ForegroundColor Yellow
if ($MergeWithExisting) {
    Write-Host "  1. Review the merged output: $OutputFile" -ForegroundColor White
    Write-Host "  2. Replace Config/winget-packages.json with the merged version" -ForegroundColor White
    Write-Host "  3. Edit install paths in Categories section if needed" -ForegroundColor White
}
else {
    Write-Host "  1. Review the converted file: $OutputFile" -ForegroundColor White
    Write-Host "  2. Merge packages into Config/winget-packages.json" -ForegroundColor White
    Write-Host "  3. Add categories to Config/winget-packages.json if new ones were created" -ForegroundColor White
}
Write-Host "  4. Run Build-Autounattend.ps1 to regenerate autounattend.xml" -ForegroundColor White
Write-Host ""

#endregion
