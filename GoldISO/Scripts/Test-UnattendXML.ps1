#Requires -Version 5.1
<#
.SYNOPSIS
    Validate autounattend.xml structure and references
.DESCRIPTION
    Performs comprehensive validation of the unattended answer file:
    - XML well-formedness
    - Required components exist
    - RunSynchronous command ordering
    - Disk configuration validity
    - File reference existence (Drivers, Packages, Scripts)
    - Schema compliance checks
.PARAMETER AnswerFile
    Path to the autounattend.xml file to validate
.PARAMETER Verbose
    Enable verbose output
.PARAMETER Strict
    Treat warnings as errors
.EXAMPLE
    .\Test-UnattendXML.ps1
.EXAMPLE
    .\Test-UnattendXML.ps1 -Verbose
.EXAMPLE
    .\Test-UnattendXML.ps1 -AnswerFile "D:\Custom\autounattend.xml" -Strict
#>
[CmdletBinding()]
param(
    [Parameter()]
    [ValidateScript({ Test-Path $_ -PathType Leaf })]
    [string]$AnswerFile = (Join-Path $PSScriptRoot "..\Config\autounattend.xml"),
    
    [switch]$Strict,

    [switch]$PassThru
)

# Import common module
$commonModule = Join-Path $PSScriptRoot "Modules\GoldISO-Common.psm1"
if (Test-Path $commonModule) {
    Import-Module $commonModule -Force -ErrorAction SilentlyContinue
}

$ErrorActionPreference = "Stop"
$script:Errors = [System.Collections.Generic.List[string]]::new()
$script:Warnings = [System.Collections.Generic.List[string]]::new()
$script:Passed = [System.Collections.Generic.List[string]]::new()
$script:xml = $null

# Initialize logging
$logPath = Join-Path $PSScriptRoot "Logs\Test-UnattendXML-$(Get-Date -Format 'yyyyMMdd-HHmmss').log"
if (Get-Command Initialize-Logging -ErrorAction SilentlyContinue) {
    Initialize-Logging -LogPath $logPath
}

function Write-Test {
    param([string]$Message, [string]$Level = "PASS", [switch]$NoConsole)
    if (-not $NoConsole) {
        switch ($Level) {
            "FAIL" { Write-Host "[FAIL] $Message" -ForegroundColor Red }
            "WARN" { Write-Host "[WARN] $Message" -ForegroundColor Yellow }
            "PASS" { Write-Host "[PASS] $Message" -ForegroundColor Green }
            default { Write-Host "[INFO] $Message" }
        }
    }
    switch ($Level) {
        "FAIL" { $script:Errors += $Message }
        "WARN" { $script:Warnings += $Message }
        "PASS" { $script:Passed += $Message }
    }
}

function Test-XMLParse {
    Write-Test "Testing XML parse..."
    
    if (-not (Test-Path $AnswerFile)) {
        Write-Test "Answer file not found: $AnswerFile" "FAIL"
        return $false
    }
    
    try {
        [xml]$script:xml = Get-Content $AnswerFile -Raw
        Write-Test "XML is well-formed" "PASS"
        return $true
    } catch {
        Write-Test "XML parse error: $_" "FAIL"
        return $false
    }
}

function Test-Components {
    Write-Test "Testing required components..."
    
    if (-not $script:xml) {
        Write-Test "XML not loaded - skipping component tests" "FAIL"
        return
    }
    
    $requiredComponents = @(
        @{ Name = "Microsoft-Windows-International-Core"; Pass = "windowsPE" },
        @{ Name = "Microsoft-Windows-Setup"; Pass = "windowsPE" },
        @{ Name = "Microsoft-Windows-Shell-Setup"; Pass = @("oobeSystem", "specialize") }
    )
    
    foreach ($comp in $requiredComponents) {
        $found = $script:xml.unattend.settings.component | Where-Object { $_.Name -eq $comp.Name }
        if ($found) {
            Write-Test "Component found: $($comp.Name)" "PASS"
        } else {
            Write-Test "Required component missing: $($comp.Name)" "FAIL"
        }
    }
    
    # Check for audit mode support
    $auditSettings = $script:xml.unattend.settings | Where-Object { $_.Pass -match "audit" }
    if ($auditSettings) {
        Write-Test "Audit mode sections found" "PASS"
    }
}

function Test-RunSynchronous {
    Write-Test "Testing RunSynchronous commands..."
    
    $allPasses = @('windowsPE', 'specialize')
    $hasIssues = $false
    
    foreach ($pass in $allPasses) {
        $passSync = $script:xml.unattend.settings | Where-Object { $_.Pass -eq $pass }
        
        if ($passSync -and $passSync.Component.RunSynchronous) {
            $commands = $passSync.Component.RunSynchronous.RunSynchronousCommand
            
            if ($commands) {
                Write-Test "Found $($commands.Count) RunSynchronous command(s) in $pass" "PASS"
                
                $orders = $commands | ForEach-Object { [int]$_.Order } | Sort-Object
                $uniqueOrders = $orders | Sort-Object -Unique
                
                if ($orders.Count -ne $uniqueOrders.Count) {
                    $dupes = $orders | Group-Object | Where-Object { $_.Count -gt 1 }
                    $dupesList = ($dupes.Name -join ', ')
                    Write-Test "Duplicate RunSynchronous orders in $pass`: $dupesList" "FAIL"
                    $hasIssues = $true
                }
            }
        }
    }
    
    if (-not $hasIssues) {
        Write-Test "All RunSynchronous orders are unique within each pass" "PASS"
    }
}

function Test-FirstLogonCommands {
    Write-Test "Testing FirstLogonCommands..."
    
    $oobe = $script:xml.unattend.settings | Where-Object { $_.Pass -eq "oobeSystem" }
    $commands = $oobe.Component.FirstLogonCommands.SynchronousCommand
    
    if ($commands) {
        Write-Test "Found $($commands.Count) FirstLogon command(s)" "PASS"
        
        $orders = $commands | ForEach-Object { [int]$_.Order } | Sort-Object
        $expectedOrders = 1..$commands.Count
        
        if (($orders -join ",") -eq ($expectedOrders -join ",")) {
            Write-Test "FirstLogon orders are sequential" "PASS"
        } else {
            Write-Test "FirstLogon orders not sequential: $orders (expected $expectedOrders)" "WARN"
        }
    }
}

function Test-FileReferences {
    Write-Test "Testing file references..."
    
    $goldISODir = Split-Path $PSScriptRoot -Parent
    
    # Drivers
    $driversDir = Join-Path $goldISODir "Drivers"
    if (Test-Path $driversDir) {
        $infCount = (Get-ChildItem $driversDir -Recurse -File -Filter "*.inf" | Measure-Object).Count
        Write-Test "Drivers: $infCount .inf files found" "PASS"
    } else {
        Write-Test "Drivers directory not found: $driversDir" "FAIL"
    }
    
    # Packages
    $packagesDir = Join-Path $goldISODir "Packages"
    if (Test-Path $packagesDir) {
        $pkgCount = (Get-ChildItem $packagesDir -File | Measure-Object).Count
        Write-Test "Packages: $pkgCount files found" "PASS"
    } else {
        Write-Test "Packages directory not found: $packagesDir" "WARN"
    }
    
    # Portable Apps
    $portableDir = Join-Path $goldISODir "Applications\Portableapps"
    if (Test-Path $portableDir) {
        $appCount = (Get-ChildItem $portableDir -Directory | Measure-Object).Count
        Write-Test "Portable Apps: $appCount app folders found" "PASS"
    } else {
        Write-Test "Portable Apps directory not found: $portableDir" "WARN"
    }
    
    # PowerShell Profile
    $profileDir = Join-Path $goldISODir "Config\PowerShellProfile"
    if (Test-Path $profileDir) {
        $profileFiles = (Get-ChildItem $profileDir -Recurse -File | Measure-Object).Count
        Write-Test "PowerShell Profile: $profileFiles files found" "PASS"
    } else {
        Write-Test "PowerShell Profile directory not found: $profileDir" "WARN"
    }

    # Verify FirstLogonCommand script references
    Write-Test "Verifying FirstLogonCommand script existence..."
    $oobe = $script:xml.unattend.settings | Where-Object { $_.Pass -eq "oobeSystem" }
    $commands = $oobe.Component.FirstLogonCommands.SynchronousCommand
    foreach ($cmd in $commands) {
        $cmdLine = $cmd.CommandLine
        if ($cmdLine -match "C:\\Scripts\\(?<script>[a-zA-Z0-9\-_]+\.ps1)") {
            $scriptName = $Matches['script']
            $localPath = Join-Path $goldISODir "Scripts\$scriptName"
            if (Test-Path $localPath) {
                Write-Test "  FirstLogon script found: $scriptName" "PASS" "NoConsole"
            } else {
                Write-Test "  FirstLogon script MISSING in repo: $scriptName" "FAIL"
            }
        }
    }
}

function Test-SchemaLogic {
    Write-Test "Testing schema logic..."
    
    # Check for Win11 bypasses (should NOT exist now)
    $specialize = $script:xml.unattend.settings | Where-Object { $_.Pass -eq "specialize" }
    if ($specialize -and $specialize.Component.RunSynchronous) {
        $bypassCommands = $specialize.Component.RunSynchronous.RunSynchronousCommand | Where-Object { 
            $_.Path -match "Bypass(TPM|SecureBoot|Storage|CPU|RAM|Disk)Check" 
        }
        if ($bypassCommands) {
            Write-Test "Found Win11 bypass commands (should be removed): $($bypassCommands.Count)" "FAIL"
        } else {
            Write-Test "No Win11 bypass commands (correct)" "PASS"
        }
    }
    
    # Collect all commands
    $allCommands = @()
    foreach ($setting in $script:xml.unattend.settings) {
        if ($setting.Component.RunSynchronous) {
            $allCommands += $setting.Component.RunSynchronous.RunSynchronousCommand
        }
        if ($setting.Component.FirstLogonCommands) {
            $allCommands += $setting.Component.FirstLogonCommands.SynchronousCommand
        }
    }
    
    # Check for shrink-and-recovery script reference
    $shrinkScript = $allCommands | Where-Object { $_.Path -match "shrink-and-recovery" }
    if ($shrinkScript) {
        Write-Test "Found shrink-and-recovery script reference" "PASS"
    } else {
        Write-Test "shrink-and-recovery script reference not found (may need to be added)" "WARN"
    }
    
    # Check for portable apps copy
    $portableCopy = $allCommands | Where-Object { $_.CommandLine -match "PortableApps" -or $_.Path -match "PortableApps" }
    if ($portableCopy) {
        Write-Test "Found portable apps copy command" "PASS"
    } else {
        Write-Test "Portable apps copy command not found (may need to be added)" "WARN"
    }
    
    # Check for PowerShell profile deployment
    $profileDeploy = $allCommands | Where-Object { $_.Path -match "PowerShellProfile|PowerShell.*profile" }
    if ($profileDeploy) {
        Write-Test "Found PowerShell profile deployment command" "PASS"
    } else {
        Write-Test "PowerShell profile deployment command not found (may need to be added)" "WARN"
    }
    
    # Check for network disable during OOBE
    $oobePass = $script:xml.unattend.settings | Where-Object { $_.Pass -eq "oobeSystem" }
    $shellSetup = $oobePass.Component | Where-Object { $_.Name -match "Shell-Setup" }
    
    $hasNetworkDisable = ($shellSetup.OOBE.DisableInternetConnection -eq "true") -or ($shellSetup.OfflineUserMachine -eq "true")
    
    if ($hasNetworkDisable) {
        Write-Test "Found OOBE network disable configuration" "PASS"
    } else {
        Write-Test "OOBE network disable configuration not found (local account creation may fail)" "WARN"
    }
}

function Test-ScriptReferences {
    Write-Test "Testing embedded script references..."
    
    # Find all <Extensions> sections with embedded scripts
    $extensions = $script:xml.unattend.Extensions
    if ($extensions) {
        Write-Test "Found Extensions section" "PASS"
        
        # Check for common embedded scripts
        $embeddedScripts = @(
            @{ Name = "shrink-and-recovery"; Pattern = "shrink.*recovery|resize.*partition" },
            @{ Name = "install-usb-apps"; Pattern = "install.*usb.*apps|winget.*install" },
            @{ Name = "configure-drives"; Pattern = "configure.*drive|partition.*disk" }
        )
        
        $extensionsText = $extensions.OuterXml
        foreach ($scriptRef in $embeddedScripts) {
            if ($extensionsText -match $scriptRef.Pattern) {
                Write-Test "Found embedded script reference: $($scriptRef.Name)" "PASS"
            } else {
                Write-Test "Embedded script not found: $($scriptRef.Name)" "WARN"
            }
        }
    } else {
        Write-Test "No Extensions section found (embedded scripts missing)" "WARN"
    }
}

function Test-DiskConfiguration {
    Write-Test "Testing disk configuration..."
    
    $diskConfig = $script:xml.unattend.settings.component | Where-Object { $_.Name -eq "Microsoft-Windows-Setup" }
    $disks = $diskConfig.DiskConfiguration.Disk
    
    if ($disks) {
        Write-Test "Found $($disks.Count) disk configuration(s)" "PASS"
        
        # Check for critical disk IDs
        $diskIds = $disks | ForEach-Object { $_.DiskID }
        
        # Disk 2 should be configured (Windows installation)
        if (2 -in $diskIds) {
            Write-Test "Disk 2 (Windows) is configured" "PASS"
        } else {
            Write-Test "Disk 2 (Windows) is not configured - this is the primary Windows disk!" "FAIL"
        }
        
        # Disk 0 and 1 should have WillWipeDisk
        foreach ($disk in $disks) {
            $diskId = $disk.DiskID
            $willWipe = $disk.WillWipeDisk
            $createParts = if ($disk.CreatePartitions.CreatePartition) { $disk.CreatePartitions.CreatePartition } else { @() }
            $modifyParts = if ($disk.ModifyPartitions.ModifyPartition) { $disk.ModifyPartitions.ModifyPartition } else { @() }
            
            Write-Test "  Disk $diskId`: WillWipe=$willWipe, CreateParts=$($createParts.Count), ModifyParts=$($modifyParts.Count)" "INFO"
            
            # Validate partition orders
            if ($createParts.Count -gt 0) {
                $orders = $createParts | ForEach-Object { [int]$_.Order } | Sort-Object
                $expectedOrders = 1..$createParts.Count
                
                if (($orders -join ",") -eq ($expectedOrders -join ",")) {
                    Write-Test "    Disk $diskId partition orders valid: $($orders -join ',')" "PASS"
                } else {
                    Write-Test "    Disk $diskId partition orders invalid: got $($orders -join ','), expected $($expectedOrders -join ',')" "FAIL"
                }
            }
            
            # Warn if disk 0 or 1 has partitions defined (should be wiped only)
            if ($diskId -in @(0, 1) -and $createParts.Count -gt 0) {
                Write-Test "    Disk $diskId has partitions defined - should only be wiped per GamerOS design" "WARN"
            }
        }
    } else {
        Write-Test "No disk configuration found" "FAIL"
    }
}

# ==========================================
# MAIN EXECUTION
# ==========================================

Write-Host "=========================================="
Write-Host "autounattend.xml Validation"
Write-Host "=========================================="
Write-Host ""

# Parse XML
if (-not (Test-XMLParse)) {
    Write-Host ""
    Write-Host "=========================================="
    Write-Host "VALIDATION FAILED - XML not parseable" -ForegroundColor Red
    Write-Host "=========================================="
    exit 1
}

# Run tests
Test-Components
Test-DiskConfiguration
Test-RunSynchronous
Test-FirstLogonCommands
Test-FileReferences
Test-SchemaLogic
Test-ScriptReferences

# Summary
Write-Host ""
Write-Host "=========================================="
Write-Host "VALIDATION SUMMARY"
Write-Host "=========================================="
Write-Host "Passed:   $($script:Passed.Count)" -ForegroundColor Green
Write-Host "Warnings: $($script:Warnings.Count)" -ForegroundColor Yellow
Write-Host "Errors:   $($script:Errors.Count)" -ForegroundColor Red
Write-Host "=========================================="

# Detailed error report
if ($script:Errors.Count -gt 0) {
    Write-Host ""
    Write-Host "ERRORS:" -ForegroundColor Red
    foreach ($errorMsg in $script:Errors) {
        Write-Host "  [X] $errorMsg" -ForegroundColor Red
    }
}

if ($script:Warnings.Count -gt 0) {
    Write-Host ""
    Write-Host "WARNINGS:" -ForegroundColor Yellow
    foreach ($warnMsg in $script:Warnings | Select-Object -First 10) {
        Write-Host "  [!] $warnMsg" -ForegroundColor Yellow
    }
    if ($script:Warnings.Count -gt 10) {
        Write-Host "  ... and $($script:Warnings.Count - 10) more warnings" -ForegroundColor Yellow
    }
}

Write-Host ""
if ($script:Errors.Count -gt 0) {
    Write-Host "FAILED - Fix errors before building" -ForegroundColor Red
    if (Get-Command Write-GoldISOLog -ErrorAction SilentlyContinue) {
        Write-GoldISOLog -Message "Validation FAILED with $($script:Errors.Count) error(s)" -Level "ERROR"
    }
    if ($PassThru) {
        $result = @{
            Status   = "Failed"
            Passed  = $script:Passed.Count
            Warnings = $script:Warnings.Count
            Errors  = $script:Errors.Count
        }
        return $result
    }
    exit 1
} elseif ($script:Warnings.Count -gt 0 -and $Strict) {
    Write-Host "FAILED (Strict mode) - Warnings treated as errors" -ForegroundColor Red
    if (Get-Command Write-GoldISOLog -ErrorAction SilentlyContinue) {
        Write-GoldISOLog -Message "Validation FAILED (strict mode) with $($script:Warnings.Count) warning(s)" -Level "ERROR"
    }
    if ($PassThru) {
        $result = @{
            Status   = "Failed"
            Passed  = $script:Passed.Count
            Warnings = $script:Warnings.Count
            Errors  = $script:Errors.Count
        }
        return $result
    }
    exit 1
} elseif ($script:Warnings.Count -gt 0) {
    Write-Host "PASSED WITH WARNINGS - Review before building" -ForegroundColor Yellow
    if (Get-Command Write-GoldISOLog -ErrorAction SilentlyContinue) {
        Write-GoldISOLog -Message "Validation passed with $($script:Warnings.Count) warning(s)" -Level "WARN"
    }
    if ($PassThru) {
        $result = @{
            Status   = "Warning"
            Passed  = $script:Passed.Count
            Warnings = $script:Warnings.Count
            Errors  = $script:Errors.Count
        }
        return $result
    }
    exit 0
} else {
    Write-Host "PASSED - Ready to build" -ForegroundColor Green
    if (Get-Command Write-GoldISOLog -ErrorAction SilentlyContinue) {
        Write-GoldISOLog -Message "Validation passed with 0 warnings/errors" -Level "SUCCESS"
    }
    if ($PassThru) {
        $result = @{
            Status   = if ($script:Errors.Count -gt 0) { "Failed" } elseif ($script:Warnings.Count -gt 0) { "Warning" } else { "Passed" }
            Passed  = $script:Passed.Count
            Warnings = $script:Warnings.Count
            Errors  = $script:Errors.Count
        }
        return $result
    }
    exit 0
}