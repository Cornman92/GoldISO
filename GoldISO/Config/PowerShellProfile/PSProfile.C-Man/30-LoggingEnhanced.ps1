<#
.SYNOPSIS
    Enhanced Logging module for C-Man's PowerShell Profile.
.DESCRIPTION
    Structured JSON logging, log levels, rotation policies, correlation
    IDs, performance counters, and log querying capabilities.
.NOTES
    Module: 30-LoggingEnhanced.ps1
    Requires: PowerShell 5.1+
#>

#region ── Configuration ──────────────────────────────────────────────────────

$script:StructuredLogDir = Join-Path -Path $script:ProfileRoot -ChildPath 'Logs' -AdditionalChildPath 'structured'
$script:LogLevel = 'Info'
$script:LogLevels = @{ Trace = 0; Debug = 1; Info = 2; Warn = 3; Error = 4; Fatal = 5 }
$script:CorrelationId = [guid]::NewGuid().ToString('N').Substring(0, 8)
$script:PerfCounters = @{}

if (-not (Test-Path -Path $script:StructuredLogDir)) {
    $null = New-Item -Path $script:StructuredLogDir -ItemType Directory -Force
}

#endregion

#region ── Structured Logging ─────────────────────────────────────────────────

<#
.SYNOPSIS
    Writes a structured log entry in JSON format.
.PARAMETER Level
    Log level.
.PARAMETER Message
    Log message.
.PARAMETER Properties
    Additional structured properties.
.PARAMETER Exception
    Exception object to include.
.EXAMPLE
    Write-StructuredLog -Level Info -Message 'Profile loaded' -Properties @{ ModuleCount = 21; LoadTimeMs = 42 }
.EXAMPLE
    slog Info 'Build complete'
#>
function Write-StructuredLog {
    [CmdletBinding()]
    [OutputType([void])]
    param(
        [Parameter(Mandatory, Position = 0)]
        [ValidateSet('Trace', 'Debug', 'Info', 'Warn', 'Error', 'Fatal')]
        [string]$Level,

        [Parameter(Mandatory, Position = 1)]
        [string]$Message,

        [Parameter()]
        [hashtable]$Properties,

        [Parameter()]
        [System.Exception]$Exception
    )

    # Check log level
    if ($script:LogLevels[$Level] -lt $script:LogLevels[$script:LogLevel]) { return }

    $entry = [ordered]@{
        timestamp     = [datetime]::UtcNow.ToString('o')
        level         = $Level
        message       = $Message
        correlationId = $script:CorrelationId
        host          = $env:COMPUTERNAME
        user          = $env:USERNAME
        pid           = $PID
    }

    if ($null -ne $Properties) {
        $entry['properties'] = $Properties
    }

    if ($null -ne $Exception) {
        $entry['exception'] = [ordered]@{
            type       = $Exception.GetType().FullName
            message    = $Exception.Message
            stackTrace = $Exception.StackTrace
        }
        if ($null -ne $Exception.InnerException) {
            $entry['exception']['innerException'] = $Exception.InnerException.Message
        }
    }

    $json = $entry | ConvertTo-Json -Depth 5 -Compress

    # Write to file (one file per day)
    $logFile = Join-Path -Path $script:StructuredLogDir -ChildPath "log-$(Get-Date -Format 'yyyy-MM-dd').jsonl"
    Add-Content -Path $logFile -Value $json -Encoding UTF8

    # Console output
    $levelColor = switch ($Level) {
        'Trace' { $script:Theme.Muted }
        'Debug' { $Global:Theme.Muted }
        'Info'  { $Global:Theme.Info }
        'Warn'  { $Global:Theme.Warning }
        'Error' { $Global:Theme.Error }
        'Fatal' { $Global:Theme.Error }
    }

    if ($script:LogLevels[$Level] -ge $script:LogLevels['Warn']) {
        Write-Host "  [$Level] $Message" -ForegroundColor $levelColor
    }
}

<#
.SYNOPSIS
    Sets the minimum log level.
.PARAMETER Level
    Minimum log level to record.
.EXAMPLE
    Set-LogLevel -Level Debug
#>
function Set-LogLevel {
    [CmdletBinding()]
    [OutputType([void])]
    param(
        [Parameter(Mandatory, Position = 0)]
        [ValidateSet('Trace', 'Debug', 'Info', 'Warn', 'Error', 'Fatal')]
        [string]$Level
    )

    $script:LogLevel = $Level
    Write-Host "  Log level set: $Level" -ForegroundColor $script:Theme.Info
}

<#
.SYNOPSIS
    Generates a new correlation ID for request tracking.
.EXAMPLE
    $id = New-CorrelationId
#>
function New-CorrelationId {
    [CmdletBinding()]
    [OutputType([string])]
    param()

    $script:CorrelationId = [guid]::NewGuid().ToString('N').Substring(0, 8)
    Write-Host "  Correlation ID: $($script:CorrelationId)" -ForegroundColor $script:Theme.Accent
    return $script:CorrelationId
}

#endregion

#region ── Log Querying ───────────────────────────────────────────────────────

<#
.SYNOPSIS
    Queries structured log files with filtering.
.PARAMETER Level
    Filter by log level.
.PARAMETER Pattern
    Filter messages by pattern.
.PARAMETER Last
    Show last N entries.
.PARAMETER Since
    Show entries since this datetime.
.PARAMETER CorrelationId
    Filter by correlation ID.
.EXAMPLE
    Search-StructuredLog -Level Error -Last 20
.EXAMPLE
    logquery -Pattern 'build' -Since (Get-Date).AddHours(-2)
#>
function Search-StructuredLog {
    [CmdletBinding()]
    [OutputType([void])]
    param(
        [Parameter(Position = 0)]
        [ValidateSet('Trace', 'Debug', 'Info', 'Warn', 'Error', 'Fatal')]
        [string]$Level,

        [Parameter()]
        [string]$Pattern,

        [Parameter()]
        [ValidateRange(1, 1000)]
        [int]$Last = 50,

        [Parameter()]
        [datetime]$Since,

        [Parameter()]
        [string]$CorrelationId
    )

    Write-Host "`n  Structured Log Query" -ForegroundColor $script:Theme.Primary
    Write-Host "  $('─' * 55)" -ForegroundColor $script:Theme.Muted

    $logFiles = Get-ChildItem -Path $script:StructuredLogDir -Filter '*.jsonl' -ErrorAction SilentlyContinue |
        Sort-Object -Property Name -Descending

    if ($logFiles.Count -eq 0) {
        Write-Host '  No log files found.' -ForegroundColor $Global:Theme.Muted
        return
    }

    $allEntries = [System.Collections.Generic.List[PSCustomObject]]::new()

    foreach ($file in $logFiles) {
        $lines = Get-Content -Path $file.FullName -ErrorAction SilentlyContinue
        foreach ($line in $lines) {
            try {
                $entry = $line | ConvertFrom-Json
                $allEntries.Add($entry)
            }
            catch { }
        }
        if ($allEntries.Count -ge $Last * 2) { break }
    }

    # Apply filters
    $filtered = $allEntries

    if (-not [string]::IsNullOrEmpty($Level)) {
        $minLevel = $script:LogLevels[$Level]
        $filtered = $filtered | Where-Object -FilterScript { $script:LogLevels[$_.level] -ge $minLevel }
    }

    if (-not [string]::IsNullOrEmpty($Pattern)) {
        $filtered = $filtered | Where-Object -FilterScript { $_.message -match $Pattern }
    }

    if ($null -ne $Since) {
        $filtered = $filtered | Where-Object -FilterScript { [datetime]::Parse($_.timestamp) -ge $Since }
    }

    if (-not [string]::IsNullOrEmpty($CorrelationId)) {
        $filtered = $filtered | Where-Object -FilterScript { $_.correlationId -eq $CorrelationId }
    }

    $results = @($filtered | Select-Object -Last $Last)

    if ($results.Count -eq 0) {
        Write-Host '  No matching entries.' -ForegroundColor $Global:Theme.Muted
        return
    }

    foreach ($entry in $results) {
        $levelColor = switch ($entry.level) {
            'Trace' { $Global:Theme.Muted }
            'Debug' { $Global:Theme.Muted }
            'Info'  { $Global:Theme.Info }
            'Warn'  { $Global:Theme.Warning }
            'Error' { $Global:Theme.Error }
            'Fatal' { $Global:Theme.Error }
            default { $Global:Theme.Text }
        }

        $time = [datetime]::Parse($entry.timestamp).ToLocalTime().ToString('HH:mm:ss')
        $lvl = $entry.level.PadRight(5)

        Write-Host "  $time " -ForegroundColor $script:Theme.Muted -NoNewline
        Write-Host "$lvl " -ForegroundColor $levelColor -NoNewline
        Write-Host "[$($entry.correlationId)] " -ForegroundColor $script:Theme.Accent -NoNewline
        Write-Host "$($entry.message)" -ForegroundColor $script:Theme.Text

        if ($null -ne $entry.exception) {
            Write-Host "         $($entry.exception.type): $($entry.exception.message)" -ForegroundColor $script:Theme.Error
        }
    }

    Write-Host "`n  $($results.Count) entries shown." -ForegroundColor $script:Theme.Muted
    Write-Host ''
}

#endregion

#region ── Performance Counters ───────────────────────────────────────────────

<#
.SYNOPSIS
    Starts a named performance timer.
.PARAMETER Name
    Timer name.
.EXAMPLE
    Start-PerfCounter -Name 'build'
    # ... do work ...
    Stop-PerfCounter -Name 'build'
#>
function Start-PerfCounter {
    [CmdletBinding()]
    [OutputType([void])]
    param(
        [Parameter(Mandatory, Position = 0)]
        [string]$Name
    )

    $script:PerfCounters[$Name] = @{
        Stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
        StartedAt = [datetime]::UtcNow.ToString('o')
    }
}

<#
.SYNOPSIS
    Stops a performance timer and logs the duration.
.PARAMETER Name
    Timer name.
.PARAMETER Log
    Also write to structured log.
.EXAMPLE
    $elapsed = Stop-PerfCounter -Name 'build' -Log
#>
function Stop-PerfCounter {
    [CmdletBinding()]
    [OutputType([double])]
    param(
        [Parameter(Mandatory, Position = 0)]
        [string]$Name,

        [Parameter()]
        [switch]$Log
    )

    if (-not $script:PerfCounters.ContainsKey($Name)) {
        Write-Warning -Message "Counter '$Name' not found."
        return -1
    }

    $counter = $script:PerfCounters[$Name]
    $counter['Stopwatch'].Stop()
    $elapsed = $counter['Stopwatch'].Elapsed.TotalMilliseconds

    Write-Host "  Timer '$Name': $([math]::Round($elapsed, 1))ms" -ForegroundColor $script:Theme.Info

    if ($Log) {
        Write-StructuredLog -Level Info -Message "Performance: $Name" -Properties @{
            counterName = $Name
            elapsedMs   = [math]::Round($elapsed, 2)
        }
    }

    $script:PerfCounters.Remove($Name)
    return $elapsed
}

<#
.SYNOPSIS
    Shows active performance counters.
.EXAMPLE
    Show-PerfCounters
#>
function Show-PerfCounters {
    [CmdletBinding()]
    [OutputType([void])]
    param()

    Write-Host "`n  Performance Counters" -ForegroundColor $script:Theme.Primary
    Write-Host "  $('─' * 40)" -ForegroundColor $script:Theme.Muted

    if ($script:PerfCounters.Count -eq 0) {
        Write-Host '  (none active)' -ForegroundColor $Global:Theme.Muted
        return
    }

    foreach ($name in ($script:PerfCounters.Keys | Sort-Object)) {
        $counter = $script:PerfCounters[$name]
        $elapsed = $counter['Stopwatch'].Elapsed.TotalMilliseconds
        Write-Host "  $($name.PadRight(25))" -ForegroundColor $script:Theme.Accent -NoNewline
        Write-Host "$([math]::Round($elapsed, 1))ms (running)" -ForegroundColor $script:Theme.Warning
    }
    Write-Host ''
}

#endregion

#region ── Log Rotation ───────────────────────────────────────────────────────

<#
.SYNOPSIS
    Rotates structured log files based on age.
.PARAMETER RetentionDays
    Days to keep log files.
.EXAMPLE
    Invoke-LogRotation -RetentionDays 30
#>
function Invoke-LogRotation {
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([void])]
    param(
        [Parameter()]
        [ValidateRange(1, 365)]
        [int]$RetentionDays = 30
    )

    $cutoff = (Get-Date).AddDays(-$RetentionDays)
    $oldFiles = Get-ChildItem -Path $script:StructuredLogDir -Filter '*.jsonl' -ErrorAction SilentlyContinue |
        Where-Object -FilterScript { $_.LastWriteTime -lt $cutoff }

    if ($oldFiles.Count -eq 0) {
        Write-Host '  No log files to rotate.' -ForegroundColor $Global:Theme.Muted
        return
    }

    if ($PSCmdlet.ShouldProcess("$($oldFiles.Count) log files", 'Remove')) {
        $oldFiles | Remove-Item -Force
        Write-Host "  Rotated $($oldFiles.Count) log file(s) older than $RetentionDays days." -ForegroundColor $script:Theme.Success
    }
}

<#
.SYNOPSIS
    Shows log file statistics.
.EXAMPLE
    Show-LogStats
#>
function Show-LogStats {
    [CmdletBinding()]
    [OutputType([void])]
    param()

    Write-Host "`n  Log Statistics" -ForegroundColor $script:Theme.Primary
    Write-Host "  $('─' * 40)" -ForegroundColor $script:Theme.Muted

    $logFiles = Get-ChildItem -Path $script:StructuredLogDir -Filter '*.jsonl' -ErrorAction SilentlyContinue
    $totalSizeMB = [math]::Round(($logFiles | Measure-Object -Property Length -Sum).Sum / 1MB, 2)
    $totalEntries = 0

    foreach ($file in $logFiles) {
        $lineCount = @(Get-Content -Path $file.FullName -ErrorAction SilentlyContinue).Count
        $totalEntries += $lineCount
    }

    Write-Host "  Files:   $($logFiles.Count)" -ForegroundColor $script:Theme.Text
    Write-Host "  Size:    $totalSizeMB MB" -ForegroundColor $script:Theme.Text
    Write-Host "  Entries: $('{0:N0}' -f $totalEntries)" -ForegroundColor $script:Theme.Text
    Write-Host "  Level:   $($script:LogLevel)" -ForegroundColor $script:Theme.Accent
    Write-Host "  CorrID:  $($script:CorrelationId)" -ForegroundColor $script:Theme.Accent

    if ($logFiles.Count -gt 0) {
        $oldest = ($logFiles | Sort-Object -Property Name | Select-Object -First 1).Name -replace '^log-|\.jsonl$', ''
        $newest = ($logFiles | Sort-Object -Property Name -Descending | Select-Object -First 1).Name -replace '^log-|\.jsonl$', ''
        Write-Host "  Range:   $oldest to $newest" -ForegroundColor $Global:Theme.Muted
    }
    Write-Host ''
}

#endregion

#region ── Aliases ─────────────────────────────────────────────────────────────

Set-Alias -Name 'slog'       -Value 'Write-StructuredLog'    -Scope Global -Force
Set-Alias -Name 'logquery'   -Value 'Search-StructuredLog'   -Scope Global -Force
Set-Alias -Name 'loglevel'   -Value 'Set-LogLevel'           -Scope Global -Force
Set-Alias -Name 'logstats'   -Value 'Show-LogStats'          -Scope Global -Force
Set-Alias -Name 'logrotate'  -Value 'Invoke-LogRotation'     -Scope Global -Force
Set-Alias -Name 'perfstart'  -Value 'Start-PerfCounter'      -Scope Global -Force
Set-Alias -Name 'perfstop'   -Value 'Stop-PerfCounter'       -Scope Global -Force
Set-Alias -Name 'perfs'      -Value 'Show-PerfCounters'      -Scope Global -Force

#endregion

