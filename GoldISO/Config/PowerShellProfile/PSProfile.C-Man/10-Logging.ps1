[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingWriteHost', '', Justification = 'Log management display requires Write-Host')]
param()

#region ── Session Logging ────────────────────────────────────────────────────

function Start-ProfileSessionLog {
    <#
    .SYNOPSIS
        Starts transcript logging for the current session.
    .DESCRIPTION
        Creates timestamped transcript files in the Logs/sessions directory.
        Old transcripts are automatically cleaned up based on retention settings.
    #>
    [CmdletBinding()]
    param()

    $sessionLogDir = Join-Path -Path $script:ProfileRoot -ChildPath 'Logs' |
        Join-Path -ChildPath 'sessions'

    if (-not (Test-Path -Path $sessionLogDir)) {
        $null = New-Item -Path $sessionLogDir -ItemType Directory -Force
    }

    $timestamp = Get-Date -Format 'yyyy-MM-dd_HH-mm-ss'
    $sessionId = [System.Guid]::NewGuid().ToString().Substring(0, 8)
    $transcriptPath = Join-Path -Path $sessionLogDir -ChildPath "session_${timestamp}_${sessionId}.log"

    try {
        Start-Transcript -Path $transcriptPath -Append -IncludeInvocationHeader -ErrorAction Stop | Out-Null
        $script:CurrentTranscriptPath = $transcriptPath
    }
    catch {
        # Transcript may already be running
        if ($_.Exception.Message -notmatch 'already been started') {
            Write-Warning -Message "Could not start transcript: $($_.Exception.Message)"
        }
    }

    # Cleanup old transcripts
    Invoke-LogRetention -LogDirectory $sessionLogDir -RetentionDays $script:ProfileConfig.TranscriptRetentionDays
}

function Stop-ProfileSessionLog {
    <#
    .SYNOPSIS
        Stops the current session transcript.
    #>
    [CmdletBinding()]
    param()

    try {
        Stop-Transcript -ErrorAction Stop | Out-Null
        Write-Host -Object '  Session transcript stopped.' -ForegroundColor $Global:Theme.Success
    }
    catch {
        Write-Host -Object '  No active transcript to stop.' -ForegroundColor $Global:Theme.Muted
    }
}

function Get-SessionLogs {
    <#
    .SYNOPSIS
        List recent session transcript files.
    .PARAMETER Last
        Number of recent logs to show.
    #>
    [CmdletBinding()]
    [Alias('logs')]
    param(
        [Parameter(Position = 0)]
        [int]$Last = 10
    )

    $tc = $Global:Theme
    $sessionLogDir = Join-Path -Path $script:ProfileRoot -ChildPath 'Logs' |
        Join-Path -ChildPath 'sessions'

    if (-not (Test-Path -Path $sessionLogDir)) {
        Write-Host -Object '  No session logs found.' -ForegroundColor $tc.Muted
        return
    }

    $logs = Get-ChildItem -Path $sessionLogDir -Filter '*.log' |
        Sort-Object -Property LastWriteTime -Descending |
        Select-Object -First $Last

    Write-Host -Object "`n  Recent Session Logs:" -ForegroundColor $tc.Primary
    foreach ($log in $logs) {
        $sizeKb = [math]::Round($log.Length / 1KB, 1)
        $age = (Get-Date) - $log.LastWriteTime
        $ageStr = if ($age.TotalHours -lt 1) { "$([math]::Round($age.TotalMinutes))m ago" }
                  elseif ($age.TotalDays -lt 1) { "$([math]::Round($age.TotalHours, 1))h ago" }
                  else { "$([math]::Round($age.TotalDays))d ago" }

        $isCurrent = $script:CurrentTranscriptPath -eq $log.FullName
        $marker = if ($isCurrent) { ' [ACTIVE]' } else { '' }
        $markerColor = if ($isCurrent) { $tc.Success } else { $tc.Muted }

        Write-Host -Object "    $($log.Name)" -ForegroundColor $tc.Text -NoNewline
        Write-Host -Object " ($sizeKb KB, $ageStr)" -ForegroundColor $tc.Muted -NoNewline
        Write-Host -Object $marker -ForegroundColor $markerColor
    }
    Write-Host ''
}

function Open-SessionLog {
    <#
    .SYNOPSIS
        Open a session log file in the default editor.
    .PARAMETER Latest
        Open the most recent log.
    .PARAMETER Path
        Open a specific log file.
    #>
    [CmdletBinding(DefaultParameterSetName = 'Latest')]
    param(
        [Parameter(ParameterSetName = 'Latest')]
        [switch]$Latest,

        [Parameter(ParameterSetName = 'Path', Position = 0)]
        [string]$Path
    )

    if ($PSCmdlet.ParameterSetName -eq 'Path') {
        if (Test-Path -Path $Path) {
            & code $Path
        }
        else {
            Write-Warning -Message "Log file not found: $Path"
        }
        return
    }

    $sessionLogDir = Join-Path -Path $script:ProfileRoot -ChildPath 'Logs' |
        Join-Path -ChildPath 'sessions'

    $latestLog = Get-ChildItem -Path $sessionLogDir -Filter '*.log' |
        Sort-Object -Property LastWriteTime -Descending |
        Select-Object -First 1

    if ($latestLog) {
        & code $latestLog.FullName
    }
    else {
        Write-Warning -Message 'No session logs found.'
    }
}

#endregion

#region ── Error Logging ──────────────────────────────────────────────────────

function Write-ProfileError {
    <#
    .SYNOPSIS
        Log an error with full stack trace to the error log file.
    .PARAMETER ErrorRecord
        The ErrorRecord to log.
    .PARAMETER Context
        Additional context about where the error occurred.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, Position = 0)]
        [System.Management.Automation.ErrorRecord]$ErrorRecord,

        [string]$Context = 'General'
    )

    if (-not $Global:ProfileConfig.EnableErrorLogging) { return }

    $errorLogDir = Join-Path -Path $script:ProfileRoot -ChildPath 'Logs' |
        Join-Path -ChildPath 'errors'

    if (-not (Test-Path -Path $errorLogDir)) {
        $null = New-Item -Path $errorLogDir -ItemType Directory -Force
    }

    $errorLogFile = Join-Path -Path $errorLogDir -ChildPath "errors_$(Get-Date -Format 'yyyy-MM-dd').log"

    $errorEntry = @"
[$( Get-Date -Format 'yyyy-MM-dd HH:mm:ss.fff' )] [$Context]
Exception: $($ErrorRecord.Exception.GetType().FullName)
Message:   $($ErrorRecord.Exception.Message)
Command:   $($ErrorRecord.InvocationInfo.MyCommand)
Line:      $($ErrorRecord.InvocationInfo.ScriptLineNumber)
Position:  $($ErrorRecord.InvocationInfo.PositionMessage)
Stack:
$($ErrorRecord.ScriptStackTrace)
---

"@

    Add-Content -Path $errorLogFile -Value $errorEntry -Encoding UTF8

    Invoke-LogRetention -LogDirectory $errorLogDir -RetentionDays $script:ProfileConfig.ErrorLogRetentionDays
}

function Get-ProfileErrors {
    <#
    .SYNOPSIS
        Display recent profile errors from the error log.
    .PARAMETER Last
        Number of recent error log files to check.
    .PARAMETER Today
        Show only today's errors.
    #>
    [CmdletBinding()]
    [Alias('errors')]
    param(
        [int]$Last = 5,

        [switch]$Today
    )

    $tc = $Global:Theme
    $errorLogDir = Join-Path -Path $script:ProfileRoot -ChildPath 'Logs' |
        Join-Path -ChildPath 'errors'

    if (-not (Test-Path -Path $errorLogDir)) {
        Write-Host -Object '  No error logs found.' -ForegroundColor $tc.Success
        return
    }

    $filter = if ($Today) { "errors_$(Get-Date -Format 'yyyy-MM-dd').log" } else { '*.log' }
    $logFiles = Get-ChildItem -Path $errorLogDir -Filter $filter |
        Sort-Object -Property LastWriteTime -Descending |
        Select-Object -First $Last

    if ($logFiles.Count -eq 0) {
        Write-Host -Object '  No errors logged.' -ForegroundColor $tc.Success
        return
    }

    foreach ($logFile in $logFiles) {
        Write-Host -Object "`n  $($logFile.Name):" -ForegroundColor $tc.Warning
        $content = Get-Content -Path $logFile.FullName -Raw
        $entries = $content -Split '---' | Where-Object -FilterScript { $_.Trim().Length -gt 0 }

        foreach ($entry in ($entries | Select-Object -Last 5)) {
            $lines = $entry.Trim() -split "`n"
            foreach ($line in $lines) {
                if ($line -match '^\[') {
                    Write-Host -Object "    $line" -ForegroundColor $tc.Error
                }
                elseif ($line -match '^(Exception|Message):') {
                    Write-Host -Object "    $line" -ForegroundColor $tc.Warning
                }
                else {
                    Write-Host -Object "    $line" -ForegroundColor $tc.Muted
                }
            }
            Write-Host -Object '    ---' -ForegroundColor $tc.Separator
        }
    }
    Write-Host ''
}

function Clear-ProfileLogs {
    <#
    .SYNOPSIS
        Remove all session and error logs.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param()

    $logDir = Join-Path -Path $script:ProfileRoot -ChildPath 'Logs'

    if ($PSCmdlet.ShouldProcess($logDir, 'Remove all log files')) {
        Get-ChildItem -Path $logDir -Filter '*.log' -Recurse | Remove-Item -Force
        Write-Host -Object '  All logs cleared.' -ForegroundColor $Global:Theme.Success
    }
}

#endregion

#region ── Log Retention ──────────────────────────────────────────────────────

function Invoke-LogRetention {
    <#
    .SYNOPSIS
        Remove log files older than retention period.
    .PARAMETER LogDirectory
        Directory containing log files.
    .PARAMETER RetentionDays
        Days to retain logs.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$LogDirectory,

        [int]$RetentionDays = 30
    )

    if (-not (Test-Path -Path $LogDirectory)) { return }
    if ($RetentionDays -le 0) { return }

    $cutoffDate = (Get-Date).AddDays(-$RetentionDays)
    Get-ChildItem -Path $LogDirectory -Filter '*.log' |
        Where-Object -FilterScript { $_.LastWriteTime -lt $cutoffDate } |
        Remove-Item -Force -ErrorAction SilentlyContinue
}

#endregion

