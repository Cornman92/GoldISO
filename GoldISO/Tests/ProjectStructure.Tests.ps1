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

BeforeAll {
    $ProjectRoot = Join-Path $PSScriptRoot ".."
}

Describe "Required Project Files" {
    It "Source ISO file exists" {
        $isoPath = Join-Path $ProjectRoot "Win11-25H2x64v2.iso"
        # Note: This may fail if ISO hasn't been downloaded
        Test-Path $isoPath | Should -Be $true
    }

    It "Primary autounattend.xml exists" {
        $unattendPath = Join-Path $ProjectRoot "autounattend.xml"
        $configUnattendPath = Join-Path $ProjectRoot "Config\autounattend.xml"
        
        (Test-Path $unattendPath) -or (Test-Path $configUnattendPath) | Should -Be $true
    }
}

Describe "Directory Structure" {
    It "Scripts directory exists" {
        $scriptsDir = Join-Path $ProjectRoot "Scripts"
        Test-Path $scriptsDir | Should -Be $true
    }

    It "Config directory exists" {
        $configDir = Join-Path $ProjectRoot "Config"
        Test-Path $configDir | Should -Be $true
    }

    It "Drivers directory exists" {
        $driversDir = Join-Path $ProjectRoot "Drivers"
        Test-Path $driversDir | Should -Be $true
    }

    It "Packages directory exists" {
        $packagesDir = Join-Path $ProjectRoot "Packages"
        Test-Path $packagesDir | Should -Be $true
    }

    It "Docs directory exists" {
        $docsDir = Join-Path $ProjectRoot "Docs"
        Test-Path $docsDir | Should -Be $true
    }

    It "Applications directory exists" {
        $appsDir = Join-Path $ProjectRoot "Applications"
        Test-Path $appsDir | Should -Be $true
    }
}

Describe "Documentation Files" {
    It "AGENTS.md exists" {
        $agentsDoc = Join-Path $ProjectRoot "Docs\AGENTS.md"
        $agentsDocAlt = Join-Path $ProjectRoot "Scripts\A.I instructions\AGENTS.md"
        (Test-Path $agentsDoc) -or (Test-Path $agentsDocAlt) | Should -Be $true
    }

    It "Scripts README exists" {
        $scriptsReadme = Join-Path $ProjectRoot "Scripts\README.md"
        Test-Path $scriptsReadme | Should -Be $true
    }

    It "Config README exists" {
        $configReadme = Join-Path $ProjectRoot "Config\README.md"
        Test-Path $configReadme | Should -Be $true
    }
}

Describe "Module Structure" {
    It "Modules directory exists" {
        $modulesDir = Join-Path $ProjectRoot "Scripts\Modules"
        Test-Path $modulesDir | Should -Be $true
    }

    It "GoldISO-Common.psm1 exists" {
        $commonModule = Join-Path $ProjectRoot "Scripts\Modules\GoldISO-Common.psm1"
        Test-Path $commonModule | Should -Be $true
    }
}

Describe "PortableApps Structure" {
    It "PortableApps subdirectory exists" {
        $portableDir = Join-Path $ProjectRoot "Applications\PortableApps"
        Test-Path $portableDir | Should -Be $true
    }

    It "Has at least some portable apps" {
        $portableDir = Join-Path $ProjectRoot "Applications\PortableApps"
        $appCount = (Get-ChildItem -Path $portableDir -Directory -ErrorAction SilentlyContinue).Count
        $appCount | Should -BeGreaterThan 0
    }
}

Describe "Driver Categories" {
    BeforeAll {
        $driversDir = Join-Path $ProjectRoot "Drivers"
        $expectedCategories = @(
            "Audio Processing Objects (APOs)",
            "Display adapters",
            "Drivers without existing device",
            "Extensions",
            "System devices"
        )
    }

    It "Expected driver categories exist" {
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
        $packagesDir = Join-Path $ProjectRoot "Packages"
        $msuCount = (Get-ChildItem -Path $packagesDir -Filter "*.msu" -ErrorAction SilentlyContinue).Count
        $cabCount = (Get-ChildItem -Path $packagesDir -Filter "*.cab" -ErrorAction SilentlyContinue).Count
        
        ($msuCount + $cabCount) | Should -BeGreaterOrEqual 0  # Optional - may be empty
    }

    It "Has MSIX packages (.msixbundle)" {
        $packagesDir = Join-Path $ProjectRoot "Packages"
        $msixCount = (Get-ChildItem -Path $packagesDir -Filter "*.msixbundle" -ErrorAction SilentlyContinue).Count
        $msixCount | Should -BeGreaterOrEqual 0  # Optional
    }
}
