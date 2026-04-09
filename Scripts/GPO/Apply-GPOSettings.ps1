#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Applies Group Policy settings via LGPO.exe on first login
.DESCRIPTION
    This script runs during OOBE FirstLogonCommands to apply GPO settings
    that replace registry-based configuration for better manageability.
    
    Settings applied:
    - Computer Policy: Privacy, Windows Update, Security, Gaming
    - User Policy: Explorer UI, Privacy, Gaming preferences
.NOTES
    Part of GoldISO GPO Migration
    Run Order: Should execute early in FirstLogonCommands (Order 5-10)
#>

[CmdletBinding()]
param(
    [string]$GPODir = "C:\ProgramData\Winhance\GPO",
    [string]$LGPOPath = "C:\ProgramData\Winhance\Tools\LGPO.exe",
    [string]$LogPath = "C:\ProgramData\Winhance\Logs\gpo-application.log"
)

$ErrorActionPreference = "Stop"

if (Test-Path (Join-Path $PSScriptRoot "..\Modules\GoldISO-Common.psm1")) {
    Import-Module (Join-Path $PSScriptRoot "..\Modules\GoldISO-Common.psm1") -Force
}

function Write-Log {
    param([string]$Message, [string]$Level = "INFO")
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logLine = "[$timestamp] [$Level] $Message"
    
    # Ensure log directory exists
    $logDir = Split-Path $LogPath -Parent
    if (-not (Test-Path $logDir)) {
        New-Item -ItemType Directory -Path $logDir -Force | Out-Null
    }
    
    Add-Content -Path $LogPath -Value $logLine
    
    # Also write to console with colors
    switch ($Level) {
        "ERROR" { Write-Host $logLine -ForegroundColor Red }
        "WARN"  { Write-Host $logLine -ForegroundColor Yellow }
        "SUCCESS" { Write-Host $logLine -ForegroundColor Green }
        default { Write-Host $logLine }
    }
}

function Install-LGPOIfNeeded {
    if (-not (Test-Path $LGPOPath)) {
        Write-Log "LGPO.exe not found, installing..." "WARN"
        $installScript = Join-Path $PSScriptRoot "Install-LGPO.ps1"
        if (Test-Path $installScript) {
            & $installScript -InstallPath (Split-Path $LGPOPath -Parent)
        } else {
            throw "LGPO install script not found: $installScript"
        }
    }
}

try {
    Write-Log "========================================"
    Write-Log "Starting GPO Application"
    Write-Log "========================================"

    # Step 1: Ensure LGPO is available
    Install-LGPOIfNeeded

    if (-not (Test-Path $LGPOPath)) {
        throw "LGPO.exe not found after installation attempt"
    }

    Write-Log "LGPO.exe located at: $LGPOPath"

    # Step 2: Verify GPO files exist
    $computerPolicy = Join-Path $GPODir "Computer-Policy.txt"
    $userPolicy = Join-Path $GPODir "User-Policy.txt"

    if (-not (Test-Path $GPODir)) {
        throw "GPO directory not found: $GPODir"
    }

    # Step 3: Apply Computer Policy (HKLM)
    if (Test-Path $computerPolicy) {
        Write-Log "Applying Computer Policy from: $computerPolicy"
        & $LGPOPath /t $computerPolicy 2>&1 | ForEach-Object { Write-Log "LGPO: $_" }
        
        if ($LASTEXITCODE -eq 0) {
            Write-Log "Computer Policy applied successfully" "SUCCESS"
        } else {
            Write-Log "Computer Policy application failed (exit code: $LASTEXITCODE)" "ERROR"
        }
    } else {
        Write-Log "Computer Policy file not found, skipping" "WARN"
    }

    # Step 4: Apply User Policy (HKCU) - applies to current user
    if (Test-Path $userPolicy) {
        Write-Log "Applying User Policy from: $userPolicy"
        & $LGPOPath /t $userPolicy /u $env:USERNAME 2>&1 | ForEach-Object { Write-Log "LGPO: $_" }
        
        if ($LASTEXITCODE -eq 0) {
            Write-Log "User Policy applied successfully" "SUCCESS"
        } else {
            Write-Log "User Policy application failed (exit code: $LASTEXITCODE)" "ERROR"
        }
    } else {
        Write-Log "User Policy file not found, skipping" "WARN"
    }

    # Step 5: Apply to Default User profile (for new users)
    $defaultUserPolicy = Join-Path $GPODir "User-Policy.txt"
    if (Test-Path $defaultUserPolicy) {
        Write-Log "Applying User Policy to Default User profile..."
        & $LGPOPath /t $defaultUserPolicy /u "Default" 2>&1 | ForEach-Object { Write-Log "LGPO: $_" }
        
        if ($LASTEXITCODE -eq 0) {
            Write-Log "Default User Policy applied successfully" "SUCCESS"
        } else {
            Write-Log "Default User Policy application failed (exit code: $LASTEXITCODE)" "WARN"
        }
    }

    # Step 6: Export current policy state for reference
    $backupDir = Join-Path $GPODir "Backup"
    if (-not (Test-Path $backupDir)) {
        New-Item -ItemType Directory -Path $backupDir -Force | Out-Null
    }
    
    $backupFile = Join-Path $backupDir "applied-policy-$(Get-Date -Format 'yyyyMMdd-HHmmss').txt"
    & $LGPOPath /b $backupFile 2>&1 | Out-Null
    Write-Log "Policy backup created: $backupFile"

    Write-Log "========================================"
    Write-Log "GPO Application Completed"
    Write-Log "========================================"

    # Refresh Group Policy
    Write-Log "Refreshing Group Policy..."
    gpupdate /force /wait:30 2>&1 | ForEach-Object { Write-Log "GPUPDATE: $_" }

    exit 0
}
catch {
    Write-Log "CRITICAL ERROR: $_" "ERROR"
    Write-Log "Stack Trace: $($_.ScriptStackTrace)" "ERROR"
    exit 1
}
