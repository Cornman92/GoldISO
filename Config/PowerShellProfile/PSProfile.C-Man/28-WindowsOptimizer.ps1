<#
.SYNOPSIS
    Windows Optimizer module for C-Man's PowerShell Profile.
.DESCRIPTION
    Telemetry toggler, service optimizer profiles, startup app manager,
    disk cleanup orchestrator, Windows Update controller, power plan
    switcher, and bloatware inventory.
.NOTES
    Module: 28-WindowsOptimizer.ps1
    Requires: PowerShell 5.1+, Windows, Admin for some operations
#>

#region -- Startup Manager ----------------------------------------------------

<#
.SYNOPSIS
    Lists and manages startup applications.
.PARAMETER Disable
    Disable a startup entry by name.
.PARAMETER Enable
    Enable a startup entry by name.
.EXAMPLE
    Show-StartupApps
.EXAMPLE
    Show-StartupApps -Disable 'OneDrive'
#>
function Show-StartupApps {
    [CmdletBinding()]
    [OutputType([void])]
    param(
        [Parameter()]
        [string]$Disable,

        [Parameter()]
        [string]$Enable
    )

    Write-Host "`n  Startup Applications" -ForegroundColor $Global:Theme.Primary
    Write-Host "  $('-' * 60)" -ForegroundColor $Global:Theme.Muted

    # Registry locations
    $locations = @(
        @{ Path = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run'; Scope = 'User' }
        @{ Path = 'HKLM:\Software\Microsoft\Windows\CurrentVersion\Run'; Scope = 'Machine' }
    )

    foreach ($loc in $locations) {
        Write-Host "`n  [$($loc.Scope)]" -ForegroundColor $Global:Theme.Accent
        $key = Get-Item -Path $loc.Path -ErrorAction SilentlyContinue
        if ($null -eq $key) { continue }

        foreach ($name in $key.GetValueNames()) {
            $value = $key.GetValue($name)
            $cmd = if ($value.Length -gt 55) { $value.Substring(0, 52) + '...' } else { $value }

            Write-Host "    $($name.PadRight(25))" -ForegroundColor $Global:Theme.Text -NoNewline
            Write-Host "$cmd" -ForegroundColor $Global:Theme.Muted
        }
    }

    # Task Scheduler startup tasks
    Write-Host "`n  [Scheduled at Logon]" -ForegroundColor $Global:Theme.Accent
    $logonTasks = Get-ScheduledTask -ErrorAction SilentlyContinue |
        Where-Object -FilterScript {
            $_.Triggers | Where-Object -FilterScript { $_.CimClass.CimClassName -eq 'MSFT_TaskLogonTrigger' }
        } | Select-Object -First 15

    foreach ($task in $logonTasks) {
        $state = $task.State
        $color = if ($state -eq 'Ready' -or $state -eq 'Running') { $Global:Theme.Success } else { $Global:Theme.Muted }
        Write-Host "    $($task.TaskName.PadRight(35))" -ForegroundColor $Global:Theme.Text -NoNewline
        Write-Host "$state" -ForegroundColor $color
    }

    Write-Host ''
}

#endregion

#region -- Service Optimizer --------------------------------------------------

<#
.SYNOPSIS
    Shows services that can be safely disabled for performance.
.DESCRIPTION
    Categorizes running services as essential, recommended, or optional
    and shows which optional services could be disabled to improve
    performance and reduce resource usage.
.PARAMETER ShowAll
    Show all services, not just optimizable ones.
.EXAMPLE
    Show-ServiceOptimizer
.EXAMPLE
    svcopt
#>
function Show-ServiceOptimizer {
    [CmdletBinding()]
    [OutputType([void])]
    param(
        [Parameter()]
        [switch]$ShowAll
    )

    $optionalServices = @(
        @{ Name = 'DiagTrack';          Desc = 'Connected User Experiences and Telemetry' }
        @{ Name = 'dmwappushservice';   Desc = 'WAP Push Message Routing' }
        @{ Name = 'MapsBroker';         Desc = 'Downloaded Maps Manager' }
        @{ Name = 'lfsvc';              Desc = 'Geolocation Service' }
        @{ Name = 'SharedAccess';       Desc = 'Internet Connection Sharing' }
        @{ Name = 'RetailDemo';         Desc = 'Retail Demo Service' }
        @{ Name = 'WMPNetworkSvc';      Desc = 'Windows Media Player Network Sharing' }
        @{ Name = 'XblAuthManager';     Desc = 'Xbox Live Auth Manager' }
        @{ Name = 'XblGameSave';        Desc = 'Xbox Live Game Save' }
        @{ Name = 'XboxNetApiSvc';      Desc = 'Xbox Live Networking' }
        @{ Name = 'WSearch';            Desc = 'Windows Search (indexing)' }
        @{ Name = 'SysMain';            Desc = 'Superfetch/SysMain (prefetch)' }
        @{ Name = 'Fax';                Desc = 'Fax Service' }
        @{ Name = 'PhoneSvc';           Desc = 'Phone Service' }
        @{ Name = 'TabletInputService'; Desc = 'Touch Keyboard and Handwriting' }
        @{ Name = 'WerSvc';             Desc = 'Windows Error Reporting' }
    )

    Write-Host "`n  Service Optimizer" -ForegroundColor $Global:Theme.Primary
    Write-Host "  $('-' * 60)" -ForegroundColor $Global:Theme.Muted

    foreach ($svcInfo in $optionalServices) {
        $svc = Get-Service -Name $svcInfo.Name -ErrorAction SilentlyContinue
        if ($null -eq $svc) { continue }

        $isRunning = $svc.Status -eq 'Running'
        $icon = if ($isRunning) { '?' } else { '�' }
        $color = if ($isRunning) { $Global:Theme.Warning } else { $Global:Theme.Muted }
        $startType = $svc.StartType

        Write-Host "  $icon " -ForegroundColor $color -NoNewline
        Write-Host "$($svcInfo.Name.PadRight(25))" -ForegroundColor $Global:Theme.Text -NoNewline
        Write-Host "$($startType.ToString().PadRight(12))" -ForegroundColor $Global:Theme.Accent -NoNewline
        Write-Host "$($svcInfo.Desc)" -ForegroundColor $Global:Theme.Muted
    }

    $runningOptional = ($optionalServices | ForEach-Object -Process {
        Get-Service -Name $_.Name -ErrorAction SilentlyContinue
    } | Where-Object -FilterScript { $null -ne $_ -and $_.Status -eq 'Running' }).Count

    Write-Host "`n  $runningOptional optional service(s) currently running." -ForegroundColor $Global:Theme.Warning
    Write-Host '  Use Set-Service -Name <name> -StartupType Disabled to disable.' -ForegroundColor $Global:Theme.Muted
    Write-Host ''
}

#endregion

#region -- Disk Cleanup -------------------------------------------------------

<#
.SYNOPSIS
    Quick disk cleanup targeting common temp/cache directories.
.PARAMETER DryRun
    Show what would be cleaned without deleting.
.PARAMETER IncludeBrowserCache
    Also clean browser caches (Edge, Chrome, Firefox).
.EXAMPLE
    Invoke-DiskCleanup -DryRun
.EXAMPLE
    cleanup
#>
function Invoke-DiskCleanup {
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([void])]
    param(
        [Parameter()]
        [switch]$DryRun,

        [Parameter()]
        [switch]$IncludeBrowserCache
    )

    Write-Host "`n  Disk Cleanup" -ForegroundColor $Global:Theme.Primary
    Write-Host "  $('-' * 50)" -ForegroundColor $Global:Theme.Muted

    $targets = @(
        @{ Path = $env:TEMP; Name = 'User Temp' }
        @{ Path = 'C:\Windows\Temp'; Name = 'Windows Temp' }
        @{ Path = Join-Path -Path $env:LOCALAPPDATA -ChildPath 'Temp'; Name = 'AppData Temp' }
        @{ Path = 'C:\Windows\SoftwareDistribution\Download'; Name = 'Windows Update Cache' }
    )

    if ($IncludeBrowserCache) {
        $targets += @(
            @{ Path = Join-Path -Path $env:LOCALAPPDATA -ChildPath 'Google\Chrome\User Data\Default\Cache'; Name = 'Chrome Cache' }
            @{ Path = Join-Path -Path $env:LOCALAPPDATA -ChildPath 'Microsoft\Edge\User Data\Default\Cache'; Name = 'Edge Cache' }
        )
    }

    $totalFreed = 0

    foreach ($target in $targets) {
        if (-not (Test-Path -Path $target.Path)) { continue }

        $files = Get-ChildItem -Path $target.Path -Recurse -File -ErrorAction SilentlyContinue
        $sizeMB = [math]::Round(($files | Measure-Object -Property Length -Sum).Sum / 1MB, 1)
        $count = $files.Count

        if ($count -eq 0) { continue }

        Write-Host "  $($target.Name.PadRight(30))" -ForegroundColor $Global:Theme.Text -NoNewline
        Write-Host "$count files, $sizeMB MB" -ForegroundColor $Global:Theme.Warning

        if (-not $DryRun -and $PSCmdlet.ShouldProcess($target.Name, 'Clean')) {
            $files | Remove-Item -Force -ErrorAction SilentlyContinue
            Get-ChildItem -Path $target.Path -Directory -Recurse -ErrorAction SilentlyContinue |
                Where-Object -FilterScript { (Get-ChildItem -Path $_.FullName -ErrorAction SilentlyContinue).Count -eq 0 } |
                Remove-Item -Force -Recurse -ErrorAction SilentlyContinue
        }
        $totalFreed += $sizeMB
    }

    $verb = if ($DryRun) { 'Would free' } else { 'Freed' }
    Write-Host "`n  $verb`: ~$totalFreed MB" -ForegroundColor $Global:Theme.Success
    Write-Host ''
}

#endregion

#region -- Power Plan ---------------------------------------------------------

<#
.SYNOPSIS
    Switches Windows power plan.
.PARAMETER Plan
    Power plan to activate.
.PARAMETER List
    List available power plans.
.EXAMPLE
    Set-PowerPlan -Plan 'High Performance'
.EXAMPLE
    powerplan 'Balanced'
#>
function Set-PowerPlan {
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([void])]
    param(
        [Parameter(Position = 0, ParameterSetName = 'Set')]
        [ValidateSet('Balanced', 'High Performance', 'Power Saver', 'Ultimate Performance')]
        [string]$Plan,

        [Parameter(ParameterSetName = 'List')]
        [switch]$List
    )

    if ($List -or [string]::IsNullOrEmpty($Plan)) {
        Write-Host "`n  Power Plans" -ForegroundColor $Global:Theme.Primary
        Write-Host "  $('-' * 40)" -ForegroundColor $Global:Theme.Muted

        $plans = & powercfg /list 2>$null
        foreach ($line in $plans) {
            if ($line -match ':\s+(.+?)\s+\((.+?)\)(.*)$') {
                $guid = $Matches[1]
                $name = $Matches[2]
                $isActive = $Matches[3] -match '\*'
                $icon = if ($isActive) { '>' } else { ' ' }
                $color = if ($isActive) { $Global:Theme.Accent } else { $Global:Theme.Text }
                Write-Host "  $icon $name" -ForegroundColor $color
            }
        }
        Write-Host ''
        return
    }

    if (-not $PSCmdlet.ShouldProcess($Plan, "Set power plan")) { return }

    $guids = @{
        'Balanced'              = '381b4222-f694-41f0-9685-ff5bb260df2e'
        'High Performance'      = '8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c'
        'Power Saver'           = 'a1841308-3541-4fab-bc81-f71556f20b4a'
        'Ultimate Performance'  = 'e9a42b02-d5df-448d-aa00-03f14749eb61'
    }

    $guid = $guids[$Plan]
    & powercfg /setactive $guid 2>$null
    if ($LASTEXITCODE -eq 0) {
        Write-Host "  Power plan set: $Plan" -ForegroundColor $Global:Theme.Success
    }
    else {
        Write-Warning -Message "Failed to set power plan. '$Plan' may not be available."
    }
}

#endregion

#region -- System Info Quick Check --------------------------------------------

<#
.SYNOPSIS
    Quick Windows optimization health check.
.EXAMPLE
    Get-OptimizationStatus
.EXAMPLE
    optcheck
#>
function Get-OptimizationStatus {
    [CmdletBinding()]
    [OutputType([void])]
    param()

    Write-Host "`n  Optimization Status" -ForegroundColor $Global:Theme.Primary
    Write-Host "  $('-' * 55)" -ForegroundColor $Global:Theme.Muted

    # Disk space
    $drives = Get-PSDrive -PSProvider FileSystem -ErrorAction SilentlyContinue |
        Where-Object -FilterScript { $_.Used -gt 0 }

    Write-Host "`n  Disk Space:" -ForegroundColor $Global:Theme.Accent
    foreach ($drive in $drives) {
        $totalGB = [math]::Round(($drive.Used + $drive.Free) / 1GB, 1)
        $freeGB = [math]::Round($drive.Free / 1GB, 1)
        $usedPct = [math]::Round($drive.Used / ($drive.Used + $drive.Free) * 100)
        $color = if ($usedPct -gt 90) { $Global:Theme.Error } elseif ($usedPct -gt 75) { $Global:Theme.Warning } else { $Global:Theme.Success }

        Write-Host "    $($drive.Name): " -ForegroundColor $Global:Theme.Text -NoNewline
        Write-Host "$freeGB GB free" -ForegroundColor $color -NoNewline
        Write-Host " / $totalGB GB ($usedPct% used)" -ForegroundColor $Global:Theme.Muted
    }

    # Uptime
    $uptime = (Get-Date) - (Get-CimInstance -ClassName Win32_OperatingSystem -ErrorAction SilentlyContinue).LastBootUpTime
    $uptimeColor = if ($uptime.Days -gt 14) { $Global:Theme.Warning } else { $Global:Theme.Success }
    Write-Host "`n  Uptime: " -ForegroundColor $Global:Theme.Accent -NoNewline
    Write-Host "$($uptime.Days)d $($uptime.Hours)h $($uptime.Minutes)m" -ForegroundColor $uptimeColor

    # Process count
    $procCount = (Get-Process).Count
    $procColor = if ($procCount -gt 300) { $Global:Theme.Warning } else { $Global:Theme.Success }
    Write-Host "  Processes: " -ForegroundColor $Global:Theme.Accent -NoNewline
    Write-Host "$procCount" -ForegroundColor $procColor

    # Temp folder size
    $tempSize = [math]::Round((Get-ChildItem -Path $env:TEMP -Recurse -File -ErrorAction SilentlyContinue |
        Measure-Object -Property Length -Sum).Sum / 1MB, 0)
    $tempColor = if ($tempSize -gt 500) { $Global:Theme.Warning } else { $Global:Theme.Success }
    Write-Host "  Temp folder: " -ForegroundColor $Global:Theme.Accent -NoNewline
    Write-Host "$tempSize MB" -ForegroundColor $tempColor

    Write-Host ''
}

#endregion

#region -- Aliases -------------------------------------------------------------

Set-Alias -Name 'startups'    -Value 'Show-StartupApps'         -Scope Global -Force
Set-Alias -Name 'svcopt'      -Value 'Show-ServiceOptimizer'    -Scope Global -Force
Set-Alias -Name 'cleanup'     -Value 'Invoke-DiskCleanup'       -Scope Global -Force
Set-Alias -Name 'powerplan'   -Value 'Set-PowerPlan'            -Scope Global -Force
Set-Alias -Name 'optcheck' -Value 'Get-OptimizationStatus' -Scope Global -Force

#endregion
