#Requires -Version 5.1
#Requires -Modules Pester
<#
.SYNOPSIS
    PowerShell script syntax and structure tests.
.DESCRIPTION
    Validates that all PowerShell scripts have valid syntax, proper structure,
    and consistent formatting.
.NOTES
    Run with: Invoke-Pester -Path .\ScriptSyntax.Tests.ps1
#>

BeforeAll {
    $ProjectRoot = Join-Path $PSScriptRoot ".."
    $ScriptsPath = Join-Path $ProjectRoot "Scripts"
    
    # Get all .ps1 files
    $AllScripts = Get-ChildItem -Path $ScriptsPath -Filter "*.ps1" -Recurse -ErrorAction SilentlyContinue
    
    # Get all .psm1 files
    $AllModules = Get-ChildItem -Path $ScriptsPath -Filter "*.psm1" -Recurse -ErrorAction SilentlyContinue
    
    $AllPowerShellFiles = $AllScripts + $AllModules
}

Describe "PowerShell Script Syntax Validation" {
    It "All .ps1 files have valid PowerShell syntax" {
        $syntaxErrors = @()
        
        $excludedFiles = @("Capture-Image.ps1")
        
        foreach ($file in $AllScripts) {
            if ($excludedFiles -contains $file.Name) { continue }
            
            $tokens = $null
            $parseErrors = $null
            $ast = [System.Management.Automation.Language.Parser]::ParseFile(
                $file.FullName, 
                [ref]$tokens, 
                [ref]$parseErrors
            )
            
            if ($parseErrors.Count -gt 0) {
                $syntaxErrors += "{0}: {1}" -f $file.Name, ($parseErrors -join ", ")
            }
        }
        
        $syntaxErrors.Count | Should -Be 0 -Because "syntax errors found: $($syntaxErrors -join '; ')"
    }
}

Describe "Script Documentation Standards" {
    It "Build scripts have help documentation" {
        $buildScripts = @(
            "Build-GoldISO.ps1",
            "Build-ISO-With-Settings.ps1",
            "Export-Settings.ps1"
        )
        
        foreach ($scriptName in $buildScripts) {
            $scriptPath = Join-Path $ScriptsPath $scriptName
            if (Test-Path $scriptPath) {
                $content = Get-Content $scriptPath -Raw
                $content | Should -Match "\.SYNOPSIS"
                $content | Should -Match "\.DESCRIPTION"
            }
        }
    }

    It "Validation scripts have help documentation" {
        $validationScripts = @(
            "Test-Environment.ps1",
            "Test-UnattendXML.ps1"
        )
        
        foreach ($scriptName in $validationScripts) {
            $scriptPath = Join-Path $ScriptsPath $scriptName
            if (Test-Path $scriptPath) {
                $content = Get-Content $scriptPath -Raw
                $content | Should -Match "\.SYNOPSIS"
            }
        }
    }

    It "Deployment scripts have help documentation" {
        $deploymentScripts = @(
            "Apply-Image.ps1",
            "Capture-Image.ps1",
            "Configure-SecondaryDrives.ps1"
        )
        
        foreach ($scriptName in $deploymentScripts) {
            $scriptPath = Join-Path $ScriptsPath $scriptName
            if (Test-Path $scriptPath) {
                $content = Get-Content $scriptPath -Raw
                $content | Should -Match "\.SYNOPSIS"
            }
        }
    }
}

Describe "Script Structure Standards" {
    It "Scripts use #Requires -Version 5.1 or higher" {
        foreach ($file in $AllPowerShellFiles) {
            $content = Get-Content $file.FullName -Raw
            if ($content -match "#Requires\s+-Version") {
                $content | Should -Match "#Requires\s+-Version\s+5\.1" -Because "$($file.Name) should require PowerShell 5.1+"
            }
        }
    }

    It "Scripts that need admin use #Requires -RunAsAdministrator or Test-Admin" {
        $adminScripts = @(
            "Apply-Image.ps1",
            "Capture-Image.ps1",
            "Configure-SecondaryDrives.ps1",
            "shrink-and-recovery.ps1",
            "install-usb-apps.ps1",
            "install-ramdisk.ps1"
        )
        
        foreach ($scriptName in $adminScripts) {
            $scriptPath = Join-Path $ScriptsPath $scriptName
            if (Test-Path $scriptPath) {
                $content = Get-Content $scriptPath -Raw
                $hasRequiresAdmin = $content -match "#Requires\s+-RunAsAdministrator"
                $hasTestAdmin = $content -match "Test-Admin|Test-GoldISOAdmin|# Check admin"
                ($hasRequiresAdmin -or $hasTestAdmin) | Should -Be $true -Because "$scriptName should require or check for admin"
            }
        }
    }
}

Describe "Error Handling Standards" {
    It "Scripts set ErrorActionPreference (except UI/dialog scripts)" {
        $excludedScripts = @(
            "AuditMode-Continue.ps1",  # Desktop UI script with dialog boxes
            "GoldISO-App.ps1",         # WPF UI application
            "GoldISO-GUI.ps1",         # Another WPF UI application
            "GoldISO-Updater.ps1",     # Updater UI script
            "Get.ps1",                 # Download/bootstrap script
            "install-ramdisk.ps1"      # Install script using #Requires
        )
        
        foreach ($file in $AllScripts) {
            if ($excludedScripts -contains $file.Name) { continue }
            
            $content = Get-Content $file.FullName -Raw
            $hasErrorPreference = $content -match '\$ErrorActionPreference\s*=\s*["''(](Stop|Continue)["'']'
            $hasErrorPreference | Should -Be $true -Because "$($file.Name) should set ErrorActionPreference"
        }
    }
}
