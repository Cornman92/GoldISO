#Requires -Version 5.1
#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Comprehensive system cleanup and optimization for GoldISO.

.DESCRIPTION
    Performs deep system cleanup including temporary files, Windows Update cache,
    browser caches, recycle bin, old logs, and component store cleanup.
    Includes safety checks and space recovery reporting.

.PARAMETER Aggressive
    Perform more aggressive cleanup (Component Store, old Windows installations).

.PARAMETER IncludeBrowserCache
    Clear browser caches (Edge, Chrome, Firefox).

.PARAMETER MaxAgeDays
    Maximum age in days for file deletion. Default: 7

.PARAMETER WhatIf
    Show what would be cleaned without actually deleting.

.PARAMETER Force
    Skip confirmation prompts.

.EXAMPLE
    .\Invoke-SystemCleanup.ps1 -Aggressive

.EXAMPLE
    .\Invoke-SystemCleanup.ps1 -WhatIf -Verbose
#>
[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [switch]$Aggressive,
    [switch]$IncludeBrowserCache,
    [int]$MaxAgeDays = 7,
    [switch]$WhatIf,
    [switch]$Force
)

#region ─────────────────────────────────────────────────────────────────────────────
# Initialization
# ─────────────────────────────────────────────────────────────────────────────

$ErrorActionPreference = "Continue"
$script:StartTime = Get-Date
$script:SpaceRecovered = 0
$script:ItemsCleaned = [System.Collections.Generic.List[string]]::new()
$script:Errors = [System.Collections.Generic.List[string]]::new()

$commonModule = Join-Path $PSScriptRoot "Modules\GoldISO-Common.psm1"
if (Test-Path $commonModule) {
    Import-Module $commonModule -Force
}

# Initialize logging
$timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
$defaultLog = Join-Path "C:\ProgramData\GoldISO\Logs" "cleanup-$timestamp.log"
Initialize-Logging -LogPath $defaultLog

Write-Log "System Cleanup Started" "INFO"
Write-Log "Mode: $(if($Aggressive){'Aggressive'}else{'Standard'}) | WhatIf: $WhatIf" "INFO"

# Confirm unless Force
if (-not $Force -and -not $WhatIf) {
    Write-Host "`nThis script will clean temporary files and system caches." -ForegroundColor Yellow
    if ($Aggressive) { Write-Host "AGGRESSIVE MODE: Will also clean Component Store and old Windows installs." -ForegroundColor Red }
    $confirm = Read-Host "`nContinue? (Y/N)"
    if ($confirm -ne 'Y') {
        Write-CleanupLog "Cleanup cancelled by user" "INFO"
        exit 0
    }
}

#endregion

#region ─────────────────────────────────────────────────────────────────────────────
# Cleanup Functions
# ─────────────────────────────────────────────────────────────────────────────

function Measure-FolderSize {
    param([string]$Path)
    try {
        if (Test-Path $Path) {
            return (Get-ChildItem $Path -Recurse -Force -ErrorAction SilentlyContinue |
                Measure-Object -Property Length -Sum).Sum
        }
        return 0
    }
    catch { return 0 }
}

function Remove-OldFiles {
    param(
        [string]$Path,
        [string]$Description,
        [string]$Filter = "*",
        [switch]$Recurse
    )

    if (-not (Test-Path $Path)) { return }

    try {
        $beforeSize = Measure-FolderSize $Path
        $cutoffDate = (Get-Date).AddDays(-$MaxAgeDays)

        $params = @{
            Path = $Path
            Filter = $Filter
            Force = $true
            ErrorAction = "SilentlyContinue"
        }
        if ($Recurse) { $params.Recurse = $true }

        $files = Get-ChildItem @params | Where-Object {
            -not $_.PSIsContainer -and $_.LastWriteTime -lt $cutoffDate
        }

        $removedCount = 0
        foreach ($file in $files) {
            if ($WhatIf) {
                Write-CleanupLog "[WHATIF] Would delete: $($file.FullName)" "INFO"
                $removedCount++
            }
            else {
                try {
                    Remove-Item $file.FullName -Force -ErrorAction Stop
                    $removedCount++
                }
                catch {
                    Write-CleanupLog "Failed to delete $($file.Name): $_" "WARN"
                }
            }
        }

        $afterSize = if (-not $WhatIf) { Measure-FolderSize $Path } else { $beforeSize }
        $recovered = $beforeSize - $afterSize
        $script:SpaceRecovered += $recovered

        if ($removedCount -gt 0 -or $recovered -gt 0) {
            $sizeStr = if ($recovered -gt 0) { " ($([math]::Round($recovered / 1MB, 2)) MB)" } else { "" }
            Write-CleanupLog "$Description`: Removed $removedCount items$sizeStr" $(if($recovered -gt 0){"SUCCESS"}else{"INFO"})
            $script:ItemsCleaned.Add("$Description`: $removedCount files$sizeStr")
        }
    }
    catch {
        Write-CleanupLog "Error cleaning $Description`: $_" "WARN"
    }
}

function Clear-TempFiles {
    Write-CleanupLog "Cleaning temporary files..." "INFO"

    # Windows Temp
    Remove-OldFiles -Path $env:TEMP -Description "User Temp" -Recurse
    Remove-OldFiles -Path "C:\Windows\Temp" -Description "Windows Temp" -Recurse

    # Common temp locations
    $tempPaths = @(
        @{ Path = "C:\Windows\Prefetch"; Desc = "Prefetch"; Recurse = $false }
        @{ Path = "C:\Windows\SoftwareDistribution\Download"; Desc = "Windows Update Downloads"; Recurse = $true }
        @{ Path = "C:\Windows\Logs\CBS"; Desc = "CBS Logs"; Recurse = $true }
        @{ Path = "C:\Windows\Logs\DISM"; Desc = "DISM Logs"; Recurse = $true }
        @{ Path = "C:\ProgramData\Microsoft\Windows\WER"; Desc = "Error Reports"; Recurse = $true }
    )

    foreach ($tp in $tempPaths) {
        Remove-OldFiles -Path $tp.Path -Description $tp.Desc -Recurse:$tp.Recurse
    }

    # Recycle Bin
    try {
        $rb = (New-Object -ComObject Shell.Application).Namespace(0xA)
        $rbItems = $rb.Items()
        if ($rbItems.Count -gt 0) {
            if ($WhatIf) {
                Write-CleanupLog "[WHATIF] Would empty Recycle Bin ($($rbItems.Count) items)" "INFO"
            }
            else {
                $rbItems | ForEach-Object { Remove-Item $_.Path -Recurse -Force -ErrorAction SilentlyContinue }
                Write-CleanupLog "Recycle Bin emptied ($($rbItems.Count) items)" "SUCCESS"
                $script:ItemsCleaned.Add("Recycle Bin: $($rbItems.Count) items")
            }
        }
    }
    catch {
        Write-CleanupLog "Could not empty Recycle Bin: $_" "WARN"
    }
}

function Clear-BrowserCaches {
    if (-not $IncludeBrowserCache) { return }

    Write-CleanupLog "Cleaning browser caches..." "INFO"

    $browserPaths = @(
        # Edge
        @{ Path = "$env:LOCALAPPDATA\Microsoft\Edge\User Data\Default\Cache"; Desc = "Edge Cache" }
        @{ Path = "$env:LOCALAPPDATA\Microsoft\Edge\User Data\Default\Code Cache"; Desc = "Edge Code Cache" }
        # Chrome
        @{ Path = "$env:LOCALAPPDATA\Google\Chrome\User Data\Default\Cache"; Desc = "Chrome Cache" }
        @{ Path = "$env:LOCALAPPDATA\Google\Chrome\User Data\Default\Code Cache"; Desc = "Chrome Code Cache" }
        # Firefox
        @{ Path = "$env:LOCALAPPDATA\Mozilla\Firefox\Profiles"; Desc = "Firefox Cache"; Recurse = $true; Pattern = "cache2" }
    )

    foreach ($bp in $browserPaths) {
        if ($bp.Pattern) {
            if (Test-Path $bp.Path) {
                Get-ChildItem $bp.Path -Directory -Filter $bp.Pattern -Recurse -ErrorAction SilentlyContinue |
                    ForEach-Object { Remove-OldFiles -Path $_.FullName -Description "$($bp.Desc) ($($_.Name))" -Recurse }
            }
        }
        else {
            Remove-OldFiles -Path $bp.Path -Description $bp.Desc -Recurse:($bp.Recurse)
        }
    }
}

function Optimize-ComponentStore {
    if (-not $Aggressive) { return }

    Write-CleanupLog "Analyzing Component Store (WinSxS)..." "INFO"

    try {
        # Check component store size
        $dismOutput = dism.exe /Online /Cleanup-Image /AnalyzeComponentStore 2>&1
        $reclaimable = ($dismOutput | Select-String "Component Store Cleanup Recommended" -Context 0, 2) |
            ForEach-Object { if ($_ -match '(\d+\.?\d*)\s*GB') { $matches[1] } }

        if ($reclaimable) {
            Write-CleanupLog "Component Store cleanup can reclaim $reclaimable GB" "INFO"

            if (-not $WhatIf) {
                Write-CleanupLog "Starting Component Store cleanup..." "INFO"
                $dismOutput = dism.exe /Online /Cleanup-Image /StartComponentCleanup /ResetBase 2>&1
                $dismOutput | ForEach-Object { Write-CleanupLog "  DISM: $_" "INFO" }
                if ($LASTEXITCODE -eq 0) {
                    Write-CleanupLog "Component Store cleanup completed" "SUCCESS"
                    $script:ItemsCleaned.Add("Component Store: ~$reclaimable GB reclaimed")
                }
                else {
                    Write-CleanupLog "Component Store cleanup failed or partially completed" "WARN"
                }
            }
            else {
                Write-CleanupLog "[WHATIF] Would run Component Store cleanup" "INFO"
            }
        }
        else {
            Write-CleanupLog "Component Store cleanup not needed at this time" "INFO"
        }
    }
    catch {
        Write-CleanupLog "Error during Component Store cleanup: $_" "WARN"
    }
}

function Clear-OldWindowsInstall {
    [CmdletBinding(SupportsShouldProcess = $true)]
    param()
    if (-not $Aggressive) { return }

    $windowsOldPath = "C:\Windows.old"
    if (Test-Path $windowsOldPath) {
        $size = (Get-ChildItem $windowsOldPath -Recurse -Force -ErrorAction SilentlyContinue |
            Measure-Object -Property Length -Sum).Sum

        if ($size -gt 0) {
            $sizeGB = [math]::Round($size / 1GB, 2)
            Write-CleanupLog "Previous Windows installation found: $sizeGB GB" "INFO"

            if ($PSCmdlet.ShouldProcess("Windows.old folder ($sizeGB GB)", "Remove")) {
                try {
                    takeown /F $windowsOldPath /A /R /D Y 2>&1 | Out-Null
                    icacls $windowsOldPath /grant Administrators:F /T 2>&1 | Out-Null
                    Remove-Item $windowsOldPath -Recurse -Force -ErrorAction Stop
                    Write-CleanupLog "Previous Windows installation removed" "SUCCESS"
                    $script:SpaceRecovered += $size
                    $script:ItemsCleaned.Add("Windows.old: $sizeGB GB")
                }
                catch {
                    Write-CleanupLog "Could not remove Windows.old: $_" "WARN"
                }
            }
        }
    }
}

function Optimize-Drives {
    [CmdletBinding(SupportsShouldProcess = $true)]
    param()
    Write-CleanupLog "Checking drive optimization status..." "INFO"

    try {
        $volumes = Get-Volume | Where-Object { $_.DriveType -eq 'Fixed' -and $_.Size -gt 0 }

        foreach ($vol in $volumes) {
            if ($vol.DriveLetter) {
                $analysis = Optimize-Volume -DriveLetter $vol.DriveLetter -Analyze -ErrorAction SilentlyContinue
                if ($analysis) {
                    Write-CleanupLog "$($vol.DriveLetter): Fragmentation: $($analysis.FragmentationPercent)%" "INFO"
                    if ($analysis.FragmentationPercent -gt 10) {
                        if ($PSCmdlet.ShouldProcess("$($vol.DriveLetter): drive", "Defragment/Optimize")) {
                            Write-CleanupLog "Optimizing $($vol.DriveLetter): ..." "INFO"
                            Optimize-Volume -DriveLetter $vol.DriveLetter -Defrag -ErrorAction SilentlyContinue | Out-Null
                            Write-CleanupLog "$($vol.DriveLetter): optimization complete" "SUCCESS"
                            $script:ItemsCleaned.Add("Drive $($vol.DriveLetter): optimized")
                        }
                    }
                }
            }
        }
    }
    catch {
        Write-CleanupLog "Drive optimization error: $_" "WARN"
    }
}

#endregion

#region ─────────────────────────────────────────────────────────────────────────────
# Main Execution
# ─────────────────────────────────────────────────────────────────────────────

Clear-TempFiles
Clear-BrowserCaches
Optimize-ComponentStore
Clear-OldWindowsInstall
Optimize-Drives

# Final Summary
Write-CleanupLog "========================================" "INFO"
Write-CleanupLog "Cleanup Summary" "INFO"
Write-CleanupLog "========================================" "INFO"

if ($script:ItemsCleaned.Count -eq 0) {
    Write-CleanupLog "No items required cleanup" "INFO"
}
else {
    foreach ($item in $script:ItemsCleaned) {
        Write-CleanupLog "  - $item" "SUCCESS"
    }
}

$duration = (Get-Date) - $script:StartTime
Write-CleanupLog "`nTotal space recovered: $([math]::Round($script:SpaceRecovered / 1MB, 2)) MB" "SUCCESS"
Write-CleanupLog "Cleanup completed in $($duration.ToString('mm\:ss'))" "INFO"
Write-CleanupLog "Log saved to: $script:LogFile" "INFO"

if ($script:Errors.Count -gt 0) { exit 1 }
exit 0
