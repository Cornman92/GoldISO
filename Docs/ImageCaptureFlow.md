# GoldISO Image Capture & Audit Mode Flow

This document describes the multi-phase WIM handling system for GoldISO, including image capture, audit mode, and recovery installation workflows.

## Overview

The capture flow system enables:
1. **Image Capture**: Boot into WinPE, capture a configured Windows installation to WIM
2. **Audit Mode**: Boot into Audit Mode to customize Windows before finalizing
3. **Image Apply**: Apply a captured WIM to a disk in WinPE
4. **Multi-phase Builds**: Build ISOs using either standard install.wim or captured WIMs

## Workflow Diagrams

### 1. Standard Install Flow
```
Boot ISO (WinPE)
    ↓
Wipe Disk 0/1/2
    ↓
Install Windows (install.wim)
    ↓
FirstLogon Commands
    ↓
Complete Setup
```

### 2. Capture Flow
```
Install Windows (standard or custom)
    ↓
Customize (apps, settings, tweaks)
    ↓
Boot WinPE from USB
    ↓
Run Capture-Image.ps1
    ↓
Capture.wim created on USB
    ↓
Build new ISO with captured WIM
```

### 3. Audit Mode Flow
```
Boot ISO with Audit Mode
    ↓
Install Windows
    ↓
Enter Audit Mode (auto-logon as Administrator)
    ↓
Customize system
    ↓
Double-click "Continue to OOBE.lnk"
    ↓
Sysprep → Reboot → OOBE
```

### 4. Apply Image Flow
```
Boot WinPE
    ↓
Run Apply-Image.ps1 -ImagePath D:\Capture.wim
    ↓
Disk wiped and partitioned
    ↓
WIM applied to disk
    ↓
Boot configuration created
    ↓
Reboot to Windows
```

## Scripts Reference

### Capture-Image.ps1
Captures a Windows installation to WIM in WinPE.

**Parameters:**
- `-TargetDisk`: Disk number to capture from (default: 2)
- `-CapturePath`: Where to save the WIM (default: C:\Capture.wim)
- `-MoveToUSB`: Move WIM to USB after capture (default: true)
- `-USBDrive`: Specific USB drive letter (default: auto-detect)

**Usage:**
```powershell
# Auto-detect and capture Disk 2, move to USB
.\Capture-Image.ps1

# Capture specific disk to custom location
.\Capture-Image.ps1 -TargetDisk 0 -CapturePath "D:\Custom.wim" -MoveToUSB:$false
```

### Apply-Image.ps1
Applies a captured WIM to a target disk in WinPE.

**Parameters:**
- `-ImagePath`: Path to WIM file (auto-detects from USB if not specified)
- `-TargetDisk`: Disk number to apply to (default: 2)
- `-ImageIndex`: Image index in WIM (default: 1)
- `-BootMode`: UEFI or BIOS (default: auto-detect)

**Usage:**
```powershell
# Auto-detect WIM and apply to Disk 2
.\Apply-Image.ps1

# Apply specific WIM to specific disk
.\Apply-Image.ps1 -ImagePath "D:\GoldISO\Capture.wim" -TargetDisk 0
```

### AuditMode-Continue.ps1
Desktop shortcut script to continue from Audit Mode to OOBE.

**Usage:**
Double-click "Continue to OOBE.lnk" on desktop, or run:
```powershell
.\AuditMode-Continue.ps1
```

### Build-GoldISO.ps1 (Updated)
Now supports multi-phase WIM handling.

**New Parameters:**
- `-BuildMode`: Standard, Audit, or Capture
- `-CaptureWIMPath`: Path to captured WIM
- `-IncludeAuditScripts`: Include audit mode scripts
- `-IncludeCaptureScripts`: Include capture/apply scripts

**Usage:**
```powershell
# Standard build (original behavior)
.\Build-GoldISO.ps1

# Build with capture scripts included
.\Build-GoldISO.ps1 -BuildMode Capture -IncludeCaptureScripts

# Build with audit mode support
.\Build-GoldISO.ps1 -BuildMode Audit -IncludeAuditScripts

# Build using captured WIM
.\Build-GoldISO.ps1 -BuildMode Capture -CaptureWIMPath "C:\Capture.wim"
```

## autounattend.xml Changes

### Disk Configuration
All three disks (0, 1, 2) are configured with `WillWipeDisk=true`:

```xml
<DiskConfiguration>
  <!-- Disk 0: Wipe only -->
  <Disk wcm:action="add">
    <DiskID>0</DiskID>
    <WillWipeDisk>true</WillWipeDisk>
  </Disk>
  <!-- Disk 1: Wipe only -->
  <Disk wcm:action="add">
    <DiskID>1</DiskID>
    <WillWipeDisk>true</WillWipeDisk>
  </Disk>
  <!-- Disk 2: Windows installation -->
  <Disk wcm:action="add">
    <DiskID>2</DiskID>
    <WillWipeDisk>true</WillWipeDisk>
    <!-- ... partitions ... -->
  </Disk>
</DiskConfiguration>
```

### Audit Mode Sections
Empty auditSystem and auditUser sections are present:
```xml
<settings pass="auditSystem"></settings>
<settings pass="auditUser"></settings>
```

### Audit Mode Entry Point
In the autounattend.xml (root level), there's a Reseal component for Audit mode:
```xml
<settings pass="oobeSystem">
    <component name="Microsoft-Windows-Deployment">
        <Reseal>
            <Mode>Audit</Mode>
        </Reseal>
    </component>
</settings>
```

## Practical Examples

### Example 1: Create Custom GoldISO from Configured System

1. Install Windows using standard GoldISO
2. Customize (install apps, configure settings)
3. Boot WinPE USB
4. Run capture:
   ```powershell
   .\Capture-Image.ps1 -TargetDisk 2
   ```
5. Capture.wim is saved to USB
6. On another PC:
   ```powershell
   .\Build-GoldISO.ps1 -BuildMode Capture -CaptureWIMPath "D:\GoldISO\Capture.wim"
   ```

### Example 2: Use Audit Mode for Pre-configuration

1. Build ISO with audit support:
   ```powershell
   .\Build-GoldISO.ps1 -BuildMode Audit -IncludeAuditScripts
   ```
2. Install on target system
3. System boots to Audit Mode (Administrator)
4. Customize as needed
5. Double-click "Continue to OOBE.lnk"
6. System finalizes and boots to OOBE

### Example 3: Quick Image Deployment

1. Have Capture.wim on USB
2. Boot WinPE on target system
3. Run:
   ```powershell
   .\Apply-Image.ps1 -ImagePath "D:\GoldISO\Capture.wim" -TargetDisk 2
   ```
4. Reboot - Windows is ready with all customizations

## File Locations

| File | Purpose |
|------|---------|
| `Scripts/Deployment/Capture-Image.ps1` | WinPE capture tool |
| `Scripts/Deployment/Apply-Image.ps1` | WinPE apply tool |
| `Scripts/Maintenance/AuditMode-Continue.ps1` | Audit → OOBE transition |
| `Scripts/Build/Build-GoldISO.ps1` | Updated with multi-phase support |
| `Config/autounattend.xml` | Disk wipe + audit mode sections |

## Troubleshooting

### Capture Issues
- **"Windows partition not found"**: Ensure target disk has a valid Windows installation
- **"Insufficient space"**: Ensure destination has at least 40% of source size free
- **USB not detected**: Try manually specifying -USBDrive parameter

### Apply Issues
- **"WIM not found"**: Check USB drive letter or specify full path
- **Boot fails after apply**: Run bcdboot manually to repair boot
- **Partition errors**: Ensure target disk exists and is accessible

### Audit Mode Issues
- **"Sysprep not found"**: Script must run on actual Windows installation, not WinPE
- **Audit mode doesn't start**: Check autounattend.xml has proper Reseal/Mode=Audit

## Notes

- Capture.wim files are typically 40-60% smaller than the original installation
- Audit Mode allows unlimited customization time before finalizing
- The captured WIM includes all installed apps, drivers, and settings
- Multiple WIM indexes can be created for different configurations

---

## Phase 5 Enhancements

### Capture-Image.ps1 — Checkpoint & Resume

The script now writes a checkpoint JSON file alongside each capture so interrupted
captures can be detected and restarted.

**Checkpoint file:** `<CapturePath>.checkpoint.json`

```json
{
  "Status":      "Started | Completed | Failed",
  "SourceDrive": "C:\\",
  "CapturePath": "E:\\GoldISO\\Capture.wim",
  "StartTime":   "2026-01-01 12:00:00",
  "TargetDisk":  2,
  "EndTime":     "2026-01-01 12:35:00",
  "FailReason":  "DISM exit code 11"
}
```

**Resume behavior:**

| Checkpoint state | Default | With `-Resume` |
|-----------------|---------|---------------|
| No checkpoint file | Fresh capture | Fresh capture |
| Status = Completed | Exits 0 (already done) | Exits 0 |
| Status = Started | Exits 1 with warning | Deletes partial WIM, restarts |
| Status = Failed | Exits 1 with warning | Deletes partial WIM, restarts |

**Real-time DISM progress:** stdout is redirected to a temp file and polled every
500 ms; `Write-Progress` updates with percentage and elapsed time during capture.

**New parameter:**

| Parameter | Description |
|-----------|-------------|
| `-Resume` | When set, clears a partial/failed capture and restarts from scratch |

### Apply-Image.ps1 — Disk Layout Selection

The script now accepts a `-DiskLayout` parameter that selects which partition
structure to apply to the target disk before image deployment.

**New parameter:**

| Parameter | Default | Description |
|-----------|---------|-------------|
| `-DiskLayout` | `GamerOS-3Disk` | Layout name: `GamerOS-3Disk`, `SingleDisk-DevGaming`, `SingleDisk-Generic` |

**Improved USB WIM detection:** instead of a fixed path list, the script now:
1. Enumerates all removable volumes via `Get-Disk | Where-Object BusType -eq USB`
2. Also checks `Get-Volume | Where-Object DriveType -eq Removable`
3. Scans all accessible partitions for `.wim` files
4. Picks the **largest** WIM found (most likely to be the intended capture)

### Typical GamerOS Build Run

```powershell
# Boot WinPE from USB.

# Capture gold image from Disk 2 (NVMe, post-sysprep):
X:\Scripts\Capture-Image.ps1 -TargetDisk 2 -CapturePath E:\Capture.wim -MoveToUSB

# Deploy to a fresh 3-disk GamerOS machine:
X:\Scripts\Apply-Image.ps1 -TargetDisk 2 -DiskLayout GamerOS-3Disk

# First boot FirstLogonCommands (from autounattend.xml):
#   Order 48: ProtectLetters.ps1
#   Order 49: Create D:\P-Apps, D:\Scratch
#   Order 50: Create E:\Media, E:\Backups
#   Order 51: pnputil post-boot driver injection
```
