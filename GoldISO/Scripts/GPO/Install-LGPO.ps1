#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Downloads and installs Microsoft LGPO.exe (Local Group Policy Object tool)
.DESCRIPTION
    LGPO.exe is required for applying Group Policy settings without gpedit.msc.
    This script downloads it from the Microsoft Security Compliance Toolkit.
.NOTES
    Part of GoldISO GPO Migration
    https://www.microsoft.com/en-us/download/details.aspx?id=55319
#>

[CmdletBinding()]
param(
    [string]$InstallPath = "C:\ProgramData\Winhance\Tools",
    [switch]$Force
)

$LGPOUrl = "https://download.microsoft.com/download/8/5/C/85C25433-A1B0-4FFA-9129-EB5938ABF5E2/LGPO.zip"
$LGPOZip = Join-Path $env:TEMP "LGPO.zip"
$LGPOExe = Join-Path $InstallPath "LGPO.exe"

function Write-Log {
    param([string]$Message, [string]$Level = "INFO")
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logLine = "[$timestamp] [$Level] $Message"
    Write-Host $logLine
    $logFile = Join-Path $InstallPath "lgpo-install.log"
    Add-Content -Path $logFile -Value $logLine -ErrorAction SilentlyContinue
}

try {
    # Check if already installed
    if ((Test-Path $LGPOExe) -and -not $Force) {
        Write-Log "LGPO.exe already installed at: $LGPOExe"
        return $LGPOExe
    }

    # Create install directory
    if (-not (Test-Path $InstallPath)) {
        New-Item -ItemType Directory -Path $InstallPath -Force | Out-Null
        Write-Log "Created install directory: $InstallPath"
    }

    Write-Log "Downloading LGPO.exe from Microsoft..."
    
    # Download LGPO
    $ProgressPreference = 'SilentlyContinue'
    Invoke-WebRequest -Uri $LGPOUrl -OutFile $LGPOZip -UseBasicParsing -ErrorAction Stop
    Write-Log "Downloaded: $LGPOZip"

    # Extract
    Write-Log "Extracting LGPO.exe..."
    Expand-Archive -Path $LGPOZip -DestinationPath $env:TEMP -Force
    
    # Move to final location (LGPO.exe is in a subfolder)
    $extractedLGPO = Get-ChildItem -Path $env:TEMP -Filter "LGPO.exe" -Recurse | Select-Object -First 1
    if ($extractedLGPO) {
        Copy-Item -Path $extractedLGPO.FullName -Destination $LGPOExe -Force
        Write-Log "Installed LGPO.exe to: $LGPOExe" "SUCCESS"
    } else {
        throw "LGPO.exe not found in extracted archive"
    }

    # Cleanup
    Remove-Item -Path $LGPOZip -Force -ErrorAction SilentlyContinue
    Remove-Item -Path "$env:TEMP\LGPO*" -Recurse -Force -ErrorAction SilentlyContinue

    # Verify
    if (Test-Path $LGPOExe) {
        $version = & $LGPOExe /? 2>&1 | Select-String -Pattern "LGPO.exe" | Select-Object -First 1
        Write-Log "LGPO version: $version" "SUCCESS"
        return $LGPOExe
    } else {
        throw "LGPO.exe installation verification failed"
    }
}
catch {
    Write-Log "Failed to install LGPO: $_" "ERROR"
    throw
}
