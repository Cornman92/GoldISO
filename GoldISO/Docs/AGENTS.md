# GoldISO - Agent Guidance

**Last Updated**: 2026-04-08 (Pipeline v2, PassThru, Sequential FirstLogon)

## Project Identity
GoldISO — Custom Windows 11 25H2 ISO build for "GamerOS" desktop. Integrates drivers, packages, apps, and unattended setup into a bootable ISO.

## Prerequisites
- Windows 10/11 or Windows Server 2019+ (for DISM)
- PowerShell 5.1+, run as Administrator
- Windows ADK with Deployment Tools (for `oscdimg`)
- 20 GB+ free space on C:
- Source ISO: `Win11_25H2_English_x64_v2.iso` in project root

## Source ISO & Paths
- **Source ISO**: `C:\Users\C-Man\GoldISO\Win11_25H2_English_x64_v2.iso`
- **GWIG Project**: `C:\Users\C-Man\GWIG` (main development repo with DISM pipeline tools)
- **Working Directory**: `C:\Users\C-Man\GoldISO`

## Log Locations
- Build scripts: `C:\GoldISO_Build\build.log`
- Post-install scripts: `C:\Scripts\Logs\`

## Common Commands
All scripts require **Administrator PowerShell**. Scripts use `$ErrorActionPreference = "Stop"` by default (except `Build-GoldISO.ps1`, which uses `"Continue"` for resilience).

### Pre-Build Validation
```powershell
# Environment check (run once per session)
.\Scripts\Test-Environment.ps1

# Validate autounattend.xml (before every build)
.\Scripts\Test-UnattendXML.ps1
.\Scripts\Test-UnattendXML.ps1 -Verbose   # detailed failure output
.\Scripts\Test-UnattendXML.ps1 -PassThru # returns structured object for pipelines
```

### Build ISO
```powershell
# Standard build
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

### Manual ISO rebuild
```powershell
oscdimg -bootdata:2#p0,e,b"C:\ISO_Work\boot\etfsboot.com"#pEF,e,b"C:\ISO_Work\efi\microsoft\boot\efisys.bin" -o -u2 -udfver102 -l"GAMEROS" "C:\ISO_Work" "GamerOS_Win11_25H2.iso"
```

## Build Script Parameters

| Parameter | Purpose |
|-----------|---------|
| `-BuildMode` | Build mode: `Audit` (sysprep audit mode), `Capture` (WIM capture) |
| `-SkipDriverInjection` | Skip driver injection for testing |
| `-SkipPackageInjection` | Skip package injection for testing |
| `-SkipPortableApps` | Skip portable apps copy for testing |
| `-IncludeAuditScripts` | Include audit mode scripts |
| `-CaptureWIMPath` | Custom WIM capture path |
| `-ExportUserData` | Export user settings for migration |
| `-MaxUserDataSizeGB` | Max user data size for migration (default: 5 GB) |
| `-OutputISO` | Custom output ISO path |
| `-Verbose` | Enable verbose logging |

## Test-UnattendXML.ps1 Parameters

| Parameter | Purpose |
|-----------|---------|
| `-AnswerFile` | Custom answer file path |
| `-Strict` | Treat warnings as errors |
| `-PassThru` | Returns structured hashtable `{Status, Passed, Warnings, Errors}` |

## Directory Structure
```
GoldISO/
├── autounattend.xml              # Unattended answer file (PRIMARY)
├── autounattend.xml.backup       # Previous version (multi-disk config)
├── winget-packages.json          # Categorized app manifest (winget install source)
├── Configure-SecondaryDrives.ps1 # Post-boot script for Disk 0/1 partitioning
├── WinhanceInstaller.exe         # Winhance installer binary
├── GamerOS Windows 11.xml        # NTLite preset (component removal list)
├── Config/PowerShellProfile/     # Custom PowerShell profile
│   ├── Microsoft.PowerShell_profile.ps1
│   ├── init.ps1
│   ├── PSProfile.C-Man/          # 30+ modular profile scripts
│   └── Config/profile-config.json
├── Scripts/                      # Build, validation, and deployment scripts
│   ├── Build-GoldISO.ps1         # Main ISO builder
│   ├── Test-UnattendXML.ps1      # Answer file validator
│   ├── Test-Environment.ps1      # Environment pre-flight checks
│   ├── Capture-Image.ps1        # WinPE WIM capture
│   ├── Apply-Image.ps1          # WinPE WIM apply
│   ├── Build-ISO-With-Settings.ps1 # Settings migration build
│   └── Modules/GoldISO-Common.psm1 # Shared utilities
├── Drivers/                      # Hardware drivers organized by device class
│   ├── Display adapters/         # NVIDIA RTX 3060 Ti (32.0.15.6094) — POST-INSTALL
│   ├── System devices/           # Intel MEI, Host Bridge — INJECTED OFFLINE
│   ├── Network adapters/         # Network drivers — INJECTED OFFLINE
│   ├── Storage controllers/      # Storage drivers — INJECTED OFFLINE
│   ├── IDE ATA ATAPI controllers/# IDE drivers — INJECTED OFFLINE
│   ├── Extensions/               # Extension drivers — INJECTED OFFLINE
│   ├── Software components/      # Software drivers — INJECTED OFFLINE
│   ├── Audio Processing Objects/ # Audio drivers — INJECTED OFFLINE
│   ├── Sound, video and game/    # Audio drivers — INJECTED OFFLINE
│   ├── Monitors/                 # Monitor drivers — INJECTED OFFLINE
│   └── Universal Serial Bus/     # Logitech G403 HERO — POST-INSTALL
├── Packages/                     # Windows updates, MSIX bundles, APPX packages
│   ├── *.msu                     # Cumulative updates, .NET 4.8.1 updates
│   ├── *.cab                     # Driver/feature CABs
│   ├── *.msixbundle              # PowerShell 7, Terminal, AppInstaller
│   └── *.appx                    # WindowsAppRuntime, UI.Xaml
└── Applications/
    ├── Winslopr-26.03.230-win-x64/  # Windows optimization tool (scripts + plugins)
    ├── windowsmanager.exe
    └── wox-windows-amd64.exe
```

## Build Pipeline (manual steps automated by Build-GoldISO.ps1)
1. Mount source ISO (`Win11_25H2_English_x64_v2.iso`) and copy to working dir (`C:\GoldISO_Build`)
2. Mount `install.wim` at `C:\Mount` for offline servicing
3. Inject all drivers from `Drivers/` via `Add-WindowsDriver -Recurse`
4. Inject packages from `Packages/` via `Add-WindowsPackage` (errors skipped gracefully for outdated packages)
5. Provision MSIX/APPX bundles (PowerShell 7, Terminal, AppInstaller, etc.)
6. Copy `autounattend.xml` to ISO root
7. Dismount and rebuild ISO with `oscdimg` (UEFI dual-boot)

## autounattend.xml — Critical Sections

### Pass Overview
| Pass | Purpose |
|------|---------|
| `windowsPE` | Disk partitioning, WinRE, offline services |
| `specialize` | .NET 3.5, driver injection, package installation, ExecutionPolicy |
| `oobeSystem` | 47 FirstLogonCommands (sequential 1-47), auto-logon as Administrator |

### Disk Configuration (hardware-specific — verify topology before deployment)
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

## Shared Module
`Scripts/Modules/GoldISO-Common.psm1` provides 8 exported functions:

| Function | Purpose |
|----------|---------|
| `Initialize-Logging` | Sets up log file path and ensures log directory exists |
| `Write-GoldISOLog` | Writes timestamped log messages with level (INFO/WARN/ERROR/SUCCESS) |
| `Test-GoldISOAdmin` | Tests for Administrator privileges, optionally exits if not admin |
| `Test-GoldISOPath` | Validates file/directory existence, optionally creates directories |
| `Format-GoldISOSize` | Formats bytes to human-readable size (KB/MB/GB/TB) |
| `Test-GoldISOWinPE` | Detects WinPE environment (multiple methods) |
| `Get-GoldISORoot` | Returns GoldISO project root path |
| `Invoke-GoldISOCommand` | Executes commands with timeout and captures output |

## Manifests & Infrastructure Scripts

### Build Manifests
| File | Purpose |
|------|---------|
| `Config/build-manifest.json` | Build version tracking, profiles |
| `Drivers/download-manifest.json` | Driver download URLs, installed versions |
| `Packages/manifest.json` | Windows Update package tracking |
| `Config/hardware-matrix.json` | Tested hardware profiles |

### Infrastructure Scripts
```powershell
# View current build manifest
.\Scripts\Get-BuildManifest.ps1
.\Scripts\Get-BuildManifest.ps1 -ShowDetails

# Driver management
.\Scripts\Get-DriverVersions.ps1                     # Scan and report driver versions

# Pre-build validation
.\Scripts\Backup-Config.ps1                          # Backup config before build

# Post-build validation
.\Tests\Test-ISO.ps1                                  # Validate built ISO
.\Tests\Verify-Drivers.ps1                             # Verify driver integrity

# Pre-deployment validation
.\Tests\Test-DiskTopology.ps1                         # Validate disk layout
```

## Winget Packages (winget-packages.json)
All packages marked `"Optional": true` (but all should be installed). Category install paths:

| Category | InstallPath | Packages |
|---|---|---|
| `browsers` | Default | Chrome, OperaGX |
| `dev_tools` | `C:\Dev` | VS Code, Git, GitHub CLI, Python 3.12, Node.js LTS, PowerShell, OhMyPosh, zoxide, Docker Desktop, PowerToys |
| `gaming` | `C:\Gaming` | Steam, Epic, GOG Galaxy, Battle.net, Xbox, Ubisoft Connect, EA, Parsec |
| `media` | `C:\Media` | VLC, HandBrake, ShareX, Discord, Spotify |
| `utilities` | `C:\Utils` | 7zip, Everything, Notepad++, WizTree, CPU-Z, GPU-Z, HWiNFO, WinRAR, Rufus, Ventoy, Windows Terminal, Logitech GHUB |
| `remote` | `C:\Remote` | AnyDesk, Tailscale |

## PowerShell Profile
- Source: `Config/PowerShellProfile/` (30+ modular scripts in `PSProfile.C-Man/`)
- Deployed to `C:\PowerShellProfile\` during FirstLogon
- Lazy-loading design; theme/config via `Config/profile-config.json`

## GWIG Integration Notes
- GWIG at `C:\Users\C-Man\GWIG` contains the full DISM pipeline tooling
- Use GWIG's `Invoke-GamerOSPipeline-v2.ps1` for automated build
- GWIG config: `Config/UnifiedGWIG-Config.json`
- Pipeline stages in `Scripts/Core/Pipeline/` (94 stages)
- See `C:\Users\C-Man\GWIG\Docs\Root\AGENTS.md` for GWIG-specific guidance

## CI/CD Pipeline
`Scripts/Start-BuildPipeline.ps1` orchestrates the full build with stages:
- Environment validation
- autounattend.xml validation (returns structured result via `-PassThru`)
- Build execution (`Build-GoldISO.ps1`)
- Post-build validation
- Artifact generation and cleanup
- Optional: `-DeployToVM` deploys to Hyper-V for automated testing
- Optional: `-Notify` sends webhook on completion

```powershell
# Preferred build entry point
.\Scripts\Start-BuildPipeline.ps1
.\Scripts\Start-BuildPipeline.ps1 -DeployToVM -Verbose
.\Scripts\Start-BuildPipeline.ps1 -SkipTests -KeepArtifacts 3

# VM Testing
.\Scripts\New-TestVM.ps1 -ISOPath "C:\Path\to\GoldISO.iso" -StartAfterCreation
```

## Additional Scripts (Post-Install / Utility)
| Script | Purpose |
|--------|---------|
| `Scripts/Get-SystemHealth.ps1` | Full system health report (642 lines) |
| `Scripts/Get-SystemReport.ps1` | Detailed system inventory (640 lines) |
| `Scripts/Backup-Macrium.ps1` | Macrium Reflect backup automation |
| `Scripts/Configure-RamDisk.ps1` | SoftPerfect RAM disk configuration |
| `Scripts/Configure-RemoteAccess.ps1` | AnyDesk/Tailscale/RDP setup |
| `Scripts/Invoke-SystemCleanup.ps1` | Post-install cleanup automation |
| `Scripts/Manage-WindowsFeatures.ps1` | Windows optional features management |
| `Scripts/Repair-SystemImage.ps1` | DISM/SFC repair automation |
| `Scripts/Test-NetworkStack.ps1` | Network connectivity validation |
| `Scripts/Measure-BuildTime.ps1` | Build performance analytics |
| `Scripts/Test-VMPerformance.ps1` | Hyper-V VM performance testing |

## Agent Documentation Index
All agent-specific guidance files live in `Docs/`:
| File | Agent | Focus |
|------|-------|-------|
| `Docs/AGENTS.md` | All | Master reference |
| `Docs/SWE.md` | SWE agents | Code quality, patterns |
| `Docs/KIMI.md` | Kimi | Long-context analysis |
| `Docs/Gemini.md` | Gemini | Documentation, logs |
| `Docs/QWEN.md` | Qwen | Script writing, XML/JSON |
| `Docs/Nemotron.md` | Nemotron | Hardware, performance |
| `Docs/Codex.md` | Codex | Code completion, templates |
| `Docs/BigPickle.md` | BigPickle | Orchestration, status |
| `Docs/ROADMAP.md` | All | Development roadmap |

## Key Constraints
- **Always validate `autounattend.xml`** with `Test-UnattendXML.ps1` after any edit
- **Do not bypass TPM/Secure Boot** — no requirement bypasses are present by design
- **Network is disabled during OOBE** (intentional, re-enabled in FirstLogonCommands step 1)
- **~95 GB unallocated on Disk 2 is intentional** Samsung NVMe overprovisioning
- **Disk IDs are machine-specific** — Disk 2 = primary NVMe on target hardware; verify before deployment
- **Test in Hyper-V VM** (`New-TestVM.ps1`) before bare-metal deployment
- Logs: build scripts → `C:\GoldISO_Build\build.log`; post-install scripts → `C:\Scripts\Logs\`

## Verification Checklist
- [ ] ISO mounts and files accessible
- [ ] WIM image mounts successfully (requires proper DISM permissions - target hardware or WinPE)
- [ ] All .msu/.cab packages integrate without errors (outdated packages should skip gracefully)
- [ ] All drivers integrate (check for architecture mismatches)
- [ ] autounattend.xml validates (Test-UnattendXML.ps1 -PassThru returns Status: "Passed")
- [ ] FirstLogon orders are sequential (1-47)
- [ ] ISO rebuilds with UEFI boot support
- [ ] Test install in VM before bare metal deployment
- [ ] Verify Disk 0/1 are wiped but unpartitioned after install
- [ ] Verify ~95 GB unallocated space on Disk 2 (Samsung OP)
- [ ] Verify C:\Scripts, C:\Dev, C:\Gaming, C:\Utils, C:\Media, C:\Remote, C:\PowerShellProfile exist post-boot
- [ ] Verify NVIDIA and Logitech drivers installed post-boot
- [ ] Run Configure-SecondaryDrives.ps1 to partition Disk 0 and Disk 1

## Environment Notes
- **WIM Mounting**: Requires proper DISM permissions. Works on target hardware or in WinPE (not VM limitations).
- **Pipeline**: Use `-DeployToVM` to automatically create Hyper-V test VM after build.
- **Language Files**: Non-English language files removed from Applications (7-Zip, CCleaner, FileVoyager, etc.).