#Requires -Version 5.1
#Requires -RunAsAdministrator

# Import common module
Import-Module (Join-Path $PSScriptRoot "Modules\GoldISO-Common.psm1") -Force

<#
.SYNOPSIS
    Configure AnyDesk and Tailscale for remote access from iPhone (or any device).
.DESCRIPTION
    AnyDesk:
      - Waits for AnyDesk to be installed (installs via winget if missing).
      - Enables the AnyDesk Windows service with automatic start.
      - Sets an unattended-access password so the iPhone app can connect
        without someone clicking "Accept" on the desktop.
      - Reads and displays the AnyDesk address ID so you can add it on your phone.

    Tailscale:
      - Waits for Tailscale to be installed (installs via winget if missing).
      - Authenticates with Tailscale using an auth key (get one from
        https://login.tailscale.com/admin/settings/keys).
      - If no auth key is provided, launches the interactive Tailscale login
        page in the default browser.
      - Displays the assigned Tailscale IP for use with RDP apps on iPhone.

    Windows Remote Desktop (RDP):
      - Enables RDP in the registry.
      - Allows RDP through Windows Firewall (scoped to Tailscale subnet).
      - Ensures the current user can connect via RDP.

    iPhone setup instructions are printed at the end.

.PARAMETER AnyDeskPassword
    Unattended-access password for AnyDesk. Min 8 chars.
    If omitted you will be prompted (input is hidden).
.PARAMETER TailscaleAuthKey
    Tailscale pre-authentication key from https://login.tailscale.com/admin/settings/keys
    If omitted, interactive browser-based login is used.
.PARAMETER TailscaleHostname
    Hostname this machine registers with on Tailscale (default: current computer name).
.PARAMETER SkipAnyDesk
    Skip AnyDesk configuration entirely.
.PARAMETER SkipTailscale
    Skip Tailscale configuration entirely.
.PARAMETER SkipRDP
    Skip Windows Remote Desktop configuration.
.EXAMPLE
    .\Configure-RemoteAccess.ps1
    # Prompts for AnyDesk password, opens browser for Tailscale login
.EXAMPLE
    .\Configure-RemoteAccess.ps1 -AnyDeskPassword "MyPass123" -TailscaleAuthKey "tskey-auth-xxxx"
    # Fully unattended (suitable for autounattend.xml FirstLogonCommands)
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    [string]$AnyDeskPassword    = '',
    [string]$TailscaleAuthKey   = '',
    [string]$TailscaleHostname  = $env:COMPUTERNAME,
    [switch]$SkipAnyDesk,
    [switch]$SkipTailscale,
    [switch]$SkipRDP
)

$ErrorActionPreference = 'Continue'

# Initialize centralized logging
$logFile = Join-Path 'C:\ProgramData\GoldISO' 'remote-access.log'
Initialize-Logging -LogPath $logFile

function Wait-ForExe {
    param([string]$ExePath, [string]$WingetId, [int]$TimeoutSec = 120)
    if (Test-Path $ExePath) { return $ExePath }

    Write-Log "$ExePath not found - installing via winget ($WingetId)..." 'WARNING'
    winget install --id $WingetId --silent --accept-package-agreements --accept-source-agreements 2>&1 |
        ForEach-Object { Write-Log "  [winget] $_" }

    $waited = 0
    while (-not (Test-Path $ExePath)) {
        if ($waited -ge $TimeoutSec) { return $null }
        Start-Sleep -Seconds 5
        $waited += 5
    }
    return $ExePath
}

Write-Log "=========================================="
Write-Log "Remote Access Configuration - GoldISO"
Write-Log "=========================================="

# ==========================================================================
# ANYDESK
# ==========================================================================
if (-not $SkipAnyDesk) {
    Write-Log "--- AnyDesk ---"

    # Common install paths for AnyDesk
    $anyDeskPaths = @(
        'C:\Program Files (x86)\AnyDesk\AnyDesk.exe',
        'C:\Program Files\AnyDesk\AnyDesk.exe'
    )
    $anyDeskExe = $anyDeskPaths | Where-Object { Test-Path $_ } | Select-Object -First 1

    if (-not $anyDeskExe) {
        $anyDeskExe = Wait-ForExe -ExePath $anyDeskPaths[0] `
                                  -WingetId 'AnyDeskSoftwareGmbH.AnyDesk'
    }

    if (-not $anyDeskExe) {
        Write-Log "ERROR: AnyDesk.exe not found after install attempt - skipping AnyDesk config." 'ERROR'
    } else {
        Write-Log "AnyDesk found: $anyDeskExe" 'SUCCESS'

        # Ensure AnyDesk service is installed and set to auto-start
        $svc = Get-Service -Name AnyDesk -ErrorAction SilentlyContinue
        if (-not $svc) {
            Write-Log "Installing AnyDesk Windows service..."
            & $anyDeskExe --install-service 2>&1 | Out-Null
            Start-Sleep -Seconds 3
            $svc = Get-Service -Name AnyDesk -ErrorAction SilentlyContinue
        }
        if ($svc) {
            Set-Service -Name AnyDesk -StartupType Automatic
            if ($svc.Status -ne 'Running') { Start-Service -Name AnyDesk -ErrorAction SilentlyContinue }
            Write-Log "AnyDesk service: Running / Auto-start" 'SUCCESS'
        } else {
            Write-Log "AnyDesk service not found - starting in background mode instead." 'WARNING'
        }

        # Set unattended access password
        if (-not $AnyDeskPassword) {
            Write-Log "Enter AnyDesk unattended-access password (min 8 chars, input hidden):"
            $secPwd = Read-Host -AsSecureString
            $AnyDeskPassword = [Runtime.InteropServices.Marshal]::PtrToStringAuto(
                [Runtime.InteropServices.Marshal]::SecureStringToBSTR($secPwd))
        }

        if ($AnyDeskPassword.Length -lt 8) {
            Write-Log "WARNING: AnyDesk password is shorter than 8 characters - AnyDesk may reject it." 'WARNING'
        }

        if ($PSCmdlet.ShouldProcess('AnyDesk', 'Set unattended access password')) {
            & $anyDeskExe --set-password $AnyDeskPassword 2>&1 | Out-Null
            Write-Log "AnyDesk unattended password set." 'SUCCESS'
        }

        # Configure system.conf for headless / auto-accept sessions
        $anyDeskConf = 'C:\ProgramData\AnyDesk\system.conf'
        if (Test-Path (Split-Path $anyDeskConf)) {
            $confLines = @(
                'ad.security.interactive_access=2',   # 0=deny 1=ask 2=allow without confirmation
                'ad.security.allow_logon_token=true',
                'ad.headless=false'                   # keep GUI visible so user can see sessions
            )
            if (Test-Path $anyDeskConf) {
                $existing = Get-Content $anyDeskConf
                foreach ($line in $confLines) {
                    $key = $line.Split('=')[0]
                    $existing = $existing | Where-Object { -not $_.StartsWith($key) }
                    $existing += $line
                }
                $existing | Set-Content $anyDeskConf -Encoding UTF8
            } else {
                $confLines | Set-Content $anyDeskConf -Encoding UTF8
            }
            Write-Log "AnyDesk system.conf updated (interactive_access=allow)." 'SUCCESS'
        }

        # Restart service to pick up conf changes
        Restart-Service -Name AnyDesk -Force -ErrorAction SilentlyContinue
        Start-Sleep -Seconds 3

        # Get and display AnyDesk ID
        $anyDeskId = & $anyDeskExe --get-id 2>&1 | Select-Object -First 1
        if ($anyDeskId -match '\d') {
            Write-Log "AnyDesk ID: $anyDeskId" 'SUCCESS'
            Write-Log "  -> On iPhone: open AnyDesk app, tap the search/connect box, enter: $anyDeskId" 'SUCCESS'
            Write-Log "  -> Enter the password you just set when prompted." 'SUCCESS'
        } else {
            Write-Log "Could not retrieve AnyDesk ID automatically. Open AnyDesk to find it." 'WARNING'
        }
    }
}

# ==========================================================================
# TAILSCALE
# ==========================================================================
if (-not $SkipTailscale) {
    Write-Log "--- Tailscale ---"

    $tailscaleExe = 'C:\Program Files (x86)\Tailscale\tailscale.exe'
    if (-not (Test-Path $tailscaleExe)) {
        # Also check standard Program Files
        $tailscaleExe = 'C:\Program Files\Tailscale\tailscale.exe'
    }
    if (-not (Test-Path $tailscaleExe)) {
        # Try PATH
        $inPath = Get-Command tailscale -ErrorAction SilentlyContinue
        if ($inPath) { $tailscaleExe = $inPath.Source }
    }

    if (-not (Test-Path $tailscaleExe -ErrorAction SilentlyContinue)) {
        $tailscaleExe = Wait-ForExe -ExePath 'C:\Program Files (x86)\Tailscale\tailscale.exe' `
                                    -WingetId 'Tailscale.Tailscale'
    }

    if (-not $tailscaleExe -or -not (Test-Path $tailscaleExe)) {
        Write-Log "ERROR: tailscale.exe not found after install attempt - skipping Tailscale config." 'ERROR'
    } else {
        Write-Log "Tailscale found: $tailscaleExe" 'SUCCESS'

        # Ensure Tailscale service is running
        $tsvc = Get-Service -Name Tailscale -ErrorAction SilentlyContinue
        if ($tsvc -and $tsvc.Status -ne 'Running') {
            Start-Service -Name Tailscale -ErrorAction SilentlyContinue
            Start-Sleep -Seconds 3
        }

        # Authenticate / bring up the network
        if ($PSCmdlet.ShouldProcess('Tailscale', 'Connect to Tailscale network')) {
            if ($TailscaleAuthKey) {
                Write-Log "Authenticating Tailscale with auth key..."
                & $tailscaleExe up --authkey=$TailscaleAuthKey --hostname=$TailscaleHostname `
                                   --accept-dns=true --accept-routes=true 2>&1 |
                    ForEach-Object { Write-Log "  [tailscale] $_" }
            } else {
                Write-Log "No auth key provided - launching interactive Tailscale login..." 'WARNING'
                Write-Log "  A browser window will open. Log in and this machine will join your network."
                & $tailscaleExe up --hostname=$TailscaleHostname --accept-dns=true 2>&1 |
                    ForEach-Object { Write-Log "  [tailscale] $_" }
            }

            # Wait briefly for the connection to establish
            Start-Sleep -Seconds 5

            # Get Tailscale IP
            $tsIP = & $tailscaleExe ip -4 2>&1 | Select-Object -First 1
            if ($tsIP -match '^\d{1,3}\.') {
                Write-Log "Tailscale IPv4: $tsIP" 'SUCCESS'
                Write-Log "  -> On iPhone: install Tailscale from App Store, sign in with the SAME account." 'SUCCESS'
                Write-Log "  -> For RDP: install 'Microsoft Remote Desktop' on iPhone, add PC at: $tsIP" 'SUCCESS'
                Write-Log "  -> For AnyDesk over Tailscale: use AnyDesk normally (it will route through Tailscale)." 'SUCCESS'
            } else {
                Write-Log "Tailscale IP not yet assigned - connect may still be in progress." 'WARNING'
                Write-Log "  Run: tailscale ip -4   (after login completes) to get your IP." 'WARNING'
            }
        }
    }
}

# ==========================================================================
# WINDOWS REMOTE DESKTOP (RDP)
# ==========================================================================
if (-not $SkipRDP) {
    Write-Log "--- Windows Remote Desktop (RDP) ---"

    if ($PSCmdlet.ShouldProcess('Windows RDP', 'Enable remote desktop')) {
        # Enable RDP
        Set-ItemProperty -Path 'HKLM:\System\CurrentControlSet\Control\Terminal Server' `
                         -Name fDenyTSConnections -Value 0 -Type DWord -Force
        Write-Log "RDP enabled in registry." 'SUCCESS'

        # Disable NLA requirement (easier to connect from non-domain iOS clients;
        # comment this out if you want to keep NLA for stricter security)
        Set-ItemProperty -Path 'HKLM:\System\CurrentControlSet\Control\Terminal Server\WinStations\RDP-Tcp' `
                         -Name UserAuthentication -Value 0 -Type DWord -Force
        Write-Log "NLA disabled (allows iOS RDP clients without NLA support)." 'SUCCESS'

        # Allow RDP through Windows Firewall
        Enable-NetFirewallRule -DisplayGroup 'Remote Desktop' -ErrorAction SilentlyContinue
        Write-Log "Windows Firewall: Remote Desktop rules enabled." 'SUCCESS'

        # Scope the RDP firewall rule to the Tailscale subnet (100.64.0.0/10)
        # This keeps RDP closed to the LAN and internet, only reachable over Tailscale.
        $rdpRules = Get-NetFirewallRule -DisplayGroup 'Remote Desktop' -ErrorAction SilentlyContinue |
                    Where-Object { $_.Direction -eq 'Inbound' -and $_.Enabled -eq 'True' }
        foreach ($rule in $rdpRules) {
            try {
                $rule | Get-NetFirewallAddressFilter |
                    Set-NetFirewallAddressFilter -RemoteAddress '100.64.0.0/10' -ErrorAction Stop
                Write-Log ("RDP firewall rule scoped to Tailscale subnet: " + $rule.DisplayName) 'SUCCESS'
            } catch {
                Write-Log ("Could not scope rule '" + $rule.DisplayName + "': $_") 'WARNING'
            }
        }

        # Ensure current user is in Remote Desktop Users group
        $currentUser = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name
        try {
            Add-LocalGroupMember -Group 'Remote Desktop Users' -Member $currentUser -ErrorAction SilentlyContinue
            Write-Log "Added $currentUser to 'Remote Desktop Users' group." 'SUCCESS'
        } catch {
            Write-Log "User already in Remote Desktop Users or group not found: $_" 'WARNING'
        }

        Write-Log "RDP is now enabled and scoped to Tailscale (100.64.0.0/10)." 'SUCCESS'
    }
}

# ==========================================================================
# SUMMARY
# ==========================================================================
Write-Log ""
Write-Log "=========================================="
Write-Log "REMOTE ACCESS SETUP COMPLETE" 'SUCCESS'
Write-Log "=========================================="
Write-Log ""
Write-Log "=== iPhone Setup Instructions ==="
Write-Log ""
Write-Log "OPTION A - AnyDesk (easiest, works over any network):"
Write-Log "  1. Install 'AnyDesk Remote Desktop' from the App Store (free)"
Write-Log "  2. Tap the address bar, enter this machine's AnyDesk ID"
Write-Log "  3. Enter the unattended-access password when prompted"
Write-Log "  4. You're connected - no Tailscale needed for AnyDesk alone"
Write-Log ""
Write-Log "OPTION B - Tailscale + Microsoft RDP (best for full desktop, low latency on home network):"
Write-Log "  1. Install 'Tailscale' from the App Store and sign in with your Tailscale account"
Write-Log "  2. Install 'Microsoft Remote Desktop' from the App Store"
Write-Log "  3. In Microsoft Remote Desktop: tap '+' -> Add PC"
Write-Log "     PC Name: <Tailscale IP shown above, e.g. 100.x.x.x>"
Write-Log "     User account: <your Windows username>"
Write-Log "  4. Connect - you will see the full Windows desktop"
Write-Log ""
Write-Log "OPTION C - AnyDesk over Tailscale (most secure - encrypted twice):"
Write-Log "  Same as Option A but connect Tailscale on iPhone first."
Write-Log "  AnyDesk traffic routes through your Tailscale tunnel."
Write-Log ""
Write-Log "Log: $LogPath"
Write-Log "=========================================="
