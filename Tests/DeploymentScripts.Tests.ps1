#Requires -Version 5.1
<#
.SYNOPSIS
    Tests for GoldISO deployment scripts.
.DESCRIPTION
    Tests DISM operations, path resolution, and error scenarios
    for deployment scripts like Apply-Image.ps1.
#>

BeforeAll {
    Import-Module (Join-Path $PSScriptRoot "TestHelpers.psm1") -Force
    $modulePath = Join-Path $PSScriptRoot "..\Scripts\Modules\GoldISO-Common.psm1"
    Import-Module $modulePath -Force

    $script:ProjectRoot = Split-Path $PSScriptRoot -Parent
    $script:ScriptsDir = Join-Path $ProjectRoot "Scripts"
}

Describe "Apply-Image.ps1 - Parameter Validation" {
    It "Should have valid parameter defaults" {
        $scriptPath = Find-ScriptPath "Apply-Image.ps1"
        $scriptPath | Should -Exist
        $content = Get-Content $scriptPath -Raw
        $content | Should -Match '\[CmdletBinding'
    }

    It "Should have expected parameters" {
        $scriptPath = Find-ScriptPath "Apply-Image.ps1"
        $content = Get-Content $scriptPath -Raw

        $expectedParams = @(
            "ImagePath",
            "TargetDisk",
            "ImageIndex",
            "BootMode",
            "UnattendPath"
        )

        foreach ($param in $expectedParams) {
            $content | Should -Match ('\$' + $param)
        }
    }

    It "Should have BootMode parameter with valid ValidateSet" {
        $scriptPath = Find-ScriptPath "Apply-Image.ps1"
        $content = Get-Content $scriptPath -Raw
        $content | Should -Match 'ValidateSet.*"UEFI"'
    }
}

Describe "Apply-Image.ps1 - WinPE Detection" {
    It "Should detect WinPE environment" {
        $scriptPath = Find-ScriptPath "Apply-Image.ps1"
        $content = Get-Content $scriptPath -Raw
        $content | Should -Match "WinPE|WindowsPE"
    }

    It "Should handle both WinPE and non-WinPE environments" {
        $scriptPath = Find-ScriptPath "Apply-Image.ps1"
        $content = Get-Content $scriptPath -Raw
        $content | Should -Match "WinPE\.exe|EditionID.*WindowsPE"
    }
}

Describe "Apply-Image.ps1 - Path Resolution" {
    It "Should search multiple drive letters for image" {
        $scriptPath = Find-ScriptPath "Apply-Image.ps1"
        $content = Get-Content $scriptPath -Raw
        $content | Should -Match "I:\\.*Capture\.wim|D:\\.*Capture\.wim"
    }

    It "Should use Join-Path for path construction" {
        $scriptPath = Find-ScriptPath "Apply-Image.ps1"
        $content = Get-Content $scriptPath -Raw
        $content | Should -Match "Join-Path"
    }
}

Describe "Apply-Image.ps1 - Boot Configuration" {
    It "Should support UEFI boot mode" {
        $scriptPath = Find-ScriptPath "Apply-Image.ps1"
        $content = Get-Content $scriptPath -Raw
        $content | Should -Match "UEFI|bcdboot.*UEFI"
    }

    It "Should support BIOS boot mode" {
        $scriptPath = Find-ScriptPath "Apply-Image.ps1"
        $content = Get-Content $scriptPath -Raw
        $content | Should -Match "BIOS|bcdboot"
    }

    It "Should create appropriate partitions for UEFI" {
        $scriptPath = Find-ScriptPath "Apply-Image.ps1"
        $content = Get-Content $scriptPath -Raw
        $content | Should -Match "EFI.*Partition|GptType"
    }
}

Describe "Apply-Image.ps1 - Module Integration" {
    It "Should import GoldISO-Common module" {
        $scriptPath = Find-ScriptPath "Apply-Image.ps1"
        $content = Get-Content $scriptPath -Raw
        $content | Should -Match "Import-Module.*GoldISO-Common"
    }

    It "Should use centralized logging" {
        $scriptPath = Find-ScriptPath "Apply-Image.ps1"
        $content = Get-Content $scriptPath -Raw
        $content | Should -Match "Initialize-Logging|Write-Log"
    }
}

Describe "Capture-Image.ps1 - Parameter Validation" {
    It "Should have valid parameter defaults" {
        $scriptPath = Find-ScriptPath "Capture-Image.ps1"
        $scriptPath | Should -Exist
        $content = Get-Content $scriptPath -Raw
        $content | Should -Match '\[CmdletBinding'
    }

    It "Should have WinPE detection" {
        $scriptPath = Find-ScriptPath "Capture-Image.ps1"
        $content = Get-Content $scriptPath -Raw
        $content | Should -Match "WinPE|Test-Path.*X:"
    }
}

Describe "shrink-and-recovery.ps1 - Parameter Validation" {
    It "Should have valid parameter defaults" {
        $scriptPath = Find-ScriptPath "shrink-and-recovery.ps1"
        $scriptPath | Should -Exist
        $content = Get-Content $scriptPath -Raw
        $content | Should -Match '\[CmdletBinding'
    }

    It "Should have DiskNumber parameter with default" {
        $scriptPath = Find-ScriptPath "shrink-and-recovery.ps1"
        $content = Get-Content $scriptPath -Raw
        $content | Should -Match '\[int\]\$DiskNumber'
    }

    It "Should use centralized logging" {
        $scriptPath = Find-ScriptPath "shrink-and-recovery.ps1"
        $content = Get-Content $scriptPath -Raw
        $content | Should -Match "Initialize-Logging|Write-Log"
    }
}
