#Requires -Version 5.1
#Requires -Modules Pester
<#
.SYNOPSIS
    Test runner for all GoldISO tests.
.DESCRIPTION
    Runs the complete test suite for the GoldISO project.
    Generates detailed output and summary reports.
    Compatible with Pester 3.x and 5.x
.PARAMETER OutputPath
    Directory for test results output. Default: .\Results
.PARAMETER CodeCoverage
    Enable code coverage analysis for the GoldISO-Common module. (Pester 5+ only)
.PARAMETER Tag
    Run only tests with specified tags. (Pester 5+ only)
.EXAMPLE
    .\Run-AllTests.ps1
    Run all tests
.EXAMPLE
    .\Run-AllTests.ps1 -CodeCoverage
    Run tests with code coverage (requires Pester 5+)
.EXAMPLE
    .\Run-AllTests.ps1 -Tag "Unit"
    Run only unit tests (requires Pester 5+)
.NOTES
    Pester 5.0+ recommended for full features.
    Install with: Install-Module Pester -MinimumVersion 5.0 -Force -SkipPublisherCheck
#>
[CmdletBinding()]
param(
    [string]$OutputPath = "",
    [switch]$CodeCoverage,
    [string]$Tag
)

# Determine script root (handles cases where $PSScriptRoot is empty)
$testRoot = $PSScriptRoot
if (-not $testRoot) {
    $testRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
}

# Set default output path if not provided
if (-not $OutputPath) {
    $OutputPath = Join-Path $testRoot "Results"
}

# Ensure Pester is available
$pesterModule = Get-Module -ListAvailable -Name Pester | Sort-Object Version -Descending | Select-Object -First 1
if (-not $pesterModule) {
    Write-Error "Pester module not found. Install with: Install-Module Pester -MinimumVersion 5.0 -Force -SkipPublisherCheck"
    exit 1
}

$pesterVersion = $pesterModule.Version
$isPester5 = $pesterVersion -ge [Version]"5.0"

if (-not $isPester5) {
    Write-Warning "Pester version $pesterVersion found. Some features require 5.0+. Consider upgrading."
}

# Create results directory
if (-not (Test-Path $OutputPath)) {
    New-Item -ItemType Directory -Path $OutputPath -Force | Out-Null
}

$timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
$resultFile = Join-Path $OutputPath "TestResults-$timestamp.xml"

# Run tests
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "GoldISO Test Suite" -ForegroundColor Cyan
Write-Host "Pester Version: $pesterVersion" -ForegroundColor Gray
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Results will be saved to: $resultFile"
Write-Host ""

try {
    $testResults = $null
    
    if ($isPester5) {
        # Pester 5.x configuration-based approach
        $configuration = New-PesterConfiguration
        $configuration.Run.Path = $testRoot
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
            $commonModule = Join-Path $testRoot "..\Scripts\Modules\GoldISO-Common.psm1"
            if (Test-Path $commonModule) {
                $configuration.CodeCoverage.Enabled = $true
                $configuration.CodeCoverage.Path = $commonModule
                $configuration.CodeCoverage.OutputPath = Join-Path $OutputPath "CodeCoverage-$timestamp.xml"
                $configuration.CodeCoverage.OutputFormat = "JaCoCo"
            } else {
                Write-Warning "GoldISO-Common module not found. Skipping code coverage."
            }
        }
        
        $testResults = Invoke-Pester -Configuration $configuration
    } else {
        # Pester 3.x/4.x legacy approach
        $pesterParams = @{
            Path = $testRoot
            PassThru = $true
            OutputFile = $resultFile
            OutputFormat = "NUnitXml"
        }
        
        if ($CodeCoverage) {
            Write-Warning "Code coverage requires Pester 5.0+. Skipping."
        }
        
        $testResults = Invoke-Pester @pesterParams
    }
    
    # Output summary
    Write-Host ""
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host "Test Summary" -ForegroundColor Cyan
    Write-Host "========================================" -ForegroundColor Cyan
    
    # Handle different property names between Pester versions
    if ($isPester5) {
        Write-Host "Total Tests: $($testResults.TotalCount)"
        Write-Host "Passed: $($testResults.PassedCount)" -ForegroundColor Green
        Write-Host "Failed: $($testResults.FailedCount)" -ForegroundColor Red
        Write-Host "Skipped: $($testResults.SkippedCount)" -ForegroundColor Yellow
        $failedTests = $testResults.Failed
    } else {
        # Pester 3.x uses different property names
        Write-Host "Total Tests: $($testResults.TotalCount)"
        Write-Host "Passed: $($testResults.PassedCount)" -ForegroundColor Green
        Write-Host "Failed: $($testResults.FailedCount)" -ForegroundColor Red
        Write-Host "Skipped: $($testResults.PendingCount + $testResults.SkippedCount)" -ForegroundColor Yellow
        $failedTests = $testResults.TestResult | Where-Object { $_.Passed -eq $false }
    }
    
    Write-Host "========================================" -ForegroundColor Cyan
    
    if ($testResults.FailedCount -gt 0) {
        Write-Host ""
        Write-Host "Failed Tests:" -ForegroundColor Red
        if ($isPester5) {
            foreach ($failedTest in $failedTests) {
                Write-Host "  - $($failedTest.FullName)" -ForegroundColor Red
            }
        } else {
            foreach ($failedTest in $failedTests) {
                Write-Host "  - $($failedTest.Name)" -ForegroundColor Red
            }
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
