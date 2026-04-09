#Requires -Version 5.1
<#
.SYNOPSIS
    Tests for GoldISO utility scripts.
.DESCRIPTION
    Tests configuration loading, manifest parsing, and common utility functions.
#>

BeforeAll {
    Import-Module (Join-Path $PSScriptRoot "TestHelpers.psm1") -Force
    $modulePath = Join-Path $PSScriptRoot "..\Scripts\Modules\GoldISO-Common.psm1"
    Import-Module $modulePath -Force

    $script:ProjectRoot = Split-Path $PSScriptRoot -Parent
    $script:ScriptsDir = Join-Path $ProjectRoot "Scripts"
    $script:ConfigDir = Join-Path $ProjectRoot "Config"
}

Describe "GoldISO-Common.psm1 - Functions" {
    It "Should export all expected functions" {
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
            Get-Command -Name $func -Module "GoldISO-Common" | Should -Not -BeNullOrEmpty
        }
    }

    It "Should have Write-Log alias" {
        Get-Alias -Name "Write-Log" | Should -Not -BeNullOrEmpty
    }
}

Describe "Test-GoldISOAdmin" {
    It "Should return current admin status without exit when ExitIfNotAdmin is not specified" {
        $result = Test-GoldISOAdmin
        $result -is [bool] | Should -Be $true
    }
}

Describe "Format-GoldISOSize" {
    It "Should format bytes to human-readable size" {
        Format-GoldISOSize -Bytes 1024 | Should -Be "1.00 KB"
        Format-GoldISOSize -Bytes 1048576 | Should -Be "1.00 MB"
        Format-GoldISOSize -Bytes 1073741824 | Should -Be "1.00 GB"
    }

    It "Should respect DecimalPlaces parameter" {
        Format-GoldISOSize -Bytes 1536 -DecimalPlaces 0 | Should -Be "2 KB"
        Format-GoldISOSize -Bytes 1536 -DecimalPlaces 3 | Should -Be "1.500 KB"
    }
}

Describe "Test-GoldISOPath" {
    It "Should return true for existing file" {
        $testFile = Join-Path $env:TEMP "test-$(Get-Random).txt"
        "test" | Set-Content $testFile
        Test-GoldISOPath -Path $testFile -Type File | Should -Be $true
        Remove-Item $testFile
    }

    It "Should return true for existing directory" {
        $testDir = Join-Path $env:TEMP "testdir-$(Get-Random)"
        New-Item -ItemType Directory -Path $testDir -Force | Out-Null
        Test-GoldISOPath -Path $testDir -Type Directory | Should -Be $true
        Remove-Item $testDir
    }

    It "Should create directory when CreateIfMissing is specified" {
        $testDir = Join-Path $env:TEMP "newdir-$(Get-Random)"
        Test-GoldISOPath -Path $testDir -Type Directory -CreateIfMissing | Should -Be $true
        $testDir | Should -Exist
        Remove-Item $testDir
    }
}

Describe "Get-GoldISORoot" {
    It "Should return a path" {
        $result = Get-GoldISORoot
        $result | Should -Not -BeNullOrEmpty
        $result -is [string] | Should -Be $true
    }
}

Describe "Export-Settings.ps1 - Configuration" {
    It "Should have valid parameter defaults" {
        $scriptPath = Find-ScriptPath "Export-Settings.ps1"
        $scriptPath | Should -Exist
        $content = Get-Content $scriptPath -Raw
        $content | Should -Match '\[CmdletBinding'
    }

    It "Should use centralized logging" {
        $scriptPath = Find-ScriptPath "Export-Settings.ps1"
        $content = Get-Content $scriptPath -Raw
        $content | Should -Match "Import-Module.*GoldISO-Common"
    }

    It "Should have ExportPath parameter" {
        $scriptPath = Find-ScriptPath "Export-Settings.ps1"
        $content = Get-Content $scriptPath -Raw
        $content | Should -Match '\[string\]\$ExportPath'
    }
}

Describe "Configure-RamDisk.ps1 - Configuration" {
    It "Should have valid parameter defaults" {
        $scriptPath = Find-ScriptPath "Configure-RamDisk.ps1"
        $scriptPath | Should -Exist
        $content = Get-Content $scriptPath -Raw
        $content | Should -Match '\[CmdletBinding'
    }

    It "Should use centralized logging" {
        $scriptPath = Find-ScriptPath "Configure-RamDisk.ps1"
        $content = Get-Content $scriptPath -Raw
        $content | Should -Match "Initialize-Logging|Write-Log"
    }

    It "Should have RamDrive parameter with default" {
        $scriptPath = Find-ScriptPath "Configure-RamDisk.ps1"
        $content = Get-Content $scriptPath -Raw
        $content | Should -Match '\[string\]\$RamDrive'
    }
}

Describe "Configure-RemoteAccess.ps1 - Configuration" {
    It "Should have valid parameter defaults" {
        $scriptPath = Find-ScriptPath "Configure-RemoteAccess.ps1"
        $scriptPath | Should -Exist
        $content = Get-Content $scriptPath -Raw
        $content | Should -Match '\[CmdletBinding'
    }

    It "Should use centralized logging" {
        $scriptPath = Find-ScriptPath "Configure-RemoteAccess.ps1"
        $content = Get-Content $scriptPath -Raw
        $content | Should -Match "Initialize-Logging|Write-Log"
    }

    It "Should have expected parameters" {
        $scriptPath = Find-ScriptPath "Configure-RemoteAccess.ps1"
        $content = Get-Content $scriptPath -Raw
        $content | Should -Match '\$AnyDeskPassword'
        $content | Should -Match '\$TailscaleAuthKey'
        $content | Should -Match '\$SkipAnyDesk'
        $content | Should -Match '\$SkipTailscale'
    }
}

Describe "Backup-Macrium.ps1 - Configuration" {
    It "Should have valid parameter defaults" {
        $scriptPath = Find-ScriptPath "Backup-Macrium.ps1"
        $scriptPath | Should -Exist
        $content = Get-Content $scriptPath -Raw
        $content | Should -Match '\[CmdletBinding'
    }

    It "Should use centralized logging" {
        $scriptPath = Find-ScriptPath "Backup-Macrium.ps1"
        $content = Get-Content $scriptPath -Raw
        $content | Should -Match "Initialize-Logging|Write-Log"
    }

    It "Should have BackupDest parameter with default" {
        $scriptPath = Find-ScriptPath "Backup-Macrium.ps1"
        $content = Get-Content $scriptPath -Raw
        $content | Should -Match '\[string\]\$BackupDest'
    }
}

Describe "Create-AuditShortcuts.ps1 - Configuration" {
    It "Should have valid cmdlet binding" {
        $scriptPath = Find-ScriptPath "Create-AuditShortcuts.ps1"
        $scriptPath | Should -Exist
        $content = Get-Content $scriptPath -Raw
        $content | Should -Match '\[CmdletBinding'
    }

    It "Should use centralized logging or local fallback" {
        $scriptPath = Find-ScriptPath "Create-AuditShortcuts.ps1"
        $content = Get-Content $scriptPath -Raw
        $content | Should -Match "Write-Log|Write-GoldISOLog"
    }
}
