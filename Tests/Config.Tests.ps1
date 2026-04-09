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

Describe "Queue Configuration Files (V3.1)" {
    It "services-config.json exists" {
        $servicesConfig = Join-Path $ProjectRoot "Config\services-config.json"
        Test-Path $servicesConfig | Should -Be $true
    }

    It "services-config.json is valid JSON" {
        $servicesConfig = Join-Path $ProjectRoot "Config\services-config.json"
        { Get-Content $servicesConfig -Raw | ConvertFrom-Json } | Should -Not -Throw
    }

    It "queued-registry.json exists" {
        $regQueue = Join-Path $ProjectRoot "Config\queued-registry.json"
        Test-Path $regQueue | Should -Be $true
    }

    It "queued-registry.json is valid JSON" {
        $regQueue = Join-Path $ProjectRoot "Config\queued-registry.json"
        { Get-Content $regQueue -Raw | ConvertFrom-Json } | Should -Not -Throw
    }

    It "driver-queue.json exists" {
        $driverQueue = Join-Path $ProjectRoot "Config\driver-queue.json"
        Test-Path $driverQueue | Should -Be $true
    }

    It "driver-queue.json is valid JSON" {
        $driverQueue = Join-Path $ProjectRoot "Config\driver-queue.json"
        { Get-Content $driverQueue -Raw | ConvertFrom-Json } | Should -Not -Throw
    }

    It "debloat-list.json exists" {
        $debloatList = Join-Path $ProjectRoot "Config\debloat-list.json"
        Test-Path $debloatList | Should -Be $true
    }

    It "debloat-list.json is valid JSON" {
        $debloatList = Join-Path $ProjectRoot "Config\debloat-list.json"
        { Get-Content $debloatList -Raw | ConvertFrom-Json } | Should -Not -Throw
    }
}

Describe "package.json" {
    It "package.json exists" {
        $packageJsonPath = Join-Path $ProjectRoot "Config\package.json"
        Test-Path $packageJsonPath | Should -Be $true
    }

    It "package.json is valid JSON" {
        $packageJsonPath = Join-Path $ProjectRoot "Config\package.json"
        { Get-Content $packageJsonPath -Raw | ConvertFrom-Json } | Should -Not -Throw
    }

    It "package.json has required fields" {
        $packageJsonPath = Join-Path $ProjectRoot "Config\package.json"
        $pkg = Get-Content $packageJsonPath -Raw | ConvertFrom-Json
        $pkg.name | Should -Not -BeNullOrEmpty
        $pkg.version | Should -Not -BeNullOrEmpty
        $pkg.scripts | Should -Not -BeNullOrEmpty
    }
}
