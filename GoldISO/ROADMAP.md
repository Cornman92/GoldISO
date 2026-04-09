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

## Phase 3: Multi-Layout Support 🔄 IN PROGRESS

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

## Phase 6: Testing & Validation Framework 📋 PLANNED

**Goal:** Automated validation of builds and disk layouts

**Deliverables:**
- Pester tests for each disk layout
- XML validation against Windows SIM requirements
- JSON schema validation for profiles
- VM-based automated testing pipeline

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

### v3.3 (Current)
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
