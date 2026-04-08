#Requires -Version 5.1
<#
.SYNOPSIS
    Build time measurement and optimization analysis.

.DESCRIPTION
    Measures and analyzes GoldISO build times, identifying bottlenecks
    and providing optimization recommendations. Maintains historical data
    for trend analysis.

.PARAMETER BuildPath
    Path to build output for analysis.

.PARAMETER AnalyzeHistory
    Analyze historical build times from logs.

.PARAMETER CompareTo
    Previous build log for comparison.

.PARAMETER GenerateTrends
    Generate trend charts (requires charting library).

.EXAMPLE
    .\Measure-BuildTime.ps1 -AnalyzeHistory -GenerateTrends

.EXAMPLE
    .\Measure-BuildTime.ps1 -BuildPath "C:\GoldISO-Build"
#>
[CmdletBinding()]
param(
    [string]$BuildPath,
    [switch]$AnalyzeHistory,
    [string]$CompareTo,
    [switch]$GenerateTrends
)

#region ─────────────────────────────────────────────────────────────────────────────
# Initialization
# ─────────────────────────────────────────────────────────────────────────────

$ErrorActionPreference = "Stop"
$script:StartTime = Get-Date

$commonModule = Join-Path $PSScriptRoot "Modules\GoldISO-Common.psm1"
if (Test-Path $commonModule) {
    Import-Module $commonModule -Force
}

$script:LogDir = Join-Path $PSScriptRoot "..\Logs\BuildMetrics"
$timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
New-Item -ItemType Directory -Path $script:LogDir -Force -ErrorAction SilentlyContinue | Out-Null

$script:Metrics = @{
    Timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    Phases = [System.Collections.Generic.List[hashtable]]::new()
    Recommendations = [System.Collections.Generic.List[string]]::new()
}

function Write-MetricLog {
    param([string]$Message, [ValidateSet("INFO","WARN","ERROR","SUCCESS","PHASE")][string]$Level = "INFO")
    $ts = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $entry = "[$ts] [$Level] $Message"
    $color = switch ($Level) {
        "ERROR" { "Red" }
        "WARN" { "Yellow" }
        "SUCCESS" { "Green" }
        "PHASE" { "Cyan" }
        default { "White" }
    }
    Write-Host $entry -ForegroundColor $color
}

Write-MetricLog "Build Time Analysis Started" "PHASE"

#endregion

#region ─────────────────────────────────────────────────────────────────────────────
# Log Parsing
# ─────────────────────────────────────────────────────────────────────────────

function Get-BuildPhasesFromLog {
    param([string]$LogPath)

    if (-not (Test-Path $LogPath)) {
        Write-MetricLog "Log file not found: $LogPath" "ERROR"
        return $null
    }

    $phases = [System.Collections.Generic.List[hashtable]]::new()
    $content = Get-Content $LogPath

    # Common build phase patterns
    $phasePatterns = @(
        @{ Name = "Validation"; StartPattern = "Starting.*[Vv]alidation|Validating.*environment"; EndPattern = "Validation.*complete|Validation.*done" }
        @{ Name = "DISM Mount"; StartPattern = "Mount.*WIM|Mounting.*image"; EndPattern = "Image.*mounted|Mount.*complete" }
        @{ Name = "DISM Operations"; StartPattern = "Adding.*package|Applying.*package|DISM.*Add-Package"; EndPattern = "Package.*added|DISM.*complete" }
        @{ Name = "File Copy"; StartPattern = "Copying.*files|Copy.*unattend|Adding.*files"; EndPattern = "Files.*copied|Copy.*complete" }
        @{ Name = "ISO Creation"; StartPattern = "Creating.*ISO|oscdimg|Building.*ISO"; EndPattern = "ISO.*created|Build.*complete|oscdimg.*complete" }
    )

    foreach ($pattern in $phasePatterns) {
        $startMatch = $content | Select-String $pattern.StartPattern | Select-Object -First 1
        $endMatch = $content | Select-String $pattern.EndPattern | Select-Object -First 1

        if ($startMatch -and $endMatch) {
            $startTime = $startMatch.Line -match '\[(\d{2}:\d{2}:\d{2})\]' | ForEach-Object { $matches[1] }
            $endTime = $endMatch.Line -match '\[(\d{2}:\d{2}:\d{2})\]' | ForEach-Object { $matches[1] }

            if ($startTime -and $endTime) {
                try {
                    $start = [DateTime]::ParseExact($startTime, "HH:mm:ss", $null)
                    $end = [DateTime]::ParseExact($endTime, "HH:mm:ss", $null)
                    $duration = $end - $start

                    $phases.Add(@{
                        Name = $pattern.Name
                        StartTime = $startTime
                        EndTime = $endTime
                        Duration = $duration
                        DurationSeconds = [math]::Round($duration.TotalSeconds, 0)
                    })
                }
                catch {}
            }
        }
    }

    return $phases
}

function Get-HistoricalBuilds {
    $logPattern = Join-Path (Join-Path $PSScriptRoot "..\Logs") "Build-GoldISO-*.log"
    $logs = Get-ChildItem $logPattern -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending | Select-Object -First 10

    $history = @()
    foreach ($log in $logs) {
        $phases = Get-BuildPhasesFromLog $log.FullName
        if ($phases.Count -gt 0) {
            $totalSeconds = ($phases | Measure-Object -Property DurationSeconds -Sum).Sum
            $history += @{
                Date = $log.LastWriteTime
                LogFile = $log.Name
                TotalSeconds = $totalSeconds
                TotalMinutes = [math]::Round($totalSeconds / 60, 1)
                Phases = $phases.Count
            }
        }
    }

    return $history
}

#endregion

#region ─────────────────────────────────────────────────────────────────────────────
# Analysis Functions
# ─────────────────────────────────────────────────────────────────────────────

function Test-BuildBottlenecks {
    param([array]$Phases)

    Write-MetricLog "Analyzing build bottlenecks..." "INFO"
    $bottlenecks = @()

    if ($Phases.Count -eq 0) { return $bottlenecks }

    $totalTime = ($Phases | Measure-Object -Property DurationSeconds -Sum).Sum
    $avgPhaseTime = $totalTime / $Phases.Count

    foreach ($phase in $Phases) {
        $percentOfTotal = [math]::Round(($phase.DurationSeconds / $totalTime) * 100, 1)

        # Identify bottlenecks (phases taking >30% of total or >5 min)
        if ($phase.DurationSeconds -gt ($avgPhaseTime * 2) -or $phase.DurationSeconds -gt 300) {
            $bottlenecks += @{
                Phase = $phase.Name
                Duration = $phase.Duration
                PercentOfTotal = $percentOfTotal
                Severity = if ($percentOfTotal -gt 40) { "Critical" } elseif ($percentOfTotal -gt 25) { "High" } else { "Medium" }
            }

            if ($percentOfTotal -gt 40) {
                $script:Metrics.Recommendations.Add("CRITICAL: $($phase.Name) takes $percentOfTotal% of build time - Consider optimization")
            }
            elseif ($percentOfTotal -gt 25) {
                $script:Metrics.Recommendations.Add("Optimize $($phase.Name) - accounts for $percentOfTotal% of build time")
            }
        }
    }

    return $bottlenecks
}

function Get-OptimizationTips {
    param([array]$Phases)

    $tips = @()

    # Analyze specific phases
    $dismPhase = $Phases | Where-Object { $_.Name -like "*DISM*" } | Sort-Object DurationSeconds -Descending | Select-Object -First 1
    if ($dismPhase -and $dismPhase.DurationSeconds -gt 180) {
        $tips += "DISM operations are slow - consider using SSD for temp directory"
        $tips += "Consider parallel DISM operations if not already optimized"
    }

    $isoPhase = $Phases | Where-Object { $_.Name -like "*ISO*" } | Select-Object -First 1
    if ($isoPhase -and $isoPhase.DurationSeconds -gt 120) {
        $tips += "ISO creation is slow - ensure output is on fast storage"
        $tips += "Consider using RAM disk for temp files during ISO creation"
    }

    $copyPhase = $Phases | Where-Object { $_.Name -like "*Copy*" } | Select-Object -First 1
    if ($copyPhase -and $copyPhase.DurationSeconds -gt 60) {
        $tips += "File copy operations taking significant time - check source storage speed"
    }

    return $tips
}

function Compare-BuildToBaseline {
    param(
        [array]$CurrentPhases,
        [string]$BaselineLog
    )

    if (-not (Test-Path $BaselineLog)) {
        Write-MetricLog "Baseline log not found: $BaselineLog" "WARN"
        return $null
    }

    Write-MetricLog "Comparing to baseline: $BaselineLog" "INFO"
    $baselinePhases = Get-BuildPhasesFromLog $BaselineLog

    $comparison = @{
        BaselineTotal = ($baselinePhases | Measure-Object -Property DurationSeconds -Sum).Sum
        CurrentTotal = ($CurrentPhases | Measure-Object -Property DurationSeconds -Sum).Sum
        PhaseComparisons = @()
    }

    $comparison.Difference = $comparison.CurrentTotal - $comparison.BaselineTotal
    $comparison.PercentChange = if ($comparison.BaselineTotal -gt 0) {
        [math]::Round(($comparison.Difference / $comparison.BaselineTotal) * 100, 1)
    } else { 0 }

    foreach ($current in $CurrentPhases) {
        $baseline = $baselinePhases | Where-Object { $_.Name -eq $current.Name } | Select-Object -First 1
        if ($baseline) {
            $diff = $current.DurationSeconds - $baseline.DurationSeconds
            $comparison.PhaseComparisons += @{
                Phase = $current.Name
                BaselineSeconds = $baseline.DurationSeconds
                CurrentSeconds = $current.DurationSeconds
                Difference = $diff
                PercentChange = if ($baseline.DurationSeconds -gt 0) {
                    [math]::Round(($diff / $baseline.DurationSeconds) * 100, 1)
                } else { 0 }
            }
        }
    }

    return $comparison
}

#endregion

#region ─────────────────────────────────────────────────────────────────────────────
# Report Generation
# ─────────────────────────────────────────────────────────────────────────────

function Export-AnalysisReport {
    param(
        [array]$Phases,
        [array]$Bottlenecks,
        [hashtable]$Comparison
    )

    $totalTime = ($Phases | Measure-Object -Property DurationSeconds -Sum).Sum

    $report = @"
===============================================
    BUILD TIME ANALYSIS REPORT
===============================================
Generated: $(Get-Date -Format "yyyy-MM-dd HH:mm:ss")
Computer: $env:COMPUTERNAME

SUMMARY
-------
Total Build Time: $([math]::Round($totalTime / 60, 1)) minutes ($totalTime seconds)
Phases Analyzed: $($Phases.Count)

BUILD PHASES
------------
"@

    foreach ($phase in ($Phases | Sort-Object DurationSeconds -Descending)) {
        $percent = [math]::Round(($phase.DurationSeconds / $totalTime) * 100, 1)
        $report += "  $($phase.Name.PadRight(20)): $($phase.Duration.ToString('mm\:ss')) ($percent%)`n"
    }

    if ($Bottlenecks.Count -gt 0) {
        $report += @"

BOTTLENECKS IDENTIFIED
----------------------
"@
        foreach ($bn in $Bottlenecks) {
            $report += "  [$($bn.Severity)] $($bn.Phase): $($bn.Duration.ToString('mm\:ss')) ($($bn.PercentOfTotal)%)`n"
        }
    }

    if ($Comparison) {
        $report += @"

BASELINE COMPARISON
-------------------
Baseline: $([math]::Round($Comparison.BaselineTotal / 60, 1)) min
Current: $([math]::Round($Comparison.CurrentTotal / 60, 1)) min
Difference: $([math]::Round($Comparison.Difference, 0)) seconds ($($Comparison.PercentChange)%)
"@
        if ($Comparison.PhaseComparisons.Count -gt 0) {
            $report += "`nPhase Changes:`n"
            foreach ($pc in $Comparison.PhaseComparisons) {
                $arrow = if ($pc.PercentChange -gt 0) { "▲" } elseif ($pc.PercentChange -lt 0) { "▼" } else { "=" }
                $report += "  $($pc.Phase.PadRight(20)): $arrow $($pc.PercentChange)% ($($pc.CurrentSeconds)s vs $($pc.BaselineSeconds)s)`n"
            }
        }
    }

    if ($script:Metrics.Recommendations.Count -gt 0) {
        $report += @"

RECOMMENDATIONS
---------------
"@
        foreach ($rec in $script:Metrics.Recommendations) {
            $report += "  • $rec`n"
        }
    }

    $tips = Get-OptimizationTips $Phases
    if ($tips.Count -gt 0) {
        $report += @"

OPTIMIZATION TIPS
-----------------
"@
        foreach ($tip in $tips) {
            $report += "  • $tip`n"
        }
    }

    $report += @"

===============================================
"@

    $reportFile = Join-Path $script:LogDir "BuildAnalysis-$timestamp.txt"
    $report | Set-Content $reportFile -Encoding UTF8

    Write-Host $report -ForegroundColor Cyan
    Write-MetricLog "Analysis report saved: $reportFile" "SUCCESS"

    return $reportFile
}

#endregion

#region ─────────────────────────────────────────────────────────────────────────────
# Main Execution
# ─────────────────────────────────────────────────────────────────────────────

if ($AnalyzeHistory) {
    $history = Get-HistoricalBuilds
    Write-MetricLog "Found $($history.Count) historical builds" "INFO"

    if ($history.Count -gt 0) {
        Write-MetricLog "Historical build times:" "INFO"
        foreach ($build in $history) {
            Write-MetricLog "  $($build.Date.ToString('yyyy-MM-dd')): $($build.TotalMinutes) min - $($build.LogFile)" "INFO"
        }

        # Calculate trends
        if ($history.Count -ge 3) {
            $avgTime = ($history | Measure-Object -Property TotalMinutes -Average).Average
            $trend = if ($history[0].TotalMinutes -gt $avgTime) { "increasing" } else { "decreasing" }
            Write-MetricLog "Average build time: $([math]::Round($avgTime, 1)) min (trend: $trend)" "INFO"
        }
    }
}

if ($BuildPath) {
    $logFile = Join-Path $BuildPath "build.log"
    if (-not (Test-Path $logFile)) {
        $logFile = Get-ChildItem $BuildPath -Filter "*.log" | Select-Object -First 1 | ForEach-Object { $_.FullName }
    }

    if (Test-Path $logFile) {
        $phases = Get-BuildPhasesFromLog $logFile
        $script:Metrics.Phases = $phases

        $bottlenecks = Test-BuildBottlenecks $phases
        $comparison = $null
        if ($CompareTo) {
            $comparison = Compare-BuildToBaseline -CurrentPhases $phases -BaselineLog $CompareTo
        }

        Export-AnalysisReport -Phases $phases -Bottlenecks $bottlenecks -Comparison $comparison
    }
    else {
        Write-MetricLog "No build log found in: $BuildPath" "ERROR"
    }
}
elseif (-not $AnalyzeHistory) {
    # Check for most recent build log
    $recentLog = Get-ChildItem (Join-Path $PSScriptRoot "..\Logs") -Filter "Build-GoldISO-*.log" |
        Sort-Object LastWriteTime -Descending |
        Select-Object -First 1

    if ($recentLog) {
        Write-MetricLog "Analyzing most recent build: $($recentLog.Name)" "INFO"
        $phases = Get-BuildPhasesFromLog $recentLog.FullName
        $script:Metrics.Phases = $phases
        $bottlenecks = Test-BuildBottlenecks $phases
        Export-AnalysisReport -Phases $phases -Bottlenecks $bottlenecks -Comparison $null
    }
    else {
        Write-MetricLog "No build logs found for analysis" "WARN"
        Write-MetricLog "Run this script after a build or use -BuildPath to specify a log location" "INFO"
    }
}

$duration = (Get-Date) - $script:StartTime
Write-MetricLog "Analysis complete in $($duration.ToString('ss')) seconds" "SUCCESS"
