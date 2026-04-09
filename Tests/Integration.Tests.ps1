#Requires -Version 5.1
<#
.SYNOPSIS
    Integration tests for GoldISO.
.DESCRIPTION
    Tests module import, logging across scripts, and path resolution consistency.
#>

BeforeAll {
    Import-Module (Join-Path $PSScriptRoot "TestHelpers.psm1") -Force
    $script:ProjectRoot = Split-Path $PSScriptRoot -Parent
    $script:ScriptsDir = Join-Path $ProjectRoot "Scripts"
    $script:ModulePath = Join-Path $ScriptsDir "Modules\GoldISO-Common.psm1"
}

Describe "Module Import" {
    It "Should import GoldISO-Common module without errors" {
        { Import-Module $ModulePath -Force -ErrorAction Stop } | Should -Not -Throw
    }

    It "Should have all exported functions available after import" {
        Import-Module $ModulePath -Force
        $expectedFunctions = @(
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

        foreach ($func in $expectedFunctions) {
            Get-Command -Name $func -Module "GoldISO-Common" -ErrorAction SilentlyContinue |
                Should -Not -BeNullOrEmpty -Because "Function $func should be exported"
        }
    }

    It "Should have Write-Log alias available after import" {
        Import-Module $ModulePath -Force
        Get-Alias -Name "Write-Log" -ErrorAction SilentlyContinue | Should -Not -BeNullOrEmpty
    }
}

Describe "Path Resolution Consistency" {
    BeforeAll {
        Import-Module $ModulePath -Force
    }

    It "Get-GoldISORoot should return consistent path" {
        $path1 = Get-GoldISORoot
        $path2 = Get-GoldISORoot
        $path1 | Should -Be $path2
    }

    It "Get-GoldISORoot should return absolute path" {
        $path = Get-GoldISORoot
        $path | Should -Match "^[A-Za-z]:\\"
    }
}

Describe "Logging Across Scripts" {
    BeforeAll {
        Import-Module $ModulePath -Force
        $script:TestLogDir = Join-Path $env:TEMP "GoldISO-Integration-$(Get-Random)"
        New-Item -ItemType Directory -Path $TestLogDir -Force | Out-Null
    }

    AfterAll {
        if (Test-Path $TestLogDir) {
            Remove-Item -Path $TestLogDir -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    It "Should maintain consistent log format across all log levels" {
        $testFile = Join-Path $TestLogDir "consistency.log"
        Initialize-Logging -LogPath $testFile

        Write-GoldISOLog -Message "Test INFO" -Level "INFO"
        Write-GoldISOLog -Message "Test WARN" -Level "WARN"
        Write-GoldISOLog -Message "Test ERROR" -Level "ERROR"
        Write-GoldISOLog -Message "Test SUCCESS" -Level "SUCCESS"

        $lines = Get-Content $testFile
        # Skip INIT line
        $logLines = $lines | Select-Object -Skip 1

        foreach ($line in $logLines) {
            $line | Should -Match "^\[\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}\] \[(INFO|WARN|ERROR|SUCCESS)\] "
        }
    }

    It "Should handle concurrent logging gracefully" {
        $testFile = Join-Path $TestLogDir "concurrent.log"
        Initialize-Logging -LogPath $testFile

        $jobs = foreach ($index in 1..5) {
            Start-Job -ScriptBlock {
                param($ImportedModulePath, $LogPath, $MessageIndex)
                Import-Module $ImportedModulePath -Force
                Initialize-Logging -LogPath $LogPath
                Write-GoldISOLog -Message "Concurrent message $MessageIndex" -Level "INFO" -NoConsole
            } -ArgumentList $ModulePath, $testFile, $index
        }

        $null = $jobs | Wait-Job
        $jobs | Receive-Job | Out-Null
        $jobs | Remove-Job -Force | Out-Null

        $content = Get-Content $testFile
        $content.Count | Should -BeGreaterThan 1
    }
}

Describe "Script Dependencies" {
    It "All main scripts should exist" {
        $requiredScripts = @(
            "Build-GoldISO.ps1",
            "Build-ISO-With-Settings.ps1",
            "Apply-Image.ps1",
            "Capture-Image.ps1",
            "Export-Settings.ps1",
            "Configure-RamDisk.ps1",
            "Configure-RemoteAccess.ps1",
            "Backup-Macrium.ps1",
            "Create-AuditShortcuts.ps1",
            "install-ramdisk.ps1",
            "install-usb-apps.ps1",
            "shrink-and-recovery.ps1"
        )

        foreach ($script in $requiredScripts) {
            $scriptPath = Find-ScriptPath $script
            $scriptPath | Should -Not -BeNullOrEmpty -Because "$script is required"
            $scriptPath | Should -Exist
        }
    }

    It "Config directory should exist" {
        $configDir = Join-Path $ProjectRoot "Config"
        $configDir | Should -Exist
    }

    It "autounattend.xml should exist in Config or root" {
        $configAutounattend = Join-Path $ProjectRoot "Config\autounattend.xml"
        $rootAutounattend = Join-Path $ProjectRoot "autounattend.xml"

        ($configAutounattend | Test-Path) -or ($rootAutounattend | Test-Path) | Should -Be $true
    }
}

Describe "Build Manifest Functions" {
    BeforeAll {
        Import-Module $ModulePath -Force
        $script:TestManifestDir = Join-Path $env:TEMP "GoldISO-Manifest-$(Get-Random)"
        New-Item -ItemType Directory -Path $TestManifestDir -Force | Out-Null
    }

    AfterAll {
        if (Test-Path $TestManifestDir) {
            Remove-Item -Path $TestManifestDir -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    It "Export-BuildManifest should create valid JSON file" {
        $testManifest = @{
            Version = "1.0"
            BuildDate = Get-Date -Format "yyyy-MM-dd"
            Components = @(
                @{ Name = "Test"; Version = "1.0" }
            )
        }

        $testPath = Join-Path $TestManifestDir "test-manifest.json"
        $result = Export-BuildManifest -Manifest $testManifest -Path $testPath

        $result | Should -Be $true
        $testPath | Should -Exist

        $content = Get-Content $testPath -Raw | ConvertFrom-Json
        $content.Version | Should -Be "1.0"
    }
}
