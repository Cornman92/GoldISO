# GoldISO Refactoring Plan

Based on comprehensive codebase audit. This plan outlines completed work, remaining priorities, and actionable tasks.

---

## ✅ COMPLETED (P1 - High Priority)

### 1. Standardized Logging
**Status:** Complete across 3 major scripts

| Script | Changes |
|--------|---------|
| `Registry-Only-Summary.ps1` | Removed custom `Write-Log`, now uses `Write-GoldISOLog` |
| `CompleteBuild.ps1` | Removed ~50 line `Write-Log` function, uses module |
| `New-EnhancedStandaloneBuild.ps1` | Removed ~35 line `Write-BuildLog` function, uses module |

**Impact:** ~110 lines of duplicate code eliminated. Consistent log format with timestamps, levels, and colors across all scripts.

### 2. Consolidated Admin Checks
**Status:** Complete

| Script | Before | After |
|--------|--------|-------|
| `Registry-Only-Summary.ps1` | `Test-AdminRights` local function | `Test-GoldISOAdmin -ExitIfNotAdmin` |
| `CompleteBuild.ps1` | `Test-Admin` local function | `Test-GoldISOAdmin -ExitIfNotAdmin` |
| `New-EnhancedStandaloneBuild.ps1` | `Test-Administrator` local function | `Test-GoldISOAdmin -ExitIfNotAdmin` |

**Impact:** Single source of truth for admin privilege checks.

---

## 📋 REMAINING WORK

### P2: High Priority - WIM/ISO Operations Module

**Goal:** Extract common WIM/ISO operations to reusable module functions

#### 2.1 WIM Mount/Unmount Functions
```powershell
# New functions to add to GoldISO-Common.psm1
function Mount-GoldISOWIM { ... }
function Dismount-GoldISOWIM { ... }
function Repair-GoldISOWIMState { ... }  # Emergency cleanup
```

**Duplicate Code Locations:**
- `CompleteBuild.ps1:491-510` - `Mount-WIMImage`, `Dismount-WIMImage`
- `New-EnhancedStandaloneBuild.ps1:469-497` - `Mount-WIM`, `Dismount-WIM`
- `Apply-Image.ps1` - WIM operations for WinPE

**Estimated Effort:** Medium (2-3 hours)
**Files to Modify:** 3 scripts + module

#### 2.2 ISO Creation Functions
```powershell
function New-GoldISOImage { ... }
function Copy-ISOContents { ... }
function Resolve-OscdimgPath { ... }  # Already in 3 scripts
```

**Duplicate Code Locations:**
- `CompleteBuild.ps1:577-646` - ISO mounting, copying, creation
- `New-EnhancedStandaloneBuild.ps1:424-464` - ISO mounting, copying
- `Build-ISO-With-Settings.ps1` - ISO operations

**Estimated Effort:** Medium (2-3 hours)
**Files to Modify:** 3 scripts + module

#### 2.3 Driver Injection Functions
```powershell
function Add-GoldISODrivers { ... }
function Test-DriverManifest { ... }
```

**Duplicate Code Locations:**
- `CompleteBuild.ps1:404-442` - `Invoke-DriverInjection`
- `New-EnhancedStandaloneBuild.ps1:546-561` - `Invoke-DriverInjection`

**Estimated Effort:** Low-Medium (1-2 hours)
**Files to Modify:** 2 scripts + module

---

### P3: Medium Priority - Script Hygiene

#### 3.1 Replace Remaining Write-Host Usage

**High-Impact Targets:**

| Script | Write-Host Count | Priority |
|--------|------------------|----------|
| `Test-UnattendXML.ps1` | 19 | High |
| `Scan-InstalledApps.ps1` | 21 | High |
| `Apply-Image.ps1` | 19 | High |
| `Export-Config.ps1` | 17 | Medium |
| `Restore-Settings.ps1` | 15 | Medium |

**Approach:**
1. Add `Import-Module` statement
2. Replace `Write-Host` with `Write-GoldISOLog`
3. Map colors to log levels (Green→SUCCESS, Red→ERROR, Yellow→WARN, etc.)

**Estimated Effort:** Low per script (15-30 min each)

#### 3.2 Add Module Import to Standalone Scripts

**Scripts Missing Common Module Import:**
- `Scan-InstalledApps.ps1`
- `Convert-WingetExport.ps1`
- `Backup-Config.ps1`
- `Restore-Settings.ps1`
- `Export-Config.ps1`

**Standard Import Pattern:**
```powershell
#Requires -Version 5.1
#Requires -RunAsAdministrator

Import-Module (Join-Path $PSScriptRoot "..\Modules\GoldISO-Common.psm1") -Force
Initialize-Logging -LogPath (Join-Path $env:TEMP "script-name.log")
```

**Estimated Effort:** Very Low (5 min each)

---

### P4: Low Priority - Build Script Consolidation

#### 4.1 Build Script Library
**Problem:** 3 build scripts with overlapping functionality:
- `CompleteBuild.ps1` (840 lines)
- `New-EnhancedStandaloneBuild.ps1` (731 lines)  
- `Build-ISO-With-Settings.ps1` (401 lines)

**Proposed Solution:**
Create `GoldISO-Build.psm1` with:
- `Start-GoldISOBuild` - Main orchestrator
- `Build-GoldISOPhase1` - Dependency download
- `Build-GoldISOPhase2` - WIM modification
- `Build-GoldISOPhase3` - ISO creation

**Estimated Effort:** High (6-8 hours)
**Benefit:** Eliminates 200+ lines of duplication, enables build resumption

#### 4.2 Extract Path Constants
**Current State:** Hardcoded paths scattered across scripts

**Proposed Module Variables:**
```powershell
$script:GoldISOPaths = @{
    Drivers = Join-Path $ProjectRoot "Drivers"
    Applications = Join-Path $ProjectRoot "Applications"
    Config = Join-Path $ProjectRoot "Config"
    TempBuild = "C:\GoldISO_Build"
    TempMount = "C:\Mount"
}
```

**Estimated Effort:** Low (1-2 hours)

---

## 📊 EFFORT SUMMARY

| Priority | Task | Estimated Time | Files Affected |
|----------|------|----------------|----------------|
| P2 | WIM/ISO Module Functions | 4-6 hours | 3 scripts + module |
| P3 | Write-Host Replacement (top 3) | 1-1.5 hours | 3 scripts |
| P3 | Module Import Cleanup | 30 min | 5 scripts |
| P4 | Build Script Consolidation | 6-8 hours | 3 scripts + new module |
| P4 | Path Constants | 1-2 hours | Module + 5+ scripts |

**Total Estimated Effort:** 12-18 hours

---

## 🎯 RECOMMENDED EXECUTION ORDER

### Phase 1: P2 - WIM/ISO Operations (Immediate)
1. Extract `Mount-GoldISOWIM` / `Dismount-GoldISOWIM`
2. Extract `New-GoldISOImage`
3. Extract `Resolve-OscdimgPath` (already exists in 3 places)
4. Update `CompleteBuild.ps1` to use new module functions
5. Update `New-EnhancedStandaloneBuild.ps1` to use new module functions

### Phase 2: P3 - High-Impact Script Hygiene
1. Refactor `Test-UnattendXML.ps1` (19 Write-Host calls)
2. Refactor `Scan-InstalledApps.ps1` (21 Write-Host calls)
3. Refactor `Apply-Image.ps1` (19 Write-Host calls)

### Phase 3: P4 - Structural Improvements
1. Create `GoldISO-Build.psm1` build library
2. Consolidate build script common code
3. Extract path constants to module

---

## 🔧 TECHNICAL NOTES

### Module Import Pattern
All scripts should use this pattern:
```powershell
#Requires -Version 5.1
#Requires -RunAsAdministrator

# Calculate module path (handles both Scriptsuildile.ps1 and Scriptsile.ps1)
$modulePath = Join-Path $PSScriptRoot "..\Modules\GoldISO-Common.psm1"
if (-not (Test-Path $modulePath)) {
    $modulePath = Join-Path $PSScriptRoot "..\..\Modules\GoldISO-Common.psm1"
}
Import-Module $modulePath -Force

Initialize-Logging -LogPath (Join-Path $env:TEMP "script-$(Get-Date -Format 'yyyyMMdd').log")
```

### Log Level Mapping
| Write-Host Color | Write-GoldISOLog Level |
|------------------|------------------------|
| Green | SUCCESS |
| Red | ERROR |
| Yellow | WARN |
| Cyan | INFO (or custom) |
| White/Gray | INFO |
| Magenta | DEBUG |

---

## 📈 SUCCESS METRICS

- **Code Duplication:** Target <100 lines of duplicate code (currently ~400+)
- **Module Function Count:** Target 25+ exported functions (currently 18)
- **Standardized Scripts:** 100% of utility scripts use common module
- **Log Consistency:** All scripts use `Write-GoldISOLog` exclusively

---

*Plan created: April 8, 2026*
*Last updated: Post P1 completion*
