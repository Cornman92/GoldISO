<#
.SYNOPSIS
    Environment Switcher module for C-Man's PowerShell Profile.
.DESCRIPTION
    Provides .env file loading per project, named environment profiles
    (dev/staging/prod), variable isolation with rollback, dotenv diff
    viewer, and auto-detection on directory change.
.NOTES
    Module: 17-EnvironmentSwitcher.ps1
    Requires: PowerShell 5.1+
#>

#region -- State --------------------------------------------------------------

$script:EnvStackDir = Join-Path -Path $script:ProfileRoot -ChildPath 'Cache'
$script:EnvStackFile = Join-Path -Path $script:EnvStackDir -ChildPath 'env-stack.json'
$script:ActiveEnvName = $null
$script:EnvSnapshot = @{}
$script:EnvHistory = [System.Collections.Generic.List[hashtable]]::new()

#endregion

#region -- Core Parser --------------------------------------------------------

<#
.SYNOPSIS
    Parses a .env file into a hashtable.
.DESCRIPTION
    Reads KEY=VALUE pairs from a .env file. Supports comments (#),
    quoted values (single and double), multiline values, variable
    expansion ($VAR and ${VAR}), and export prefix.
.PARAMETER Path
    Path to the .env file.
.PARAMETER ExpandVariables
    Expand $VAR references in values using current environment.
.EXAMPLE
    $vars = Read-EnvFile -Path '.env'
#>
function Read-EnvFile {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory, Position = 0)]
        [ValidateScript({ Test-Path -Path $_ })]
        [string]$Path,

        [Parameter()]
        [switch]$ExpandVariables
    )

    $result = @{}
    $lines = Get-Content -Path $Path -ErrorAction Stop

    foreach ($line in $lines) {
        # Skip comments and empty lines
        if ($line -match '^\s*(#|$)') { continue }

        # Strip optional 'export ' prefix
        $line = $line -replace '^\s*export\s+', ''

        if ($line -match '^\s*([A-Za-z_][A-Za-z0-9_]*)\s*=\s*(.*)$') {
            $key = $Matches[1]
            $val = $Matches[2].Trim()

            # Handle quoted values
            if ($val -match '^"(.*)"$') {
                $val = $Matches[1]
                # Process escape sequences in double-quoted strings
                $val = $val -replace '\\n', "`n"
                $val = $val -replace '\\t', "`t"
                $val = $val -replace '\\"', '"'
                $val = $val -replace '\\\\', '\'
            }
            elseif ($val -match "^'(.*)'$") {
                $val = $Matches[1]
                # Single-quoted: no escape processing
            }

            # Strip inline comments (unquoted)
            if ($val -match '^([^#]*?)\s+#') {
                $val = $Matches[1].TrimEnd()
            }

            # Variable expansion
            if ($ExpandVariables) {
                $val = [regex]::Replace($val, '\$\{?([A-Za-z_][A-Za-z0-9_]*)\}?', {
                    param($match)
                    $varName = $match.Groups[1].Value
                    if ($result.ContainsKey($varName)) {
                        return $result[$varName]
                    }
                    $envVal = [Environment]::GetEnvironmentVariable($varName)
                    if ($null -ne $envVal) { return $envVal }
                    return $match.Value
                })
            }

            $result[$key] = $val
        }
    }

    return $result
}

#endregion

#region -- Snapshot / Restore -------------------------------------------------

<#
.SYNOPSIS
    Takes a snapshot of the current environment variables.
.DESCRIPTION
    Captures all current environment variable values so they can be
    restored later. Used internally for rollback functionality.
#>
function Save-EnvSnapshot {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter()]
        [string[]]$Keys
    )

    $snapshot = @{}
    if ($Keys -and $Keys.Count -gt 0) {
        foreach ($key in $Keys) {
            $snapshot[$key] = [Environment]::GetEnvironmentVariable($key, 'Process')
        }
    }
    else {
        $envVars = [Environment]::GetEnvironmentVariables('Process')
        foreach ($key in $envVars.Keys) {
            $snapshot[$key] = $envVars[$key]
        }
    }
    return $snapshot
}

<#
.SYNOPSIS
    Restores environment variables from a snapshot.
.DESCRIPTION
    Resets environment variables to their values at snapshot time.
    Variables that did not exist in the snapshot are removed.
.PARAMETER Snapshot
    The snapshot hashtable to restore from.
.PARAMETER Keys
    Specific keys to restore. If omitted, restores all keys in snapshot.
#>
function Restore-EnvSnapshot {
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([void])]
    param(
        [Parameter(Mandatory)]
        [hashtable]$Snapshot,

        [Parameter()]
        [string[]]$Keys
    )

    $restoreKeys = if ($Keys -and $Keys.Count -gt 0) { $Keys } else { $Snapshot.Keys }

    foreach ($key in $restoreKeys) {
        if (-not $PSCmdlet.ShouldProcess($key, 'Restore environment variable')) {
            continue
        }

        if ($Snapshot.ContainsKey($key)) {
            $originalValue = $Snapshot[$key]
            if ($null -eq $originalValue) {
                [Environment]::SetEnvironmentVariable($key, $null, 'Process')
            }
            else {
                [Environment]::SetEnvironmentVariable($key, $originalValue, 'Process')
            }
        }
    }
}

#endregion

#region -- Environment Loading ------------------------------------------------

<#
.SYNOPSIS
    Loads a .env file into the current process environment.
.DESCRIPTION
    Parses a .env file and sets the variables in the current process.
    Creates a snapshot for rollback. Supports named profiles (dev,
    staging, prod) by looking for .env.{profile} files.
.PARAMETER Path
    Path to the .env file. If not specified, searches current directory.
.PARAMETER Profile
    Named profile to load (.env.dev, .env.staging, .env.prod, etc.).
.PARAMETER Override
    Override existing environment variables.
.PARAMETER Quiet
    Suppress output messages.
.EXAMPLE
    Import-EnvFile
.EXAMPLE
    Import-EnvFile -Profile 'staging' -Override
.EXAMPLE
    envload -Profile prod
#>
function Import-EnvFile {
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([void])]
    param(
        [Parameter(Position = 0)]
        [string]$Path,

        [Parameter()]
        [string]$ProfileName,

        [Parameter()]
        [switch]$Override,

        [Parameter()]
        [switch]$Quiet
    )

    # Determine file path
    if ([string]::IsNullOrEmpty($Path)) {
        if (-not [string]::IsNullOrEmpty($ProfileName)) {
            $Path = Join-Path -Path (Get-Location).Path -ChildPath ".env.$ProfileName"
        }
        else {
            $Path = Join-Path -Path (Get-Location).Path -ChildPath '.env'
        }
    }

    if (-not (Test-Path -Path $Path)) {
        if (-not $Quiet) {
            Write-Warning -Message "Environment file not found: $Path"
        }
        return
    }

    $fileName = Split-Path -Path $Path -Leaf
    if (-not $Quiet) {
        Write-Host "  Loading: $fileName" -ForegroundColor $Global:Theme.Info
    }

    # Parse the file
    $vars = Read-EnvFile -Path $Path -ExpandVariables

    if ($vars.Count -eq 0) {
        if (-not $Quiet) {
            Write-Host '  (no variables found)' -ForegroundColor $Global:Theme.Muted
        }
        return
    }

    # Snapshot current state for rollback
    $snapshot = Save-EnvSnapshot -Keys @($vars.Keys)

    # Apply variables
    $applied = 0
    $skipped = 0
    foreach ($key in $vars.Keys) {
        $currentValue = [Environment]::GetEnvironmentVariable($key, 'Process')
        $isExisting = $null -ne $currentValue

        if ($isExisting -and -not $Override) {
            $skipped++
            continue
        }

        if ($PSCmdlet.ShouldProcess($key, 'Set environment variable')) {
            [Environment]::SetEnvironmentVariable($key, $vars[$key], 'Process')
            $applied++
        }
    }

    # Push to history
    $historyEntry = @{
        Name      = if (-not [string]::IsNullOrEmpty($Profile)) { $Profile } else { $fileName }
        Path      = $Path
        Snapshot  = $snapshot
        Keys      = @($vars.Keys)
        Timestamp = [datetime]::UtcNow.ToString('o')
    }
    $script:EnvHistory.Add($historyEntry)
    $script:ActiveEnvName = $historyEntry.Name

    if (-not $Quiet) {
        Write-Host "  Applied: $applied variable(s)" -ForegroundColor $Global:Theme.Success
        if ($skipped -gt 0) {
            Write-Host "  Skipped: $skipped (already set, use -Override)" -ForegroundColor $Global:Theme.Muted
        }
    }
}

<#
.SYNOPSIS
    Unloads the last loaded .env file, restoring previous values.
.DESCRIPTION
    Pops the most recent environment from the stack and restores all
    variables to their pre-load values.
.PARAMETER All
    Unload all stacked environments.
.EXAMPLE
    Remove-EnvFile
.EXAMPLE
    envunload -All
#>
function Remove-EnvFile {
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([void])]
    param(
        [Parameter()]
        [switch]$All
    )

    if ($script:EnvHistory.Count -eq 0) {
        Write-Host '  No environments loaded to unload.' -ForegroundColor $Global:Theme.Muted
        return
    }

    if ($All) {
        # Unload in reverse order
        for ($i = $script:EnvHistory.Count - 1; $i -ge 0; $i--) {
            $entry = $script:EnvHistory[$i]
            if ($PSCmdlet.ShouldProcess($entry.Name, 'Unload environment')) {
                Restore-EnvSnapshot -Snapshot $entry.Snapshot -Keys $entry.Keys -Confirm:$false

                # Remove keys that were added (not in snapshot)
                foreach ($key in $entry.Keys) {
                    if (-not $entry.Snapshot.ContainsKey($key)) {
                        [Environment]::SetEnvironmentVariable($key, $null, 'Process')
                    }
                }

                Write-Host "  Unloaded: $($entry.Name)" -ForegroundColor $Global:Theme.Warning
            }
        }
        $script:EnvHistory.Clear()
        $script:ActiveEnvName = $null
    }
    else {
        $entry = $script:EnvHistory[$script:EnvHistory.Count - 1]
        if ($PSCmdlet.ShouldProcess($entry.Name, 'Unload environment')) {
            Restore-EnvSnapshot -Snapshot $entry.Snapshot -Keys $entry.Keys -Confirm:$false

            foreach ($key in $entry.Keys) {
                if (-not $entry.Snapshot.ContainsKey($key)) {
                    [Environment]::SetEnvironmentVariable($key, $null, 'Process')
                }
            }

            $script:EnvHistory.RemoveAt($script:EnvHistory.Count - 1)
            $script:ActiveEnvName = if ($script:EnvHistory.Count -gt 0) {
                $script:EnvHistory[$script:EnvHistory.Count - 1].Name
            }
            else { $null }

            Write-Host "  Unloaded: $($entry.Name)" -ForegroundColor $Global:Theme.Warning
        }
    }
}

#endregion

#region -- Environment Status & Diff ------------------------------------------

<#
.SYNOPSIS
    Shows the currently loaded environment stack.
.EXAMPLE
    Show-EnvStack
#>
function Show-EnvStack {
    [CmdletBinding()]
    [OutputType([void])]
    param()

    Write-Host "`n  Environment Stack" -ForegroundColor $Global:Theme.Primary
    Write-Host "  $('-' * 50)" -ForegroundColor $Global:Theme.Muted

    if ($script:EnvHistory.Count -eq 0) {
        Write-Host '  (no environments loaded)' -ForegroundColor $Global:Theme.Muted
        return
    }

    for ($i = $script:EnvHistory.Count - 1; $i -ge 0; $i--) {
        $entry = $script:EnvHistory[$i]
        $depth = $script:EnvHistory.Count - $i
        $isTop = ($i -eq $script:EnvHistory.Count - 1)
        $icon = if ($isTop) { '>' } else { ' ' }
        $color = if ($isTop) { $Global:Theme.Accent } else { $Global:Theme.Text }

        Write-Host "  $icon [$depth] " -ForegroundColor $Global:Theme.Muted -NoNewline
        Write-Host "$($entry.Name.PadRight(20))" -ForegroundColor $color -NoNewline
        Write-Host " $($entry.Keys.Count) var(s)" -ForegroundColor $Global:Theme.Muted -NoNewline

        $timestamp = [datetime]::Parse($entry.Timestamp).ToLocalTime().ToString('HH:mm:ss')
        Write-Host " @ $timestamp" -ForegroundColor $Global:Theme.Muted
    }
    Write-Host ''
}

<#
.SYNOPSIS
    Diffs two .env files side by side.
.DESCRIPTION
    Compares variables between two .env files, highlighting additions,
    removals, and value changes.
.PARAMETER Left
    Path to the first .env file.
.PARAMETER Right
    Path to the second .env file.
.PARAMETER ShowValues
    Display actual values (may contain secrets).
.EXAMPLE
    Compare-EnvFiles -Left '.env.dev' -Right '.env.prod'
#>
function Compare-EnvFiles {
    [CmdletBinding()]
    [OutputType([void])]
    param(
        [Parameter(Mandatory, Position = 0)]
        [ValidateScript({ Test-Path -Path $_ })]
        [string]$Left,

        [Parameter(Mandatory, Position = 1)]
        [ValidateScript({ Test-Path -Path $_ })]
        [string]$Right,

        [Parameter()]
        [switch]$ShowValues
    )

    $leftVars = Read-EnvFile -Path $Left
    $rightVars = Read-EnvFile -Path $Right
    $leftName = Split-Path -Path $Left -Leaf
    $rightName = Split-Path -Path $Right -Leaf

    Write-Host "`n  Env Diff: $leftName ? $rightName" -ForegroundColor $Global:Theme.Primary
    Write-Host "  $('-' * 60)" -ForegroundColor $Global:Theme.Muted

    $allKeys = @($leftVars.Keys + $rightVars.Keys | Sort-Object -Unique)
    $added = 0; $removed = 0; $changed = 0; $same = 0

    foreach ($key in $allKeys) {
        $inLeft = $leftVars.ContainsKey($key)
        $inRight = $rightVars.ContainsKey($key)

        if ($inLeft -and -not $inRight) {
            Write-Host "  - $key" -ForegroundColor $Global:Theme.Error
            if ($ShowValues) { Write-Host "    L: $($leftVars[$key])" -ForegroundColor $Global:Theme.Muted }
            $removed++
        }
        elseif (-not $inLeft -and $inRight) {
            Write-Host "  + $key" -ForegroundColor $Global:Theme.Success
            if ($ShowValues) { Write-Host "    R: $($rightVars[$key])" -ForegroundColor $Global:Theme.Muted }
            $added++
        }
        elseif ($leftVars[$key] -ne $rightVars[$key]) {
            Write-Host "  ~ $key" -ForegroundColor $Global:Theme.Warning
            if ($ShowValues) {
                Write-Host "    L: $($leftVars[$key])" -ForegroundColor $Global:Theme.Error
                Write-Host "    R: $($rightVars[$key])" -ForegroundColor $Global:Theme.Success
            }
            $changed++
        }
        else {
            $same++
        }
    }

    Write-Host "`n  Summary: +$added -$removed ~$changed =$same" -ForegroundColor $Global:Theme.Muted
    Write-Host ''
}

<#
.SYNOPSIS
    Lists available .env files in the current directory.
.EXAMPLE
    Show-EnvFiles
#>
function Show-EnvFiles {
    [CmdletBinding()]
    [OutputType([void])]
    param()

    $envFiles = Get-ChildItem -Path (Get-Location).Path -Filter '.env*' -File -Force -ErrorAction SilentlyContinue

    Write-Host "`n  Available .env files" -ForegroundColor $Global:Theme.Primary
    Write-Host "  $('-' * 50)" -ForegroundColor $Global:Theme.Muted

    if ($envFiles.Count -eq 0) {
        Write-Host '  (none found)' -ForegroundColor $Global:Theme.Muted
        return
    }

    foreach ($file in $envFiles | Sort-Object -Property Name) {
        $vars = Read-EnvFile -Path $file.FullName
        $isActive = $script:ActiveEnvName -eq $file.Name
        $icon = if ($isActive) { '>' } else { ' ' }
        $color = if ($isActive) { $Global:Theme.Accent } else { $Global:Theme.Text }

        Write-Host "  $icon $($file.Name.PadRight(25))" -ForegroundColor $color -NoNewline
        Write-Host " $($vars.Count) var(s)" -ForegroundColor $Global:Theme.Muted -NoNewline
        Write-Host " ($($file.Length) bytes)" -ForegroundColor $Global:Theme.Muted
    }
    Write-Host ''
}

#endregion

#region -- Auto-Detect --------------------------------------------------------

<#
.SYNOPSIS
    Checks for and optionally auto-loads .env files on directory change.
.DESCRIPTION
    Called by directory-change hooks to detect .env files in new
    directories. Respects a .env-auto marker file for automatic loading.
#>
function Invoke-EnvAutoDetect {
    [CmdletBinding()]
    [OutputType([void])]
    param(
        [Parameter()]
        [string]$Directory = (Get-Location).Path
    )

    $autoMarker = Join-Path -Path $Directory -ChildPath '.env-auto'
    $envFile = Join-Path -Path $Directory -ChildPath '.env'

    if ((Test-Path -Path $autoMarker) -and (Test-Path -Path $envFile)) {
        # Check if already loaded for this directory
        $alreadyLoaded = $script:EnvHistory | Where-Object -FilterScript {
            $_.Path -eq $envFile
        }

        if ($null -eq $alreadyLoaded) {
            Write-Host "  Auto-loading .env from $Directory" -ForegroundColor $Global:Theme.Info
            Import-EnvFile -Path $envFile -Override -Quiet
        }
    }
}

<#
.SYNOPSIS
    Creates a .env-auto marker to enable auto-loading.
.DESCRIPTION
    Creates the .env-auto file that signals the profile to automatically
    load the .env file when navigating to this directory.
.EXAMPLE
    Enable-EnvAutoLoad
#>
function Enable-EnvAutoLoad {
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([void])]
    param(
        [Parameter()]
        [string]$Directory = (Get-Location).Path
    )

    $markerPath = Join-Path -Path $Directory -ChildPath '.env-auto'

    if (-not $PSCmdlet.ShouldProcess($markerPath, 'Create auto-load marker')) {
        return
    }

    Set-Content -Path $markerPath -Value "# Auto-load .env on cd`n# Created: $(Get-Date -Format 'o')"
    Write-Host "  Auto-load enabled for: $Directory" -ForegroundColor $Global:Theme.Success
}

<#
.SYNOPSIS
    Removes the .env-auto marker.
.EXAMPLE
    Disable-EnvAutoLoad
#>
function Disable-EnvAutoLoad {
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([void])]
    param(
        [Parameter()]
        [string]$Directory = (Get-Location).Path
    )

    $markerPath = Join-Path -Path $Directory -ChildPath '.env-auto'

    if (Test-Path -Path $markerPath) {
        if ($PSCmdlet.ShouldProcess($markerPath, 'Remove auto-load marker')) {
            Remove-Item -Path $markerPath -Force
            Write-Host "  Auto-load disabled for: $Directory" -ForegroundColor $Global:Theme.Warning
        }
    }
    else {
        Write-Host '  Auto-load was not enabled here.' -ForegroundColor $Global:Theme.Muted
    }
}

#endregion

#region -- Template Generation ------------------------------------------------

<#
.SYNOPSIS
    Creates a .env.example file from the current .env.
.DESCRIPTION
    Generates a template with all keys but placeholder values,
    suitable for committing to version control.
.PARAMETER SourcePath
    Path to the source .env file.
.PARAMETER OutputPath
    Path for the generated template.
.EXAMPLE
    New-EnvTemplate
#>
function New-EnvTemplate {
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([void])]
    param(
        [Parameter()]
        [string]$SourcePath = (Join-Path -Path (Get-Location).Path -ChildPath '.env'),

        [Parameter()]
        [string]$OutputPath = (Join-Path -Path (Get-Location).Path -ChildPath '.env.example')
    )

    if (-not (Test-Path -Path $SourcePath)) {
        Write-Warning -Message "Source file not found: $SourcePath"
        return
    }

    if (-not $PSCmdlet.ShouldProcess($OutputPath, 'Generate .env.example')) {
        return
    }

    $vars = Read-EnvFile -Path $SourcePath
    $lines = @("# Environment variables template", "# Generated: $(Get-Date -Format 'yyyy-MM-dd')", "")

    foreach ($key in ($vars.Keys | Sort-Object)) {
        $placeholder = switch -Regex ($key) {
            'KEY|TOKEN|SECRET|PASSWORD|PASS' { 'your-secret-here' }
            'URL|URI|ENDPOINT'               { 'https://example.com' }
            'HOST'                           { 'localhost' }
            'PORT'                           { '3000' }
            'DATABASE|DB'                    { 'mydb' }
            'USER|USERNAME'                  { 'myuser' }
            'EMAIL'                          { 'user@example.com' }
            default                          { 'value' }
        }
        $lines += "$key=$placeholder"
    }

    $lines | Set-Content -Path $OutputPath
    Write-Host "  Generated: $OutputPath ($($vars.Count) keys)" -ForegroundColor $Global:Theme.Success
}

#endregion

#region -- Aliases -------------------------------------------------------------

Set-Alias -Name 'envload'    -Value 'Import-EnvFile'       -Scope Global -Force
Set-Alias -Name 'envunload'  -Value 'Remove-EnvFile'       -Scope Global -Force
Set-Alias -Name 'envstack'   -Value 'Show-EnvStack'        -Scope Global -Force
Set-Alias -Name 'envdiff'    -Value 'Compare-EnvFiles'     -Scope Global -Force
Set-Alias -Name 'envls'      -Value 'Show-EnvFiles'        -Scope Global -Force
Set-Alias -Name 'envauto'    -Value 'Enable-EnvAutoLoad'   -Scope Global -Force
Set-Alias -Name 'envtemplate' -Value 'New-EnvTemplate'     -Scope Global -Force

#endregion

#region -- Tab Completion -----------------------------------------------------

Register-ArgumentCompleter -CommandName 'Import-EnvFile' -ParameterName 'ProfileName' -ScriptBlock {
    param($commandName, $parameterName, $wordToComplete, $commandAst, $fakeBoundParameters)

    $envFiles = Get-ChildItem -Path (Get-Location).Path -Filter '.env.*' -File -Force -ErrorAction SilentlyContinue
    $envFiles | ForEach-Object -Process {
        $profileName = $_.Name -replace '^\.env\.', ''
        if ($profileName -like "${wordToComplete}*") {
            [System.Management.Automation.CompletionResult]::new($profileName, $profileName, 'ParameterValue', $profileName)
        }
    }
}

#endregion
