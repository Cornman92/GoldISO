[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingWriteHost', '', Justification = 'Lazy loading notifications require colored output')]
param()

#region ─────────────────────────────────────────────────────────────────────────────
# Lazy Module Loader
# Defers loading of non-critical modules until first use
# ─────────────────────────────────────────────────────────────────────────────

# Modules to load at startup (critical + frequently used)
$script:ImmediateModules = @(
    '00-Themes.ps1'
    '01-PSReadLine.ps1'
    '02-Prompt.ps1'
    '03-Navigation.ps1'
    '04-Aliases.ps1'
    '05-Functions-Core.ps1'
    '06-Functions-Dev.ps1'
    '07-Functions-SysAdmin.ps1'
    '08-Completers.ps1'
    '09-Banner.ps1'
    '10-Logging.ps1'
    '12-Better11.ps1'
    '15-SecretVault.ps1'
)

# Modules to load on demand (rarely used)
$script:DeferredModules = @(
    '11-Management.ps1'
    '13-AutoUpdater.ps1'
    '14-ExtendedTools.ps1'
    '16-GitWorkflow.ps1'
    '17-EnvironmentSwitcher.ps1'
    '18-Snippets.ps1'
    '19-PackageHealth.ps1'
    '20-ClipboardRing.ps1'
    '21-DockerWorkflow.ps1'
    '22-DotnetToolbox.ps1'
    '23-NetworkDiag.ps1'
    '24-ProcessMonitor.ps1'
    '25-FileOpsAdvanced.ps1'
    '26-RegistryTools.ps1'
    '27-TaskScheduler.ps1'
    '28-WindowsOptimizer.ps1'
    '29-APIClient.ps1'
    '30-LoggingEnhanced.ps1'
)

# Track which deferred modules have been loaded
$script:LoadedDeferredModules = @{}
# Track failed module loads to prevent hammering
$script:FailedDeferredModules = @{}

# Map of commands/functions to their module (for auto-loading)
$script:DeferredCommandMap = @{
    # 11-Management
    'Show-ProfileHelp'      = '11-Management.ps1'
    'Get-ProfileConfig'     = '11-Management.ps1'
    'Set-ProfileConfig'     = '11-Management.ps1'
    'Show-ProfileStats'     = '11-Management.ps1'
    'Invoke-ProfileReload'  = '11-Management.ps1'
    'Edit-Profile'          = '11-Management.ps1'

    # 13-AutoUpdater
    'Update-Profile'        = '13-AutoUpdater.ps1'
    'Check-ProfileUpdate'   = '13-AutoUpdater.ps1'

    # 14-ExtendedTools
    'npm'                   = '14-ExtendedTools.ps1'
    'pip'                   = '14-ExtendedTools.ps1'
    'podman'                = '14-ExtendedTools.ps1'
    'wsl'                   = '14-ExtendedTools.ps1'
    'Invoke-DriftDetection' = '14-ExtendedTools.ps1'
    'Show-CIStatus'         = '14-ExtendedTools.ps1'

    # 15-SecretVault - Keeping in immediate for security responsiveness
    # 16-GitWorkflow
    'git'                   = '16-GitWorkflow.ps1'
    'gcommit'               = '16-GitWorkflow.ps1'
    'ga'                    = '16-GitWorkflow.ps1'
    'gpush'                 = '16-GitWorkflow.ps1'
    'gpull'                 = '16-GitWorkflow.ps1'
    'gbranch'               = '16-GitWorkflow.ps1'
    'gmerge'                = '16-GitWorkflow.ps1'
    'grbase'                = '16-GitWorkflow.ps1'
    'gcleanup'              = '16-GitWorkflow.ps1'
    'gsave'                 = '16-GitWorkflow.ps1'
    'gstashes'              = '16-GitWorkflow.ps1'
    'grestore'              = '16-GitWorkflow.ps1'
    'gconflict'             = '16-GitWorkflow.ps1'
    'pr'                    = '16-GitWorkflow.ps1'
    'glog'                  = '16-GitWorkflow.ps1'
    'gdiff'                 = '16-GitWorkflow.ps1'
    'gamend'                = '16-GitWorkflow.ps1'
    'gundo'                 = '16-GitWorkflow.ps1'
    'gwt'                   = '16-GitWorkflow.ps1'
    'gwtnew'                = '16-GitWorkflow.ps1'

    # 17-EnvironmentSwitcher
    'envload'               = '17-EnvironmentSwitcher.ps1'
    'envunload'             = '17-EnvironmentSwitcher.ps1'
    'envstack'              = '17-EnvironmentSwitcher.ps1'
    'envdiff'               = '17-EnvironmentSwitcher.ps1'
    'envls'                 = '17-EnvironmentSwitcher.ps1'
    'envauto'               = '17-EnvironmentSwitcher.ps1'
    'envtemplate'           = '17-EnvironmentSwitcher.ps1'

    # 18-Snippets
    'templates'             = '18-Snippets.ps1'
    'scaffold'              = '18-Snippets.ps1'

    # 19-PackageHealth
    'health'                = '19-PackageHealth.ps1'
    'pkgupdate'             = '19-PackageHealth.ps1'

    # 20-ClipboardRing
    'clip+'                 = '20-ClipboardRing.ps1'
    'clip-'                 = '20-ClipboardRing.ps1'
    'clipls'                = '20-ClipboardRing.ps1'
    'clipsearch'            = '20-ClipboardRing.ps1'
    'clipx'                 = '20-ClipboardRing.ps1'
    'clipclear'             = '20-ClipboardRing.ps1'

    # 21-DockerWorkflow
    'docker'                = '21-DockerWorkflow.ps1'
    'dc'                    = '21-DockerWorkflow.ps1'
    'docker-compose'        = '21-DockerWorkflow.ps1'

    # 22-DotnetToolbox
    'dotnet'                = '22-DotnetToolbox.ps1'
    'dotnet-info'           = '22-DotnetToolbox.ps1'
    'dotnet-list'           = '22-DotnetToolbox.ps1'
    'dotnet-clean'          = '22-DotnetToolbox.ps1'
    'dotnet-build'          = '22-DotnetToolbox.ps1'
    'dotnet-test'           = '22-DotnetToolbox.ps1'
    'dotnet-publish'        = '22-DotnetToolbox.ps1'
    'dotnet-run'            = '22-DotnetToolbox.ps1'
    'dotnet-new'            = '22-DotnetToolbox.ps1'
    'dotnet-add'            = '22-DotnetToolbox.ps1'
    'dotnet-remove'         = '22-DotnetToolbox.ps1'
    'dotnet-format'         = '22-DotnetToolbox.ps1'
    'dotnet-watch'          = '22-DotnetToolbox.ps1'
    'dotnet-msbuild'        = '22-DotnetToolbox.ps1'

    # 23-NetworkDiag
    'Test-Network'          = '23-NetworkDiag.ps1'
    'Show-NetworkInfo'      = '23-NetworkDiag.ps1'
    'Test-Port'             = '23-NetworkDiag.ps1'
    'Trace-Route'           = '23-NetworkDiag.ps1'
    'Get-LanIP'             = '23-NetworkDiag.ps1'
    'Get-PublicIP'          = '23-NetworkDiag.ps1'

    # 24-ProcessMonitor
    'Find-ResourceHogs'     = '24-ProcessMonitor.ps1'
    'hogs'                  = '24-ProcessMonitor.ps1'
    'Show-ProcessTree'      = '24-ProcessMonitor.ps1'
    'Watch-Process'         = '24-ProcessMonitor.ps1'
    'Show-ProcessHogs'      = '24-ProcessMonitor.ps1'
    'Get-ProcessHandles'    = '24-ProcessMonitor.ps1'
    'Get-ProcessModules'    = '24-ProcessMonitor.ps1'
    'Find-ProcessByName'    = '24-ProcessMonitor.ps1'
    'Stop-ProcessByName'    = '24-ProcessMonitor.ps1'
    'Get-ServiceDetail'     = '24-ProcessMonitor.ps1'

    # 25-FileOpsAdvanced
    'Rename-BulkFiles'      = '25-FileOpsAdvanced.ps1'
    'bulkrename'            = '25-FileOpsAdvanced.ps1'
    'Find-Duplicates'       = '25-FileOpsAdvanced.ps1'
    'dupes'                 = '25-FileOpsAdvanced.ps1'
    'Compare-Directories'   = '25-FileOpsAdvanced.ps1'
    'dircompare'            = '25-FileOpsAdvanced.ps1'
    'Watch-File'            = '25-FileOpsAdvanced.ps1'
    'filewatch'             = '25-FileOpsAdvanced.ps1'
    'Manage-Junction'       = '25-FileOpsAdvanced.ps1'
    'junction'              = '25-FileOpsAdvanced.ps1'
    'Find-LargeFiles'       = '25-FileOpsAdvanced.ps1'
    'largefiles'            = '25-FileOpsAdvanced.ps1'

    # 26-RegistryTools
    'Get-RegValue'          = '26-RegistryTools.ps1'
    'regget'                = '26-RegistryTools.ps1'
    'Set-RegValue'          = '26-RegistryTools.ps1'
    'regset'                = '26-RegistryTools.ps1'
    'Remove-RegValue'       = '26-RegistryTools.ps1'
    'regremove'             = '26-RegistryTools.ps1'
    'Get-RegSubkeys'        = '26-RegistryTools.ps1'
    'regsubkeys'            = '26-RegistryTools.ps1'
    'Get-RegKeys'           = '26-RegistryTools.ps1'
    'regkeys'               = '26-RegistryTools.ps1'
    'Export-RegKey'         = '26-RegistryTools.ps1'
    'regekey'               = '26-RegistryTools.ps1'
    'Import-RegKey'         = '26-RegistryTools.ps1'
    'regimport'             = '26-RegistryTools.ps1'
    'Reg-MultiString'       = '26-RegistryTools.ps1'
    'regmulti'              = '26-RegistryTools.ps1'

    # 27-TaskScheduler
    'Show-ScheduledTasks'   = '27-TaskScheduler.ps1'
    'scheduledtasks'        = '27-TaskScheduler.ps1'
    'New-ScheduledTask'     = '27-TaskScheduler.ps1'
    'newtask'               = '27-TaskScheduler.ps1'
    'Remove-ScheduledTask'  = '27-TaskScheduler.ps1'
    'removetask'            = '27-TaskScheduler.ps1'
    'Get-ScheduledTask'     = '27-TaskScheduler.ps1'
    'gettask'               = '27-TaskScheduler.ps1'

    # 28-WindowsOptimizer
    'Optimize-Windows'      = '28-WindowsOptimizer.ps1'
    'winopt'                = '28-WindowsOptimizer.ps1'
    'Disable-Telemetry'     = '28-WindowsOptimizer.ps1'
    'notel'                 = '28-WindowsOptimizer.ps1'
    'Enable-GamingMode'     = '28-WindowsOptimizer.ps1'
    'gamemode'              = '28-WindowsOptimizer.ps1'
    'Clean-WinSxS'          = '28-WindowsOptimizer.ps1'
    'cleansxs'              = '28-WindowsOptimizer.ps1'
    'Optimize-StartMenu'    = '28-WindowsOptimizer.ps1'
    'optstart'              = '28-WindowsOptimizer.ps1'
    'Disable-Hibernation'   = '28-WindowsOptimizer.ps1'
    'hiboff'                = '28-WindowsOptimizer.ps1'
    'Reduce-BootTimeout'    = '28-WindowsOptimizer.ps1'
    'boottimeout'           = '28-WindowsOptimizer.ps1'

    # 29-APIClient
    'Invoke-Api'            = '29-APIClient.ps1'
    'Get-Api'               = '29-APIClient.ps1'
    'Post-Api'              = '29-APIClient.ps1'
    'Put-Api'               = '29-APIClient.ps1'
    'Delete-Api'            = '29-APIClient.ps1'

    # 30-LoggingEnhanced
    'Show-LogStats'         = '30-LoggingEnhanced.ps1'
    'logstats'              = '30-LoggingEnhanced.ps1'
    'Clear-OldLogs'         = '30-LoggingEnhanced.ps1'
    'clearlogs'             = '30-LoggingEnhanced.ps1'
    'Enable-DebugLogging'   = '30-LoggingEnhanced.ps1'
    'debuglog'              = '30-LoggingEnhanced.ps1'
    'Disable-DebugLogging'  = '30-LoggingEnhanced.ps1'
    'nodebuglog'            = '30-LoggingEnhanced.ps1'
}

function Import-DeferredModule {
    <#
    .SYNOPSIS
        Loads a deferred module on first use.
    .PARAMETER ModuleName
        Name of the module file to load.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$ModuleName
    )

    if ($script:LoadedDeferredModules.ContainsKey($ModuleName)) {
        return $true
    }

    # Check if recently failed (avoid hammering)
    if ($script:FailedDeferredModules.ContainsKey($ModuleName)) {
        $lastFailed = $script:FailedDeferredModules[$ModuleName]
        if ((Get-Date) - $lastFailed -lt [Timespan]::FromMinutes(5)) {
            return $false
        }
    }

    $modulePath = Join-Path -Path $script:ProfileModulesPath -ChildPath $ModuleName

    if (-not (Test-Path -Path $modulePath)) {
        return $false
    }

    $timer = [System.Diagnostics.Stopwatch]::StartNew()

    try {
        . $modulePath
        $timer.Stop()

        $script:ProfileLoadTimes.Add([PSCustomObject]@{
            Module  = [System.IO.Path]::GetFileNameWithoutExtension($ModuleName)
            TimeMs  = [math]::Round($timer.Elapsed.TotalMilliseconds, 1)
            Status  = 'OK (lazy)'
        })

        $script:LoadedDeferredModules[$ModuleName] = $true

        # Remove from failed list if it was there
        if ($script:FailedDeferredModules.ContainsKey($ModuleName)) {
            $script:FailedDeferredModules.Remove($ModuleName)
        }

        # Show subtle loading indicator for slow loads (>100ms) but only in interactive sessions
        if ($timer.Elapsed.TotalMilliseconds -gt 100 -and $Host.UI.RawUI.KeyAvailable -eq $false) {
            Write-Host -NoNewline "." -ForegroundColor DarkGray
        }

        return $true
    }
    catch {
        $timer.Stop()
        $script:ProfileLoadTimes.Add([PSCustomObject]@{
            Module  = [System.IO.Path]::GetFileNameWithoutExtension($ModuleName)
            TimeMs  = [math]::Round($timer.Elapsed.TotalMilliseconds, 1)
            Status  = "FAIL: $($_.Exception.Message)"
        })

        $script:FailedDeferredModules[$ModuleName] = Get-Date

        Write-Warning -Message "Failed to lazy-load module '$ModuleName': $($_.Exception.Message)"
        return $false
    }
}

function New-DeferredFunctionStub {
    <#
    .SYNOPSIS
        Creates a stub function for lazy-loaded commands.
    .DESCRIPTION
        Factory function that properly captures variables in closure for deferred loading.
    .PARAMETER CommandName
        Name of the command to create stub for.
    .PARAMETER ModuleName
        Name of the module containing the actual implementation.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$CommandName,

        [Parameter(Mandatory)]
        [string]$ModuleName
    )

    # Create the function using New-Item on function: drive
    $functionPath = "function:global:$CommandName"

    $scriptBlock = {
        param()

        # Capture the module name from parent scope
        $targetModule = $ModuleName
        $targetCommand = $CommandName

        # Load the deferred module
        if (Import-DeferredModule -ModuleName $targetModule) {
            # Get the actual command implementation
            $actualCommand = Get-Command -Name $targetCommand -ErrorAction SilentlyContinue
            if ($actualCommand) {
                # Invoke with original arguments
                & $actualCommand @args
            } else {
                Write-Warning "Command '$targetCommand' not found in module '$targetModule' after loading"
            }
        } else {
            Write-Warning "Failed to load module '$targetModule' for command '$targetCommand'"
        }
    }.GetNewClosure()

    # Create the function
    $null = New-Item -Path $functionPath -Value $scriptBlock -Force
}

function Initialize-LazyLoading {
    <#
    .SYNOPSIS
        Sets up lazy loading hooks for deferred modules.
    #>
    [CmdletBinding()]
    param()

    # Create function stubs for deferred commands for immediate loading
    foreach ($command in $script:DeferredCommandMap.Keys) {
        if (-not (Get-Command -Name $command -ErrorAction SilentlyContinue)) {
            $moduleName = $script:DeferredCommandMap[$command]

            # Create stub function using factory (properly captures variables)
            New-DeferredFunctionStub -CommandName $command -ModuleName $moduleName
        }
    }

    # Unified CommandNotFound handler: auto-CD first, then deferred module loading
    $ExecutionContext.SessionState.InvokeCommand.CommandNotFoundAction = {
        param($commandName, $commandLookupEventArgs)

        # Auto-CD: check if the command name is a navigable directory path
        if ($Global:ProfileConfig.EnableAutoCD) {
            $fullPath = $null
            if (Test-Path -Path $commandName -PathType Container) {
                $fullPath = $commandName
            }
            elseif (Test-Path -Path (Join-Path -Path (Get-Location).Path -ChildPath $commandName) -PathType Container) {
                $fullPath = Join-Path -Path (Get-Location).Path -ChildPath $commandName
            }
            if ($fullPath) {
                $commandLookupEventArgs.StopSearch = $true
                $commandLookupEventArgs.CommandScriptBlock = {
                    Set-LocationTracked -Path $fullPath
                }.GetNewClosure()
                return
            }
        }

        # Deferred module loading: auto-load the module that owns this command
        if ($script:DeferredCommandMap.ContainsKey($commandName)) {
            $moduleName = $script:DeferredCommandMap[$commandName]
            $loaded = Import-DeferredModule -ModuleName $moduleName

            if ($loaded) {
                $command = Get-Command -Name $commandName -ErrorAction SilentlyContinue
                if ($command) {
                    $commandLookupEventArgs.Command = $command
                }
            }
        }
    }
}

#endregion

function Initialize-PredictiveLoading {
    <#
    .SYNOPSIS
        Performs predictive loading based on current directory context.
    .DESCRIPTION
        Analyzes the current directory for project indicators and preloads relevant modules.
    #>
    [CmdletBinding()]
    param()

    try {
        $location = Get-Location

        # Git repository detected
        if (Test-Path (Join-Path $location '.git')) {
            Import-DeferredModule '16-GitWorkflow.ps1' | Out-Null
        }

        # Docker files detected
        if ((Test-Path (Join-Path $location 'Dockerfile')) -or
            (Test-Path (Join-Path $location 'docker-compose.yml')) -or
            (Test-Path (Join-Path $location 'docker-compose.yaml'))) {
            Import-DeferredModule '21-DockerWorkflow.ps1' | Out-Null
        }

        # .NET project detected
        if ((Get-ChildItem -Path $location -Filter '*.csproj' -ErrorAction SilentlyContinue) -or
           (Get-ChildItem -Path $location -Filter '*.sln' -ErrorAction SilentlyContinue)) {
            Import-DeferredModule '22-DotnetToolbox.ps1' | Out-Null
        }

        # Node.js project detected
        if (Test-Path (Join-Path $location 'package.json')) {
            Import-DeferredModule '14-ExtendedTools.ps1' | Out-Null
        }

        # Python project detected
        if ((Test-Path (Join-Path $location 'requirements.txt')) -or
           (Test-Path (Join-Path $location 'setup.py')) -or
           (Test-Path (Join-Path $location 'pyproject.toml'))) {
            Import-DeferredModule '14-ExtendedTools.ps1' | Out-Null
        }
    }
    catch {
        # Silently fail to avoid breaking prompt
    }
}