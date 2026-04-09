#Requires -Version 5.1
<#
.SYNOPSIS
    Additional tests for Build-GoldISO.ps1
.DESCRIPTION
    Tests core build functions, phase execution, and error handling.
#>

BeforeAll {
    Import-Module (Join-Path $PSScriptRoot "TestHelpers.psm1") -Force
    $modulePath = Join-Path $PSScriptRoot "..\Scripts\Modules\GoldISO-Common.psm1"
    Import-Module $modulePath -Force

    $script:ProjectRoot = Split-Path $PSScriptRoot -Parent
}

Describe "Build-GoldISO.ps1 - Build Configuration" {
    It "Should have #Requires RunAsAdministrator" {
        $scriptPath = Find-ScriptPath "Build-GoldISO.ps1"
        $content = Get-Content $scriptPath -Raw
        $content | Should -Match '#Requires -RunAsAdministrator'
    }

    It "Should define working directory parameter" {
        $scriptPath = Find-ScriptPath "Build-GoldISO.ps1"
        $content = Get-Content $scriptPath -Raw
        $content | Should -Match '\$WorkingDir'
    }

    It "Should support SkipDriverInjection switch" {
        $scriptPath = Find-ScriptPath "Build-GoldISO.ps1"
        $content = Get-Content $scriptPath -Raw
        $content | Should -Match 'SkipDriverInjection'
    }

    It "Should have BuildMode parameter with ValidateSet" {
        $scriptPath = Find-ScriptPath "Build-GoldISO.ps1"
        $content = Get-Content $scriptPath -Raw
        $content | Should -Match 'ValidateSet'
    }
}

Describe "Build-GoldISO.ps1 - Core Functions" {
    It "Should define Invoke-OfflineRegistryHardening function" {
        $scriptPath = Find-ScriptPath "Build-GoldISO.ps1"
        $content = Get-Content $scriptPath -Raw
        $content | Should -Match 'function Invoke-OfflineRegistryHardening'
    }

    It "Should define Invoke-OfflineServiceConfig function" {
        $scriptPath = Find-ScriptPath "Build-GoldISO.ps1"
        $content = Get-Content $scriptPath -Raw
        $content | Should -Match 'function Invoke-OfflineServiceConfig'
    }

    It "Should define Invoke-OfflineDebloat function" {
        $scriptPath = Find-ScriptPath "Build-GoldISO.ps1"
        $content = Get-Content $scriptPath -Raw
        $content | Should -Match 'function Invoke-OfflineDebloat'
    }

    It "Should use module functions or defined helper functions" {
        $scriptPath = Find-ScriptPath "Build-GoldISO.ps1"
        $content = Get-Content $scriptPath -Raw
        # Check for either module function calls or custom function definitions
        $usesModule = $content -match 'Get-ComponentHash|Mount-WindowsImage|Export-WindowsImage|Test-DiskTopology'
        $hasHelpers = $content -match 'function (Copy-WorkingISO|Mount-SourceISO|Mount-WIM|Add-Drivers)'
        $usesModule -or $hasHelpers | Should -Be $true
    }
}

Describe "Build-GoldISO.ps1 - Prerequisites" {
    It "Should check for required tools (DISM)" {
        $scriptPath = Find-ScriptPath "Build-GoldISO.ps1"
        $content = Get-Content $scriptPath -Raw
        $content | Should -Match 'dism'
    }

    It "Should check for admin rights" {
        $scriptPath = Find-ScriptPath "Build-GoldISO.ps1"
        $content = Get-Content $scriptPath -Raw
        $content | Should -Match 'Test-Admin|Administrator'
    }

    It "Should validate source ISO path" {
        $scriptPath = Find-ScriptPath "Build-GoldISO.ps1"
        $content = Get-Content $scriptPath -Raw
        $content | Should -Match 'SourceISO|Source.*ISO|\.iso'
    }
}

Describe "Build-GoldISO.ps1 - Error Handling" {
    It "Should use try/catch blocks" {
        $scriptPath = Find-ScriptPath "Build-GoldISO.ps1"
        $content = Get-Content $scriptPath -Raw
        $content | Should -Match 'try\s*{'
        $content | Should -Match 'catch\s*{'
    }

    It "Should set ErrorActionPreference" {
        $scriptPath = Find-ScriptPath "Build-GoldISO.ps1"
        $content = Get-Content $scriptPath -Raw
        $content | Should -Match '\$ErrorActionPreference\s*=\s*"Stop"'
    }
}

Describe "Build-ISO-With-Settings.ps1 - Build Configuration" {
    It "Should exist" {
        $scriptPath = Find-ScriptPath "Build-ISO-With-Settings.ps1"
        $scriptPath | Should -Exist
    }

    It "Should import GoldISO-Common module" {
        $scriptPath = Find-ScriptPath "Build-ISO-With-Settings.ps1"
        $content = Get-Content $scriptPath -Raw
        $content | Should -Match 'Import-Module.*GoldISO-Common'
    }

    It "Should have descriptive phase names (not numbered)" {
        $scriptPath = Find-ScriptPath "Build-ISO-With-Settings.ps1"
        $content = Get-Content $scriptPath -Raw
        $content | Should -Not -Match '"Phase \d+:'
    }
}

Describe "Build-ISO-With-Settings.ps1 - Parameters" {
    It "Should have Profile parameter or configuration" {
        $scriptPath = Find-ScriptPath "Build-ISO-With-Settings.ps1"
        $content = Get-Content $scriptPath -Raw
        $content | Should -Match '\$Profile|ProfilePath'
    }

    It "Should have DiskLayout parameter" {
        $scriptPath = Find-ScriptPath "Build-ISO-With-Settings.ps1"
        $content = Get-Content $scriptPath -Raw
        $content | Should -Match '\$DiskLayout|DiskLayout'
    }

    It "Should have driver injection options" {
        $scriptPath = Find-ScriptPath "Build-ISO-With-Settings.ps1"
        $content = Get-Content $scriptPath -Raw
        $content | Should -Match 'Driver|Injection'
    }
}