#Requires -Version 5.1

# Import common module
Import-Module (Join-Path $PSScriptRoot "Modules\GoldISO-Common.psm1") -Force

<#
.SYNOPSIS
    Sysprep and shutdown - run in Audit mode before capturing
.DESCRIPTION
    Runs sysprep generalize with oobe and shutdown.
    After shutdown, boot to WinPE and run Capture-Image.ps1 to capture.
.EXAMPLE
    .\Audit-Sysprep.ps1
#>
[CmdletBinding()]
param(
    [switch]$NoBackup
)

$ErrorActionPreference = "Stop"

# Initialize logging
$logFile = Join-Path (Split-Path $PSScriptRoot -Parent) "Logs\Audit-Sysprep-$(Get-Date -Format 'yyyyMMdd-HHmmss').log"
Initialize-Logging -LogPath $logFile

Write-Log "=========================================="
Write-Log "Audit Mode Sysprep Starting" "INFO"
Write-Log "=========================================="

# Check admin
$isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    Write-Log "ERROR: Run as Administrator" "ERROR"
    exit 1
}

if (-not $NoBackup) {
    Write-Log "Creating system backup point..."
    try {
        Checkpoint-Computer -Description "GoldISO-PreSysprep" -RestorePointType "ApplicationAndServices" -ErrorAction SilentlyContinue | Out-Null
        Write-Log "System restore point created" "SUCCESS"
    } catch {
        Write-Log "Could not create restore point (non-critical): $_" "WARN"
    }
}

Write-Log "Cleaning up before sysprep..."
$cleanupFiles = @(
    "$env:TEMP\*",
    "$env:LOCALAPPDATA\Temp\*",
    "C:\Windows\Temp\*"
)
foreach ($path in $cleanupFiles) {
    try {
        Remove-Item -Path $path -Recurse -Force -ErrorAction SilentlyContinue
    } catch {}
}
Write-Log "Cleanup complete" "SUCCESS"

Write-Log "=========================================="
Write-Log "WARNING: About to run sysprep!" "WARN"
Write-Log "This will generalize the Windows installation." "WARN"
Write-Log "After sysprep completes, the system will SHUT DOWN." "WARN"
Write-Log "=========================================="
Write-Host ""

$confirm = Read-Host "Type 'YES' to continue (or 'N' to cancel)"
if ($confirm -ne "YES") {
    Write-Log "Cancelled by user" "WARN"
    exit 0
}

Write-Log "Running sysprep generalize + oobe + shutdown..."

$sysprepPath = "C:\Windows\System32\Sysprep\sysprep.exe"
$args = "/generalize /oobe /shutdown /quiet /unattend:C:\Windows\System32\Sysprep\unattend.xml"

if (Test-Path $sysprepPath) {
    $proc = Start-Process -FilePath $sysprepPath -ArgumentList $args -Wait -PassThru -NoNewWindow
    Write-Log "Sysprep exit code: $($proc.ExitCode)" "INFO"
} else {
    Write-Log "ERROR: sysprep.exe not found" "ERROR"
    exit 1
}

Write-Log "System has shut down."
Write-Log "=========================================="
Write-Log "NEXT STEPS:" "INFO"
Write-Log "1. Boot into WinPE" "INFO"
Write-Log "2. Run Capture-Image.ps1" "INFO"
Write-Log "3. Image will be saved to C:\Capture.wim" "INFO"
Write-Log "4. Move to I:\GoldISO\Capture.wim" "INFO"
Write-Log "=========================================="