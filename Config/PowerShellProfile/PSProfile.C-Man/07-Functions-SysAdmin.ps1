[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingWriteHost', '', Justification = 'Admin tool output requires colored display')]
param()

#region ── Windows Services ───────────────────────────────────────────────────

function Find-Service {
    <#
    .SYNOPSIS
        Search for Windows services by name pattern with status coloring.
    .PARAMETER Name
        Wildcard pattern to match service name or display name.
    #>
    [CmdletBinding()]
    [Alias('svcfind')]
    param(
        [Parameter(Mandatory, Position = 0)]
        [string]$Name
    )

    $tc = $Global:Theme
    Get-Service | Where-Object -FilterScript {
        $_.Name -like "*$Name*" -or $_.DisplayName -like "*$Name*"
    } | ForEach-Object -Process {
        $statusColor = switch ($_.Status) {
            'Running' { $tc.Success }
            'Stopped' { $tc.Error }
            default   { $tc.Warning }
        }
        Write-Host -Object "  $($_.Status.ToString().PadRight(10))" -ForegroundColor $statusColor -NoNewline
        Write-Host -Object "$($_.Name.PadRight(30))" -ForegroundColor $tc.Accent -NoNewline
        Write-Host -Object $_.DisplayName -ForegroundColor $tc.Text
    }
}

function Restart-ServiceSafe {
    <#
    .SYNOPSIS
        Restart a service with timeout and status verification.
    .PARAMETER Name
        Service name.
    .PARAMETER TimeoutSeconds
        Max wait time for service to restart.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    [Alias('svcrestart')]
    param(
        [Parameter(Mandatory, Position = 0)]
        [string]$Name,

        [int]$TimeoutSeconds = 30
    )

    $tc = $script:Theme
    $service = Get-Service -Name $Name -ErrorAction SilentlyContinue
    if ($null -eq $service) {
        Write-Warning -Message "Service not found: $Name"
        return
    }

    if ($PSCmdlet.ShouldProcess($Name, 'Restart')) {
        Write-Host -Object "  Restarting $Name..." -ForegroundColor $tc.Warning
        try {
            $service | Restart-Service -Force -ErrorAction Stop
            $service.WaitForStatus('Running', [TimeSpan]::FromSeconds($TimeoutSeconds))
            Write-Host -Object "  $Name is running." -ForegroundColor $tc.Success
        }
        catch {
            Write-Warning -Message "Failed to restart $Name`: $($_.Exception.Message)"
        }
    }
}

function Get-ServicesByStartType {
    <#
    .SYNOPSIS
        List services grouped by start type (Automatic, Manual, Disabled).
    .PARAMETER StartType
        Filter by start type.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Position = 0)]
        [ValidateSet('Automatic', 'Manual', 'Disabled', 'All')]
        [string]$StartType = 'All'
    )

    $services = Get-CimInstance -ClassName Win32_Service
    if ($StartType -ne 'All') {
        $services = $services | Where-Object -FilterScript { $_.StartMode -eq $StartType }
    }

    $services | Sort-Object -Property StartMode, Name |
        Format-Table -Property Name, DisplayName, State, StartMode -AutoSize
}

#endregion

#region ── Network Utilities ──────────────────────────────────────────────────

function Test-PortOpen {
    <#
    .SYNOPSIS
        Test if a TCP port is open on a remote host.
    .PARAMETER ComputerName
        Target host.
    .PARAMETER Port
        Port number to test.
    .PARAMETER TimeoutMs
        Connection timeout in milliseconds.
    #>
    [CmdletBinding()]
    [Alias('testport')]
    param(
        [Parameter(Mandatory, Position = 0)]
        [string]$ComputerName,

        [Parameter(Mandatory, Position = 1)]
        [int]$Port,

        [int]$TimeoutMs = 3000
    )

    $tc = $script:Theme
    $tcpClient = [System.Net.Sockets.TcpClient]::new()
    try {
        $result = $tcpClient.BeginConnect($ComputerName, $Port, $null, $null)
        $success = $result.AsyncWaitHandle.WaitOne($TimeoutMs)
        if ($success -and $tcpClient.Connected) {
            Write-Host -Object "  $ComputerName`:$Port is OPEN" -ForegroundColor $tc.Success
            return $true
        }
        else {
            Write-Host -Object "  $ComputerName`:$Port is CLOSED/FILTERED" -ForegroundColor $tc.Error
            return $false
        }
    }
    catch {
        Write-Host -Object "  $ComputerName`:$Port - Error: $($_.Exception.Message)" -ForegroundColor $tc.Error
        return $false
    }
    finally {
        $tcpClient.Close()
    }
}

function Invoke-MultiPing {
    <#
    .SYNOPSIS
        Ping multiple hosts in parallel with color-coded results.
    .PARAMETER ComputerName
        Array of hostnames or IPs to ping.
    .PARAMETER Count
        Number of pings per host.
    #>
    [CmdletBinding()]
    [Alias('mping')]
    param(
        [Parameter(Mandatory, Position = 0)]
        [string[]]$ComputerName,

        [int]$Count = 4
    )

    $tc = $script:Theme
    foreach ($host_ in $ComputerName) {
        $results = Test-Connection -ComputerName $host_ -Count $Count -ErrorAction SilentlyContinue
        if ($results) {
            $avgMs = [math]::Round(($results | Measure-Object -Property ResponseTime -Average).Average, 1)
            $loss = [math]::Round((($Count - $results.Count) / $Count) * 100, 0)
            $color = if ($avgMs -lt 50) { $tc.Success } elseif ($avgMs -lt 200) { $tc.Warning } else { $tc.Error }
            Write-Host -Object "  $($host_.PadRight(25))" -ForegroundColor $tc.Accent -NoNewline
            Write-Host -Object "Avg: ${avgMs}ms  Loss: ${loss}%" -ForegroundColor $color
        }
        else {
            Write-Host -Object "  $($host_.PadRight(25))" -ForegroundColor $tc.Accent -NoNewline
            Write-Host -Object 'UNREACHABLE' -ForegroundColor $tc.Error
        }
    }
}

function Get-NetworkAdapterInfo {
    <#
    .SYNOPSIS
        Display active network adapters with IP configuration.
    #>
    [CmdletBinding()]
    [Alias('netinfo')]
    param()

    $tc = $script:Theme
    $adapters = Get-NetAdapter | Where-Object -FilterScript { $_.Status -eq 'Up' }

    foreach ($adapter in $adapters) {
        $ipConfig = Get-NetIPAddress -InterfaceIndex $adapter.ifIndex -AddressFamily IPv4 -ErrorAction SilentlyContinue
        $gateway = Get-NetRoute -InterfaceIndex $adapter.ifIndex -DestinationPrefix '0.0.0.0/0' -ErrorAction SilentlyContinue |
            Select-Object -First 1 -ExpandProperty NextHop
        $dns = Get-DnsClientServerAddress -InterfaceIndex $adapter.ifIndex -AddressFamily IPv4 -ErrorAction SilentlyContinue

        Write-Host -Object "`n  $($adapter.Name) ($($adapter.InterfaceDescription))" -ForegroundColor $tc.Primary
        Write-Host -Object "    Status:  " -ForegroundColor $tc.Muted -NoNewline
        Write-Host -Object "Up ($($adapter.LinkSpeed))" -ForegroundColor $tc.Success
        if ($ipConfig) {
            Write-Host -Object "    IP:      " -ForegroundColor $tc.Muted -NoNewline
            Write-Host -Object "$($ipConfig.IPAddress)/$($ipConfig.PrefixLength)" -ForegroundColor $tc.Text
        }
        if ($gateway) {
            Write-Host -Object "    Gateway: " -ForegroundColor $tc.Muted -NoNewline
            Write-Host -Object $gateway -ForegroundColor $tc.Text
        }
        if ($dns.ServerAddresses) {
            Write-Host -Object "    DNS:     " -ForegroundColor $tc.Muted -NoNewline
            Write-Host -Object ($dns.ServerAddresses -join ', ') -ForegroundColor $tc.Text
        }
        Write-Host -Object "    MAC:     " -ForegroundColor $tc.Muted -NoNewline
        Write-Host -Object $adapter.MacAddress -ForegroundColor $tc.Muted
    }
    Write-Host ''
}

#endregion

#region ── Firewall Management ────────────────────────────────────────────────

function Find-FirewallRule {
    <#
    .SYNOPSIS
        Search firewall rules by name or port.
    .PARAMETER Name
        Rule name pattern.
    .PARAMETER Port
        Port number to find rules for.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Position = 0)]
        [string]$Name,

        [int]$Port
    )

    $rules = Get-NetFirewallRule -ErrorAction SilentlyContinue

    if ($Name) {
        $rules = $rules | Where-Object -FilterScript { $_.DisplayName -like "*$Name*" }
    }

    if ($Port) {
        $portFilters = Get-NetFirewallPortFilter -ErrorAction SilentlyContinue
        $matchingRuleNames = $portFilters | Where-Object -FilterScript {
            $_.LocalPort -contains $Port -or $_.RemotePort -contains $Port
        } | Select-Object -ExpandProperty InstanceID

        $rules = $rules | Where-Object -FilterScript { $matchingRuleNames -contains $_.Name }
    }

    $rules | Select-Object -Property DisplayName, Direction, Action, Enabled, Profile |
        Format-Table -AutoSize
}

function New-FirewallPortRule {
    <#
    .SYNOPSIS
        Quick-create a firewall rule to allow inbound traffic on a port.
    .PARAMETER DisplayName
        Human-readable rule name.
    .PARAMETER Port
        Port to open.
    .PARAMETER Protocol
        TCP or UDP.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)]
        [string]$DisplayName,

        [Parameter(Mandatory)]
        [int]$Port,

        [ValidateSet('TCP', 'UDP')]
        [string]$Protocol = 'TCP'
    )

    if ($PSCmdlet.ShouldProcess("Port $Port ($Protocol)", "Create firewall rule '$DisplayName'")) {
        New-NetFirewallRule -DisplayName $DisplayName -Direction Inbound -Action Allow `
            -Protocol $Protocol -LocalPort $Port
        Write-Host -Object "  Firewall rule created: $DisplayName (Port $Port/$Protocol)" -ForegroundColor $script:Theme.Success
    }
}

#endregion

#region ── SSH Helpers ─────────────────────────────────────────────────────────

function Get-SSHConnections {
    <#
    .SYNOPSIS
        List configured SSH hosts from ~/.ssh/config.
    #>
    [CmdletBinding()]
    [Alias('sshlist')]
    param()

    $sshConfigPath = Join-Path -Path $env:USERPROFILE -ChildPath '.ssh' | Join-Path -ChildPath 'config'
    if (-not (Test-Path -Path $sshConfigPath)) {
        Write-Warning -Message 'No SSH config found at ~/.ssh/config'
        return
    }

    $tc = $Global:Theme
    $content = Get-Content -Path $sshConfigPath
    $currentHost = $null
    $hostInfo = @{}

    foreach ($line in $content) {
        $trimmed = $line.Trim()
        if ($trimmed -match '^Host\s+(.+)$' -and $trimmed -notmatch '\*') {
            if ($currentHost -and $hostInfo.Count -gt 0) {
                Write-Host -Object "  $($currentHost.PadRight(20))" -ForegroundColor $tc.Accent -NoNewline
                Write-Host -Object ($hostInfo.Values -join '  ') -ForegroundColor $tc.Text
            }
            $currentHost = $Matches[1]
            $hostInfo = @{}
        }
        elseif ($trimmed -match '^HostName\s+(.+)$') {
            $hostInfo['host'] = $Matches[1]
        }
        elseif ($trimmed -match '^User\s+(.+)$') {
            $hostInfo['user'] = "User:$($Matches[1])"
        }
        elseif ($trimmed -match '^Port\s+(.+)$') {
            $hostInfo['port'] = "Port:$($Matches[1])"
        }
    }
    # Output last host
    if ($currentHost -and $hostInfo.Count -gt 0) {
        Write-Host -Object "  $($currentHost.PadRight(20))" -ForegroundColor $tc.Accent -NoNewline
        Write-Host -Object ($hostInfo.Values -join '  ') -ForegroundColor $tc.Text
    }
}

#endregion

#region ── Hyper-V Helpers ────────────────────────────────────────────────────

if (Get-Command -Name 'Get-VM' -ErrorAction SilentlyContinue) {
    function Get-VMSummary {
        <#
        .SYNOPSIS
            Quick overview of all Hyper-V VMs with status and resource usage.
        #>
        [CmdletBinding()]
        [Alias('vms')]
        param()

        $tc = $script:Theme
        Get-VM | ForEach-Object -Process {
            $statusColor = switch ($_.State) {
                'Running' { $tc.Success }
                'Off'     { $tc.Error }
                default   { $tc.Warning }
            }
            $memGb = [math]::Round($_.MemoryAssigned / 1GB, 1)
            Write-Host -Object "  $($_.State.ToString().PadRight(10))" -ForegroundColor $statusColor -NoNewline
            Write-Host -Object "$($_.Name.PadRight(25))" -ForegroundColor $tc.Accent -NoNewline
            Write-Host -Object "CPU: $($_.ProcessorCount)  Mem: ${memGb}GB  Uptime: $($_.Uptime)" -ForegroundColor $tc.Text
        }
    }

    function Start-VMQuick {
        <#
        .SYNOPSIS
            Start a VM and optionally connect to it.
        .PARAMETER Name
            VM name.
        .PARAMETER Connect
            Also open VMConnect window.
        #>
        [CmdletBinding()]
        param(
            [Parameter(Mandatory, Position = 0)]
            [string]$Name,

            [switch]$Connect
        )

        Start-VM -Name $Name
        Write-Host -Object "  Starting VM: $Name" -ForegroundColor $script:Theme.Success
        if ($Connect) {
            & vmconnect.exe localhost $Name
        }
    }
}

#endregion

#region ── Admin Elevation ────────────────────────────────────────────────────

function Enter-AdminSession {
    <#
    .SYNOPSIS
        Open a new elevated PowerShell session.
    #>
    [CmdletBinding()]
    [Alias('sudo')]
    param()

    $psExe = if ($PSVersionTable.PSVersion.Major -ge 7) { 'pwsh.exe' } else { 'powershell.exe' }
    Start-Process -FilePath $psExe -Verb RunAs -ArgumentList "-NoExit -Command Set-Location '$((Get-Location).Path)'"
}

function Test-IsAdmin {
    <#
    .SYNOPSIS
        Check if current session is elevated.
    #>
    [CmdletBinding()]
    param()

    ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
        [Security.Principal.WindowsBuiltInRole]::Administrator
    )
}

#endregion

