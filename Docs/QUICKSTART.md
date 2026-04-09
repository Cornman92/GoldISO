# GoldISO Quick Start Guide

## Prerequisites

- Windows 10/11 or Windows Server 2019+
- PowerShell 5.1+ (Administrator)
- Windows ADK with Deployment Tools (for `oscdimg`)
- 30GB+ free disk space
- Source ISO: `Win11-25H2x64v2.iso` in project root

## Quick Start

### 1. Validate Environment

```powershell
# Run environment validation
.\Scripts\Test-Environment.ps1
```

### 2. Validate Answer File

```powershell
# Validate autounattend.xml
.\Scripts\Test-UnattendXML.ps1
```

### 3. Run the Build

```powershell
# Full build with default settings
.\Scripts\Build\Build-GoldISO.ps1

# Skip driver/package injection for faster testing
.\Scripts\Build\Build-GoldISO.ps1 -SkipDriverInjection -SkipPackageInjection

# Use specific disk layout
.\Scripts\Build\Build-GoldISO.ps1 -DiskLayout GamerOS-3Disk
```

### 4. Output

- ISO: `GamerOS-Win11x64Pro25H2.iso` (project root)
- Checksum: `GamerOS-Win11x64Pro25H2.iso.sha256`

## Common Tasks

### Run Tests

```powershell
.\Tests\Run-AllTests.ps1
```

### Verify ISO

```powershell
.\Scripts\Build\Verify-ISO.ps1 -ISOPath "GamerOS-Win11x64Pro25H2.iso"
```

### Create Config Snapshot

```powershell
.\Scripts\ConfigManagement\New-ConfigSnapshot.ps1 -Action Create -Name "before-update"
```

## Support

- See `Docs/AGENTS.md` for detailed architecture
- See `Docs/ROADMAP.md` for project phases
- See `Docs/ImageCaptureFlow.md` for WinPE workflows