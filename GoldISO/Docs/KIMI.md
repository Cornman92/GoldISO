# GoldISO — Kimi Agent Guide

**Last Updated**: 2026-04-08
**Model**: Kimi (Moonshot AI) — optimized for long-context analysis and document processing
**Best For**: Reading entire large files, cross-file analysis, comprehensive documentation review

---

## Your Strengths on This Project

Kimi's extended context window (128K–1M tokens) makes you ideal for tasks that require holding the entire project in memory simultaneously:

- Reading `autounattend.xml` (large XML, 43 FirstLogonCommands) in full and reasoning about the complete command sequence
- Analyzing `Docs/PLAN.md` (2100+ lines) without truncation
- Cross-referencing `Config/winget-packages.json` against `Scripts/install-usb-apps.ps1` to verify package IDs match
- Reading all 30+ PowerShell profile scripts in `Config/PowerShellProfile/PSProfile.C-Man/` to understand the full profile system
- Reviewing the complete `Build-GoldISO.ps1` (1346 lines) as a whole

---

## Project Context

GoldISO is a custom Windows 11 25H2 ISO build system for "GamerOS" — a gaming-optimized desktop. Key facts:

- **Primary output**: `GamerOS-Win11x64Pro25H2.iso`
- **Build script**: `Scripts/Build-GoldISO.ps1`
- **Answer file**: `Config/autounattend.xml` (canonical) — always validate after edits
- **Target hardware**: 3-disk system; Disk 2 = Samsung NVMe primary (~843 GB C: + 15 GB recovery + ~90 GB unallocated OP)
- **GWIG companion**: `C:\Users\C-Man\GWIG` — 94-stage pipeline for automated builds

---

## Recommended Tasks for Kimi

### 1. autounattend.xml Full Audit
Read the entire `Config/autounattend.xml` and:
- Verify all 43 FirstLogonCommands are in correct order (gaps = problem)
- Check for duplicate `<Order>` values
- Identify any scripts referenced in `<CommandLine>` that don't exist in `Scripts/`
- Verify disk partition sizes add up correctly for Disk 2

### 2. Cross-File Consistency Check
Read all of these together and report inconsistencies:
- `Config/winget-packages.json` — package IDs
- `Scripts/install-usb-apps.ps1` — how packages are installed
- `Docs/AGENTS.md` — documented package list
- `Scripts/README.md` — script documentation

### 3. PLAN.md Gap Analysis
Read `Docs/PLAN.md` in full and identify:
- Phases that have no corresponding script implementation
- Steps that are documented but scripts are missing
- Outdated references (wrong paths, old ISO names)

### 4. PowerShell Profile Dependency Analysis
Read all files in `Config/PowerShellProfile/PSProfile.C-Man/` and:
- Map which modules depend on which others
- Identify functions that are defined multiple times
- Find functions that are called but never defined

### 5. Build-GoldISO.ps1 Full Review
Read `Scripts/Build-GoldISO.ps1` completely and:
- Trace the complete execution flow from param block to ISO creation
- Identify any variables that are set but never used
- Find error paths that silently continue when they should fail
- Check that all `-Skip*` parameters actually skip the right sections

---

## Constraints

- **Do not partition the ~90 GB unallocated space on Disk 2** — that is Samsung NVMe overprovisioning
- **Disk IDs are machine-specific** — Disk 2 is the primary NVMe on the target machine only
- **Always validate XML** with `.\Scripts\Test-UnattendXML.ps1` after any `autounattend.xml` change
- **Config/autounattend.xml is canonical** — root `autounattend.xml` is a build-time copy

---

## How to Reference Files

When working on this project, use these absolute paths:
- Project root: `C:\Users\C-Man\GoldISO\`
- Answer file: `C:\Users\C-Man\GoldISO\Config\autounattend.xml`
- Main build script: `C:\Users\C-Man\GoldISO\Scripts\Build-GoldISO.ps1`
- Shared module: `C:\Users\C-Man\GoldISO\Scripts\Modules\GoldISO-Common.psm1`
- GWIG pipeline: `C:\Users\C-Man\GWIG\Scripts\Core\Pipeline\Invoke-GamerOSPipeline-v2.ps1`
