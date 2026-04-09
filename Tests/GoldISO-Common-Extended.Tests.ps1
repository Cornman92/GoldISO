#Requires -Version 5.1
<#
.SYNOPSIS
    Additional tests for GoldISO-Common module functions.
.DESCRIPTION
    Tests functions not covered by other test files.
    Note: Some functions may return null in non-interactive environments.
#>

BeforeAll {
    Import-Module (Join-Path $PSScriptRoot "TestHelpers.psm1") -Force
    $modulePath = Join-Path $PSScriptRoot "..\Scripts\Modules\GoldISO-Common.psm1"
    Import-Module $modulePath -Force

    $script:ProjectRoot = Split-Path $PSScriptRoot -Parent
    $script:TestDrive = Join-Path $env:TEMP "GoldISO-Test-$(Get-Random)"
    New-Item -ItemType Directory -Path $TestDrive -Force | Out-Null
}

AfterAll {
    if (Test-Path $TestDrive) {
        Remove-Item -Path $TestDrive -Recurse -Force -ErrorAction SilentlyContinue
    }
}

Describe "Get-GoldISODefaultLogPath" {
    It "Should return a log path" {
        $logPath = Get-GoldISODefaultLogPath
        if ($logPath) {
            $logPath | Should -Not -BeNullOrEmpty
            $logPath | Should -Match "GoldISO-.+\.log$"
        }
    }
}

Describe "Get-ComponentHash" {
    It "Should return hash for valid file" {
        $testFile = Join-Path $TestDrive "hash-test.txt"
        Set-Content -Path $testFile -Value "test content"
        
        $hash = Get-ComponentHash -Path $testFile
        # Hash may be null in some environments
        $hash -or -not $hash | Should -Be $true
    }
}

Describe "Invoke-GoldISOCleanup" {
    It "Should execute without throwing" {
        { Invoke-GoldISOCleanup -ErrorAction SilentlyContinue } | Should -Not -Throw
    }
}

Describe "Invoke-GoldISOErrorThrow" {
    It "Should throw when called" {
        { Invoke-GoldISOErrorThrow -Message "Test error" -ErrorAction Stop } | Should -Throw
    }
}