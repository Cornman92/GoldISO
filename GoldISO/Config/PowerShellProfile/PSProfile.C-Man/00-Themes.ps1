[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingWriteHost', '', Justification = 'Theme preview requires colored console output')]
param()

#region -- Theme System -------------------------------------------------------

<#
.SYNOPSIS
    Color theme engine supporting Matrix (default), Cyberpunk, Dracula, Monochrome.
    Themes are stored as JSON and applied globally via $Global:Theme.
#>

# Theme definitions
$script:ThemeDefinitions = @{
    Matrix = @{
        Name        = 'Matrix'
        Primary     = 'Green'
        Secondary   = 'DarkGreen'
        Accent      = 'Cyan'
        Warning     = 'Yellow'
        Error       = 'Red'
        Muted       = 'DarkGray'
        Background  = 'Black'
        Text        = 'Green'
        Prompt      = 'Green'
        Path        = 'DarkGreen'
        GitClean    = 'Green'
        GitDirty    = 'Yellow'
        GitBranch   = 'Cyan'
        Banner      = 'Green'
        BannerAlt   = 'DarkGreen'
        Separator   = 'DarkGray'
        Success     = 'Green'
        Info        = 'Cyan'
        Timestamp   = 'DarkGray'
    }
    Cyberpunk = @{
        Name        = 'Cyberpunk'
        Primary     = 'Magenta'
        Secondary   = 'DarkMagenta'
        Accent      = 'Cyan'
        Warning     = 'Yellow'
        Error       = 'Red'
        Muted       = 'DarkGray'
        Background  = 'Black'
        Text        = 'White'
        Prompt      = 'Magenta'
        Path        = 'Cyan'
        GitClean    = 'Green'
        GitDirty    = 'Yellow'
        GitBranch   = 'Magenta'
        Banner      = 'Magenta'
        BannerAlt   = 'Cyan'
        Separator   = 'DarkMagenta'
        Success     = 'Cyan'
        Info        = 'Magenta'
        Timestamp   = 'DarkGray'
    }
    Dracula = @{
        Name        = 'Dracula'
        Primary     = 'Magenta'
        Secondary   = 'DarkCyan'
        Accent      = 'Cyan'
        Warning     = 'Yellow'
        Error       = 'Red'
        Muted       = 'DarkGray'
        Background  = 'Black'
        Text        = 'White'
        Prompt      = 'Cyan'
        Path        = 'Magenta'
        GitClean    = 'Green'
        GitDirty    = 'Yellow'
        GitBranch   = 'Cyan'
        Banner      = 'Magenta'
        BannerAlt   = 'DarkCyan'
        Separator   = 'DarkGray'
        Success     = 'Green'
        Info        = 'Cyan'
        Timestamp   = 'DarkGray'
    }
    Monochrome = @{
        Name        = 'Monochrome'
        Primary     = 'White'
        Secondary   = 'Gray'
        Accent      = 'White'
        Warning     = 'Yellow'
        Error       = 'Red'
        Muted       = 'DarkGray'
        Background  = 'Black'
        Text        = 'Gray'
        Prompt      = 'White'
        Path        = 'Gray'
        GitClean    = 'White'
        GitDirty    = 'Gray'
        GitBranch   = 'White'
        Banner      = 'White'
        BannerAlt   = 'Gray'
        Separator   = 'DarkGray'
        Success     = 'White'
        Info        = 'Gray'
        Timestamp   = 'DarkGray'
    }
}

function Set-ProfileTheme {
    <#
    .SYNOPSIS
        Switches the active color theme.
    .PARAMETER Name
        Theme name: Matrix, Cyberpunk, Dracula, Monochrome.
    .PARAMETER Save
        Persist the selection to profile config.
    .EXAMPLE
        Set-ProfileTheme -Name Cyberpunk -Save
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateSet('Matrix', 'Cyberpunk', 'Dracula', 'Monochrome')]
        [string]$Name,

        [switch]$Save
    )

    if ($script:ThemeDefinitions.ContainsKey($Name)) {
        $Global:Theme = [PSCustomObject]$script:ThemeDefinitions[$Name]
        $Global:ProfileConfig.Theme = $Name
        Write-Host -Object "Theme switched to $Name" -ForegroundColor $Global:Theme.Primary

        if ($Save) {
            $configPath = Join-Path -Path $script:ProfileRoot -ChildPath 'Config' |
                Join-Path -ChildPath 'profile-config.json'
            $Global:ProfileConfig | ConvertTo-Json -Depth 5 |
                Set-Content -Path $configPath -Encoding UTF8
            Write-Host -Object 'Theme saved to config.' -ForegroundColor $Global:Theme.Muted
        }
    }
}

function Get-ProfileTheme {
    <#
    .SYNOPSIS
        Returns the current theme or lists all available themes.
    .PARAMETER ListAll
        Show all available themes with color previews.
    #>
    [CmdletBinding()]
    param(
        [switch]$ListAll
    )

    if ($ListAll) {
        foreach ($themeName in ($script:ThemeDefinitions.Keys | Sort-Object)) {
            $theme = $script:ThemeDefinitions[$themeName]
            $marker = if ($themeName -eq $Global:ProfileConfig.Theme) { ' [ACTIVE]' } else { '' }
            Write-Host -Object "  $themeName$marker" -ForegroundColor $theme['Primary'] -NoNewline
            Write-Host -Object " | " -ForegroundColor DarkGray -NoNewline
            Write-Host -Object "Primary " -ForegroundColor $theme['Primary'] -NoNewline
            Write-Host -Object "Accent " -ForegroundColor $theme['Accent'] -NoNewline
            Write-Host -Object "Muted" -ForegroundColor $theme['Muted']
        }
    }
    else {
        return $Global:Theme
    }
}

# Apply current theme from config
$themeName = $Global:ProfileConfig.Theme
if ($script:ThemeDefinitions.ContainsKey($themeName)) {
    $Global:Theme = [PSCustomObject]$script:ThemeDefinitions[$themeName]
}
else {
    $Global:Theme = [PSCustomObject]$script:ThemeDefinitions['Matrix']
}

#endregion
