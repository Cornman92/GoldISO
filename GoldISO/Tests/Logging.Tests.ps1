#Requires -Version 5.1
<#
.SYNOPSIS
    Comprehensive tests for GoldISO centralized logging system.
.DESCRIPTION
    Tests all log levels, file output formatting, console color output,
    auto-initialization, and backward compatibility.
#>

BeforeAll {
    # Import the module under test
    $modulePath = Join-Path $PSScriptRoot "..\Scripts\Modules\GoldISO-Common.psm1"
    Import-Module $modulePath -Force

    # Test log directory
    $script:TestLogDir = Join-Path $env:TEMP "GoldISO-Tests-$(Get-Random)"
    $script:TestLogFile = Join-Path $TestLogDir "test.log"

    # Ensure test directory exists
    if (-not (Test-Path $TestLogDir)) {
        New-Item -ItemType Directory -Path $TestLogDir -Force | Out-Null
    }
}

AfterAll {
    # Cleanup test directory
    if (Test-Path $TestLogDir) {
        Remove-Item -Path $TestLogDir -Recurse -Force -ErrorAction SilentlyContinue
    }
}

Describe "Initialize-Logging" {
    It "Should create log file when initialized" {
        $testFile = Join-Path $TestLogDir "init-test.log"
        Initialize-Logging -LogPath $testFile
        $testFile | Should -Exist
    }

    It "Should create log directory if it doesn't exist" {
        $newDir = Join-Path $TestLogDir "NewDir$(Get-Random)"
        $testFile = Join-Path $newDir "test.log"
        Initialize-Logging -LogPath $testFile
        $newDir | Should -Exist
        $testFile | Should -Exist
    }

    It "Should write initialization entry to log file" {
        $testFile = Join-Path $TestLogDir "init-entry.log"
        Initialize-Logging -LogPath $testFile
        $content = Get-Content $testFile -Raw
        $content | Should -Match "\[INIT\]"
    }
}

Describe "Write-GoldISOLog - Log Levels" {
    BeforeEach {
        $script:LevelTestFile = Join-Path $TestLogDir "levels-$(Get-Random).log"
        Initialize-Logging -LogPath $LevelTestFile
    }

    It "Should log INFO level correctly" {
        Write-GoldISOLog -Message "Test INFO message" -Level "INFO"
        $content = Get-Content $LevelTestFile -Raw
        $content | Should -Match "\[INFO\] Test INFO message"
    }

    It "Should log WARN level correctly" {
        Write-GoldISOLog -Message "Test WARN message" -Level "WARN"
        $content = Get-Content $LevelTestFile -Raw
        $content | Should -Match "\[WARN\] Test WARN message"
    }

    It "Should log WARNING level (normalized to WARN) correctly" {
        Write-GoldISOLog -Message "Test WARNING message" -Level "WARNING"
        $content = Get-Content $LevelTestFile -Raw
        $content | Should -Match "\[WARN\] Test WARNING message"
    }

    It "Should log ERROR level correctly" {
        Write-GoldISOLog -Message "Test ERROR message" -Level "ERROR"
        $content = Get-Content $LevelTestFile -Raw
        $content | Should -Match "\[ERROR\] Test ERROR message"
    }

    It "Should log SUCCESS level correctly" {
        Write-GoldISOLog -Message "Test SUCCESS message" -Level "SUCCESS"
        $content = Get-Content $LevelTestFile -Raw
        $content | Should -Match "\[SUCCESS\] Test SUCCESS message"
    }

    It "Should log SKIP level correctly" {
        Write-GoldISOLog -Message "Test SKIP message" -Level "SKIP"
        $content = Get-Content $LevelTestFile -Raw
        $content | Should -Match "\[SKIP\] Test SKIP message"
    }

    It "Should log DEBUG level correctly (when enabled)" {
        # DEBUG only logs when explicitly enabled
        $testFile = Join-Path $TestLogDir "debug-test-$(Get-Random).log"
        Initialize-Logging -LogPath $testFile
        # Enable debug logging in module scope
        & (Get-Module GoldISO-Common) { $script:DebugLoggingEnabled = $true }
        Write-GoldISOLog -Message "Test DEBUG message" -Level "DEBUG"
        $content = Get-Content $testFile -Raw
        $content | Should -Match "\[DEBUG\] Test DEBUG message"
        # Disable debug logging
        & (Get-Module GoldISO-Common) { $script:DebugLoggingEnabled = $false }
    }

    It "Should default to INFO level when not specified" {
        Write-GoldISOLog -Message "Default level test"
        $content = Get-Content $LevelTestFile -Raw
        $content | Should -Match "\[INFO\] Default level test"
    }
}

Describe "Write-GoldISOLog - File Output" {
    It "Should write timestamp in correct format" {
        $testFile = Join-Path $TestLogDir "timestamp.log"
        Initialize-Logging -LogPath $testFile
        Write-GoldISOLog -Message "Timestamp test"
        $content = Get-Content $testFile | Select-Object -Last 1
        # Should match format: [yyyy-MM-dd HH:mm:ss] [LEVEL] Message
        $content | Should -Match "^\[\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}\] \[\w+\]"
    }

    It "Should append to existing log file" {
        $testFile = Join-Path $TestLogDir "append.log"
        Initialize-Logging -LogPath $testFile
        Write-GoldISOLog -Message "First entry"
        Write-GoldISOLog -Message "Second entry"
        $content = Get-Content $testFile
        $content.Count | Should -BeGreaterThan 2 # INIT + 2 messages
        $raw = $content -join "\n"
        $raw | Should -Match "\[INFO\] First entry"
        $raw | Should -Match "\[INFO\] Second entry"
    }

    It "Should use UTF8 encoding" {
        $testFile = Join-Path $TestLogDir "encoding.log"
        Initialize-Logging -LogPath $testFile
        Write-GoldISOLog -Message "UTF8 test: ñáéíóú"
        $rawBytes = [System.IO.File]::ReadAllBytes($testFile)
        # Check for UTF8 BOM or UTF8 encoded characters
        $hasUtf8 = ($rawBytes[0] -eq 0xEF -and $rawBytes[1] -eq 0xBB -and $rawBytes[2] -eq 0xBF) -or
                   ($rawBytes -contains 0xC3) # Common UTF8 multi-byte indicator
        $hasUtf8 | Should -Be $true
    }
}

Describe "Write-GoldISOLog - NoConsole Switch" {
    It "Should not write to console when NoConsole is specified" {
        $testFile = Join-Path $TestLogDir "noconsole.log"
        Initialize-Logging -LogPath $testFile
        # Capture console output
        $output = Write-GoldISOLog -Message "NoConsole test" -NoConsole 2>&1
        $output | Should -BeNullOrEmpty
    }
}

Describe "Write-GoldISOLog - Auto-Initialization" {
    It "Should auto-initialize when logging without explicit initialization" {
        # Reset module state to test auto-init
        $script:LogInitialized = $false
        $script:LogFile = $null

        # This should auto-initialize with default path
        { Write-GoldISOLog -Message "Auto-init test" } | Should -Not -Throw
    }
}

Describe "Write-Log Alias" {
    It "Should have Write-Log as an alias for Write-GoldISOLog" {
        $alias = Get-Alias -Name "Write-Log" -ErrorAction SilentlyContinue
        $alias | Should -Not -BeNullOrEmpty
        $alias.Definition | Should -Be "Write-GoldISOLog"
    }

    It "Should work via Write-Log alias" {
        $testFile = Join-Path $TestLogDir "alias.log"
        Initialize-Logging -LogPath $testFile
        Write-Log -Message "Alias test message" -Level "INFO"
        $content = Get-Content $testFile -Raw
        $content | Should -Match "Alias test message"
    }
}

Describe "Log File Path Handling" {
    It "Should handle paths with spaces" {
        $dirWithSpaces = Join-Path $TestLogDir "Path With Spaces"
        New-Item -ItemType Directory -Path $dirWithSpaces -Force | Out-Null
        $testFile = Join-Path $dirWithSpaces "test log.log"
        Initialize-Logging -LogPath $testFile
        Write-GoldISOLog -Message "Path with spaces test"
        $testFile | Should -Exist
    }

    It "Should handle long paths gracefully" {
        $longPath = Join-Path $TestLogDir ("A" * 50) | Join-Path -ChildPath "test.log"
        { Initialize-Logging -LogPath $longPath } | Should -Not -Throw
    }
}
