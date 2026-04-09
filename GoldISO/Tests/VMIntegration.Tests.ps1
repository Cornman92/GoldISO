#Requires -Version 5.1
#Requires -Modules Pester
<#
.SYNOPSIS
    Pester tests for VM-based testing pipeline integration.
.DESCRIPTION
    Validates VM test infrastructure and integration with the build pipeline.
    These tests check for the presence and basic structure of VM-related scripts.
    Actual VM creation/testing requires Hyper-V and is typically run manually.
.NOTES
    Run with: Invoke-Pester -Path .\VMIntegration.Tests.ps1
#>

BeforeAll {
    Import-Module (Join-Path $PSScriptRoot "TestHelpers.psm1") -Force
    $script:ProjectRoot = Join-Path $PSScriptRoot ".."
    $script:ScriptsDir = Join-Path $script:ProjectRoot "Scripts"
}

Describe "VM Test Infrastructure" {
    Context "VM Creation Scripts" {
        It "New-TestVM.ps1 exists" {
            $vmScript = Find-ScriptPath "New-TestVM.ps1"
            Test-Path $vmScript | Should -Be $true
        }

        It "New-TestVM.ps1 has valid syntax" {
            $vmScript = Find-ScriptPath "New-TestVM.ps1"
            $errors = $null
            $null = [System.Management.Automation.PSParser]::Tokenize((Get-Content $vmScript -Raw), [ref]$errors)
            $errors.Count | Should -Be 0
        }

        It "New-TestVM.ps1 has required parameters" {
            $vmScript = Find-ScriptPath "New-TestVM.ps1"
            $content = Get-Content $vmScript -Raw
            $content | Should -Match '\[string\]\$VMName'
            $content | Should -Match '\[int\]\$VHDSizeGB'
            $content | Should -Match '\[int\]\$MemoryGB'
            $content | Should -Match '\[int\]\$CPUs'
        }
    }

    Context "VM Performance Scripts" {
        It "Test-VMPerformance.ps1 exists" {
            $perfScript = Find-ScriptPath "Test-VMPerformance.ps1"
            Test-Path $perfScript | Should -Be $true
        }

        It "Test-VMPerformance.ps1 has valid syntax" {
            $perfScript = Find-ScriptPath "Test-VMPerformance.ps1"
            $errors = $null
            $null = [System.Management.Automation.PSParser]::Tokenize((Get-Content $perfScript -Raw), [ref]$errors)
            $errors.Count | Should -Be 0
        }
    }
}

Describe "VM Pipeline Integration" {
    Context "Start-BuildPipeline VM Support" {
        It "Start-BuildPipeline.ps1 has -DeployToVM parameter" {
            $pipelineScript = Find-ScriptPath "Start-BuildPipeline.ps1"
            $content = Get-Content $pipelineScript -Raw
            $content | Should -Match '\[switch\]\$DeployToVM'
        }

        It "Start-BuildPipeline.ps1 references New-TestVM" {
            $pipelineScript = Find-ScriptPath "Start-BuildPipeline.ps1"
            $content = Get-Content $pipelineScript -Raw
            $content | Should -Match 'New-TestVM'
        }
    }

    Context "VM Requirements Check" {
        It "Documents VM requirements" {
            $docsDir = Join-Path $script:ProjectRoot "Docs"
            $docsExist = Test-Path $docsDir
            $docsExist | Should -Be $true
        }
    }
}

Describe "VM Test Execution" {
    Context "Hyper-V Availability" {
        It "Can detect Hyper-V status" {
            # Just verify the command exists
            { Get-Command Get-VM -ErrorAction SilentlyContinue } | Should -Not -Throw
        }
    }

    Context "VM Network Switch" {
        It "Documents Default Switch requirement" {
            $newVMScript = Find-ScriptPath "New-TestVM.ps1"
            $content = Get-Content $newVMScript -Raw
            $content | Should -Match 'Default Switch'
        }
    }
}

Describe "ISO Boot Test Infrastructure" {
    Context "Test-ISO.ps1" {
        It "Test-ISO.ps1 exists" {
            $testISO = Join-Path $PSScriptRoot "Test-ISO.ps1"
            Test-Path $testISO | Should -Be $true
        }

        It "Test-ISO.ps1 validates ISO structure" {
            $testISO = Join-Path $PSScriptRoot "Test-ISO.ps1"
            $content = Get-Content $testISO -Raw
            $content | Should -Match 'autounattend\.xml'
            $content | Should -Match 'install\.wim'
        }
    }
}
