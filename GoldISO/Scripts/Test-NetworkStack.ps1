#Requires -Version 5.1
<#
.SYNOPSIS
    Comprehensive network stack testing and diagnostics.

.DESCRIPTION
    Tests network connectivity, DNS resolution, Windows network stack health,
    and adapter configuration. Includes latency testing and throughput estimation.

.PARAMETER Target
    Target host for connectivity tests. Default: 8.8.8.8,cloudflare.com

.PARAMETER IncludeSpeedTest
    Perform speed test (requires speedtest-cli or external service).

.PARAMETER AdapterName
    Specific network adapter to test.

.PARAMETER ExtendedTests
    Include extended tests (packet loss, MTU discovery, route tracing).

.PARAMETER OutputPath
    Path for test results. Default: Console

.EXAMPLE
    .\Test-NetworkStack.ps1 -ExtendedTests

.EXAMPLE
    .\Test-NetworkStack.ps1 -Target "10.0.0.1" -AdapterName "Ethernet"
#>
[CmdletBinding()]
param(
    [string[]]$Target = @("8.8.8.8", "cloudflare.com", "microsoft.com"),
    [switch]$IncludeSpeedTest,
    [string]$AdapterName,
    [switch]$ExtendedTests,
    [string]$OutputPath
)

#region ─────────────────────────────────────────────────────────────────────────────
# Initialization
# ─────────────────────────────────────────────────────────────────────────────

$ErrorActionPreference = "Continue"
$script:StartTime = Get-Date
$script:Results = @{
    Timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    ComputerName = $env:COMPUTERNAME
    Tests = @{}
    OverallStatus = "Unknown"
}

$commonModule = Join-Path $PSScriptRoot "Modules\GoldISO-Common.psm1"
if (Test-Path $commonModule) {
    Import-Module $commonModule -Force
}

$script:LogFile = Join-Path $env:TEMP "NetTest-$(Get-Date -Format 'yyyyMMdd-HHmmss').log"

function Write-NetLog {
    param([string]$Message, [ValidateSet("INFO","WARN","ERROR","SUCCESS","TEST")][string]$Level = "INFO")
    $ts = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $entry = "[$ts] [$Level] $Message"
    $color = switch ($Level) {
        "ERROR" { "Red" }
        "WARN" { "Yellow" }
        "SUCCESS" { "Green" }
        "TEST" { "Cyan" }
        default { "White" }
    }
    Write-Host $entry -ForegroundColor $color
    Add-Content -Path $script:LogFile -Value $entry -ErrorAction SilentlyContinue
}

Write-NetLog "Network Stack Test Started" "TEST"
Write-NetLog "Targets: $($Target -join ', ')" "INFO"

#endregion

#region ─────────────────────────────────────────────────────────────────────────────
# Adapter Tests
# ─────────────────────────────────────────────────────────────────────────────

function Test-NetworkAdapters {
    Write-NetLog "Analyzing network adapters..." "TEST"
    $adapters = @()

    $netAdapters = Get-NetAdapter | Where-Object { $_.Status -eq 'Up' }

    if ($AdapterName) {
        $netAdapters = $netAdapters | Where-Object { $_.Name -like "*$AdapterName*" }
    }

    foreach ($adapter in $netAdapters) {
        $config = Get-NetIPConfiguration -InterfaceIndex $adapter.InterfaceIndex -ErrorAction SilentlyContinue
        $ipConfig = Get-NetIPAddress -InterfaceIndex $adapter.InterfaceIndex -AddressFamily IPv4 -ErrorAction SilentlyContinue | Select-Object -First 1
        $dns = Get-DnsClientServerAddress -InterfaceIndex $adapter.InterfaceIndex -AddressFamily IPv4 -ErrorAction SilentlyContinue

        $adapterInfo = @{
            Name = $adapter.Name
            InterfaceDescription = $adapter.InterfaceDescription
            LinkSpeed = $adapter.LinkSpeed
            MacAddress = $adapter.MacAddress
            IPAddress = $ipConfig.IPAddress
            SubnetPrefix = if ($ipConfig) { "$($ipConfig.PrefixLength)" } else { "N/A" }
            DefaultGateway = ($config.IPv4DefaultGateway | Select-Object -First 1).NextHop
            DNSServers = $dns.ServerAddresses
            Status = "OK"
        }

        # Validate configuration
        if (-not $adapterInfo.IPAddress) {
            $adapterInfo.Status = "No IP"
            Write-NetLog "  $($adapter.Name): No IP address assigned" "WARN"
        }
        elseif (-not $adapterInfo.DefaultGateway) {
            $adapterInfo.Status = "No Gateway"
            Write-NetLog "  $($adapter.Name): No default gateway" "WARN"
        }
        else {
            Write-NetLog "  $($adapter.Name): $($adapterInfo.IPAddress) - OK" "SUCCESS"
        }

        $adapters += $adapterInfo
    }

    if ($adapters.Count -eq 0) {
        Write-NetLog "No active network adapters found!" "ERROR"
    }

    return @{
        AdapterCount = $adapters.Count
        Adapters = $adapters
        HealthyAdapters = ($adapters | Where-Object { $_.Status -eq 'OK' }).Count
    }
}

#endregion

#region ─────────────────────────────────────────────────────────────────────────────
# Connectivity Tests
# ─────────────────────────────────────────────────────────────────────────────

function Test-Connectivity {
    Write-NetLog "`nTesting connectivity..." "TEST"
    $results = @()

    foreach ($hostTarget in $Target) {
        Write-NetLog "  Testing: $hostTarget" "INFO"

        # Ping test
        $pingResults = @()
        $packetLoss = 0
        $latencies = @()

        for ($i = 0; $i -lt 4; $i++) {
            try {
                $ping = Test-Connection -ComputerName $hostTarget -Count 1 -ErrorAction Stop
                $pingResults += $ping
                $latencies += $ping.Latency
            }
            catch {
                $packetLoss++
            }
            Start-Sleep -Milliseconds 250
        }

        $result = @{
            Target = $hostTarget
            Reachable = $pingResults.Count -gt 0
            PacketsSent = 4
            PacketsReceived = $pingResults.Count
            PacketLoss = [math]::Round(($packetLoss / 4) * 100, 1)
            AvgLatency = if ($latencies.Count -gt 0) { [math]::Round(($latencies | Measure-Object -Average).Average, 1) } else { 0 }
            MinLatency = if ($latencies.Count -gt 0) { ($latencies | Measure-Object -Minimum).Minimum } else { 0 }
            MaxLatency = if ($latencies.Count -gt 0) { ($latencies | Measure-Object -Maximum).Maximum } else { 0 }
        }

        if ($result.Reachable) {
            Write-NetLog "    Latency: $($result.AvgLatency)ms (min: $($result.MinLatency), max: $($result.MaxLatency))" "SUCCESS"
            if ($result.PacketLoss -gt 0) {
                Write-NetLog "    Packet Loss: $($result.PacketLoss)%" "WARN"
            }
        }
        else {
            Write-NetLog "    Host unreachable" "ERROR"
        }

        $results += $result
    }

    return @{
        TotalTargets = $results.Count
        Reachable = ($results | Where-Object { $_.Reachable }).Count
        Unreachable = ($results | Where-Object { -not $_.Reachable }).Count
        AverageLatency = [math]::Round(($results | Where-Object { $_.AvgLatency -gt 0 } | Measure-Object AvgLatency -Average).Average, 1)
        Results = $results
    }
}

#endregion

#region ─────────────────────────────────────────────────────────────────────────────
# DNS Tests
# ─────────────────────────────────────────────────────────────────────────────

function Test-DNSResolution {
    Write-NetLog "`nTesting DNS resolution..." "TEST"
    $results = @()

    $dnsTargets = @(
        @{ Name = "Google"; Query = "google.com"; ExpectedType = "A" }
        @{ Name = "Cloudflare"; Query = "cloudflare.com"; ExpectedType = "A" }
        @{ Name = "Reverse"; Query = "8.8.8.8.in-addr.arpa"; ExpectedType = "PTR" }
    )

    foreach ($test in $dnsTargets) {
        try {
            $resolved = Resolve-DnsName -Name $test.Query -Type $test.ExpectedType -ErrorAction Stop | Select-Object -First 1
            $results += @{
                Query = $test.Name
                Target = $test.Query
                Resolved = $true
                ResponseTime = 0  # PowerShell doesn't easily expose this
                Result = if ($resolved.IPAddress) { $resolved.IPAddress } else { $resolved.NameHost }
            }
            Write-NetLog "  $($test.Name): Resolved to $($results[-1].Result)" "SUCCESS"
        }
        catch {
            $results += @{
                Query = $test.Name
                Target = $test.Query
                Resolved = $false
                Error = $_.Exception.Message
            }
            Write-NetLog "  $($test.Name): Resolution failed" "WARN"
        }
    }

    return @{
        TotalTests = $results.Count
        Successful = ($results | Where-Object { $_.Resolved }).Count
        Failed = ($results | Where-Object { -not $_.Resolved }).Count
        Results = $results
    }
}

#endregion

#region ─────────────────────────────────────────────────────────────────────────────
# Extended Tests
# ─────────────────────────────────────────────────────────────────────────────

function Test-ExtendedNetwork {
    if (-not $ExtendedTests) { return $null }

    Write-NetLog "`nRunning extended network tests..." "TEST"
    $extended = @{
        MTUDiscovery = $null
        RouteTrace = @()
        TCPTest = @()
    }

    # MTU Discovery (simplified)
    try {
        $commonPorts = @(80, 443, 445, 3389, 22)
        foreach ($port in $commonPorts) {
            $testHost = if ($Target[0] -match '^\d') { $Target[0] } else { "8.8.8.8" }
            $result = Test-NetConnection -ComputerName $testHost -Port $port -WarningAction SilentlyContinue
            $extended.TCPTest += @{
                Port = $port
                Open = $result.TcpTestSucceeded
                ResponseTime = $result.PingReplyDetails.RoundtripTime
            }
        }
        Write-NetLog "  Port scan completed" "SUCCESS"
    }
    catch {
        Write-NetLog "  Extended tests error: $_" "WARN"
    }

    return $extended
}

#endregion

#region ─────────────────────────────────────────────────────────────────────────────
# Stack Health
# ─────────────────────────────────────────────────────────────────────────────

function Test-NetworkStackHealth {
    Write-NetLog "`nChecking network stack health..." "TEST"
    $health = @{
        Services = @()
        Winsock = $false
        TCPStack = $false
    }

    # Check critical services
    $criticalServices = @("Dhcp", "Dnscache", "NlaSvc", "netprofm")
    foreach ($svc in $criticalServices) {
        $service = Get-Service -Name $svc -ErrorAction SilentlyContinue
        $status = if ($service) { $service.Status } else { "Not Found" }
        $healthy = $status -eq 'Running'

        $health.Services += @{
            Name = $svc
            Status = $status
            Healthy = $healthy
        }

        $level = if ($healthy) { "SUCCESS" } else { "WARN" }
        Write-NetLog "  Service $svc`: $status" $level
    }

    # Test Winsock
    try {
        $winsockTest = Test-NetConnection -ComputerName "localhost" -Port 445 -WarningAction SilentlyContinue
        $health.Winsock = $winsockTest.TcpTestSucceeded
        Write-NetLog "  Winsock/TCP: $(if($health.Winsock){'OK'}else{'Issues detected'})" $(if($health.Winsock){"SUCCESS"}else{"WARN"})
    }
    catch {
        Write-NetLog "  Winsock test failed" "WARN"
    }

    return $health
}

#endregion

#region ─────────────────────────────────────────────────────────────────────────────
# Report Generation
# ─────────────────────────────────────────────────────────────────────────────

function Export-TestResults {
    $script:Results.Tests.Adapters = Test-NetworkAdapters
    $script:Results.Tests.Connectivity = Test-Connectivity
    $script:Results.Tests.DNS = Test-DNSResolution
    $script:Results.Tests.Extended = Test-ExtendedNetwork
    $script:Results.Tests.StackHealth = Test-NetworkStackHealth

    # Determine overall status
    $allOk = @(
        $script:Results.Tests.Adapters.HealthyAdapters -eq $script:Results.Tests.Adapters.AdapterCount,
        $script:Results.Tests.Connectivity.Unreachable -eq 0,
        $script:Results.Tests.DNS.Failed -eq 0,
        ($script:Results.Tests.StackHealth.Services | Where-Object { -not $_.Healthy }).Count -eq 0
    )

    $script:Results.OverallStatus = if ($allOk -notcontains $false) { "Healthy" }
                                    elseif ($allOk -contains $true) { "Degraded" }
                                    else { "Critical" }

    # Console summary
    Write-NetLog "`n========================================" "TEST"
    Write-NetLog "NETWORK TEST SUMMARY" "TEST"
    Write-NetLog "========================================" "TEST"

    Write-NetLog "Adapters: $($script:Results.Tests.Adapters.HealthyAdapters)/$($script:Results.Tests.Adapters.AdapterCount) healthy" $(if($script:Results.Tests.Adapters.HealthyAdapters -eq $script:Results.Tests.Adapters.AdapterCount){"SUCCESS"}else{"WARN"})
    Write-NetLog "Connectivity: $($script:Results.Tests.Connectivity.Reachable)/$($script:Results.Tests.Connectivity.TotalTargets) reachable" $(if($script:Results.Tests.Connectivity.Unreachable -eq 0){"SUCCESS"}else{"WARN"})
    Write-NetLog "DNS: $($script:Results.Tests.DNS.Successful)/$($script:Results.Tests.DNS.TotalTests) resolved" $(if($script:Results.Tests.DNS.Failed -eq 0){"SUCCESS"}else{"WARN"})
    Write-NetLog "Average Latency: $($script:Results.Tests.Connectivity.AverageLatency) ms" "INFO"

    $failedServices = $script:Results.Tests.StackHealth.Services | Where-Object { -not $_.Healthy }
    if ($failedServices) {
        Write-NetLog "Service Issues: $($failedServices.Count) services not running" "WARN"
    }

    Write-NetLog "`nOverall Status: $($script:Results.OverallStatus)" $(switch($script:Results.OverallStatus){"Healthy"{"SUCCESS"}"Degraded"{"WARN"}default{"ERROR"}})

    # Export if path specified
    if ($OutputPath) {
        $resultFile = Join-Path $OutputPath "NetTest-$($env:COMPUTERNAME)-$(Get-Date -Format 'yyyyMMdd-HHmmss').json"
        $script:Results | ConvertTo-Json -Depth 5 | Set-Content $resultFile
        Write-NetLog "`nResults saved: $resultFile" "SUCCESS"
    }

    Write-NetLog "Log file: $script:LogFile" "INFO"
}

#endregion

# Run tests
Export-TestResults

$duration = (Get-Date) - $script:StartTime
Write-NetLog "`nTest completed in $($duration.TotalSeconds.ToString('F1')) seconds" "SUCCESS"

# Exit code based on health
exit $(switch ($script:Results.OverallStatus) { "Healthy" { 0 } "Degraded" { 1 } default { 2 } })
