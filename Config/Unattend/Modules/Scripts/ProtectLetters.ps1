#Requires -Version 5.1
<#
.SYNOPSIS
    Protects reserved drive letters from being claimed by removable media.
.DESCRIPTION
    Detects removable volumes that have stolen a reserved letter and reassigns them
    to an available fallback letter. Designed to run as a FirstLogonCommand before
    folder creation commands so that D:, E:, R:, etc. are available at the expected letters.

    Protected letters by layout:
      GamerOS-3Disk: D, E, F, C, U, V, W, X, Y, Z, R, T, M
      (S and B are folder names inside D: and E:, not drive letters)

.NOTES
    Run as FirstLogonCommand BEFORE any command that creates folders on D: or E:.
    Requires no external modules - uses built-in PowerShell cmdlets.
#>
[CmdletBinding()]
param(
    # Letters that must not be occupied by removable media
    [string[]]$ProtectedLetters = @('D','E','F','C','U','V','W','X','Y','Z','R','T','M'),

    # Fallback pool used when reassigning a conflicting removable drive
    [string[]]$FallbackLetters  = @('H','I','J','K','L','N','O','P','Q')
)

$ErrorActionPreference = 'Stop'

function Write-ProtectLog {
    param([string]$Message, [string]$Level = 'INFO')
    $ts = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    Write-Host "[$ts] [$Level] $Message"
    $logDir = 'C:\ProgramData\GoldISO\Logs'
    if (-not (Test-Path $logDir)) { New-Item -ItemType Directory -Path $logDir -Force | Out-Null }
    "[$ts] [$Level] $Message" | Add-Content -Path (Join-Path $logDir 'ProtectLetters.log') -Encoding UTF8
}

Write-ProtectLog "ProtectLetters.ps1 started"
Write-ProtectLog "Protected letters: $($ProtectedLetters -join ', ')"

try {
    $removableVolumes = Get-Volume -ErrorAction SilentlyContinue |
        Where-Object { $_.DriveType -eq 'Removable' -and $_.DriveLetter }

    if (-not $removableVolumes) {
        Write-ProtectLog "No removable volumes found - nothing to reassign"
        exit 0
    }

    foreach ($vol in $removableVolumes) {
        $letter = $vol.DriveLetter

        if ($ProtectedLetters -contains $letter) {
            Write-ProtectLog "Removable volume is occupying protected letter '$($letter):' - reassigning" 'WARN'

            # Find first fallback letter not already in use
            $usedLetters = (Get-Volume -ErrorAction SilentlyContinue |
                Where-Object { $_.DriveLetter } |
                ForEach-Object { $_.DriveLetter })

            $newLetter = $FallbackLetters | Where-Object { $usedLetters -notcontains $_ } | Select-Object -First 1

            if ($newLetter) {
                try {
                    # Get-Partition to obtain the disk/partition object for Set-Partition
                    $partition = Get-Partition -DriveLetter $letter -ErrorAction Stop
                    Set-Partition -InputObject $partition -NewDriveLetter $newLetter -ErrorAction Stop
                    Write-ProtectLog "Reassigned removable drive '$($letter):' -> '$($newLetter):'" 'INFO'
                } catch {
                    Write-ProtectLog "Failed to reassign '$($letter):': $($_.Exception.Message)" 'ERROR'
                }
            } else {
                Write-ProtectLog "No available fallback letter to reassign '$($letter):' - protected letter remains occupied" 'ERROR'
            }
        } else {
            Write-ProtectLog "Removable volume at '$($letter):' does not conflict with protected letters"
        }
    }
}
catch {
    Write-ProtectLog "Unexpected error: $($_.Exception.Message)" 'ERROR'
    exit 1
}

Write-ProtectLog "ProtectLetters.ps1 completed"
