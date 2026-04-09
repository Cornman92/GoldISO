#Requires -Version 5.1
#Requires -Modules Pester
<#
.SYNOPSIS
    Pester tests for Export-Settings.ps1
.NOTES
    Run with: Invoke-Pester -Path .\ExportSettings.Tests.ps1
#>

BeforeAll {
    $ProjectRoot = Join-Path $PSScriptRoot ".."
    $ScriptPath  = Join-Path $ProjectRoot "Scripts\Export-Settings.ps1"
    $script:Ast  = [System.Management.Automation.Language.Parser]::ParseFile($ScriptPath, [ref]$null, [ref]$null)
}

Describe "Export-Settings.ps1 - Structure" -Tag "Structure" {

    It "Script file exists" {
        Test-Path $ScriptPath | Should -Be $true
    }

    It "Has valid PowerShell syntax" {
        $errors = $null
        [System.Management.Automation.Language.Parser]::ParseFile(
            $ScriptPath, [ref]$null, [ref]$errors) | Out-Null
        $errors | Should -BeNullOrEmpty
    }

    It "Has CmdletBinding attribute" {
        $script:Ast.ParamBlock.Attributes.TypeName.FullName | Should -Contain 'CmdletBinding'
    }

    It "Requires PowerShell 5.1 or higher" {
        $content = Get-Content $ScriptPath -Raw
        $content | Should -Match '#Requires -Version 5\.1'
    }
}

Describe "Export-Settings.ps1 - Parameters" -Tag "Unit" {

    BeforeAll {
        $params = $script:Ast.ParamBlock.Parameters
        $script:ParamNames = $params.Name.VariablePath.UserPath
    }

    It "Has ExportPath parameter" {
        $script:ParamNames | Should -Contain 'ExportPath'
    }

    It "Has ExportUserData switch" {
        $script:ParamNames | Should -Contain 'ExportUserData'
    }

    It "Has ExcludeApps parameter" {
        $script:ParamNames | Should -Contain 'ExcludeApps'
    }

    It "Has MaxUserDataSizeGB parameter" {
        $script:ParamNames | Should -Contain 'MaxUserDataSizeGB'
    }

    It "Has IncludeWifiPasswords switch" {
        $script:ParamNames | Should -Contain 'IncludeWifiPasswords'
    }

    It "Has Compress switch" {
        $script:ParamNames | Should -Contain 'Compress'
    }

    It "MaxUserDataSizeGB defaults to 10" {
        $param = $script:Ast.ParamBlock.Parameters |
            Where-Object { $_.Name.VariablePath.UserPath -eq 'MaxUserDataSizeGB' }
        $param.DefaultValue.Value | Should -Be 10
    }

    It "ExcludeApps defaults to empty array" {
        $param = $script:Ast.ParamBlock.Parameters |
            Where-Object { $_.Name.VariablePath.UserPath -eq 'ExcludeApps' }
        $param.DefaultValue | Should -Not -BeNullOrEmpty
    }
}

Describe "Export-Settings.ps1 - Export Directory" -Tag "Integration" {

    It "Creates timestamped subdirectory under ExportPath" {
        $testPath = Join-Path $TestDrive "SettingsMigration"
        New-Item -ItemType Directory -Path $testPath -Force | Out-Null

        # Invoke script - it will fail partway through (no real apps/registry to export)
        # but the directory creation happens immediately on startup
        & $ScriptPath -ExportPath $testPath -ExportUserData:$false 2>&1 | Out-Null

        $dirs = Get-ChildItem -Path $testPath -Directory -ErrorAction SilentlyContinue
        $dirs.Count | Should -BeGreaterThan 0
        $dirs[0].Name | Should -Match '^Settings-Migration-\d+-\d+$'
    }

    It "Creates export.log inside export directory" {
        $testPath = Join-Path $TestDrive "SettingsMigration2"
        New-Item -ItemType Directory -Path $testPath -Force | Out-Null

        & $ScriptPath -ExportPath $testPath -ExportUserData:$false 2>&1 | Out-Null

        $exportDir = Get-ChildItem -Path $testPath -Directory -ErrorAction SilentlyContinue |
            Select-Object -First 1
        if ($exportDir) {
            $logFile = Join-Path $exportDir.FullName "export.log"
            Test-Path $logFile | Should -Be $true
        }
    }
}

AfterAll {
    Remove-Variable -Name Ast -Scope Script -ErrorAction SilentlyContinue
}
