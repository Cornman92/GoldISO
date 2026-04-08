# GoldISO Scripts

This directory contains all PowerShell scripts for building, validating, and deploying the GamerOS custom Windows 11 ISO.

## Quick Reference

| Script | Purpose | When to Run |
| ------ | ------- | ----------- |
| `Build-GoldISO.ps1` | Main build script - creates the custom ISO | When you need to build a new ISO |
| `Test-UnattendXML.ps1` | Validates autounattend.xml structure | Before every build |
| `Test-Environment.ps1` | Pre-flight environment checks | Before first build, after system changes |
| `Configure-SecondaryDrives.ps1` | Partitions Disk 0/1 post-install | After Windows installation completes |
| `Capture-Image.ps1` | Captures configured Windows to WIM | In WinPE, after customizing system |
| `Apply-Image.ps1` | Applies captured WIM to disk | In WinPE, for quick deployment |

## Build Workflow

### Standard Build

```powershell
# 1. Validate environment
.\Test-Environment.ps
# 2. Validate answer file
.\Test-UnattendXML.ps1

# 3. Build the ISO
.\Build-GoldISO.ps1
```

### Build with Settings Migration

```powershell
.\Build-ISO-With-Settings.ps1 -ExportUserData -MaxUserDataSizeGB 5
```

### Post-Install Drive Configuration

```powershell
# After Windows installation completes, run as Administrator:
.\Configure-SecondaryDrives.ps1
```

## Script Categories

### Build Scripts

- **Build-GoldISO.ps1** - Full ISO build with DISM operations
- **Build-ISO-With-Settings.ps1** - Build with settings migration integration
- **Export-Settings.ps1** - Export current system settings for migration

### Validation Scripts

- **Test-UnattendXML.ps1** - XML validation with 50+ checks
- **Test-Environment.ps1** - Environment pre-flight checks

### Deployment Scripts

- **Apply-Image.ps1** - Apply captured WIM (WinPE)
- **Capture-Image.ps1** - Capture Windows installation (WinPE)
- **Configure-SecondaryDrives.ps1** - Post-install drive setup

### Utility Scripts

- **AuditMode-Continue.ps1** - Transition from Audit Mode to OOBE
- **Audit-Sysprep.ps1** - Sysprep helper for audit mode
- **Create-AuditShortcuts.ps1** - Creates desktop shortcuts for audit mode
- **New-TestVM.ps1** - Creates Hyper-V test VM
- **Get.ps1** - Component retrieval utilities

## Common Parameters

Most scripts support these standard parameters:

| Parameter | Description |
| --------- | ----------- |
| `-Verbose` | Enable detailed output |
| `-WhatIf` | Show what would be done (no changes) |
| `-Force` | Skip confirmation prompts |

## Logging

All scripts write to log files in:

- `C:\Scripts\Logs\` (for post-install scripts)
- `..\Logs\` (for build/validation scripts)

## Error Handling

- Scripts use `$ErrorActionPreference = "Stop"` for critical failures
- Validation scripts return exit code 1 on failure
- Build scripts include rollback mechanisms where possible

## Shared Module

The `Modules\GoldISO-Common.psm1` module provides:

- Standardized logging (`Write-GoldISOLog`)
- Admin privilege checking (`Test-GoldISOAdmin`)
- Path validation (`Test-GoldISOPath`)
- Size formatting (`Format-GoldISOSize`)
- WinPE detection (`Test-GoldISOWinPE`)

## Prerequisites

- Windows 10/11 or Windows Server 2019+
- PowerShell 5.1 or PowerShell 7+
- Administrator privileges
- Windows ADK (for oscdimg)
- 20GB+ free disk space on C:

## Troubleshooting

### "DISM not found"

Ensure you're running on Windows 10/11 or Windows Server. DISM is built-in.

### "oscdimg not found"

Install Windows ADK with Deployment Tools, or add ADK path to system PATH.

### "Administrator privileges required"

Run PowerShell as Administrator (right-click → Run as Administrator).

### Validation failures

Run `Test-UnattendXML.ps1 -Verbose` to see detailed failure information.