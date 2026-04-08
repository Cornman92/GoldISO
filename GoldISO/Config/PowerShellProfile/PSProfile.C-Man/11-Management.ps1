[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingWriteHost', '', Justification = 'Profile management display requires Write-Host')]
param()

#region -- Lazy Module Loading ------------------------------------------------

<#
.SYNOPSIS
    Lazy-load heavy PowerShell modules on first use instead of at startup.
    This dramatically reduces profile load time.
#>

function Register-LazyModule {
    <#
    .SYNOPSIS
        Register a module for lazy loading. Creates a proxy command that loads the module on first use.
    .PARAMETER ModuleName
        The module to lazy-load.
    .PARAMETER Commands
        Commands that trigger the module load. If omitted, uses the module's exported commands.
    .EXAMPLE
        Register-LazyModule -ModuleName 'Az.Accounts' -Commands @('Connect-AzAccount', 'Get-AzContext')
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, Position = 0)]
        [string]$ModuleName,

        [string[]]$Commands
    )

    if (-not $Commands -or $Commands.Count -eq 0) {
        # Try to get commands from module manifest without loading
        $manifest = Get-Module -Name $ModuleName -ListAvailable | Select-Object -First 1
        if ($manifest -and $manifest.ExportedCommands.Count -gt 0) {
            $Commands = $manifest.ExportedCommands.Keys
        }
        else {
            return
        }
    }

    foreach ($command in $Commands) {
        $scriptBlock = {
            param()
            $moduleName = $MyInvocation.MyCommand.Name -replace '^_lazy_', ''

            # This is a closure trick - we capture the actual module name
            Write-Host -Object "  Loading $($script:LazyModuleMap[$MyInvocation.MyCommand.Name])..." -ForegroundColor $Global:Theme.Muted

            $actualModule = $script:LazyModuleMap[$MyInvocation.MyCommand.Name]
            Import-Module -Name $actualModule -Global -ErrorAction Stop

            # Remove the lazy proxy
            Remove-Item -Path "Function:\$($MyInvocation.MyCommand.Name)" -ErrorAction SilentlyContinue

            # Re-invoke the real command with original arguments
            $realCommand = Get-Command -Name $MyInvocation.MyCommand.Name -ErrorAction SilentlyContinue
            if ($realCommand) {
                & $realCommand @args
            }
        }.GetNewClosure()

        # Only create proxy if command doesn't already exist
        if (-not (Get-Command -Name $command -ErrorAction SilentlyContinue)) {
            if ($null -eq $script:LazyModuleMap) {
                $script:LazyModuleMap = @{}
            }
            $script:LazyModuleMap[$command] = $ModuleName

            $null = New-Item -Path "Function:\Global:$command" -Value $scriptBlock -Force -ErrorAction SilentlyContinue
        }
    }
}

# Register commonly heavy modules for lazy loading
if ($Global:ProfileConfig.EnableLazyLoading) {
    $lazyModules = @(
        @{ Name = 'Az.Accounts';       Commands = @('Connect-AzAccount', 'Get-AzContext', 'Set-AzContext') }
        @{ Name = 'Az.Resources';      Commands = @('Get-AzResource', 'Get-AzResourceGroup') }
        @{ Name = 'Pester';            Commands = @('Invoke-Pester', 'Describe', 'It', 'Should') }
        @{ Name = 'platyPS';           Commands = @('New-MarkdownHelp', 'Update-MarkdownHelp') }
        @{ Name = 'ImportExcel';       Commands = @('Import-Excel', 'Export-Excel') }
        @{ Name = 'Microsoft.Graph';   Commands = @('Connect-MgGraph', 'Get-MgUser') }
        @{ Name = 'SqlServer';         Commands = @('Invoke-Sqlcmd', 'Get-SqlDatabase') }
        @{ Name = 'VMware.PowerCLI';   Commands = @('Connect-VIServer', 'Get-VM') }
    )

    foreach ($module in $lazyModules) {
        if (Get-Module -Name $module.Name -ListAvailable -ErrorAction SilentlyContinue) {
            Register-LazyModule -ModuleName $module.Name -Commands $module.Commands
        }
    }
}

#endregion

#region -- Profile Management -------------------------------------------------

function Get-ProfileLoadTimes {
    <#
    .SYNOPSIS
        Display profile module load times for performance analysis.
    #>
    [CmdletBinding()]
    [Alias('loadtimes')]
    param()

    $tc = $Global:Theme
    Write-Host -Object "`n  Profile Load Times (Total: ${Global:ProfileLoadTimeMs}ms):" -ForegroundColor $tc.Primary

    $script:ProfileLoadTimes | Sort-Object -Property TimeMs -Descending | ForEach-Object -Process {
        $barLength = [math]::Min([math]::Round($_.TimeMs / 10), 40)
        $bar = [string]::new([char]0x2588, [math]::Max($barLength, 1))
        $statusColor = if ($_.Status -eq 'OK') { $tc.Success } else { $tc.Error }
        $barColor = if ($_.TimeMs -gt $Global:ProfileConfig.MaxModuleLoadTimeMs) { $tc.Warning } else { $tc.Accent }

        Write-Host -Object "    $($_.Module.PadRight(25))" -ForegroundColor $tc.Text -NoNewline
        Write-Host -Object "$("$($_.TimeMs)ms".PadLeft(8)) " -ForegroundColor $statusColor -NoNewline
        Write-Host -Object $bar -ForegroundColor $barColor
    }
    Write-Host ''
}

function Update-ProfileConfig {
    <#
    .SYNOPSIS
        Update a profile configuration value and save.
    .PARAMETER Key
        Configuration key to update.
    .PARAMETER Value
        New value for the key.
    .EXAMPLE
        Update-ProfileConfig -Key 'Theme' -Value 'Cyberpunk'
    .EXAMPLE
        Update-ProfileConfig -Key 'BannerMode' -Value 'Expanded'
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, Position = 0)]
        [string]$Key,

        [Parameter(Mandatory, Position = 1)]
        [object]$Value
    )

    $tc = $Global:Theme
    if ($null -eq ($Global:ProfileConfig.PSObject.Properties | Where-Object -FilterScript { $_.Name -eq $Key })) {
        Write-Warning -Message "Unknown config key: $Key"
        Write-Host -Object '  Valid keys:' -ForegroundColor $tc.Muted
        $Global:ProfileConfig.PSObject.Properties.Name | ForEach-Object -Process {
            Write-Host -Object "    $_" -ForegroundColor $tc.Text
        }
        return
    }

    $Global:ProfileConfig.$Key = $Value
    $configPath = Join-Path -Path $script:ProfileRoot -ChildPath 'Config' |
        Join-Path -ChildPath 'profile-config.json'
    $Global:ProfileConfig | ConvertTo-Json -Depth 5 |
        Set-Content -Path $configPath -Encoding UTF8

    Write-Host -Object "  Config updated: $Key = $Value" -ForegroundColor $tc.Success
}

function Show-ProfileConfig {
    <#
    .SYNOPSIS
        Display current profile configuration.
    #>
    [CmdletBinding()]
    [Alias('config')]
    param()

    $tc = $Global:Theme
    Write-Host -Object "`n  Profile Configuration:" -ForegroundColor $tc.Primary
    $Global:ProfileConfig.PSObject.Properties | Sort-Object -Property Name | ForEach-Object -Process {
        $valueStr = if ($_.Value -is [array]) { $_.Value -join ', ' } else { "$($_.Value)" }
        $valueColor = switch -Regex ($valueStr) {
            '^True$'  { $tc.Success }
            '^False$' { $tc.Error }
            default   { $tc.Text }
        }
        Write-Host -Object "    $($_.Name.PadRight(30))" -ForegroundColor $tc.Accent -NoNewline
        Write-Host -Object $valueStr -ForegroundColor $valueColor
    }
    Write-Host ''
}

function Show-ProfileHelp {
    <#
    .SYNOPSIS
        Display comprehensive profile help with all available commands.
    #>
    [CmdletBinding()]
    [Alias('phelp')]
    param()

    $tc = $Global:Theme
    Write-Host ''
    Write-Host -Object '  +--------------------------------------------------------------+' -ForegroundColor $tc.Primary
    Write-Host -Object '  �          C-MAN POWERSHELL PROFILE - COMMAND REFERENCE        �' -ForegroundColor $tc.Primary
    Write-Host -Object '  �--------------------------------------------------------------�' -ForegroundColor $tc.Primary

    $commandGroups = @(
        @{ Group = 'Navigation';   Commands = @('go <bookmark>', 'bm <name>', 'bms', 'up [N]', 'bd/fd', 'z <query>', 'cdd', 'cdp') }
        @{ Group = 'Files';        Commands = @('fif <pattern>', 'ff <name>', 'sha <file>', 'dirsize', 'cpath', 'cfile', 'cpaste') }
        @{ Group = 'System';       Commands = @('sysinfo', 'myip', 'ports', 'killport', 'top', 'pgrep', 'pkill', 'showpath', 'sudo') }
        @{ Group = 'Dev Tools';    Commands = @('devenv', 'projinfo', 'cdp', 'cleanall', 'lint', 'cloc', 'bench') }
        @{ Group = 'SysAdmin';     Commands = @('svcfind', 'svcrestart', 'testport', 'mping', 'netinfo', 'sshlist', 'vms') }
        @{ Group = 'Profile';      Commands = @('config', 'loadtimes', 'phelp', 'banner', 'aliases', 'theme', 'logs', 'errors') }
        @{ Group = 'Utilities';    Commands = @('pjson', 'genpass', 'guid', 'touch', 'mkcd', 'rmrf', 'reload') }
    )

    foreach ($cg in $commandGroups) {
        Write-Host -Object '  �' -ForegroundColor $tc.Primary -NoNewline
        Write-Host -Object "  [$($cg.Group)]" -ForegroundColor $tc.Accent -NoNewline
        $headerPad = 60 - "  [$($cg.Group)]".Length
        Write-Host -Object (' ' * $headerPad) -NoNewline
        Write-Host -Object '�' -ForegroundColor $tc.Primary

        foreach ($cmd in $cg.Commands) {
            $cmdPad = 60 - "    $cmd".Length
            if ($cmdPad -lt 0) { $cmdPad = 0 }
            Write-Host -Object '  �' -ForegroundColor $tc.Primary -NoNewline
            Write-Host -Object "    $cmd" -ForegroundColor $tc.Text -NoNewline
            Write-Host -Object (' ' * $cmdPad) -NoNewline
            Write-Host -Object '�' -ForegroundColor $tc.Primary
        }
    }

    Write-Host -Object '  �--------------------------------------------------------------�' -ForegroundColor $tc.Primary
    Write-Host -Object '  �' -ForegroundColor $tc.Primary -NoNewline
    Write-Host -Object '  Use Get-Help <command> -Full for detailed help on any command  ' -ForegroundColor $tc.Info -NoNewline
    Write-Host -Object '�' -ForegroundColor $tc.Primary
    Write-Host -Object '  +--------------------------------------------------------------+' -ForegroundColor $tc.Primary
    Write-Host ''
}

# Convenience aliases
Set-Alias -Name 'aliases' -Value Show-ProfileAliases   -Option AllScope -Force
Set-Alias -Name 'theme'   -Value Set-ProfileTheme      -Option AllScope -Force

#endregion
