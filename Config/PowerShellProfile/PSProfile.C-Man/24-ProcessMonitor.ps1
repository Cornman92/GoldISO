<#
.SYNOPSIS
    Process Monitor module for C-Man's PowerShell Profile.
.DESCRIPTION
    Real-time process watcher with threshold alerts, resource hog detector,
    process tree viewer, handle/DLL inspector, service dependency mapper,
    and crash dump collector.
.NOTES
    Module: 24-ProcessMonitor.ps1
    Requires: PowerShell 5.1+
#>

#region -- Resource Hog Detector ----------------------------------------------

<#
.SYNOPSIS
    Detects processes consuming excessive resources.
.PARAMETER CpuThreshold
    CPU percentage threshold. Default is 50.
.PARAMETER MemoryThresholdMB
    Memory threshold in MB. Default is 500.
.PARAMETER Top
    Number of top processes to show per category.
.EXAMPLE
    Find-ResourceHogs -CpuThreshold 30
.EXAMPLE
    hogs
#>
function Find-ResourceHogs {
    [CmdletBinding()]
    [OutputType([void])]
    param(
        [Parameter()]
        [ValidateRange(1, 100)]
        [int]$CpuThreshold = 50,

        [Parameter()]
        [ValidateRange(50, 32768)]
        [int]$MemoryThresholdMB = 500,

        [Parameter()]
        [ValidateRange(1, 50)]
        [int]$Top = 10
    )

    Write-Host "`n  Resource Hog Detector" -ForegroundColor $Global:Theme.Primary
    Write-Host "  $('-' * 65)" -ForegroundColor $Global:Theme.Muted

    # CPU hogs
    Write-Host "`n  Top CPU Consumers:" -ForegroundColor $Global:Theme.Accent
    $procs = Get-Process -ErrorAction SilentlyContinue | Where-Object -FilterScript { $_.CPU -gt 0 } |
        Sort-Object -Property CPU -Descending | Select-Object -First $Top

    foreach ($p in $procs) {
        $cpuSec = [math]::Round($p.CPU, 1)
        $memMB = [math]::Round($p.WorkingSet64 / 1MB, 1)
        $name = $p.ProcessName
        if ($name.Length -gt 25) { $name = $name.Substring(0, 22) + '...' }

        $isHog = $memMB -gt $MemoryThresholdMB
        $color = if ($isHog) { $Global:Theme.Error } else { $Global:Theme.Text }
        $icon = if ($isHog) { '!!' } else { '  ' }

        Write-Host "  $icon $($p.Id.ToString().PadLeft(7))" -ForegroundColor $Global:Theme.Muted -NoNewline
        Write-Host " $($name.PadRight(27))" -ForegroundColor $color -NoNewline
        Write-Host "CPU: $($cpuSec.ToString().PadLeft(10))s" -ForegroundColor $Global:Theme.Warning -NoNewline
        Write-Host "  Mem: $($memMB.ToString().PadLeft(8)) MB" -ForegroundColor $Global:Theme.Info
    }

    # Memory hogs
    Write-Host "`n  Top Memory Consumers:" -ForegroundColor $Global:Theme.Accent
    $memProcs = Get-Process -ErrorAction SilentlyContinue |
        Sort-Object -Property WorkingSet64 -Descending | Select-Object -First $Top

    foreach ($p in $memProcs) {
        $memMB = [math]::Round($p.WorkingSet64 / 1MB, 1)
        $name = $p.ProcessName
        if ($name.Length -gt 25) { $name = $name.Substring(0, 22) + '...' }
        $isHog = $memMB -gt $MemoryThresholdMB
        $color = if ($isHog) { $Global:Theme.Error } else { $Global:Theme.Text }
        $bar = '�' * [math]::Min([math]::Ceiling($memMB / 100), 20)

        Write-Host "  $($p.Id.ToString().PadLeft(7))" -ForegroundColor $Global:Theme.Muted -NoNewline
        Write-Host " $($name.PadRight(27))" -ForegroundColor $color -NoNewline
        Write-Host "$($memMB.ToString().PadLeft(8)) MB " -ForegroundColor $Global:Theme.Warning -NoNewline
        Write-Host "$bar" -ForegroundColor $Global:Theme.Info
    }

    # System summary
    $totalMem = (Get-CimInstance -ClassName Win32_ComputerSystem -ErrorAction SilentlyContinue).TotalPhysicalMemory
    $freeMem = (Get-CimInstance -ClassName Win32_OperatingSystem -ErrorAction SilentlyContinue).FreePhysicalMemory * 1KB
    if ($null -ne $totalMem) {
        $usedPct = [math]::Round((1 - $freeMem / $totalMem) * 100, 1)
        $memColor = if ($usedPct -gt 90) { $Global:Theme.Error } elseif ($usedPct -gt 70) { $Global:Theme.Warning } else { $Global:Theme.Success }
        Write-Host "`n  System Memory: $usedPct% used" -ForegroundColor $memColor
    }
    Write-Host ''
}

#endregion

#region -- Process Tree -------------------------------------------------------

<#
.SYNOPSIS
    Displays process hierarchy as a tree.
.PARAMETER RootPid
    Show tree starting from a specific PID.
.PARAMETER Depth
    Maximum tree depth.
.EXAMPLE
    Show-ProcessTree
.EXAMPLE
    ptree -RootPid 1234
#>
function Show-ProcessTree {
    [CmdletBinding()]
    [OutputType([void])]
    param(
        [Parameter(Position = 0)]
        [int]$RootPid = 0,

        [Parameter()]
        [ValidateRange(1, 20)]
        [int]$Depth = 5
    )

    Write-Host "`n  Process Tree" -ForegroundColor $Global:Theme.Primary
    Write-Host "  $('-' * 60)" -ForegroundColor $Global:Theme.Muted

    try {
        $processes = Get-CimInstance -ClassName Win32_Process -ErrorAction Stop |
            Select-Object -Property ProcessId, ParentProcessId, Name, CommandLine, WorkingSetSize

        $childMap = @{}
        foreach ($p in $processes) {
            if (-not $childMap.ContainsKey($p.ParentProcessId)) {
                $childMap[$p.ParentProcessId] = [System.Collections.Generic.List[object]]::new()
            }
            $childMap[$p.ParentProcessId].Add($p)
        }

        function Write-TreeNode {
            param([object]$Process, [string]$Prefix, [bool]$IsLast, [int]$CurrentDepth)

            if ($CurrentDepth -gt $Depth) { return }

            $connector = if ($CurrentDepth -eq 0) { '' } elseif ($IsLast) { '+- ' } else { '+- ' }
            $memMB = [math]::Round($Process.WorkingSetSize / 1MB, 1)

            Write-Host "  $Prefix$connector" -ForegroundColor $Global:Theme.Muted -NoNewline
            Write-Host "$($Process.ProcessId.ToString().PadLeft(6)) " -ForegroundColor $Global:Theme.Accent -NoNewline

            $name = $Process.Name
            if ($name.Length -gt 25) { $name = $name.Substring(0, 22) + '...' }
            Write-Host "$($name.PadRight(27))" -ForegroundColor $Global:Theme.Text -NoNewline
            Write-Host "$memMB MB" -ForegroundColor $Global:Theme.Muted

            $children = if ($childMap.ContainsKey($Process.ProcessId)) { $childMap[$Process.ProcessId] } else { @() }
            $childPrefix = $Prefix + $(if ($CurrentDepth -eq 0) { '' } elseif ($IsLast) { '   ' } else { '�  ' })

            for ($i = 0; $i -lt $children.Count; $i++) {
                $isChildLast = ($i -eq $children.Count - 1)
                Write-TreeNode -Process $children[$i] -Prefix $childPrefix -IsLast $isChildLast -CurrentDepth ($CurrentDepth + 1)
            }
        }

        if ($RootPid -gt 0) {
            $root = $processes | Where-Object -FilterScript { $_.ProcessId -eq $RootPid }
            if ($null -ne $root) {
                Write-TreeNode -Process $root -Prefix '' -IsLast $true -CurrentDepth 0
            }
            else {
                Write-Warning -Message "Process $RootPid not found."
            }
        }
        else {
            # Show top-level processes (no parent or parent not running)
            $allPids = $processes | ForEach-Object -Process { $_.ProcessId }
            $roots = $processes | Where-Object -FilterScript {
                $_.ParentProcessId -eq 0 -or $_.ParentProcessId -notin $allPids
            } | Sort-Object -Property Name | Select-Object -First 30

            foreach ($root in $roots) {
                Write-TreeNode -Process $root -Prefix '' -IsLast $true -CurrentDepth 0
            }
        }
    }
    catch {
        Write-Warning -Message "Cannot build process tree: $($_.Exception.Message)"
    }
    Write-Host ''
}

#endregion

#region -- Process Watcher ----------------------------------------------------

<#
.SYNOPSIS
    Watches a process with live resource tracking.
.PARAMETER Name
    Process name to watch.
.PARAMETER Pid
    Process ID to watch.
.PARAMETER IntervalSeconds
    Polling interval in seconds.
.PARAMETER Duration
    Maximum watch duration in seconds. Default 60.
.EXAMPLE
    Watch-Process -Name 'devenv' -IntervalSeconds 2
.EXAMPLE
    pwatch -Pid 1234
#>
function Watch-Process {
    [CmdletBinding(DefaultParameterSetName = 'ByName')]
    [OutputType([void])]
    param(
        [Parameter(Mandatory, Position = 0, ParameterSetName = 'ByName')]
        [string]$Name,

        [Parameter(Mandatory, ParameterSetName = 'ByPid')]
        [int]$Pid,

        [Parameter()]
        [ValidateRange(1, 30)]
        [int]$IntervalSeconds = 3,

        [Parameter()]
        [ValidateRange(5, 3600)]
        [int]$Duration = 60
    )

    Write-Host "`n  Process Watcher (Ctrl+C to stop)" -ForegroundColor $Global:Theme.Primary
    Write-Host "  $('-' * 50)" -ForegroundColor $Global:Theme.Muted

    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    $samples = [System.Collections.Generic.List[hashtable]]::new()

    while ($sw.Elapsed.TotalSeconds -lt $Duration) {
        $proc = if ($PSCmdlet.ParameterSetName -eq 'ByName') {
            Get-Process -Name $Name -ErrorAction SilentlyContinue | Select-Object -First 1
        }
        else {
            Get-Process -Id $Pid -ErrorAction SilentlyContinue
        }

        if ($null -eq $proc) {
            Write-Host "  Process not found. Waiting..." -ForegroundColor $Global:Theme.Warning
            Start-Sleep -Seconds $IntervalSeconds
            continue
        }

        $memMB = [math]::Round($proc.WorkingSet64 / 1MB, 1)
        $cpuSec = [math]::Round($proc.CPU, 2)
        $threads = $proc.Threads.Count
        $handles = $proc.HandleCount
        $elapsed = [math]::Round($sw.Elapsed.TotalSeconds)

        $sample = @{ Time = $elapsed; MemMB = $memMB; CpuSec = $cpuSec; Threads = $threads; Handles = $handles }
        $samples.Add($sample)

        $memColor = if ($memMB -gt 1000) { $Global:Theme.Error } elseif ($memMB -gt 500) { $Global:Theme.Warning } else { $Global:Theme.Success }

        Write-Host "`r  [$($elapsed.ToString().PadLeft(4))s] " -ForegroundColor $Global:Theme.Muted -NoNewline
        Write-Host "PID:$($proc.Id) " -ForegroundColor $Global:Theme.Accent -NoNewline
        Write-Host "Mem:$($memMB.ToString().PadLeft(8))MB " -ForegroundColor $memColor -NoNewline
        Write-Host "CPU:$($cpuSec.ToString().PadLeft(10))s " -ForegroundColor $Global:Theme.Warning -NoNewline
        Write-Host "TH:$threads HD:$handles" -ForegroundColor $Global:Theme.Muted -NoNewline

        Start-Sleep -Seconds $IntervalSeconds
    }

    # Summary
    if ($samples.Count -gt 0) {
        $avgMem = [math]::Round(($samples | ForEach-Object -Process { $_['MemMB'] } | Measure-Object -Average).Average, 1)
        $maxMem = [math]::Round(($samples | ForEach-Object -Process { $_['MemMB'] } | Measure-Object -Maximum).Maximum, 1)
        Write-Host "`n`n  Summary ($($samples.Count) samples):" -ForegroundColor $Global:Theme.Primary
        Write-Host "    Avg Memory: $avgMem MB  Max Memory: $maxMem MB" -ForegroundColor $Global:Theme.Text
    }
    Write-Host ''
}

#endregion

#region -- Service Dependency Mapper ------------------------------------------

<#
.SYNOPSIS
    Maps service dependencies for a Windows service.
.PARAMETER Name
    Service name.
.EXAMPLE
    Show-ServiceDependencies -Name 'wuauserv'
.EXAMPLE
    svcdeps wuauserv
#>
function Show-ServiceDependencies {
    [CmdletBinding()]
    [OutputType([void])]
    param(
        [Parameter(Mandatory, Position = 0)]
        [string]$Name
    )

    Write-Host "`n  Service Dependencies: $Name" -ForegroundColor $Global:Theme.Primary
    Write-Host "  $('-' * 50)" -ForegroundColor $Global:Theme.Muted

    $svc = Get-Service -Name $Name -ErrorAction SilentlyContinue
    if ($null -eq $svc) {
        Write-Warning -Message "Service '$Name' not found."
        return
    }

    $statusColor = switch ($svc.Status) {
        'Running' { $Global:Theme.Success }
        'Stopped' { $Global:Theme.Error }
        default   { $Global:Theme.Warning }
    }

    Write-Host "  $($svc.DisplayName) [$($svc.Status)]" -ForegroundColor $statusColor

    # Dependencies (services this one depends on)
    $deps = $svc.ServicesDependedOn
    if ($deps.Count -gt 0) {
        Write-Host "`n  Depends On ($($deps.Count)):" -ForegroundColor $Global:Theme.Accent
        foreach ($d in ($deps | Sort-Object -Property Name)) {
            $dColor = if ($d.Status -eq 'Running') { $Global:Theme.Success } else { $Global:Theme.Error }
            Write-Host "    +- $($d.Name.PadRight(30)) $($d.Status)" -ForegroundColor $dColor
        }
    }

    # Dependents (services that depend on this one)
    $dependents = $svc.DependentServices
    if ($dependents.Count -gt 0) {
        Write-Host "`n  Depended On By ($($dependents.Count)):" -ForegroundColor $Global:Theme.Accent
        foreach ($d in ($dependents | Sort-Object -Property Name)) {
            $dColor = if ($d.Status -eq 'Running') { $Global:Theme.Success } else { $Global:Theme.Error }
            Write-Host "    +- $($d.Name.PadRight(30)) $($d.Status)" -ForegroundColor $dColor
        }
    }
    Write-Host ''
}

#endregion

#region -- Handle Inspector ---------------------------------------------------

<#
.SYNOPSIS
    Shows loaded modules (DLLs) for a process.
.PARAMETER ProcessName
    Name of the process.
.PARAMETER Pid
    Process ID.
.PARAMETER Filter
    Filter module names.
.EXAMPLE
    Show-ProcessModules -ProcessName 'explorer'
#>
function Show-ProcessModules {
    [CmdletBinding(DefaultParameterSetName = 'ByName')]
    [OutputType([void])]
    param(
        [Parameter(Mandatory, Position = 0, ParameterSetName = 'ByName')]
        [string]$ProcessName,

        [Parameter(Mandatory, ParameterSetName = 'ByPid')]
        [int]$Pid,

        [Parameter()]
        [string]$Filter
    )

    $proc = if ($PSCmdlet.ParameterSetName -eq 'ByName') {
        Get-Process -Name $ProcessName -ErrorAction SilentlyContinue | Select-Object -First 1
    }
    else {
        Get-Process -Id $Pid -ErrorAction SilentlyContinue
    }

    if ($null -eq $proc) {
        Write-Warning -Message 'Process not found.'
        return
    }

    Write-Host "`n  Modules: $($proc.ProcessName) (PID: $($proc.Id))" -ForegroundColor $Global:Theme.Primary
    Write-Host "  $('-' * 60)" -ForegroundColor $Global:Theme.Muted

    try {
        $modules = $proc.Modules | Sort-Object -Property ModuleName
        if (-not [string]::IsNullOrEmpty($Filter)) {
            $modules = $modules | Where-Object -FilterScript { $_.ModuleName -match $Filter }
        }

        foreach ($mod in $modules) {
            $sizeMB = [math]::Round($mod.ModuleMemorySize / 1MB, 2)
            $name = $mod.ModuleName
            if ($name.Length -gt 30) { $name = $name.Substring(0, 27) + '...' }

            Write-Host "  $($name.PadRight(32))" -ForegroundColor $Global:Theme.Text -NoNewline
            Write-Host "$($sizeMB.ToString().PadLeft(8)) MB" -ForegroundColor $Global:Theme.Muted -NoNewline
            $verInfo = $mod.FileVersionInfo
            if ($null -ne $verInfo -and -not [string]::IsNullOrEmpty($verInfo.FileVersion)) {
                Write-Host "  v$($verInfo.FileVersion)" -ForegroundColor $Global:Theme.Info
            }
            else {
                Write-Host '' -ForegroundColor $Global:Theme.Muted
            }
        }

        Write-Host "`n  Total: $($modules.Count) modules" -ForegroundColor $Global:Theme.Muted
    }
    catch {
        Write-Warning -Message "Cannot access modules (try running as admin): $($_.Exception.Message)"
    }
    Write-Host ''
}

#endregion

#region -- Aliases -------------------------------------------------------------

Set-Alias -Name 'hogs'      -Value 'Find-ResourceHogs'        -Scope Global -Force
Set-Alias -Name 'ptree'     -Value 'Show-ProcessTree'         -Scope Global -Force
Set-Alias -Name 'pwatch'    -Value 'Watch-Process'            -Scope Global -Force
Set-Alias -Name 'svcdeps'   -Value 'Show-ServiceDependencies' -Scope Global -Force
Set-Alias -Name 'pmods'     -Value 'Show-ProcessModules'      -Scope Global -Force

#endregion

#region -- Tab Completion -----------------------------------------------------

Register-ArgumentCompleter -CommandName @('Watch-Process', 'Show-ProcessModules') -ParameterName 'ProcessName' -ScriptBlock {
    param($commandName, $parameterName, $wordToComplete, $commandAst, $fakeBoundParameters)

    Get-Process -ErrorAction SilentlyContinue |
        Select-Object -ExpandProperty ProcessName -Unique |
        Where-Object -FilterScript { $_ -like "${wordToComplete}*" } |
        Sort-Object |
        ForEach-Object -Process {
            [System.Management.Automation.CompletionResult]::new($_, $_, 'ParameterValue', $_)
        }
}

Register-ArgumentCompleter -CommandName 'Show-ServiceDependencies' -ParameterName 'Name' -ScriptBlock {
    param($commandName, $parameterName, $wordToComplete, $commandAst, $fakeBoundParameters)

    Get-Service -ErrorAction SilentlyContinue |
        Where-Object -FilterScript { $_.Name -like "${wordToComplete}*" } |
        Sort-Object -Property Name |
        ForEach-Object -Process {
            [System.Management.Automation.CompletionResult]::new($_.Name, $_.Name, 'ParameterValue', $_.DisplayName)
        }
}

#endregion
