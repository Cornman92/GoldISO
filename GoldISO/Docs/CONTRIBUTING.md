# Contributing to GoldISO

## Hard Rules

### PowerShell version — PS 5.1 only
All scripts must be compatible with Windows PowerShell 5.1. Do not use:
- `??=` (null-coalescing assignment)
- `ForEach-Object -Parallel`
- Any syntax exclusive to PowerShell 7+

Use `#Requires -Version 5.1` at the top of every script.

### Never rename disk layouts without updating all references
Disk layout names (`GamerOS-3Disk`, `SingleDisk-DevGaming`, `SingleDisk-Generic`) appear in:
- `Build-Autounattend.ps1` — `[ValidateSet(...)]` on `-DiskLayout`
- `Build-GoldISO.ps1` — `[ValidateSet(...)]` on `-DiskLayout`
- `ROADMAP.md` — Phase 3 table
- `Config/DiskLayouts/README.md` — Available Templates section

All four must be updated atomically. The `Tests/DiskLayouts.Tests.ps1` suite will catch missing pairs.

### `GamerOS-3Disk` layout is LOCKED
Do not change partition sizes, disk IDs, or drive letters in `Config/DiskLayouts/GamerOS-3Disk.xml` or `.json`.
This layout is calibrated for specific physical hardware:
- Disk 0: 232 GB Samsung SSD
- Disk 1: 1 TB HDD
- Disk 2: 1 TB Samsung NVMe (90 GB OP is intentional — do not add partitions)

### `Config/autounattend.xml` is the canonical answer file
The root `autounattend.xml` is a **generated copy** — never edit it by hand. Always edit `Config/autounattend.xml`, then let `Build-GoldISO.ps1` regenerate the root copy at build time.

### Script standards
Every `.ps1` script must:
- Start with `#Requires -Version 5.1` and `[CmdletBinding()]`
- Import `GoldISO-Common.psm1` and call `Test-GoldISOAdmin -ExitIfNotAdmin`
- Use `Write-GoldISOLog` — never `Write-Host`
- Use `Join-Path` — never string concatenation for paths
- Resolve the project root via `Get-GoldISORoot` — never hardcode `C:\Users\C-Man\GoldISO`
- Write logs to `Logs/` at project root

## Adding a New Disk Layout

1. Create `Config/DiskLayouts/{Name}.xml` — use `{{VARIABLE}}` for configurable values
2. Create `Config/DiskLayouts/{Name}.json` — define `variables` (each with a `default`), `disks`, and `driveLetters`
3. Add `{Name}` to `[ValidateSet(...)]` in `Scripts/Build/Build-Autounattend.ps1`
4. Add `{Name}` to `[ValidateSet(...)]` in `Scripts/Build-GoldISO.ps1`
5. Update Phase 3 table in `ROADMAP.md`
6. Update Available Templates in `Config/DiskLayouts/README.md`
7. Test in Hyper-V before bare-metal

## Running Tests

```powershell
# Full suite
.\Tests\Run-AllTests.ps1

# Disk layout tests only
.\Tests\Run-AllTests.ps1 -Tag "DiskLayout"

# With code coverage
.\Tests\Run-AllTests.ps1 -CodeCoverage
```

## Lint

```powershell
# Check all scripts for errors (runs automatically in Start-BuildPipeline.ps1)
.\Scripts\Invoke-Lint.ps1

# Fail on warnings too
.\Scripts\Invoke-Lint.ps1 -FailOnWarning
```

Requires: `Install-Module PSScriptAnalyzer -Force`
