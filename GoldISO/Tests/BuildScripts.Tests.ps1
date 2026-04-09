#Requires -Version 5.1
<#
.SYNOPSIS
    Tests for GoldISO build scripts.
.DESCRIPTION
    Tests parameter validation, prerequisite checks, and error handling paths
    for the main build scripts.
#>

BeforeAll {
    $modulePath = Join-Path $PSScriptRoot "..\Scripts\Modules\GoldISO-Common.psm1"
    Import-Module $modulePath -Force

    $script:ProjectRoot = Split-Path $PSScriptRoot -Parent
    $script:ScriptsDir = Join-Path $ProjectRoot "Scripts"
}

Describe "Build-GoldISO.ps1 - Parameter Validation" {
    It "Should have valid parameter defaults" {
        $scriptPath = Join-Path $ScriptsDir "Build-GoldISO.ps1"
        $scriptPath | Should -Exist

        # Parse script for parameter block
        $content = Get-Content $scriptPath -Raw
        $content | Should -Match "\[CmdletBinding\(\)\]"
        $content | Should -Match "param\("
    }

    It "Should have all expected parameters defined" {
        $scriptPath = Join-Path $ScriptsDir "Build-GoldISO.ps1"
        $content = Get-Content $scriptPath -Raw

        # Check for expected parameters
        $expectedParams = @(
            "WorkingDir",
            "MountDir",
            "OutputISO",
            "SkipDriverInjection",
            "SkipPackageInjection",
            "SkipPortableApps",
            "SkipDependencyDownload",
            "BuildMode"
        )

        foreach ($param in $expectedParams) {
            $content | Should -Match "\[.*\]\$$param"
        }
    }

    It "Should have BuildMode parameter with valid ValidateSet" {
        $scriptPath = Join-Path $ScriptsDir "Build-GoldISO.ps1"
        $content = Get-Content $scriptPath -Raw
        $content | Should -Match "\[ValidateSet\(\"Standard\", \"Audit\", \"Capture\"\)\]"
    }
}

Describe "Build-ISO-With-Settings.ps1 - Parameter Validation" {
    It "Should have valid parameter defaults" {
        $scriptPath = Join-Path $ScriptsDir "Build-ISO-With-Settings.ps1"
        $scriptPath | Should -Exist
        $content = Get-Content $scriptPath -Raw
        $content | Should -Match "\[CmdletBinding\(\)\]"
    }

    It "Should import GoldISO-Common module" {
        $scriptPath = Join-Path $ScriptsDir "Build-ISO-With-Settings.ps1"
        $content = Get-Content $scriptPath -Raw
        $content | Should -Match "Import-Module.*GoldISO-Common"
    }

    It "Should use descriptive phase names instead of numbered phases" {
        $scriptPath = Join-Path $ScriptsDir "Build-ISO-With-Settings.ps1"
        $content = Get-Content $scriptPath -Raw

        # Should NOT have old "Phase N:" patterns
        $content | Should -Not -Match '"Phase \d+:'

        # Should have descriptive names
        $content | Should -Match "Settings Export"
        $content | Should -Match "Package Validation"
        $content | Should -Match "Settings Migration Prep"
    }
}

Describe "Build Scripts - Prerequisite Checks" {
    It "Build-GoldISO.ps1 should check for admin rights" {
        $scriptPath = Join-Path $ScriptsDir "Build-GoldISO.ps1"
        $content = Get-Content $scriptPath -Raw
        $content | Should -Match "Test-Admin|Administrator"
    }

    It "Build-GoldISO.ps1 should check for DISM" {
        $scriptPath = Join-Path $ScriptsDir "Build-GoldISO.ps1"
        $content = Get-Content $scriptPath -Raw
        $content | Should -Match "dism|DISM"
    }

    It "Build-GoldISO.ps1 should check for source ISO" {
        $scriptPath = Join-Path $ScriptsDir "Build-GoldISO.ps1"
        $content = Get-Content $scriptPath -Raw
        $content | Should -Match "Win11.*\.iso|Source ISO"
    }
}

Describe "Build Scripts - Error Handling" {
    It "Build-GoldISO.ps1 should have error handling for key operations" {
        $scriptPath = Join-Path $ScriptsDir "Build-GoldISO.ps1"
        $content = Get-Content $scriptPath -Raw
        $content | Should -Match "try \{|catch \{|ErrorAction"
    }

    It "Build-ISO-With-Settings.ps1 should handle export failures gracefully" {
        $scriptPath = Join-Path $ScriptsDir "Build-ISO-With-Settings.ps1"
        $content = Get-Content $scriptPath -Raw
        $content | Should -Match "try \{|catch \{|return \`$false"
    }
}

Describe "Build Scripts - Module Integration" {
    It "All build scripts should use centralized logging" {
        $buildScripts = @(
            "Build-GoldISO.ps1",
            "Build-ISO-With-Settings.ps1"
        )

        foreach ($script in $buildScripts) {
            $scriptPath = Join-Path $ScriptsDir $script
            if (Test-Path $scriptPath) {
                $content = Get-Content $scriptPath -Raw
                # Should use Write-Log or Write-GoldISOLog
                ($content -match "Write-Log|Write-GoldISOLog") | Should -Be $true -Because "$script should use centralized logging"
            }
        }
    }
}
