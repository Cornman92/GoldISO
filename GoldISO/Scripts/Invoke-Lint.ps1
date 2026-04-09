#Requires -Version 5.1
<#
.SYNOPSIS
    Runs PSScriptAnalyzer across all GoldISO PowerShell scripts.
.DESCRIPTION
    Lints every .ps1 and .psm1 file under Scripts/ and Tests/ using PSScriptAnalyzer.
    Exits with code 1 if any Error-severity findings are present.
    Warnings are printed but do not cause failure.
.PARAMETER Path
    Root directory to scan. Defaults to the project root.
.PARAMETER FailOnWarning
    Also exit 1 if any Warning-severity findings exist.
.EXAMPLE
    .\Scripts\Invoke-Lint.ps1
.EXAMPLE
    .\Scripts\Invoke-Lint.ps1 -FailOnWarning
#>
[CmdletBinding()]
param(
    [string]$Path = "",
    [switch]$FailOnWarning
)

$ErrorActionPreference = "Stop"

# Resolve project root
if (-not $Path) {
    $Path = Split-Path $PSScriptRoot -Parent
}

# Ensure PSScriptAnalyzer is available
if (-not (Get-Module -ListAvailable -Name PSScriptAnalyzer)) {
    Write-Host "[ERROR] PSScriptAnalyzer not installed. Run: Install-Module PSScriptAnalyzer -Force" -ForegroundColor Red
    exit 1
}

Import-Module PSScriptAnalyzer -Force

# Gather scripts
$scanDirs = @(
    (Join-Path $Path "Scripts"),
    (Join-Path $Path "Tests")
)

$allFiles = foreach ($dir in $scanDirs) {
    if (Test-Path $dir) {
        Get-ChildItem -Path $dir -Include "*.ps1","*.psm1" -Recurse -ErrorAction SilentlyContinue
    }
}

if (-not $allFiles) {
    Write-Host "[WARN] No PowerShell files found to lint under: $($scanDirs -join ', ')" -ForegroundColor Yellow
    exit 0
}

Write-Host "==========================================" -ForegroundColor Cyan
Write-Host "GoldISO PSScriptAnalyzer Lint" -ForegroundColor Cyan
Write-Host "Scanning $($allFiles.Count) file(s)..." -ForegroundColor Cyan
Write-Host "==========================================" -ForegroundColor Cyan

$allFindings = @()

foreach ($file in $allFiles) {
    $findings = Invoke-ScriptAnalyzer -Path $file.FullName -Severity @("Error","Warning","Information") -ErrorAction SilentlyContinue
    if ($findings) {
        $allFindings += $findings
        foreach ($f in $findings) {
            $color = switch ($f.Severity) {
                "Error"       { "Red" }
                "Warning"     { "Yellow" }
                default       { "Gray" }
            }
            $relativePath = $file.FullName.Replace($Path, "").TrimStart("\")
            Write-Host "[$($f.Severity)] $relativePath`:$($f.Line) — $($f.RuleName): $($f.Message)" -ForegroundColor $color
        }
    }
}

$errors   = @($allFindings | Where-Object { $_.Severity -eq "Error" })
$warnings = @($allFindings | Where-Object { $_.Severity -eq "Warning" })

Write-Host ""
Write-Host "==========================================" -ForegroundColor Cyan
Write-Host "Lint Summary" -ForegroundColor Cyan
Write-Host "  Files scanned : $($allFiles.Count)"
Write-Host "  Errors        : $($errors.Count)" -ForegroundColor $(if ($errors.Count -gt 0) { "Red" } else { "Green" })
Write-Host "  Warnings      : $($warnings.Count)" -ForegroundColor $(if ($warnings.Count -gt 0) { "Yellow" } else { "Green" })
Write-Host "==========================================" -ForegroundColor Cyan

if ($errors.Count -gt 0) {
    Write-Host "Lint FAILED — $($errors.Count) error(s) found." -ForegroundColor Red
    exit 1
}

if ($FailOnWarning -and $warnings.Count -gt 0) {
    Write-Host "Lint FAILED — $($warnings.Count) warning(s) found (-FailOnWarning)." -ForegroundColor Red
    exit 1
}

Write-Host "Lint PASSED" -ForegroundColor Green
exit 0
