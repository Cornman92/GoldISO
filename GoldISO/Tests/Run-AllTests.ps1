#Requires -Version 5.1
#Requires -Modules Pester
<#
.SYNOPSIS
    Test runner for all GoldISO tests.
.DESCRIPTION
    Runs the complete test suite for the GoldISO project.
    Generates detailed output and summary reports.
.PARAMETER OutputPath
    Directory for test results output. Default: .\Results
.PARAMETER CodeCoverage
    Enable code coverage analysis for the GoldISO-Common module.
.PARAMETER Tag
    Run only tests with specified tags.
.EXAMPLE
    .\Run-AllTests.ps1
    Run all tests
.EXAMPLE
    .\Run-AllTests.ps1 -CodeCoverage
    Run tests with code coverage
.EXAMPLE
    .\Run-AllTests.ps1 -Tag "Unit"
    Run only unit tests
.NOTES
    Requires Pester module 5.0 or later.
    Install with: Install-Module Pester -MinimumVersion 5.0 -Force
#>
[CmdletBinding()]
param(
    [string]$OutputPath = (Join-Path $PSScriptRoot "Results"),
    [switch]$CodeCoverage,
    [string]$Tag
)

# Ensure Pester is available
$pesterModule = Get-Module -ListAvailable -Name Pester | Sort-Object Version -Descending | Select-Object -First 1
if (-not $pesterModule) {
    Write-Error "Pester module not found. Install with: Install-Module Pester -MinimumVersion 5.0 -Force"
    exit 1
}

if ($pesterModule.Version -lt [Version]"5.0") {
    Write-Warning "Pester version $($pesterModule.Version) found. Version 5.0+ recommended."
}

# Create results directory
if (-not (Test-Path $OutputPath)) {
    New-Item -ItemType Directory -Path $OutputPath -Force | Out-Null
}

$timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
$resultFile = Join-Path $OutputPath "TestResults-$timestamp.xml"

# Build Pester configuration
$configuration = New-PesterConfiguration
$configuration.Run.Path = $PSScriptRoot
$configuration.Run.PassThru = $true
$configuration.Output.Verbosity = "Detailed"

if ($Tag) {
    $configuration.Filter.Tag = $Tag
}

# Configure test result output
$configuration.TestResult.Enabled = $true
$configuration.TestResult.OutputPath = $resultFile
$configuration.TestResult.OutputFormat = "NUnitXml"

# Code coverage configuration
if ($CodeCoverage) {
    $commonModule = Join-Path $PSScriptRoot "..\Scripts\Modules\GoldISO-Common.psm1"
    if (Test-Path $commonModule) {
        $configuration.CodeCoverage.Enabled = $true
        $configuration.CodeCoverage.Path = $commonModule
        $configuration.CodeCoverage.OutputPath = Join-Path $OutputPath "CodeCoverage-$timestamp.xml"
        $configuration.CodeCoverage.OutputFormat = "JaCoCo"
    } else {
        Write-Warning "GoldISO-Common module not found. Skipping code coverage."
    }
}

# Run tests
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "GoldISO Test Suite" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Results will be saved to: $resultFile"
Write-Host ""

try {
    $testResults = Invoke-Pester -Configuration $configuration
    
    # Output summary
    Write-Host ""
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host "Test Summary" -ForegroundColor Cyan
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host "Total Tests: $($testResults.TotalCount)"
    Write-Host "Passed: $($testResults.PassedCount)" -ForegroundColor Green
    Write-Host "Failed: $($testResults.FailedCount)" -ForegroundColor Red
    Write-Host "Skipped: $($testResults.SkippedCount)" -ForegroundColor Yellow
    Write-Host "========================================" -ForegroundColor Cyan
    
    if ($testResults.FailedCount -gt 0) {
        Write-Host ""
        Write-Host "Failed Tests:" -ForegroundColor Red
        foreach ($failedTest in $testResults.Failed) {
            Write-Host "  - $($failedTest.FullName)" -ForegroundColor Red
        }
        exit 1
    } else {
        Write-Host ""
        Write-Host "All tests passed!" -ForegroundColor Green
        exit 0
    }
}
catch {
    Write-Error "Test execution failed: $_"
    exit 1
}
