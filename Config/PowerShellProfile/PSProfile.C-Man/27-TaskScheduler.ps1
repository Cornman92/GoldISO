<#
.SYNOPSIS
    Task Scheduler module for C-Man's PowerShell Profile.
.DESCRIPTION
    Create/list/modify scheduled tasks from PS, cron-style syntax parser,
    task health monitor, missed-run detector, one-liner task creation.
.NOTES
    Module: 27-TaskScheduler.ps1
    Requires: PowerShell 5.1+, Windows
#>

#region ── Task Dashboard ─────────────────────────────────────────────────────

<#
.SYNOPSIS
    Shows scheduled tasks with status and next run time.
.PARAMETER Path
    Task folder path. Default is root.
.PARAMETER Filter
    Filter task names.
.PARAMETER ShowDisabled
    Include disabled tasks.
.EXAMPLE
    Show-ScheduledTasks -Path '\Microsoft\Windows\WindowsUpdate'
.EXAMPLE
    tasks -Filter '*Better11*'
#>
function Show-ScheduledTasks {
    [CmdletBinding()]
    [OutputType([void])]
    param(
        [Parameter(Position = 0)]
        [string]$Path = '\',

        [Parameter()]
        [string]$Filter,

        [Parameter()]
        [switch]$ShowDisabled
    )

    Write-Host "`n  Scheduled Tasks" -ForegroundColor $script:Theme.Primary
    Write-Host "  $('â•' * 65)" -ForegroundColor $script:Theme.Muted

    $tasks = Get-ScheduledTask -TaskPath "$Path*" -ErrorAction SilentlyContinue

    if (-not [string]::IsNullOrEmpty($Filter)) {
        $tasks = $tasks | Where-Object -FilterScript { $_.TaskName -like "*$Filter*" }
    }

    if (-not $ShowDisabled) {
        $tasks = $tasks | Where-Object -FilterScript { $_.State -ne 'Disabled' }
    }

    if ($null -eq $tasks -or @($tasks).Count -eq 0) {
        Write-Host '  No tasks found.' -ForegroundColor $script:Theme.Muted
        return
    }

    foreach ($task in ($tasks | Sort-Object -Property TaskName)) {
        $info = $task | Get-ScheduledTaskInfo -ErrorAction SilentlyContinue
        $lastRun = if ($null -ne $info -and $info.LastRunTime -gt [datetime]::MinValue) {
            $info.LastRunTime.ToString('yyyy-MM-dd HH:mm')
        } else { 'Never' }
        $nextRun = if ($null -ne $info -and $info.NextRunTime -gt [datetime]::MinValue) {
            $info.NextRunTime.ToString('yyyy-MM-dd HH:mm')
        } else { 'N/A' }

        $statusIcon = switch ($task.State) {
            'Ready'    { '✓' }
            'Running'  { 'â–¶' }
            'Disabled' { 'â– ' }
            default    { '?' }
        }
        $statusColor = switch ($task.State) {
            'Ready'    { $Global:Theme.Success }
            'Running'  { $Global:Theme.Info }
            'Disabled' { $Global:Theme.Muted }
            default    { $Global:Theme.Warning }
        }
        $name = $task.TaskName
        if ($name.Length -gt 30) { $name = $name.Substring(0, 27) + '...' }

        Write-Host "  $statusIcon " -ForegroundColor $statusColor -NoNewline
        Write-Host "$($name.PadRight(32))" -ForegroundColor $script:Theme.Text -NoNewline
        Write-Host "$($lastRun.PadRight(18))" -ForegroundColor $script:Theme.Muted -NoNewline
        Write-Host "$nextRun" -ForegroundColor $script:Theme.Accent
    }
    Write-Host ''
}

#endregion

#region ── Quick Task Creation ────────────────────────────────────────────────

<#
.SYNOPSIS
    Creates a scheduled task with a one-liner.
.PARAMETER Name
    Task name.
.PARAMETER Command
    Command or script to execute.
.PARAMETER Schedule
    Simple schedule: 'daily', 'hourly', 'weekly', 'boot', 'logon', or cron-like 'HH:MM'.
.PARAMETER Description
    Task description.
.PARAMETER AsAdmin
    Run with highest privileges.
.EXAMPLE
    New-QuickTask -Name 'ProfileBackup' -Command 'powershell -File $env:USERPROFILE\Scripts\backup.ps1' -Schedule 'daily'
.EXAMPLE
    qtask 'CleanTemp' 'powershell -Command "Remove-Item $env:TEMP\* -Force"' 'weekly'
#>
function New-QuickTask {
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([void])]
    param(
        [Parameter(Mandatory, Position = 0)]
        [ValidateNotNullOrEmpty()]
        [string]$Name,

        [Parameter(Mandatory, Position = 1)]
        [string]$Command,

        [Parameter(Position = 2)]
        [string]$Schedule = 'daily',

        [Parameter()]
        [string]$Description = "Created by profile on $(Get-Date -Format 'yyyy-MM-dd')",

        [Parameter()]
        [switch]$AsAdmin
    )

    if (-not $PSCmdlet.ShouldProcess($Name, "Create scheduled task ($Schedule)")) { return }

    # Parse command into executable and arguments
    $parts = $Command -Split '\s+', 2
    $executable = $parts[0]
    $arguments = if ($parts.Count -gt 1) { $parts[1] } else { '' }

    $action = New-ScheduledTaskAction -Execute $executable -Argument $arguments

    $trigger = switch -Regex ($Schedule) {
        '^daily$'   { New-ScheduledTaskTrigger -Daily -At '09:00' }
        '^hourly$'  { New-ScheduledTaskTrigger -Once -At (Get-Date) -RepetitionInterval (New-TimeSpan -Hours 1) }
        '^weekly$'  { New-ScheduledTaskTrigger -Weekly -DaysOfWeek Monday -At '09:00' }
        '^boot$'    { New-ScheduledTaskTrigger -AtStartup }
        '^logon$'   { New-ScheduledTaskTrigger -AtLogOn }
        '^\d{1,2}:\d{2}$' { New-ScheduledTaskTrigger -Daily -At $Schedule }
        default {
            Write-Warning -Message "Unknown schedule: $Schedule. Use daily, hourly, weekly, boot, logon, or HH:MM."
            return
        }
    }

    $settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable

    $principal = if ($AsAdmin) {
        New-ScheduledTaskPrincipal -UserId $env:USERNAME -RunLevel Highest -LogonType Interactive
    }
    else {
        New-ScheduledTaskPrincipal -UserId $env:USERNAME -LogonType Interactive
    }

    try {
        Register-ScheduledTask -TaskName $Name -Action $action -Trigger $trigger -Settings $settings -Principal $principal -Description $Description -Force | Out-Null
        Write-Host "  Created task: $Name ($Schedule)" -ForegroundColor $script:Theme.Success
    }
    catch {
        Write-Warning -Message "Failed: $($_.Exception.Message)"
    }
}

<#
.SYNOPSIS
    Removes a scheduled task.
.PARAMETER Name
    Task name to remove.
.EXAMPLE
    Remove-QuickTask -Name 'ProfileBackup'
#>
function Remove-QuickTask {
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([void])]
    param(
        [Parameter(Mandatory, Position = 0)]
        [string]$Name
    )

    if (-not $PSCmdlet.ShouldProcess($Name, 'Remove scheduled task')) { return }

    try {
        Unregister-ScheduledTask -TaskName $Name -Confirm:$false -ErrorAction Stop
        Write-Host "  Removed task: $Name" -ForegroundColor $script:Theme.Warning
    }
    catch {
        Write-Warning -Message "Failed: $($_.Exception.Message)"
    }
}

#endregion

#region ── Task Health Monitor ────────────────────────────────────────────────

<#
.SYNOPSIS
    Detects failed or missed scheduled tasks.
.PARAMETER HoursBack
    Check tasks that should have run in the last N hours.
.EXAMPLE
    Get-TaskHealth -HoursBack 24
.EXAMPLE
    taskhealth
#>
function Get-TaskHealth {
    [CmdletBinding()]
    [OutputType([void])]
    param(
        [Parameter()]
        [ValidateRange(1, 720)]
        [int]$HoursBack = 24
    )

    Write-Host "`n  Task Health (last ${HoursBack}h)" -ForegroundColor $script:Theme.Primary
    Write-Host "  $('─' * 55)" -ForegroundColor $script:Theme.Muted

    $cutoff = (Get-Date).AddHours(-$HoursBack)
    $tasks = Get-ScheduledTask -ErrorAction SilentlyContinue |
        Where-Object -FilterScript { $_.State -ne 'Disabled' }

    $failed = 0; $missed = 0; $ok = 0

    foreach ($task in $tasks) {
        $info = $task | Get-ScheduledTaskInfo -ErrorAction SilentlyContinue
        if ($null -eq $info) { continue }

        $lastResult = $info.LastTaskResult
        $lastRun = $info.LastRunTime
        $nextRun = $info.NextRunTime

        $isFailed = $lastResult -ne 0 -and $lastResult -ne 267011 -and $lastRun -gt $cutoff
        $isMissed = $nextRun -lt (Get-Date) -and $nextRun -gt $cutoff -and $task.State -eq 'Ready'

        if ($isFailed) {
            Write-Host "  ✗ FAILED " -ForegroundColor $script:Theme.Error -NoNewline
            Write-Host "$($task.TaskName.PadRight(35))" -ForegroundColor $script:Theme.Text -NoNewline
            Write-Host "Exit: $lastResult" -ForegroundColor $script:Theme.Error
            $failed++
        }
        elseif ($isMissed) {
            Write-Host "  ⚠ MISSED " -ForegroundColor $script:Theme.Warning -NoNewline
            Write-Host "$($task.TaskName.PadRight(35))" -ForegroundColor $script:Theme.Text -NoNewline
            Write-Host "Due: $($nextRun.ToString('yyyy-MM-dd HH:mm'))" -ForegroundColor $script:Theme.Warning
            $missed++
        }
        else {
            $ok++
        }
    }

    Write-Host "`n  OK: $ok  Failed: $failed  Missed: $missed" -ForegroundColor $Global:Theme.Muted
    Write-Host ''
}

#endregion

#region ── Aliases ─────────────────────────────────────────────────────────────

Set-Alias -Name 'tasks'       -Value 'Show-ScheduledTasks'    -Scope Global -Force
Set-Alias -Name 'qtask'       -Value 'New-QuickTask'          -Scope Global -Force
Set-Alias -Name 'rmtask'      -Value 'Remove-QuickTask'       -Scope Global -Force
Set-Alias -Name 'taskhealth'  -Value 'Get-TaskHealth'         -Scope Global -Force

#endregion

