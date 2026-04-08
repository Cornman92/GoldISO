# GoldISO / GamerOS — Development Roadmap

**Last Updated**: 2026-04-08
**Current State**: Phase II complete — Pipeline v2, PassThru support, Sequential FirstLogon, Language cleanup

---

## Current Capabilities (Done)

- `Build-GoldISO.ps1` — full offline ISO build with driver + package injection
- `autounattend.xml` — 47-command sequential FirstLogon (1-47), hardware-tuned for 3-disk Samsung NVMe rig
- `Export-Settings.ps1` + `Build-ISO-With-Settings.ps1` — settings migration system
- `Start-BuildPipeline.ps1` — CI-style orchestrator with `-PassThru` results and `-DeployToVM`
- `Test-UnattendXML.ps1` — 36 tests, supports `-PassThru` returning `{Status, Passed, Warnings, Errors}`
- `New-TestVM.ps1` — Hyper-V test VM provisioner
- Pester test suite (`Tests/`) — module, config, syntax, and structure tests
- GWIG companion pipeline at `C:\Users\C-Man\GWIG` (94 stages, `Invoke-GamerOSPipeline-v2.ps1`)
- Shared module `GoldISO-Common.psm1` — logging, admin check, WinPE detection, etc.
- **Language cleanup**: Non-English files removed from Applications (7-Zip, CCleaner, FileVoyager, FreeCommander, etc.)
- **Pipeline fixes**: -PassThru, -OutputISO, FirstLogon 91→47

---

## Phase II — Infrastructure Hardening (Next Priority)

### II-A: autounattend.xml Sync Fix
- **Problem**: Root `autounattend.xml` and `Config/autounattend.xml` have diverged (different checksums)
- **Fix**: Make `Config/autounattend.xml` the canonical source; have `Build-GoldISO.ps1` copy it to the ISO root during build
- **Files**: `Build-GoldISO.ps1`, `Test-UnattendXML.ps1`
- **Test**: Both files must match after any edit

### II-B: Expand Test Coverage
- Add Pester tests for `Export-Settings.ps1` (mock registry/file ops)
- Add Pester tests for `Build-ISO-With-Settings.ps1`
- Add integration test: `Test-ISO.ps1` verifies built ISO structure
- Target: 80%+ script-level coverage
- **Files**: `Tests/ExportSettings.Tests.ps1`, `Tests/BuildWithSettings.Tests.ps1`

### II-C: Log File Hygiene
- All scripts should log to `Scripts/Logs/` (not script root)
- `Build-ISO-With-Settings.log` already moved; audit remaining scripts
- `Start-BuildPipeline.ps1` logs → `Scripts/Logs/pipeline-<timestamp>.log`
- **Files**: All scripts that call `Write-GoldISOLog` or `Add-Content`

### II-D: .gitignore Expansion
- Add `Scripts/Logs/` to .gitignore (runtime logs should not be committed)
- Add `Config/SettingsMigration/Settings-Migration-*/` (export artifacts)
- Add `Tests/Results/` (Pester output)
- **Files**: `.gitignore`

---

## Phase III — Driver & Package Automation (Short-Term)

### III-A: Driver Update Checker
- Script: `Scripts/Update-Drivers.ps1`
- Read `Drivers/download-manifest.json` for current versions + download URLs
- Compare against latest available (NVIDIA API, Intel ARK page scrape, vendor feeds)
- Output report: which drivers are stale with download links
- Optionally download and stage new drivers

### III-B: NVIDIA Driver Auto-Stage
- Use NVIDIA's driver API endpoint to get latest Game Ready / Studio driver
- Auto-download to `Drivers/Display adapters/`
- Update `Drivers/download-manifest.json` with new version
- **Constraint**: NVIDIA post-boot via pnputil (not DISM offline) — download only, don't change injection strategy

### III-C: Package Freshness Validator
- Script: `Scripts/Test-PackageFreshness.ps1`
- For each `.msu`/`.cab` in `Packages/`:
  - Query Microsoft Update Catalog to check if superseded
  - Flag outdated packages (they'll fail silently in DISM but waste time)
- Output actionable report: keep / remove / replace with newer KB

### III-D: Winget Package ID Validator
- Script: `Scripts/Validate-WingetPackages.ps1`
- Foreach package ID in `Config/winget-packages.json`, run `winget show <id>` to confirm still valid
- Flag any packages with changed IDs or removed from winget

---

## Phase IV — Build Pipeline Unification (Medium-Term)

### IV-A: Single Entry Point
- `Start-BuildPipeline.ps1` becomes the canonical build entry (not `Build-GoldISO.ps1` directly)
- Add `-Mode` parameter: `Quick` (skip VM deploy), `Full` (all stages), `Validate` (tests only)
- Update `CLAUDE.md` and `AGENTS.md` primary command documentation

### IV-B: GWIG-GoldISO Bridge
- Create `Scripts/Invoke-GWIGBuild.ps1` — thin wrapper that calls `C:\Users\C-Man\GWIG\Scripts\Core\Pipeline\Invoke-GamerOSPipeline-v2.ps1`
- Pass GoldISO config paths as GWIG parameters
- Route GWIG stage output to GoldISO's logging system
- **Goal**: `Start-BuildPipeline.ps1 -UseGWIG` triggers the full 94-stage GWIG pipeline with GoldISO inputs

### IV-C: Build Artifact Management
- `Start-BuildPipeline.ps1` already has `-KeepArtifacts N` parameter
- Implement actual artifact archiving: move completed ISOs to `C:\GoldISO_Artifacts\<timestamp>\`
- Keep manifest of each build (git hash, build time, driver versions, package list)

---

## Phase V — WinPE & Deployment Improvements (Medium-Term)

### V-A: Smarter USB Detection in Apply-Image.ps1
- Current: looks for WIM on USB drives
- Improve: enumerate all removable drives, score candidates by WIM presence + filename
- Add `-USBLabel "GAMEROS"` parameter to target specific USB volume label

### V-B: WIM Index Selection
- `Apply-Image.ps1` currently applies index 1
- Add `-ImageIndex` parameter with auto-list of available indices from WIM
- Display edition names before applying

### V-C: Recovery Mode Support
- After Windows install, add a WinRE boot entry pointing to the GoldISO WinPE environment
- Script: `Scripts/Register-RecoveryBoot.ps1`
- Enables field recovery without a USB drive

### V-D: Capture → Apply Round-Trip Test
- Test: `Tests/Test-CaptureApply.ps1`
- In Hyper-V: capture VM disk, apply to new VM, boot and verify
- Validates the full Capture-Image → Apply-Image workflow

---

## Phase VI — Health & Observability (Long-Term)

### VI-A: Post-Install Health Baseline
- `Scripts/Get-SystemHealth.ps1` already exists (642 lines)
- Create `Scripts/Save-HealthBaseline.ps1` — captures baseline on first boot
- Create `Scripts/Compare-HealthBaseline.ps1` — compare current vs. baseline
- Alert on: missing services, unexpected processes, changed registry keys

### VI-B: Build Analytics Dashboard
- `Measure-BuildTime.ps1` already exists (433 lines)
- Output structured JSON to `Scripts/Logs/build-metrics-<date>.json`
- Create simple HTML report from metrics (no external deps, pure PowerShell)
- Track: per-stage timing, total build time, ISO size, driver count, package count

### VI-C: Remote Access Automation
- `Configure-RemoteAccess.ps1` exists (333 lines)
- Integrate with `autounattend.xml` FirstLogonCommands
- Support: AnyDesk ID export, Tailscale auth key injection, RDP enable/configure

---

## Phase VII — Multi-Machine Support (Long-Term)

### VII-A: Hardware Profile System
- `Config/hardware-matrix.json` already exists — expand it
- Define named profiles: `Home-NVMe-3Disk`, `Dev-VM`, `Laptop-Single-Disk`
- `Build-GoldISO.ps1 -HardwareProfile "Home-NVMe-3Disk"` selects disk layout + driver set
- `autounattend.xml` generation from profile (template + profile merge)

### VII-B: Disk Layout Templates
- Extract disk partitioning XML from `autounattend.xml` into `Config/DiskLayouts/`
- `single-disk.xml`, `two-disk.xml`, `three-disk-nvme.xml` (current)
- `Build-GoldISO.ps1` merges chosen layout into the final answer file

### VII-C: Cloud Settings Sync
- Optional: Export-Settings.ps1 uploads bundle to OneDrive / network share
- Apply-Image.ps1 / FirstLogon pulls bundle from cloud if USB not present
- Enables zero-USB deployment for machines with network access during WinPE

---

## Immediate Action Items (Next Session)

Priority order for the next working session:

1. **Fix autounattend.xml sync** — `Config/` version should be canonical; update `Build-GoldISO.ps1` copy step
2. **Add `Scripts/Logs/` to .gitignore** — prevent committing runtime log files
3. **Write `Tests/ExportSettings.Tests.ps1`** — mock-based tests for the export script
4. **Implement `Scripts/Validate-WingetPackages.ps1`** — simple ID checker, high ROI
5. **Update `Start-BuildPipeline.ps1`** — add `-Mode` parameter, unify as primary entry point
6. **Document `Get-SystemHealth.ps1` and `Get-SystemReport.ps1`** in AGENTS.md — currently undocumented

---

## Known Gaps / Tech Debt

| Item | Severity | Notes |
|------|----------|-------|
| autounattend.xml root vs Config/ desync | High | Different checksums — root is primary per CLAUDE.md but Config/ is listed as canonical |
| `Scripts/Get.ps1` purpose unclear | Medium | 493-line script; needs inline documentation |
| `Backup-Macrium.ps1` undocumented | Medium | Not in AGENTS.md, unclear integration |
| `Configure-RamDisk.ps1` not wired to autounattend | Medium | RAM disk script exists but runs manually |
| `Config/package.json` is a stub | Low | Node package file with 5 lines; may be vestigial |
| RAM disk (`createramdisk.cmd`) creates R: drive | Low | Verify R: drive letter is always available |
| FanControl app bundled in Applications/ | Low | Full application binary tree committed to repo |
