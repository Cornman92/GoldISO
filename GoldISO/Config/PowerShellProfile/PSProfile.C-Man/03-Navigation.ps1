[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingWriteHost', '', Justification = 'Navigation feedback requires colored output')]
param()

#region -- Directory Navigation System ----------------------------------------

<#
.SYNOPSIS
    Comprehensive navigation: auto-cd, Zoxide frecency, bookmarks, enhanced directory stack.
#>

# Directory stack for back/forward navigation
$Global:DirectoryHistory = [System.Collections.Generic.List[string]]::new()
$Global:DirectoryHistoryIndex = -1

function Set-LocationTracked {
    <#
    .SYNOPSIS
        Changes directory while maintaining navigation history stack.
    .PARAMETER Path
        Target directory path.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, Position = 0)]
        [string]$Path
    )

    $resolvedPath = $null
    try {
        $resolvedPath = Resolve-Path -Path $Path -ErrorAction Stop | Select-Object -ExpandProperty Path
    }
    catch {
        Write-Warning -Message "Path not found: $Path"
        return
    }

    $currentLocation = Get-Location | Select-Object -ExpandProperty Path

    if ($resolvedPath -ne $currentLocation) {
        # Trim forward history when navigating to new location
        if ($Global:DirectoryHistoryIndex -lt ($Global:DirectoryHistory.Count - 1)) {
            $removeCount = $Global:DirectoryHistory.Count - 1 - $Global:DirectoryHistoryIndex
            for ($i = 0; $i -lt $removeCount; $i++) {
                $Global:DirectoryHistory.RemoveAt($Global:DirectoryHistory.Count - 1)
            }
        }

        $Global:DirectoryHistory.Add($currentLocation)
        $Global:DirectoryHistoryIndex = $Global:DirectoryHistory.Count - 1

        Set-Location -Path $resolvedPath
    }
}

function Enter-PreviousDirectory {
    <#
    .SYNOPSIS
        Navigate back in directory history (like browser back button).
    #>
    [CmdletBinding()]
    [Alias('bd')]
    param()

    if ($Global:DirectoryHistoryIndex -gt 0) {
        $Global:DirectoryHistoryIndex--
        $targetPath = $Global:DirectoryHistory[$Global:DirectoryHistoryIndex]
        Set-Location -Path $targetPath
    }
    else {
        Write-Host -Object 'No previous directory in history.' -ForegroundColor $Global:Theme.Muted
    }
}

function Enter-NextDirectory {
    <#
    .SYNOPSIS
        Navigate forward in directory history.
    #>
    [CmdletBinding()]
    [Alias('fd')]
    param()

    if ($Global:DirectoryHistoryIndex -lt ($Global:DirectoryHistory.Count - 1)) {
        $Global:DirectoryHistoryIndex++
        $targetPath = $Global:DirectoryHistory[$Global:DirectoryHistoryIndex]
        Set-Location -Path $targetPath
    }
    else {
        Write-Host -Object 'No forward directory in history.' -ForegroundColor $Global:Theme.Muted
    }
}

function Show-DirectoryHistory {
    <#
    .SYNOPSIS
        Display the directory navigation history stack.
    #>
    [CmdletBinding()]
    [Alias('dh')]
    param()

    $tc = $Global:Theme
    Write-Host -Object '  Directory History:' -ForegroundColor $tc.Primary
    for ($i = 0; $i -lt $Global:DirectoryHistory.Count; $i++) {
        $marker = if ($i -eq $Global:DirectoryHistoryIndex) { ' >' } else { '  ' }
        $color = if ($i -eq $Global:DirectoryHistoryIndex) { $tc.Accent } else { $tc.Muted }
        Write-Host -Object "  $marker [$i] $($Global:DirectoryHistory[$i])" -ForegroundColor $color
    }
}

#endregion

# Auto-CD is handled in 00-LazyLoader.ps1 unified CommandNotFoundAction

#region -- Zoxide Integration -------------------------------------------------

if ($Global:ProfileConfig.EnableZoxideIntegration) {
    $script:ZoxideAvailable = $null -ne (Get-Command -Name 'zoxide' -ErrorAction SilentlyContinue)

    if ($script:ZoxideAvailable) {
        Invoke-Expression -Command (& zoxide init powershell | Out-String)
    }
    else {
        # Lightweight frecency fallback when Zoxide isn't installed
        $script:FrecencyDbPath = Join-Path -Path $script:ProfileRoot -ChildPath 'Cache' |
            Join-Path -ChildPath 'frecency-db.json'

        $script:FrecencyDb = @{}
        if (Test-Path -Path $script:FrecencyDbPath) {
            try {
                $script:FrecencyDb = Get-Content -Path $script:FrecencyDbPath -Raw |
                    ConvertFrom-Json -AsHashtable -ErrorAction SilentlyContinue
                if ($null -eq $script:FrecencyDb) {
                    $script:FrecencyDb = @{}
                }
            }
            catch {
                $script:FrecencyDb = @{}
            }
        }

        function Invoke-ZLike {
            <#
            .SYNOPSIS
                Zoxide-like frecency directory jump. Finds best match from history.
            .PARAMETER Query
                Partial directory name to match against.
            #>
            [CmdletBinding()]
            [Alias('z')]
            param(
                [Parameter(Position = 0)]
                [string]$Query
            )

            if ([string]::IsNullOrWhiteSpace($Query)) {
                Set-LocationTracked -Path $env:USERPROFILE
                return
            }

            # Find best match by score
            $bestMatch = $null
            $bestScore = 0

            foreach ($entry in $script:FrecencyDb.GetEnumerator()) {
                $path = $entry.Key
                if ($path -match [regex]::Escape($Query) -and (Test-Path -Path $path -PathType Container)) {
                    $score = $entry.Value
                    if ($score -gt $bestScore) {
                        $bestScore = $score
                        $bestMatch = $path
                    }
                }
            }

            if ($bestMatch) {
                Set-LocationTracked -Path $bestMatch
                Write-Host -Object "  -> $bestMatch" -ForegroundColor $Global:Theme.Muted
            }
            else {
                Write-Warning -Message "No frecency match for: $Query"
            }
        }

        function Update-FrecencyDb {
            <#
            .SYNOPSIS
                Records current directory visit for frecency scoring.
            #>
            [CmdletBinding()]
            param()

            $currentPath = (Get-Location).Path
            if ($script:FrecencyDb.ContainsKey($currentPath)) {
                $script:FrecencyDb[$currentPath] += 1
            }
            else {
                $script:FrecencyDb[$currentPath] = 1
            }

            # Persist every 10 visits
            $totalVisits = ($script:FrecencyDb.Values | Measure-Object -Sum).Sum
            if ($totalVisits % 10 -eq 0) {
                $script:FrecencyDb | ConvertTo-Json -Depth 3 |
                    Set-Content -Path $script:FrecencyDbPath -Encoding UTF8
            }
        }

        # Hook into prompt to record visits
        $Global:FrecencyEnabled = $true
    }
}

#endregion

#region -- Directory Bookmarks ------------------------------------------------

if ($Global:ProfileConfig.EnableDirectoryBookmarks) {
    $script:BookmarkStore = @{}
    $script:BookmarkCachePath = Join-Path -Path $script:ProfileRoot -ChildPath 'Cache' |
        Join-Path -ChildPath 'bookmarks.json'

    # Load from config
    if ($Global:ProfileConfig.DirectoryBookmarks) {
        $Global:ProfileConfig.DirectoryBookmarks.PSObject.Properties | ForEach-Object -Process {
            $expandedPath = $ExecutionContext.InvokeCommand.ExpandString($_.Value)
            $script:BookmarkStore[$_.Name] = $expandedPath
        }
    }

    # Load user-added bookmarks from cache
    if (Test-Path -Path $script:BookmarkCachePath) {
        try {
            $cached = Get-Content -Path $script:BookmarkCachePath -Raw | ConvertFrom-Json
            $cached.PSObject.Properties | ForEach-Object -Process {
                if (-not $script:BookmarkStore.ContainsKey($_.Name)) {
                    $script:BookmarkStore[$_.Name] = $_.Value
                }
            }
        }
        catch {
            # Silently continue if cache is corrupted
        }
    }

    function Set-DirectoryBookmark {
        <#
        .SYNOPSIS
            Creates or updates a directory bookmark.
        .PARAMETER Name
            Short alias for the bookmark.
        .PARAMETER Path
            Directory path. Defaults to current directory.
        .EXAMPLE
            Set-DirectoryBookmark -Name proj -Path C:\Projects\MyApp
        .EXAMPLE
            Set-DirectoryBookmark -Name here
        #>
        [CmdletBinding()]
        [Alias('bm')]
        param(
            [Parameter(Mandatory, Position = 0)]
            [string]$Name,

            [Parameter(Position = 1)]
            [string]$Path = (Get-Location).Path
        )

        $script:BookmarkStore[$Name] = $Path
        $script:BookmarkStore | ConvertTo-Json -Depth 3 |
            Set-Content -Path $script:BookmarkCachePath -Encoding UTF8

        Write-Host -Object "  Bookmark '$Name' -> $Path" -ForegroundColor $Global:Theme.Success
    }

    function Enter-Bookmark {
        <#
        .SYNOPSIS
            Jump to a bookmarked directory.
        .PARAMETER Name
            Bookmark alias to jump to.
        .EXAMPLE
            Enter-Bookmark dev
        #>
        [CmdletBinding()]
        [Alias('go')]
        param(
            [Parameter(Mandatory, Position = 0)]
            [string]$Name
        )

        if ($script:BookmarkStore.ContainsKey($Name)) {
            $target = $script:BookmarkStore[$Name]
            if (Test-Path -Path $target -PathType Container) {
                Set-LocationTracked -Path $target
            }
            else {
                Write-Warning -Message "Bookmark path does not exist: $target"
            }
        }
        else {
            Write-Warning -Message "Unknown bookmark: $Name. Use Show-DirectoryBookmarks to list."
        }
    }

    function Show-DirectoryBookmarks {
        <#
        .SYNOPSIS
            Lists all directory bookmarks.
        #>
        [CmdletBinding()]
        [Alias('bms')]
        param()

        $tc = $Global:Theme
        Write-Host -Object '  Directory Bookmarks:' -ForegroundColor $tc.Primary
        foreach ($entry in ($script:BookmarkStore.GetEnumerator() | Sort-Object -Property Key)) {
            $exists = Test-Path -Path $entry.Value -PathType Container
            $statusIcon = if ($exists) { [char]0x2713 } else { [char]0x2717 }
            $statusColor = if ($exists) { $tc.Success } else { $tc.Error }
            Write-Host -Object "  $statusIcon " -ForegroundColor $statusColor -NoNewline
            Write-Host -Object "$($entry.Key.PadRight(10))" -ForegroundColor $tc.Accent -NoNewline
            Write-Host -Object " -> $($entry.Value)" -ForegroundColor $tc.Text
        }
    }

    function Remove-DirectoryBookmark {
        <#
        .SYNOPSIS
            Removes a directory bookmark.
        .PARAMETER Name
            Bookmark alias to remove.
        #>
        [CmdletBinding()]
        param(
            [Parameter(Mandatory, Position = 0)]
            [string]$Name
        )

        if ($script:BookmarkStore.ContainsKey($Name)) {
            $script:BookmarkStore.Remove($Name)
            $script:BookmarkStore | ConvertTo-Json -Depth 3 |
                Set-Content -Path $script:BookmarkCachePath -Encoding UTF8
            Write-Host -Object "  Bookmark '$Name' removed." -ForegroundColor $Global:Theme.Warning
        }
        else {
            Write-Warning -Message "Bookmark not found: $Name"
        }
    }

    # Register argument completer for Enter-Bookmark
    Register-ArgumentCompleter -CommandName 'Enter-Bookmark' -ParameterName 'Name' -ScriptBlock {
        param($commandName, $parameterName, $wordToComplete, $commandAst, $fakeBoundParameters)
        $script:BookmarkStore.Keys | Where-Object -FilterScript { $_ -like "$wordToComplete*" } | ForEach-Object -Process {
            [System.Management.Automation.CompletionResult]::new($_, $_, 'ParameterValue', $script:BookmarkStore[$_])
        }
    }
}

#endregion

#region -- Quick Navigation Shortcuts -----------------------------------------

function Enter-ParentDirectory {
    <#
    .SYNOPSIS
        Navigate up N levels. Shorthand: 'up', 'up 2', 'up 3'.
    .PARAMETER Levels
        Number of parent directories to traverse.
    #>
    [CmdletBinding()]
    [Alias('up')]
    param(
        [Parameter(Position = 0)]
        [ValidateRange(1, 20)]
        [int]$Levels = 1
    )

    $target = (Get-Location).Path
    for ($i = 0; $i -lt $Levels; $i++) {
        $parent = Split-Path -Path $target -Parent
        if ($parent) {
            $target = $parent
        }
        else {
            break
        }
    }
    Set-LocationTracked -Path $target
}

function Enter-LastDirectory {
    <#
    .SYNOPSIS
        Toggle between current and last directory (like 'cd -').
    #>
    [CmdletBinding()]
    [Alias('cdd')]
    param()

    if ($Global:DirectoryHistory.Count -ge 2) {
        $lastDir = $Global:DirectoryHistory[$Global:DirectoryHistory.Count - 1]
        Set-LocationTracked -Path $lastDir
    }
}

# CTT Navigation Functions
function Global:Set-Workspace { Set-Location "$env:USERPROFILE\Workspace" }
function Global:Set-Scripts { Set-Location "$env:USERPROFILE\Scripts\PowerShell" }
function Global:Set-Docs { Set-Location "$env:USERPROFILE\Docs" }
function Global:Set-Tools { Set-Location "$env:USERPROFILE\Tools" }
function Global:Set-Dev { Set-Location "$env:USERPROFILE\OneDrive\Dev" }
function Global:Set-Dotfiles { Set-Location "$env:USERPROFILE\dotfiles" }

# CTT Cleanup Shortcut
function Global:Invoke-Cleanup {
    if (Test-Path "$env:USERPROFILE\Scripts\PowerShell\Cleanup-System.ps1") {
        & "$env:USERPROFILE\Scripts\PowerShell\Cleanup-System.ps1" @args
    }
    else {
        Write-Warning "Cleanup-System.ps1 not found at $env:USERPROFILE\Scripts\PowerShell\"
    }
}

# CTT Navigation Aliases
Set-Alias -Name ws       -Value Set-Workspace  -Scope Global -Force
Set-Alias -Name cln      -Value Invoke-Cleanup -Scope Global -Force
Set-Alias -Name scripts  -Value Set-Scripts    -Scope Global -Force
Set-Alias -Name docs     -Value Set-Docs       -Scope Global -Force
Set-Alias -Name tools    -Value Set-Tools      -Scope Global -Force
Set-Alias -Name dev      -Value Set-Dev        -Scope Global -Force
Set-Alias -Name OC       -Value opencode       -Scope Global -Force
Set-Alias -Name dotfiles -Value Set-Dotfiles   -Scope Global -Force
# 'path' alias → Show-Path from 05-Functions-Core.ps1 (the richer version)

#endregion
