#Requires -Version 5.1
#Requires -RunAsAdministrator
<#
.SYNOPSIS
    System image repair and recovery utilities.

.DESCRIPTION
    Repairs Windows system image using DISM and SFC. Handles various corruption
    scenarios with fallback repair options. Includes component store cleanup
    and health restoration.

.PARAMETER DeepRepair
    Perform deep repair including Windows Update source repair.

.PARAMETER CheckOnly
    Only check health status without making repairs.

.PARAMETER UseWindowsUpdate
    Use Windows Update as repair source (requires internet).

.PARAMETER SourceImage
    Path to Windows source image for offline repairs.

.PARAMETER Stage
    Repair stage: Check, RestoreHealth, ComponentCleanup, or All. Default: All

.EXAMPLE
    .\Repair-SystemImage.ps1 -CheckOnly

.EXAMPLE
    .\Repair-SystemImage.ps1 -DeepRepair -UseWindowsUpdate
#>
[CmdletBinding()]
param(
    [switch]$DeepRepair,
    [switch]$CheckOnly,
    [switch]$UseWindowsUpdate,
    [string]$SourceImage,
    [ValidateSet("Check", "RestoreHealth", "ComponentCleanup", "All")]
    [string]$Stage = "All"
)

#region ─────────────────────────────────────────────────────────────────────────────
# Initialization
# ─────────────────────────────────────────────────────────────────────────────

$ErrorActionPreference = "Continue"
$script:StartTime = Get-Date
$script:RepairLog = [System.Collections.Generic.List[string]]::new()
$script:Errors = [System.Collections.Generic.List[string]]::new()

$commonModule = Join-Path $PSScriptRoot "Modules\GoldISO-Common.psm1"
if (Test-Path $commonModule) {
    Import-Module $commonModule -Force
}

$script:LogDir = "C:\ProgramData\GoldISO\Logs"
$timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
$script:LogFile = Join-Path $script:LogDir "repair-$timestamp.log"
New-Item -ItemType Directory -Path $script:LogDir -Force -ErrorAction SilentlyContinue | Out-Null

function Write-RepairLog {
    param(
        [string]$Message,
        [ValidateSet("INFO", "WARN", "ERROR", "SUCCESS", "REPAIR")][string]$Level = "INFO"
    )
    $ts = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $entry = "[$ts] [$Level] $Message"

    $color = switch ($Level) {
        "ERROR" { "Red" }
        "WARN" { "Yellow" }
        "SUCCESS" { "Green" }
        "REPAIR" { "Cyan" }
        default { "White" }
    }
    Write-Host $entry -ForegroundColor $color
    Add-Content -Path $script:LogFile -Value $entry -ErrorAction SilentlyContinue

    if ($Level -eq "ERROR") { $script:Errors.Add($Message) }
    $script:RepairLog.Add($entry)
}

Write-RepairLog "System Image Repair Started" "REPAIR"
Write-RepairLog "Stage: $Stage | DeepRepair: $DeepRepair | CheckOnly: $CheckOnly" "INFO"

#endregion

#region ─────────────────────────────────────────────────────────────────────────────
# Health Check Functions
# ─────────────────────────────────────────────────────────────────────────────

function Test-ImageHealth {
    Write-RepairLog "Checking Windows image health..." "REPAIR"

    try {
        $healthResult = dism.exe /Online /Get-Health 2>&1
        $healthString = $healthResult | Select-String "Health State"

        if ($healthString -match "Healthy") {
            Write-RepairLog "Image health status: HEALTHY" "SUCCESS"
            return @{ Status = "Healthy"; RepairNeeded = $false }
        }
        elseif ($healthString -match "Repairable") {
            Write-RepairLog "Image health status: REPAIRABLE" "WARN"
            return @{ Status = "Repairable"; RepairNeeded = $true }
        }
        else {
            Write-RepairLog "Image health status: UNHEALTHY" "ERROR"
            return @{ Status = "Unhealthy"; RepairNeeded = $true }
        }
    }
    catch {
        Write-RepairLog "Could not determine health status: $_" "ERROR"
        return @{ Status = "Unknown"; RepairNeeded = $true }
    }
}

function Test-ComponentStore {
    Write-RepairLog "Analyzing Component Store..." "REPAIR"

    try {
        $analysis = dism.exe /Online /Cleanup-Image /AnalyzeComponentStore 2>&1

        $winSxSFolder = ($analysis | Select-String "Actual Size of Windows Explorer:") -replace ".*:\s*", "" -replace "\s.*$", ""
        $sharedWithWindows = ($analysis | Select-String "Shared with Windows:") -replace ".*:\s*", "" -replace "\s.*$", ""
        $backupAndDisabled = ($analysis | Select-String "Backups and Disabled Features:") -replace ".*:\s*", "" -replace "\s.*$", ""
        $cacheAndTemp = ($analysis | Select-String "Cache and temporary data:") -replace ".*:\s*", "" -replace "\s.*$", ""
        $reclaimable = ($analysis | Select-String " reclaim ") -replace ".*reclaim ([0-9.]+).*", '$1'

        Write-RepairLog "  WinSxS Size: $winSxSFolder" "INFO"
        Write-RepairLog "  Shared with Windows: $sharedWithWindows" "INFO"
        Write-RepairLog "  Backups/Disabled: $backupAndDisabled" "INFO"
        Write-RepairLog "  Cache/Temp: $cacheAndTemp" "INFO"

        if ($reclaimable -and [double]$reclaimable -gt 0.5) {
            Write-RepairLog "  Reclaimable: $reclaimable GB (cleanup recommended)" "WARN"
            return @{ NeedsCleanup = $true; ReclaimableGB = [double]$reclaimable }
        }
        else {
            Write-RepairLog "  Reclaimable: $reclaimable GB (minimal)" "INFO"
            return @{ NeedsCleanup = $false; ReclaimableGB = [double]$reclaimable }
        }
    }
    catch {
        Write-RepairLog "Could not analyze component store: $_" "WARN"
        return @{ NeedsCleanup = $false; ReclaimableGB = 0 }
    }
}

#endregion

#region ─────────────────────────────────────────────────────────────────────────────
# Repair Functions
# ─────────────────────────────────────────────────────────────────────────────

function Repair-ImageHealth {
    param([hashtable]$HealthStatus)

    if (-not $HealthStatus.RepairNeeded) {
        Write-RepairLog "No repair needed, skipping restore health" "INFO"
        return $true
    }

    Write-RepairLog "Starting image health restoration..." "REPAIR"

    $dismArgs = @("/Online", "/Cleanup-Image", "/RestoreHealth")

    if ($UseWindowsUpdate) {
        Write-RepairLog "Using Windows Update as repair source" "INFO"
        # /RestoreHealth defaults to Windows Update
    }
    elseif ($SourceImage -and (Test-Path $SourceImage)) {
        Write-RepairLog "Using source image: $SourceImage" "INFO"
        $dismArgs += "/Source"
        $dismArgs += "WIM:$SourceImage`:1"
        $dismArgs += "/LimitAccess"
    }
    else {
        Write-RepairLog "Using default repair sources (Windows Update / Local)" "INFO"
    }

    Write-RepairLog "Executing: dism.exe $dismArgs" "INFO"
    $dismOutput = dism.exe @dismArgs 2>&1

    foreach ($line in $dismOutput) {
        if ($line -match "error|failed|corrupt" -and $line -notmatch "0x0") {
            Write-RepairLog "DISM: $line" "WARN"
        }
    }

    # Check if repair succeeded
    $postHealth = Test-ImageHealth
    if ($postHealth.Status -eq "Healthy") {
        Write-RepairLog "Image health restored successfully" "SUCCESS"
        return $true
    }
    else {
        Write-RepairLog "Image health still has issues after repair attempt" "WARN"
        return $false
    }
}

function Start-SystemFileCheck {
    Write-RepairLog "Starting System File Checker (SFC)..." "REPAIR"

    try {
        $result = sfc.exe /scannow 2>&1

        # Parse SFC results
        if ($result -match "Windows Resource Protection did not find any integrity violations") {
            Write-RepairLog "SFC: No integrity violations found" "SUCCESS"
            return @{ Success = $true; IssuesFound = 0 }
        }
        elseif ($result -match "Windows Resource Protection found corrupt files and successfully repaired them") {
            Write-RepairLog "SFC: Corrupt files found and repaired" "SUCCESS"
            return @{ Success = $true; IssuesFound = 1 }
        }
        elseif ($result -match "Windows Resource Protection found corrupt files but was unable to fix some of them") {
            Write-RepairLog "SFC: Some corrupt files could not be repaired" "WARN"
            return @{ Success = $false; IssuesFound = 1 }
        }
        elseif ($result -match "Windows Resource Protection could not perform the requested operation") {
            Write-RepairLog "SFC: Could not complete scan (may need offline repair)" "WARN"
            return @{ Success = $false; IssuesFound = 0 }
        }
        else {
            Write-RepairLog "SFC: Unknown result - check CBS.log" "WARN"
            return @{ Success = $null; IssuesFound = 0 }
        }
    }
    catch {
        Write-RepairLog "SFC execution failed: $_" "ERROR"
        return @{ Success = $false; IssuesFound = 0 }
    }
}

function Optimize-ComponentStore {
    param([hashtable]$Analysis)

    if (-not $Analysis.NeedsCleanup -and -not $DeepRepair) {
        Write-RepairLog "Component Store cleanup not needed" "INFO"
        return $true
    }

    Write-RepairLog "Starting Component Store cleanup..." "REPAIR"

    try {
        $cleanupArgs = @("/Online", "/Cleanup-Image", "/StartComponentCleanup")

        if ($DeepRepair) {
            Write-RepairLog "Deep cleanup: Including reset base" "INFO"
            $cleanupArgs += "/ResetBase"
        }

        $result = dism.exe @cleanupArgs 2>&1

        if ($LASTEXITCODE -eq 0) {
            Write-RepairLog "Component Store cleanup completed" "SUCCESS"
            return $true
        }
        else {
            Write-RepairLog "Component Store cleanup completed with warnings" "WARN"
            return $false
        }
    }
    catch {
        Write-RepairLog "Component Store cleanup failed: $_" "ERROR"
        return $false
    }
}

function Repair-UpdateComponents {
    if (-not $DeepRepair) { return $true }

    Write-RepairLog "Deep repair: Checking Windows Update components..." "REPAIR"

    try {
        # Reset Windows Update components
        $services = @("wuauserv", "cryptSvc", "bits", "msiserver")

        foreach ($service in $services) {
            Write-RepairLog "  Stopping $service..." "INFO"
            Stop-Service -Name $service -Force -ErrorAction SilentlyContinue | Out-Null
        }

        # Rename software distribution folders
        $folders = @(
            "C:\Windows\SoftwareDistribution",
            "C:\Windows\System32\catroot2"
        )

        foreach ($folder in $folders) {
            if (Test-Path $folder) {
                $backup = "$folder.bak-$(Get-Date -Format yyyyMMdd)"
                try {
                    Rename-Item $folder $backup -Force -ErrorAction Stop
                    Write-RepairLog "  Renamed: $folder -> $backup" "INFO"
                }
                catch {
                    Write-RepairLog "  Could not rename $folder`: $_" "WARN"
                }
            }
        }

        # Restart services
        foreach ($service in ($services | Sort-Object)) {
            Write-RepairLog "  Starting $service..." "INFO"
            Start-Service -Name $service -ErrorAction SilentlyContinue | Out-Null
        }

        Write-RepairLog "Windows Update components reset" "SUCCESS"
        return $true
    }
    catch {
        Write-RepairLog "Update component repair failed: $_" "WARN"
        return $false
    }
}

#endregion

#region ─────────────────────────────────────────────────────────────────────────────
# Main Execution
# ─────────────────────────────────────────────────────────────────────────────

$results = @{
    HealthCheck = $null
    ComponentStore = $null
    ImageRepair = $null
    SFC = $null
    ComponentCleanup = $null
    UpdateRepair = $null
}

# Stage 1: Health Check
if ($Stage -in @("Check", "All")) {
    $results.HealthCheck = Test-ImageHealth
}

# Stage 2: Component Store Analysis
if ($Stage -in @("All")) {
    $results.ComponentStore = Test-ComponentStore
}

if ($CheckOnly) {
    Write-RepairLog "Check-only mode, skipping repairs" "INFO"
}
else {
    # Stage 3: Restore Health
    if ($Stage -in @("RestoreHealth", "All")) {
        $results.ImageRepair = Repair-ImageHealth -HealthStatus $results.HealthCheck
    }

    # Stage 4: Component Store Cleanup
    if ($Stage -in @("ComponentCleanup", "All")) {
        $results.ComponentCleanup = Optimize-ComponentStore -Analysis $results.ComponentStore
    }

    # Stage 5: SFC Scan
    if ($Stage -in @("All")) {
        $results.SFC = Start-SystemFileCheck
    }

    # Stage 6: Deep Repair
    if ($DeepRepair -and $Stage -eq "All") {
        $results.UpdateRepair = Repair-UpdateComponents
    }
}

# Generate Summary
Write-RepairLog "========================================" "REPAIR"
Write-RepairLog "REPAIR SUMMARY" "REPAIR"
Write-RepairLog "========================================" "REPAIR"

$duration = (Get-Date) - $script:StartTime
Write-RepairLog "Total Duration: $($duration.ToString('mm\:ss'))" "INFO"

if ($results.HealthCheck) {
    Write-RepairLog "Image Health: $($results.HealthCheck.Status)" $(if($results.HealthCheck.Status -eq "Healthy"){"SUCCESS"}else{"WARN"})
}
if ($null -ne $results.ImageRepair) {
    Write-RepairLog "Image Repair: $(if($results.ImageRepair){'Success'}else{'Partial/Failed'})" $(if($results.ImageRepair){"SUCCESS"}else{"WARN"})
}
if ($results.SFC) {
    Write-RepairLog "SFC Scan: $(if($results.SFC.Success){'Success'}else{'Issues Found'})" $(if($results.SFC.Success){"SUCCESS"}else{"WARN"})
}
if ($null -ne $results.ComponentCleanup) {
    Write-RepairLog "Component Cleanup: $(if($results.ComponentCleanup){'Complete'}else{'Issues'})" $(if($results.ComponentCleanup){"SUCCESS"}else{"WARN"})
}

Write-RepairLog "Log saved to: $script:LogFile" "INFO"

# Export results
$resultFile = Join-Path $script:LogDir "repair-results-$timestamp.json"
$results | ConvertTo-Json | Set-Content $resultFile
Write-RepairLog "Results saved to: $resultFile" "INFO"

exit $(if ($script:Errors.Count -eq 0) { 0 } elseif ($results.HealthCheck.Status -eq "Healthy") { 0 } else { 1 })
