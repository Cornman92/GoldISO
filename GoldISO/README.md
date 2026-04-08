# GoldISO - GamerOS Custom Windows 11 ISO

A production-grade automated build system for creating optimized Windows 11 ISO images with pre-configured settings, drivers, packages, and applications.

## Overview

GoldISO automates the creation of custom Windows 11 ISOs using Microsoft's DISM tools and unattended installation (autounattend.xml). It produces an optimized gaming-focused Windows image with:

- Pre-injected drivers (display, audio, chipset, network)
- Windows packages (updates, features)
- Portable applications
- Performance and privacy tweaks
- Automated post-install configuration

## Project Structure

```text
GoldISO/
├── Scripts/                    # Build and deployment scripts
│   ├── Build-GoldISO.ps1      # Main ISO build script
│   ├── Test-UnattendXML.ps1   # Answer file validator
│   ├── Capture-Image.ps1      # WinPE image capture
│   ├── Apply-Image.ps1      # WinPE image deployment
│   ├── Configure-SecondaryDrives.ps1  # Post-install drive setup
│   └── ...
├── Config/
│   ├── autounattend.xml       # Unattended installation config
│   ├── winget-packages.json   # Application manifest
│   └── PowerShellProfile/     # Custom PowerShell profile
├── Drivers/                   # Driver injection source
├── Packages/                  # Windows packages (.cab, .msu)
├── Applications/
│   └── Portableapps/          # Portable applications
├── Docs/
│   └── AGENTS.md             # Comprehensive project documentation
└── README.md                 # This file
```

## Quick Start

### Prerequisites

- Windows 10/11 or Windows Server 2019+
- PowerShell 5.1 or PowerShell 7+
- Administrator privileges
- Windows ADK (for oscdimg)
- 20GB+ free disk space

### Building the ISO

```powershell
# 1. Validate the answer file
.\Scripts\Test-UnattendXML.ps1

# 2. Build the ISO
.\Scripts\Build-GoldISO.ps1

# 3. Output will be in the project root: GamerOS-Win11x64Pro25H2.iso
```

## Key Features

### Build System

- **Robust cleanup** with retry logic and locked file handling
- **Multi-phase WIM processing** for optimization
- **Driver injection** organized by category
- **Package integration** for Windows updates
- **Portable apps** auto-copied to ISO

### Validation

- XML well-formedness checking
- Component validation
- Disk configuration verification
- File reference checking
- RunSynchronous order validation

### Standalone Winhance Scripts

Extracted from autounattend.xml for maintainability:

| Script | Purpose |
| ------ | ------- |
| `shrink-and-recovery.ps1` | Disk partitioning for Windows + Recovery + OP space |
| `install-usb-apps.ps1` | Winget package installation by category |
| `install-ramdisk.ps1` | SoftPerfect RAM Disk installation |
| `tweaks-system.cmd` | System-level performance tweaks |
| `tweaks-user.cmd` | User-level performance tweaks |
| `createramdisk.cmd` | RAM disk creation with standard directories |

## Recent Refactoring (2025)

### Critical Fixes

- **Build-GoldISO.ps1**: Fixed incomplete cleanup with proper retry logic
- **00-LazyLoader.ps1**: Fixed dynamic function creation using closures
- **Get.ps1**: Added comprehensive parameter validation with mutually exclusive parameter sets

### New Scripts

- 6 standalone Winhance scripts extracted from embedded XML
- All scripts include full parameter handling, logging, and error handling

### Enhanced Validation

- **Test-UnattendXML.ps1**: Comprehensive 469-line validator with structured output
- Component checking, disk validation, file reference verification

## Documentation

- [Project Documentation](Docs/AGENTS.md) - Comprehensive architecture and workflow guide
- [Script Reference](Scripts/README.md) - Individual script documentation

## License

This project is for personal/educational use. Windows is a trademark of Microsoft Corporation.
