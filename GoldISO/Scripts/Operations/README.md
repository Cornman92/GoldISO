# GoldISO App Operations Scripts

Scripts for discovering, converting, and managing installed applications for GWIG (GoldISO Windows Installation Generator) autounattend.xml integration.

## Quick Start

### Option A: winget Export (Quickest - Recommended)

For modern apps available via winget (most browsers, dev tools, utilities):

```powershell
# 1. Export your currently installed winget packages
winget export -o "C:\temp\my-winget-apps.json" --include-versions

# 2. Convert to GWIG format and merge with existing config
.\Convert-WingetExport.ps1 `
    -InputFile "C:\temp\my-winget-apps.json" `
    -MergeWithExisting `
    -AutoCategorize
```

### Option B: Comprehensive System Scan

For all installed apps including those without winget equivalents:

```powershell
# Scan everything (Win32, UWP, winget) with auto-categorization
.\Scan-InstalledApps.ps1 `
    -OutputPath "C:\temp\gwig-scan" `
    -IncludeWinget `
    -Categorize `
    -GenerateReport
```

## Scripts

### Scan-InstalledApps.ps1

Performs comprehensive system scan to discover installed applications.

**What it scans:**
- Win32 apps (Add/Remove Programs registry)
- UWP/Microsoft Store apps
- winget packages (optional, with `-IncludeWinget`)

**Output files:**
| File | Contents |
|------|----------|
| `installed-apps-winget.json` | Apps with winget equivalents (auto-convertible) |
| `installed-apps-win32.json` | Traditional installers requiring manual config |
| `installed-apps-uwp.json` | Microsoft Store apps |
| `installed-apps-full.json` | Complete raw scan data |
| `app-discovery-report.txt` | Human-readable summary report |

**Parameters:**

| Parameter | Description | Default |
|-----------|-------------|---------|
| `-OutputPath` | Directory to save scan results | `C:\temp\gwig-scan` |
| `-IncludeWinget` | Also query winget for package availability | `$false` |
| `-Categorize` | Auto-categorize apps based on name patterns | `$false` |
| `-GenerateReport` | Generate text summary report | `$true` |

**Example:**
```powershell
# Basic scan
.\Scan-InstalledApps.ps1

# Full scan with categorization
.\Scan-InstalledApps.ps1 -OutputPath "D:\my-scan" -IncludeWinget -Categorize
```

### Convert-WingetExport.ps1

Converts winget export JSON to GWIG-compatible `winget-packages.json` format.

**Supported input formats:**
- Native `winget export` output
- `installed-apps-winget.json` from `Scan-InstalledApps.ps1`

**Features:**
- Auto-categorization of packages
- Merging with existing GWIG configuration
- Install path assignment per category
- Duplicate detection and prevention

**Parameters:**

| Parameter | Description | Default |
|-----------|-------------|---------|
| `-InputFile` | **Required.** Path to winget export JSON | - |
| `-OutputFile` | Path for output JSON | `winget-packages-converted.json` |
| `-MergeWithExisting` | Merge with existing `Config/winget-packages.json` | `$false` |
| `-ExistingConfigPath` | Path to existing config (auto-detected if not specified) | - |
| `-AutoCategorize` | Automatically categorize apps | `$false` |

**Example:**
```powershell
# Convert only
.\Convert-WingetExport.ps1 -InputFile "my-apps.json" -AutoCategorize

# Convert and merge with existing
.\Convert-WingetExport.ps1 `
    -InputFile "my-apps.json" `
    -MergeWithExisting `
    -AutoCategorize
```

## Categories

Both scripts auto-categorize apps into these GWIG-compatible categories:

| Category | Typical Apps | Default Install Path |
|----------|-------------|---------------------|
| `browsers` | Chrome, Firefox, Edge, Opera, Brave | `C:\Program Files` |
| `dev_tools` | VS Code, Git, Python, Node, Docker | `C:\Dev` |
| `gaming` | Steam, Epic, GOG, Discord, OBS | `C:\Gaming` |
| `media` | VLC, Spotify, HandBrake, Adobe CC | `C:\Media` |
| `utilities` | 7-Zip, Everything, CPU-Z, PowerToys | `C:\Utils` |
| `remote` | AnyDesk, TeamViewer, Tailscale, Parsec | `C:\Remote` |
| `productivity` | Office, Notion, Slack, Zoom | `C:\Program Files` |
| `uncategorized` | Apps without matching patterns | `C:\Program Files` |

## Workflow

### 1. Discovery Phase

**For winget-available apps (recommended):**
```powershell
winget export -o "C:\temp\my-apps.json"
```

**For complete inventory:**
```powershell
.\Scan-InstalledApps.ps1 -IncludeWinget -Categorize
```

### 2. Conversion Phase

**Merge with existing config:**
```powershell
.\Convert-WingetExport.ps1 `
    -InputFile "C:\temp\my-apps.json" `
    -MergeWithExisting `
    -AutoCategorize
```

### 3. Integration Phase

**Option 1: Replace entire config (if starting fresh)**
```powershell
Copy-Item "winget-packages-converted.json" "..\..\Config\winget-packages.json" -Force
```

**Option 2: Manual selective merge**
1. Open `winget-packages-converted.json`
2. Select desired packages from `Sources[0].Packages`
3. Add to `Config/winget-packages.json` in appropriate category sections
4. Add new categories to the `Categories` array if needed

### 4. Validation Phase

```powershell
# Validate the JSON structure
.\..\Validate-WingetPackages.ps1

# Build the autounattend.xml
.\..\Build-Autounattend.ps1 -Profile "YourProfile"
```

## App Installation in autounattend.xml

GWIG supports two mechanisms for app installation:

### 1. winget-packages.json (Recommended)

For apps available via winget. Add your profile's `firstLogonCommands`:

```json
"firstLogonCommands": [
    "install-winget-apps"
]
```

The build process will generate `FirstLogonCommands` in the autounattend.xml that installs packages during first logon.

### 2. Custom Installers (For non-winget apps)

For Win32 apps without winget equivalents:

1. Add installer files to `Installers/` directory
2. Configure in profile's `InstallerManager`:

```json
"installerManager": {
    "installers": [
        {
            "name": "MyCustomApp",
            "fileName": "MyApp-Setup.exe",
            "arguments": "/silent /install",
            "phase": "oobeSystem",
            "installPath": "C:\\Program Files\\MyApp"
        }
    ]
}
```

## Tips

### Finding winget IDs

```powershell
# Search for an app
winget search "visual studio code"

# Show app info
winget show "Microsoft.VisualStudioCode"

# List installed
winget list
```

### Testing winget installation

```powershell
# Test install (dry run with what-if)
winget install Microsoft.VisualStudioCode --what-if

# Actually install
winget install Microsoft.VisualStudioCode
```

### Common Issues

**"winget not recognized"**
- Install App Installer from Microsoft Store
- Or use `Add-AppxPackage` to install winget manually

**"Access denied" during export**
- Run PowerShell as Administrator
- Some apps require admin to read registry info

**Category not found**
- Add custom category to both `Categories` array and package entries
- Or use `uncategorized` as fallback

### Category Assignment Logic

Apps are categorized based on name patterns. Common patterns:

```powershell
# Development
- Contains: VSCode, Git, Python, Node, Docker, VisualStudio
- Category: dev_tools

# Gaming
- Contains: Steam, Epic, Discord, OBS, GeForce
- Category: gaming

# Media
- Contains: VLC, Spotify, Adobe, Blender, Premiere
- Category: media
```

To override auto-categorization, manually edit the output JSON before merging.

## See Also

- `../Build-Autounattend.ps1` - Generate autounattend.xml from configuration
- `../Validate-WingetPackages.ps1` - Validate winget-packages.json
- `../../Config/winget-packages.json` - GWIG app manifest
- `../../Docs/SETTINGS_MIGRATION_README.md` - Complete migration guide
