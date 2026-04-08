# GoldISO Test Suite

This directory contains comprehensive Pester tests for the GoldISO project.

## Prerequisites

- PowerShell 5.1 or later
- Pester module 5.0 or later

```powershell
# Install Pester
Install-Module Pester -MinimumVersion 5.0 -Force

# Import Pester
Import-Module Pester
```

## Test Files

| Test File | Purpose |
| --------- | ------- |
| `GoldISO-Common.Tests.ps1` | Unit tests for the GoldISO-Common.psm1 module |
| `Config.Tests.ps1` | JSON config file validation |
| `ScriptSyntax.Tests.ps1` | PowerShell script syntax and structure validation |
| `ProjectStructure.Tests.ps1` | Project file and directory structure validation |

## Running Tests

### Run All Tests

```powershell
# Using the test runner (recommended)
.\Run-AllTests.ps1

# Or directly with Pester
Invoke-Pester -Path .\Tests
```

### Run Specific Test File

```powershell
Invoke-Pester -Path .\Tests\GoldISO-Common.Tests.ps1
```

### Run with Code Coverage

```powershell
.\Run-AllTests.ps1 -CodeCoverage
```

### Run Tests by Tag

```powershell
Invoke-Pester -Path .\Tests -Tag "Unit"
```

## Test Results

Test results are saved to `Tests\Results\` in NUnit XML format compatible with CI/CD systems.

## Adding New Tests

1. Create a new `.Tests.ps1` file in the `Tests` directory
2. Follow Pester 5.x syntax with `BeforeAll`, `Describe`, and `It` blocks
3. Tag tests appropriately with `-Tag "Unit"`, `-Tag "Integration"`, etc.
4. Run tests locally before committing

### Test Template

```powershell
#Requires -Version 5.1
#Requires -Modules Pester

BeforeAll {
    $ProjectRoot = Join-Path $PSScriptRoot ".."
}

Describe "Feature Name" -Tag "Unit" {
    BeforeEach {
        # Setup code
    }

    It "Should do something" {
        # Test assertion
        $true | Should -Be $true
    }

    AfterEach {
        # Cleanup code
    }
}
```

## Test Categories

- **Unit**: Tests for individual functions and modules
- **Integration**: Tests for script interactions
- **Config**: Tests for configuration file validation
- **Structure**: Tests for project organization
