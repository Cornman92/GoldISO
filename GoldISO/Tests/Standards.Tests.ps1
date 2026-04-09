#Requires -Version 5.1
<#
.SYNOPSIS
    Standards enforcement tests for GoldISO.
.DESCRIPTION
    Verifies all scripts import GoldISO-Common, no local Write-Log functions remain,
    no hardcoded paths, and proper Join-Path usage.
#>

BeforeAll {
    $script:ProjectRoot = Split-Path $PSScriptRoot -Parent
    $script:ScriptsDir = Join-Path $ProjectRoot "Scripts"
    $script:ModulePath = Join-Path $ScriptsDir "Modules\GoldISO-Common.psm1"
}

Describe "Centralized Logging Compliance" {
    It "All scripts should use centralized logging" {
        $scripts = Get-ChildItem -Path $ScriptsDir -Filter "*.ps1" -ErrorAction SilentlyContinue

        foreach ($script in $scripts) {
            $content = Get-Content $script.FullName -Raw -ErrorAction SilentlyContinue
            if ($content) {
                # Skip scripts that are meant to be standalone in target environments
                $targetEnvironmentScripts = @(
                    "install-usb-apps.ps1",
                    "shrink-and-recovery.ps1",
                    "install-ramdisk.ps1",
                    "Capture-Image.ps1",
                    "Create-AuditShortcuts.ps1"
                )

                if ($targetEnvironmentScripts -contains $script.Name) {
                    # These scripts should have try/catch for module import
                    $content | Should -Match "Import-Module.*GoldISO-Common|Initialize-Logging" -Because "$($script.Name) should attempt to use centralized logging"
                }
                else {
                    # Other scripts should directly import the module
                    $content | Should -Match "Import-Module.*GoldISO-Common|Initialize-Logging" -Because "$($script.Name) should import GoldISO-Common module"
                }
            }
        }
    }

    It "Scripts should not define local Write-Log function when module is available" {
        $coreScripts = @(
            "Build-GoldISO.ps1",
            "Build-ISO-With-Settings.ps1",
            "Export-Settings.ps1",
            "Backup-Macrium.ps1",
            "Configure-RamDisk.ps1",
            "Configure-RemoteAccess.ps1"
        )

        foreach ($scriptName in $coreScripts) {
            $scriptPath = Join-Path $ScriptsDir $scriptName
            if (Test-Path $scriptPath) {
                $content = Get-Content $scriptPath -Raw
                # Should not have "function Write-Log" after importing module
                if ($content -match "Import-Module.*GoldISO-Common") {
                    $content | Should -Not -Match "function Write-Log" -Because "$scriptName should not define local Write-Log when using module"
                }
            }
        }
    }
}

Describe "Path Construction Standards" {
    It "Scripts should use Join-Path instead of string concatenation" {
        $scripts = Get-ChildItem -Path $ScriptsDir -Filter "*.ps1" -ErrorAction SilentlyContinue

        foreach ($script in $scripts) {
            $content = Get-Content $script.FullName -Raw -ErrorAction SilentlyContinue
            if ($content) {
                # Check for common path construction patterns
                # Note: This is a heuristic check
                $hasJoinPath = $content -match "Join-Path"
                $hasHardcodedBackslash = $content -match "\\\$[A-Za-z]"  # Patterns like "\$variable"

                if ($hasHardcodedBackslash) {
                    $hasJoinPath | Should -Be $true -Because "$($script.Name) should use Join-Path for path construction"
                }
            }
        }
    }

    It "Should not have hardcoded absolute paths to user profiles" {
        $scripts = Get-ChildItem -Path $ScriptsDir -Filter "*.ps1" -ErrorAction SilentlyContinue

        foreach ($script in $scripts) {
            $content = Get-Content $script.FullName -Raw -ErrorAction SilentlyContinue
            if ($content) {
                # Should not have hardcoded references to specific user profiles
                $content | Should -Not -Match "C:\\Users\\[A-Za-z0-9]+\\" -Because "$($script.Name) should not have hardcoded user profile paths"
            }
        }
    }
}

Describe "Phase Numbering Standards" {
    It "Build scripts should use descriptive names instead of numbered phases" {
        $buildScripts = @(
            "Build-GoldISO.ps1",
            "Build-ISO-With-Settings.ps1"
        )

        foreach ($scriptName in $buildScripts) {
            $scriptPath = Join-Path $ScriptsDir $scriptName
            if (Test-Path $scriptPath) {
                $content = Get-Content $scriptPath -Raw
                # Should not have old "Phase N:" patterns in comments or strings
                $content | Should -Not -Match '"Phase \d+:' -Because "$scriptName should not use numbered phase patterns"
                $content | Should -Not -Match "'Phase \d+:" -Because "$scriptName should not use numbered phase patterns"
            }
        }
    }
}

Describe "Module Export Standards" {
    BeforeAll {
        Import-Module $ModulePath -Force
    }

    It "Module should export all required functions" {
        $requiredFunctions = @(
            "Initialize-Logging",
            "Write-GoldISOLog",
            "Test-GoldISOAdmin",
            "Test-GoldISOPath",
            "Format-GoldISOSize",
            "Test-GoldISOWinPE",
            "Get-GoldISORoot",
            "Invoke-GoldISOCommand",
            "Get-ComponentHash",
            "Test-DiskTopology",
            "Import-BuildManifest",
            "Export-BuildManifest"
        )

        $exported = Get-Module "GoldISO-Common" | Select-Object -ExpandProperty ExportedFunctions

        foreach ($func in $requiredFunctions) {
            $exported.Keys | Should -Contain $func -Because "Function $func should be exported from module"
        }
    }

    It "Module should have proper version information" {
        $module = Get-Module "GoldISO-Common"
        $module.Version | Should -Not -BeNullOrEmpty
    }
}

Describe "Error Handling Standards" {
    It "Scripts should have ErrorActionPreference defined" {
        $scripts = Get-ChildItem -Path $ScriptsDir -Filter "*.ps1" -ErrorAction SilentlyContinue

        foreach ($script in $scripts) {
            $content = Get-Content $script.FullName -Raw -ErrorAction SilentlyContinue
            if ($content) {
                $content | Should -Match "ErrorActionPreference" -Because "$($script.Name) should define ErrorActionPreference"
            }
        }
    }

    It "Scripts should have try/catch or error handling for critical operations" {
        # This is a heuristic check - not all scripts need try/catch everywhere
        # but scripts that perform system modifications should have error handling
        $criticalScripts = @(
            "Build-GoldISO.ps1",
            "Apply-Image.ps1",
            "Capture-Image.ps1",
            "shrink-and-recovery.ps1",
            "Export-Settings.ps1"
        )

        foreach ($scriptName in $criticalScripts) {
            $scriptPath = Join-Path $ScriptsDir $scriptName
            if (Test-Path $scriptPath) {
                $content = Get-Content $scriptPath -Raw
                $content | Should -Match "try \{|catch \{|ErrorAction" -Because "$scriptName should have error handling for critical operations"
            }
        }
    }
}

Describe "Documentation Standards" {
    It "Scripts should have synopsis in help" {
        $scripts = Get-ChildItem -Path $ScriptsDir -Filter "*.ps1" -ErrorAction SilentlyContinue

        foreach ($script in $scripts) {
            $content = Get-Content $script.FullName -Raw -ErrorAction SilentlyContinue
            if ($content -and -not ($script.Name -match "^_")) {
                # Skip scripts that start with underscore (private/internal)
                $content | Should -Match "\.SYNOPSIS" -Because "$($script.Name) should have a SYNOPSIS in help documentation"
            }
        }
    }

    It "Scripts should have parameter documentation when parameters exist" {
        $scripts = Get-ChildItem -Path $ScriptsDir -Filter "*.ps1" -ErrorAction SilentlyContinue

        foreach ($script in $scripts) {
            $content = Get-Content $script.FullName -Raw -ErrorAction SilentlyContinue
            if ($content -and ($content -match "\[CmdletBinding\(\)\]")) {
                # If script has cmdlet binding and parameters, should document them
                if ($content -match "param\(") {
                    $content | Should -Match "\.PARAMETER" -Because "$($script.Name) should document its parameters"
                }
            }
        }
    }
}
