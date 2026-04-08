#Requires -Version 5.1
<#
.SYNOPSIS
    C-Man's Ultimate PowerShell Profile - Main Loader
.DESCRIPTION
    Modular, lazy-loading PowerShell profile with Matrix-themed UI,
    comprehensive dev tooling, sysadmin utilities, and performance optimizations.
    Compatible with PowerShell 5.1 and 7+.
.NOTES
    Structure: ~/PowerShell/Profile.d/*.ps1 (loaded in sort order)
    Config:    ~/PowerShell/Config/profile-config.json
    Logs:      ~/PowerShell/Logs/{sessions,errors}/
    Themes:    ~/PowerShell/Themes/*.json
#>
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingWriteHost', '', Justification = 'Interactive profile requires Write-Host for colored UI output')]
param()

#region â”€â”€ Profile Bootstrap â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

# Global profile stopwatch for load-time benchmarking
$script:ProfileLoadTimer = [System.Diagnostics.Stopwatch]::StartNew()
$script:ProfileLoadTimes = [System.Collections.Generic.List[PSCustomObject]]::new()

# Establish profile root (use actual file location, not $PROFILE)
$script:ProfileRoot = Split-Path -Path $PSCommandPath -Parent

# Ensure directory structure exists
$script:ProfileDirectories = @(
    (Join-Path -Path $script:ProfileRoot -ChildPath 'PSProfile.C-Man')
    (Join-Path -Path $script:ProfileRoot -ChildPath 'Config')
    (Join-Path -Path $script:ProfileRoot -ChildPath 'Themes')
    (Join-Path -Path $script:ProfileRoot -ChildPath 'Logs' | Join-Path -ChildPath 'sessions')
    (Join-Path -Path $script:ProfileRoot -ChildPath 'Logs' | Join-Path -ChildPath 'errors')
    (Join-Path -Path $script:ProfileRoot -ChildPath 'Cache')
    (Join-Path -Path $script:ProfileRoot -ChildPath 'Tools')
)

foreach ($directory in $script:ProfileDirectories) {
    if (-not (Test-Path -Path $directory)) {
        $null = New-Item -Path $directory -ItemType Directory -Force
    }
}

#endregion

#region â”€â”€ Configuration Loading â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

$script:ConfigPath = Join-Path -Path $script:ProfileRoot -ChildPath 'Config' |
    Join-Path -ChildPath 'profile-config.json'

# Global config object
$Global:ProfileConfig = $null

if (Test-Path -Path $script:ConfigPath) {
    try {
        $Global:ProfileConfig = Get-Content -Path $script:ConfigPath -Raw | ConvertFrom-Json
    }
    catch {
        Write-Warning -Message "Profile config corrupted, loading defaults: $_"
    }
}

# Apply defaults for any missing keys
$script:DefaultConfig = @{
    Theme                  = 'Matrix'
    BannerMode             = 'Compact'
    EnableLazyLoading      = $true
    EnableSessionLogging   = $true
    EnableErrorLogging     = $true
    EnableAutoCD           = $true
    EnableZoxideIntegration = $true
    EnableDirectoryBookmarks = $true
    EnableGitPrompt          = $true
    EnablePredictiveIntelliSense = $true
    HistoryMaxCount        = 10000
    HistoryDeduplicate     = $true
    HistoryFilterSensitive = $true
    SlowCommandThresholdMs = 3000
    LogRetentionDays       = 30
    PromptStyle            = 'Custom'
    EnableToolAutoInstall   = $true
    PreferredPackageManager = 'scoop'
    FallbackPackageManager  = 'winget'
    EnableToolAutoUpdate    = $true
    DevToolAliases         = $true
    SysAdminTools          = $true
    Better11Integration    = $true
    NerdFontEnabled        = $true
    MaxModuleLoadTimeMs    = 500
}

if ($null -eq $Global:ProfileConfig) {
    $Global:ProfileConfig = [PSCustomObject]$script:DefaultConfig
    $script:DefaultConfig | ConvertTo-Json -Depth 5 |
        Set-Content -Path $script:ConfigPath -Encoding UTF8
}
else {
    # Merge missing defaults into existing config
    $configHash = @{}
    $Global:ProfileConfig.PSObject.Properties | ForEach-Object -Process {
        $configHash[$_.Name] = $_.Value
    }
    foreach ($key in $script:DefaultConfig.Keys) {
        if (-not $configHash.ContainsKey($key)) {
            $configHash[$key] = $script:DefaultConfig[$key]
        }
    }
    $Global:ProfileConfig = [PSCustomObject]$configHash
}

#endregion

#region â”€â”€ Module Loader Engine â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

function Import-ProfileModule {
    <#
    .SYNOPSIS
        Loads a profile module with timing and error handling.
    .PARAMETER Path
        Full path to the .ps1 module file.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateScript({ Test-Path -Path $_ -PathType Leaf })]
        [string]$Path
    )

    $moduleName = [System.IO.Path]::GetFileNameWithoutExtension($Path)
    $timer = [System.Diagnostics.Stopwatch]::StartNew()

    try {
        . $Path
        $timer.Stop()
        $script:ProfileLoadTimes.Add([PSCustomObject]@{
            Module  = $moduleName
            TimeMs  = [math]::Round($timer.Elapsed.TotalMilliseconds, 1)
            Status  = 'OK'
        })
    }
    catch {
        $timer.Stop()
        $script:ProfileLoadTimes.Add([PSCustomObject]@{
            Module  = $moduleName
            TimeMs  = [math]::Round($timer.Elapsed.TotalMilliseconds, 1)
            Status  = "FAIL: $($_.Exception.Message)"
        })

        # Log error with stack trace
        if ($script:ProfileConfig.EnableErrorLogging) {
            $errorLogDir = Join-Path -Path $script:ProfileRoot -ChildPath 'Logs' |
                Join-Path -ChildPath 'errors'
            $errorLogFile = Join-Path -Path $errorLogDir -ChildPath "error_$(Get-Date -Format 'yyyy-MM-dd').log"
            $errorEntry = @"
[$( Get-Date -Format 'yyyy-MM-dd HH:mm:ss.fff' )] MODULE LOAD ERROR: $moduleName
Message: $($_.Exception.Message)
ScriptStackTrace:
$($_.ScriptStackTrace)
---
"@
            Add-Content -Path $errorLogFile -Value $errorEntry -Encoding UTF8
        }

        Write-Warning -Message "Failed to load profile module '$moduleName': $($_.Exception.Message)"
    }
}

# Load immediate modules
$script:ProfileModulesPath = Join-Path -Path $script:ProfileRoot -ChildPath 'PSProfile.C-Man'

if (Test-Path -Path $script:ProfileModulesPath) {
    # Load lazy loader first
    $lazyLoaderPath = Join-Path -Path $script:ProfileModulesPath -ChildPath '00-LazyLoader.ps1'
    if (Test-Path -Path $lazyLoaderPath) {
        Import-ProfileModule -Path $lazyLoaderPath
    }

    # Load only immediate modules
    foreach ($moduleName in $script:ImmediateModules) {
        $modulePath = Join-Path -Path $script:ProfileModulesPath -ChildPath $moduleName
        if (Test-Path -Path $modulePath) {
            Import-ProfileModule -Path $modulePath
        }
    }

    # Initialize lazy loading hooks
    if (Get-Command -Name 'Initialize-LazyLoading' -ErrorAction SilentlyContinue) {
        Initialize-LazyLoading
    }
}

#endregion

#region â”€â”€ Profile Load Complete â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

$script:ProfileLoadTimer.Stop()

# Store total load time for banner display
$Global:ProfileLoadTimeMs = [math]::Round($script:ProfileLoadTimer.Elapsed.TotalMilliseconds, 0)

# Show banner if function was loaded
if (Get-Command -Name 'Show-ProfileBanner' -ErrorAction SilentlyContinue) {
    Show-ProfileBanner
}
else {
    Write-Host -Object "Profile loaded in ${Global:ProfileLoadTimeMs}ms" -ForegroundColor Green
    Write-Host -Object "Aliases: ws, cln, scripts, dev, gs, ga, gc, OC" -ForegroundColor DarkGray
    Write-Host -Object "Use 'Show-Help' to display help" -ForegroundColor Yellow
}

# Start session logging if enabled
if ($Global:ProfileConfig.EnableSessionLogging) {
    if (Get-Command -Name 'Start-ProfileSessionLog' -ErrorAction SilentlyContinue) {
        Start-ProfileSessionLog
    }
}

#endregion

