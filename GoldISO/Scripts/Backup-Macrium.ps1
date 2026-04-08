#Requires -Version 5.1
#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Download (if needed), install Macrium Reflect, then create a full system backup.
.DESCRIPTION
    1. Checks if Macrium Reflect is installed; installs via winget if not.
    2. Discovers all partitions on the system disk (typically C:) including hidden
       EFI and Recovery partitions so the backup is fully bootable.
    3. Generates a Macrium Reflect backup definition XML and runs the backup.
    4. Saves the image to BackupDest (default: D:\Backups\Macrium).
    5. Verifies the resulting .mrimg file exists and reports its size.

    Uses Macrium Reflect Free v8.0.7638 - the last free release before Macrium
    moved to a subscription model in January 2024.  Install order:
      1. Chocolatey  (choco install macrium-reflect-free) - preferred
      2. Direct CDN  (updates.macrium.com) - fallback
    The backup XML targets Reflect v8.  If you upgrade to v9+ later, regenerate
    the definition file from the Reflect GUI and update BackupDefPath.
.PARAMETER BackupDest
    Folder where the .mrimg backup image will be saved.
    Default: D:\Backups\Macrium
    The folder is created if it does not exist.
.PARAMETER BackupDefPath
    Where to write (and read) the generated Macrium backup definition XML.
    Default: C:\ProgramData\GoldISO\macrium-backup-def.xml
.PARAMETER IncludeDrives
    Comma-separated disk numbers to back up (default: auto-detect system disk).
    Usually disk 0 for a single-disk setup.  Example: "0,1"
.PARAMETER MaxImages
    Maximum number of full images to keep in BackupDest before the oldest is
    deleted by Macrium (default: 3).
.PARAMETER CompressionLevel
    Macrium compression level 1-8 (1=fast/large, 8=slow/small).  Default: 6.
.PARAMETER ForceReinstall
    Uninstall and reinstall Macrium Reflect even if already present.
.EXAMPLE
    .\Backup-Macrium.ps1
    # Auto-detects system disk, backs up to D:\Backups\Macrium
.EXAMPLE
    .\Backup-Macrium.ps1 -BackupDest "E:\Backups\Macrium" -CompressionLevel 8
.EXAMPLE
    .\Backup-Macrium.ps1 -BackupDest "D:\Backups\Macrium" -IncludeDrives "0"
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    [string]$BackupDest       = 'D:\Backups\Macrium',
    [string]$BackupDefPath    = 'C:\ProgramData\GoldISO\macrium-backup-def.xml',
    [string]$IncludeDrives    = '',
    [int]$MaxImages           = 3,
    [ValidateRange(1,8)][int]$CompressionLevel = 6,
    [switch]$ForceReinstall
)

$ErrorActionPreference = 'Continue'
$LogDir  = 'C:\ProgramData\GoldISO'
$LogPath = "$LogDir\macrium-backup.log"
$null    = New-Item -Path $LogDir -ItemType Directory -Force -ErrorAction SilentlyContinue

function Write-Log {
    param([string]$Message, [ValidateSet('INFO','SUCCESS','WARNING','ERROR')][string]$Level = 'INFO')
    $ts    = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    $entry = "[$ts] [$Level] $Message"
    Add-Content -Path $LogPath -Value $entry -Encoding UTF8 -ErrorAction SilentlyContinue
    $color = switch ($Level) { 'ERROR' { 'Red' } 'WARNING' { 'Yellow' } 'SUCCESS' { 'Green' } default { 'White' } }
    Write-Host $entry -ForegroundColor $color
}

# ---------------------------------------------------------------------------
# Helper: find the Macrium Reflect executable
# ---------------------------------------------------------------------------
function Find-ReflectExe {
    $candidates = @(
        'C:\Program Files\Macrium\Reflect\Reflect.exe',
        'C:\Program Files (x86)\Macrium\Reflect\Reflect.exe',
        "${env:ProgramFiles}\Macrium\Reflect\Reflect.exe"
    )
    foreach ($c in $candidates) { if (Test-Path $c) { return $c } }

    # Search registry uninstall keys
    $uninstallPaths = @(
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall',
        'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall'
    )
    foreach ($regRoot in $uninstallPaths) {
        $keys = Get-ChildItem $regRoot -ErrorAction SilentlyContinue |
                Where-Object { (Get-ItemProperty $_.PSPath -ErrorAction SilentlyContinue).DisplayName -like '*Macrium Reflect*' }
        foreach ($key in $keys) {
            $loc = (Get-ItemProperty $key.PSPath -ErrorAction SilentlyContinue).InstallLocation
            if ($loc) {
                $exe = Join-Path $loc 'Reflect.exe'
                if (Test-Path $exe) { return $exe }
            }
        }
    }
    return $null
}

# ---------------------------------------------------------------------------
# 1. Install Macrium Reflect if needed
# ---------------------------------------------------------------------------
Write-Log "=========================================="
Write-Log "Macrium Reflect Backup - GoldISO"
Write-Log "=========================================="

$reflectExe = Find-ReflectExe

if ($reflectExe -and -not $ForceReinstall) {
    Write-Log "Macrium Reflect Free already installed: $reflectExe" 'SUCCESS'
} else {
    if ($ForceReinstall -and $reflectExe) {
        Write-Log "ForceReinstall: removing existing installation..." 'WARNING'
        $uninstallKey = Get-ChildItem 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall',
                                      'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall' `
                        -ErrorAction SilentlyContinue |
                        Where-Object { (Get-ItemProperty $_.PSPath -ErrorAction SilentlyContinue).DisplayName -like '*Macrium*' } |
                        Select-Object -First 1
        if ($uninstallKey) {
            $uninstallStr = (Get-ItemProperty $uninstallKey.PSPath).UninstallString
            if ($uninstallStr) {
                Start-Process cmd -ArgumentList "/c $uninstallStr /S" -Wait | Out-Null
                Write-Log "Uninstall complete." 'SUCCESS'
            }
        }
    }

    $installed = $false

    # --- Attempt 1: Chocolatey (preferred - choco is installed by GoldISO first-logon step 3) ---
    $choco = Get-Command choco -ErrorAction SilentlyContinue
    if ($choco) {
        Write-Log "Attempting install via Chocolatey: choco install macrium-reflect-free"
        $chocoOut = & choco install macrium-reflect-free --yes --no-progress 2>&1
        $chocoOut | ForEach-Object { Write-Log "  [choco] $_" }
        $reflectExe = Find-ReflectExe
        if ($reflectExe) {
            Write-Log "Macrium Reflect Free installed via Chocolatey." 'SUCCESS'
            $installed = $true
        } else {
            Write-Log "Chocolatey install did not produce a detectable Reflect.exe - trying direct download." 'WARNING'
        }
    } else {
        Write-Log "Chocolatey not found - skipping Chocolatey install path." 'WARNING'
    }

    # --- Attempt 2: Direct CDN download (v8.0.7638 - last free release) ---
    if (-not $installed) {
        $freeUrls = @(
            'https://updates.macrium.com/reflect/v8/8.0.7638/ReflectSetup_Free.exe',
            'https://www.macrium.com/downloads/ReflectSetup_Free.exe'
        )
        $setupExe = "$env:TEMP\ReflectSetup_Free.exe"

        foreach ($url in $freeUrls) {
            Write-Log "Downloading Macrium Reflect Free from: $url"
            try {
                Invoke-WebRequest -Uri $url -OutFile $setupExe -UseBasicParsing -ErrorAction Stop
                Write-Log ("Downloaded: " + [math]::Round((Get-Item $setupExe).Length/1MB,1) + " MB") 'SUCCESS'
                break
            } catch {
                Write-Log "Download failed from $url`: $_" 'WARNING'
                Remove-Item $setupExe -Force -ErrorAction SilentlyContinue
            }
        }

        if (Test-Path $setupExe) {
            Write-Log "Running Macrium Reflect Free installer silently..."
            $proc = Start-Process $setupExe -ArgumentList '/VERYSILENT /NORESTART /SUPPRESSMSGBOXES' -Wait -PassThru
            Remove-Item $setupExe -Force -ErrorAction SilentlyContinue
            $reflectExe = Find-ReflectExe
            if ($reflectExe) {
                Write-Log "Macrium Reflect Free installed via direct download." 'SUCCESS'
                $installed = $true
            } else {
                Write-Log "Installer ran (exit code $($proc.ExitCode)) but Reflect.exe not found." 'WARNING'
            }
        }
    }

    if (-not $installed) {
        Write-Log "ERROR: All install methods failed. Manual steps:" 'ERROR'
        Write-Log "  choco install macrium-reflect-free   (if Chocolatey is available)" 'ERROR'
        Write-Log "  - or -" 'ERROR'
        Write-Log "  Download the free v8.0.7638 installer from an archived source and install manually," 'ERROR'
        Write-Log "  then re-run this script." 'ERROR'
        exit 1
    }
}

# ---------------------------------------------------------------------------
# 2. Discover system disk and partitions to back up
# ---------------------------------------------------------------------------
Write-Log "--- Discovering disks to back up ---"

if ($IncludeDrives) {
    $diskNumbers = $IncludeDrives -split ',' | ForEach-Object { [int]$_.Trim() }
} else {
    # Auto-detect: find the disk containing the Windows partition (C:)
    $cPartition  = Get-Partition | Where-Object { $_.DriveLetter -eq 'C' } | Select-Object -First 1
    if (-not $cPartition) {
        Write-Log "ERROR: Cannot find the partition holding C:." 'ERROR'
        exit 1
    }
    $diskNumbers = @($cPartition.DiskNumber)
    Write-Log ("Auto-detected system disk: Disk " + $cPartition.DiskNumber)
}

# Enumerate all partitions on selected disks
$diskInfoList = foreach ($diskNum in $diskNumbers) {
    $partitions = Get-Partition -DiskNumber $diskNum -ErrorAction SilentlyContinue
    if (-not $partitions) {
        Write-Log "WARNING: No partitions found on Disk $diskNum - skipping." 'WARNING'
        continue
    }
    Write-Log ("Disk $diskNum partitions: " + (($partitions | ForEach-Object {
        $letter = if ($_.DriveLetter) { $_.DriveLetter + ':' } else { "(hidden/$($_.Type))" }
        $letter
    }) -join ', '))
    [PSCustomObject]@{ DiskNumber = $diskNum; Partitions = $partitions }
}

if (-not $diskInfoList) {
    Write-Log "ERROR: No valid disks found to back up." 'ERROR'
    exit 1
}

# ---------------------------------------------------------------------------
# 3. Create backup destination folder
# ---------------------------------------------------------------------------
Write-Log "--- Preparing backup destination: $BackupDest ---"
if ($PSCmdlet.ShouldProcess($BackupDest, 'Create backup destination folder')) {
    New-Item -ItemType Directory -Path $BackupDest -Force | Out-Null
    Write-Log "Backup destination ready: $BackupDest" 'SUCCESS'
}

# ---------------------------------------------------------------------------
# 4. Generate Macrium Reflect v8 backup definition XML
# ---------------------------------------------------------------------------
Write-Log "--- Generating backup definition XML ---"

# Build DRIVE elements for each disk
$driveXml = foreach ($di in $diskInfoList) {
    $partXml = ($di.Partitions | ForEach-Object {
        $letter = if ($_.DriveLetter -and $_.DriveLetter -ne "`0") {
            ' letter="' + $_.DriveLetter + '"'
        } else { '' }
        # Include all partitions (EFI, MSR, Recovery, Windows)
        "            <PARTITION index=`"$($_.PartitionNumber)`"$letter />"
    }) -join "`n"
    @"
        <DRIVE disk="$($di.DiskNumber)">
            <PARTITIONS>
$partXml
            </PARTITIONS>
        </DRIVE>
"@
}

$defDir = Split-Path $BackupDefPath -Parent
New-Item -ItemType Directory -Path $defDir -Force | Out-Null

# Macrium Reflect v8 backup definition XML
$xml = @"
<?xml version="1.0" encoding="UTF-16"?>
<MR>
  <BACKUP comment="GoldISO Full System Backup" type="1">
    <BACKUPSET>
$($driveXml -join "`n")
    </BACKUPSET>
    <DESTINATION>
      <FOLDER>$BackupDest</FOLDER>
      <FILENAME>{COMPUTERNAME}_{DATE}_{TIME}_GoldISO.mrimg</FILENAME>
      <MAX_COUNT>$MaxImages</MAX_COUNT>
    </DESTINATION>
    <OPTIONS>
      <COMPRESSION>$CompressionLevel</COMPRESSION>
      <VERIFY>1</VERIFY>
      <PASSWORD></PASSWORD>
      <INTELLIGENT_SECTOR>1</INTELLIGENT_SECTOR>
      <COMMENT>GoldISO full system image - created by Backup-Macrium.ps1</COMMENT>
    </OPTIONS>
  </BACKUP>
</MR>
"@

if ($PSCmdlet.ShouldProcess($BackupDefPath, 'Write backup definition XML')) {
    [System.IO.File]::WriteAllText($BackupDefPath, $xml, [System.Text.Encoding]::Unicode)
    Write-Log "Backup definition written: $BackupDefPath" 'SUCCESS'
}

# ---------------------------------------------------------------------------
# 5. Run the backup
# ---------------------------------------------------------------------------
Write-Log "--- Starting Macrium Reflect backup ---"
Write-Log "  Executable : $reflectExe"
Write-Log "  Definition : $BackupDefPath"
Write-Log "  Destination: $BackupDest"
Write-Log "  Compression: $CompressionLevel / 8"
Write-Log "  Verify     : Yes"
Write-Log ""
Write-Log "NOTE: Large drives (500+ GB) can take 30-90 minutes. Do not interrupt."

$startTime = Get-Date

if ($PSCmdlet.ShouldProcess('Full system backup', 'Run Macrium Reflect')) {
    # /b = backup using definition file
    # /w = wait for completion (blocking)
    # Exit codes: 0 = success, non-zero = failure
    $proc = Start-Process -FilePath $reflectExe -ArgumentList "/b `"$BackupDefPath`" /w" `
                          -Wait -PassThru -NoNewWindow
    $elapsed = [math]::Round(((Get-Date) - $startTime).TotalMinutes, 1)

    if ($proc.ExitCode -eq 0) {
        Write-Log "Backup completed successfully in $elapsed minutes." 'SUCCESS'
    } else {
        Write-Log "Backup process exited with code $($proc.ExitCode) after $elapsed minutes." 'ERROR'
        Write-Log "Check Macrium Reflect logs in: $env:LOCALAPPDATA\Macrium\Reflect\Logs" 'ERROR'
        exit 1
    }
}

# ---------------------------------------------------------------------------
# 6. Verify output
# ---------------------------------------------------------------------------
Write-Log "--- Verifying backup output ---"
$images = Get-ChildItem -Path $BackupDest -Filter '*.mrimg' -ErrorAction SilentlyContinue |
          Sort-Object LastWriteTime -Descending
if ($images) {
    $newest = $images[0]
    $sizeGB = [math]::Round($newest.Length / 1GB, 2)
    Write-Log ("Backup image found: " + $newest.Name + " ($sizeGB GB)") 'SUCCESS'
    Write-Log ("Full path: " + $newest.FullName) 'SUCCESS'
    Write-Log ("Images in $BackupDest`: " + $images.Count + " (max $MaxImages kept)")
} else {
    Write-Log "WARNING: No .mrimg files found in $BackupDest after backup." 'WARNING'
    Write-Log "The backup may have saved to a subfolder - check $BackupDest manually." 'WARNING'
}

Write-Log "=========================================="
Write-Log "Macrium Reflect Backup Script Complete" 'SUCCESS'
Write-Log "=========================================="
