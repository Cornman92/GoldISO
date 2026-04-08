# GoldISO — Codex Agent Guide

**Last Updated**: 2026-04-08
**Model**: OpenAI Codex / GitHub Copilot — inline code completion, boilerplate generation, test scaffolding
**Best For**: Completing partial functions, generating repetitive code patterns, scaffolding new scripts from templates

---

## Your Strengths on This Project

Codex excels at pattern-based code generation from context:

- Completing half-written PowerShell functions
- Generating repetitive switch/case blocks (e.g., winget category handlers)
- Scaffolding Pester test files from the existing test patterns
- Writing parameter validation blocks
- Generating XML fragments for autounattend.xml (FirstLogonCommands, partitions)
- Filling in DISM command sequences from partial scaffolds

---

## Project Context

**Language**: PowerShell 5.1 (strict compatibility — no PS7-only syntax)
**Build system**: DISM + oscdimg
**Test framework**: Pester 5.x
**Config format**: XML (autounattend.xml), JSON (manifests)

---

## Code Templates

### New Script Scaffold

```powershell
#Requires -Version 5.1
<#
.SYNOPSIS
    [One-line purpose]
.DESCRIPTION
    [Detailed description]
.PARAMETER ParamName
    [Parameter description]
.EXAMPLE
    .\ScriptName.ps1 -ParamName "value"
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter(Mandatory = $false)]
    [string]$ParamName = "default",
    
    [switch]$Force
)

$ErrorActionPreference = "Stop"
$script:ScriptName = [System.IO.Path]::GetFileNameWithoutExtension($MyInvocation.MyCommand.Name)
$script:ProjectRoot = Split-Path $PSScriptRoot -Parent

Import-Module (Join-Path $PSScriptRoot "Modules\GoldISO-Common.psm1") -Force
Test-GoldISOAdmin -ExitIfNotAdmin

$logPath = Join-Path $PSScriptRoot "Logs\$script:ScriptName-$(Get-Date -Format yyyyMMdd-HHmmss).log"
Initialize-Logging -LogPath $logPath
Write-GoldISOLog "Starting $script:ScriptName" -Level "INFO"

try {
    # Main logic here
    
    Write-GoldISOLog "$script:ScriptName completed successfully" -Level "SUCCESS"
} catch {
    Write-GoldISOLog "Fatal error: $($_.Exception.Message)" -Level "ERROR"
    throw
}
```

### Pester Test Scaffold

```powershell
#Requires -Version 5.1
#Requires -Modules Pester

BeforeAll {
    $ProjectRoot = Join-Path $PSScriptRoot ".."
    $ScriptPath  = Join-Path $ProjectRoot "Scripts\ScriptName.ps1"
    $ModulePath  = Join-Path $ProjectRoot "Scripts\Modules\GoldISO-Common.psm1"
    Import-Module $ModulePath -Force
}

Describe "ScriptName" -Tag "Unit" {
    
    BeforeEach {
        # Common setup
        Mock Write-GoldISOLog { }
        Mock Test-GoldISOAdmin { $true }
    }
    
    Context "Happy path" {
        It "Should succeed with valid inputs" {
            # Arrange
            $expected = "expected value"
            
            # Act
            $result = "actual value"
            
            # Assert
            $result | Should -Be $expected
        }
    }
    
    Context "Error handling" {
        It "Should log error and throw on failure" {
            { throw "test error" } | Should -Throw
        }
    }
    
    AfterEach {
        # Cleanup
    }
}
```

### FirstLogonCommand XML Fragment

```xml
<SynchronousCommand wcm:action="add">
    <Order><!-- NEXT ORDER NUMBER --></Order>
    <Description><!-- What this does --></Description>
    <CommandLine>powershell.exe -NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File "C:\Scripts\<!-- ScriptName.ps1 -->"</CommandLine>
    <RequiresUserInput>false</RequiresUserInput>
</SynchronousCommand>
```

### Winget Package JSON Entry

```json
{
    "PackageIdentifier": "Publisher.AppName",
    "PackageVersion": "latest",
    "InstallPath": "C:\\Category",
    "Optional": true,
    "Notes": "What this app does"
}
```

### DISM Driver Injection Loop

```powershell
$driverRoot = Join-Path $script:ProjectRoot "Drivers"
$drivers = Get-ChildItem -Path $driverRoot -Recurse -Filter "*.inf"
foreach ($driver in $drivers) {
    try {
        Add-WindowsDriver -Path $MountDir -Driver $driver.FullName -ErrorAction Stop
        Write-GoldISOLog "Injected: $($driver.Name)" -Level "SUCCESS"
    } catch {
        Write-GoldISOLog "Driver failed: $($driver.Name) — $($_.Exception.Message)" -Level "WARN"
    }
}
```

### Switch Block for Winget Categories

```powershell
foreach ($category in $packages.Keys) {
    switch ($category) {
        "browsers"   { $installPath = $env:ProgramFiles }
        "dev_tools"  { $installPath = "C:\Dev" }
        "gaming"     { $installPath = "C:\Gaming" }
        "media"      { $installPath = "C:\Media" }
        "utilities"  { $installPath = "C:\Utils" }
        "remote"     { $installPath = "C:\Remote" }
        default      { $installPath = $env:ProgramFiles }
    }
    # Install packages in this category...
}
```

---

## Completion Rules

When completing partial code in this project:

1. **Keep PowerShell 5.1 syntax** — no `??=`, no parallel foreach, no `using namespace`
2. **Use `Write-GoldISOLog`** not `Write-Host` or `Write-Output`
3. **Use `Join-Path`** not string `+` for paths
4. **Wrap DISM calls in try/catch** — they can fail on stale packages; log and continue
5. **No hardcoded user paths** — use `$script:ProjectRoot`, `$env:USERPROFILE`, or `$env:ProgramFiles`
6. **Order values in XML are sequential** — find the last `<Order>N</Order>` and use N+1
7. **`&amp;` in XML CommandLine** — never raw `&`

---

## Files Worth Knowing

| File | Use When |
|------|----------|
| `Scripts/Build-GoldISO.ps1` | Reference for build pattern, error handling style |
| `Scripts/Modules/GoldISO-Common.psm1` | Functions available without writing new ones |
| `Tests/GoldISO-Common.Tests.ps1` | Reference for Pester patterns used in this project |
| `Config/autounattend.xml` | XML patterns for new FirstLogonCommands |
| `Config/winget-packages.json` | JSON schema for package entries |
