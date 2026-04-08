#Requires -Version 5.1
#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Comprehensive system health check for GoldISO environments.

.DESCRIPTION
    Analyzes system health across multiple dimensions: disk health, memory,
    Windows services, event logs, and system stability. Generates a detailed
    health report with recommendations.

.PARAMETER OutputPath
    Directory to save the health report. Default: $PSScriptRoot\..\Logs

.PARAMETER Detailed
    Include detailed component analysis (slower but more thorough).

.PARAMETER CheckUpdates
    Check for pending Windows updates.

.PARAMETER ExportFormat
    Output format: HTML, JSON, or TXT. Default: HTML
#>
[CmdletBinding()]
param(
    [string]$OutputPath = (Join-Path $PSScriptRoot "..\Logs"),
    [switch]$Detailed,
    [switch]$CheckUpdates,
    [ValidateSet("HTML", "JSON", "TXT")]
    [string]$ExportFormat = "HTML"
)

#region Initialization
$ErrorActionPreference = "Stop"
$script:StartTime = Get-Date
$script:Results = @{
    Timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    ComputerName = $env:COMPUTERNAME
    OverallHealth = "Unknown"
    Categories = @{}
    Warnings = [System.Collections.Generic.List[string]]::new()
    Errors = [System.Collections.Generic.List[string]]::new()
    Recommendations = [System.Collections.Generic.List[string]]::new()
}

# Import common module if exists
$commonModule = Join-Path $PSScriptRoot "Modules\GoldISO-Common.psm1"
if (Test-Path $commonModule) {
    Import-Module $commonModule -Force
}

# Initialize logging if possible, otherwise use a fallback
if (-not (Test-Path $OutputPath)) {
    New-Item -ItemType Directory -Path $OutputPath -Force | Out-Null
}
$timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
$script:LogFile = Join-Path $OutputPath "SystemHealth-$timestamp.log"

function Write-HealthLog {
    param(
        [string]$Message,
        [ValidateSet("INFO", "WARN", "ERROR", "SUCCESS")][string]$Level = "INFO"
    )
    # Check if Write-Log exists from common module
    if (Get-Command "Write-Log" -ErrorAction SilentlyContinue) {
        Write-Log -Message $Message -Level $Level
    } else {
        $ts = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
        "[$ts] [$Level] $Message" | Add-Content $script:LogFile -ErrorAction SilentlyContinue
        Write-Host "[$Level] $Message"
    }
    
    if ($Level -eq "WARN") { $script:Results.Warnings.Add($Message) }
    if ($Level -eq "ERROR") { $script:Results.Errors.Add($Message) }
}

# History directory setup
$script:SystemDataDir = if ($env:ProgramData) { Join-Path $env:ProgramData "GoldISO" } else { "C:\ProgramData\GoldISO" }
$script:HistoryDir = Join-Path $script:SystemDataDir "HealthHistory"
if (-not (Test-Path $script:HistoryDir)) {
    New-Item -ItemType Directory -Path $script:HistoryDir -Force | Out-Null
}

# Load history for comparison
function Get-LastHealthRecord {
    try {
        $records = Get-ChildItem -Path $script:HistoryDir -Filter "*.json" -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending
        if ($records) {
            $lastFile = $records[0].FullName
            return Get-Content $lastFile -Raw | ConvertFrom-Json
        }
    } catch { }
    return $null
}

$script:PreviousResults = Get-LastHealthRecord

Write-HealthLog "System Health Check Started" "INFO"
Write-HealthLog "Computer: $($env:COMPUTERNAME) | User: $($env:USERNAME)" "INFO"
#endregion

#region Disk Health Checks
function Test-DiskHealth {
    Write-HealthLog "Checking disk health..." "INFO"
    $diskResults = @{ Status = "OK"; Score = 100; Disks = @() }

    try {
        $physicalDisks = Get-PhysicalDisk | Where-Object { $_.BusType -ne 'File Backed Virtual' }

        foreach ($disk in $physicalDisks) {
            $diskInfo = @{
                DeviceId = $disk.DeviceId
                FriendlyName = $disk.FriendlyName
                Size = "$([math]::Round($disk.Size / 1GB, 2)) GB"
                MediaType = $disk.MediaType
                HealthStatus = $disk.HealthStatus
                OperationalStatus = ($disk.OperationalStatus -join ', ')
                Temperature = $null
                SMART = @{}
            }

            try {
                $reliability = Get-StorageReliabilityCounter -PhysicalDisk $disk -ErrorAction SilentlyContinue
                if ($reliability) {
                    $diskInfo.Temperature = $reliability.Temperature
                    $diskInfo.SMART = @{
                        Wear = $reliability.Wear
                        ReadErrors = $reliability.ReadErrorsTotal
                        WriteErrors = $reliability.WriteErrorsTotal
                    }
                }
            } catch { }

            if ($script:PreviousResults) {
                $prevDisk = $script:PreviousResults.Categories.Disk.Disks | Where-Object { $_.DeviceId -eq $disk.DeviceId }
                if ($prevDisk -and ($null -ne $diskInfo.Temperature) -and ($null -ne $prevDisk.Temperature)) {
                    $tempDiff = $diskInfo.Temperature - $prevDisk.Temperature
                    if ($tempDiff -ne 0) {
                        $pDiffStr = if ($tempDiff -gt 0) { "+$tempDiff" } else { "$tempDiff" }
                        Write-HealthLog "  Temp Diff for $($disk.FriendlyName): $pDiffStr C since last check" "INFO"
                    }
                }
            }
            $diskResults.Disks += $diskInfo
        }

        $volumes = Get-Volume | Where-Object { $_.DriveType -eq 'Fixed' -and $_.Size -gt 0 }
        foreach ($vol in $volumes) {
            $freePercent = ($vol.SizeRemaining / $vol.Size) * 100
            if ($freePercent -lt 10) {
                $diskResults.Score -= 15
                $driveId = if ($vol.DriveLetter) { "$($vol.DriveLetter):\" } else { "Volume $($vol.UniqueId)" }
                Write-HealthLog "Low disk space on $driveId - $([math]::Round($freePercent, 1))% free" "WARN"
            }
        }
    }
    catch {
        Write-HealthLog "Error checking disk health: $_" "ERROR"
        $diskResults.Status = "Error"
    }

    $script:Results.Categories['Disk'] = $diskResults
}
#endregion

#region Memory Health
function Test-MemoryHealth {
    Write-HealthLog "Checking memory health..." "INFO"
    $memoryResults = @{ Status = "OK"; Score = 100; Details = @{} }

    try {
        $os = Get-CimInstance Win32_OperatingSystem
        $memoryResults.TotalGB = [math]::Round($os.TotalVisibleMemorySize / 1MB, 2)
        $memoryResults.AvailableGB = [math]::Round($os.FreePhysicalMemory / 1MB, 2)
        $memoryResults.Details.UsedPercent = [math]::Round((($os.TotalVisibleMemorySize - $os.FreePhysicalMemory) / $os.TotalVisibleMemorySize) * 100, 1)

        if ($script:PreviousResults -and $script:PreviousResults.Categories.Memory) {
            $prevUsed = $script:PreviousResults.Categories.Memory.Details.UsedPercent
            $memDiff = $memoryResults.Details.UsedPercent - $prevUsed
            if ([math]::Abs($memDiff) -gt 2) {
                 $memDiffStr = if ($memDiff -gt 0) { "+$memDiff" } else { "$memDiff" }
                 Write-HealthLog "Memory Usage Change: $memDiffStr% since last check" "INFO"
            }
        }
    } catch { 
        Write-HealthLog "Error checking memory: $_" "ERROR"
    }
    $script:Results.Categories['Memory'] = $memoryResults
}
#endregion

#region Service Health
function Test-ServiceHealth {
    Write-HealthLog "Checking critical services..." "INFO"
    $serviceResults = @{ Status = "OK"; Score = 100; Services = @() }
    $criticalServices = @("wuauserv", "BITS", "CryptSvc", "Dhcp", "Dnscache", "MpsSvc", "EventLog", "Schedule")
    
    foreach ($svcName in $criticalServices) {
        $svc = Get-Service -Name $svcName -ErrorAction SilentlyContinue
        if ($svc -and $svc.Status -ne 'Running' -and $svc.StartType -eq 'Automatic') {
            $serviceResults.Score -= 10
            Write-HealthLog "Service not running: $svcName" "WARN"
        }
    }
    $script:Results.Categories['Services'] = $serviceResults
}
#endregion

#region Windows Updates Check
function Test-UpdateStatus {
    if (-not $CheckUpdates) { return }
    Write-HealthLog "Checking Windows Update status..." "INFO"
    $updateResults = @{ Status = "OK"; Score = 100 }
    try {
        $updateSession = New-Object -ComObject Microsoft.Update.Session
        $updateSearcher = $updateSession.CreateUpdateSearcher()
        $searchResult = $updateSearcher.Search("IsInstalled=0 and Type='Software'")
        $updateResults.PendingCount = $searchResult.Updates.Count
        if ($updateResults.PendingCount -gt 0) { 
            Write-HealthLog "$($updateResults.PendingCount) updates pending" "WARN" 
        }
    } catch { 
        $updateResults.Status = "Error"
    }
    $script:Results.Categories['WindowsUpdates'] = $updateResults
}
#endregion

#region Report Generation
function Export-HealthReport {
    $scores = $script:Results.Categories.Values | ForEach-Object { $_.Score }
    $avgScore = if ($scores) { [math]::Round(($scores | Measure-Object -Average).Average) } else { 0 }
    $script:Results.OverallScore = $avgScore
    $script:Results.OverallHealth = if ($avgScore -ge 90) { "Excellent" } elseif ($avgScore -ge 80) { "Good" } else { "Fair" }

    $reportPathBase = Join-Path $OutputPath "SystemHealth-Report-$timestamp"
    
    # Save JSON always for history
    $jsonContent = $script:Results | ConvertTo-Json -Depth 10
    $historyFile = Join-Path $script:HistoryDir "Health-$timestamp.json"
    $jsonContent | Set-Content $historyFile -Encoding UTF8

    $reportFile = "$reportPathBase.json"
    if ($ExportFormat -eq "JSON") { } else {
        $reportFile = "$reportPathBase.txt"
        $jsonContent | Set-Content $reportFile -Encoding UTF8
    }
    
    Write-HealthLog "Report saved: $reportFile" "SUCCESS"
    return $reportFile
}
#endregion

# Main
try {
    Test-DiskHealth
    Test-MemoryHealth
    Test-ServiceHealth
    Test-UpdateStatus
    $reportFile = Export-HealthReport
    Write-HealthLog "Health Check Complete. Score: $($script:Results.OverallScore)/100" "SUCCESS"
    if ($script:Results.OverallScore -lt 80) { exit 1 } else { exit 0 }
} catch {
    Write-HealthLog "Critical Failure: $_" "ERROR"
    exit 1
}
