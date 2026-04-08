# GoldISO / GamerOS — Complete Multi-Phase Implementation Plan

**Document Date**: 2026-04-07
**Target**: Windows 11 25H2 Pro (GamerOS) custom ISO
**Build Machine**: Windows 11 / Server, PowerShell 5.1+, Administrator
**Target Hardware**: 3-disk system — Disk 2 = Samsung NVMe (primary), Disk 0/1 = secondary

---

## Master Execution Overview

The plan is organized into 10 phases executed in strict sequence. Each phase has internal steps that may partially parallelize. The critical path is: Phase 0 → 1 → 2 → 3 → 4 → 5 → 6 → 7 → 8 → 9 → 10. Do not skip phases.

```
Phase 0   Environment Preparation          [BUILD MACHINE]
Phase 1   Pre-Build Validation             [BUILD MACHINE]
Phase 2   ISO Extraction & WIM Mounting    [BUILD MACHINE]
Phase 3   Offline Servicing                [BUILD MACHINE]
Phase 4   Answer File & Script Injection   [BUILD MACHINE]
Phase 5   WIM Finalization & ISO Rebuild   [BUILD MACHINE]
Phase 6   ISO Verification                 [BUILD MACHINE]
Phase 7   VM Testing                       [HYPER-V HOST]
Phase 8   Bare-Metal Deployment            [TARGET MACHINE]
Phase 9   Post-Install Configuration       [TARGET MACHINE]
Phase 10  Audit / Capture Workflows        [CONDITIONAL]
```

---

## Phase 0 — Environment Preparation

**Risk Level**: Medium
**Prerequisite**: None — this is the starting point
**Parallelism**: Steps 0.1–0.5 can be verified in parallel; 0.6 must follow 0.5

### 0.1 — Confirm Build Machine Requirements

Verify the machine you will build on meets all prerequisites before touching any scripts.

```powershell
# Run as Administrator in PowerShell 5.1 or 7.x
# Check OS version (must be Windows 10/11 or Server 2019+)
[System.Environment]::OSVersion.VersionString
(Get-CimInstance Win32_OperatingSystem).Caption

# Check PowerShell version (must be 5.1+)
$PSVersionTable.PSVersion

# Check available disk space — C: must have at LEAST 50 GB free
# The build process needs:
#   ~8 GB for source ISO copy
#   ~8 GB for WIM mount (C:\Mount)
#   ~8 GB for working directory (C:\GoldISO_Build)
#   ~8 GB for exported WIM files
#   ~5 GB buffer for temp operations
#   Total minimum: ~37 GB; 50 GB strongly recommended
$drive = Get-PSDrive C
Write-Host "Free: $([math]::Round($drive.Free / 1GB, 1)) GB of $([math]::Round(($drive.Used + $drive.Free) / 1GB, 1)) GB"

# Check admin rights
([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
    [Security.Principal.WindowsBuiltInRole]::Administrator
)
# Must return: True
```

**What to check**: All four must pass. If OS is too old, DISM features won't work. If space is too low, the export step will fail mid-operation, leaving orphaned WIM mounts that are difficult to clean.

**Failure recovery**: Free disk space by removing `C:\GoldISO_Build` and `C:\Mount` if they exist from a prior failed build:
```powershell
# Emergency cleanup of stale mounts
Dismount-WindowsImage -Path "C:\Mount" -Discard -ErrorAction SilentlyContinue
Dismount-WindowsImage -Path "C:\Mnt" -Discard -ErrorAction SilentlyContinue
Remove-Item "C:\GoldISO_Build" -Recurse -Force -ErrorAction SilentlyContinue
```

### 0.2 — Install Windows ADK (for oscdimg)

oscdimg is the tool that creates the final bootable ISO. Without it the build completes but you cannot produce the `.iso` file.

```powershell
# Check if already installed
$oscdimg = Get-Command oscdimg -ErrorAction SilentlyContinue
if ($oscdimg) {
    Write-Host "oscdimg found: $($oscdimg.Source)"
} else {
    # Search common ADK install paths
    $adkPaths = @(
        "${env:ProgramFiles(x86)}\Windows Kits\10\Assessment and Deployment Kit\Deployment Tools\amd64\Oscdimg\oscdimg.exe",
        "${env:ProgramFiles(x86)}\Windows Kits\10\bin\10.0.22621.0\x64\oscdimg.exe",
        "${env:ProgramFiles(x86)}\Windows Kits\10\bin\10.0.26100.0\x64\oscdimg.exe"
    )
    foreach ($p in $adkPaths) {
        if (Test-Path $p) { Write-Host "Found (not in PATH): $p"; break }
    }
}
```

If not found, download the Windows ADK for Windows 11 25H2 from Microsoft:
`https://go.microsoft.com/fwlink/?linkid=2289930`

Install with ONLY "Deployment Tools" checked (no other features needed). Then add to PATH:

```powershell
# After ADK install, add oscdimg to the system PATH permanently
$adkPath = "${env:ProgramFiles(x86)}\Windows Kits\10\Assessment and Deployment Kit\Deployment Tools\amd64\Oscdimg"
$currentPath = [Environment]::GetEnvironmentVariable("PATH", "Machine")
if ($currentPath -notlike "*Oscdimg*") {
    [Environment]::SetEnvironmentVariable("PATH", "$currentPath;$adkPath", "Machine")
    # Reload PATH in current session
    $env:PATH = "$env:PATH;$adkPath"
    Write-Host "oscdimg added to PATH"
} else {
    Write-Host "ADK already in PATH"
}

# Verify
oscdimg /?
# Should print usage without error
```

**Failure recovery**: If the installer fails, you can xcopy just the oscdimg binary from another machine or use the Deployment Tools ISO from ADK separately.

### 0.3 — Verify Source ISO Integrity

The source ISO must be the exact file `Win11-25H2x64v2.iso` (or `Win11_25H2_English_x64_v2.iso` as named in AGENTS.md). Note: Build-GoldISO.ps1 looks for `Win11-25H2x64v2.iso` (hyphenated) at the project root.

```powershell
$isoPath = "C:\Users\C-Man\GoldISO\Win11-25H2x64v2.iso"

# Verify it exists
if (-not (Test-Path $isoPath)) {
    Write-Error "Source ISO not found: $isoPath"
    # If you have Win11_25H2_English_x64_v2.iso instead:
    # Rename-Item "C:\Users\C-Man\GoldISO\Win11_25H2_English_x64_v2.iso" "Win11-25H2x64v2.iso"
} else {
    $iso = Get-Item $isoPath
    Write-Host "ISO found: $($iso.Name)"
    Write-Host "Size: $([math]::Round($iso.Length / 1GB, 2)) GB"
    Write-Host "Modified: $($iso.LastWriteTime)"
}

# Optional: Verify ISO can be mounted
$mounted = Mount-DiskImage -ImagePath $isoPath -PassThru -ErrorAction Stop
$vol = $mounted | Get-Volume
Write-Host "ISO mounts as drive: $($vol.DriveLetter):"

# Verify it contains install.wim and boot files
Test-Path "$($vol.DriveLetter):\sources\install.wim"   # Must be True
Test-Path "$($vol.DriveLetter):\boot\etfsboot.com"     # Must be True
Test-Path "$($vol.DriveLetter):\efi\microsoft\boot\efisys.bin"  # Must be True

# Dismount after check
Dismount-DiskImage -ImagePath $isoPath
```

**What to check**: ISO must be >4 GB, must mount cleanly, must contain `install.wim` with index 6 (Windows 11 Pro). If you get a different index for Pro, you must update the `-Index 6` parameter in Build-GoldISO.ps1.

**Verify WIM index 6 is Pro**:
```powershell
$isoPath = "C:\Users\C-Man\GoldISO\Win11-25H2x64v2.iso"
$mounted = Mount-DiskImage -ImagePath $isoPath -PassThru
$drive = ($mounted | Get-Volume).DriveLetter
Get-WindowsImage -ImagePath "${drive}:\sources\install.wim" | Select-Object ImageIndex, ImageName
# Look for: 6   Windows 11 Pro
Dismount-DiskImage -ImagePath $isoPath
```

### 0.4 — Verify GoldISO Repository Structure

Confirm all required directories and critical files are present before running any build scripts.

```powershell
$root = "C:\Users\C-Man\GoldISO"

# Critical files — ALL must exist
$required = @(
    "$root\Scripts\Build-GoldISO.ps1",
    "$root\Scripts\Test-UnattendXML.ps1",
    "$root\Scripts\Test-Environment.ps1",
    "$root\Scripts\Modules\GoldISO-Common.psm1",
    "$root\Config\autounattend.xml",
    "$root\Config\winget-packages.json"
)

# Strongly recommended — warn if missing
$recommended = @(
    "$root\Scripts\shrink-and-recovery.ps1",
    "$root\Scripts\install-usb-apps.ps1",
    "$root\Scripts\install-ramdisk.ps1",
    "$root\Scripts\Configure-SecondaryDrives.ps1",
    "$root\Scripts\Capture-Image.ps1",
    "$root\Scripts\Apply-Image.ps1",
    "$root\Scripts\New-TestVM.ps1"
)

foreach ($f in $required) {
    if (Test-Path $f) { Write-Host "[OK]   $f" -ForegroundColor Green }
    else              { Write-Host "[FAIL] $f" -ForegroundColor Red }
}

foreach ($f in $recommended) {
    if (Test-Path $f) { Write-Host "[OK]   $f" -ForegroundColor Green }
    else              { Write-Host "[WARN] $f" -ForegroundColor Yellow }
}

# Count drivers
$driverInfs = Get-ChildItem "$root\Drivers" -Recurse -Filter "*.inf" | Measure-Object
Write-Host "Drivers: $($driverInfs.Count) .inf files"

# Count packages
$packages = Get-ChildItem "$root\Packages" -File | Measure-Object
Write-Host "Packages: $($packages.Count) files"
```

**What to check**: Zero [FAIL] results. [WARN] on recommended files is acceptable but means those post-install features won't work.

### 0.5 — Verify Driver Directory Completeness

Cross-reference the driver directories against the injection strategy from AGENTS.md. NVIDIA and Logitech are intentionally NOT injected offline — they must remain in Drivers/ but are only used during FirstLogon.

```powershell
$driverRoot = "C:\Users\C-Man\GoldISO\Drivers"

# Offline-injected categories (must exist)
$offlineCategories = @(
    "System devices",
    "Network adapters",
    "Storage controllers",
    "IDE ATA ATAPI controllers",
    "Extensions",
    "Software components",
    "Sound, video and game controllers",
    "Audio Processing Objects (APOs)",
    "Monitors"
)

# Post-boot only (should exist in Drivers/ but NOT injected offline)
$postBootCategories = @(
    "Display adapters",         # NVIDIA RTX 3060 Ti
    "Universal Serial Bus controllers"  # Logitech G403 HERO
)

foreach ($cat in $offlineCategories) {
    $path = Join-Path $driverRoot $cat
    if (Test-Path $path) {
        $count = (Get-ChildItem $path -Recurse -Filter "*.inf").Count
        Write-Host "[OFFLINE] $cat`: $count drivers" -ForegroundColor Green
    } else {
        Write-Host "[MISSING] $cat" -ForegroundColor Red
    }
}

foreach ($cat in $postBootCategories) {
    $path = Join-Path $driverRoot $cat
    if (Test-Path $path) {
        $count = (Get-ChildItem $path -Recurse -Filter "*.inf").Count
        Write-Host "[POST-BOOT] $cat`: $count drivers (correct - NOT offline injected)" -ForegroundColor Cyan
    }
}
```

**Critical constraint**: Do NOT add `Display adapters` or `Universal Serial Bus controllers` to the `$driverCategories` array in `Build-GoldISO.ps1`. NVIDIA drivers injected offline cause WIM corruption on non-matching hardware and prevent boot on VMs without that GPU.

### 0.6 — Set PowerShell Execution Policy

Required for the build session. This must be set before running any GoldISO scripts.

```powershell
# Verify current policy
Get-ExecutionPolicy
# If not RemoteSigned or Unrestricted:
Set-ExecutionPolicy RemoteSigned -Scope Process -Force
# Or for the machine permanently (use with caution):
Set-ExecutionPolicy RemoteSigned -Scope LocalMachine -Force
```

**Verification checkpoint**: `Get-ExecutionPolicy` returns `RemoteSigned`, `Unrestricted`, or `Bypass`.

---

## Phase 1 — Pre-Build Validation

**Risk Level**: Low
**Prerequisite**: Phase 0 complete
**Parallelism**: Steps 1.1 and 1.2 can run simultaneously in two separate PowerShell windows

### 1.1 — Run Environment Validation Script

This is the automated pre-flight check. Run once per session before any build.

```powershell
# Navigate to project root
Set-Location "C:\Users\C-Man\GoldISO"

# Run environment check
.\Scripts\Test-Environment.ps1

# If oscdimg isn't in PATH, use SkipNetworkCheck variant first:
.\Scripts\Test-Environment.ps1 -SkipNetworkCheck

# Verbose for troubleshooting
.\Scripts\Test-Environment.ps1 -Verbose
```

**What to check**: The script validates:
- PowerShell version (5.1+ required)
- ExecutionPolicy (must not be Restricted)
- Administrator privileges
- DISM availability
- .NET Framework 3.5 (warning if missing — installed offline during build)
- oscdimg in PATH (FAIL if missing — ISO rebuild won't work)
- bcdboot availability
- C: drive free space (WARN under 50 GB, FAIL under 20 GB)
- Network connectivity (warning only — offline builds still work)
- GoldISO root directory and critical files

**Expected outcome**: All PASSes and at most minor WARNings. Any FAIL must be resolved before proceeding.

**Log location**: `C:\Users\C-Man\GoldISO\Scripts\Logs\Test-Environment-YYYYMMDD-HHmmss.log`

**Common failures and fixes**:

| Failure | Fix |
|---|---|
| `oscdimg not found` | Install ADK Deployment Tools, add to PATH (see Phase 0.2) |
| `Administrator privileges required` | Close PowerShell, right-click → Run as Administrator |
| `C: drive has only Xgb free` | Delete `C:\GoldISO_Build` and `C:\Mount` if stale; clear temp files |
| `Source ISO not found` | Verify `Win11-25H2x64v2.iso` exists at project root with correct hyphenated name |

### 1.2 — Run Answer File Validation

Run before EVERY build. The autounattend.xml is 1MB+ and complex; errors here cause silent install failures hours later.

```powershell
Set-Location "C:\Users\C-Man\GoldISO"

# Standard validation (50+ checks)
.\Scripts\Test-UnattendXML.ps1

# Verbose mode — shows each individual check
.\Scripts\Test-UnattendXML.ps1 -Verbose

# Strict mode — warnings become errors
.\Scripts\Test-UnattendXML.ps1 -Strict

# Against a non-default answer file (e.g., after editing)
.\Scripts\Test-UnattendXML.ps1 -AnswerFile "C:\Users\C-Man\GoldISO\Config\autounattend.xml"
```

**What the validator checks**:
1. XML is well-formed (parseable)
2. Required components present: `Microsoft-Windows-International-Core` (windowsPE), `Microsoft-Windows-Setup` (windowsPE), `Microsoft-Windows-Shell-Setup` (oobeSystem/specialize)
3. Disk 2 is configured in DiskConfiguration
4. Disks 0 and 1 are NOT assigned partitions (wiped only)
5. RunSynchronous orders are unique within each pass (no duplicates)
6. FirstLogonCommands are sequential (no gaps or duplicates in order numbers)
7. No Win11 bypass commands (TPM, SecureBoot, Storage, CPU, RAM, Disk)
8. References to `shrink-and-recovery` and `install-usb-apps` are present
9. PowerShell profile deployment command is present
10. `<Extensions>` section exists with embedded scripts
11. Driver directory exists with .inf files
12. Packages directory exists

**Expected outcome**: "PASSED - Ready to build" or "PASSED WITH WARNINGS - Review before building"

**Log location**: `C:\Users\C-Man\GoldISO\Scripts\Logs\Test-UnattendXML-YYYYMMDD-HHmmss.log`

**Critical failure — XML not parseable**: Open `Config\autounattend.xml` in VS Code with the XML extension; it will highlight the exact line and column of the syntax error. Fix, then re-validate.

**Common warnings (acceptable)**:
- "Portable apps copy command not found" — only needed if you have portable apps
- "OOBE network disable configuration not found" — verify by searching XML for `OfflineUserMachine` or `HideWirelessSetupInOOBE`

### 1.3 — Manual Pre-Build Inventory Check

Before spending 45-90 minutes on a build, visually confirm the key assets are current.

```powershell
$root = "C:\Users\C-Man\GoldISO"

# Show packages with dates — identify stale packages
Get-ChildItem "$root\Packages" -File | Sort-Object LastWriteTime -Descending |
    Select-Object Name, @{N="SizeMB";E={[math]::Round($_.Length/1MB,1)}}, LastWriteTime |
    Format-Table -AutoSize

# Show autounattend.xml last edit time
(Get-Item "$root\Config\autounattend.xml").LastWriteTime

# Show FirstLogonCommands count (should be 43)
[xml]$xml = Get-Content "$root\Config\autounattend.xml" -Raw
$oobe = $xml.unattend.settings | Where-Object { $_.Pass -eq "oobeSystem" }
$cmds = $oobe.Component.FirstLogonCommands.SynchronousCommand
Write-Host "FirstLogonCommands: $($cmds.Count)"

# Show specialize RunSynchronous count
$spec = $xml.unattend.settings | Where-Object { $_.Pass -eq "specialize" }
$specCmds = $spec.Component.RunSynchronous.RunSynchronousCommand
Write-Host "Specialize RunSynchronous: $($specCmds.Count)"
```

---

## Phase 2 — ISO Extraction and WIM Mounting

**Risk Level**: Low (the build script handles this)
**Prerequisite**: Phase 1 complete, all validations passed
**Parallelism**: Strictly sequential — each step depends on the prior

This phase is entirely automated by `Build-GoldISO.ps1`. The manual commands below explain what happens under the hood and are used for recovery/debugging.

### 2.1 — Launch the Build Script

```powershell
Set-Location "C:\Users\C-Man\GoldISO"

# Standard build (most common)
.\Scripts\Build-GoldISO.ps1

# With verbose output (recommended for first-time builds)
.\Scripts\Build-GoldISO.ps1 -Verbose

# For testing — skip drivers and packages (fast, for XML/ISO structure testing only)
.\Scripts\Build-GoldISO.ps1 -SkipDriverInjection -SkipPackageInjection -Verbose

# Custom output location
.\Scripts\Build-GoldISO.ps1 -OutputISO "D:\ISOs\GamerOS_Win11_25H2.iso"
```

**Build log**: `C:\GoldISO_Build\build.log` — this is the authoritative log for the entire build operation.

### 2.2 — ISO Mounting (Automated — Understanding Only)

The script performs these steps internally:

```powershell
# WHAT THE SCRIPT DOES — do not run manually unless recovering
$isoPath = "C:\Users\C-Man\GoldISO\Win11-25H2x64v2.iso"

# Mount ISO as a virtual drive
$image = Mount-DiskImage -ImagePath $isoPath -PassThru -ErrorAction Stop
$driveLetter = ($image | Get-Volume).DriveLetter
Write-Host "ISO mounted at: ${driveLetter}:"
# Example: ISO mounted at: D:

# Verify boot files exist
Test-Path "${driveLetter}:\boot\etfsboot.com"
Test-Path "${driveLetter}:\efi\microsoft\boot\efisys.bin"
Test-Path "${driveLetter}:\sources\install.wim"
```

### 2.3 — ISO Content Copy (Automated — Understanding Only)

```powershell
# WHAT THE SCRIPT DOES — do not run manually unless recovering
$workDir = "C:\GoldISO_Build"
$isoContentsDir = "$workDir\ISO"

# Create working directory
New-Item -ItemType Directory -Path $workDir -Force | Out-Null
New-Item -ItemType Directory -Path $isoContentsDir -Force | Out-Null

# Robocopy preserves all attributes including hidden/system files
# /E = all subdirectories including empty ones
# /R:3 = retry 3 times on failure
# /W:5 = wait 5 seconds between retries
robocopy "${driveLetter}:\" "$isoContentsDir" /E /R:3 /W:5

# Verify copy succeeded — install.wim is the critical check
if (-not (Test-Path "$isoContentsDir\sources\install.wim")) {
    throw "install.wim not found after copy — aborting"
}

# Dismount source ISO (no longer needed)
Dismount-DiskImage -ImagePath $isoPath
```

**What to check after copy**:
- `$isoContentsDir\sources\install.wim` exists
- `$isoContentsDir\boot\etfsboot.com` exists
- `$isoContentsDir\efi\microsoft\boot\efisys.bin` exists
- Total size of `$isoContentsDir` should be approximately the same as the source ISO (typically 5-7 GB before servicing)

**Estimated time**: 2-8 minutes depending on disk speed

### 2.4 — WIM Index Selection and Mounting (Automated — Understanding Only)

```powershell
# WHAT THE SCRIPT DOES — do not run manually unless recovering
$wimPath = "C:\GoldISO_Build\ISO\sources\install.wim"
$mountDir = "C:\Mount"

# First, enumerate all indexes to confirm index 6 = Windows 11 Pro
Get-WindowsImage -ImagePath $wimPath |
    Select-Object ImageIndex, ImageName, ImageDescription |
    Format-Table -AutoSize
# Expected output includes:
# 6   Windows 11 Pro   Windows 11 Pro

# Create mount directory
New-Item -ItemType Directory -Path $mountDir -Force | Out-Null

# Mount index 6 (Windows 11 Pro) for read/write servicing
Mount-WindowsImage -ImagePath $wimPath -Path $mountDir -Index 6 -ErrorAction Stop
# This operation takes 2-10 minutes

# Verify mount
Get-WindowsImage -Mounted | Format-Table MountPath, ImagePath, MountStatus
# MountStatus should be: Ok
```

**Critical**: The mount operation makes the WIM read-write. If the build machine loses power while the WIM is mounted, you will have a corrupted WIM mount. Recovery: `Dism /Cleanup-Mountpoints` followed by `Dismount-WindowsImage -Path "C:\Mount" -Discard`.

**Estimated time**: 3-10 minutes (WIM decompression and mounting)

**Failure modes**:

| Error | Cause | Fix |
|---|---|---|
| "The image is already mounted" | Previous failed build | `Dismount-WindowsImage -Path "C:\Mount" -Discard` |
| "Access denied" | Not running as Administrator | Restart as admin |
| "Invalid image index" | Index 6 doesn't exist in this ISO | Run `Get-WindowsImage -ImagePath` to find correct Pro index |
| "Not enough space" | C: drive too full | Clear 20+ GB from C: |

---

## Phase 3 — Offline Servicing

**Risk Level**: Medium (driver conflicts possible; package obsolescence expected)
**Prerequisite**: WIM mounted at C:\Mount (Phase 2 complete)
**Parallelism**: Driver injection and package injection are conceptually independent but the build script runs them sequentially by design. Do NOT attempt to parallelize these — DISM operations on a single mounted image are not thread-safe.

### 3.1 — Driver Injection (Offline)

This injects all specified driver categories into the offline WIM. Drivers are installed into the image's driver store, not executed — they become available to the OS during its first boot's plug-and-play phase.

```powershell
# MANUAL EQUIVALENT of what Build-GoldISO.ps1 does
$mountDir = "C:\Mount"
$driverRoot = "C:\Users\C-Man\GoldISO\Drivers"

# Categories to inject offline (do NOT add Display adapters or USB controllers)
$offlineCategories = @(
    "System devices",
    "Network adapters",
    "Storage controllers",
    "IDE ATA ATAPI controllers",
    "Extensions",
    "Software components",
    "Sound, video and game controllers",
    "Audio Processing Objects (APOs)",
    "Monitors"
)

foreach ($category in $offlineCategories) {
    $catPath = Join-Path $driverRoot $category
    if (-not (Test-Path $catPath)) {
        Write-Warning "Category not found, skipping: $category"
        continue
    }

    $infCount = (Get-ChildItem $catPath -Recurse -Filter "*.inf").Count
    Write-Host "Injecting [$category] — $infCount .inf files..."

    # /ForceUnsigned allows unsigned drivers (required for some OEM drivers)
    # /Recurse searches all subdirectories
    dism /Image:"$mountDir" /Add-Driver /Driver:"$catPath" /Recurse /ForceUnsigned
    # Exit code 0 = success, 50 = some drivers failed (non-fatal), others = hard failure

    if ($LASTEXITCODE -eq 0) {
        Write-Host "  [OK] $category" -ForegroundColor Green
    } elseif ($LASTEXITCODE -eq 50) {
        Write-Warning "  [PARTIAL] $category — some drivers skipped (architecture mismatch or dependency issues)"
    } else {
        Write-Error "  [FAIL] $category — exit code $LASTEXITCODE"
    }
}

# Verify drivers were added
dism /Image:"$mountDir" /Get-Drivers /Format:Table
# Review the list — look for your expected drivers
```

**Alternative — single recursive call across all driver subdirectories** (simpler but less granular logging):
```powershell
# Add ALL drivers recursively (except post-boot categories — move those out first or use category list above)
Add-WindowsDriver -Path $mountDir -Driver $driverRoot -Recurse -ErrorAction SilentlyContinue
```

**What to check after driver injection**:
```powershell
# List all injected drivers — look for expected vendors (Intel, ASUS, network, audio, monitor)
dism /Image:"$mountDir" /Get-Drivers /Format:Table | Select-String -Pattern "Published Name|Provider Name" | Select-Object -First 40

# Or using PowerShell
Get-WindowsDriver -Path $mountDir | Where-Object { $_.ProviderName -match "Intel|ASUS|Realtek|network" } |
    Select-Object ProviderName, Driver, Date | Format-Table -AutoSize
```

**Common failure modes**:

| Issue | Cause | Recovery |
|---|---|---|
| Architecture mismatch | 32-bit driver in x64 image | Normal — logged as warning, ignored |
| Driver fails signature check | Driver not signed (rare for system drivers) | `/ForceUnsigned` overrides this |
| Dependency not found | Extension driver missing prerequisite | Ensure base driver category is in the image |
| DISM error 0x800f0226 | Driver inf has syntax error | Remove problematic driver, retry |

**Estimated time**: 5-20 minutes depending on number of drivers

### 3.2 — Windows Update Package Injection (.msu and .cab)

```powershell
$mountDir = "C:\Mount"
$packagesDir = "C:\Users\C-Man\GoldISO\Packages"

# Current packages in Packages/ as of 2026-04-07:
# - windows11.0-kb5043080-x64_... .msu   (Cumulative Update)
# - windows11.0-kb5066128-x64-ndp481_... .msu  (.NET 4.8.1 update)
# - windows11.0-kb5067931-x64-ndp481_... .msu  (.NET 4.8.1 update)
# - windows11.0-kb5068516-x64_... .cab   (CAB package)
# - windows11.0-kb5074828-x64-ndp481_... .msu  (.NET 4.8.1 update)
# - windows11.0-kb5079391-x64_... .msu   (Cumulative Update)
# - windows11.0-kb5083482-x64_... .cab   (CAB package)
# - windows11.0-kb5085516-x64_... .msu   (Cumulative Update, likely most recent)

# Inject .msu files (IMPORTANT: inject in KB number order, oldest first)
# Some updates depend on prior ones; ordering matters to avoid dependency errors
$msuFiles = Get-ChildItem $packagesDir -Filter "*.msu" |
    Sort-Object Name  # Sorting by name approximates KB order for sequential KBs

foreach ($msu in $msuFiles) {
    Write-Host "Injecting: $($msu.Name)..."
    try {
        Add-WindowsPackage -Path $mountDir -PackagePath $msu.FullName -NoRestart -ErrorAction Stop
        Write-Host "  [OK]" -ForegroundColor Green
    } catch {
        # Common: "The package is already installed" or "superseded by a newer update"
        # These are NON-FATAL — the script continues gracefully
        Write-Warning "  [SKIP] $($_.Exception.Message)"
    }
}

# Inject .cab files
$cabFiles = Get-ChildItem $packagesDir -Filter "*.cab" | Sort-Object Name
foreach ($cab in $cabFiles) {
    Write-Host "Injecting: $($cab.Name)..."
    try {
        Add-WindowsPackage -Path $mountDir -PackagePath $cab.FullName -NoRestart -ErrorAction Stop
        Write-Host "  [OK]" -ForegroundColor Green
    } catch {
        Write-Warning "  [SKIP] $($_.Exception.Message)"
    }
}
```

**What to check after package injection**:
```powershell
# List all installed packages — look for your KB numbers
dism /Image:"$mountDir" /Get-Packages /Format:Table | Select-String "KB50\d+|KB48\d+"

# Or PowerShell:
Get-WindowsPackage -Path $mountDir |
    Where-Object { $_.PackageName -match "KB" } |
    Select-Object PackageName, PackageState | Format-Table -AutoSize
```

**Important behavior**: The `updateplatform.amd64fre_*.exe` in Packages is an executable, NOT a DISM package. Do NOT attempt to inject it via `Add-WindowsPackage`. It will fail. This file is likely the Windows Update Platform installer that runs post-boot.

**Failure modes**:

| Error Message | Meaning | Action |
|---|---|---|
| "0x800f0823 — package not applicable" | Update is superseded by a newer one already in the WIM | Normal — log and continue |
| "0x800f082f — dependency not installed" | Required prerequisite package missing | Check KB dependencies on Microsoft Update Catalog |
| "0x800f0824 — the package is already installed" | KB already included in base ISO | Normal — skip |
| "0x800f0922 — transaction" | DISM internal error | Restart the machine, re-mount WIM, retry |

### 3.3 — MSIX and APPX Bundle Provisioning

These are provisioned (pre-staged) into the image, meaning they install automatically for every new user account on first sign-in.

```powershell
$mountDir = "C:\Mount"
$packagesDir = "C:\Users\C-Man\GoldISO\Packages"

# Current MSIX/APPX bundles:
# - PowerShell-7.6.0.msixbundle
# - Microsoft.WindowsTerminal_1.24.10621.0_8wekyb3d8bbwe.msixbundle
# - Microsoft.DesktopAppInstaller_8wekyb3d8bbwe.msixbundle
# - Microsoft.WindowsAppRuntime.1.8_8000.616.304.0_x64.appx
# - Microsoft.UI.Xaml.2.8_8.2501.31001.0_x64.appx

# IMPORTANT: Provision in dependency order:
# 1. UI.Xaml (dependency for others)
# 2. WindowsAppRuntime (dependency for Terminal)
# 3. AppInstaller (dependency for winget)
# 4. PowerShell 7
# 5. Windows Terminal

# Step 1: Provision UI.Xaml framework (dependency)
$uiXaml = Get-ChildItem $packagesDir -Filter "Microsoft.UI.Xaml*.appx" | Select-Object -First 1
if ($uiXaml) {
    Write-Host "Provisioning: $($uiXaml.Name)"
    Add-AppxProvisionedPackage -Path $mountDir -PackagePath $uiXaml.FullName -SkipLicense -ErrorAction SilentlyContinue
}

# Step 2: Provision WindowsAppRuntime (dependency)
$appRuntime = Get-ChildItem $packagesDir -Filter "Microsoft.WindowsAppRuntime*.appx" | Select-Object -First 1
if ($appRuntime) {
    Write-Host "Provisioning: $($appRuntime.Name)"
    Add-AppxProvisionedPackage -Path $mountDir -PackagePath $appRuntime.FullName -SkipLicense -ErrorAction SilentlyContinue
}

# Step 3: Provision AppInstaller (winget)
$appInstaller = Get-ChildItem $packagesDir -Filter "Microsoft.DesktopAppInstaller*.msixbundle" | Select-Object -First 1
if ($appInstaller) {
    Write-Host "Provisioning: $($appInstaller.Name)"
    Add-AppxProvisionedPackage -Path $mountDir -PackagePath $appInstaller.FullName -SkipLicense -ErrorAction SilentlyContinue
}

# Step 4: Provision PowerShell 7
$ps7 = Get-ChildItem $packagesDir -Filter "PowerShell-7*.msixbundle" | Select-Object -First 1
if ($ps7) {
    Write-Host "Provisioning: $($ps7.Name)"
    Add-AppxProvisionedPackage -Path $mountDir -PackagePath $ps7.FullName -SkipLicense -ErrorAction SilentlyContinue
}

# Step 5: Provision Windows Terminal
$terminal = Get-ChildItem $packagesDir -Filter "Microsoft.WindowsTerminal*.msixbundle" | Select-Object -First 1
if ($terminal) {
    Write-Host "Provisioning: $($terminal.Name)"
    Add-AppxProvisionedPackage -Path $mountDir -PackagePath $terminal.FullName -SkipLicense -ErrorAction SilentlyContinue
}

# Verify provisioned packages
Get-AppxProvisionedPackage -Path $mountDir |
    Where-Object { $_.DisplayName -match "PowerShell|Terminal|AppInstaller|WindowsRuntime|UI.Xaml" } |
    Select-Object DisplayName, Version | Format-Table -AutoSize
```

**What to check**: All 5 packages should appear in the provisioned package list. If AppInstaller doesn't provision correctly, `winget` won't work during FirstLogon and all `winget install` commands will fail silently.

### 3.4 — Optional: Enable Windows Features Offline

If .NET 3.5 is not in the base image, or if you need to enable specific features:

```powershell
$mountDir = "C:\Mount"
$isoSxsPath = "C:\GoldISO_Build\ISO\sources\sxs"  # Side-by-side store from ISO

# Enable .NET Framework 3.5 offline (no internet required)
# This is referenced in autounattend.xml specialize phase
Enable-WindowsOptionalFeature -Path $mountDir -FeatureName "NetFx3" -Source $isoSxsPath -LimitAccess
# -LimitAccess prevents Windows Update from being used as a source (offline build)

# Verify
Get-WindowsOptionalFeature -Path $mountDir -FeatureName "NetFx3" | Select-Object State
# Should show: Enabled
```

**Note**: The `autounattend.xml` specialize phase also enables .NET 3.5 from `sources\sxs` during installation. Doing it offline here AND in the answer file is redundant but harmless — the specialize command will succeed instantly if already enabled.

---

## Phase 4 — Answer File and Script Injection

**Risk Level**: Low (file copy operations)
**Prerequisite**: Phase 3 complete (offline servicing done)
**Parallelism**: Steps 4.1-4.4 can run in parallel since they operate on different destinations

### 4.1 — Copy autounattend.xml to ISO Root

```powershell
$isoContentsDir = "C:\GoldISO_Build\ISO"
$answerFileSrc = "C:\Users\C-Man\GoldISO\Config\autounattend.xml"

# Primary location (Config/)
if (Test-Path $answerFileSrc) {
    Copy-Item -Path $answerFileSrc -Destination "$isoContentsDir\autounattend.xml" -Force
    Write-Host "Answer file copied to ISO root" -ForegroundColor Green
} else {
    # Fallback: root-level autounattend.xml
    $fallback = "C:\Users\C-Man\GoldISO\autounattend.xml"
    if (Test-Path $fallback) {
        Copy-Item -Path $fallback -Destination "$isoContentsDir\autounattend.xml" -Force
        Write-Host "Answer file copied from fallback location" -ForegroundColor Yellow
    } else {
        throw "autounattend.xml not found in Config/ or project root"
    }
}

# Verify
(Get-Item "$isoContentsDir\autounattend.xml").Length
# Should be ~1 MB or larger
```

**Critical**: The answer file MUST be at the ISO root, not in any subdirectory. Windows Setup looks for `autounattend.xml` in specific locations in order: the root of the installation media (drive root) first. If it's not at the root, the entire unattended installation will fail and Windows Setup will prompt for user input.

### 4.2 — Copy Utility Scripts to ISO Scripts Directory

```powershell
$isoScriptsDir = "C:\GoldISO_Build\ISO\Scripts"
New-Item -ItemType Directory -Path $isoScriptsDir -Force | Out-Null

$scriptRoot = "C:\Users\C-Man\GoldISO\Scripts"

# Scripts to embed in the ISO for use during/after installation
$scriptsToEmbed = @(
    "Capture-Image.ps1",         # WinPE capture tool
    "Apply-Image.ps1",           # WinPE apply tool
    "Audit-Sysprep.ps1",         # Audit mode helper
    "Create-AuditShortcuts.ps1", # Audit shortcuts
    "Configure-SecondaryDrives.ps1"  # Post-install Disk 0/1 partitioning
)

foreach ($script in $scriptsToEmbed) {
    $src = Join-Path $scriptRoot $script
    if (Test-Path $src) {
        Copy-Item -Path $src -Destination $isoScriptsDir -Force
        Write-Host "Embedded in ISO: $script"
    } else {
        Write-Warning "Script not found (skipping): $script"
    }
}

# Also embed Winhance standalone scripts (they may also be in autounattend.xml Extensions)
$winhanceScripts = @(
    "shrink-and-recovery.ps1",
    "install-usb-apps.ps1",
    "install-ramdisk.ps1",
    "createramdisk.cmd",
    "tweaks-system.cmd",
    "tweaks-user.cmd"
)
foreach ($script in $winhanceScripts) {
    $src = Join-Path $scriptRoot $script
    if (Test-Path $src) {
        Copy-Item -Path $src -Destination $isoScriptsDir -Force
    }
}

# Copy winget-packages.json to ISO (referenced by install-usb-apps.ps1)
Copy-Item "C:\Users\C-Man\GoldISO\Config\winget-packages.json" -Destination $isoScriptsDir -Force
```

### 4.3 — Copy PowerShell Profile to ISO

```powershell
$isoContentsDir = "C:\GoldISO_Build\ISO"
$profileSrc = "C:\Users\C-Man\GoldISO\Config\PowerShellProfile"
$profileDest = "$isoContentsDir\PowerShellProfile"

if (Test-Path $profileSrc) {
    Copy-Item -Path $profileSrc -Destination $profileDest -Recurse -Force
    $profileFiles = (Get-ChildItem $profileDest -Recurse -File).Count
    Write-Host "PowerShell Profile copied: $profileFiles files"
} else {
    Write-Warning "PowerShell Profile not found at $profileSrc"
}
```

**Note**: The `autounattend.xml` FirstLogonCommand #40 deploys the profile from the ISO to `C:\PowerShellProfile\`. The ISO must therefore contain the profile source files at a location the FirstLogonCommand references.

### 4.4 — Copy Applications to ISO (Optional)

```powershell
$isoContentsDir = "C:\GoldISO_Build\ISO"
$appsSrc = "C:\Users\C-Man\GoldISO\Applications"

# The build script copies portable apps from Applications\Portableapps
# to ISO\PortableApps. The Applications directory contains many installers
# that are large — only include what FirstLogonCommands reference.

# Check what's in Applications
Get-ChildItem $appsSrc | Format-Table Name, @{N="SizeMB";E={[math]::Round($_.Length/1MB,0)}}, PSIsContainer

# The ramdisk installer is referenced by install-ramdisk.ps1
$ramdiskSrc = "$appsSrc\ramdisk_setup.exe"
if (Test-Path $ramdiskSrc) {
    $isoInstallersDir = "$isoContentsDir\Installers"
    New-Item -ItemType Directory -Path $isoInstallersDir -Force | Out-Null
    Copy-Item -Path $ramdiskSrc -Destination $isoInstallersDir -Force
    Write-Host "RAM disk installer copied to ISO"
}
```

**Important constraint**: The ISO has a practical size limit. Everything you add to the ISO contents inflates the final `.iso` file. Keep the ISO under ~8 GB if you want it to fit on a DVD or be used with tools that have size limits. For USB deployment there's no hard limit but smaller is faster to flash.

### 4.5 — Verify ISO Contents Before WIM Dismount

This is the last opportunity to catch missing files before committing the WIM changes.

```powershell
$isoContentsDir = "C:\GoldISO_Build\ISO"
$mountDir = "C:\Mount"

# Check all critical ISO files are in place
$checks = @{
    "autounattend.xml at root"     = "$isoContentsDir\autounattend.xml"
    "install.wim in sources"       = "$isoContentsDir\sources\install.wim"
    "boot\etfsboot.com"            = "$isoContentsDir\boot\etfsboot.com"
    "EFI boot bin"                 = "$isoContentsDir\efi\microsoft\boot\efisys.bin"
    "Scripts\Configure-SecDrives"  = "$isoContentsDir\Scripts\Configure-SecondaryDrives.ps1"
    "winget-packages.json"         = "$isoContentsDir\Scripts\winget-packages.json"
}

foreach ($check in $checks.GetEnumerator()) {
    if (Test-Path $check.Value) {
        Write-Host "[OK]   $($check.Key)" -ForegroundColor Green
    } else {
        Write-Host "[FAIL] $($check.Key) — $($check.Value)" -ForegroundColor Red
    }
}

# Check WIM is still properly mounted
Get-WindowsImage -Mounted | Where-Object { $_.MountPath -eq $mountDir } |
    Select-Object MountPath, ImagePath, MountStatus
# MountStatus must be: Ok
# If MountStatus is "NeedsRemount", run: Dism /Remount-Image /MountDir:"$mountDir"
```

---

## Phase 5 — WIM Finalization and ISO Rebuild

**Risk Level**: High (irreversible operations; WIM corruption risk; long-running)
**Prerequisite**: Phase 4 complete, all files in place
**Parallelism**: Strictly sequential

### 5.1 — Image Optimization (Before Dismount)

```powershell
$mountDir = "C:\Mount"

# Optimize provisioned APPX packages — reduces image size
Write-Host "Optimizing provisioned APPX packages..."
dism /Image:"$mountDir" /Optimize-AppxProvisionedPackage
# Note: This may take 5-20 minutes. Exit code 0 = success.

# Component cleanup — removes superseded components (reduces size significantly)
# /ResetBase makes cleanup permanent (cannot be undone — components cannot be restored)
# WARNING: /ResetBase removes the ability to uninstall patches. For a gold image this is correct.
Write-Host "Running component cleanup (this takes 10-30 minutes)..."
dism /Image:"$mountDir" /Cleanup-Image /StartComponentCleanup /ResetBase
# Exit code 0 = success; anything else = check log

# Check resulting WIM size before dismount
$wimPath = "C:\GoldISO_Build\ISO\sources\install.wim"
dism /Image:"$mountDir" /Get-ImageInfo
```

**Risk note**: `/ResetBase` is the highest-risk optimization. It permanently removes the ability to uninstall Windows Updates from the image. For a deployment "gold" image this is the correct behavior (smaller, faster installs). Do NOT use this if you need to maintain a patchable image.

**Estimated time**: 15-45 minutes total for both operations

### 5.2 — Dismount and Save WIM

```powershell
$mountDir = "C:\Mount"

# Dismount and commit all changes — this is the point of no return
# All drivers, packages, and APPX additions are written to install.wim
Write-Host "Saving WIM — this may take 10-30 minutes..."
Dismount-WindowsImage -Path $mountDir -Save -ErrorAction Stop
# -Save commits all changes; -Discard would throw them away
Write-Host "WIM saved successfully" -ForegroundColor Green

# Verify the WIM is no longer mounted
$mounted = Get-WindowsImage -Mounted
if ($mounted | Where-Object { $_.MountPath -eq $mountDir }) {
    Write-Error "WIM is still mounted — dismount failed"
} else {
    Write-Host "WIM dismount confirmed" -ForegroundColor Green
}
```

**Failure recovery**: If `Dismount-WindowsImage -Save` fails:
```powershell
# Check mount status
dism /Get-MountedWimInfo
# If status shows "Needs Remount":
dism /Remount-Image /MountDir:"C:\Mount"
# Then retry: Dismount-WindowsImage -Path "C:\Mount" -Save

# If unrecoverable, discard and rebuild from ISO copy:
Dismount-WindowsImage -Path "C:\Mount" -Discard
# You must re-mount and redo Phase 3 from scratch
```

### 5.3 — Export to Single-Index WIM with Maximum Compression

The exported WIM strips metadata from other indexes and applies maximum compression, significantly reducing the final ISO size.

```powershell
$sourceWIM = "C:\GoldISO_Build\ISO\sources\install.wim"
$singleIndexWIM = "C:\GoldISO_Build\install-single-index.wim"
$secondMountDir = "C:\Mnt"

# Export index 6 (Pro) to a new single-index WIM with maximum compression
Write-Host "Exporting single-index WIM (maximum compression)..."
Write-Host "This typically takes 20-60 minutes..."
Export-WindowsImage `
    -SourceImagePath $sourceWIM `
    -SourceIndex 6 `
    -DestinationImagePath $singleIndexWIM `
    -Compression Maximum `
    -ErrorAction Stop

$size = [math]::Round((Get-Item $singleIndexWIM).Length / 1GB, 2)
Write-Host "Single-index WIM created: $singleIndexWIM ($size GB)" -ForegroundColor Green

# Create a backup copy of the serviced single-index WIM
Copy-Item $singleIndexWIM "C:\GoldISO_Build\install-Pro-Max.wim" -Force
Write-Host "Backup WIM created: C:\GoldISO_Build\install-Pro-Max.wim"
```

**Estimated time**: 20-60 minutes (compression is CPU-intensive)

### 5.4 — Second Mount, Optimize, and Final Export

The build script does a second round of optimization on the exported single-index WIM to ensure maximum compaction.

```powershell
$singleIndexWIM = "C:\GoldISO_Build\install-single-index.wim"
$secondMountDir = "C:\Mnt"
New-Item -ItemType Directory -Path $secondMountDir -Force | Out-Null

# Mount the single-index WIM (index 1 — it only has one index now)
Write-Host "Mounting single-index WIM for second optimization pass..."
Mount-WindowsImage -ImagePath $singleIndexWIM -Path $secondMountDir -Index 1 -ErrorAction Stop

# Second optimization pass
Write-Host "Running second optimization pass..."
dism /Image:"$secondMountDir" /Optimize-AppxProvisionedPackage
dism /Image:"$secondMountDir" /Cleanup-Image /StartComponentCleanup /ResetBase

# Save the second-pass optimized WIM
Dismount-WindowsImage -Path $secondMountDir -Save -ErrorAction Stop
Write-Host "Second optimization pass complete" -ForegroundColor Green

# Final export: replace install.wim in ISO directory
$finalWIM = "C:\GoldISO_Build\ISO\sources\install.wim"
Write-Host "Exporting final WIM to ISO directory..."
Export-WindowsImage `
    -SourceImagePath $singleIndexWIM `
    -SourceIndex 1 `
    -DestinationImagePath $finalWIM `
    -Compression Maximum `
    -ErrorAction Stop

$finalSize = [math]::Round((Get-Item $finalWIM).Length / 1GB, 2)
Write-Host "Final install.wim: $finalSize GB" -ForegroundColor Green

# Also export a recovery WIM (Recovery compression = smaller, used by Windows Recovery)
$recoveryDir = "C:\GoldISO_Build\Recovery"
New-Item -ItemType Directory -Path $recoveryDir -Force | Out-Null
Export-WindowsImage `
    -SourceImagePath $singleIndexWIM `
    -SourceIndex 1 `
    -DestinationImagePath "$recoveryDir\install-recovery.wim" `
    -Compression Recovery
Write-Host "Recovery WIM created: $recoveryDir\install-recovery.wim"
```

**Estimated time for this entire phase**: 40-90 minutes

### 5.5 — Build the Final ISO with oscdimg

This is the last step of the build process. It produces the bootable `.iso` file.

```powershell
$isoContentsDir = "C:\GoldISO_Build\ISO"
$outputISO = "C:\Users\C-Man\GoldISO\GamerOS-Win11x64Pro25H2.iso"

# Verify boot files exist
$etfsBoot = "$isoContentsDir\boot\etfsboot.com"
$efiBoot  = "$isoContentsDir\efi\microsoft\boot\efisys.bin"

if (-not (Test-Path $etfsBoot)) { throw "Missing: $etfsBoot" }
if (-not (Test-Path $efiBoot))  { throw "Missing: $efiBoot" }

# Delete old output ISO if it exists
if (Test-Path $outputISO) { Remove-Item $outputISO -Force }

# Build the ISO
# -bootdata:2#...  = dual boot sectors (BIOS legacy + UEFI)
# p0,e,b"..."     = boot sector type 0 (El Torito), emulation mode e, boot file b
# pEF,e,b"..."    = EFI partition type EF, emulation mode e, boot file b
# -o              = optimize storage (combine duplicate files)
# -u2             = UDF 2.x filesystem
# -udfver102      = UDF version 1.02 for compatibility
# -l"GAMEROS"     = volume label (must match what autounattend.xml expects)

Write-Host "Building ISO with oscdimg..."
Write-Host "This typically takes 5-20 minutes..."
$oscdimgCmd = @(
    "-bootdata:2#p0,e,b`"$etfsBoot`"#pEF,e,b`"$efiBoot`"",
    "-o",
    "-u2",
    "-udfver102",
    "-l`"GAMEROS`"",
    "`"$isoContentsDir`"",
    "`"$outputISO`""
)
& oscdimg $oscdimgCmd

if ($LASTEXITCODE -eq 0 -and (Test-Path $outputISO)) {
    $isoSize = [math]::Round((Get-Item $outputISO).Length / 1GB, 2)
    Write-Host "ISO created successfully: $outputISO ($isoSize GB)" -ForegroundColor Green
} else {
    throw "oscdimg failed with exit code $LASTEXITCODE"
}
```

**Estimated time**: 5-20 minutes

**Failure modes**:

| Error | Cause | Fix |
|---|---|---|
| "oscdimg: error — bad option" | Command syntax error | Verify quoting in the -bootdata parameter |
| "Cannot create file" | Output path doesn't exist or is read-only | Ensure parent directory exists; check permissions |
| Exit code 1 and no output file | ISO directory contains invalid files | Check for files >4GB (UDF limit); split or exclude |
| "boot file not found" | etfsboot.com or efisys.bin missing from ISO copy | Verify robocopy copied ALL files including hidden/system |

---

## Phase 6 — ISO Verification

**Risk Level**: Low
**Prerequisite**: Phase 5 complete, GamerOS-Win11x64Pro25H2.iso exists
**Parallelism**: Steps 6.1-6.4 can run in parallel

### 6.1 — ISO Mount and Structure Verification

```powershell
$outputISO = "C:\Users\C-Man\GoldISO\GamerOS-Win11x64Pro25H2.iso"

# Verify ISO properties
$isoItem = Get-Item $outputISO
Write-Host "ISO size: $([math]::Round($isoItem.Length / 1GB, 2)) GB"
Write-Host "Created: $($isoItem.LastWriteTime)"

# Mount and verify structure
$mounted = Mount-DiskImage -ImagePath $outputISO -PassThru -ErrorAction Stop
$drive = ($mounted | Get-Volume).DriveLetter
Write-Host "ISO mounted at: ${drive}:"

# Check all critical files
$criticalFiles = @(
    "${drive}:\autounattend.xml",
    "${drive}:\sources\install.wim",
    "${drive}:\boot\etfsboot.com",
    "${drive}:\efi\microsoft\boot\efisys.bin",
    "${drive}:\sources\boot.wim"
)

$allOk = $true
foreach ($f in $criticalFiles) {
    if (Test-Path $f) {
        $size = [math]::Round((Get-Item $f).Length / 1MB, 0)
        Write-Host "[OK]   $f ($size MB)" -ForegroundColor Green
    } else {
        Write-Host "[FAIL] $f not found" -ForegroundColor Red
        $allOk = $false
    }
}

# Verify volume label
$vol = Get-Volume -DriveLetter $drive
Write-Host "Volume label: $($vol.FileSystemLabel)"
# Should be: GAMEROS

# Dismount
Dismount-DiskImage -ImagePath $outputISO
```

### 6.2 — Verify WIM Index and Content

```powershell
$outputISO = "C:\Users\C-Man\GoldISO\GamerOS-Win11x64Pro25H2.iso"
$mounted = Mount-DiskImage -ImagePath $outputISO -PassThru
$drive = ($mounted | Get-Volume).DriveLetter

# Check WIM indexes — should be EXACTLY 1 index (Windows 11 Pro)
$wimInfo = Get-WindowsImage -ImagePath "${drive}:\sources\install.wim"
Write-Host "WIM indexes: $($wimInfo.Count) (expected: 1)"
foreach ($img in $wimInfo) {
    Write-Host "  Index $($img.ImageIndex): $($img.ImageName) — $([math]::Round($img.Size / 1GB, 2)) GB"
}

Dismount-DiskImage -ImagePath $outputISO
```

### 6.3 — Verify autounattend.xml in ISO

```powershell
$outputISO = "C:\Users\C-Man\GoldISO\GamerOS-Win11x64Pro25H2.iso"
$mounted = Mount-DiskImage -ImagePath $outputISO -PassThru
$drive = ($mounted | Get-Volume).DriveLetter

# Read and validate the answer file from within the ISO
[xml]$isoXml = Get-Content "${drive}:\autounattend.xml" -Raw
$oobe = $isoXml.unattend.settings | Where-Object { $_.Pass -eq "oobeSystem" }
$flCmds = $oobe.Component.FirstLogonCommands.SynchronousCommand
Write-Host "FirstLogonCommands in ISO autounattend.xml: $($flCmds.Count)"
# Should be 43

# Verify disk config
$diskConfig = $isoXml.unattend.settings.component |
    Where-Object { $_.Name -eq "Microsoft-Windows-Setup" }
$disks = $diskConfig.DiskConfiguration.Disk
Write-Host "Disk configurations: $($disks.Count)"
foreach ($d in $disks) {
    Write-Host "  Disk $($d.DiskID): WillWipe=$($d.WillWipeDisk), Partitions=$($d.CreatePartitions.CreatePartition.Count)"
}

Dismount-DiskImage -ImagePath $outputISO
```

### 6.4 — Verify Injected Drivers (Mount and Inspect)

```powershell
$outputISO = "C:\Users\C-Man\GoldISO\GamerOS-Win11x64Pro25H2.iso"
$verifyMount = "C:\MountVerify"
New-Item -ItemType Directory -Path $verifyMount -Force | Out-Null

$mounted = Mount-DiskImage -ImagePath $outputISO -PassThru
$drive = ($mounted | Get-Volume).DriveLetter

# Mount WIM for driver inspection (read-only)
Mount-WindowsImage -ImagePath "${drive}:\sources\install.wim" -Path $verifyMount -Index 1 -ReadOnly

# Check drivers
$drivers = Get-WindowsDriver -Path $verifyMount
Write-Host "Total drivers in image: $($drivers.Count)"

# Verify key driver vendors are present
$expectedVendors = @("Intel", "Realtek", "ASUS")
foreach ($vendor in $expectedVendors) {
    $found = $drivers | Where-Object { $_.ProviderName -match $vendor }
    if ($found) {
        Write-Host "[OK]   $vendor drivers: $($found.Count)" -ForegroundColor Green
    } else {
        Write-Host "[WARN] No $vendor drivers found" -ForegroundColor Yellow
    }
}

# Verify NVIDIA is NOT in the image (it should NOT be offline injected)
$nvidia = $drivers | Where-Object { $_.ProviderName -match "NVIDIA" }
if ($nvidia) {
    Write-Host "[WARN] NVIDIA drivers found in image — they should be post-boot only" -ForegroundColor Yellow
} else {
    Write-Host "[OK]   NVIDIA drivers NOT in image (correct)" -ForegroundColor Green
}

# Dismount
Dismount-WindowsImage -Path $verifyMount -Discard
Dismount-DiskImage -ImagePath $outputISO
Remove-Item $verifyMount -Force -ErrorAction SilentlyContinue
```

---

## Phase 7 — VM Testing

**Risk Level**: Medium (testing environment, no production risk)
**Prerequisite**: Phase 6 complete, ISO verified
**Parallelism**: VM setup (7.1) and USB preparation (for bare metal, not needed here) can run in parallel

### 7.1 — Create Hyper-V Test VM

The project includes `New-TestVM.ps1` for this purpose.

```powershell
Set-Location "C:\Users\C-Man\GoldISO\Scripts"

# Create test VM (review script first if this is your first run)
.\New-TestVM.ps1

# Or manually with full control:
$vmName = "GamerOS-Test-$(Get-Date -Format 'yyyyMMdd-HHmm')"
$isoPath = "C:\Users\C-Man\GoldISO\GamerOS-Win11x64Pro25H2.iso"
$vhdPath = "C:\Hyper-V\$vmName\$vmName.vhdx"
$switchName = "Default Switch"  # Use existing switch; create if needed

# Ensure Hyper-V is enabled
$hvFeature = Get-WindowsOptionalFeature -Online -FeatureName "Microsoft-Hyper-V-All"
if ($hvFeature.State -ne "Enabled") {
    Enable-WindowsOptionalFeature -Online -FeatureName "Microsoft-Hyper-V-All" -All -NoRestart
    # Requires reboot — reboot and continue from here
}

# Create VM with Gen 2 (UEFI, required for Windows 11)
$vm = New-VM `
    -Name $vmName `
    -Generation 2 `
    -MemoryStartupBytes 8GB `
    -Path "C:\Hyper-V"

# Add virtual hard disk (100 GB for testing)
New-VHD -Path $vhdPath -SizeBytes 100GB -Dynamic
Add-VMHardDiskDrive -VM $vm -Path $vhdPath

# Attach ISO
Add-VMDvdDrive -VM $vm -Path $isoPath

# Configure boot order (DVD first)
$dvdDrive = Get-VMDvdDrive -VM $vm
Set-VMFirmware -VM $vm -BootOrder @($dvdDrive, (Get-VMHardDiskDrive -VM $vm))

# Enable TPM (required for Windows 11 — no bypasses in this build)
Enable-VMTPM -VM $vm
Set-VMKeyProtector -VM $vm -NewLocalKeyProtector

# Disable Secure Boot for testing (or configure a test certificate)
# Note: The GamerOS build does NOT bypass TPM/SecureBoot in autounattend.xml
# For VM testing, you need Secure Boot enabled with a valid key
Set-VMFirmware -VM $vm -EnableSecureBoot On -SecureBootTemplate "MicrosoftWindows"

# Set processor count
Set-VMProcessor -VM $vm -Count 4

# Disable checkpoints (clean test)
Set-VM -VM $vm -CheckpointType Disabled

Write-Host "VM created: $vmName"
```

**Critical constraint**: The GamerOS build does NOT bypass TPM, Secure Boot, Storage, CPU, RAM, or Disk requirements. The test VM MUST have:
- TPM 2.0 enabled (virtual TPM via VTPM)
- Secure Boot enabled with Microsoft Windows template
- At least 4 GB RAM (8 GB recommended)
- At least 64 GB disk
- At least 2 vCPUs

### 7.2 — IMPORTANT — Adapt Disk IDs for VM

The `autounattend.xml` is configured for a specific 3-disk hardware layout (Disk 0, 1, 2). In a VM with a single disk, the disk topology will be different.

**Before VM testing**, you have two options:

**Option A** — Create a single-disk VM and temporarily modify the answer file:
The current `autounattend.xml` wipes Disks 0, 1, and 2, then installs Windows on Disk 2. A single-disk VM will have only Disk 0. The `WillWipeDisk=true` for Disks 1 and 2 that don't exist will cause errors.

**Option B** — Create a 3-disk VM to match the hardware layout exactly:
```powershell
# Add two additional disks to the VM to match the 3-disk layout
$vm = Get-VM -Name $vmName

# Disk 0 (secondary SSD equivalent)
$vhd0 = "C:\Hyper-V\$vmName\disk0.vhdx"
New-VHD -Path $vhd0 -SizeBytes 50GB -Dynamic
Add-VMHardDiskDrive -VM $vm -Path $vhd0

# Disk 1 (HDD equivalent)
$vhd1 = "C:\Hyper-V\$vmName\disk1.vhdx"
New-VHD -Path $vhd1 -SizeBytes 50GB -Dynamic
Add-VMHardDiskDrive -VM $vm -Path $vhd1

# Verify disk order matches expected (Disk 0=first, Disk 1=second, Disk 2=third)
# Note: Hyper-V assigns disk numbers in the order they appear in the SCSI controller
Get-VMHardDiskDrive -VM $vm | Select-Object ControllerType, ControllerNumber, ControllerLocation, Path
```

**Recommendation**: Option B is safer and more representative of actual hardware.

### 7.3 — Start VM and Monitor Installation

```powershell
# Start the VM
Start-VM -Name $vmName

# Connect to VM console
vmconnect localhost $vmName

# In the VM console, observe:
# 1. UEFI boot → Windows Setup loader
# 2. Language/Region screen should be SKIPPED (autounattend handles it)
# 3. Disk partitioning (windowsPE pass) — Disk 2 gets 4 partitions
# 4. Windows files copy
# 5. First reboot
# 6. Specialize phase (drivers, packages, scripts)
# 7. OOBE phase — should auto-complete with local account "Administrator"
# 8. First Logon → 43 commands run sequentially
```

**Checkpoint list during installation**:

| Stage | What to Verify |
|---|---|
| Pre-copy | No disk selection dialog appears (autounattend handles it) |
| During copy | Progress bar advances; no error dialogs |
| Specialize | No popup errors; system reboots cleanly |
| OOBE | "Welcome" screen passes automatically; no Microsoft account prompt |
| First boot | Desktop appears; Administrator is logged in; no password prompt |
| Post-first-boot | CMD windows appear and close (FirstLogonCommands running) |
| ~10-30 minutes post-boot | Check Task Manager for background processes completing |

### 7.4 — Post-VM-Install Verification Checklist

After the VM completes all FirstLogonCommands, verify:

```powershell
# Run these inside the VM as Administrator
# Check category folders exist
foreach ($folder in @("C:\Dev","C:\Gaming","C:\Utils","C:\Media","C:\Remote","C:\Scripts")) {
    if (Test-Path $folder) { Write-Host "[OK]   $folder" -ForegroundColor Green }
    else { Write-Host "[FAIL] $folder missing" -ForegroundColor Red }
}

# Check PowerShell profile deployed
Test-Path "C:\PowerShellProfile\Microsoft.PowerShell_profile.ps1"
Test-Path "C:\PowerShellProfile\PSProfile.C-Man"

# Check winget is available
winget --version
# Should return version 1.x or 2.x

# Check AppInstaller package
Get-AppxPackage -Name "Microsoft.DesktopAppInstaller" | Select-Object Name, Version

# Check PowerShell 7 provisioned
Get-AppxPackage -Name "Microsoft.PowerShell" | Select-Object Name, Version

# Check Windows Terminal provisioned
Get-AppxPackage -Name "Microsoft.WindowsTerminal" | Select-Object Name, Version

# Check disk partitions on VM "Disk 2"
Get-Disk | Select-Object Number, FriendlyName, Size, PartitionStyle
Get-Partition | Where-Object { $_.DiskNumber -eq 2 } |
    Select-Object PartitionNumber, DriveLetter, Size, Type

# Verify ~90GB unallocated (Samsung OP space) — won't be present in VM unless disk is large enough
# On real hardware, C:\GoldISO_Build\Logs\disk-config.log will show the shrink operation result
```

**Disk partition check (Disk 2 in VM)**:
```
Expected partitions after install + specialize:
1. EFI       300 MB    System
2. MSR        16 MB    Reserved
3. C: Windows ~843 GB  Primary (on real hardware; proportionally smaller in VM)
4. Recovery   15 GB    Recovery (hidden, no drive letter)
Unallocated:  ~90 GB   (Samsung overprovisioning — proportionally smaller in VM)
```

**Note on VM recovery partition**: The `shrink-and-recovery.ps1` runs during specialize. In a small VM disk (100 GB), the shrink of 105 GB may fail with "New Windows partition would be too small" since the disk isn't large enough. This is expected and non-fatal — the script continues. On real hardware with a 1TB NVMe this works correctly.

---

## Phase 8 — Bare-Metal Deployment

**Risk Level**: HIGH — this operation wipes three physical disks
**Prerequisite**: Phase 7 complete (VM test passed), target hardware prepared
**Parallelism**: Strictly sequential

### 8.1 — Pre-Deployment Hardware Verification

**Before booting the installation media on the target machine**, verify the disk topology matches what autounattend.xml expects.

```powershell
# Run this on the TARGET MACHINE before installing (boot into WinPE or existing Windows)
# OR: During WinPE boot, open PowerShell and run:

# Get physical disk list
Get-PhysicalDisk | Select-Object DeviceId, FriendlyName, MediaType, Size |
    Sort-Object DeviceId | Format-Table -AutoSize

# Expected output on target hardware:
# DeviceId  FriendlyName                    MediaType  Size
# 0         Some SSD (secondary)            SSD        ~512GB or ~1TB
# 1         Some HDD (storage)              HDD        ~2TB
# 2         Samsung NVMe (primary Windows)  SSD        ~1TB

# CRITICAL: Disk 2 MUST be the Samsung NVMe where Windows will install
# If the disk order is different, autounattend.xml MUST be updated before deploying
```

**If disk order is wrong**: Edit `Config\autounattend.xml`, change `<DiskID>2</DiskID>` to the correct disk number for the Samsung NVMe, then rebuild the ISO (Phases 1-6 again).

**DATA LOSS WARNING**: The autounattend.xml sets `WillWipeDisk=true` on Disks 0, 1, AND 2. All data on ALL THREE DISKS will be permanently destroyed. This is by design. Ensure all important data is backed up before proceeding.

### 8.2 — Create Bootable USB

```powershell
# On the BUILD MACHINE or any Windows machine
# Using Rufus (from Applications/ or winget)
# OR using built-in tools:

$isoPath = "C:\Users\C-Man\GoldISO\GamerOS-Win11x64Pro25H2.iso"
# Rufus method (GUI — recommended for reliable UEFI boot):
# 1. Open Rufus
# 2. Select USB drive (minimum 8 GB)
# 3. Select ISO: $isoPath
# 4. Partition scheme: GPT (for UEFI-only systems)
# 5. Target system: UEFI (non CSM)
# 6. File system: NTFS (for ISOs with files >4GB)
# 7. Click START

# Ventoy method (if ISO >4GB, Ventoy handles it automatically):
# 1. Install Ventoy to USB
# 2. Copy the ISO to the USB drive root
# 3. Ventoy multi-boot menu will appear on boot

# PowerShell/DISM method (advanced):
# Get the USB drive number (be VERY careful — wrong disk = data loss)
Get-Disk | Where-Object { $_.BusType -eq "USB" } | Select-Object Number, FriendlyName, Size
# $usbDisk = 3  # VERIFY THIS CAREFULLY

# Then use diskpart to format and copy — Rufus is strongly preferred
```

### 8.3 — BIOS/UEFI Configuration on Target Machine

Before booting from USB:
1. Enter UEFI/BIOS setup (typically Del or F2 during POST)
2. Verify Secure Boot is ENABLED
3. Verify TPM is ENABLED (look for "AMD fTPM" or "Intel PTT" or standalone TPM)
4. Set boot order: USB first, then NVMe
5. Verify AHCI/NVMe mode is NOT in legacy IDE/compatibility mode
6. Save and exit

**Why this matters**: The GamerOS build explicitly does NOT bypass TPM or Secure Boot. If either is disabled, Windows Setup will detect incompatibility and refuse to continue.

### 8.4 — Boot and Installation Process

1. Insert the GamerOS USB into the target machine
2. Power on and boot from USB
3. The Windows Setup process will:
   a. Load WinPE from boot.wim (~1 minute)
   b. Detect `autounattend.xml` at ISO root automatically
   c. Begin unattended installation with no user input required

**What NOT to do during installation**:
- Do NOT press any keys during setup unless it stalls completely
- Do NOT interrupt the specialize phase (recognizable by a screen showing "Getting devices ready")
- Do NOT remove the USB until Windows has fully booted to the desktop

**Estimated total installation time**: 15-40 minutes for the full install through first logon completion of all 43 FirstLogonCommands.

### 8.5 — Monitor Critical Installation Phases

**windowsPE phase** (disk partitioning):
- System will show "Windows is loading files" then the setup UI briefly appears
- With autounattend.xml, the UI should vanish and the copy phase should begin automatically
- Watch for any partition error dialogs — these indicate disk topology mismatch

**specialize phase** (drivers, packages, scripts):
- System reboots into the "Getting devices ready" screen
- This phase takes 5-15 minutes; the progress percentage advances
- The `shrink-and-recovery.ps1` script runs here — verify C:\ProgramData\Winhance\Unattend\Logs\disk-config.log after boot

**OOBE phase**:
- Should complete automatically (local account, no Microsoft account)
- Network is intentionally disabled during this phase
- If prompted for network: click "I don't have internet" then "Continue with limited setup"

**FirstLogon commands** (43 sequential operations):
- System boots to desktop with CMD/PowerShell windows appearing and disappearing
- DO NOT interact with the system during this phase
- Total time: 15-45 minutes (mostly waiting on winget installs)

---

## Phase 9 — Post-Install Configuration

**Risk Level**: Low to Medium
**Prerequisite**: Phase 8 complete, Windows booted to desktop, all FirstLogonCommands finished
**Parallelism**: Steps 9.1 and 9.2 can run in separate PowerShell windows

### 9.1 — Verify FirstLogonCommands Completed Successfully

```powershell
# Run as Administrator on the TARGET MACHINE

# Check the installation log (if Winhance logging is active)
Get-Content "C:\ProgramData\Winhance\Unattend\Logs\disk-config.log" -ErrorAction SilentlyContinue
Get-Content "C:\ProgramData\Winhance\Unattend\Logs\usb-apps-install.log" -ErrorAction SilentlyContinue

# Check category folders (created by FirstLogonCommand #38)
foreach ($folder in @("C:\Dev","C:\Gaming","C:\Utils","C:\Media","C:\Remote","C:\Scripts")) {
    $status = if (Test-Path $folder) { "OK" } else { "MISSING" }
    Write-Host "[$status] $folder"
}

# Check GWIG scripts were copied (FirstLogonCommand #39)
Get-ChildItem "C:\Scripts" -ErrorAction SilentlyContinue | Select-Object Name | Format-Table

# Check PowerShell profile deployed (FirstLogonCommand #40)
Test-Path "C:\PowerShellProfile\Microsoft.PowerShell_profile.ps1"
Test-Path "C:\PowerShellProfile\PSProfile.C-Man"

# Check NVIDIA driver installed (FirstLogonCommand #41)
Get-CimInstance Win32_VideoController | Select-Object Name, DriverVersion | Format-Table

# Check Logitech driver installed (FirstLogonCommand #42)
# Check USB HID devices
Get-CimInstance Win32_PnPEntity | Where-Object { $_.Name -match "Logitech" } |
    Select-Object Name, Status | Format-Table

# Check winget apps were installed (a sample)
winget list | Select-String "Google.Chrome|Git.Git|Valve.Steam|7zip"

# Check RAM disk (if install-ramdisk.ps1 ran successfully)
Get-PSDrive R -ErrorAction SilentlyContinue
# Should show R: with 8GB size if RAM disk was created

# Check DNS settings
Get-NetAdapter | Get-DnsClientServerAddress | Format-Table
# Should show 1.1.1.1 and 8.8.8.8 (or similar from FirstLogonCommand #5)

# Check power plan
powercfg /getactivescheme
# Should show "High performance" or similar
```

### 9.2 — Partition Secondary Drives

This step MUST be run manually after the system is fully up. The `autounattend.xml` intentionally leaves Disk 0 and Disk 1 wiped but unpartitioned.

```powershell
# Run as Administrator on the TARGET MACHINE

# FIRST: Verify disk topology one more time before partitioning
Get-Disk | Select-Object Number, FriendlyName, Size, PartitionStyle | Format-Table -AutoSize
# Confirm:
# Disk 0 = Secondary SSD (RAW partition style — no partitions)
# Disk 1 = HDD (RAW partition style — no partitions)
# Disk 2 = Samsung NVMe (GPT with 4+ partitions — already done)

# Run the secondary drives configuration script
Set-Location "C:\Scripts"  # Copied here during FirstLogon #39
.\Configure-SecondaryDrives.ps1

# OR from the original location:
Set-Location "C:\Users\C-Man\GoldISO"
.\Scripts\Configure-SecondaryDrives.ps1

# What this script creates:
# Disk 0 (SSD):
#   F: Apps    — 100 GB, NTFS
#   G: Scratch — 120 GB, NTFS
#   Remaining: Unallocated (available for future use)
#
# Disk 1 (HDD):
#   H: Media   — 500 GB, NTFS
#   I: Storage — Remaining (all of it), NTFS
```

**Verification after Configure-SecondaryDrives.ps1**:
```powershell
# Verify all expected drives exist and are accessible
foreach ($drive in @("F","G","H","I")) {
    $d = Get-PSDrive $drive -ErrorAction SilentlyContinue
    if ($d) {
        Write-Host "[OK]   ${drive}: — $([math]::Round($d.Used / 1GB, 0)) GB used of $([math]::Round(($d.Used + $d.Free) / 1GB, 0)) GB" -ForegroundColor Green
    } else {
        Write-Host "[FAIL] ${drive}: drive not found" -ForegroundColor Red
    }
}

# Verify partition labels
Get-Volume | Where-Object { $_.DriveLetter -in @("F","G","H","I") } |
    Select-Object DriveLetter, FileSystemLabel, Size, FileSystem | Format-Table
```

### 9.3 — Install NVIDIA Driver (if not done by FirstLogon)

The NVIDIA RTX 3060 Ti driver should have been installed by FirstLogonCommand #41 using `pnputil`. If it didn't complete:

```powershell
# Find NVIDIA drivers in the Drivers directory (copied to the machine or USB)
$nvidiaDriverPath = "C:\Users\C-Man\GoldISO\Drivers\Display adapters"
# OR from USB if GoldISO project is on USB:
# $nvidiaDriverPath = "U:\GoldISO\Drivers\Display adapters"

# Install NVIDIA driver offline
$nvidiaInf = Get-ChildItem $nvidiaDriverPath -Recurse -Filter "*.inf" | Select-Object -First 1
if ($nvidiaInf) {
    pnputil /add-driver $nvidiaInf.FullName /install /subdirs
} else {
    Write-Warning "NVIDIA INF not found — download from nvidia.com"
    # Download NVIDIA RTX 3060 Ti driver 32.0.15.6094 from nvidia.com
    # Run the downloaded installer with /s (silent) flag
}

# Verify NVIDIA driver
Get-CimInstance Win32_VideoController | Where-Object { $_.Name -match "NVIDIA" } |
    Select-Object Name, DriverVersion | Format-Table
```

### 9.4 — Install Logitech G403 HERO Driver (if not done by FirstLogon)

```powershell
# Find Logitech USB driver
$logitechDriverPath = "C:\Users\C-Man\GoldISO\Drivers\Universal Serial Bus controllers"

$logitechInf = Get-ChildItem $logitechDriverPath -Recurse -Filter "*.inf" | Select-Object -First 1
if ($logitechInf) {
    pnputil /add-driver $logitechInf.FullName /install /subdirs
    Write-Host "Logitech driver installed"
}

# Verify via Device Manager or:
Get-CimInstance Win32_PnPEntity | Where-Object { $_.Name -match "Logitech" } |
    Select-Object Name, DeviceID, Status | Format-Table
```

### 9.5 — Samsung Magician Setup for NVMe Overprovisioning

```powershell
# If Samsung Magician wasn't installed by winget or FirstLogon:
$magicianInstaller = "C:\Users\C-Man\GoldISO\Applications\Samsung_Magician_Installer_Official_9.0.1.950.exe"
if (Test-Path $magicianInstaller) {
    Start-Process $magicianInstaller -ArgumentList "/silent" -Wait
}

# Samsung Magician will automatically detect the ~90 GB unallocated space
# at the end of Disk 2 (created by shrink-and-recovery.ps1) as overprovisioning space
# Open Samsung Magician → Performance Optimization → Over Provisioning
# It should show ~90 GB allocated for OP — no additional action needed
```

### 9.6 — Final System Health Verification

```powershell
# Comprehensive post-install health check
Write-Host "=== GamerOS Post-Install Health Check ===" -ForegroundColor Cyan

# 1. Windows activation status
$activ = Get-CimInstance SoftwareLicensingProduct |
    Where-Object { $_.Name -match "Windows" -and $_.LicenseStatus -eq 1 }
if ($activ) { Write-Host "[OK] Windows is activated" -ForegroundColor Green }
else { Write-Host "[WARN] Windows not yet activated" -ForegroundColor Yellow }

# 2. All drives accessible
foreach ($drive in @("C","F","G","H","I")) {
    if (Get-PSDrive $drive -ErrorAction SilentlyContinue) {
        Write-Host "[OK]   Drive ${drive}:" -ForegroundColor Green
    } else {
        Write-Host "[WARN] Drive ${drive}: not found" -ForegroundColor Yellow
    }
}

# 3. Critical software
$software = @("winget","git","code","pwsh")
foreach ($sw in $software) {
    $cmd = Get-Command $sw -ErrorAction SilentlyContinue
    if ($cmd) { Write-Host "[OK]   $sw — $($cmd.Source)" -ForegroundColor Green }
    else { Write-Host "[WARN] $sw not found in PATH" -ForegroundColor Yellow }
}

# 4. NVIDIA driver
$gpu = Get-CimInstance Win32_VideoController | Where-Object { $_.Name -match "NVIDIA" }
if ($gpu) {
    Write-Host "[OK]   NVIDIA GPU: $($gpu.Name) v$($gpu.DriverVersion)" -ForegroundColor Green
} else {
    Write-Host "[FAIL] NVIDIA GPU not detected" -ForegroundColor Red
}

# 5. Network connectivity
if (Test-Connection 8.8.8.8 -Count 1 -Quiet) {
    Write-Host "[OK]   Network connectivity" -ForegroundColor Green
} else {
    Write-Host "[FAIL] No network connectivity" -ForegroundColor Red
}

# 6. Disk health
Get-PhysicalDisk | Select-Object DeviceId, FriendlyName, HealthStatus, OperationalStatus |
    Format-Table -AutoSize

# 7. Event log errors (last 1 hour)
$recentErrors = Get-EventLog -LogName Application -EntryType Error -Newest 20 -ErrorAction SilentlyContinue
Write-Host "Recent Application errors: $($recentErrors.Count)"
```

### 9.7 — Create Initial System Restore Point

```powershell
# This should have been created by FirstLogonCommand #25, but verify:
Get-ComputerRestorePoint | Select-Object Description, CreationTime, SequenceNumber |
    Sort-Object CreationTime -Descending | Select-Object -First 5 | Format-Table

# If no restore point exists or you want a fresh one after drive config:
Checkpoint-Computer -Description "GamerOS Post-Install - All Drives Configured" -RestorePointType "MODIFY_SETTINGS"
Write-Host "System restore point created" -ForegroundColor Green
```

---

## Phase 10 — Audit / Capture Workflows (Conditional)

**Risk Level**: Medium (audit mode), High (capture — changes are permanent if sysprep fails)
**Prerequisite**: A functional Windows installation (either from standard GoldISO install OR existing configured system)
**When to use**: When you want to capture a configured system state to create a faster, pre-configured deployment image

### 10.1 — Audit Mode Workflow

Use Audit Mode when you want to customize the Windows installation BEFORE the final OOBE, without creating a user account yet.

**Step 1**: Build an Audit Mode ISO:
```powershell
Set-Location "C:\Users\C-Man\GoldISO"
.\Scripts\Build-GoldISO.ps1 -BuildMode Audit -IncludeAuditScripts
```

**Step 2**: Install the Audit Mode ISO on the target. The system will boot into Audit Mode automatically (Administrator account, no OOBE yet).

**Step 3**: Customize the system while in Audit Mode:
```powershell
# In Audit Mode, you can:
# - Install applications
# - Configure settings
# - Copy files
# - Adjust registry
# Do NOT create user accounts yet — that happens in OOBE
```

**Step 4**: Transition from Audit Mode to OOBE:
```powershell
# Double-click "Continue to OOBE.lnk" on the desktop (created by IncludeAuditScripts)
# OR run:
C:\Scripts\AuditMode-Continue.ps1

# What this script does:
# Runs sysprep to generalize the installation and trigger OOBE on next boot
# sysprep /generalize /oobe /reboot /quit
```

**Failure mode**: If Audit-Continue fails with "sysprep validation error":
```powershell
# Check sysprep log for details
Get-Content "C:\Windows\System32\Sysprep\Panther\setupact.log" | Select-Object -Last 50
# Common cause: installed apps that aren't sysprep-compatible (e.g., some UWP apps)
# Fix: uninstall incompatible apps, then retry
```

### 10.2 — WIM Capture Workflow (from Configured System)

Use this to capture a fully configured, post-install Windows system into a WIM file for rapid future deployments.

**Prerequisites for capture**:
- The system to capture must be fully configured (all apps, settings, tweaks applied)
- A WinPE boot USB must be prepared (use Windows ADK's WinPE tools or an existing WinPE image)
- The USB drive must have at least 60 GB free space for the WIM file (typical capture is 20-50 GB)

**Step 1**: Boot into WinPE from USB on the target machine. Do NOT boot the configured Windows — capture must happen offline.

**Step 2**: Inside WinPE, the USB drive should be accessible. Find and run the capture script:
```powershell
# In WinPE PowerShell session:
# Auto-detect USB drive letter (WinPE typically has X: as its drive)
$usbDrive = Get-Volume | Where-Object {
    $_.DriveType -eq "Removable" -and $_.DriveLetter -ne "X"
} | Select-Object -First 1 -ExpandProperty DriveLetter

Write-Host "USB drive detected at: ${usbDrive}:"

# Run the capture script from USB
& "${usbDrive}:\Scripts\Capture-Image.ps1"

# OR with explicit parameters:
& "${usbDrive}:\Scripts\Capture-Image.ps1" `
    -TargetDisk 2 `                      # Disk to capture (Samsung NVMe = Disk 2)
    -CapturePath "${usbDrive}:\Capture.wim" `  # Save directly to USB
    -MoveToUSB:$false                    # Already saving to USB
```

**What Capture-Image.ps1 does internally**:
```powershell
# Manual equivalent for understanding:
# 1. Identify the Windows partition on Disk 2
$winPartition = Get-Partition -DiskNumber 2 | Where-Object { $_.Type -eq "Basic" } |
    Get-Volume | Where-Object { $_.FileSystemLabel -match "Windows" -or Test-Path "$($_.DriveLetter):\Windows\System32" }

# 2. Capture the partition using DISM
# /Compress:Maximum = smaller file, slower capture
# /Name describes the image
dism /Capture-Image `
    /ImageFile:"${usbDrive}:\Capture.wim" `
    /CaptureDir:"$($winPartition.DriveLetter):\" `
    /Name:"GamerOS Win11 25H2 - $(Get-Date -Format 'yyyy-MM-dd')" `
    /Description:"Captured from configured GamerOS system" `
    /Compress:Maximum `
    /Verify
```

**Estimated capture time**: 30-90 minutes depending on disk size and data
**Expected WIM size**: 40-60% of installed size (Maximum compression)

### 10.3 — Build ISO from Captured WIM

After capturing, build a new ISO that uses the captured system state instead of the original install.wim:

```powershell
Set-Location "C:\Users\C-Man\GoldISO"

# Build using the captured WIM
.\Scripts\Build-GoldISO.ps1 `
    -BuildMode Capture `
    -CaptureWIMPath "D:\GoldISO\Capture.wim" `  # Path to captured WIM on USB
    -SkipDriverInjection `   # Captured WIM already has drivers from the configured system
    -SkipPackageInjection    # Captured WIM already has packages installed

# Note: Driver and package injection is skipped because the captured WIM already
# contains everything from the configured system.
# autounattend.xml is still copied to ISO root for future OOBE handling.
```

### 10.4 — Apply Captured WIM to New Machine (Quick Deployment)

For deploying the captured image to additional machines without going through the full install process:

```powershell
# Boot target machine into WinPE from USB
# In WinPE:
$usbDrive = (Get-Volume | Where-Object { $_.DriveType -eq "Removable" -and $_.DriveLetter -ne "X" } |
    Select-Object -First 1).DriveLetter

# Auto-detect WIM from USB and apply
& "${usbDrive}:\Scripts\Apply-Image.ps1"

# OR with explicit parameters:
& "${usbDrive}:\Scripts\Apply-Image.ps1" `
    -ImagePath "${usbDrive}:\Capture.wim" `
    -TargetDisk 2 `
    -ImageIndex 1 `
    -BootMode UEFI

# What Apply-Image.ps1 does:
# 1. Clears and partitions the target disk (EFI + MSR + Windows + Recovery)
# 2. Applies the WIM to the Windows partition
# 3. Configures the BCD boot store
# 4. System reboots into Windows ready for use
```

**Manual equivalent for Apply**:
```powershell
# In WinPE, manual disk setup and image application:

# 1. Clean and partition Disk 2
@"
select disk 2
clean
convert gpt
create partition efi size=300
format quick fs=fat32 label="System"
assign letter=S
create partition msr size=16
create partition primary
format quick fs=ntfs label="Windows"
assign letter=W
"@ | diskpart

# 2. Apply WIM to Windows partition
dism /Apply-Image /ImageFile:"${usbDrive}:\Capture.wim" /Index:1 /ApplyDir:W:\

# 3. Configure boot
bcdboot W:\Windows /s S: /f UEFI

# 4. Reboot
wpeutil reboot
```

---

## Failure Recovery Matrix — Cross-Phase

| Failure Scenario | Detection | Recovery Procedure |
|---|---|---|
| Stale WIM mount from crashed build | `Get-WindowsImage -Mounted` shows mounted WIM | `Dismount-WindowsImage -Path "C:\Mount" -Discard; dism /Cleanup-Mountpoints` |
| ISO already mounted at start of build | `Mount-DiskImage` returns existing mount | `Dismount-DiskImage -ImagePath $isoPath` |
| DISM error 0x800f0830 during package inject | Package log shows error | The update is incompatible — delete from Packages/ or accept the skip |
| oscdimg missing boot files | "boot file not found" error | Re-copy ISO contents with robocopy; verify etfsboot.com and efisys.bin are present |
| autounattend.xml not found during Setup | Setup prompts for user input | ISO was built without autounattend.xml at root; rebuild with correct file placement |
| Setup fails at disk partitioning | Setup shows partition error dialog | Disk topology doesn't match autounattend.xml — verify disk IDs match hardware |
| specialize phase BSoD | Blue screen during "Getting devices ready" | Injected driver is incompatible — remove suspect driver from Drivers/ and rebuild |
| OOBE asks for Microsoft account | Network connected during OOBE | Normal — click "I don't have internet" / "Limited setup" |
| winget not available after install | `winget` command not found | AppInstaller MSIX provisioning failed — install via: `Add-AppxPackage` from Packages/ |
| Disk 0/1 still unpartitioned after reboot | `Get-Partition` shows no partitions on Disk 0/1 | Normal — run `Configure-SecondaryDrives.ps1` manually |
| NVIDIA driver not loaded | Device Manager shows yellow ! on display | Run `pnputil /add-driver` manually as shown in Phase 9.3 |
| RAM disk not created | `R:` drive missing | Run `install-ramdisk.ps1` then `createramdisk.cmd` manually |
| Export-WindowsImage fails mid-way | Disk space error or timeout | Free disk space; delete partial output WIM; retry from Phase 5.3 |
| Capture-Image.ps1 fails in WinPE | "Windows partition not found" | Specify `-TargetDisk` explicitly; verify disk has Windows partition |

---

## Parallel Execution Map

The following steps can safely execute in parallel (same phase):

**Phase 0**: Steps 0.1, 0.2, 0.3, 0.4, 0.5 can be verified simultaneously in multiple terminal windows. 0.6 must follow 0.5.

**Phase 1**: Steps 1.1 (Test-Environment) and 1.2 (Test-UnattendXML) can run simultaneously — they operate on different resources.

**Phase 4**: Steps 4.1, 4.2, 4.3, 4.4 can run in parallel — they copy files to different locations.

**Phase 6**: Steps 6.1, 6.2, 6.3, 6.4 can run sequentially on a mounted ISO, or you can mount the ISO in multiple read-only points for simultaneous verification.

**Phase 9**: Steps 9.1, 9.2 operate on different resources (logs vs disk partitioning) and can run simultaneously. Steps 9.3 and 9.4 can run simultaneously.

**The following CANNOT be parallelized** (strictly sequential within phase):
- Phase 2: ISO mounting → copy → WIM mounting (each step depends on prior)
- Phase 3: Driver injection → Package injection → APPX provisioning (all operate on the same mounted WIM; DISM is not thread-safe on a single mount)
- Phase 5: Optimization → Dismount → Export → Second mount → Second optimization → Second export → ISO build
- Phase 8: All bare-metal steps are sequential by nature

---

## Build Time Estimates

| Phase | Operation | Estimated Time | Notes |
|---|---|---|---|
| 0 | Environment preparation | 15-30 min | One-time setup; ADK install included |
| 1 | Validation | 2-5 min | Fast — file checks only |
| 2 | ISO mount and copy | 5-15 min | Robocopy speed varies by disk |
| 2 | WIM mount | 3-10 min | Decompression overhead |
| 3 | Driver injection | 5-20 min | Depends on driver count |
| 3 | Package injection | 10-30 min | .msu files are large |
| 3 | APPX provisioning | 2-10 min | 5 packages |
| 5 | First optimization | 15-45 min | /ResetBase is slow |
| 5 | First dismount + save | 10-30 min | Writes all changes to WIM |
| 5 | First export | 20-60 min | Maximum compression is CPU-intensive |
| 5 | Second optimization | 10-30 min | |
| 5 | Second export (final WIM) | 20-60 min | |
| 5 | Recovery WIM export | 10-20 min | Recovery compression |
| 5 | oscdimg ISO build | 5-20 min | |
| **Total build** | | **~2-6 hours** | Wide variance by hardware |
| 7 | VM test | 30-60 min | Install + FirstLogon |
| 8 | Bare metal deploy | 30-90 min | Install + FirstLogon + drivers |
| 9 | Post-install config | 15-30 min | Drive partitioning + verification |

---

## Quick Reference Commands

```powershell
# ============================================================
# EMERGENCY CLEANUP (after failed build)
# ============================================================
Dismount-WindowsImage -Path "C:\Mount" -Discard -ErrorAction SilentlyContinue
Dismount-WindowsImage -Path "C:\Mnt" -Discard -ErrorAction SilentlyContinue
dism /Cleanup-Mountpoints
Remove-Item "C:\GoldISO_Build" -Recurse -Force -ErrorAction SilentlyContinue
Remove-Item "C:\Mount" -Force -ErrorAction SilentlyContinue
Remove-Item "C:\Mnt" -Force -ErrorAction SilentlyContinue

# ============================================================
# CHECK WIM MOUNT STATUS
# ============================================================
Get-WindowsImage -Mounted
dism /Get-MountedWimInfo

# ============================================================
# FULL BUILD PIPELINE (single command)
# ============================================================
Set-Location "C:\Users\C-Man\GoldISO"
.\Scripts\Test-Environment.ps1
.\Scripts\Test-UnattendXML.ps1
.\Scripts\Build-GoldISO.ps1 -Verbose

# ============================================================
# REBUILD ISO ONLY (manual, if WIM already serviced)
# ============================================================
$iso = "C:\GoldISO_Build\ISO"
oscdimg -bootdata:2#p0,e,b"$iso\boot\etfsboot.com"#pEF,e,b"$iso\efi\microsoft\boot\efisys.bin" -o -u2 -udfver102 -l"GAMEROS" "$iso" "C:\Users\C-Man\GoldISO\GamerOS-Win11x64Pro25H2.iso"

# ============================================================
# POST-INSTALL: CONFIGURE SECONDARY DRIVES
# ============================================================
Set-Location "C:\Scripts"
.\Configure-SecondaryDrives.ps1

# ============================================================
# WINPE: CAPTURE IMAGE
# ============================================================
.\Capture-Image.ps1 -TargetDisk 2

# ============================================================
# WINPE: APPLY IMAGE
# ============================================================
.\Apply-Image.ps1 -TargetDisk 2

# ============================================================
# BUILD AUDIT MODE ISO
# ============================================================
.\Scripts\Build-GoldISO.ps1 -BuildMode Audit -IncludeAuditScripts

# ============================================================
# BUILD FROM CAPTURED WIM
# ============================================================
.\Scripts\Build-GoldISO.ps1 -BuildMode Capture -CaptureWIMPath "D:\Capture.wim" -SkipDriverInjection -SkipPackageInjection
```

---

### Critical Files for Implementation

- `C:\Users\C-Man\GoldISO\Scripts\Build-GoldISO.ps1`
- `C:\Users\C-Man\GoldISO\Config\autounattend.xml`
- `C:\Users\C-Man\GoldISO\Scripts\Test-UnattendXML.ps1`
- `C:\Users\C-Man\GoldISO\Scripts\shrink-and-recovery.ps1`
- `C:\Users\C-Man\GoldISO\Scripts\Configure-SecondaryDrives.ps1`
