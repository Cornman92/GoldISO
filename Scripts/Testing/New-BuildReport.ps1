#Requires -Version 5.1
<#
.SYNOPSIS
    Generates a detailed build report from build logs.
.DESCRIPTION
    Parses GoldISO build logs and generates an HTML report with:
    - Build duration and phases
    - Driver injection metrics
    - WIM size delta
    - Warnings and errors summary
    - Configuration summary
.PARAMETER BuildPath
    Path to the build directory containing logs.
.PARAMETER OutputPath
    Path for the output report. Default: build-report.html in same dir as logs.
.PARAMETER Format
    Output format: HTML, JSON, or Text. Default: HTML
.EXAMPLE
    .\New-BuildReport.ps1 -BuildPath "C:\GoldISO_Build" -Format HTML
.EXAMPLE
    .\New-BuildReport.ps1 -BuildPath "C:\GoldISO_Build" -OutputPath "C:\Reports\build.html"
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)]
    [string]$BuildPath,

    [string]$OutputPath = "",

    [ValidateSet("HTML", "JSON", "Text")]
    [string]$Format = "HTML"
)

$ErrorActionPreference = "Stop"

if (-not (Test-Path $BuildPath)) {
    Write-Error "Build path not found: $BuildPath"
    exit 1
}

$script:BuildRoot = $BuildPath
$script:ReportDir = Split-Path $BuildPath -Parent
if (-not $OutputPath) {
    $OutputPath = Join-Path $BuildPath "build-report.html"
}

$timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"

$logFiles = Get-ChildItem $BuildPath -Filter "*.log" -ErrorAction SilentlyContinue
$buildLog = $logFiles | Where-Object { $_.Name -match "GoldISO|Build|build" } | Select-Object -First 1
if (-not $buildLog) {
    $buildLog = $logFiles | Select-Object -First 1
}

$reportData = @{
    Timestamp = $timestamp
    BuildPath = $BuildPath
    Phases = @()
    Errors = @()
    Warnings = @()
    Config = @{}
}

if ($buildLog) {
    $content = Get-Content $buildLog.FullName -Raw -ErrorAction SilentlyContinue
    
    $phasePattern = '\[(\d+)/(\d+)\]\s*(.+?)(?:\s|$)|Phase\s+(\w+)'
    $phases = [regex]::Matches($content, $phasePattern)
    foreach ($p in $phases) {
        if ($p.Groups[3].Value) {
            $reportData.Phases += @{
                Name = $p.Groups[3].Value.Trim()
                Number = if ($p.Groups[1].Value) { [int]$p.Groups[1].Value } else { 0 }
            }
        }
    }

    $errorPattern = '\[ERROR\]|\[ERROR\s*\]|ERROR:|failed|Failed|Error'
    $errors = [regex]::Matches($content, $errorPattern)
    $reportData.Errors = @($errors.Count)

    $warningPattern = '\[WARN\]|WARNING:|Warning'
    $warnings = [regex]::Matches($content, $warningPattern)
    $reportData.Warnings = @($warnings.Count)

    $durationPattern = 'Duration.*?(\d+\.?\d*)\s*(seconds|minutes|hours|sec|min|hr)'
    $durMatch = [regex]::Match($content, $durationPattern)
    if ($durMatch.Success) {
        $reportData.Duration = $durMatch.Value
    }
}

if ($Format -eq "JSON") {
    $reportData | ConvertTo-Json -Depth 5 | Set-Content $OutputPath -Encoding UTF8
    Write-Host "JSON report saved: $OutputPath" -ForegroundColor Green
    exit 0
}

if ($Format -eq "Text") {
    $lines = @()
    $lines += "=" * 60
    $lines += "GoldISO Build Report"
    $lines += "=" * 60
    $lines += "Timestamp: $($reportData.Timestamp)"
    $lines += "Build Path: $($reportData.BuildPath)"
    if ($reportData.Duration) { $lines += "Duration: $($reportData.Duration)" }
    $lines += ""
    $lines += "Phases: $($reportData.Phases.Count)"
    $lines += "Errors: $($reportData.Errors[0])"
    $lines += "Warnings: $($reportData.Warnings[0])"
    $lines += "=" * 60
    $lines | Set-Content $OutputPath -Encoding UTF8
    Write-Host "Text report saved: $OutputPath" -ForegroundColor Green
    exit 0
}

$html = @"
<!DOCTYPE html>
<html>
<head>
    <meta charset="UTF-8">
    <title>GoldISO Build Report</title>
    <style>
        body { font-family: 'Segoe UI', sans-serif; margin: 40px; background: #f5f5f5; }
        .container { max-width: 900px; margin: 0 auto; background: white; padding: 30px; border-radius: 8px; box-shadow: 0 2px 10px rgba(0,0,0,0.1); }
        h1 { color: #2c3e50; border-bottom: 3px solid #3498db; padding-bottom: 10px; }
        .meta { color: #7f8c8d; margin-bottom: 20px; }
        .stats { display: flex; gap: 20px; margin: 20px 0; }
        .stat-box { flex: 1; padding: 15px; border-radius: 6px; text-align: center; }
        .stat-box.success { background: #d4edda; color: #155724; }
        .stat-box.warning { background: #fff3cd; color: #856404; }
        .stat-box.error { background: #f8d7da; color: #721c24; }
        .stat-value { font-size: 28px; font-weight: bold; }
        .stat-label { font-size: 12px; text-transform: uppercase; }
        .phases { margin: 20px 0; }
        .phase-item { padding: 8px 12px; margin: 4px 0; background: #ecf0f1; border-left: 4px solid #3498db; }
        .footer { margin-top: 30px; padding-top: 20px; border-top: 1px solid #eee; color: #95a5a6; font-size: 12px; }
    </style>
</head>
<body>
    <div class="container">
        <h1>GoldISO Build Report</h1>
        <div class="meta">
            <p><strong>Build Path:</strong> $($reportData.BuildPath)</p>
            <p><strong>Generated:</strong> $($reportData.Timestamp)</p>
            $(if ($reportData.Duration) { "<p><strong>Duration:</strong> $($reportData.Duration)</p>" })
        </div>
        
        <div class="stats">
            <div class="stat-box success">
                <div class="stat-value">$($reportData.Phases.Count)</div>
                <div class="stat-label">Phases</div>
            </div>
            <div class="stat-box warning">
                <div class="stat-value">$($reportData.Warnings[0])</div>
                <div class="stat-label">Warnings</div>
            </div>
            <div class="stat-box error">
                <div class="stat-value">$($reportData.Errors[0])</div>
                <div class="stat-label">Errors</div>
            </div>
        </div>

        <div class="phases">
            <h3>Build Phases</h3>
"@

foreach ($phase in $reportData.Phases) {
    $html += "            <div class=""phase-item"">Phase $($phase.Number): $($phase.Name)</div>`n"
}

$html += @"
        </div>
        
        <div class="footer">
            Generated by GoldISO Build System
        </div>
    </div>
</body>
</html>
"@

$html | Set-Content $OutputPath -Encoding UTF8
Write-Host "HTML report saved: $OutputPath" -ForegroundColor Green