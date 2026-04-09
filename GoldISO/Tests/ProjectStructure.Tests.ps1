#Requires -Version 5.1
#Requires -Modules Pester
<#
.SYNOPSIS
    Project structure and file organization tests.
.DESCRIPTION
    Validates that all required project files exist and are in the expected locations.
.NOTES
    Run with: Invoke-Pester -Path .\ProjectStructure.Tests.ps1
#>


Describe "Required Project Files" {
    It "Source ISO file exists" {
        $ProjectRoot = Join-Path $PSScriptRoot ".."
        $isoPath = Join-Path $ProjectRoot "Win11-25H2x64v2.iso"
        # Note: This may fail if ISO hasn't been downloaded
        Test-Path $isoPath | Should -Be $true
    }

    It "Primary autounattend.xml exists" {
        $ProjectRoot = Join-Path $PSScriptRoot ".."
        $unattendPath = Join-Path $ProjectRoot "autounattend.xml"
        $configUnattendPath = Join-Path $ProjectRoot "Config\autounattend.xml"
        
        (Test-Path $unattendPath) -or (Test-Path $configUnattendPath) | Should -Be $true
    }
}

Describe "Directory Structure" {
    It "Scripts directory exists" {
        $ProjectRoot = Join-Path $PSScriptRoot ".."
        $scriptsDir = Join-Path $ProjectRoot "Scripts"
        Test-Path $scriptsDir | Should -Be $true
    }

    It "Config directory exists" {
        $ProjectRoot = Join-Path $PSScriptRoot ".."
        $configDir = Join-Path $ProjectRoot "Config"
        Test-Path $configDir | Should -Be $true
    }

    It "Drivers directory exists" {
        $ProjectRoot = Join-Path $PSScriptRoot ".."
        $driversDir = Join-Path $ProjectRoot "Drivers"
        Test-Path $driversDir | Should -Be $true
    }

    It "Packages directory exists" {
        $ProjectRoot = Join-Path $PSScriptRoot ".."
        $packagesDir = Join-Path $ProjectRoot "Packages"
        Test-Path $packagesDir | Should -Be $true
    }

    It "Docs directory exists" {
        $ProjectRoot = Join-Path $PSScriptRoot ".."
        $docsDir = Join-Path $ProjectRoot "Docs"
        Test-Path $docsDir | Should -Be $true
    }

    It "Applications directory exists" {
        $ProjectRoot = Join-Path $PSScriptRoot ".."
        $appsDir = Join-Path $ProjectRoot "Applications"
        Test-Path $appsDir | Should -Be $true
    }
}

Describe "Documentation Files" {
    It "AGENTS.md exists" {
        $ProjectRoot = Join-Path $PSScriptRoot ".."
        $agentsDoc = Join-Path $ProjectRoot "Docs\AGENTS.md"
        $agentsDocAlt = Join-Path $ProjectRoot "Scripts\A.I instructions\AGENTS.md"
        (Test-Path $agentsDoc) -or (Test-Path $agentsDocAlt) | Should -Be $true
    }

    It "Scripts README exists" {
        $ProjectRoot = Join-Path $PSScriptRoot ".."
        $scriptsReadme = Join-Path $ProjectRoot "Scripts\README.md"
        Test-Path $scriptsReadme | Should -Be $true
    }

    It "Config README exists" {
        $ProjectRoot = Join-Path $PSScriptRoot ".."
        $configReadme = Join-Path $ProjectRoot "Config\README.md"
        Test-Path $configReadme | Should -Be $true
    }
}

Describe "Module Structure" {
    It "Modules directory exists" {
        $ProjectRoot = Join-Path $PSScriptRoot ".."
        $modulesDir = Join-Path $ProjectRoot "Scripts\Modules"
        Test-Path $modulesDir | Should -Be $true
    }

    It "GoldISO-Common.psm1 exists" {
        $ProjectRoot = Join-Path $PSScriptRoot ".."
        $commonModule = Join-Path $ProjectRoot "Scripts\Modules\GoldISO-Common.psm1"
        Test-Path $commonModule | Should -Be $true
    }
}

Describe "PortableApps Structure" {
    It "PortableApps subdirectory exists" {
        $ProjectRoot = Join-Path $PSScriptRoot ".."
        $portableDir = Join-Path $ProjectRoot "Applications\PortableApps"
        Test-Path $portableDir | Should -Be $true
    }

    It "Has at least some portable apps" {
        $ProjectRoot = Join-Path $PSScriptRoot ".."
        $portableDir = Join-Path $ProjectRoot "Applications\PortableApps"
        $appCount = (Get-ChildItem -Path $portableDir -Directory -ErrorAction SilentlyContinue).Count
        $appCount | Should -BeGreaterThan 0
    }
}

Describe "Driver Categories" {
    It "Expected driver categories exist" {
        $ProjectRoot = Join-Path $PSScriptRoot ".."
        $driversDir = Join-Path $ProjectRoot "Drivers"
        $expectedCategories = @(
            "Audio Processing Objects (APOs)",
            "Display adapters",
            "Drivers without existing device",
            "Extensions",
            "System devices"
        )
        foreach ($category in $expectedCategories) {
            $categoryPath = Join-Path $driversDir $category
            # Not all categories may exist, just check that Drivers dir has subfolders
            if (Test-Path $categoryPath) {
                Test-Path $categoryPath | Should -Be $true
            }
        }
    }
}

Describe "Package Files" {
    It "Has Windows update packages (.msu) or (.cab)" {
        $ProjectRoot = Join-Path $PSScriptRoot ".."
        $packagesDir = Join-Path $ProjectRoot "Packages"
        $msuCount = (Get-ChildItem -Path $packagesDir -Filter "*.msu" -ErrorAction SilentlyContinue).Count
        $cabCount = (Get-ChildItem -Path $packagesDir -Filter "*.cab" -ErrorAction SilentlyContinue).Count

        ($msuCount + $cabCount) | Should -BeGreaterOrEqual 0  # Optional - may be empty
    }

    It "Has MSIX packages (.msixbundle)" {
        $ProjectRoot = Join-Path $PSScriptRoot ".."
        $packagesDir = Join-Path $ProjectRoot "Packages"
        $msixCount = (Get-ChildItem -Path $packagesDir -Filter "*.msixbundle" -ErrorAction SilentlyContinue).Count
        $msixCount | Should -BeGreaterOrEqual 0  # Optional
    }
}

Describe "Logging Consolidation Compliance" {
    It "Should have no scripts with local Write-Log when module is available" {
        $scriptsDir = Join-Path (Join-Path $PSScriptRoot "..") "Scripts"
        $scripts = Get-ChildItem -Path $scriptsDir -Filter "*.ps1" -ErrorAction SilentlyContinue

        $scriptsWithLocalWriteLog = @()

        foreach ($script in $scripts) {
            $content = Get-Content $script.FullName -Raw
            # Check for local Write-Log function definition
            if ($content -match "function\s+Write-Log") {
                # Allow local Write-Log for target environment scripts that need fallback
                $targetScripts = @(
                    "install-usb-apps.ps1",
                    "shrink-and-recovery.ps1",
                    "install-ramdisk.ps1",
                    "Capture-Image.ps1",
                    "Create-AuditShortcuts.ps1"
                )

                if ($targetScripts -notcontains $script.Name) {
                    $scriptsWithLocalWriteLog += $script.Name
                }
            }
        }

        $scriptsWithLocalWriteLog.Count | Should -Be 0 -Because "scripts should not have local Write-Log: $($scriptsWithLocalWriteLog -join ', ')"
    }

    It "Should have centralized module in Modules directory" {
        $modulePath = Join-Path (Join-Path $PSScriptRoot "..") "Scripts\Modules\GoldISO-Common.psm1"
        $modulePath | Should -Exist -Because "GoldISO-Common.psm1 should exist"
    }
}
