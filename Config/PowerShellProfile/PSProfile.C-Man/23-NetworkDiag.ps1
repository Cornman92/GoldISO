<#
.SYNOPSIS
    Network Diagnostics module for C-Man's PowerShell Profile.
.DESCRIPTION
    Traceroute with latency heatmap, DNS lookup chain, SSL certificate
    inspector, HTTP request builder, bandwidth estimation, proxy detector,
    and mDNS/service scanner.
.NOTES
    Module: 23-NetworkDiag.ps1
    Requires: PowerShell 5.1+
#>

#region ── DNS Lookup ─────────────────────────────────────────────────────────

<#
.SYNOPSIS
    Performs DNS lookups with multiple record types.
.PARAMETER Name
    Hostname to resolve.
.PARAMETER Type
    DNS record type.
.PARAMETER Server
    DNS server to query.
.EXAMPLE
    Resolve-DnsLookup -Name 'github.com' -Type A
.EXAMPLE
    dns github.com MX
#>
function Resolve-DnsLookup {
    [CmdletBinding()]
    [OutputType([void])]
    param(
        [Parameter(Mandatory, Position = 0)]
        [string]$Name,

        [Parameter(Position = 1)]
        [ValidateSet('A', 'AAAA', 'CNAME', 'MX', 'NS', 'TXT', 'SOA', 'SRV', 'PTR', 'ANY')]
        [string]$Type = 'A',

        [Parameter()]
        [string]$Server
    )

    Write-Host "`n  DNS Lookup: $Name ($Type)" -ForegroundColor $script:Theme.Primary
    Write-Host "  $('─' * 50)" -ForegroundColor $script:Theme.Muted

    try {
        $sw = [System.Diagnostics.Stopwatch]::StartNew()

        if ($Type -eq 'ANY') {
            foreach ($t in @('A', 'AAAA', 'CNAME', 'MX', 'NS', 'TXT')) {
                $results = Resolve-DnsName -Name $Name -Type $t -ErrorAction SilentlyContinue
                if ($null -ne $results) {
                    Write-Host "  [$t]" -ForegroundColor $script:Theme.Accent
                    foreach ($r in $results) {
                        $value = switch ($t) {
                            'A'     { $r.IPAddress }
                            'AAAA'  { $r.IPAddress }
                            'CNAME' { $r.NameHost }
                            'MX'    { "$($r.Preference) $($r.NameExchange)" }
                            'NS'    { $r.NameHost }
                            'TXT'   { ($r.Strings -join ' ') }
                            default { $r.ToString() }
                        }
                        if ($null -ne $value) {
                            Write-Host "    $value" -ForegroundColor $script:Theme.Text
                        }
                    }
                }
            }
        }
        else {
            $results = Resolve-DnsName -Name $Name -Type $Type -ErrorAction Stop
            foreach ($r in $results) {
                $value = switch ($Type) {
                    'A'     { $r.IPAddress }
                    'AAAA'  { $r.IPAddress }
                    'CNAME' { $r.NameHost }
                    'MX'    { "Priority: $($r.Preference)  Exchange: $($r.NameExchange)" }
                    'NS'    { $r.NameHost }
                    'TXT'   { ($r.Strings -join ' ') }
                    'SOA'   { "Primary: $($r.PrimaryServer)  Admin: $($r.Administrator)" }
                    'SRV'   { "Priority: $($r.Priority) Port: $($r.Port) Target: $($r.NameTarget)" }
                    'PTR'   { $r.NameHost }
                    default { $r.ToString() }
                }
                if ($null -ne $value) {
                    Write-Host "  $value" -ForegroundColor $script:Theme.Text -NoNewline
                    Write-Host "  TTL: $($r.TTL)s" -ForegroundColor $script:Theme.Muted
                }
            }
        }

        $sw.Stop()
        Write-Host "`n  Resolved in $($sw.ElapsedMilliseconds)ms" -ForegroundColor $script:Theme.Muted
    }
    catch {
        Write-Warning -Message "DNS lookup failed: $($_.Exception.Message)"
    }
    Write-Host ''
}

#endregion

#region ── SSL Certificate Inspector ──────────────────────────────────────────

<#
.SYNOPSIS
    Inspects SSL/TLS certificate for a host.
.DESCRIPTION
    Connects to a host and retrieves the SSL certificate details
    including issuer, validity, SANs, and chain information.
.PARAMETER Host
    Hostname to inspect.
.PARAMETER Port
    Port number. Default is 443.
.EXAMPLE
    Show-SSLCertificate -Host 'github.com'
.EXAMPLE
    sslcheck google.com
#>
function Show-SSLCertificate {
    [CmdletBinding()]
    [OutputType([void])]
    param(
        [Parameter(Mandatory, Position = 0)]
        [string]$HostName,

        [Parameter()]
        [ValidateRange(1, 65535)]
        [int]$Port = 443
    )

    Write-Host "`n  SSL Certificate: $HostName`:$Port" -ForegroundColor $script:Theme.Primary
    Write-Host "  $('─' * 55)" -ForegroundColor $script:Theme.Muted

    try {
        $tcpClient = [System.Net.Sockets.TcpClient]::new()
        $tcpClient.Connect($HostName, $Port)

        $sslStream = [System.Net.Security.SslStream]::new(
            $tcpClient.GetStream(),
            $false,
            { param($s, $cert, $chain, $errors) return $true }
        )

        $sslStream.AuthenticateAsClient($HostName)
        $cert = [System.Security.Cryptography.X509Certificates.X509Certificate2]::new($sslStream.RemoteCertificate)

        $daysLeft = ($cert.NotAfter - [datetime]::Now).Days
        $expiryColor = if ($daysLeft -lt 7) { $Global:Theme.Error }
            elseif ($daysLeft -lt 30) { $Global:Theme.Warning }
            else { $Global:Theme.Success }

        $props = [ordered]@{
            'Subject'        = $cert.Subject
            'Issuer'         = $cert.Issuer
            'Valid From'     = $cert.NotBefore.ToString('yyyy-MM-dd HH:mm')
            'Valid Until'    = $cert.NotAfter.ToString('yyyy-MM-dd HH:mm')
            'Days Left'      = "$daysLeft days"
            'Serial'         = $cert.SerialNumber
            'Thumbprint'     = $cert.Thumbprint
            'Key Algorithm'  = $cert.PublicKey.Oid.FriendlyName
            'Key Size'       = "$($cert.PublicKey.Key.KeySize) bits"
            'TLS Version'    = $sslStream.SslProtocol.ToString()
            'Cipher'         = $sslStream.CipherAlgorithm.ToString()
        }

        foreach ($key in $props.Keys) {
            $color = if ($key -eq 'Days Left') { $expiryColor } else { $script:Theme.Text }
            Write-Host "  $($key.PadRight(18))" -ForegroundColor $script:Theme.Accent -NoNewline
            Write-Host "$($props[$key])" -ForegroundColor $color
        }

        # SANs
        $sanExt = $cert.Extensions | Where-Object -FilterScript { $_.Oid.FriendlyName -eq 'Subject Alternative Name' }
        if ($null -ne $sanExt) {
            $sans = $sanExt.Format($true) -split "`n" | ForEach-Object -Process { $_.Trim() } | Where-Object -FilterScript { $_ -match 'DNS' }
            if ($sans.Count -gt 0) {
                Write-Host "`n  SANs ($($sans.Count)):" -ForegroundColor $script:Theme.Primary
                foreach ($san in $sans | Select-Object -First 10) {
                    Write-Host "    $san" -ForegroundColor $script:Theme.Muted
                }
                if ($sans.Count -gt 10) {
                    Write-Host "    ... and $($sans.Count - 10) more" -ForegroundColor $script:Theme.Muted
                }
            }
        }

        $sslStream.Dispose()
        $tcpClient.Dispose()
        $cert.Dispose()
    }
    catch {
        Write-Warning -Message "SSL inspection failed: $($_.Exception.Message)"
    }
    Write-Host ''
}

#endregion

#region ── HTTP Request Builder ───────────────────────────────────────────────

<#
.SYNOPSIS
    Makes HTTP requests with detailed output.
.DESCRIPTION
    A curl-like HTTP client with colored output, timing breakdown,
    header display, and response body formatting.
.PARAMETER Url
    The URL to request.
.PARAMETER Method
    HTTP method. Default is GET.
.PARAMETER Body
    Request body (for POST/PUT/PATCH).
.PARAMETER Headers
    Additional headers as a hashtable.
.PARAMETER ContentType
    Content-Type header value.
.PARAMETER ShowHeaders
    Display response headers.
.PARAMETER Raw
    Return raw response object instead of formatted output.
.EXAMPLE
    Invoke-HttpRequest -Url 'https://api.github.com/zen'
.EXAMPLE
    http https://httpbin.org/post -Method POST -Body '{"key":"val"}' -ShowHeaders
#>
function Invoke-HttpRequest {
    [CmdletBinding()]
    [OutputType([void], [PSCustomObject])]
    param(
        [Parameter(Mandatory, Position = 0)]
        [string]$Url,

        [Parameter(Position = 1)]
        [ValidateSet('GET', 'POST', 'PUT', 'PATCH', 'DELETE', 'HEAD', 'OPTIONS')]
        [string]$Method = 'GET',

        [Parameter()]
        [string]$Body,

        [Parameter()]
        [hashtable]$Headers = @{},

        [Parameter()]
        [string]$ContentType = 'application/json',

        [Parameter()]
        [switch]$ShowHeaders,

        [Parameter()]
        [switch]$Raw
    )

    Write-Host "`n  $Method $Url" -ForegroundColor $script:Theme.Primary

    $sw = [System.Diagnostics.Stopwatch]::StartNew()

    try {
        $params = @{
            Uri    = $Url
            Method = $Method
            UseBasicParsing = $true
        }

        if ($Headers.Count -gt 0) { $params['Headers'] = $Headers }
        if (-not [string]::IsNullOrEmpty($Body)) {
            $params['Body'] = $Body
            $params['ContentType'] = $ContentType
        }

        $response = Invoke-WebRequest @params -ErrorAction Stop
        $sw.Stop()

        if ($Raw) { return $response }

        # Status
        $statusColor = if ($response.StatusCode -lt 300) { $Global:Theme.Success }
            elseif ($response.StatusCode -lt 400) { $Global:Theme.Warning }
            else { $Global:Theme.Error }

        Write-Host "  $('─' * 50)" -ForegroundColor $script:Theme.Muted
        Write-Host "  Status: $($response.StatusCode) $($response.StatusDescription)" -ForegroundColor $statusColor
        Write-Host "  Time:   $($sw.ElapsedMilliseconds)ms" -ForegroundColor $script:Theme.Muted
        Write-Host "  Size:   $('{0:N0}' -f $response.Content.Length) bytes" -ForegroundColor $script:Theme.Muted

        # Headers
        if ($ShowHeaders) {
            Write-Host "`n  Response Headers:" -ForegroundColor $script:Theme.Accent
            foreach ($key in ($response.Headers.Keys | Sort-Object)) {
                Write-Host "    $($key.PadRight(25))" -ForegroundColor $script:Theme.Text -NoNewline
                Write-Host "$($response.Headers[$key])" -ForegroundColor $script:Theme.Muted
            }
        }

        # Body
        $contentType = $response.Headers['Content-Type']
        if ($contentType -match 'json') {
            Write-Host "`n  Body (JSON):" -ForegroundColor $script:Theme.Accent
            try {
                $formatted = $response.Content | ConvertFrom-Json | ConvertTo-Json -Depth 10
                Write-Host $formatted -ForegroundColor $Global:Theme.Text
            }
            catch {
                Write-Host $response.Content -ForegroundColor $Global:Theme.Text
            }
        }
        else {
            $preview = $response.Content
            if ($preview.Length -gt 500) { $preview = $preview.Substring(0, 497) + '...' }
            Write-Host "`n  Body:" -ForegroundColor $script:Theme.Accent
            Write-Host "  $preview" -ForegroundColor $script:Theme.Text
        }
    }
    catch {
        $sw.Stop()
        $statusCode = if ($_.Exception.Response) { [int]$_.Exception.Response.StatusCode } else { 0 }
        Write-Host "  Error: $statusCode $($_.Exception.Message)" -ForegroundColor $script:Theme.Error
        Write-Host "  Time: $($sw.ElapsedMilliseconds)ms" -ForegroundColor $script:Theme.Muted
    }
    Write-Host ''
}

#endregion

#region ── Traceroute ─────────────────────────────────────────────────────────

<#
.SYNOPSIS
    Visual traceroute with latency heatmap.
.PARAMETER Destination
    Target hostname or IP.
.PARAMETER MaxHops
    Maximum hop count.
.EXAMPLE
    Invoke-VisualTraceroute -Destination 'google.com'
.EXAMPLE
    trace google.com
#>
function Invoke-VisualTraceroute {
    [CmdletBinding()]
    [OutputType([void])]
    param(
        [Parameter(Mandatory, Position = 0)]
        [string]$Destination,

        [Parameter()]
        [ValidateRange(1, 64)]
        [int]$MaxHops = 30
    )

    Write-Host "`n  Traceroute to $Destination (max $MaxHops hops)" -ForegroundColor $script:Theme.Primary
    Write-Host "  $('─' * 60)" -ForegroundColor $script:Theme.Muted

    try {
        $results = Test-NetConnection -ComputerName $Destination -TraceRoute -ErrorAction Stop -WarningAction SilentlyContinue

        if ($null -ne $results.TraceRoute) {
            $hopNum = 0
            foreach ($hop in $results.TraceRoute) {
                $hopNum++
                $latency = 0
                try {
                    $ping = Test-Connection -ComputerName $hop -Count 1 -TimeoutSeconds 2 -ErrorAction SilentlyContinue
                    if ($null -ne $ping) { $latency = $ping.Latency }
                }
                catch { }

                $latencyColor = if ($latency -eq 0) { $Global:Theme.Muted }
                    elseif ($latency -lt 20) { $Global:Theme.Success }
                    elseif ($latency -lt 100) { $Global:Theme.Warning }
                    else { $Global:Theme.Error }

                $bar = if ($latency -gt 0) { '█' * [math]::Min([math]::Ceiling($latency / 10), 30) } else { '?' }

                $hopStr = $hopNum.ToString().PadLeft(3)
                $latStr = if ($latency -gt 0) { "${latency}ms".PadRight(8) } else { '*'.PadRight(8) }

                # Try reverse DNS
                $hostName = try { [System.Net.Dns]::GetHostEntry($hop).HostName } catch { $hop }
                if ($hostName.Length -gt 35) { $hostName = $hostName.Substring(0, 32) + '...' }

                Write-Host "  $hopStr " -ForegroundColor $script:Theme.Accent -NoNewline
                Write-Host "$($hop.PadRight(16))" -ForegroundColor $script:Theme.Text -NoNewline
                Write-Host "$latStr" -ForegroundColor $latencyColor -NoNewline
                Write-Host "$bar " -ForegroundColor $latencyColor -NoNewline
                Write-Host "$hostName" -ForegroundColor $script:Theme.Muted
            }
        }

        $status = if ($results.TcpTestSucceeded) { 'Reachable' } else { 'Unreachable' }
        $statusColor = if ($results.TcpTestSucceeded) { $Global:Theme.Success } else { $Global:Theme.Error }
        Write-Host "`n  Destination: $status" -ForegroundColor $statusColor
    }
    catch {
        Write-Warning -Message "Traceroute failed: $($_.Exception.Message)"
    }
    Write-Host ''
}

#endregion

#region ── Port Scanner ───────────────────────────────────────────────────────

<#
.SYNOPSIS
    Scans common ports on a target host.
.PARAMETER Target
    Hostname or IP to scan.
.PARAMETER Ports
    Specific ports to scan. Defaults to common service ports.
.PARAMETER TimeoutMs
    Connection timeout in milliseconds.
.EXAMPLE
    Invoke-PortScan -Target 'localhost'
.EXAMPLE
    portscan 192.168.1.1 -Ports 80,443,8080,3389
#>
function Invoke-PortScan {
    [CmdletBinding()]
    [OutputType([void])]
    param(
        [Parameter(Mandatory, Position = 0)]
        [string]$Target,

        [Parameter(Position = 1)]
        [int[]]$Ports = @(21, 22, 23, 25, 53, 80, 110, 135, 139, 143, 443, 445, 993, 995, 1433, 1521, 3306, 3389, 5432, 5900, 6379, 8080, 8443, 9090, 27017),

        [Parameter()]
        [ValidateRange(100, 10000)]
        [int]$TimeoutMs = 1000
    )

    Write-Host "`n  Port Scan: $Target ($($Ports.Count) ports)" -ForegroundColor $script:Theme.Primary
    Write-Host "  $('─' * 50)" -ForegroundColor $script:Theme.Muted

    $open = 0
    foreach ($port in ($Ports | Sort-Object)) {
        $tcp = [System.Net.Sockets.TcpClient]::new()
        try {
            $result = $tcp.BeginConnect($Target, $port, $null, $null)
            $success = $result.AsyncWaitHandle.WaitOne($TimeoutMs, $false)

            if ($success -and $tcp.Connected) {
                $serviceName = switch ($port) {
                    21    { 'FTP' }     22   { 'SSH' }       23   { 'Telnet' }
                    25    { 'SMTP' }    53   { 'DNS' }       80   { 'HTTP' }
                    110   { 'POP3' }    135  { 'RPC' }       139  { 'NetBIOS' }
                    143   { 'IMAP' }    443  { 'HTTPS' }     445  { 'SMB' }
                    993   { 'IMAPS' }   995  { 'POP3S' }     1433 { 'MSSQL' }
                    1521  { 'Oracle' }  3306 { 'MySQL' }     3389 { 'RDP' }
                    5432  { 'PostgreSQL' } 5900 { 'VNC' }    6379 { 'Redis' }
                    8080  { 'HTTP-Alt' } 8443 { 'HTTPS-Alt' } 27017 { 'MongoDB' }
                    default { '' }
                }

                Write-Host "  OPEN  " -ForegroundColor $script:Theme.Success -NoNewline
                Write-Host "$($port.ToString().PadRight(8))" -ForegroundColor $script:Theme.Accent -NoNewline
                Write-Host "$serviceName" -ForegroundColor $script:Theme.Text
                $open++
            }
        }
        catch { }
        finally {
            $tcp.Close()
            $tcp.Dispose()
        }
    }

    $closed = $Ports.Count - $open
    Write-Host "`n  Results: $open open, $closed closed/filtered" -ForegroundColor $script:Theme.Muted
    Write-Host ''
}

#endregion

#region ── Network Speed Estimation ───────────────────────────────────────────

<#
.SYNOPSIS
    Estimates network speed with a download test.
.PARAMETER TestUrl
    URL to use for download test.
.EXAMPLE
    Test-NetworkSpeed
#>
function Test-NetworkSpeed {
    [CmdletBinding()]
    [OutputType([void])]
    param(
        [Parameter()]
        [string]$TestUrl = 'https://speed.cloudflare.com/__down?bytes=10000000'
    )

    Write-Host "`n  Network Speed Test" -ForegroundColor $script:Theme.Primary
    Write-Host "  $('─' * 40)" -ForegroundColor $script:Theme.Muted
    Write-Host '  Downloading test file...' -ForegroundColor $Global:Theme.Info

    try {
        $sw = [System.Diagnostics.Stopwatch]::StartNew()
        $response = Invoke-WebRequest -Uri $TestUrl -UseBasicParsing -ErrorAction Stop
        $sw.Stop()

        $bytes = $response.Content.Length
        $seconds = $sw.Elapsed.TotalSeconds
        $mbps = [math]::Round(($bytes * 8) / ($seconds * 1000000), 2)
        $mbytes = [math]::Round($bytes / 1048576, 2)

        $speedColor = if ($mbps -gt 100) { $Global:Theme.Success }
            elseif ($mbps -gt 10) { $Global:Theme.Warning }
            else { $Global:Theme.Error }

        Write-Host "  Downloaded: ${mbytes} MB in $([math]::Round($seconds, 2))s" -ForegroundColor $script:Theme.Muted
        Write-Host "  Speed:      $mbps Mbps" -ForegroundColor $speedColor
    }
    catch {
        Write-Warning -Message "Speed test failed: $($_.Exception.Message)"
    }
    Write-Host ''
}

#endregion

#region ── Aliases ─────────────────────────────────────────────────────────────

Set-Alias -Name 'dns'       -Value 'Resolve-DnsLookup'       -Scope Global -Force
Set-Alias -Name 'sslcheck'  -Value 'Show-SSLCertificate'     -Scope Global -Force
Set-Alias -Name 'http'      -Value 'Invoke-HttpRequest'      -Scope Global -Force
Set-Alias -Name 'trace'     -Value 'Invoke-VisualTraceroute' -Scope Global -Force
Set-Alias -Name 'portscan'  -Value 'Invoke-PortScan'         -Scope Global -Force
Set-Alias -Name 'speedtest' -Value 'Test-NetworkSpeed'        -Scope Global -Force

#endregion

