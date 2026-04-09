#Requires -Version 5.1
<#
.SYNOPSIS
    Validates the GoldISO build environment.
.DESCRIPTION
    Performs pre-flight checks to ensure the system is ready for GoldISO operations:
    - PowerShell execution policy
    - Required Windows features (DISM, NetFx3)
    - Windows ADK availability (oscdimg)
    - Disk space for build operations
    - Network connectivity
    - File path permissions
.PARAMETER SkipDiskCheck
    Skip disk space validation.
.PARAMETER SkipNetworkCheck
    Skip network connectivity tests.
.EXAMPLE
    .\Test-Environment.ps1
.EXAMPLE
    .\Test-Environment.ps1 -SkipNetworkCheck
.NOTES
    Run this before executing Build-GoldISO.ps1 or other build operations.
#>
[CmdletBinding()]
param(
    [switch]$SkipDiskCheck,
    [switch]$SkipNetworkCheck
)

$ErrorActionPreference = "Continue"

# Import common module
$commonModule = Join-Path $PSScriptRoot "Modules\GoldISO-Common.psm1"
if (Test-Path $commonModule) {
    Import-Module $commonModule -Force -ErrorAction SilentlyContinue
}

# Initialize logging
$logPath = Join-Path $PSScriptRoot "Logs\Test-Environment-$(Get-Date -Format 'yyyyMMdd-HHmmss').log"
if (Get-Command Initialize-Logging -ErrorAction SilentlyContinue) {
    Initialize-Logging -LogPath $logPath
}

# Results tracking
$script:Passed = [System.Collections.Generic.List[string]]::new()
$script:Warnings = [System.Collections.Generic.List[string]]::new()
$script:Errors = [System.Collections.Generic.List[string]]::new()

function Write-Result {
    param([string]$Message, [string]$Level = "PASS")
    
    $prefix = switch ($Level) {
        "PASS" { "[PASS]" }
        "WARN" { "[WARN]" }
        "FAIL" { "[FAIL]" }
        "INFO" { "[INFO]" }
    }
    
    $color = switch ($Level) {
        "PASS" { "Green" }
        "WARN" { "Yellow" }
        "FAIL" { "Red" }
        default { "White" }
    }
    
    Write-Host "$prefix $Message" -ForegroundColor $color
    
    switch ($Level) {
        "PASS" { $script:Passed.Add($Message) }
        "WARN" { $script:Warnings.Add($Message) }
        "FAIL" { $script:Errors.Add($Message) }
    }
    
    if (Get-Command Write-GoldISOLog -ErrorAction SilentlyContinue) {
        Write-GoldISOLog -Message $Message -Level $(if ($Level -eq "FAIL") { "ERROR" } elseif ($Level -eq "WARN") { "WARN" } else { "INFO" })
    }
}

function Test-ExecutionPolicy {
    Write-Result "Checking PowerShell execution policy..." "INFO"
    
    $policy = Get-ExecutionPolicy
    if ($policy -in @("RemoteSigned", "Unrestricted", "Bypass")) {
        Write-Result "Execution policy is sufficient: $policy" "PASS"
    } else {
        Write-Result "Execution policy may be too restrictive: $policy (recommend RemoteSigned)" "WARN"
    }
}

function Test-AdminRights {
    Write-Result "Checking administrator privileges..." "INFO"
    
    if (Get-Command Test-GoldISOAdmin -ErrorAction SilentlyContinue) {
        if (Test-GoldISOAdmin) {
            Write-Result "Running with administrator privileges" "PASS"
        } else {
            Write-Result "Administrator privileges required for DISM operations" "FAIL"
        }
    } else {
        $isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
            [Security.Principal.WindowsBuiltInRole]::Administrator
        )
        if ($isAdmin) {
            Write-Result "Running with administrator privileges" "PASS"
        } else {
            Write-Result "Administrator privileges required for DISM operations" "FAIL"
        }
    }
}

function Test-RequiredFeatures {
    Write-Result "Checking required Windows features..." "INFO"
    
    # Check DISM (should always be available on modern Windows)
    $dism = Get-Command dism -ErrorAction SilentlyContinue
    if ($dism) {
        Write-Result "DISM available at: $($dism.Source)" "PASS"
    } else {
        Write-Result "DISM not found - required for image servicing" "FAIL"
    }
    
    # Check for .NET 3.5 (needed for some legacy components)
    $netFx3 = Get-WindowsOptionalFeature -Online -FeatureName "NetFx3" -ErrorAction SilentlyContinue
    if ($netFx3 -and $netFx3.State -eq "Enabled") {
        Write-Result ".NET Framework 3.5 is enabled" "PASS"
    } else {
        Write-Result ".NET Framework 3.5 not enabled (may be needed for some operations)" "WARN"
    }
}

function Test-ADKTools {
    Write-Result "Checking Windows ADK tools..." "INFO"
    
    # Check oscdimg (for ISO creation)
    $oscdimg = Get-Command oscdimg -ErrorAction SilentlyContinue
    if ($oscdimg) {
        Write-Result "oscdimg available at: $($oscdimg.Source)" "PASS"
    } else {
        # Check common ADK installation paths
        $adkPaths = @(
            "${env:ProgramFiles(x86)}\Windows Kits\10\Assessment and Deployment Kit\Deployment Tools\amd64\Oscdimg\oscdimg.exe",
            "${env:ProgramFiles(x86)}\Windows Kits\10\bin\10.0.22621.0\x64\oscdimg.exe",
            "${env:ProgramFiles(x86)}\Windows Kits\10\bin\10.0.22000.0\x64\oscdimg.exe"
        )
        
        $found = $false
        foreach ($path in $adkPaths) {
            if (Test-Path $path) {
                Write-Result "oscdimg found at: $path (add to PATH)" "WARN"
                $found = $true
                break
            }
        }
        
        if (-not $found) {
            Write-Result "oscdimg not found - required for ISO creation. Install Windows ADK." "FAIL"
        }
    }
    
    # Check bcdboot (usually available)
    $bcdboot = Get-Command bcdboot -ErrorAction SilentlyContinue
    if ($bcdboot) {
        Write-Result "bcdboot available" "PASS"
    } else {
        Write-Result "bcdboot not found - required for boot configuration" "FAIL"
    }
}

function Test-DiskSpace {
    if ($SkipDiskCheck) {
        Write-Result "Skipping disk space check (--SkipDiskCheck specified)" "INFO"
        return
    }
    
    Write-Result "Checking available disk space..." "INFO"
    
    # Check C: drive (working directory)
    $cDrive = Get-CimInstance -ClassName Win32_LogicalDisk -Filter "DeviceID='C:'" -ErrorAction SilentlyContinue
    if ($cDrive) {
        $freeGB = [math]::Round($cDrive.FreeSpace / 1GB, 2)
        $totalGB = [math]::Round($cDrive.Size / 1GB, 2)
        
        if ($freeGB -gt 50) {
            Write-Result "C: drive has ${freeGB}GB free of ${totalGB}GB (sufficient for build operations)" "PASS"
        } elseif ($freeGB -gt 20) {
            Write-Result "C: drive has ${freeGB}GB free of ${totalGB}GB (tight but may work)" "WARN"
        } else {
            Write-Result "C: drive has only ${freeGB}GB free - need at least 20GB for build operations" "FAIL"
        }
    } else {
        Write-Result "Could not query C: drive information" "WARN"
    }
}

function Test-NetworkConnectivity {
    if ($SkipNetworkCheck) {
        Write-Result "Skipping network connectivity check (--SkipNetworkCheck specified)" "INFO"
        return
    }
    
    Write-Result "Checking network connectivity..." "INFO"
    
    # Test basic connectivity
    $hasNetwork = Test-Connection -ComputerName "8.8.8.8" -Count 1 -Quiet -ErrorAction SilentlyContinue
    if ($hasNetwork) {
        Write-Result "Internet connectivity available" "PASS"
        
        # Test DNS resolution
        try {
            Resolve-DnsName -Name "microsoft.com" -ErrorAction Stop | Out-Null
            Write-Result "DNS resolution working" "PASS"
        } catch {
            Write-Result "DNS resolution failed - winget package installation may fail" "WARN"
        }
    } else {
        Write-Result "No internet connectivity - winget package installation will fail" "WARN"
    }
}

function Test-GoldISOPaths {
    Write-Result "Checking GoldISO paths..." "INFO"
    
    $goldISORoot = if (Get-Command Get-GoldISORoot -ErrorAction SilentlyContinue) { Get-GoldISORoot } else { Split-Path $PSScriptRoot -Parent }
    
    # Check root directory
    if (Test-Path $goldISORoot) {
        Write-Result "GoldISO root found: $goldISORoot" "PASS"
    } else {
        Write-Result "GoldISO root not found: $goldISORoot" "FAIL"
        return
    }
    
    # Check critical files
    $criticalFiles = @(
        @{ Path = "$goldISORoot\autounattend.xml"; Name = "Unattended answer file" }
        @{ Path = "$goldISORoot\Win11_25H2_English_x64_v2.iso"; Name = "Source ISO" }
    )
    
    foreach ($file in $criticalFiles) {
        if (Test-Path $file.Path) {
            Write-Result "$($file.Name) found" "PASS"
        } else {
            Write-Result "$($file.Name) not found: $($file.Path)" "WARN"
        }
    }
    
    # Check directories
    $directories = @(
        @{ Path = "$goldISORoot\Scripts"; Name = "Scripts directory" }
        @{ Path = "$goldISORoot\Config"; Name = "Config directory" }
        @{ Path = "$goldISORoot\Drivers"; Name = "Drivers directory" }
    )
    
    foreach ($dir in $directories) {
        if (Test-Path $dir.Path) {
            Write-Result "$($dir.Name) found" "PASS"
        } else {
            Write-Result "$($dir.Name) not found: $($dir.Path)" "WARN"
        }
    }
}

function Test-PowerShellVersion {
    Write-Result "Checking PowerShell version..." "INFO"
    
    $version = $PSVersionTable.PSVersion
    if ($version.Major -ge 7) {
        Write-Result "PowerShell $($version.ToString()) - Excellent (PowerShell 7+)" "PASS"
    } elseif ($version.Major -eq 5 -and $version.Minor -ge 1) {
        Write-Result "PowerShell $($version.ToString()) - Supported (Windows PowerShell 5.1)" "PASS"
    } else {
        Write-Result "PowerShell $($version.ToString()) - Upgrade to 5.1 or 7.x recommended" "WARN"
    }
}

# ==========================================
# MAIN EXECUTION
# ==========================================

Write-Host ""
Write-Host "==========================================" -ForegroundColor Cyan
Write-Host "  GoldISO Environment Validation" -ForegroundColor Cyan
Write-Host "==========================================" -ForegroundColor Cyan
Write-Host ""

# Run all tests
Test-PowerShellVersion
Test-ExecutionPolicy
Test-AdminRights
Test-RequiredFeatures
Test-ADKTools
Test-DiskSpace
Test-NetworkConnectivity
Test-GoldISOPaths

# Summary
Write-Host ""
Write-Host "==========================================" -ForegroundColor Cyan
Write-Host "  VALIDATION SUMMARY" -ForegroundColor Cyan
Write-Host "==========================================" -ForegroundColor Cyan
Write-Host "Passed:   $($script:Passed.Count)" -ForegroundColor Green
Write-Host "Warnings: $($script:Warnings.Count)" -ForegroundColor Yellow
Write-Host "Errors:   $($script:Errors.Count)" -ForegroundColor Red
Write-Host "==========================================" -ForegroundColor Cyan

if ($script:Errors.Count -gt 0) {
    Write-Host ""
    Write-Host "FAILED - Fix errors before proceeding:" -ForegroundColor Red
    foreach ($errorMsg in $script:Errors) {
        Write-Host "  [X] $errorMsg" -ForegroundColor Red
    }
    exit 1
} elseif ($script:Warnings.Count -gt 0) {
    Write-Host ""
    Write-Host "PASSED WITH WARNINGS:" -ForegroundColor Yellow
    foreach ($warnMsg in $script:Warnings) {
        Write-Host "  [!] $warnMsg" -ForegroundColor Yellow
    }
    exit 0
} else {
    Write-Host ""
    Write-Host "PASSED - Environment ready for GoldISO operations" -ForegroundColor Green
    exit 0
}
