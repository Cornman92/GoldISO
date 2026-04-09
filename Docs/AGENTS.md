# GoldISO - Agent Guidance Document

This file provides comprehensive guidance for AI agents working with the GoldISO project.

## Project Overview

**GoldISO** is a custom Windows 11 25H2 ISO build system for "GamerOS" — a gaming-optimized Windows desktop. It integrates offline driver injection, Windows Update packages, MSIX/APPX bundles, an unattended answer file, and a custom PowerShell profile into a bootable ISO via DISM and oscdimg.

## Project Structure

```
GoldISO/
├── Scripts/                    # Build and deployment scripts
│   ├── Build-GoldISO.ps1      # Main ISO build script
│   ├── Test-UnattendXML.ps1   # Answer file validator
│   ├── Capture-Image.ps1      # WinPE image capture
│   ├── Apply-Image.ps1        # WinPE image deployment
│   ├── Modules/
│   │   └── GoldISO-Common.psm1  # Shared functions
│   └── ...
├── Config/
│   ├── autounattend.xml       # Unattended installation config (canonical source)
│   ├── winget-packages.json   # Application manifest
│   └── PowerShellProfile/     # Custom PowerShell profile
├── Drivers/                   # Driver injection source
├── Packages/                  # Windows packages (.cab, .msu)
├── Applications/
│   └── Portableapps/        # Portable applications
├── Tests/                     # Pester test suite
├── Docs/                      # Documentation
└── README.md                  # Main documentation
```

## Critical Paths

- **Source ISO**: `Win11_25H2_English_x64_v2.iso` (in project root)
- **Canonical Answer File**: `Config/autounattend.xml` — always edit this one; root copy is generated
- **Build Output**: `GamerOS-Win11x64Pro25H2.iso`
- **Working Directory**: `C:\GoldISO_Build`
- **Mount Point**: `C:\Mount`
- **Log Directory**: `Logs/` (project root, gitignored; `Logs/Pipeline/` for pipeline runs)

## Build Pipeline

1. Mount source ISO and copy to working dir
2. Mount `install.wim` for offline servicing
3. Inject drivers from `Drivers/`
4. Inject packages from `Packages/`
5. Copy `Config/autounattend.xml` to ISO root
6. Rebuild ISO with `oscdimg`

## autounattend.xml Critical Sections

| Pass | Purpose |
|------|---------|
| `windowsPE` | Disk partitioning, WinRE, offline services |
| `specialize` | .NET 3.5, driver injection, packages |
| `oobeSystem` | 47 FirstLogonCommands, auto-logon as Administrator |

**Disk Layout (Hardware-Specific):**
- **Disk 2** (Primary NVMe): EFI (300 MB) + MSR (16 MB) + Windows C: (~843 GB) + Recovery (15 GB) + ~90 GB unallocated (Samsung OP)
- **Disk 0/1**: Configured post-boot via `Configure-SecondaryDrives.ps1`

## Script Standards

All scripts must:
- Begin with `#Requires -Version 5.1` and `[CmdletBinding()]`
- Import `GoldISO-Common.psm1`
- Call `Test-GoldISOAdmin -ExitIfNotAdmin`
- Use `Write-GoldISOLog` (never `Write-Host`)
- Use `Join-Path` (never string concatenation)
- Set `$ErrorActionPreference = "Stop"`
- Log to `Logs/` directory

## Shared Module Functions

`GoldISO-Common.psm1` provides:

### Logging
- `Write-GoldISOLog` / `Write-Log` (alias)
- `Initialize-Logging`
- `Start-GoldISOTranscript`
- `Stop-GoldISOTranscript`

### Validation
- `Test-GoldISOAdmin`
- `Test-GoldISOPath`
- `Test-GoldISOWinPE`
- `Test-GoldISODiskSpace`
- `Test-GoldISOCommand`
- `Test-DiskTopology`

### Utilities
- `Format-GoldISOSize`
- `Get-GoldISORoot`
- `Invoke-GoldISOCommand`
- `Get-ComponentHash`
- `Import-BuildManifest`
- `Export-BuildManifest`
- `Invoke-GoldISOErrorThrow`
- `Register-GoldISOCleanup`
- `Invoke-GoldISOCleanup`

## Validation Commands

```powershell
# Environment check
.\Scripts\Test-Environment.ps1

# Validate answer file
.\Scripts\Test-UnattendXML.ps1

# Run test suite
.\Tests\Run-AllTests.ps1
```

## Common Commands

### Pre-Build Validation
```powershell
# Environment check (once per session)
.\Scripts\Test-Environment.ps1

# Validate autounattend.xml (before every build)
.\Scripts\Test-UnattendXML.ps1
.\Scripts\Test-UnattendXML.ps1 -Verbose   # detailed failure output

# Run test suite
.\Tests\Run-AllTests.ps1
```

### Build Commands
```powershell
# Full pipeline (validates + builds + optional VM deploy)
.\Scripts\Start-BuildPipeline.ps1
.\Scripts\Start-BuildPipeline.ps1 -DeployToVM -Verbose
.\Scripts\Start-BuildPipeline.ps1 -SkipTests -KeepArtifacts 3

# Direct build
.\Scripts\Build-GoldISO.ps1

# Build with specific modes
.\Scripts\Build-GoldISO.ps1 -BuildMode Audit -IncludeAuditScripts
.\Scripts\Build-GoldISO.ps1 -BuildMode Capture -CaptureWIMPath "C:\Capture.wim"

# Skip components (for testing)
.\Scripts\Build-GoldISO.ps1 -SkipDriverInjection -SkipPackageInjection -Verbose

# Build with settings migration
.\Scripts\Build-ISO-With-Settings.ps1 -ExportUserData -MaxUserDataSizeGB 5
```

### WinPE Capture/Apply (run in WinPE)
```powershell
.\Scripts\Capture-Image.ps1                          # capture Disk 2, move to USB
.\Scripts\Capture-Image.ps1 -TargetDisk 0 -CapturePath "D:\Custom.wim" -MoveToUSB:$false
.\Scripts\Apply-Image.ps1                            # auto-detect WIM from USB, apply to Disk 2
.\Scripts\Apply-Image.ps1 -ImagePath "D:\Capture.wim" -TargetDisk 2
```

### Post-Install (run as Administrator on target system)
```powershell
.\Scripts\Configure-SecondaryDrives.ps1   # partition Disk 0 and Disk 1 after Windows install
```

## Architecture

### Directory Layout
| Path | Purpose |
|------|---------|
| `autounattend.xml` | Build-time copy (generated by Build-GoldISO.ps1) |
| `Config/autounattend.xml` | **Canonical source** — always edit this one |
| `Config/winget-packages.json` | App manifest read by `install-usb-apps.ps1` |
| `Config/PowerShellProfile/` | Custom modular PowerShell profile (deployed to `C:\PowerShellProfile\`) |
| `Config/DiskLayouts/` | Disk partition templates — each layout is a paired `{Name}.xml` + `{Name}.json` |
| `Config/Unattend/Core/` | Master autounattend template for modular builds |
| `Config/Unattend/Passes/` | Per-pass XML fragments (`01-offlineServicing.xml` … `07-oobeSystem.xml`) |
| `Config/Unattend/Profiles/` | JSON build profiles used by `Build-Autounattend.ps1` |
| `Config/Unattend/Modules/Scripts/` | Scripts embedded or referenced during setup (e.g., `ProtectLetters.ps1`) |
| `Scripts/` | All build, validation, deployment, and utility scripts |
| `Scripts/Build/` | Modular build helpers (`Build-Autounattend.ps1`, `Build-Unattend.ps1`) |
| `Scripts/Modules/GoldISO-Common.psm1` | Shared module: logging, admin check, path validation |
| `Drivers/` | Hardware drivers organized by device class |
| `Packages/` | Windows Updates (.msu/.cab) and MSIX/APPX bundles |
| `Applications/` | Standalone installers referenced in FirstLogonCommands |
| `Logs/` | Runtime logs — gitignored (`Logs/Pipeline/` for pipeline runs) |
| `Docs/` | All AI agent guidance, roadmap, plan, and workflow docs |

### Build Pipeline
1. Mount source ISO (`Win11-25H2x64v2.iso`) and copy to working dir (`C:\GoldISO_Build`)
2. Mount `install.wim` at `C:\Mount` for offline servicing
3. Inject all drivers from `Drivers/` via `Add-WindowsDriver -Recurse`
4. Inject packages from `Packages/` via `Add-WindowsPackage` (errors skipped gracefully for outdated packages)
5. Provision MSIX/APPX bundles (PowerShell 7, Terminal, AppInstaller, etc.)
6. If `-UseModular`: call `Scripts/Build/Build-Autounattend.ps1 -DiskLayout <layout>` to generate `autounattend.xml`; else copy `Config/autounattend.xml` to ISO root
7. Dismount and rebuild ISO with `oscdimg` (UEFI dual-boot)

### Disk Layout System (Phase 3)

Layouts live in `Config/DiskLayouts/` as paired `{LayoutName}.xml` + `{LayoutName}.json`.

**Variable substitution:** XML templates use `{{VARIABLE_NAME}}` placeholders. `Build-Autounattend.ps1` reads the companion JSON to get defaults and applies string replacement before embedding the layout XML into the answer file.

```
Config/DiskLayouts/
  GamerOS-3Disk.xml / .json     ← LOCKED — DO NOT MODIFY sizes or letters
  SingleDisk-DevGaming.xml / .json
  SingleDisk-Generic.xml / .json
```

**To add a new layout:**
1. Create `{Name}.xml` (use `{{VARIABLE}}` for configurable values) and `{Name}.json` (define `variables`, `disks`, `driveLetters`)
2. Add `{Name}` to `ValidateSet` in both `Build-Autounattend.ps1` and `Build-GoldISO.ps1`
3. Update this doc and `ROADMAP.md`

### Drive Letter Protection (Phase 4)

`Config/Unattend/Modules/Scripts/ProtectLetters.ps1` runs as a FirstLogonCommand **before** any folder-creation commands. It reassigns removable media that has claimed a protected letter to a fallback letter.

**Protected letters for GamerOS-3Disk:** D, E, F, C, U, V, W, X, Y, Z, R, T, M  
**Fallback pool:** H, I, J, K, L, N, O, P, Q

Integration points:
- `Config/Unattend/Passes/07-oobeSystem.xml` Order 36 (canonical pass file)
- `Config/autounattend.xml` Order 48 (canonical answer file)
- `Build-Autounattend.ps1` `Build-FirstLogonCommands` (modular builder, `GamerOS-3Disk` only)

### GamerOS-3Disk Folder Creation

After drive letter protection, FirstLogonCommands create the expected folder structure:
- `D:\P-Apps` and `D:\Scratch` — on the 232 GB SSD (Disk 0, letter D)
- `E:\Media` and `E:\Backups` — on the 1 TB HDD (Disk 1, letter E)

These folders are created at Orders 49/50 in `Config/autounattend.xml` and at Orders 37/38 in `07-oobeSystem.xml`.

### Driver Injection Strategy
- **Offline (DISM into WIM)**: Intel system devices, ASUS, network adapters, storage controllers, IDE ATA/ATAPI controllers
- **Post-boot (FirstLogon via pnputil)**: Extensions, Software components, Audio Processing Objects (APOs), Sound/video/game controllers, Monitors, NVIDIA RTX 3060 Ti, Logitech G403 HERO

Extensions and audio/monitor categories require a running OS for correct PnP enumeration — injecting them offline via DISM causes missed associations. They are installed via `pnputil /add-driver /subdirs /install` at FirstLogon Order 51 in `Config/autounattend.xml`.

## Script Patterns

Every script must:
- Begin with `#Requires -Version 5.1` and `[CmdletBinding()]`
- Import `GoldISO-Common.psm1` and call `Test-GoldISOAdmin -ExitIfNotAdmin`
- Use `Write-GoldISOLog` (never `Write-Host`)
- Use `Join-Path` (never string concatenation for paths)
- Log to `Logs/` at project root — path: `Join-Path (Split-Path $PSScriptRoot -Parent) "Logs\<name>-<ts>.log"`
- Never hardcode `C:\Users\C-Man\GoldISO` — use `Get-GoldISORoot` or `$script:ProjectRoot`
- Wrap DISM calls in try/catch; log WARN and continue on failure

## PowerShell Profile

- Source: `Config/PowerShellProfile/` (30+ modular scripts in `PSProfile.C-Man/`)
- Deployed to `C:\PowerShellProfile\` during FirstLogon
- Lazy-loading design; theme/config via `Config/PowerShellProfile/Config/profile-config.json`

## Key Constraints

1. Always validate `autounattend.xml` after edits
2. `Config/autounattend.xml` is the **canonical source** — root `autounattend.xml` is a build-time copy
3. No TPM/Secure Boot bypasses (by design)
4. Network disabled during OOBE (re-enabled in FirstLogonCommands)
5. ~95 GB unallocated on Disk 2 is **intentional** Samsung NVMe overprovisioning — do NOT add partitions
6. Disk IDs are machine-specific
7. Test in Hyper-V VM before bare-metal
8. PS 5.1 only — no `??=`, no `ForEach-Object -Parallel`, no PS7-only syntax
9. Log files go in `Logs/` (project root) — not `Scripts/Logs/` or script directory

## Winhance Scripts (autounattend.xml Extensions)

These extract to `C:\ProgramData\Winhance\Unattend\Scripts\` during specialize:

| Script | Purpose |
|--------|---------|
| `shrink-and-recovery.ps1` | Shrinks C:, creates Recovery, leaves OP space |
| `install-usb-apps.ps1` | Installs winget packages by category |
| `install-ramdisk.ps1` | Installs SoftPerfect RAM Disk |
| `createramdisk.cmd` | Creates 8 GB RAM disk at R: |
| `tweaks-system.cmd` | HKLM performance registry tweaks |
| `tweaks-user.cmd` | HKCU performance registry tweaks |

## System Health & Reporting Scripts

| Script | Location | Purpose |
|--------|----------|---------|
| `Test-SystemHealth.ps1` | `Scripts/Testing/` | Checks Windows Update status, service state, disk space, and basic system health. Returns pass/fail summary. Run post-install to confirm baseline. |
| `Get-SystemReport.ps1` | `Scripts/Testing/` | Generates comprehensive 667-line diagnostic report: hardware inventory, driver versions, installed apps, network config, performance counters. Outputs to `Logs/SystemReport-<ts>.txt`. |
| `Measure-BuildTime.ps1` | `Scripts/Testing/` | Instruments build pipeline stages; outputs per-stage timing to `Logs/build-metrics-<date>.json`. |
| `Test-VMPerformance.ps1` | `Scripts/Testing/` | Runs performance baseline inside Hyper-V test VM. |

These scripts are not wired into the build pipeline — run them manually post-install or post-build.

## Prerequisites

- Windows 10/11 or Windows Server 2019+
- PowerShell 5.1+ (Administrator)
- Windows ADK with Deployment Tools (for `oscdimg`)
- 20 GB+ free space
- Source ISO in project root

## Notes

- The test suite requires Pester 5.0+
- All scripts are designed for PS 5.1 compatibility
- Driver injection organized by device class
- Portable apps auto-copied to ISO
- Build creates working copy of source ISO (original never modified)

---

*Canonical AI agent guidance for GoldISO. This is the single source of truth for project documentation.*
