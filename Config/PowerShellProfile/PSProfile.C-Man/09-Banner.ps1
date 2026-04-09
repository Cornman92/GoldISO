[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingWriteHost', '', Justification = 'Banner display is entirely Write-Host based')]
param()

#region ── Startup Banner ─────────────────────────────────────────────────────

function Show-ProfileBanner {
    <#
    .SYNOPSIS
        Display the startup banner. Compact by default, expandable.
    .PARAMETER Expanded
        Show full system dashboard instead of compact banner.
    #>
    [CmdletBinding()]
    param(
        [switch]$Expanded
    )

    $tc = $Global:Theme
    $mode = if ($Expanded) { 'Expanded' } else { $Global:ProfileConfig.BannerMode }
    $isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
        [Security.Principal.WindowsBuiltInRole]::Administrator
    )

    if ($mode -eq 'Compact') {
        Show-CompactBanner -Theme $tc -IsAdmin $isAdmin
    }
    else {
        Show-ExpandedBanner -Theme $tc -IsAdmin $isAdmin
    }
}

function Show-CompactBanner {
    <#
    .SYNOPSIS
        Compact 3-line startup banner with essential info.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object]$Theme,

        [bool]$IsAdmin
    )

    $tc = $Theme
    $adminTag = if ($IsAdmin) { " [C-Man]" } else { '' }
    $psVersion = "PS $($PSVersionTable.PSVersion.Major).$($PSVersionTable.PSVersion.Minor)"
    $profileModuleCount = $script:ProfileLoadTimes.Count
    $failCount = ($script:ProfileLoadTimes | Where-Object -FilterScript { $_.Status -ne 'OK' }).Count
    $failStr = if ($failCount -gt 0) { " ($failCount failed)" } else { '' }

    Write-Host ''
    Write-Host -Object '  ╔â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•╗' -ForegroundColor $tc.Primary
    Write-Host -Object '  ║' -ForegroundColor $tc.Primary -NoNewline
    Write-Host -Object '  C-Man Terminal' -ForegroundColor $tc.Accent -NoNewline
    Write-Host -Object "$adminTag" -ForegroundColor Red -NoNewline
    $spacer = ' ' * (41 - $adminTag.Length - $psVersion.Length)
    Write-Host -Object "$spacer$psVersion" -ForegroundColor $tc.Muted -NoNewline
    Write-Host -Object '  ║' -ForegroundColor $tc.Primary
    Write-Host -Object '  ║' -ForegroundColor $tc.Primary -NoNewline
    Write-Host -Object "  Loaded $profileModuleCount modules in ${Global:ProfileLoadTimeMs}ms$failStr" -ForegroundColor $tc.Text -NoNewline
    $infoSpacer = ' ' * (55 - "Loaded $profileModuleCount modules in ${Global:ProfileLoadTimeMs}ms$failStr".Length)
    Write-Host -Object "$infoSpacer" -NoNewline
    Write-Host -Object '║' -ForegroundColor $tc.Primary
    Write-Host -Object '  ║' -ForegroundColor $tc.Primary -NoNewline
    Write-Host -Object '  F1=Help  banner -Expanded  aliases  devenv' -ForegroundColor $tc.Muted -NoNewline
    Write-Host -Object '              ║' -ForegroundColor $tc.Primary
    Write-Host -Object '  ╚â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•' -ForegroundColor $tc.Primary
    Write-Host ''
}

function Show-ExpandedBanner {
    <#
    .SYNOPSIS
        Full system dashboard banner with hardware, network, and dev tool info.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object]$Theme,

        [bool]$IsAdmin
    )

    $tc = $Theme
    $adminTag = if ($IsAdmin) { ' [ADMIN]' } else { '' }

    # System info (with error handling for missing WMI)
    $hostname = $env:COMPUTERNAME
    $username = $env:USERNAME
    $psVersion = "$($PSVersionTable.PSVersion)"

    $osCaption = 'Unknown'
    $cpuName = 'Unknown'
    $totalMemGb = 0
    $usedMemPct = 0
    $uptimeStr = 'Unknown'
    $diskFreeGb = 0
    $diskTotalGb = 0

    try {
        $os = Get-CimInstance -ClassName Win32_OperatingSystem -ErrorAction Stop
        $cpu = Get-CimInstance -ClassName Win32_Processor -ErrorAction Stop | Select-Object -First 1
        $disk = Get-CimInstance -ClassName Win32_LogicalDisk -Filter "DeviceID='C:'" -ErrorAction Stop

        $osCaption = $os.Caption -replace 'Microsoft ', ''
        $cpuName = $cpu.Name.Trim()
        if ($cpuName.Length -gt 40) { $cpuName = $cpuName.Substring(0, 37) + '...' }
        $totalMemGb = [math]::Round($os.TotalVisibleMemorySize / 1MB, 1)
        $usedMemPct = [math]::Round((($os.TotalVisibleMemorySize - $os.FreePhysicalMemory) / $os.TotalVisibleMemorySize) * 100, 0)
        $uptime = (Get-Date) - $os.LastBootUpTime
        $uptimeStr = "$($uptime.Days)d $($uptime.Hours)h $($uptime.Minutes)m"
        $diskFreeGb = [math]::Round($disk.FreeSpace / 1GB, 0)
        $diskTotalGb = [math]::Round($disk.Size / 1GB, 0)
    }
    catch {
        # Silently continue with defaults
    }

    # Memory bar
    $barLength = 20
    $filledLength = [math]::Round(($usedMemPct / 100) * $barLength)
    $emptyLength = $barLength - $filledLength
    $memBar = ('[' + ('#' * $filledLength) + ('-' * $emptyLength) + ']')
    $memColor = if ($usedMemPct -lt 70) { $tc.Success } elseif ($usedMemPct -lt 90) { $tc.Warning } else { $tc.Error }

    Write-Host ''
    Write-Host -Object '  ╔â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•╗' -ForegroundColor $tc.Primary
    Write-Host -Object '  ║                                                              ║' -ForegroundColor $tc.Primary

    # ASCII Art - Matrix style
    Write-Host -Object '  ║' -ForegroundColor $tc.Primary -NoNewline
    Write-Host -Object '     ██████╗      ███╗   ███╗ █████╗ ███╗   ██╗             ' -ForegroundColor $tc.Accent -NoNewline
    Write-Host -Object '║' -ForegroundColor $tc.Primary
    Write-Host -Object '  ║' -ForegroundColor $tc.Primary -NoNewline
    Write-Host -Object '    ██╔â•â•â•â•â•█████╗████╗ ████║██╔â•â•██╗████╗  ██║             ' -ForegroundColor $tc.Accent -NoNewline
    Write-Host -Object '║' -ForegroundColor $tc.Primary
    Write-Host -Object '  ║' -ForegroundColor $tc.Primary -NoNewline
    Write-Host -Object '    ██║     ╚â•â•â•â•â•██╔████╔██║███████║██╔██╗ ██║             ' -ForegroundColor $tc.Accent -NoNewline
    Write-Host -Object '║' -ForegroundColor $tc.Primary
    Write-Host -Object '  ║' -ForegroundColor $tc.Primary -NoNewline
    Write-Host -Object '    ██║           ██║╚██╔â•██║██╔â•â•██║██║╚██╗██║             ' -ForegroundColor $tc.Accent -NoNewline
    Write-Host -Object '║' -ForegroundColor $tc.Primary
    Write-Host -Object '  ║' -ForegroundColor $tc.Primary -NoNewline
    Write-Host -Object '    ╚██████╗      ██║ ╚â•â• ██║██║  ██║██║ ╚████║             ' -ForegroundColor $tc.Accent -NoNewline
    Write-Host -Object '║' -ForegroundColor $tc.Primary
    Write-Host -Object '  ║' -ForegroundColor $tc.Primary -NoNewline
    Write-Host -Object '     ╚â•â•â•â•â•â•      ╚â•â•     ╚â•â•╚â•â•  ╚â•â•╚â•â•  ╚â•â•â•â•             ' -ForegroundColor $tc.Accent -NoNewline
    Write-Host -Object '║' -ForegroundColor $tc.Primary

    Write-Host -Object '  ║                                                              ║' -ForegroundColor $tc.Primary
    Write-Host -Object '  ╠â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•╣' -ForegroundColor $tc.Primary

    # System info lines
    $infoLines = @(
        @{ Label = 'Host';   Value = "$username@$hostname$adminTag" }
        @{ Label = 'OS';     Value = $osCaption }
        @{ Label = 'CPU';    Value = $cpuName }
        @{ Label = 'Memory'; Value = "$memBar ${usedMemPct}% of ${totalMemGb}GB"; Color = $memColor }
        @{ Label = 'Disk C'; Value = "${diskFreeGb}GB free of ${diskTotalGb}GB" }
        @{ Label = 'Uptime'; Value = $uptimeStr }
        @{ Label = 'Shell';  Value = "PowerShell $psVersion" }
        @{ Label = 'Theme';  Value = $script:ProfileConfig.Theme }
    )

    foreach ($info in $infoLines) {
        $valueColor = if ($info.Color) { $info.Color } else { $tc.Text }
        $label = "  $($info.Label.PadRight(8))"
        $value = $info.Value
        $padding = 60 - $label.Length - $value.Length
        if ($padding -lt 0) { $padding = 0 }

        Write-Host -Object '  ║' -ForegroundColor $tc.Primary -NoNewline
        Write-Host -Object $label -ForegroundColor $tc.Muted -NoNewline
        Write-Host -Object $value -ForegroundColor $valueColor -NoNewline
        Write-Host -Object (' ' * $padding) -NoNewline
        Write-Host -Object '║' -ForegroundColor $tc.Primary
    }

    Write-Host -Object '  ╠â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•╣' -ForegroundColor $tc.Primary

    # Module load times
    Write-Host -Object '  ║' -ForegroundColor $tc.Primary -NoNewline
    Write-Host -Object "  Modules loaded in ${Global:ProfileLoadTimeMs}ms:" -ForegroundColor $tc.Info -NoNewline
    $modPad = 60 - "  Modules loaded in ${Global:ProfileLoadTimeMs}ms:".Length
    Write-Host -Object (' ' * $modPad) -NoNewline
    Write-Host -Object '║' -ForegroundColor $tc.Primary

    foreach ($mod in $script:ProfileLoadTimes) {
        $statusIcon = if ($mod.Status -eq 'OK') { [char]0x2713 } else { [char]0x2717 }
        $statusColor = if ($mod.Status -eq 'OK') { $tc.Success } else { $tc.Error }
        $modLine = "  $statusIcon $($mod.Module.PadRight(25)) $("$($mod.TimeMs)ms".PadLeft(8))"
        $modPadding = 60 - $modLine.Length
        if ($modPadding -lt 0) { $modPadding = 0 }

        Write-Host -Object '  ║' -ForegroundColor $tc.Primary -NoNewline
        Write-Host -Object "  $statusIcon " -ForegroundColor $statusColor -NoNewline
        Write-Host -Object "$($mod.Module.PadRight(25))" -ForegroundColor $tc.Text -NoNewline
        Write-Host -Object "$("$($mod.TimeMs)ms".PadLeft(8))" -ForegroundColor $tc.Muted -NoNewline
        Write-Host -Object (' ' * ($modPadding - 2)) -NoNewline
        Write-Host -Object '║' -ForegroundColor $tc.Primary
    }

    Write-Host -Object '  ╚â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•' -ForegroundColor $tc.Primary
    Write-Host ''
}

function Set-BannerMode {
    <#
    .SYNOPSIS
        Switch banner mode between Compact and Expanded.
    .PARAMETER Mode
        Banner display mode.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, Position = 0)]
        [ValidateSet('Compact', 'Expanded', 'Off')]
        [string]$Mode
    )

    $script:ProfileConfig.BannerMode = $Mode
    $configPath = Join-Path -Path $script:ProfileRoot -ChildPath 'Config' |
        Join-Path -ChildPath 'profile-config.json'
    $Global:ProfileConfig | ConvertTo-Json -Depth 5 |
        Set-Content -Path $configPath -Encoding UTF8
    Write-Host -Object "  Banner mode set to: $Mode" -ForegroundColor $Global:Theme.Success
}

# Alias for quick expanded banner display
function Show-Banner {
    <#
    .SYNOPSIS
        Shortcut to show the expanded banner on demand.
    #>
    [CmdletBinding()]
    [Alias('banner')]
    param(
        [switch]$Expanded
    )

    if ($Expanded) {
        Show-ProfileBanner -Expanded
    }
    else {
        Show-ProfileBanner
    }
}

#endregion

