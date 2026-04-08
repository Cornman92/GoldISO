#Requires -Version 5.1
#Requires -Modules Pester
<#
.SYNOPSIS
    Configuration file validation tests.
.DESCRIPTION
    Tests for validating JSON configs, package manifests, and other configuration files.
.NOTES
    Run with: Invoke-Pester -Path .\Config.Tests.ps1
#>

BeforeAll {
    $ProjectRoot = Join-Path $PSScriptRoot ".."
}

Describe "winget-packages.json Validation" {
    BeforeAll {
        $ConfigPath = Join-Path $ProjectRoot "Config\winget-packages.json"
        $Config = $null
    }

    It "File exists" {
        Test-Path $ConfigPath | Should -Be $true
    }

    It "Is valid JSON" {
        { $Config = Get-Content $ConfigPath -Raw | ConvertFrom-Json } | Should -Not -Throw
    }

    It "Has required top-level properties" {
        $Config = Get-Content $ConfigPath -Raw | ConvertFrom-Json
        $Config.Categories | Should -Not -BeNullOrEmpty
        $Config.Sources | Should -Not -BeNullOrEmpty
        $Config.Sources[0].Packages | Should -Not -BeNullOrEmpty
    }

    It "Has valid category definitions" {
        $Config = Get-Content $ConfigPath -Raw | ConvertFrom-Json
        foreach ($category in $Config.Categories) {
            $category.Name | Should -Not -BeNullOrEmpty
            $category.Description | Should -Not -BeNullOrEmpty
        }
    }

    It "Has valid package definitions" {
        $Config = Get-Content $ConfigPath -Raw | ConvertFrom-Json
        $packages = $Config.Sources[0].Packages
        
        foreach ($pkg in $packages) {
            $pkg.PackageIdentifier | Should -Not -BeNullOrEmpty
            $pkg.PackageIdentifier | Should -Match "^[^.]+\.[^.]+"  # At least two dot-separated parts
            $pkg.Category | Should -Not -BeNullOrEmpty
            $pkg.Optional | Should -Not -BeNullOrEmpty
        }
    }

    It "All packages reference valid categories" {
        $Config = Get-Content $ConfigPath -Raw | ConvertFrom-Json
        $validCategories = $Config.Categories.Name
        $packages = $Config.Sources[0].Packages

        foreach ($pkg in $packages) {
            $validCategories | Should -Contain $pkg.Category
        }
    }

    It "Has expected package count" {
        $Config = Get-Content $ConfigPath -Raw | ConvertFrom-Json
        $packageCount = $Config.Sources[0].Packages.Count
        $packageCount | Should -BeGreaterThan 0
        # Log the count for reference
        Write-Host "  Total packages: $packageCount"
    }
}

Describe "NTLite Preset Validation" {
    It "GamerOS Windows 11.xml exists" {
        $presetPath = Join-Path $ProjectRoot "Config\GamerOS Windows 11.xml"
        Test-Path $presetPath | Should -Be $true
    }
}

Describe "Package.json Validation" {
    BeforeAll {
        $PackageJsonPath = Join-Path $ProjectRoot "Config\package.json"
    }

    It "File exists" {
        Test-Path $PackageJsonPath | Should -Be $true
    }

    It "Is valid JSON" {
        { Get-Content $PackageJsonPath -Raw | ConvertFrom-Json } | Should -Not -Throw
    }
}

Describe "PowerShell Profile Configuration" {
    It "PowerShellProfile directory exists" {
        $profileDir = Join-Path $ProjectRoot "Config\PowerShellProfile"
        Test-Path $profileDir | Should -Be $true
    }

    It "Profile script exists" {
        $profileScript = Join-Path $ProjectRoot "Config\PowerShellProfile\Microsoft.PowerShell_profile.ps1"
        Test-Path $profileScript | Should -Be $true
    }

    It "Profile config exists" {
        $profileConfig = Join-Path $ProjectRoot "Config\PowerShellProfile\Config\profile-config.json"
        Test-Path $profileConfig | Should -Be $true
    }
}

Describe "SettingsMigration Directory" {
    It "SettingsMigration directory exists" {
        $smDir = Join-Path $ProjectRoot "Config\SettingsMigration"
        Test-Path $smDir | Should -Be $true
    }

    It "Contains restore-settings.ps1" {
        $restoreScript = Join-Path $ProjectRoot "Config\SettingsMigration\restore-settings.ps1"
        Test-Path $restoreScript | Should -Be $true
    }
}
