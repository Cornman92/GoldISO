#Requires -Version 5.1
#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Configure RAM disk with browser cache, temp, and build cache redirects.
.DESCRIPTION
    Redirects the following to the RAM disk (default R:):
      - Microsoft Edge browser cache     (registry policy)
      - Google Chrome browser cache      (registry policy)
      - Opera GX browser cache           (registry policy + shortcut)
      - User TEMP / TMP                  (HKCU environment)
      - System TEMP / TMP                (HKLM environment)
      - npm cache                        (npm config + env var)
      - pip cache                        (env var)
      - NuGet cache                      (env var)
      - MSBuild / compiler temp          (via TEMP override already applied)
    All operations are idempotent and safe to re-run.
.PARAMETER RamDrive
    Drive letter of the RAM disk (default: R).
.PARAMETER SkipBrowserCache
    Skip browser cache redirects.
.PARAMETER SkipTempRedirect
    Skip TEMP/TMP folder redirects.
.PARAMETER SkipBuildCache
    Skip npm/pip/NuGet build cache redirects.
.PARAMETER WaitForDrive
    Seconds to wait for the RAM disk drive to appear before failing (default: 30).
.EXAMPLE
    .\Configure-RamDisk.ps1
.EXAMPLE
    .\Configure-RamDisk.ps1 -RamDrive S -SkipBuildCache
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    [string]$RamDrive         = 'R',
    [switch]$SkipBrowserCache,
    [switch]$SkipTempRedirect,
    [switch]$SkipBuildCache,
    [int]$WaitForDrive        = 30
)

$ErrorActionPreference = 'Continue'
$LogPath = 'C:\ProgramData\Winhance\Unattend\Logs\ramdisk-config.log'
$null = New-Item -Path (Split-Path $LogPath) -ItemType Directory -Force -ErrorAction SilentlyContinue

function Write-Log {
    param([string]$Message, [ValidateSet('INFO','SUCCESS','WARNING','ERROR')][string]$Level = 'INFO')
    $ts    = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    $entry = "[$ts] [$Level] $Message"
    Add-Content -Path $LogPath -Value $entry -Encoding UTF8 -ErrorAction SilentlyContinue
    $color = switch ($Level) { 'ERROR' { 'Red' } 'WARNING' { 'Yellow' } 'SUCCESS' { 'Green' } default { 'White' } }
    Write-Host $entry -ForegroundColor $color
}

function Ensure-Dir {
    param([string]$Path)
    if (-not (Test-Path $Path)) {
        New-Item -ItemType Directory -Path $Path -Force | Out-Null
        Write-Log "Created directory: $Path"
    }
}

function Set-RegValue {
    param([string]$Path, [string]$Name, $Value, [string]$Type = 'String')
    if (-not (Test-Path $Path)) {
        New-Item -Path $Path -Force | Out-Null
    }
    Set-ItemProperty -Path $Path -Name $Name -Value $Value -Type $Type -Force
}

# ---------------------------------------------------------------------------
# 0. Wait for RAM disk drive to be ready
# ---------------------------------------------------------------------------
$R = $RamDrive.TrimEnd(':') + ':'
Write-Log "============================================"
Write-Log "RAM Disk Configuration - Drive $R"
Write-Log "============================================"

$waited = 0
while (-not (Test-Path "$R\")) {
    if ($waited -ge $WaitForDrive) {
        Write-Log "ERROR: RAM disk drive $R not available after $WaitForDrive seconds." 'ERROR'
        Write-Log "Ensure SoftPerfect RAM Disk is installed and the disk is created." 'ERROR'
        exit 1
    }
    Write-Log "Waiting for $R\ ... ($waited/$WaitForDrive s)" 'WARNING'
    Start-Sleep -Seconds 5
    $waited += 5
}
Write-Log "RAM disk $R is available." 'SUCCESS'

# ---------------------------------------------------------------------------
# 1. Create directory structure on RAM disk
# ---------------------------------------------------------------------------
Write-Log "--- Creating RAM disk directory structure ---"
$dirs = @(
    "$R\BrowserCache\Edge",
    "$R\BrowserCache\Chrome",
    "$R\BrowserCache\OperaGX",
    "$R\Temp\User",
    "$R\Temp\System",
    "$R\BuildCache\npm",
    "$R\BuildCache\pip",
    "$R\BuildCache\nuget"
)
foreach ($d in $dirs) { Ensure-Dir $d }
Write-Log "Directory structure ready." 'SUCCESS'

# ---------------------------------------------------------------------------
# 2. Browser cache redirects
# ---------------------------------------------------------------------------
if (-not $SkipBrowserCache) {
    Write-Log "--- Browser cache redirects ---"

    # -- Edge (Chromium) --
    # Registry policy: HKLM\SOFTWARE\Policies\Microsoft\Edge  DiskCacheDir
    # Applies to all profiles on this machine. Takes effect on next Edge launch.
    if ($PSCmdlet.ShouldProcess('Microsoft Edge', 'Redirect disk cache')) {
        $edgePolicyPath = 'HKLM:\SOFTWARE\Policies\Microsoft\Edge'
        Set-RegValue -Path $edgePolicyPath -Name 'DiskCacheDir' -Value "$R\BrowserCache\Edge"
        Set-RegValue -Path $edgePolicyPath -Name 'DiskCacheSize' -Value 524288000 -Type 'DWord'  # 500 MB
        Write-Log "Edge cache redirected to $R\BrowserCache\Edge" 'SUCCESS'
    }

    # -- Chrome --
    # Registry policy: HKLM\SOFTWARE\Policies\Google\Chrome  DiskCacheDir
    if ($PSCmdlet.ShouldProcess('Google Chrome', 'Redirect disk cache')) {
        $chromePolicyPath = 'HKLM:\SOFTWARE\Policies\Google\Chrome'
        Set-RegValue -Path $chromePolicyPath -Name 'DiskCacheDir' -Value "$R\BrowserCache\Chrome"
        Set-RegValue -Path $chromePolicyPath -Name 'DiskCacheSize' -Value 524288000 -Type 'DWord'  # 500 MB
        Write-Log "Chrome cache redirected to $R\BrowserCache\Chrome" 'SUCCESS'
    }

    # -- Opera GX --
    # Opera Software policy path (Chromium-based, respects enterprise policy keys)
    if ($PSCmdlet.ShouldProcess('Opera GX', 'Redirect disk cache')) {
        $operaPolicyPath = 'HKLM:\SOFTWARE\Policies\OperaSoftware\Opera'
        Set-RegValue -Path $operaPolicyPath -Name 'DiskCacheDir' -Value "$R\BrowserCache\OperaGX"
        Set-RegValue -Path $operaPolicyPath -Name 'DiskCacheSize' -Value 524288000 -Type 'DWord'  # 500 MB
        Write-Log "Opera GX registry policy set to $R\BrowserCache\OperaGX" 'SUCCESS'

        # Also patch the launcher shortcut to include --disk-cache-dir flag as a belt-and-suspenders
        # approach since Opera GX's policy compliance varies between versions.
        $operaLaunchers = @(
            "$env:LOCALAPPDATA\Programs\Opera GX\launcher.exe",
            "$env:PROGRAMFILES\Opera GX\launcher.exe"
        )
        $operaStart = "$env:APPDATA\Microsoft\Windows\Start Menu\Programs\Opera GX\Opera GX.lnk"
        $desktopLnk = "$env:PUBLIC\Desktop\Opera GX.lnk"

        foreach ($lnkPath in @($operaStart, $desktopLnk)) {
            if (Test-Path $lnkPath) {
                try {
                    $shell   = New-Object -ComObject WScript.Shell
                    $lnk     = $shell.CreateShortcut($lnkPath)
                    $newArgs = $lnk.Arguments
                    $flag    = "--disk-cache-dir=`"$R\BrowserCache\OperaGX`""
                    if ($newArgs -notlike "*disk-cache-dir*") {
                        $lnk.Arguments = ($newArgs + " " + $flag).Trim()
                        $lnk.Save()
                        Write-Log "Opera GX shortcut patched: $lnkPath" 'SUCCESS'
                    } else {
                        Write-Log "Opera GX shortcut already has cache flag: $lnkPath"
                    }
                } catch {
                    Write-Log "Could not patch Opera GX shortcut $lnkPath`: $_" 'WARNING'
                }
            }
        }

        # Junction: if Opera GX has already created its cache directory, move it to RAM disk
        $operaProfile = "$env:APPDATA\Opera Software\Opera GX Stable"
        $operaCacheDir = "$operaProfile\Cache"
        if (Test-Path $operaProfile) {
            if ((Test-Path $operaCacheDir) -and -not ([System.IO.Directory]::Exists($operaCacheDir) -and
                (Get-Item $operaCacheDir).Attributes -band [System.IO.FileAttributes]::ReparsePoint)) {
                # Real directory exists, not yet a junction - move and create junction
                try {
                    $tmpCache = "$operaProfile\Cache_backup_$(Get-Date -Format 'yyyyMMddHHmm')"
                    Move-Item $operaCacheDir $tmpCache -Force
                    & cmd /c mklink /D "`"$operaCacheDir`"" "`"$R\BrowserCache\OperaGX`"" | Out-Null
                    Write-Log "Opera GX cache junction created (old cache moved to $tmpCache)" 'SUCCESS'
                    # Remove backup after small delay to confirm junction works
                    Start-Sleep -Seconds 1
                    if (Test-Path $operaCacheDir) { Remove-Item $tmpCache -Recurse -Force -ErrorAction SilentlyContinue }
                } catch {
                    Write-Log "Could not create Opera GX cache junction: $_" 'WARNING'
                }
            } elseif (-not (Test-Path $operaCacheDir)) {
                # Profile exists but no cache yet - pre-create junction
                try {
                    & cmd /c mklink /D "`"$operaCacheDir`"" "`"$R\BrowserCache\OperaGX`"" | Out-Null
                    Write-Log "Opera GX cache junction pre-created (profile exists, cache not yet)" 'SUCCESS'
                } catch {
                    Write-Log "Could not pre-create Opera GX cache junction: $_" 'WARNING'
                }
            } else {
                Write-Log "Opera GX cache is already a junction - skipping"
            }
        } else {
            Write-Log "Opera GX profile not yet created - registry policy will apply on first run"
        }
    }
} else {
    Write-Log "Skipping browser cache redirects (SkipBrowserCache set)" 'WARNING'
}

# ---------------------------------------------------------------------------
# 3. TEMP / TMP redirect
# ---------------------------------------------------------------------------
if (-not $SkipTempRedirect) {
    Write-Log "--- TEMP / TMP folder redirects ---"

    if ($PSCmdlet.ShouldProcess('User TEMP', 'Redirect to RAM disk')) {
        Set-RegValue -Path 'HKCU:\Environment' -Name 'TEMP' -Value "$R\Temp\User"
        Set-RegValue -Path 'HKCU:\Environment' -Name 'TMP'  -Value "$R\Temp\User"
        # Apply to current session immediately
        [System.Environment]::SetEnvironmentVariable('TEMP', "$R\Temp\User", 'User')
        [System.Environment]::SetEnvironmentVariable('TMP',  "$R\Temp\User", 'User')
        Write-Log "User TEMP redirected to $R\Temp\User" 'SUCCESS'
    }

    if ($PSCmdlet.ShouldProcess('System TEMP', 'Redirect to RAM disk')) {
        $sysEnvPath = 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Environment'
        Set-RegValue -Path $sysEnvPath -Name 'TEMP' -Value "$R\Temp\System"
        Set-RegValue -Path $sysEnvPath -Name 'TMP'  -Value "$R\Temp\System"
        [System.Environment]::SetEnvironmentVariable('TEMP', "$R\Temp\System", 'Machine')
        [System.Environment]::SetEnvironmentVariable('TMP',  "$R\Temp\System", 'Machine')
        Write-Log "System TEMP redirected to $R\Temp\System" 'SUCCESS'
    }

    # Broadcast WM_SETTINGCHANGE so running processes pick up new env vars
    try {
        $HWND_BROADCAST = [IntPtr]0xffff
        $WM_SETTINGCHANGE = 0x001A
        Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
public class WinMsg {
    [DllImport("user32.dll", SetLastError=true)]
    public static extern IntPtr SendMessageTimeout(IntPtr hWnd, uint Msg, IntPtr wParam,
        string lParam, uint fuFlags, uint uTimeout, out IntPtr lpdwResult);
}
'@ -ErrorAction SilentlyContinue
        $result = [IntPtr]::Zero
        [WinMsg]::SendMessageTimeout($HWND_BROADCAST, $WM_SETTINGCHANGE, [IntPtr]::Zero,
            'Environment', 2, 5000, [ref]$result) | Out-Null
        Write-Log "Environment change broadcast sent to running processes" 'SUCCESS'
    } catch {
        Write-Log "Could not broadcast environment change (non-fatal): $_" 'WARNING'
    }
} else {
    Write-Log "Skipping TEMP redirects (SkipTempRedirect set)" 'WARNING'
}

# ---------------------------------------------------------------------------
# 4. Build cache redirects
# ---------------------------------------------------------------------------
if (-not $SkipBuildCache) {
    Write-Log "--- Build cache redirects ---"

    # -- npm --
    $npmPath = Get-Command npm -ErrorAction SilentlyContinue
    if ($npmPath) {
        if ($PSCmdlet.ShouldProcess('npm cache', 'Redirect to RAM disk')) {
            try {
                & npm config set cache "$R\BuildCache\npm" --global 2>&1 | Out-Null
                Write-Log "npm cache redirected to $R\BuildCache\npm" 'SUCCESS'
            } catch {
                Write-Log "npm config set failed: $_" 'WARNING'
            }
        }
    } else {
        # npm not installed yet; set the env var so it picks it up when installed
        Set-RegValue -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Environment' `
                     -Name 'npm_config_cache' -Value "$R\BuildCache\npm"
        Write-Log "npm_config_cache env var pre-set to $R\BuildCache\npm (npm not yet installed)" 'SUCCESS'
    }

    # -- pip --
    if ($PSCmdlet.ShouldProcess('pip cache', 'Redirect to RAM disk')) {
        Set-RegValue -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Environment' `
                     -Name 'PIP_CACHE_DIR' -Value "$R\BuildCache\pip"
        [System.Environment]::SetEnvironmentVariable('PIP_CACHE_DIR', "$R\BuildCache\pip", 'Machine')
        Write-Log "PIP_CACHE_DIR set to $R\BuildCache\pip" 'SUCCESS'
    }

    # -- NuGet --
    if ($PSCmdlet.ShouldProcess('NuGet cache', 'Redirect to RAM disk')) {
        Set-RegValue -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Environment' `
                     -Name 'NUGET_PACKAGES' -Value "$R\BuildCache\nuget"
        [System.Environment]::SetEnvironmentVariable('NUGET_PACKAGES', "$R\BuildCache\nuget", 'Machine')
        Write-Log "NUGET_PACKAGES set to $R\BuildCache\nuget" 'SUCCESS'
    }

    # NOTE: cargo build artifacts (CARGO_TARGET_DIR) are intentionally NOT redirected
    # to the RAM disk - Rust builds can exceed 10-20 GB which would exhaust the RAM disk.
    # Set this per-project if needed: $env:CARGO_TARGET_DIR = "R:\BuildCache\cargo-target"

    Write-Log "Build cache redirect complete." 'SUCCESS'
} else {
    Write-Log "Skipping build cache redirects (SkipBuildCache set)" 'WARNING'
}

Write-Log "============================================"
Write-Log "RAM Disk Configuration Complete" 'SUCCESS'
Write-Log "NOTE: Browser cache changes take effect on next browser launch."
Write-Log "NOTE: TEMP changes take effect on next login / process start."
Write-Log "NOTE: RAM disk contents are VOLATILE - cleared on every reboot."
Write-Log "============================================"
