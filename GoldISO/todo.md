# GoldISO Todo

> Tracks all pending work across all phases. Check off items as completed.

---

## Phase 3: Multi-Layout Disk Support

- [x] 1. Verify `Build-Autounattend.ps1 -DiskLayout` ValidateSet matches all three layout names exactly (`GamerOS-3Disk`, `SingleDisk-DevGaming`, `SingleDisk-Generic`) — fixed `SingleDisk-Basic` → `SingleDisk-Generic`
- [x] 2. Verify `Build-GoldISO.ps1 -DiskLayout` ValidateSet matches the same three names — already correct
- [x] 3. Confirm variable substitution (`{{WINDOWS_DISK_ID}}`, `{{SSD_DISK_ID}}`, etc.) is applied before embedding `GamerOS-3Disk.xml` into the answer file — rewrote `Build-DiskConfigurationSection` to use JSON defaults + string replacement
- [x] 4. Confirm `SingleDisk-Generic.xml` substitution works for `{{DISK_ID}}`, `{{EFI_SIZE}}`, `{{MSR_SIZE}}` — same fix covers all layouts
- [x] 5. Confirm `SingleDisk-DevGaming.xml` substitution works for all its variables — same fix
- [ ] 6. Audit `Config/Unattend/Passes/02-windowsPE.xml` — ensure it either embeds or references the layout XML at build time (not hardcoded)
- [x] 7. Add FirstLogonCommand entries to `Config/Unattend/Passes/07-oobeSystem.xml` to create `D:\P-Apps` and `D:\Scratch` when layout is `GamerOS-3Disk` — added Orders 37/38
- [x] 8. Add FirstLogonCommand entries to create `E:\Media` and `E:\Backups` when layout is `GamerOS-3Disk` — added Order 38 in oobeSystem.xml
- [x] 9. Ensure folder creation commands run after drive-letter protection — ProtectLetters is Order 36, folders are 37/38 in oobeSystem.xml; 48/49/50 in autounattend.xml
- [ ] 10. Test `GamerOS-3Disk` layout in Hyper-V with simulated 3-disk setup
- [ ] 11. Test `SingleDisk-Generic` layout in Hyper-V VM for clean single-disk install
- [ ] 12. Test `SingleDisk-DevGaming` layout in Hyper-V VM
- [ ] 13. Validate that root `autounattend.xml` is regenerated (not manually edited) after modular build
- [x] 14. Add a Pester test that asserts all three layout files (`.xml` + `.json`) exist and are parseable — `Tests/DiskLayouts.Tests.ps1`
- [x] 15. Add a Pester test that validates each layout JSON contains required keys (`variables`, `diskStructure`) — `Tests/DiskLayouts.Tests.ps1`

---

## Phase 4: Drive Letter Protection

- [x] 16. Create `Config/Unattend/Modules/Scripts/ProtectLetters.ps1` skeleton with `#Requires -Version 5.1` and `[CmdletBinding()]`
- [x] 17. Implement drive letter protection for letters: D, E, F, C, U, V, W, X, Y, Z, R, T, M (uses `Set-Partition` + `Get-Volume`)
- [x] 18. Add logic to detect if a protected letter is occupied by a removable volume and reassign it
- [x] 19. Integrate `ProtectLetters.ps1` into `oobeSystem` FirstLogonCommands (runs before folder creation at Order 36)
- [x] 20. Add a Pester test for `ProtectLetters.ps1` mocking the `Get-Volume`/`Set-Partition` calls — `Tests/ProtectLetters.Tests.ps1` (structural AST tests + logic pattern checks)
- [x] 21. Document protected letter set per layout in `Config/DiskLayouts/README.md` — added SingleDisk-Generic (C only), SingleDisk-DevGaming (C only), GamerOS-3Disk (D,E,F,C,U-Z,R,T,M) sections

---

## Phase 5: WinPE Integration Enhancement

- [x] 22. Add progress tracking to `Scripts/Capture-Image.ps1` (percentage complete, current file count) — DISM stdout polled every 500ms, Write-Progress with % and elapsed time
- [x] 23. Add disk layout selection parameter to `Scripts/Apply-Image.ps1` (`-DiskLayout`) — ValidateSet(GamerOS-3Disk, SingleDisk-DevGaming, SingleDisk-Generic)
- [x] 24. Implement USB auto-detection improvements in `Apply-Image.ps1` (enumerate USB volumes, pick largest WIM) — scans USB-bus + removable volumes, picks largest .wim
- [x] 25. Integrate checkpoint system into `Capture-Image.ps1` so interrupted captures can resume — checkpoint.json written at start/complete/fail; -Resume switch clears partial WIM
- [ ] 26. Test `Capture-Image.ps1` improvements in WinPE environment
- [ ] 27. Test `Apply-Image.ps1` improvements in WinPE with each disk layout

---

## Phase 6: Testing & Validation Framework

- [x] 28. Add Pester tests for `Build-GoldISO.ps1` parameter validation — `Tests/BuildValidation.Tests.ps1` (layout names, switches, PS 5.1, no parse errors)
- [x] 29. Add Pester test for `Test-UnattendXML.ps1` — feed it a known-bad XML and assert exit code 1 — `Tests/BuildValidation.Tests.ps1`
- [x] 30. Add Pester test for `GoldISO-Common.psm1`: `Initialize-Logging` creates log file — already in `GoldISO-Common.Tests.ps1`
- [x] 31. Add Pester test for `GoldISO-Common.psm1`: `Test-GoldISOAdmin` returns false when not elevated — already in `GoldISO-Common.Tests.ps1`
- [x] 32. Add Pester test for `GoldISO-Common.psm1`: `Get-GoldISORoot` returns a valid path — added extended tests
- [x] 33. Add Pester test for `GoldISO-Common.psm1`: `Format-GoldISOSize` formats bytes correctly — already in `GoldISO-Common.Tests.ps1`
- [x] 34. Add Pester test for `GoldISO-Common.psm1`: `Test-GoldISODiskSpace` fails gracefully when drive missing — added to `GoldISO-Common.Tests.ps1`
- [x] 35. Add JSON schema validation test for `Config/Unattend/Profiles/gaming-gameros.json` against `_schema.json` — `Tests/BuildValidation.Tests.ps1` "Build Profile JSON Schema" describe block
- [x] 36. Add XML validation test for each pass fragment (`Config/Unattend/Passes/*.xml`) — `Tests/BuildValidation.Tests.ps1` "Unattend Pass Fragments — XML Well-formedness" describe block
- [ ] 37. Run `.\Tests\Run-AllTests.ps1 -CodeCoverage` and address any functions with 0% coverage

---

## Driver Injection Split (Extensions/Audio/Monitors → Post-Boot)

- [x] Move Extensions, Software components, APOs, Sound/video/game controllers, Monitors from offline DISM injection to post-boot pnputil in FirstLogonCommands
  - Updated `Config/autounattend.xml` specialize Order 38 (offline only: System, Network, Storage, IDE/ATA)
  - Added `Config/autounattend.xml` FirstLogon Order 51 (pnputil for post-boot categories)
  - Updated `Build-GoldISO.ps1` sequential and parallel driver category lists
  - Updated `Docs/AGENTS.md` and `CLAUDE.md` driver injection strategy

---

## autounattend.xml Hardening

- [ ] 38. Audit all 47 FirstLogonCommands in `Config/autounattend.xml` — verify order is correct (ProtectLetters → folders → apps → tweaks)
- [ ] 39. Verify `shrink-and-recovery.ps1` is embedded or referenced correctly in `specialize` pass
- [ ] 40. Verify `install-usb-apps.ps1` reads `Config/winget-packages.json` at the correct path post-install
- [ ] 41. Verify `install-ramdisk.ps1` and `createramdisk.cmd` execute in correct sequence during OOBE
- [ ] 42. Verify `tweaks-system.cmd` applies HKLM registry tweaks before user-level tweaks
- [ ] 43. Audit network disable/re-enable sequence in `windowsPE` and `oobeSystem` passes

---

## Build Script Housekeeping

- [x] 44. Confirm `Build-GoldISO.ps1 -ParallelDrivers` runspace pool correctly limits to 4 concurrent injections — `[runspacefactory]::CreateRunspacePool(1, 4)` at Build-GoldISO.ps1:808
- [x] 45. Confirm checkpoint JSON format is documented (location, schema) for `-Resume` and `-ClearCheckpoint` — documented in `Docs/ImageCaptureFlow.md`; `Initialize-Checkpoint`/`Save-Checkpoint`/`Test-PhaseComplete` implemented in GoldISO-Common.psm1
- [x] 46. Verify `Scripts/Start-BuildPipeline.ps1` runs `Test-UnattendXML.ps1` before invoking `Build-GoldISO.ps1` — Invoke-Lint.ps1 at line 214, Test-UnattendXML at line 234
- [ ] 47. Review `Scripts/Export-Settings.ps1` — confirm it exports to a path compatible with `Build-ISO-With-Settings.ps1 -ExportUserData`
- [x] 48. Verify `Get-GoldISORoot` in `GoldISO-Common.psm1` resolves correctly when scripts are run from different working directories — rewrote to check 3 candidate paths against 4 reliable markers (CLAUDE.md, Config\autounattend.xml, Scripts\Modules\GoldISO-Common.psm1, autounattend.xml)

---

## Documentation

- [x] 49. Update `Docs/AGENTS.md` to reflect Phase 3 disk layout system (variable substitution details)
- [x] 50. Add Phase 4 section to `Docs/AGENTS.md` documenting `ProtectLetters.ps1` and protected letter sets
- [x] 51. Update `Config/DiskLayouts/README.md` with protected letter sets for all three layouts — done (see item 21)
- [x] 52. Add a `Docs/ImageCaptureFlow.md` documenting the WinPE capture/apply workflow (Phase 5 reference) — updated existing doc with Phase 5 checkpoint/resume, disk layout, USB detection enhancements

---

## Infrastructure / DevEx

- [x] 53. Add `.gitattributes` with `* text=auto eol=lf` to ensure consistent line endings across Windows/Linux
- [x] 54. Add a `Scripts/Invoke-Lint.ps1` that runs PSScriptAnalyzer across all `.ps1` files and fails on errors
- [x] 55. Integrate `Scripts/Invoke-Lint.ps1` into `Start-BuildPipeline.ps1` pre-build step
- [x] 56. Verify `Logs/` and `Tests/Results/` are in `.gitignore` — both present in .gitignore
- [x] 57. Add `CONTRIBUTING.md` with the "never rename layouts without updating ValidateSet" rule and the PS 5.1 constraint
