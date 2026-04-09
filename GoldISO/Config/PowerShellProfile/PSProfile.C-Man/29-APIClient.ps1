<#
.SYNOPSIS
    API Client module for C-Man's PowerShell Profile.
.DESCRIPTION
    REST client with session management, OAuth2 flow helpers, response
    caching, request history, environment-aware base URLs, and collection
    management (Postman-like).
.NOTES
    Module: 29-APIClient.ps1
    Requires: PowerShell 5.1+
#>

#region ── State ──────────────────────────────────────────────────────────────

$script:ApiSessions = @{}
$script:RequestHistory = [System.Collections.Generic.List[hashtable]]::new()
$script:ResponseCache = @{}
$script:MaxHistorySize = 100

#endregion

#region ── Session Management ─────────────────────────────────────────────────

<#
.SYNOPSIS
    Creates or updates a named API session with base URL and default headers.
.PARAMETER Name
    Session name.
.PARAMETER BaseUrl
    Base URL for all requests in this session.
.PARAMETER Headers
    Default headers for all requests.
.PARAMETER BearerToken
    Bearer token for Authorization header.
.PARAMETER ApiKey
    API key (added as X-API-Key header).
.EXAMPLE
    New-ApiSession -Name 'github' -BaseUrl 'https://api.github.com' -BearerToken 'ghp_xxx'
.EXAMPLE
    apisession github https://api.github.com
#>
function New-ApiSession {
    [CmdletBinding()]
    [OutputType([void])]
    param(
        [Parameter(Mandatory, Position = 0)]
        [string]$Name,

        [Parameter(Mandatory, Position = 1)]
        [string]$BaseUrl,

        [Parameter()]
        [hashtable]$Headers = @{},

        [Parameter()]
        [string]$BearerToken,

        [Parameter()]
        [string]$ApiKey
    )

    $sessionHeaders = @{ 'Accept' = 'application/json' }
    foreach ($key in $Headers.Keys) { $sessionHeaders[$key] = $Headers[$key] }
    if (-not [string]::IsNullOrEmpty($BearerToken)) { $sessionHeaders['Authorization'] = "Bearer $BearerToken" }
    if (-not [string]::IsNullOrEmpty($ApiKey)) { $sessionHeaders['X-API-Key'] = $ApiKey }

    $script:ApiSessions[$Name] = @{
        BaseUrl   = $BaseUrl.TrimEnd('/')
        Headers   = $sessionHeaders
        CreatedAt = [datetime]::UtcNow.ToString('o')
    }

    Write-Host "  Session '$Name' created: $BaseUrl" -ForegroundColor $script:Theme.Success
}

<#
.SYNOPSIS
    Lists active API sessions.
.EXAMPLE
    Show-ApiSessions
#>
function Show-ApiSessions {
    [CmdletBinding()]
    [OutputType([void])]
    param()

    Write-Host "`n  API Sessions" -ForegroundColor $script:Theme.Primary
    Write-Host "  $('─' * 50)" -ForegroundColor $script:Theme.Muted

    if ($script:ApiSessions.Count -eq 0) {
        Write-Host '  (none)' -ForegroundColor $Global:Theme.Muted
        return
    }

    foreach ($name in ($script:ApiSessions.Keys | Sort-Object)) {
        $session = $script:ApiSessions[$name]
        Write-Host "  $($name.PadRight(18))" -ForegroundColor $script:Theme.Accent -NoNewline
        Write-Host "$($session.BaseUrl)" -ForegroundColor $script:Theme.Text
    }
    Write-Host ''
}

<#
.SYNOPSIS
    Removes an API session.
.PARAMETER Name
    Session name.
.EXAMPLE
    Remove-ApiSession -Name 'github'
#>
function Remove-ApiSession {
    [CmdletBinding()]
    [OutputType([void])]
    param(
        [Parameter(Mandatory, Position = 0)]
        [string]$Name
    )

    if ($script:ApiSessions.ContainsKey($Name)) {
        $script:ApiSessions.Remove($Name)
        Write-Host "  Session '$Name' removed." -ForegroundColor $script:Theme.Warning
    }
    else {
        Write-Warning -Message "Session '$Name' not found."
    }
}

#endregion

#region ── Request Engine ─────────────────────────────────────────────────────

<#
.SYNOPSIS
    Makes an API request using a session or direct URL.
.DESCRIPTION
    Flexible HTTP client with session support, automatic JSON handling,
    response timing, caching, and history tracking.
.PARAMETER Session
    Named session to use.
.PARAMETER Path
    URL path (appended to session base URL) or full URL.
.PARAMETER Method
    HTTP method.
.PARAMETER Body
    Request body (object or string).
.PARAMETER Headers
    Additional headers (merged with session headers).
.PARAMETER Query
    Query string parameters as hashtable.
.PARAMETER Cache
    Cache the response for this many seconds.
.PARAMETER Raw
    Return raw PSCustomObject instead of formatted output.
.EXAMPLE
    Invoke-ApiRequest -Session 'github' -Path '/user/repos' -Method GET
.EXAMPLE
    api github /user/repos
.EXAMPLE
    api github /repos -Method POST -Body @{ name = 'new-repo'; private = $true }
#>
function Invoke-ApiRequest {
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Position = 0)]
        [string]$Session,

        [Parameter(Mandatory, Position = 1)]
        [string]$Path,

        [Parameter(Position = 2)]
        [ValidateSet('GET', 'POST', 'PUT', 'PATCH', 'DELETE', 'HEAD', 'OPTIONS')]
        [string]$Method = 'GET',

        [Parameter()]
        [object]$Body,

        [Parameter()]
        [hashtable]$Headers = @{},

        [Parameter()]
        [hashtable]$Query,

        [Parameter()]
        [int]$Cache = 0,

        [Parameter()]
        [switch]$Raw
    )

    # Build URL
    $url = if (-not [string]::IsNullOrEmpty($Session) -and $script:ApiSessions.ContainsKey($Session)) {
        $s = $script:ApiSessions[$Session]
        "$($s.BaseUrl)/$($Path.TrimStart('/'))"
    }
    elseif ($Path -match '^https?://') {
        $Path
    }
    else {
        Write-Warning -Message "Session '$Session' not found and path is not a full URL."
        return $null
    }

    # Add query parameters
    if ($null -ne $Query -and $Query.Count -gt 0) {
        $qs = ($Query.GetEnumerator() | ForEach-Object -Process { "$($_.Key)=$([uri]::EscapeDataString($_.Value))" }) -join '&'
        $url = "${url}?${qs}"
    }

    # Check cache
    $cacheKey = "$Method`:$url"
    if ($Cache -gt 0 -and $script:ResponseCache.ContainsKey($cacheKey)) {
        $cached = $script:ResponseCache[$cacheKey]
        $age = ([datetime]::UtcNow - [datetime]::Parse($cached.Timestamp)).TotalSeconds
        if ($age -lt $Cache) {
            if (-not $Raw) {
                Write-Host "  (cached, ${([math]::Round($age))}s old)" -ForegroundColor $script:Theme.Muted
            }
            return $cached.Data
        }
    }

    # Build request
    $requestHeaders = @{}
    if (-not [string]::IsNullOrEmpty($Session) -and $script:ApiSessions.ContainsKey($Session)) {
        foreach ($key in $script:ApiSessions[$Session].Headers.Keys) {
            $requestHeaders[$key] = $script:ApiSessions[$Session].Headers[$key]
        }
    }
    foreach ($key in $Headers.Keys) { $requestHeaders[$key] = $Headers[$key] }

    $params = @{
        Uri             = $url
        Method          = $Method
        Headers         = $requestHeaders
        UseBasicParsing = $true
        ErrorAction     = 'Stop'
    }

    if ($null -ne $Body) {
        if ($Body -is [hashtable] -or $Body -is [PSCustomObject]) {
            $params['Body'] = ($Body | ConvertTo-Json -Depth 10)
            $params['ContentType'] = 'application/json'
        }
        else {
            $params['Body'] = $Body.ToString()
            $params['ContentType'] = 'application/json'
        }
    }

    $sw = [System.Diagnostics.Stopwatch]::StartNew()

    try {
        $response = Invoke-WebRequest @params
        $sw.Stop()

        $statusCode = $response.StatusCode
        $contentType = $response.Headers['Content-Type']
        $data = if ($contentType -match 'json') {
            $response.Content | ConvertFrom-Json
        }
        else {
            $response.Content
        }

        # Cache
        if ($Cache -gt 0 -and $Method -eq 'GET') {
            $script:ResponseCache[$cacheKey] = @{
                Data      = $data
                Timestamp = [datetime]::UtcNow.ToString('o')
            }
        }

        # History
        $historyEntry = @{
            Url       = $url
            Method    = $Method
            Status    = $statusCode
            TimeMs    = $sw.ElapsedMilliseconds
            Timestamp = [datetime]::UtcNow.ToString('o')
        }
        $script:RequestHistory.Add($historyEntry)
        while ($script:RequestHistory.Count -gt $script:MaxHistorySize) {
            $script:RequestHistory.RemoveAt(0)
        }

        if (-not $Raw) {
            $statusColor = if ($statusCode -lt 300) { $Global:Theme.Success }
                elseif ($statusCode -lt 400) { $Global:Theme.Warning }
                else { $Global:Theme.Error }

            Write-Host "  $Method $url" -ForegroundColor $script:Theme.Primary
            Write-Host "  $statusCode ($($sw.ElapsedMilliseconds)ms)" -ForegroundColor $statusColor
        }

        return $data
    }
    catch {
        $sw.Stop()
        $statusCode = if ($_.Exception.Response) { [int]$_.Exception.Response.StatusCode } else { 0 }
        $errorBody = ''
        if ($_.Exception.Response) {
            try {
                $reader = [System.IO.StreamReader]::new($_.Exception.Response.GetResponseStream())
                $errorBody = $reader.ReadToEnd()
                $reader.Close()
            }
            catch { }
        }

        $script:RequestHistory.Add(@{
            Url = $url; Method = $Method; Status = $statusCode
            TimeMs = $sw.ElapsedMilliseconds; Timestamp = [datetime]::UtcNow.ToString('o')
            Error = $_.Exception.Message
        })

        if (-not $Raw) {
            Write-Host "  $Method $url" -ForegroundColor $script:Theme.Primary
            Write-Host "  ERROR $statusCode ($($sw.ElapsedMilliseconds)ms)" -ForegroundColor $script:Theme.Error
            if (-not [string]::IsNullOrEmpty($errorBody)) {
                try {
                    $formatted = $errorBody | ConvertFrom-Json | ConvertTo-Json -Depth 5
                    Write-Host $formatted -ForegroundColor $Global:Theme.Muted
                }
                catch {
                    $preview = if ($errorBody.Length -gt 200) { $errorBody.Substring(0, 197) + '...' } else { $errorBody }
                    Write-Host "  $preview" -ForegroundColor $script:Theme.Muted
                }
            }
        }
        return $null
    }
}

#endregion

#region ── Request History ────────────────────────────────────────────────────

<#
.SYNOPSIS
    Shows recent API request history.
.PARAMETER Count
    Number of entries to show.
.EXAMPLE
    Show-ApiHistory -Count 20
.EXAMPLE
    apihist
#>
function Show-ApiHistory {
    [CmdletBinding()]
    [OutputType([void])]
    param(
        [Parameter()]
        [ValidateRange(1, 100)]
        [int]$Count = 15
    )

    Write-Host "`n  API Request History" -ForegroundColor $script:Theme.Primary
    Write-Host "  $('─' * 65)" -ForegroundColor $script:Theme.Muted

    if ($script:RequestHistory.Count -eq 0) {
        Write-Host '  (no history)' -ForegroundColor $Global:Theme.Muted
        return
    }

    $entries = $script:RequestHistory | Select-Object -Last $Count
    foreach ($entry in $entries) {
        $statusColor = if ($entry['Status'] -lt 300) { $Global:Theme.Success }
            elseif ($entry['Status'] -lt 400) { $Global:Theme.Warning }
            else { $Global:Theme.Error }

        $time = [datetime]::Parse($entry['Timestamp']).ToLocalTime().ToString('HH:mm:ss')
        $urlShort = $entry['Url']
        if ($urlShort.Length -gt 40) { $urlShort = $urlShort.Substring(0, 37) + '...' }

        Write-Host "  $time " -ForegroundColor $script:Theme.Muted -NoNewline
        Write-Host "$($entry['Method'].PadRight(7))" -ForegroundColor $script:Theme.Accent -NoNewline
        Write-Host "$($entry['Status'].ToString().PadRight(5))" -ForegroundColor $statusColor -NoNewline
        Write-Host "$($entry['TimeMs'].ToString().PadLeft(5))ms " -ForegroundColor $script:Theme.Muted -NoNewline
        Write-Host "$urlShort" -ForegroundColor $script:Theme.Text
    }
    Write-Host ''
}

<#
.SYNOPSIS
    Clears the response cache.
.EXAMPLE
    Clear-ApiCache
#>
function Clear-ApiCache {
    [CmdletBinding()]
    [OutputType([void])]
    param()

    $count = $script:ResponseCache.Count
    $script:ResponseCache.Clear()
    Write-Host "  Cleared $count cached response(s)." -ForegroundColor $script:Theme.Warning
}

#endregion

#region ── OAuth2 Helpers ─────────────────────────────────────────────────────

<#
.SYNOPSIS
    Performs OAuth2 client_credentials token exchange.
.PARAMETER TokenUrl
    Token endpoint URL.
.PARAMETER ClientId
    Client ID.
.PARAMETER ClientSecret
    Client secret.
.PARAMETER Scope
    Requested scopes (space-separated).
.EXAMPLE
    $token = Get-OAuth2Token -TokenUrl 'https://auth.example.com/token' -ClientId 'xxx' -ClientSecret 'yyy'
#>
function Get-OAuth2Token {
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory)]
        [string]$TokenUrl,

        [Parameter(Mandatory)]
        [string]$ClientId,

        [Parameter(Mandatory)]
        [string]$ClientSecret,

        [Parameter()]
        [string]$Scope
    )

    $body = @{
        grant_type    = 'client_credentials'
        client_id     = $ClientId
        client_secret = $ClientSecret
    }
    if (-not [string]::IsNullOrEmpty($Scope)) { $body['scope'] = $Scope }

    try {
        $response = Invoke-RestMethod -Uri $TokenUrl -Method POST -Body $body -ContentType 'application/x-www-form-urlencoded' -ErrorAction Stop

        Write-Host "  Token obtained (expires in $($response.expires_in)s)" -ForegroundColor $script:Theme.Success
        return $response
    }
    catch {
        Write-Warning -Message "Token exchange failed: $($_.Exception.Message)"
        return $null
    }
}

#endregion

#region ── Aliases ─────────────────────────────────────────────────────────────

Set-Alias -Name 'api'         -Value 'Invoke-ApiRequest'    -Scope Global -Force
Set-Alias -Name 'apisession'  -Value 'New-ApiSession'       -Scope Global -Force
Set-Alias -Name 'apils'       -Value 'Show-ApiSessions'     -Scope Global -Force
Set-Alias -Name 'apirm'       -Value 'Remove-ApiSession'    -Scope Global -Force
Set-Alias -Name 'apihist'     -Value 'Show-ApiHistory'      -Scope Global -Force
Set-Alias -Name 'oauth2'      -Value 'Get-OAuth2Token'      -Scope Global -Force

#endregion

#region ── Tab Completion ─────────────────────────────────────────────────────

Register-ArgumentCompleter -CommandName @('Invoke-ApiRequest', 'Remove-ApiSession') -ParameterName 'Session' -ScriptBlock {
    param($commandName, $parameterName, $wordToComplete, $commandAst, $fakeBoundParameters)

    $script:ApiSessions.Keys | Where-Object -FilterScript { $_ -like "${wordToComplete}*" } | ForEach-Object -Process {
        [System.Management.Automation.CompletionResult]::new($_, $_, 'ParameterValue', $script:ApiSessions[$_].BaseUrl)
    }
}

#endregion

