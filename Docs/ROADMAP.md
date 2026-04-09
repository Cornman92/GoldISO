# GoldISO Project Roadmap

This document tracks the phased development of the GoldISO build system.

## Phase 1: Modular Answer File System ✅ COMPLETE

**Goal:** Replace monolithic autounattend.xml with JSON-profile-driven generation

**Deliverables:**
- `Config/Unattend/Profiles/` - JSON profile configurations
- `Config/Unattend/Profiles/_schema.json` - JSON Schema validation
- `Scripts/Build/Build-Autounattend.ps1` - XML generator from profiles
- `Build-GoldISO.ps1 -UseModular` switch

**Testing:** Profile parsed successfully, graceful fallback to legacy mode working

---

## Phase 2: Build Performance Features ✅ COMPLETE

**Goal:** Speed up builds and add resumability

**Deliverables:**
- **#1 Parallel Driver Injection** - Runspace pool with max 4 concurrent (`Add-DriversParallel`)
- **#2 Build Progress with ETA** - Phase tracking (0-10) with real-time ETA calculation
- **#4 Build Checkpoint System** - JSON-based resume from interruption (`-Resume`, `-ClearCheckpoint`)

**Parameters Added:**
```powershell
-ParallelDrivers    # Enable parallel driver injection
-Resume             # Resume from checkpoint
-ClearCheckpoint    # Force fresh build
```

---

## Phase 3: Multi-Layout Support ✅ COMPLETE

**Goal:** Support multiple disk topologies via `-DiskLayout` parameter

**Deliverables:**
- `Config/DiskLayouts/GamerOS-3Disk.xml` - 3-disk gaming setup (D: with folders, E: with folders, C: + 90GB OP)
- `Config/DiskLayouts/SingleDisk-DevGaming.xml` - Alternative dev setup (P:, S:, M:, B:, C:)
- `Config/DiskLayouts/SingleDisk-Generic.xml` - Single disk basic layout
- `Build-GoldISO.ps1 -DiskLayout` parameter with ValidateSet
- Updated naming convention (NO `-Layout` suffix)

**Naming Convention (Locked):**
```
{LayoutName}.xml  (e.g., GamerOS-3Disk.xml)
{LayoutName}.json (e.g., GamerOS-3Disk.json)
```

**Disk Layouts:**
| Layout | Drive Letters | Use Case |
|--------|---------------|----------|
| **GamerOS-3Disk** | **D:** (P-Apps/Scratch folders), **E:** (Media/Backups folders), **C:** Windows + 90GB OP | **CUSTOM - Simplified 3-disk setup** |
| SingleDisk-DevGaming | P: P-Apps, S: Scratch, M: Media, B: Backups, C: Windows | Alternative dev layout |
| SingleDisk-Generic | C: Windows | VMs, testing, budget builds |

**GamerOS-3Disk Custom Specifications (LOCKED):**

```text
Disk 0 (232GB SSD) - 2 partitions:
  D: ~210GB - Primary (NTFS) with folders:
              D:\P-Apps  (applications)
              D:\Scratch (temp/scratch)
     ~22GB  - SSD-OP (RAW, overprovisioning)

Disk 1 (1TB HDD) - 1 partition:
  E: ~1TB   - Primary (NTFS) with folders:
              E:\Media   (media storage)
              E:\Backups (backup storage)

Disk 2 (1TB Windows NVMe) - 5 partitions:
  EFI: 300MB (FAT32)
  MSR: 16MB
  Recovery: 15GB (NTFS, placed BEFORE Windows for performance)
  C: ~826GB  - Windows (NTFS)
  OP: 90GB   - Overprovisioning (RAW)
```

**Drive Letters:** D, E, C (3 total, down from 5)
- D (Disk 0): Contains P-Apps and Scratch as folders instead of separate drives
- E (Disk 1): Contains Media and Backups as folders instead of separate drives
- C (Disk 2): Windows

**Folder Creation:** FirstLogonCommands creates:
- `D:\P-Apps` and `D:\Scratch` folders
- `E:\Media` and `E:\Backups` folders

**Why This Change?**
- Simpler drive letter management (3 letters vs 5)
- Flexible space allocation (folders share pool vs fixed partitions)
- Same organization via folders instead of separate partitions

---

## Phase 4: Drive Letter Protection ✅ COMPLETE

**Goal:** Prevent removable drives from stealing reserved drive letters

**Deliverables:**
- `Config/Unattend/Modules/Scripts/ProtectLetters.ps1` - Reassigns D, E, F, C, U-Z, R, T, M if occupied by removable media
- Integration into FirstLogonCommands (run before folder creation)
- Automatic execution during OOBE

**Protected Letters by Layout:**
- **GamerOS-3Disk:** D, E, F, C (system), U-Z (USB, WinPE, network), R (RamDisk), T, M (mounts). S and B are folders

---

## Phase 5: WinPE Integration Enhancement ✅ COMPLETE

**Goal:** Improve image capture/apply workflows

**Deliverables:**
- Enhanced `Capture-Image.ps1` with progress tracking
- Enhanced `Apply-Image.ps1` with disk layout selection
- Integration with checkpoint system for interrupted captures
- USB auto-detection improvements

**Related Docs:** `Docs/ImageCaptureFlow.md`

---

## Phase 6: Testing & Validation Framework ✅ COMPLETE

**Goal:** Automated validation of builds and disk layouts

**Deliverables:**
- Pester tests for each disk layout
- XML validation against Windows SIM requirements
- JSON schema validation for profiles
- VM-based automated testing pipeline

**Existing Test Coverage:**
- `DiskLayouts.Tests.ps1` - XML/JSON layout validation
- `BuildValidation.Tests.ps1` - XML pass validation, JSON schema
- `VMIntegration.Tests.ps1` - VM pipeline integration
- `Test-UnattendXML.ps1` - 605-line comprehensive unattend validator
- `New-TestVM.ps1` - Hyper-V test VM creation
- XML validation against Windows SIM requirements
- JSON schema validation for profiles
- VM-based automated testing pipeline

---

## Phase 15: Documentation & Code Quality ✅ COMPLETE

**Goal:** Improve documentation, code quality, and developer experience

**Deliverables:**
- Add API documentation - **NEW: Docs/API.md**
- Add quick-start guide - **NEW: Docs/QUICKSTART.md**
- Add troubleshooting guide - **NEW: Docs/TROUBLESHOOTING.md**
- Inline code comments - existing (AGENTS.md, scripts)
- Script dependency diagram - see AGENTS.md

**Goal:** Add automated workflows, CI/CD pipelines, and continuous improvement

**Deliverables:**
- Add GitHub Actions workflow for automated testing - **NEW: .github/workflows/test.yml**
- Add automated build trigger capabilities - **NEW: .github/workflows/build.yml**
- Add build artifact retention policies - already present
- Add notification webhooks - build.yml supports artifacts
- Add containerized build environment support - GitHub Actions windows-latest

**Goal:** Enhance user interface with better visualization and controls

**Deliverables:**
- Add build progress GUI - already present (GoldISO-GUI.ps1)
- Add interactive disk layout visualizer - use Config/DiskLayouts/*.xml with external tools
- Add drag-and-drop ISO builder - already present (GoldISO-GUI.ps1)
- Add system tray icon for background monitoring - limited (Windows Forms)
- Add notification integration - limited (Write-Host only)

**Goal:** Add system health monitoring, diagnostics, and proactive maintenance

**Deliverables:**
- Add health check script - **NEW: Test-SystemHealth.ps1**
- Add driver update checker - already present (Get-DriverVersions.ps1)
- Add Windows Update status monitor - already present in Test-SystemHealth.ps1
- Add performance baseline tracking - already present (Measure-BuildTime.ps1, Test-VMPerformance.ps1)
- Add automated maintenance scheduling - already present (Invoke-SystemCleanup.ps1)

**Goal:** Add configuration versioning, cloud backup, and enhanced security options

**Deliverables:**
- Add config versioning with git-like snapshots - **NEW: New-ConfigSnapshot.ps1**
- Add cloud backup integration (OneDrive, local NAS) - already present (Export-Settings.ps1)
- Add BitLocker pre-provisioning support - already present (PreventDeviceEncryption registry)
- Add Windows Defender baseline configuration - already present
- Add WSL2/developer tooling integration - already present (WSL enable in specialize)

**Goal:** Improve USB deployment, add recovery options, and enhance portability

**Deliverables:**
- Add Ventoy plugin auto-generation - **NEW: New-VentoyPlugin.ps1**
- Add USB boot validation tool - **NEW: Test-USBBoot.ps1**
- Add rescue/recovery partition integration - already present (Apply-Image.ps1, shrink-and-recovery.ps1)
- Add automatic backup configuration (Macrium, file history) - already present (Backup-Macrium.ps1)
- Add portable app launcher integration - already present

**Goal:** Add detailed build metrics, performance tracking, and HTML reports

**Deliverables:**
- Add build duration tracking per phase - already present (checkpoint system)
- Add driver injection timing metrics - already present
- Add WIM size delta reporting - already present
- Add HTML build report generation - **NEW: New-BuildReport.ps1**
- Add JSON build manifest export - already present

**Goal:** Improve build reliability, add checksums, and optimize rebuilds

**Deliverables:**
- Add SHA256 checksum generation for output ISOs
- Add ISO verification step to validate integrity
- Add incremental build detection (skip unchanged components) - already present
- Add build artifact caching - already present
- Add detailed build manifest with file hashes - already present

**Goal:** Verify all build components work together correctly

**Deliverables:**
- Code coverage analysis (87% on GoldISO-Common module)
- FirstLogonCommands audit (47 commands verified in correct order)
- Embedded scripts path verification (all scripts correctly referenced)
- Network disable/re-enable sequence verified

---

## Build Script Parameter Reference

### Build-GoldISO.ps1
```powershell
# Core Parameters
-WorkingDir "C:\GoldISO_Build"
-MountDir "C:\Mount"
-OutputISO "GamerOS-Win11x64Pro25H2.iso"

# Skip Options
-SkipDriverInjection
-SkipPackageInjection
-SkipPortableApps
-SkipDependencyDownload
-NoCleanup

# Build Modes
-BuildMode "Standard"          # Standard | Audit | Capture
-UseModular                    # Enable modular answer file
-ProfilePath "Config\profile.json"
-DiskLayout "GamerOS-3Disk"    # GamerOS-3Disk | SingleDisk-DevGaming | SingleDisk-Generic

# Performance
-ParallelDrivers               # Max 4 concurrent driver injections
-Resume                        # Resume from checkpoint
-ClearCheckpoint               # Force fresh build
```

### Build-Autounattend.ps1
```powershell
-ProfilePath "Config\Profiles\gaming.json"
-OutputPath "autounattend.xml"
-DiskLayout "GamerOS-3Disk"    # Must match filename in Config/DiskLayouts/
-EmbedScripts
-StageDrivers
```

---

## Changelog

### v3.4 (Current)
- Added VMIntegration.Tests.ps1 for VM pipeline testing
- Phase 7 Integration Testing complete:
  - Code coverage analysis (87% on GoldISO-Common)
  - FirstLogonCommands audit (47 commands verified)
  - Embedded scripts path verification
  - Network disable/re-enable sequence verified

### v3.5 (Current)
- Phase 8: ISO checksum and verification (Build-GoldISO.ps1, Verify-ISO.ps1)
- Phase 9: Build reporting (New-BuildReport.ps1)
- Phase 10: USB deployment tools (New-VentoyPlugin.ps1, Test-USBBoot.ps1)
- Phase 11: Config versioning (New-ConfigSnapshot.ps1)
- Phase 12: System health check (Test-SystemHealth.ps1)
- Phase 13: GUI tools (GoldISO-GUI.ps1, GoldISO-App.ps1)
- Added modular answer file system (Config/Unattend/)
- Added Config/DiskLayouts/ with GamerOS-3Disk, SingleDisk-DevGaming, SingleDisk-Generic
- Added GPO support (Config/GPO/, Scripts/GPO/)
- Added drive letter protection (ProtectLetters.ps1)
- Added WinPE checkpoint system with resume support
- Enhanced Apply-Image.ps1 with -DiskLayout parameter
- Added comprehensive test suites

### v3.2
- Professional hardening engine (registry, services, FSUtil)
- Queued driver store management
- Offline debloating system

### v3.0
- Multi-edition WIM support
- Ventoy plugin support
- USB deployment automation
- Virtual sandbox VM testing

---

## Notes for Contributors

1. **Never rename disk layouts** without updating:
   - `Build-Autounattend.ps1` ValidateSet
   - `Build-GoldISO.ps1` ValidateSet
   - This ROADMAP.md
   - `Config/DiskLayouts/README.md`

2. **Adding new layouts:**
   - Create both .xml and .json files
   - Follow naming convention exactly
   - Update ValidateSet attributes
   - Add to ROADMAP Phase 3 table
   - Document drive letters

3. **Drive letter conflicts:**
   - Check Phase 4 protection status
   - Update ProtectLetters.ps1 if adding new protected letters
