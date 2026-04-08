# GoldISO — Gemini Agent Guide

**Last Updated**: 2026-04-08
**Model**: Google Gemini (multimodal, long context, strong documentation and reasoning)
**Best For**: Documentation generation, log analysis, visual output interpretation, structured reporting

---

## Your Strengths on This Project

Gemini's multimodal capabilities and strong document understanding make you ideal for:

- Generating comprehensive documentation from code (JSDoc-style → Markdown)
- Analyzing build logs and extracting failure patterns
- Interpreting screenshots of Windows installation states or DISM output
- Writing structured reports from unstructured log data
- Creating diagrams and flow descriptions for complex workflows
- Reviewing `autounattend.xml` against Microsoft's Unattended Windows Setup Reference

---

## Project Context

GoldISO builds a custom Windows 11 25H2 ISO called "GamerOS." Key components:

| Component | Path | Purpose |
|-----------|------|---------|
| Main builder | `Scripts/Build-GoldISO.ps1` | 1346-line ISO build script |
| Answer file | `Config/autounattend.xml` | Drives unattended install (43 FirstLogonCommands) |
| CI pipeline | `Scripts/Start-BuildPipeline.ps1` | Orchestrates all stages |
| Shared module | `Scripts/Modules/GoldISO-Common.psm1` | Logging, admin checks |
| Test suite | `Tests/` | Pester 5.x tests |
| App manifest | `Config/winget-packages.json` | Winget package definitions |

---

## Recommended Tasks for Gemini

### 1. Log Analysis
When provided a build log from `Scripts/Logs/build.log` or `C:\GoldISO_Build\build.log`:
- Extract all `[ERROR]` and `[WARN]` entries
- Group errors by category (DISM, driver, package, XML)
- Suggest fixes for each error pattern
- Summarize the overall build health

### 2. Documentation Generation
For any PowerShell script in `Scripts/`:
- Read the script and generate a comprehensive Markdown doc
- Include: purpose, parameters, examples, side effects, log output locations
- Format suitable for addition to `Scripts/README.md`

### 3. Workflow Diagrams
Create ASCII or Mermaid diagrams for:
- The full build pipeline (Phase 0 → 10 from `Docs/PLAN.md`)
- The settings migration workflow (Export → Embed → Restore)
- The WinPE Capture → Apply flow from `Docs/ImageCaptureFlow.md`

### 4. autounattend.xml Documentation
Read `Config/autounattend.xml` and produce:
- A table of all 43 FirstLogonCommands with Order, Description, and CommandLine
- A table of all disk partitions with Type, Size, and Purpose
- List of all scripts embedded in `<Extensions>` blocks
- Cross-reference: which Commands reference which scripts

### 5. Structured Test Reports
Given Pester output from `.\Tests\Run-AllTests.ps1`:
- Parse pass/fail counts
- Identify patterns in failures
- Generate a summary table suitable for a git commit message or README update

### 6. winget-packages.json Review
Read `Config/winget-packages.json` and:
- Verify JSON schema compliance against `https://aka.ms/winget-packages.schema.2.0.json`
- Identify any packages that may be outdated (check release dates in names)
- Generate a human-readable list grouped by category

---

## Output Format Preferences

When generating documentation for this project:
- Use **GitHub-flavored Markdown**
- Use **tables** for parameter lists, file references, and comparison data
- Use **fenced code blocks** with `powershell` language tag for all PS code
- Keep headers at 2-3 levels max (`##`, `###`)
- Include a "Last Updated" date at the top of every document

---

## Constraints

- **Never suggest bypassing TPM or Secure Boot** — intentionally required
- **Never suggest partitioning the ~90 GB gap on Disk 2** — Samsung NVMe overprovisioning
- **Config/autounattend.xml is canonical** — any edits go there, not root
- **Always include validation reminder** after XML changes: `.\Scripts\Test-UnattendXML.ps1`
- **Do not add features not requested** — this is a production system, not a playground

---

## Key File Paths

```
C:\Users\C-Man\GoldISO\               # Project root
C:\Users\C-Man\GoldISO\Config\autounattend.xml   # Canonical answer file
C:\Users\C-Man\GoldISO\Scripts\Logs\             # Runtime logs
C:\GoldISO_Build\build.log            # Build log (created during build)
C:\Users\C-Man\GWIG\                  # Companion GWIG pipeline project
```
