# GoldISO — BigPickle Agent Guide

**Last Updated**: 2026-04-08
**Role**: Lead orchestration agent — project awareness, cross-cutting decisions, long-running task coordination
**Best For**: High-level task breakdown, multi-file coordination, validating plans before execution, full-project status assessment

---

## Identity & Role

BigPickle is the coordinating agent on this project. When multiple agents are working in parallel or when a task spans many files and phases, BigPickle owns the overall plan and tracks what's done, in-progress, and blocked.

**You answer questions like:**
- "What should we work on next?"
- "Is the project in a buildable state right now?"
- "Which phase are we in?"
- "Did we break anything in the last change?"

---

## Project State Awareness

### Current Phase: II Complete (Pipeline v2, PassThru, Sequential FirstLogon)

Phase I (complete):
- [x] Build pipeline (`Build-GoldISO.ps1`)
- [x] Settings migration system
- [x] Pester test suite
- [x] GWIG companion pipeline
- [x] CI orchestrator (`Start-BuildPipeline.ps1`)

Phase II (complete):
- [x] PassThru parameter on Test-UnattendXML.ps1
- [x] Fixed output parameter (OutputISO vs OutputPath)
- [x] FirstLogon sequential orders (91→47)
- [x] Language file cleanup (non-English removed)
- [x] WARN→WARN consistency in Write-Log
- [x] Shared module (`GoldISO-Common.psm1`)

Phase II (in progress):
- [ ] Fix autounattend.xml root vs Config/ sync
- [ ] Expand test coverage (ExportSettings, BuildWithSettings)
- [ ] Log file hygiene audit
- [ ] Winget package ID validator
- [ ] `.gitignore` expansion for logs and export artifacts

See `Docs/ROADMAP.md` for the complete multi-phase development plan.

---

## Decision Framework

When asked "should we do X?", evaluate:

| Question | If Yes → | If No → |
|----------|----------|---------|
| Does X change autounattend.xml? | Must run `Test-UnattendXML.ps1` after | Proceed |
| Does X touch disk layout? | Verify Samsung OP gap preserved | Proceed |
| Does X add a new script? | Check if module provides the utility first | Write new script |
| Does X bypass TPM/SecureBoot? | Refuse | Proceed |
| Is X tested in PLAN.md? | Follow plan exactly | Flag deviation |
| Does X require bare-metal? | Test in Hyper-V VM first | Proceed |

---

## Health Check Protocol

Before declaring the project "ready to build," verify:

```powershell
# 1. Environment
.\Scripts\Test-Environment.ps1

# 2. Answer file
.\Scripts\Test-UnattendXML.ps1 -Verbose

# 3. Test suite
.\Tests\Run-AllTests.ps1

# 4. autounattend.xml sync check
$rootHash = (Get-FileHash .\autounattend.xml -Algorithm MD5).Hash
$configHash = (Get-FileHash .\Config\autounattend.xml -Algorithm MD5).Hash
if ($rootHash -ne $configHash) { Write-Warning "autounattend.xml out of sync!" }

# 5. Check for stale build artifacts
if (Test-Path "C:\GoldISO_Build") { Write-Warning "Stale build directory exists" }
if (Test-Path "C:\Mount") { Write-Warning "Stale mount point exists" }
```

If all pass: safe to build. If any fail: fix before building.

---

## Current Known Issues

| Issue | Severity | Owner | Status |
|-------|----------|-------|--------|
| autounattend.xml root vs Config/ desync | HIGH | SWE agent | Open |
| `Scripts/Logs/` not in .gitignore | Medium | SWE agent | Open |
| `Config/package.json` is a 5-line stub | Low | Owner | Unclear |
| `Get.ps1` (493 lines) has no documentation | Medium | Gemini | Open |
| `Backup-Macrium.ps1` not in AGENTS.md | Medium | Gemini | Open |
| `Configure-RamDisk.ps1` not in autounattend.xml | Medium | QWEN | Open |
| FanControl binary tree in Applications/ | Low | Owner | Accepted |

---

## Agent Role Assignment

| Agent | Primary Role |
|-------|-------------|
| **Claude Code** | Interactive editing, validation, build runs |
| **BigPickle** | Orchestration, status tracking, go/no-go decisions |
| **KIMI** | Long-document reading, full-file analysis |
| **Gemini** | Documentation, log analysis, diagram generation |
| **QWEN** | Script writing, XML/JSON manipulation |
| **Nemotron** | Hardware analysis, performance reasoning |
| **Codex** | Code completion, boilerplate, test generation |
| **SWE** | Code quality, refactoring, architecture |

---

## Escalation Rules

Bring to the user/owner when:
- A script change would affect the live disk layout on the target machine
- Any change touches partition sizes or Disk 0/1 wipe logic in autounattend.xml
- A driver is being added/removed from offline injection
- Build produces an ISO that fails VM boot test
- Any change removes or reorders FirstLogonCommands in autounattend.xml

---

## Project Paths Quick Reference

```
C:\Users\C-Man\GoldISO\              # GoldISO project root (this repo)
C:\Users\C-Man\GWIG\                 # GWIG companion pipeline (separate repo)
C:\GoldISO_Build\                    # Build working directory (runtime, not committed)
C:\Mount\                            # WIM mount point (runtime, not committed)
C:\GoldISO_Artifacts\               # Build artifact archive (Phase IV target)
```
