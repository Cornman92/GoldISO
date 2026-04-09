# GoldISO - GamerOS Custom Windows 11 ISO Builder

A production-grade automated build system for creating optimized Windows 11 25H2 ISO images with pre-injected drivers, packages, and automated post-install configuration.

## What It Does

GoldISO builds a custom Windows 11 Pro ISO ("GamerOS") with:

- **Offline driver injection** - Display, audio, chipset, network, and storage drivers integrated into the install image
- **Windows package integration** - Updates and features injected offline  
- **Portable applications** - Pre-copied to the ISO for automatic installation
- **Performance & privacy tweaks** - System and user-level optimizations
- **Custom PowerShell profile** - Lazy-loaded modules for enhanced shell experience
- **Unattended installation** - Zero-user-interaction setup with auto-logon

## How It Works

1. **Build Phase**: Mounts a Windows 11 ISO, injects drivers and packages into `install.wim` using DISM
2. **Configuration Phase**: Copies the answer file (`autounattend.xml`) for unattended setup
3. **Packaging Phase**: Rebuilds the ISO with `oscdimg` for UEFI dual-boot

The build is controlled by PowerShell scripts that handle:
- WIM mounting/dismounting with retry logic
- Driver injection organized by category
- Package integration
- ISO rebuilding

## How to Use It

### Prerequisites
- Windows 10/11 or Windows Server 2019+
- PowerShell 5.1+
- Administrator privileges
- Windows ADK (for oscdimg)
- 30GB+ free disk space

### Quick Start

```powershell
# Validate the answer file
.\Scripts\Test-UnattendXML.ps1

# Run the build pipeline (validate → build → deploy)
.\Scripts\Start-BuildPipeline.ps1

# Or build directly
.\Scripts\Build-GoldISO.ps1
```

Output: `GamerOS-Win11x64Pro25H2.iso` in the project root.

### Build Options

```powershell
# Skip driver/package injection (faster iteration)
.\Scripts\Build-GoldISO.ps1 -SkipDriverInjection -SkipPackageInjection

# Use a specific disk layout
.\Scripts\Build-GoldISO.ps1 -DiskLayout GamerOS-3Disk

# Use modular answer file generation
.\Scripts\Build-GoldISO.ps1 -UseModular -ProfilePath Config\profile.json
```

### Testing

```powershell
# Run all tests
.\Tests\Run-AllTests.ps1

# Run specific test categories
.\Tests\Run-AllTests.ps1 -Tag "Unit"
.\Tests\Run-AllTests.ps1 -Tag "Integration"
```

## Project Structure

```
GoldISO/
├── Scripts/                    # Build and deployment scripts
│   ├── Build-GoldISO.ps1      # Main ISO build script
│   ├── Start-BuildPipeline.ps1 # Orchestrates full flow
│   ├── Test-UnattendXML.ps1   # Answer file validator
│   ├── Capture-Image.ps1      # WinPE image capture
│   ├── Apply-Image.ps1        # WinPE image deployment
│   └── Modules/               # Shared PowerShell modules
├── Config/
│   ├── autounattend.xml       # Main answer file
│   ├── DiskLayouts/           # Partition templates
│   ├── Unattend/              # Modular answer file system
│   └── PowerShellProfile/    # Custom PS profile
├── Tests/                     # Pester test suites
└── Docs/
    └── AGENTS.md              # Detailed documentation
```

## Documentation

See [Docs/AGENTS.md](Docs/AGENTS.md) for comprehensive architecture and workflow details.

## License

For personal/educational use. Windows is a trademark of Microsoft Corporation.
