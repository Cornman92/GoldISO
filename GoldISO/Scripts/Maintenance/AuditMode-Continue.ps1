#Requires -Version 5.1
#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Desktop shortcut script to continue from Audit Mode to OOBE.
.DESCRIPTION
    This script is placed on the desktop during Audit Mode.
    When run, it triggers the system to proceed to OOBE (Out-of-Box Experience)
    and complete Windows setup.
.EXAMPLE
    Double-click "Continue to OOBE.lnk" on the desktop
    or run from PowerShell: .\AuditMode-Continue.ps1
#>
[CmdletBinding()]
param()

Add-Type -AssemblyName System.Windows.Forms

# Confirmation dialog
$result = [System.Windows.Forms.MessageBox]::Show(
    "This will complete Windows Setup and proceed to the Out-of-Box Experience (OOBE).`n`n" +
    "Make sure:`n" +
    "  - All your settings and applications are configured`n" +
    "  - You want to finalize this Windows installation`n`n" +
    "The system will reboot and continue setup.`n`n" +
    "Continue?",
    "Continue to OOBE",
    [System.Windows.Forms.MessageBoxButtons]::YesNo,
    [System.Windows.Forms.MessageBoxIcon]::Question
)

if ($result -eq [System.Windows.Forms.DialogResult]::Yes) {
    Write-Host "Preparing to continue to OOBE..." -ForegroundColor Cyan
    
    # Run sysprep to generalize and reboot to OOBE
    $sysprepPath = "C:\Windows\System32\Sysprep\Sysprep.exe"
    
    if (Test-Path $sysprepPath) {
        Write-Host "Running Sysprep to generalize and reboot to OOBE..." -ForegroundColor Yellow
        
        # /oobe - Start in OOBE mode
        # /generalize - Remove system-specific info
        # /reboot - Reboot after sysprep completes
        $arguments = "/oobe /generalize /reboot"
        
        try {
            Start-Process -FilePath $sysprepPath -ArgumentList $arguments -Wait -NoNewWindow
        }
        catch {
            Write-Error "Failed to run Sysprep: $_"
            [System.Windows.Forms.MessageBox]::Show(
                "Failed to run Sysprep: $_`n`nYou can try running it manually from:`n$sysprepPath",
                "Error",
                [System.Windows.Forms.MessageBoxButtons]::OK,
                [System.Windows.Forms.MessageBoxIcon]::Error
            )
        }
    } else {
        Write-Error "Sysprep not found at expected location"
        [System.Windows.Forms.MessageBox]::Show(
            "Sysprep not found at:`n$sysprepPath`n`nThis script must be run on a Windows installation in Audit Mode.",
            "Error",
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Error
        )
    }
} else {
    Write-Host "Cancelled. System will remain in Audit Mode." -ForegroundColor Yellow
}
