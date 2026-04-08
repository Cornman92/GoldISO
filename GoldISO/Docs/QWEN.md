# GoldISO — Qwen Agent Guide

**Last Updated**: 2026-04-08
**Model**: Alibaba Qwen (Qwen2.5-Coder) — specialized for code generation and structured data manipulation
**Best For**: PowerShell script writing, JSON/XML manipulation, registry operations, batch code generation

---

## Your Strengths on This Project

Qwen's strong code generation capabilities make you ideal for:

- Writing new PowerShell scripts following the established patterns
- Manipulating XML (autounattend.xml modifications)
- JSON operations (winget-packages.json, build-manifest.json, hardware-matrix.json)
- Batch operations: generating multiple similar functions or config blocks
- Registry key analysis and manipulation scripts
- PowerShell DSC configurations

---

## Project Context

**GoldISO** = custom Windows 11 25H2 ISO builder. All code is PowerShell (5.1 compatible). Key patterns:

```powershell
# Standard script header
#Requires -Version 5.1
[CmdletBinding()]
param(
    [string]$Param1 = "default",
    [switch]$Force
)
$ErrorActionPreference = "Stop"
$script:ProjectRoot = Split-Path $PSScriptRoot -Parent
Import-Module (Join-Path $PSScriptRoot "Modules\GoldISO-Common.psm1") -Force
Test-GoldISOAdmin -ExitIfNotAdmin
```

```powershell
# Standard logging — ALWAYS use this, never Write-Host directly
Write-GoldISOLog -Message "Operation complete" -Level "SUCCESS"
Write-GoldISOLog -Message "Warning: skipping package" -Level "WARN"
Write-GoldISOLog -Message "Fatal error" -Level "ERROR"
```

---

## Recommended Tasks for Qwen

### 1. New PowerShell Script Generation
When asked to create a new script:
- Follow the header/param/import pattern above
- Use `Write-GoldISOLog` for all output
- Put log file at `Join-Path $PSScriptRoot "Logs\<scriptname>-<timestamp>.log"`
- Include `.SYNOPSIS`, `.DESCRIPTION`, `.PARAMETER`, `.EXAMPLE` comment blocks
- Handle `-WhatIf` where the script makes changes

### 2. autounattend.xml Modifications
When modifying `Config/autounattend.xml`:
- Preserve the exact XML namespace declarations
- Maintain `wcm:action="add"` attributes on list items
- Keep `<Order>` values sequential with no gaps
- Use `&amp;` for `&` in `<CommandLine>` values
- Validate syntax: `.\Scripts\Test-UnattendXML.ps1`

```xml
<!-- FirstLogonCommand template -->
<SynchronousCommand wcm:action="add">
    <Order>44</Order>
    <Description>Your description here</Description>
    <CommandLine>powershell.exe -NoProfile -ExecutionPolicy Bypass -File "C:\Scripts\YourScript.ps1"</CommandLine>
    <RequiresUserInput>false</RequiresUserInput>
</SynchronousCommand>
```

### 3. winget-packages.json Updates
Schema pattern for adding packages:

```json
{
    "PackageIdentifier": "Publisher.AppName",
    "PackageVersion": "latest",
    "InstallPath": "C:\\Category",
    "Optional": true,
    "Notes": "Description of what this does"
}
```

### 4. Registry Operations in Scripts
Pattern for registry modifications (used in FirstLogon scripts):

```powershell
# Safe registry set with existence check
function Set-RegistryValue {
    param([string]$Path, [string]$Name, $Value, [string]$Type = "DWord")
    if (-not (Test-Path $Path)) {
        New-Item -Path $Path -Force | Out-Null
    }
    Set-ItemProperty -Path $Path -Name $Name -Value $Value -Type $Type
    Write-GoldISOLog "Registry: $Path\$Name = $Value" -Level "INFO"
}
```

### 5. Driver Manifest Updates
When adding driver entries to `Drivers/download-manifest.json`:

```json
{
    "DriverClass": "Display adapters",
    "Name": "NVIDIA RTX 3060 Ti",
    "Version": "566.36",
    "DownloadURL": "...",
    "InjectionMethod": "PostBoot",
    "InfFile": "nvlti.inf",
    "LastChecked": "2026-04-08"
}
```

### 6. Pester Test Generation
When asked to write tests for a script:

```powershell
#Requires -Version 5.1
#Requires -Modules Pester

BeforeAll {
    $ProjectRoot = Join-Path $PSScriptRoot ".."
    $ModulePath = Join-Path $ProjectRoot "Scripts\Modules\GoldISO-Common.psm1"
    Import-Module $ModulePath -Force
}

Describe "ScriptName Tests" -Tag "Unit" {
    Context "When parameters are valid" {
        It "Should do expected thing" {
            # Arrange
            # Act
            # Assert
            $true | Should -Be $true
        }
    }
}
```

---

## Critical Code Rules

1. **PowerShell 5.1 compatibility** — no `??=`, no `ForEach-Object -Parallel`, no PS7-only syntax
2. **Path separator** — always use `Join-Path`, never string concatenation with `\`
3. **No hardcoded user paths** — never `C:\Users\C-Man\...`, use `$script:ProjectRoot` or `$env:USERPROFILE`
4. **Error handling** — wrap DISM calls in try/catch; log and continue (don't exit) for package failures
5. **Never partition Disk 2 beyond** Windows (C:) + Recovery + MSR + EFI — the rest is Samsung OP

---

## Key Manifests

| File | Purpose | Format |
|------|---------|--------|
| `Config/winget-packages.json` | App install list | Winget schema 2.0 |
| `Config/build-manifest.json` | Build version tracking | Custom JSON |
| `Config/hardware-matrix.json` | Hardware profiles | Custom JSON |
| `Drivers/download-manifest.json` | Driver download URLs | Custom JSON |
| `Packages/manifest.json` | Windows Update packages | Custom JSON |
