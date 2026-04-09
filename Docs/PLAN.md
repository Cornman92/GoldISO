# GoldISO Implementation Plan

> Generated: 2026-04-08  
> Current Phase: 7 (Integration Testing) — see ROADMAP.md for phase history

---

## Active Goal: Phase II — Infrastructure Hardening (from .ai/ROADMAP.md)

**Phase 7 Status: Complete** ✅  
**Phase II Status: In Progress** 🔄

### Phase II Remaining Work
- [x] II-A: autounattend.xml sync fix — `Config/autounattend.xml` is canonical, copied at build time
- [x] II-B: `Tests/BuildWithSettings.Tests.ps1` — Pester tests for Build-ISO-With-Settings.ps1
- [x] II-C: Log hygiene — fixed `Build-ISO-With-Settings.ps1` log path; all scripts use project-root `Logs/`
- [x] II-D: `.gitignore` expansion — `Config/SettingsMigration/Settings-Migration-*/` present

### Phase III Status (Complete)
- [x] III-A: `Scripts/System/Update-Drivers.ps1` — audits staged .inf files; downloads from manifest URLs
- [x] III-C: `Scripts/Testing/Test-PackageFreshness.ps1` — package age check with Update Catalog links
- [x] III-D: `Scripts/Testing/Validate-WingetPackages.ps1` — implemented

### Documentation (Complete)
- [x] Added `Get-SystemHealth.ps1` and `Get-SystemReport.ps1` to `Docs/AGENTS.md`
- [x] Fixed `Docs/AGENTS.md` log directory path (`Scripts/Logs/` → `Logs/`)

---

### Phase 3: Multi-Layout Disk Support

**Status:** Complete ✅  
**Objective:** Allow `Build-GoldISO.ps1` and `Build-Autounattend.ps1` to accept `-DiskLayout` and produce correct partition XML for each layout.

#### Completed Work
1. ✅ Wired `GamerOS-3Disk.xml` variable substitution through `Build-Autounattend.ps1`
2. ✅ `FirstLogonCommands` in `oobeSystem` pass creates `D:\P-Apps`, `D:\Scratch`, `E:\Media`, `E:\Backups`
3. ✅ `Config/Unattend/Passes/02-windowsPE.xml` uses `{{VARIABLE}}` placeholders, replaced at build time
4. ✅ Pester tests covering all three layouts (`Tests/DiskLayouts.Tests.ps1`, `Tests/BuildValidation.Tests.ps1`)
5. ✅ Root `autounattend.xml` synced with `Config/autounattend.xml`

#### Phase 3 Decision Record
- Disk layout naming uses `{Name}.xml` + `{Name}.json` — no `-Layout` suffix
- `GamerOS-3Disk` is LOCKED — sizes and drive letters must not change
- Folders (`D:\P-Apps`, `D:\Scratch`, `E:\Media`, `E:\Backups`) are created by FirstLogon, not by diskpart

---

### Phase 4: Drive Letter Protection

**Status:** Planned  
**Objective:** Prevent removable drives from stealing reserved letters during OOBE.

#### Plan
1. `Config/Unattend/Modules/Scripts/ProtectLetters.ps1` — reassign letters if occupied by removable media
2. Integrate into `oobeSystem` FirstLogonCommands (run before folder creation commands)
3. Protected letters for `GamerOS-3Disk`: D, E, F, C, U–Z, R, T, M
4. Add Pester tests mocking registry-based letter assignment

---

## Architecture Decisions

| Decision | Rationale |
|----------|-----------|
| PS 5.1 only | Target machines may not have PS7 pre-installed; unattend runs in WinPE |
| `Config/autounattend.xml` is canonical | Root copy is generated — prevents accidental manual edits |
| Folder-based layout (D:\P-Apps vs D:\ partition) | Simpler letter management; flexible space sharing |
| Recovery partition before Windows partition | Better boot performance on Samsung NVMe |
| 90 GB unallocated on Disk 2 | Samsung NVMe overprovisioning — mandatory for drive health |

---

## Risk Areas

1. **autounattend desync** — root `autounattend.xml` drifting from `Config/autounattend.xml` is the #1 source of silent build failures
2. **Disk ID assumptions** — IDs 0/1/2 are hardware-specific; any layout change needs physical verification
3. **DISM package failures** — outdated `.msu` packages silently skip; verify package list against target Windows version
4. **Pester version drift** — test suite supports 3.x and 5.x; new tests should target 5.x configuration API only

---

## Testing Strategy

- Run `.\Tests\Run-AllTests.ps1` before every commit
- Validate answer file with `.\Scripts\Test-UnattendXML.ps1 -Verbose` after any XML edit
- Test new layouts in Hyper-V VM via `.\Scripts\New-TestVM.ps1` before bare-metal
- Code coverage target: `GoldISO-Common.psm1` functions (run with `-CodeCoverage`)
