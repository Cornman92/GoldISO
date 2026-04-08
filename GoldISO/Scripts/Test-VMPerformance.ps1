#Requires -Version 5.1
<#
.SYNOPSIS
    Performance testing utility for GoldISO VMs and systems.

.DESCRIPTION
    Runs standardized performance tests including disk I/O, memory throughput,
    CPU benchmarks, and network latency. Generates comparative performance reports.

.PARAMETER Duration
    Test duration in seconds. Default: 60

.PARAMETER OutputPath
    Directory to save test results. Default: $PSScriptRoot\..\Logs

.PARAMETER BaselinePath
    Path to baseline results for comparison.

.PARAMETER IncludeStressTest
    Include stress testing components.

.EXAMPLE
    .\Test-VMPerformance.ps1 -Duration 120

.EXAMPLE
    .\Test-VMPerformance.ps1 -BaselinePath ".\baseline-results.json"
#>
[CmdletBinding()]
param(
    [int]$Duration = 60,
    [string]$OutputPath = (Join-Path $PSScriptRoot "..\Logs"),
    [string]$BaselinePath,
    [switch]$IncludeStressTest
)

#region ─────────────────────────────────────────────────────────────────────────────
# Initialization
# ─────────────────────────────────────────────────────────────────────────────

$ErrorActionPreference = "Stop"
$script:Results = @{
    Timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    ComputerName = $env:COMPUTERNAME
    Duration = $Duration
    Tests = @{}
    Score = 0
}

$commonModule = Join-Path $PSScriptRoot "Modules\GoldISO-Common.psm1"
if (Test-Path $commonModule) {
    Import-Module $commonModule -Force
}

$timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
if (-not (Test-Path $OutputPath)) {
    New-Item -ItemType Directory -Path $OutputPath -Force | Out-Null
}

$script:LogFile = Join-Path $OutputPath "PerfTest-$timestamp.log"

function Write-PerfLog {
    param([string]$Message, [ValidateSet("INFO","WARN","ERROR","SUCCESS")][string]$Level = "INFO")
    $ts = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $entry = "[$ts] [$Level] $Message"
    Write-Host $entry -ForegroundColor $(switch($Level) { "ERROR"{"Red"} "WARN"{"Yellow"} "SUCCESS"{"Green"} default{"White"} })
    Add-Content -Path $script:LogFile -Value $entry -ErrorAction SilentlyContinue
}

Write-PerfLog "Performance Test Started" "INFO"
Write-PerfLog "Duration: $Duration seconds | Computer: $env:COMPUTERNAME" "INFO"

#endregion

#region ─────────────────────────────────────────────────────────────────────────────
# Test Functions
# ─────────────────────────────────────────────────────────────────────────────

function Test-CPUPerformance {
    Write-PerfLog "Testing CPU performance..." "INFO"

    $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
    $iterations = 0
    $primeLimit = 10000

    while ($stopwatch.Elapsed.TotalSeconds -lt ($Duration / 4)) {
        # Prime number calculation (dummy work)
        $sum = 0
        for ($i = 2; $i -lt $primeLimit; $i++) {
            $sum += $i
        }
        $iterations++
    }
    $stopwatch.Stop()

    $elapsed = $stopwatch.Elapsed.TotalSeconds
    $opsPerSecond = [math]::Round($iterations / $elapsed, 2)

    $cpuInfo = Get-CimInstance Win32_Processor | Select-Object -First 1

    $result = @{
        Score = [math]::Round($opsPerSecond * 100)
        Iterations = $iterations
        Duration = $elapsed
        OpsPerSecond = $opsPerSecond
        Processor = $cpuInfo.Name
        Cores = $cpuInfo.NumberOfCores
        LogicalProcessors = $cpuInfo.NumberOfLogicalProcessors
    }

    Write-PerfLog "CPU: $iterations iterations in $([math]::Round($elapsed, 1))s ($opsPerSecond ops/s)" "SUCCESS"
    return $result
}

function Test-MemoryPerformance {
    Write-PerfLog "Testing memory performance..." "INFO"

    $sizeMB = 100
    $arraySize = $sizeMB * 1024 * 1024 / 8  # 8 bytes per long
    $iterations = 0

    $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()

    # Write test
    $data = [long[]]::new($arraySize)
    for ($i = 0; $i -lt $arraySize; $i++) {
        $data[$i] = $i
    }

    # Read test
    $sum = 0
    for ($i = 0; $i -lt $arraySize; $i++) {
        $sum += $data[$i]
    }

    # Copy test
    $copy = [long[]]::new($arraySize)
    [Array]::Copy($data, $copy, $arraySize)

    $stopwatch.Stop()
    $elapsed = $stopwatch.Elapsed.TotalSeconds

    $totalBytes = $sizeMB * 1024 * 1024 * 3  # Write + Read + Copy
    $throughput = [math]::Round($totalBytes / $elapsed / 1024 / 1024, 2)

    $memInfo = Get-CimInstance Win32_PhysicalMemory | Measure-Object -Property Capacity -Sum

    $result = @{
        Score = [math]::Round($throughput * 10)
        ThroughputMBps = $throughput
        TestSizeMB = $sizeMB * 3
        Duration = $elapsed
        TotalMemoryGB = [math]::Round($memInfo.Sum / 1GB, 2)
    }

    Write-PerfLog "Memory: $throughput MB/s throughput" "SUCCESS"
    return $result
}

function Test-DiskPerformance {
    Write-PerfLog "Testing disk I/O performance..." "INFO"

    $testFile = "$env:TEMP\perftest_$(Get-Random).dat"
    $fileSize = 500MB
    $blockSize = 64KB

    try {
        # Sequential Write Test
        $buffer = New-Object byte[] $blockSize
        $rng = [System.Security.Cryptography.RNGCryptoServiceProvider]::Create()
        $rng.GetBytes($buffer)

        $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
        $fileStream = [System.IO.FileStream]::new($testFile, [System.IO.FileMode]::Create, [System.IO.FileAccess]::Write, [System.IO.FileShare]::None, $blockSize, [System.IO.FileOptions]::SequentialScan)

        for ($i = 0; $i -lt ($fileSize / $blockSize); $i++) {
            $fileStream.Write($buffer, 0, $blockSize)
        }
        $fileStream.Flush()
        $stopwatch.Stop()
        $fileStream.Close()

        $writeTime = $stopwatch.Elapsed.TotalSeconds
        $writeSpeed = [math]::Round($fileSize / $writeTime / 1024 / 1024, 2)

        # Sequential Read Test
        $stopwatch.Restart()
        $fileStream = [System.IO.FileStream]::new($testFile, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::Read, $blockSize, [System.IO.FileOptions]::SequentialScan)
        while ($fileStream.Read($buffer, 0, $blockSize) -gt 0) { }
        $stopwatch.Stop()
        $fileStream.Close()

        $readTime = $stopwatch.Elapsed.TotalSeconds
        $readSpeed = [math]::Round($fileSize / $readTime / 1024 / 1024, 2)

        # Get disk info
        $disk = Get-PhysicalDisk | Where-Object { $_.DeviceId -eq 0 }

        $result = @{
            Score = [math]::Round(($readSpeed + $writeSpeed) * 5)
            WriteSpeedMBps = $writeSpeed
            ReadSpeedMBps = $readSpeed
            TestFileSizeMB = [math]::Round($fileSize / 1MB)
            WriteDuration = $writeTime
            ReadDuration = $readTime
            DiskType = $disk.MediaType
            DiskModel = $disk.FriendlyName
        }

        Write-PerfLog "Disk: Write $writeSpeed MB/s, Read $readSpeed MB/s" "SUCCESS"
    }
    finally {
        if (Test-Path $testFile) {
            Remove-Item $testFile -Force -ErrorAction SilentlyContinue
        }
    }

    return $result
}

function Test-NetworkLatency {
    Write-PerfLog "Testing network latency..." "INFO"

    $pingTargets = @("8.8.8.8", "1.1.1.1", "cloudflare.com")
    $pingResults = @()
    $totalAvg = 0

    foreach ($target in $pingTargets) {
        try {
            $pings = Test-Connection -ComputerName $target -Count 4 -ErrorAction SilentlyContinue
            if ($pings) {
                $avg = [math]::Round(($pings | Measure-Object -Property Latency -Average).Average, 2)
                $loss = [math]::Round((1 - ($pings.Count / 4)) * 100, 1)
                $pingResults += @{
                    Target = $target
                    AverageLatency = $avg
                    PacketLoss = $loss
                }
                $totalAvg += $avg
            }
        }
        catch {
            Write-PerfLog "Could not ping $target" "WARN"
        }
    }

    $overallAvg = if ($pingResults.Count -gt 0) { $totalAvg / $pingResults.Count } else { 0 }
    $score = if ($overallAvg -eq 0) { 0 } else { [math]::Max(0, 1000 - [math]::Round($overallAvg)) }

    $result = @{
        Score = $score
        AverageLatency = [math]::Round($overallAvg, 2)
        Results = $pingResults
    }

    Write-PerfLog "Network: Average latency $([math]::Round($overallAvg, 1)) ms" "SUCCESS"
    return $result
}

function Test-Stress {
    if (-not $IncludeStressTest) { return $null }

    Write-PerfLog "Running stress test for $Duration seconds..." "INFO"

    $startTime = Get-Date
    $cpuLoad = @()

    # Run parallel CPU stress
    $jobs = 1..($env:NUMBER_OF_PROCESSORS) | ForEach-Object {
        Start-Job -ScriptBlock {
            $end = (Get-Date).AddSeconds($using:Duration)
            while (Get-Date -lt $end) {
                # CPU stress
                for ($i = 0; $i -lt 1000000; $i++) { [math]::Sqrt($i) | Out-Null }
            }
        }
    }

    # Monitor during stress
    while ((Get-Date) -lt $startTime.AddSeconds($Duration)) {
        $cpu = (Get-Counter '\Processor(_Total)\% Processor Time' -SampleInterval 1 -MaxSamples 1).CounterSamples.CookedValue
        $cpuLoad += $cpu
        Start-Sleep -Milliseconds 500
    }

    $jobs | Stop-Job -ErrorAction SilentlyContinue
    $jobs | Remove-Job -ErrorAction SilentlyContinue

    $avgCpu = [math]::Round(($cpuLoad | Measure-Object -Average).Average, 1)
    $maxCpu = [math]::Round(($cpuLoad | Measure-Object -Maximum).Maximum, 1)

    $result = @{
        Score = [math]::Round($avgCpu * 10)
        AverageCPULoad = $avgCpu
        MaxCPULoad = $maxCpu
        Duration = $Duration
    }

    Write-PerfLog "Stress: Average CPU $avgCpu%, Peak $maxCpu%" "SUCCESS"
    return $result
}

#endregion

#region ─────────────────────────────────────────────────────────────────────────────
# Comparison & Reporting
# ─────────────────────────────────────────────────────────────────────────────

function Compare-ToBaseline {
    param([hashtable]$CurrentResults)

    if (-not $BaselinePath -or -not (Test-Path $BaselinePath)) { return }

    Write-PerfLog "Comparing to baseline: $BaselinePath" "INFO"

    try {
        $baseline = Get-Content $BaselinePath | ConvertFrom-Json

        $comparison = @{}
        foreach ($test in $CurrentResults.Tests.Keys) {
            $current = $CurrentResults.Tests[$test].Score
            $base = $baseline.Tests.$test.Score

            if ($base -and $base -gt 0) {
                $diff = [math]::Round((($current - $base) / $base) * 100, 1)
                $comparison[$test] = @{
                    Current = $current
                    Baseline = $base
                    Difference = $diff
                    Status = if ($diff -lt -10) { "Regression" } elseif ($diff -gt 10) { "Improvement" } else { "Similar" }
                }
            }
        }

        return $comparison
    }
    catch {
        Write-PerfLog "Could not compare to baseline: $_" "WARN"
        return $null
    }
}

function Export-Results {
    $reportPath = Join-Path $OutputPath "PerfTest-Results-$timestamp.json"
    $script:Results | ConvertTo-Json -Depth 10 | Set-Content $reportPath -Encoding UTF8

    # Generate summary report
    Write-Host "`n========================================" -ForegroundColor Cyan
    Write-Host "    PERFORMANCE TEST RESULTS" -ForegroundColor Cyan
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host "Computer: $($env:COMPUTERNAME)"
    Write-Host "Duration: $Duration seconds"
    Write-Host "Timestamp: $($script:Results.Timestamp)"
    Write-Host "----------------------------------------" -ForegroundColor Gray

    foreach ($test in $script:Results.Tests.Keys) {
        $t = $script:Results.Tests[$test]
        Write-Host "$test Test:" -ForegroundColor Yellow
        Write-Host "  Score: $($t.Score)"
        switch ($test) {
            "CPU" {
                Write-Host "  Operations/sec: $($t.OpsPerSecond)"
                Write-Host "  Processor: $($t.Processor)"
            }
            "Memory" {
                Write-Host "  Throughput: $($t.ThroughputMBps) MB/s"
                Write-Host "  Total RAM: $($t.TotalMemoryGB) GB"
            }
            "Disk" {
                Write-Host "  Read: $($t.ReadSpeedMBps) MB/s | Write: $($t.WriteSpeedMBps) MB/s"
                Write-Host "  Disk: $($t.DiskType) - $($t.DiskModel)"
            }
            "Network" {
                Write-Host "  Latency: $($t.AverageLatency) ms"
            }
            "Stress" {
                Write-Host "  Avg CPU: $($t.AverageCPULoad)% | Peak: $($t.MaxCPULoad)%"
            }
        }
        Write-Host ""
    }

    Write-Host "----------------------------------------" -ForegroundColor Gray
    Write-Host "Overall Score: $($script:Results.Score)/1000" -ForegroundColor $(if($script:Results.Score -gt 700){"Green"}elseif($script:Results.Score -gt 400){"Yellow"}else{"Red"})
    Write-Host "Results saved to: $reportPath" -ForegroundColor Gray
    Write-Host "========================================" -ForegroundColor Cyan
}

#endregion

#region ─────────────────────────────────────────────────────────────────────────────
# Main Execution
# ─────────────────────────────────────────────────────────────────────────────

$script:Results.Tests.CPU = Test-CPUPerformance
$script:Results.Tests.Memory = Test-MemoryPerformance
$script:Results.Tests.Disk = Test-DiskPerformance
$script:Results.Tests.Network = Test-NetworkLatency
$stress = Test-Stress
if ($stress) { $script:Results.Tests.Stress = $stress }

# Calculate overall score
$totalScore = 0
$testCount = 0
foreach ($test in $script:Results.Tests.Values) {
    if ($test.Score) {
        $totalScore += $test.Score
        $testCount++
    }
}
$script:Results.Score = [math]::Min(1000, $totalScore)

# Compare to baseline
if ($BaselinePath) {
    $script:Results.Comparison = Compare-ToBaseline -CurrentResults $script:Results
}

Export-Results

Write-PerfLog "Performance test completed. Overall Score: $($script:Results.Score)/1000" "SUCCESS"
