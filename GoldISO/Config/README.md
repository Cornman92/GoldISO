# GoldISO Configuration

This directory contains all configuration files for the GamerOS custom Windows 11 build.

## Files Overview

| File | Purpose |
|------|---------|
| `autounattend.xml` | Primary unattended answer file (1MB+) - controls the entire Windows installation |
| `GamerOS Windows 11.xml` | NTLite preset for component removal |
| `winget-packages.json` | Categorized application manifest for winget installation |
| `package.json` | Node.js dependencies (for any build tools) |
| `SettingsMigration/` | Settings export/restore configurations |

## autounattend.xml

The unattended answer file is the heart of GoldISO. It controls:

- **Disk partitioning** - 3-disk layout (0/1 wiped, 2 with Windows)
- **OOBE configuration** - Local account, network disabled
- **FirstLogonCommands** - 40+ post-install operations
- **Driver injection** - Offline and post-boot strategies
- **Samsung overprovisioning** - 95GB unallocated space

**Validation**: Run `..\Scripts\Test-UnattendXML.ps1` before every build

### Critical Sections

| Section | Pass | Purpose |
|---------|------|---------|
| `windowsPE` | WinPE | Disk setup, WinRE, offline services |
| `specialize` | Specialize | .NET 3.5, drivers, packages, scripts |
| `oobeSystem` | OOBE | FirstLogonCommands, auto-logon |
| `auditSystem` | Audit | Empty (for audit mode support) |
| `auditUser` | Audit | Empty (for audit mode support) |

## winget-packages.json

Application manifest with categories:

| Category | Install Path | Count |
|----------|--------------|-------|
| browsers | Default | 2 |
| dev_tools | `C:\Dev` | 10 |
| gaming | `C:\Gaming` | 8 |
| media | `C:\Media` | 4 |
| utilities | `C:\Utils` | 11 |
| remote | `C:\Remote` | 2 |

All packages marked `"Optional": true` for graceful failures.

## PowerShellProfile/

Custom PowerShell profile deployed to `C:\PowerShellProfile\` during FirstLogon:

- **Modular design** - 30+ scripts in `PSProfile.C-Man/`
- **Lazy loading** - Fast startup with on-demand module loads
- **Configuration** - `Config/profile-config.json` for themes and options
- **Session logging** - Full command history and transcript support

## NTLite Preset

`GamerOS Windows 11.xml` removes 500+ components:

- Bloatware apps (Candy Crush, Xbox apps, etc.)
- Unused language packs
- Legacy features (Internet Explorer, Windows Mail)
- Telemetry components

**Warning**: Heavily stripped - verify compatibility before deployment.

## SettingsMigration/

Contains exported settings and restore configurations:

- Registry exports for application settings
- Browser configurations
- Development tool settings
- Windows Explorer preferences

See `../Docs/SETTINGS_MIGRATION_README.md` for full usage documentation.

## Modification Guidelines

1. **Always backup** `autounattend.xml` before changes
2. **Validate after edits** using `Test-UnattendXML.ps1`
3. **Test in VM** before bare metal deployment
4. **Document changes** in commit messages

## Related Documentation

- `../Docs/AGENTS.md` - Full project overview and agent guidance
- `../Docs/ROADMAP.md` - Development roadmap and next steps
- `../Scripts/README.md` - Build and validation scripts
- `../Docs/ImageCaptureFlow.md` - Audit and capture workflows
- `../Docs/SETTINGS_MIGRATION_README.md` - Settings migration system
