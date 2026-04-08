# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

**GoldISO** is a custom Windows 11 25H2 ISO build system for "GamerOS" — a gaming-optimized Windows desktop. It integrates offline driver injection, Windows Update packages, MSIX/APPX bundles, an unattended answer file, and a custom PowerShell profile into a bootable ISO via DISM and oscdimg.

The companion build pipeline project lives at `C:\Users\C-Man\GWIG` (separate repo). GWIG provides `Invoke-GamerOSPipeline-v2.ps1` and 94 pipeline stages for automated builds; see its own `Docs/Root/AGENTS.md`.

## Common Commands

All scripts require **Administrator PowerShell**. Scripts use `$ErrorActionPreference = "Stop"` by default (except `Build-GoldISO.ps1`, which uses `"Continue"` for resilience).

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

### Build ISO
```powershell
# Preferred: CI pipeline (validates + builds + optional VM deploy)
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

### Manual ISO rebuild (if not using Build-GoldISO.ps1)
```powershell
oscdimg -bootdata:2#p0,e,b"C:\ISO_Work\boot\etfsboot.com"#pEF,e,b"C:\ISO_Work\efi\microsoft\boot\efisys.bin" -o -u2 -udfver102 -l"GAMEROS" "C:\ISO_Work" "GamerOS_Win11_25H2.iso"
```

## Architecture

### Directory Layout
| Path | Purpose |
|------|---------|
| `autounattend.xml` | **Primary answer file** — controls entire unattended install |
| `Config/autounattend.xml` | Same file (Config/ is the canonical config directory) |
| `Config/winget-packages.json` | App manifest read by `install-usb-apps.ps1` |
| `Config/GamerOS Windows 11.xml` | NTLite preset — removes 500+ Windows components |
| `Config/PowerShellProfile/` | Custom modular PowerShell profile (deployed to `C:\PowerShellProfile\`) |
| `Scripts/` | All build, validation, deployment, and utility scripts |
| `Scripts/Modules/GoldISO-Common.psm1` | Shared module: logging, admin check, path validation |
| `Drivers/` | Hardware drivers organized by device class |
| `Packages/` | Windows Updates (.msu/.cab) and MSIX/APPX bundles |
| `Applications/` | Standalone installers referenced in FirstLogonCommands |

### Build Pipeline (manual steps automated by Build-GoldISO.ps1)
1. Mount source ISO (`Win11-25H2x64v2.iso`) and copy to working dir (`C:\GoldISO_Build`)
2. Mount `install.wim` at `C:\Mount` for offline servicing
3. Inject all drivers from `Drivers/` via `Add-WindowsDriver -Recurse`
4. Inject packages from `Packages/` via `Add-WindowsPackage` (errors skipped gracefully for outdated packages)
5. Provision MSIX/APPX bundles (PowerShell 7, Terminal, AppInstaller, etc.)
6. Copy `autounattend.xml` to ISO root
7. Dismount and rebuild ISO with `oscdimg` (UEFI dual-boot)

### autounattend.xml — Critical Sections
| Pass | Purpose |
|------|---------|
| `windowsPE` | Disk partitioning, WinRE, offline services |
| `specialize` | .NET 3.5, driver injection, package installation, ExecutionPolicy |
| `oobeSystem` | 43 FirstLogonCommands, auto-logon as Administrator |

**Disk layout** (hardware-specific — verify topology before deployment):
- **Disk 2** (Primary NVMe): EFI (300 MB) + MSR (16 MB) + Windows C: (~843 GB) + Recovery (15 GB) + ~90 GB unallocated (Samsung NVMe overprovisioning — do NOT partition)
- **Disk 0 / Disk 1**: Wiped only during install; `Configure-SecondaryDrives.ps1` creates partitions post-boot

### Driver Injection Strategy
- **Offline (DISM into WIM)**: Intel system devices, ASUS, network adapters, storage controllers, IDE/ATA, extensions, software components, audio, monitors
- **Post-boot (FirstLogon via pnputil)**: NVIDIA RTX 3060 Ti, Logitech G403 HERO

### Winhance Scripts (extracted from autounattend.xml `<Extensions>`)
These scripts live in `Scripts/` but are also embedded in autounattend.xml to extract themselves to `C:\ProgramData\Winhance\Unattend\Scripts\` during specialize. **Do not manually pre-create those paths.**

| Script | What it does |
|--------|-------------|
| `Scripts/shrink-and-recovery.ps1` | Shrinks C: by 105 GB, creates 15 GB Recovery partition, leaves ~90 GB for Samsung OP |
| `Scripts/install-usb-apps.ps1` | Installs winget packages from `winget-packages.json` by category |
| `Scripts/install-ramdisk.ps1` | Installs SoftPerfect RAM Disk (USB-first, download fallback) |
| `Scripts/createramdisk.cmd` | Creates 8 GB RAM disk at R: |
| `Scripts/tweaks-system.cmd` | HKLM performance registry tweaks |
| `Scripts/tweaks-user.cmd` | HKCU performance registry tweaks |

### Shared Module
`Scripts/Modules/GoldISO-Common.psm1` provides: `Write-GoldISOLog`, `Test-GoldISOAdmin`, `Test-GoldISOPath`, `Format-GoldISOSize`, `Test-GoldISOWinPE`, `Get-GoldISORoot`, `Invoke-GoldISOCommand`, `Initialize-Logging`.

**Always use the module** — do not duplicate these functions inline.

### PowerShell Profile
- Source: `Config/PowerShellProfile/` (30+ modular scripts in `PSProfile.C-Man/`)
- Deployed to `C:\PowerShellProfile\` during FirstLogon
- Lazy-loading design; theme/config via `Config/profile-config.json`

## Prerequisites
- Windows 10/11 or Windows Server 2019+ (for DISM)
- PowerShell 5.1+, run as Administrator
- Windows ADK with Deployment Tools (for `oscdimg`)
- 20 GB+ free space on C:
- Source ISO: `Win11-25H2x64v2.iso` in project root

## Key Constraints
- **Always validate `autounattend.xml`** with `Test-UnattendXML.ps1` after any edit
- **`Config/autounattend.xml` is the canonical source** — root `autounattend.xml` is a build-time copy produced by `Build-GoldISO.ps1`; edit only the Config/ version
- **Do not bypass TPM/Secure Boot** — no requirement bypasses are present by design
- **Network is disabled during OOBE** (intentional, re-enabled in FirstLogonCommands step 1)
- **~95 GB unallocated on Disk 2 is intentional** Samsung NVMe overprovisioning — do NOT add partitions
- **Disk IDs are machine-specific** — Disk 2 = primary NVMe on target hardware; verify before deployment
- **Test in Hyper-V VM** (`New-TestVM.ps1`) before bare-metal deployment
- **Log files go in `Scripts/Logs/`** — not in the script directory root
- Logs: build scripts → `C:\GoldISO_Build\build.log`; post-install scripts → `C:\Scripts\Logs\`

## Agent Documentation
All AI agent guidance files live in `Docs/`. See `Docs/AGENTS.md` for the master reference and `Docs/ROADMAP.md` for the development roadmap.
