#Requires -Version 5.1
#Requires -Modules Pester
<#
.SYNOPSIS
    Pester tests for GoldISO-Common.psm1 module functions.
.DESCRIPTION
    Comprehensive unit tests for all exported functions in the GoldISO common module.
.NOTES
    Run with: Invoke-Pester -Path .\GoldISO-Common.Tests.ps1
#>

BeforeAll {
    $ModulePath = Join-Path $PSScriptRoot "..\Scripts\Modules\GoldISO-Common.psm1"
    Import-Module $ModulePath -Force -ErrorAction Stop
}

Describe "Initialize-Logging" {
    It "Creates log file when directory exists" {
        $testLog = Join-Path $env:TEMP "GoldISO-Test-$(Get-Random).log"
        Initialize-Logging -LogPath $testLog
        Test-Path $testLog | Should -Be $true
        if (Test-Path $testLog) { Remove-Item $testLog -Force }
    }

    It "Creates log directory if missing" {
        $testDir = Join-Path $env:TEMP "GoldISO-TestDir-$(Get-Random)"
        $testLog = Join-Path $testDir "test.log"
        Initialize-Logging -LogPath $testLog
        Test-Path $testDir | Should -Be $true
        if (Test-Path $testDir) { Remove-Item $testDir -Recurse -Force }
    }
}

Describe "Write-GoldISOLog" {
    BeforeEach {
        $testLog = Join-Path $env:TEMP "GoldISO-LogTest-$(Get-Random).log"
        Initialize-Logging -LogPath $testLog
    }

    AfterEach {
        if (Test-Path $testLog) { Remove-Item $testLog -Force }
    }

    It "Writes INFO level message to log file" {
        Write-GoldISOLog -Message "Test message" -Level "INFO"
        $content = Get-Content $testLog -Tail 1
        $content | Should -Match "\[INFO\] Test message"
    }

    It "Writes ERROR level message to log file" {
        Write-GoldISOLog -Message "Error occurred" -Level "ERROR"
        $content = Get-Content $testLog -Tail 1
        $content | Should -Match "\[ERROR\] Error occurred"
    }

    It "Writes SUCCESS level message to log file" {
        Write-GoldISOLog -Message "Success!" -Level "SUCCESS"
        $content = Get-Content $testLog -Tail 1
        $content | Should -Match "\[SUCCESS\] Success!"
    }

    It "Writes WARN level message to log file" {
        Write-GoldISOLog -Message "Warning!" -Level "WARN"
        $content = Get-Content $testLog -Tail 1
        $content | Should -Match "\[WARN\] Warning!"
    }
}

Describe "Test-GoldISOAdmin" {
    It "Returns true when running as administrator" -Skip:(-not ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        Test-GoldISOAdmin | Should -Be $true
    }
}

Describe "Test-GoldISOPath" {
    BeforeAll {
        $testDir = Join-Path $env:TEMP "GoldISO-PathTest-$(Get-Random)"
        New-Item -ItemType Directory -Path $testDir -Force | Out-Null
        $testFile = Join-Path $testDir "test.txt"
        "test content" | Set-Content $testFile
    }

    AfterAll {
        if (Test-Path $testDir) { Remove-Item $testDir -Recurse -Force }
    }

    It "Returns true for existing file with Type File" {
        Test-GoldISOPath -Path $testFile -Type "File" | Should -Be $true
    }

    It "Returns true for existing directory with Type Directory" {
        Test-GoldISOPath -Path $testDir -Type "Directory" | Should -Be $true
    }

    It "Returns false for file when checking as Directory" {
        Test-GoldISOPath -Path $testFile -Type "Directory" | Should -Be $false
    }

    It "Returns false for non-existent path" {
        $nonExistent = Join-Path $env:TEMP "GoldISO-NonExistent-$(Get-Random)"
        Test-GoldISOPath -Path $nonExistent | Should -Be $false
    }

    It "Creates directory when CreateIfMissing specified" {
        $newDir = Join-Path $env:TEMP "GoldISO-NewDir-$(Get-Random)"
        Test-GoldISOPath -Path $newDir -Type "Directory" -CreateIfMissing | Should -Be $true
        Test-Path $newDir | Should -Be $true
        if (Test-Path $newDir) { Remove-Item $newDir -Force }
    }
}

Describe "Format-GoldISOSize" {
    It "Formats bytes as B" {
        Format-GoldISOSize -Bytes 512 | Should -Be "512.00 B"
    }

    It "Formats bytes as KB" {
        Format-GoldISOSize -Bytes 1536 | Should -Be "1.50 KB"
    }

    It "Formats bytes as MB" {
        Format-GoldISOSize -Bytes (2 * 1024 * 1024) | Should -Be "2.00 MB"
    }

    It "Formats bytes as GB" {
        Format-GoldISOSize -Bytes ([math]::Pow(1024, 3) * 4.5) | Should -Be "4.50 GB"
    }

    It "Formats bytes as TB" {
        Format-GoldISOSize -Bytes ([math]::Pow(1024, 4) * 2) | Should -Be "2.00 TB"
    }

    It "Respects custom decimal places" {
        Format-GoldISOSize -Bytes ([math]::Pow(1024, 3) * 1.2345) -DecimalPlaces 4 | Should -Be "1.2345 GB"
    }
}

Describe "Test-GoldISOWinPE" {
    It "Returns false when not in WinPE" {
        # Assuming we're running on a normal Windows system
        Test-GoldISOWinPE | Should -Be $false
    }
}

Describe "Get-GoldISORoot" {
    It "Returns a path" {
        $root = Get-GoldISORoot
        $root | Should -Not -BeNullOrEmpty
        $root.ToString() | Should -BeOfType [string]
    }
}

AfterAll {
    Remove-Module GoldISO-Common -Force -ErrorAction SilentlyContinue
}
