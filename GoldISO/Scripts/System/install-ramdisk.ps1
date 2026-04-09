#Requires -Version 5.1
#Requires -RunAsAdministrator

# Import common module (may not exist in WinPE/target environment, so wrap in try/catch)
try {
    Import-Module (Join-Path $PSScriptRoot "Modules\GoldISO-Common.psm1") -Force -ErrorAction Stop
} catch {
    # Module not available in target environment, define minimal local logging
}

<#
.SYNOPSIS
    Installs SoftPerfect RAM Disk from USB drive or downloads as fallback
.DESCRIPTION
    Searches all drive letters D-Z for ramdisk_setup.exe under Applications\ or Installers\.
    Falls back to downloading from the official SoftPerfect website if not found on any drive.
.PARAMETER InstallerPath
    Explicit path to local installer. If omitted, drives D-Z are scanned automatically.
.PARAMETER DownloadUrl
    URL to download installer from if local not found
.PARAMETER SizeGB
    RAM disk size in GB to create after installation (default: 8)
.EXAMPLE
    .\install-ramdisk.ps1
    Installs from USB or downloads, creates 8GB RAM disk
.EXAMPLE
    .\install-ramdisk.ps1 -SizeGB 16
    Creates 16GB RAM disk after installation
#>
[CmdletBinding()]
param(
    [string]$InstallerPath = '',
    [string]$DownloadUrl = 'https://www.softperfect.com/download/ramdisk/ramdisk_setup.exe',
    [int]$SizeGB = 8
)

# Initialize centralized logging (auto-initialization handles fallback)
$logFile = 'C:\ProgramData\Winhance\Unattend\Logs\ramdisk-install.txt'
Initialize-Logging -LogPath $logFile

Write-Log 'RAM Disk Installation Script Started'

# Check if already installed
$installPath = 'C:\Program Files\SoftPerfect RAM Disk\ramdiskws.exe'
if (Test-Path $installPath) {
    Write-Log 'SoftPerfect RAM Disk is already installed. Skipping.' 'SUCCESS'
    exit 0
}

# Try USB/source drive first " scan D-Z if no explicit path was provided
$localInstaller = $null

if (-not $InstallerPath) {
    Write-Log 'No InstallerPath specified " scanning drives D-Z for ramdisk_setup.exe...' 'INFO'
    foreach ($d in ([char[]]([char]'D'..[char]'Z'))) {
        foreach ($sub in @('Applications', 'Installers')) {
            $candidate = "${d}:\${sub}\ramdisk_setup.exe"
            if (Test-Path $candidate) {
                $InstallerPath = $candidate
                break
            }
        }
        if ($InstallerPath) { break }
    }
    if ($InstallerPath) {
        Write-Log "Found installer on USB: $InstallerPath" 'SUCCESS'
    } else {
        Write-Log 'Installer not found on any drive " will attempt download fallback' 'WARNING'
    }
}

if ($InstallerPath -and (Test-Path $InstallerPath)) {
    $localInstaller = $InstallerPath
    Write-Log "Using local installer: $InstallerPath" 'INFO'
} else {
    if ($InstallerPath) { Write-Log "Specified path not found: $InstallerPath" 'WARNING' }
    Write-Log 'Local installer not found, attempting download fallback' 'WARNING'

    # Download fallback
    $tempDir = Join-Path $env:TEMP 'SoftPerfectRAMDisk'
    $downloadPath = Join-Path $tempDir 'ramdisk_setup.exe'

    try {
        New-Item -Path $tempDir -ItemType Directory -Force | Out-Null
        Write-Log "Downloading from: $DownloadUrl" 'INFO'
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
        Invoke-WebRequest -Uri $DownloadUrl -OutFile $downloadPath -UseBasicParsing
        $localInstaller = $downloadPath
        Write-Log 'Download completed successfully' 'SUCCESS'
    } catch {
        Write-Log "Download failed: $_" 'ERROR'
        Write-Log 'RAM Disk installation skipped - installer not available' 'WARNING'
        exit 1
    }
}

# Run installer silently - try multiple silent switch combinations
Write-Log "Running installer: $localInstaller" 'INFO'
$installSuccess = $false

# Try Inno Setup switches first (most common for SoftPerfect)
$switchSets = @(
    @('/VERYSILENT', '/NORESTART', '/SUPPRESSMSGBOXES'),
    @('/SILENT', '/NORESTART'),
    @('/S'),
    @('/quiet', '/norestart')
)

foreach ($switches in $switchSets) {
    try {
        Write-Log "Trying installer with switches: $($switches -join ' ')" 'INFO'
        $process = Start-Process -FilePath $localInstaller -ArgumentList $switches -Wait -PassThru -WindowStyle Hidden -ErrorAction Stop

        if ($process.ExitCode -eq 0 -or $process.ExitCode -eq 1 -or $process.ExitCode -eq 3010) {
            Write-Log "SoftPerfect RAM Disk installed successfully (switches: $($switches -join ' '))" 'SUCCESS'
            $installSuccess = $true
            break
        } else {
            Write-Log "Installer exited with code: $($process.ExitCode)" 'WARNING'
        }
    } catch {
        Write-Log "Installer failed with switches $($switches -join ' '): $_" 'ERROR'
    }
}

if (-not $installSuccess) {
    Write-Log 'All silent switch combinations failed for RAM Disk installer' 'ERROR'
    exit 1
}

# Cleanup temp files
if ($localInstaller -and $localInstaller.StartsWith($env:TEMP)) {
    Remove-Item -Path $localInstaller -Force -ErrorAction SilentlyContinue
    Remove-Item -Path (Split-Path $localInstaller) -Recurse -Force -ErrorAction SilentlyContinue
}

Write-Log 'RAM Disk Installation Script Completed' 'SUCCESS'
