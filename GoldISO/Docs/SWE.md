# GoldISO — Software Engineering Agent Guide

**Last Updated**: 2026-04-08
**Audience**: General-purpose SWE agents (Claude Code, Cursor, Cline, Copilot, etc.)

---

## Mission

You are assisting with **GoldISO** — a production-grade custom Windows 11 ISO build system targeting gaming-optimized "GamerOS" installations. All scripts are PowerShell. The target environment is a 3-disk gaming PC (Samsung NVMe primary, 2 secondary HDDs).

---

## Non-Negotiable Rules

1. **Always validate `autounattend.xml`** after any edit: `.\Scripts\Test-UnattendXML.ps1`
2. **Never bypass TPM/Secure Boot** — this system intentionally requires them
3. **Always run as Administrator** — DISM, pnputil, diskpart all require elevation
4. **Test in Hyper-V first** — never deploy bare-metal without VM validation
5. **Disk topology is hardware-specific** — Disk 2 = primary NVMe on *this machine only*
6. **~95 GB unallocated on Disk 2 is intentional** — Samsung overprovisioning; do NOT partition it
7. **Log files go in `Scripts/Logs/`** — not in the script directory root

---

## Code Patterns to Follow

### Script Structure
Every script should:
- Begin with `#Requires -Version 5.1`
- Use a `[CmdletBinding()]` param block
- Import `GoldISO-Common.psm1` for logging and admin checks
- Default `$ErrorActionPreference = "Stop"` (except `Build-GoldISO.ps1` which uses `"Continue"`)

```powershell
#Requires -Version 5.1
[CmdletBinding()]
param(
    [string]$Something = "default"
)

$ErrorActionPreference = "Stop"
$scriptRoot = Split-Path $MyInvocation.MyCommand.Path -Parent
Import-Module (Join-Path $scriptRoot "Modules\GoldISO-Common.psm1") -Force

Test-GoldISOAdmin -ExitIfNotAdmin
```

### Logging
Use `Write-GoldISOLog`, not `Write-Host` or `Write-Output` directly:

```powershell
Write-GoldISOLog -Message "Starting operation" -Level "INFO"
Write-GoldISOLog -Message "Driver injected" -Level "SUCCESS"
Write-GoldISOLog -Message "Package skipped" -Level "WARN"
Write-GoldISOLog -Message "DISM failed" -Level "ERROR"
```

### Path Handling
Always use `Join-Path` and `$script:ProjectRoot`. Never hardcode `C:\Users\C-Man\GoldISO`:

```powershell
$script:ProjectRoot = Split-Path $PSScriptRoot -Parent
$driversPath = Join-Path $script:ProjectRoot "Drivers"
```

### Error Handling in Build Scripts
Build scripts use `"Continue"` and handle errors inline:

```powershell
try {
    Add-WindowsPackage -Path $MountDir -PackagePath $pkg -ErrorAction Stop
    Write-GoldISOLog "Package added: $pkg" -Level "SUCCESS"
} catch {
    Write-GoldISOLog "Package failed (skipping): $($_.Exception.Message)" -Level "WARN"
}
```

---

## Module: GoldISO-Common.psm1

Import path: `Scripts/Modules/GoldISO-Common.psm1`

| Function | Signature | Use |
|----------|-----------|-----|
| `Initialize-Logging` | `-LogPath <string>` | Call once at script start |
| `Write-GoldISOLog` | `-Message <string> -Level <string>` | All logging |
| `Test-GoldISOAdmin` | `-ExitIfNotAdmin` | Privilege check |
| `Test-GoldISOPath` | `-Path <string> -Create` | Path validation |
| `Format-GoldISOSize` | `-Bytes <long>` | Human-readable sizes |
| `Test-GoldISOWinPE` | _(none)_ | Returns `$true` in WinPE |
| `Get-GoldISORoot` | _(none)_ | Returns project root path |
| `Invoke-GoldISOCommand` | `-Command <string> -Timeout <int>` | Run with timeout |

**Do not duplicate** these functions in individual scripts. If you need a utility that the module doesn't provide, add it to the module — not inline.

---

## Testing Requirements

- Test framework: **Pester 5.x**
- Test files in: `Tests/` (name pattern: `*.Tests.ps1`)
- Run all tests: `.\Tests\Run-AllTests.ps1`
- Run specific: `Invoke-Pester -Path .\Tests\GoldISO-Common.Tests.ps1`

### When adding a new script, also add:
1. A syntax test in `Tests/ScriptSyntax.Tests.ps1` (already auto-discovers all .ps1 files)
2. A functional test file if the script has testable logic

### Test patterns:
- Mock DISM commands (`Mock Add-WindowsDriver { }`)
- Mock file system operations where possible
- Use `$TestDrive` for temp file operations
- Tag tests: `[Unit]`, `[Integration]`, `[Config]`, `[Structure]`

---

## Directory Quick Reference

```
GoldISO/
├── autounattend.xml              # ISO root copy (keep synced with Config/)
├── Config/
│   ├── autounattend.xml          # Canonical source (edit this one)
│   ├── winget-packages.json      # App manifest
│   ├── build-manifest.json       # Build version tracking
│   ├── hardware-matrix.json      # Hardware profiles
│   └── PowerShellProfile/        # Custom PS profile (deployed to C:\PowerShellProfile\)
├── Drivers/                      # .inf/.sys files organized by device class
├── Packages/                     # .msu/.cab/.msixbundle/.appx files
├── Applications/                 # Installers and portable apps
├── Scripts/
│   ├── Modules/GoldISO-Common.psm1  # SHARED — always use this
│   ├── Build-GoldISO.ps1         # Main builder (1346 lines)
│   ├── Start-BuildPipeline.ps1   # CI orchestrator
│   ├── Test-UnattendXML.ps1      # XML validator
│   └── Logs/                     # Runtime logs (gitignored)
├── Tests/                        # Pester test suite
└── Docs/                         # All documentation
```

---

## Build Command Reference

```powershell
# Standard build
.\Scripts\Build-GoldISO.ps1

# CI pipeline (preferred entry point)
.\Scripts\Start-BuildPipeline.ps1

# Skip components for quick iteration
.\Scripts\Build-GoldISO.ps1 -SkipDriverInjection -SkipPackageInjection

# Validate without building
.\Scripts\Test-Environment.ps1
.\Scripts\Test-UnattendXML.ps1 -Verbose
```

---

## Common Mistakes to Avoid

| Mistake | Correct Approach |
|---------|-----------------|
| Editing root `autounattend.xml` directly | Edit `Config/autounattend.xml`, then sync |
| Using `Write-Host` for logging | Use `Write-GoldISOLog` |
| Hardcoding `C:\Users\C-Man\GoldISO` | Use `Get-GoldISORoot` or `$script:ProjectRoot` |
| Adding partition steps for the ~90 GB gap on Disk 2 | That gap is Samsung OP — leave it |
| Skipping `Test-UnattendXML.ps1` after XML edits | Always validate XML |
| Putting log files in the script directory | Logs go in `Scripts/Logs/` |
| Creating a new logging helper | Use `Write-GoldISOLog` from the module |

---

## GWIG Integration

A companion pipeline lives at `C:\Users\C-Man\GWIG`:
- 94-stage build pipeline: `Invoke-GamerOSPipeline-v2.ps1`
- Config: `Config/UnifiedGWIG-Config.json`
- Docs: `C:\Users\C-Man\GWIG\Docs\Root\AGENTS.md`

When working on DISM-heavy tasks or needing the full 94-stage pipeline, consult GWIG first. GoldISO scripts call GWIG; GWIG does not call GoldISO.
