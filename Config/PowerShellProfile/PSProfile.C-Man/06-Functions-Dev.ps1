[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingWriteHost', '', Justification = 'Dev tool output requires colored display')]
param()

#region ── Project Management ─────────────────────────────────────────────────

function Find-ProjectRoot {
    <#
    .SYNOPSIS
        Walk up from current directory to find project root markers.
    .DESCRIPTION
        Searches for .git, .sln, package.json, Cargo.toml, etc.
    #>
    [CmdletBinding()]
    [Alias('projroot')]
    param()

    $markers = @('.git', '*.sln', 'package.json', 'Cargo.toml', 'go.mod', '*.csproj', 'build.ps1', 'Taskfile.yml')
    $current = Get-Location | Select-Object -ExpandProperty Path

    while ($current) {
        foreach ($marker in $markers) {
            if (Get-ChildItem -Path $current -Filter $marker -Force -ErrorAction SilentlyContinue) {
                return $current
            }
        }
        $parent = Split-Path -Path $current -Parent
        if ($parent -eq $current) { break }
        $current = $parent
    }

    Write-Warning -Message 'No project root found.'
    return $null
}

function Enter-ProjectRoot {
    <#
    .SYNOPSIS
        Navigate to the detected project root.
    #>
    [CmdletBinding()]
    [Alias('cdp')]
    param()

    $root = Find-ProjectRoot
    if ($root) {
        Set-Location -Path $root
        Write-Host -Object "  -> $root" -ForegroundColor $script:Theme.Success
    }
}

function Get-ProjectInfo {
    <#
    .SYNOPSIS
        Display project metadata from current directory.
    #>
    [CmdletBinding()]
    [Alias('projinfo')]
    param()

    $tc = $Global:Theme
    $root = Find-ProjectRoot
    if (-not $root) { return }

    Write-Host -Object "`n  Project Root: $root" -ForegroundColor $tc.Primary

    # Detect project types
    $types = [System.Collections.Generic.List[string]]::new()

    if (Get-ChildItem -Path $root -Filter '*.sln' -ErrorAction SilentlyContinue) {
        $slnFiles = Get-ChildItem -Path $root -Filter '*.sln'
        $types.Add(".NET Solution ($($slnFiles[0].Name))")
    }
    if (Test-Path -Path (Join-Path -Path $root -ChildPath 'package.json')) {
        $pkg = Get-Content -Path (Join-Path -Path $root -ChildPath 'package.json') -Raw | ConvertFrom-Json
        $types.Add("Node.js ($($pkg.name) v$($pkg.version))")
    }
    $csprojFiles = Get-ChildItem -Path $root -Filter '*.csproj' -Recurse -ErrorAction SilentlyContinue
    if ($csprojFiles) {
        $types.Add("C# Projects ($($csprojFiles.Count) .csproj)")
    }
    $ps1Files = Get-ChildItem -Path $root -Filter '*.ps1' -Recurse -ErrorAction SilentlyContinue
    if ($ps1Files.Count -gt 5) {
        $types.Add("PowerShell ($($ps1Files.Count) scripts)")
    }
    if (Test-Path -Path (Join-Path -Path $root -ChildPath 'Dockerfile')) {
        $types.Add('Docker')
    }

    foreach ($type in $types) {
        Write-Host -Object "  Type:    $type" -ForegroundColor $tc.Text
    }

    # Git info
    Push-Location -Path $root
    try {
        $branch = & git rev-parse --abbrev-ref HEAD 2>$null
        if ($LASTEXITCODE -eq 0) {
            $commitCount = & git rev-list --count HEAD 2>$null
            $lastCommit = & git log -1 --format='%s (%cr)' 2>$null
            Write-Host -Object "  Branch:  $branch ($commitCount commits)" -ForegroundColor $tc.Text
            Write-Host -Object "  Latest:  $lastCommit" -ForegroundColor $tc.Muted
        }
    }
    finally {
        Pop-Location
    }

    Write-Host ''
}

#endregion

#region ── Build Helpers ──────────────────────────────────────────────────────

function Invoke-CleanBuildArtifacts {
    <#
    .SYNOPSIS
        Remove common build artifacts (bin, obj, node_modules, dist, .vs, etc.).
    .PARAMETER Path
        Root directory to clean.
    .PARAMETER WhatIf
        Preview what would be deleted.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    [Alias('cleanall')]
    param(
        [Parameter(Position = 0)]
        [string]$Path = '.'
    )

    $foldersToDelete = @('bin', 'obj', 'node_modules', 'dist', '.vs', '.vscode/.browse', 'packages',
        'TestResults', 'BenchmarkDotNet.Artifacts', '__pycache__', '.pytest_cache', 'coverage')

    $tc = $script:Theme
    $totalSize = 0
    $totalCount = 0

    foreach ($folder in $foldersToDelete) {
        $found = Get-ChildItem -Path $Path -Directory -Filter $folder -Recurse -Force -ErrorAction SilentlyContinue
        foreach ($dir in $found) {
            $size = (Get-ChildItem -Path $dir.FullName -Recurse -File -Force -ErrorAction SilentlyContinue |
                Measure-Object -Property Length -Sum).Sum
            $sizeMb = [math]::Round($size / 1MB, 1)

            if ($PSCmdlet.ShouldProcess($dir.FullName, "Remove ($sizeMb MB)")) {
                Remove-Item -Path $dir.FullName -Recurse -Force -ErrorAction SilentlyContinue
                $totalSize += $size
                $totalCount++
                Write-Host -Object "  Removed: $($dir.FullName) ($sizeMb MB)" -ForegroundColor $tc.Warning
            }
        }
    }

    $totalMb = [math]::Round($totalSize / 1MB, 1)
    Write-Host -Object "`n  Cleaned $totalCount folders, freed $totalMb MB" -ForegroundColor $tc.Success
}

function Watch-FileChanges {
    <#
    .SYNOPSIS
        Watch a directory for file changes and run a command on change.
    .PARAMETER Path
        Directory to watch.
    .PARAMETER Filter
        File filter pattern.
    .PARAMETER ScriptBlock
        Command to execute on change.
    .EXAMPLE
        Watch-FileChanges -Path ./src -Filter '*.cs' -ScriptBlock { dotnet build }
    #>
    [CmdletBinding()]
    param(
        [Parameter(Position = 0)]
        [string]$Path = '.',

        [string]$Filter = '*.*',

        [Parameter(Mandatory)]
        [scriptblock]$ScriptBlock
    )

    $watcher = [System.IO.FileSystemWatcher]::new()
    $watcher.Path = (Resolve-Path -Path $Path).Path
    $watcher.Filter = $Filter
    $watcher.IncludeSubdirectories = $true
    $watcher.EnableRaisingEvents = $true

    $action = {
        $details = $Event.SourceEventArgs
        Write-Host -Object "  [$(Get-Date -Format 'HH:mm:ss')] $($details.ChangeType): $($details.Name)" -ForegroundColor Cyan
        & $ScriptBlock
    }

    $handlers = @()
    $handlers += Register-ObjectEvent -InputObject $watcher -EventName Changed -Action $action
    $handlers += Register-ObjectEvent -InputObject $watcher -EventName Created -Action $action
    $handlers += Register-ObjectEvent -InputObject $watcher -EventName Deleted -Action $action

    Write-Host -Object "  Watching $Path for $Filter changes. Press Ctrl+C to stop." -ForegroundColor $script:Theme.Info
    try {
        while ($true) { Start-Sleep -Seconds 1 }
    }
    finally {
        $handlers | ForEach-Object -Process { Unregister-Event -SubscriptionId $_.Id }
        $watcher.Dispose()
    }
}

#endregion

#region ── Code Quality ───────────────────────────────────────────────────────

function Invoke-PSScriptAnalyzerCheck {
    <#
    .SYNOPSIS
        Run PSScriptAnalyzer on a file or directory with formatted output.
    .PARAMETER Path
        File or directory to analyze.
    .PARAMETER Severity
        Minimum severity to report.
    #>
    [CmdletBinding()]
    [Alias('lint')]
    param(
        [Parameter(Position = 0)]
        [string]$Path = '.',

        [ValidateSet('Information', 'Warning', 'Error')]
        [string]$Severity = 'Warning'
    )

    if (-not (Get-Module -Name PSScriptAnalyzer -ListAvailable)) {
        Write-Warning -Message 'PSScriptAnalyzer not installed. Run: Install-Module PSScriptAnalyzer'
        return
    }

    $tc = $Global:Theme
    $results = Invoke-ScriptAnalyzer -Path $Path -Recurse -Severity $Severity

    if ($results.Count -eq 0) {
        Write-Host -Object '  All clear - no issues found.' -ForegroundColor $tc.Success
        return
    }

    $grouped = $results | Group-Object -Property Severity
    foreach ($group in $grouped) {
        $color = switch ($group.Name) {
            'Error'       { $tc.Error }
            'Warning'     { $tc.Warning }
            'Information' { $tc.Info }
        }
        Write-Host -Object "`n  [$($group.Name)] $($group.Count) issues:" -ForegroundColor $color

        foreach ($issue in $group.Group) {
            $relativePath = Resolve-Path -Path $issue.ScriptPath -Relative -ErrorAction SilentlyContinue
            Write-Host -Object "    $relativePath" -ForegroundColor $tc.Muted -NoNewline
            Write-Host -Object ":$($issue.Line) " -ForegroundColor $tc.Muted -NoNewline
            Write-Host -Object $issue.RuleName -ForegroundColor $color -NoNewline
            Write-Host -Object " - $($issue.Message)" -ForegroundColor $tc.Text
        }
    }
    Write-Host ''
}

function Get-CodeStats {
    <#
    .SYNOPSIS
        Count lines of code by file type in a project.
    .PARAMETER Path
        Root directory to analyze.
    #>
    [CmdletBinding()]
    [Alias('cloc')]
    param(
        [Parameter(Position = 0)]
        [string]$Path = '.'
    )

    $tc = $script:Theme
    $extensions = @{
        '.ps1'    = 'PowerShell'
        '.psm1'   = 'PowerShell Module'
        '.psd1'   = 'PowerShell Data'
        '.cs'     = 'C#'
        '.csproj' = 'C# Project'
        '.xaml'   = 'XAML'
        '.json'   = 'JSON'
        '.xml'    = 'XML'
        '.js'     = 'JavaScript'
        '.ts'     = 'TypeScript'
        '.tsx'    = 'React TSX'
        '.jsx'    = 'React JSX'
        '.css'    = 'CSS'
        '.scss'   = 'SCSS'
        '.html'   = 'HTML'
        '.py'     = 'Python'
        '.cpp'    = 'C++'
        '.h'      = 'C/C++ Header'
        '.md'     = 'Markdown'
        '.yml'    = 'YAML'
        '.yaml'   = 'YAML'
    }

    $excludeDirs = @('node_modules', 'bin', 'obj', '.git', '.vs', 'dist', 'packages', '__pycache__')
    $stats = @{}

    $files = Get-ChildItem -Path $Path -Recurse -File -ErrorAction SilentlyContinue |
        Where-Object -FilterScript {
            $fullName = $_.FullName
            $excluded = $false
            foreach ($dir in $excludeDirs) {
                if ($fullName -match "[\\/]$dir[\\/]") {
                    $excluded = $true
                    break
                }
            }
            -not $excluded -and $extensions.ContainsKey($_.Extension.ToLower())
        }

    foreach ($file in $files) {
        $lang = $extensions[$file.Extension.ToLower()]
        $lineCount = (Get-Content -Path $file.FullName -ErrorAction SilentlyContinue | Measure-Object).Count

        if (-not $stats.ContainsKey($lang)) {
            $stats[$lang] = @{ Files = 0; Lines = 0 }
        }
        $stats[$lang].Files++
        $stats[$lang].Lines += $lineCount
    }

    Write-Host -Object "`n  Code Statistics:" -ForegroundColor $tc.Primary
    $totalFiles = 0
    $totalLines = 0

    $stats.GetEnumerator() | Sort-Object -Property { $_.Value.Lines } -Descending | ForEach-Object -Process {
        $lang = $_.Key.PadRight(20)
        $fileCount = "$($_.Value.Files) files".PadRight(12)
        $lineCount = "$($_.Value.Lines) lines"
        Write-Host -Object "    $lang" -ForegroundColor $tc.Accent -NoNewline
        Write-Host -Object "$fileCount" -ForegroundColor $tc.Muted -NoNewline
        Write-Host -Object $lineCount -ForegroundColor $tc.Text
        $totalFiles += $_.Value.Files
        $totalLines += $_.Value.Lines
    }

    Write-Host -Object "    $('─' * 45)" -ForegroundColor $tc.Separator
    Write-Host -Object "    $('TOTAL'.PadRight(20))" -ForegroundColor $tc.Primary -NoNewline
    Write-Host -Object "$("$totalFiles files".PadRight(12))" -ForegroundColor $tc.Muted -NoNewline
    Write-Host -Object "$totalLines lines" -ForegroundColor $tc.Primary
    Write-Host ''
}

function New-DotnetProject {
    <#
    .SYNOPSIS
        Quick-scaffold a new .NET project with common setup.
    .PARAMETER Name
        Project name.
    .PARAMETER Template
        dotnet template (console, classlib, webapi, winui3, etc.).
    .PARAMETER Framework
        Target framework (net8.0, net9.0, etc.).
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, Position = 0)]
        [string]$Name,

        [Parameter(Position = 1)]
        [string]$Template = 'console',

        [string]$Framework = 'net9.0'
    )

    $tc = $script:Theme
    & dotnet new $Template -n $Name --framework $Framework
    if ($LASTEXITCODE -eq 0) {
        Set-Location -Path $Name
        & git init
        Write-Host -Object "  Created $Template project: $Name ($Framework)" -ForegroundColor $tc.Success
    }
}

#endregion

#region ── Environment Diagnostics ────────────────────────────────────────────

function Get-DevEnvironment {
    <#
    .SYNOPSIS
        Show installed dev tool versions at a glance.
    #>
    [CmdletBinding()]
    [Alias('devenv')]
    param()

    $tc = $script:Theme
    Write-Host -Object "`n  Development Environment:" -ForegroundColor $tc.Primary

    $tools = @(
        @{ Name = 'PowerShell'; Cmd = { $PSVersionTable.PSVersion.ToString() } }
        @{ Name = '.NET SDK';   Cmd = { (& dotnet --version 2>$null) } }
        @{ Name = 'Node.js';    Cmd = { (& node --version 2>$null) } }
        @{ Name = 'npm';        Cmd = { (& npm --version 2>$null) } }
        @{ Name = 'Git';        Cmd = { (& git --version 2>$null) -replace 'git version ', '' } }
        @{ Name = 'Docker';     Cmd = { (& docker --version 2>$null) -replace 'Docker version ', '' -replace ',.*', '' } }
        @{ Name = 'Python';     Cmd = { (& python --version 2>$null) -replace 'Python ', '' } }
        @{ Name = 'Rust';       Cmd = { (& rustc --version 2>$null) -replace 'rustc ', '' } }
        @{ Name = 'Go';         Cmd = { (& go version 2>$null) -replace 'go version go', '' -replace ' .*', '' } }
        @{ Name = 'VS Code';    Cmd = { (& code --version 2>$null | Select-Object -First 1) } }
    )

    foreach ($tool in $tools) {
        $version = try { & $tool.Cmd } catch { $null }
        if ($version) {
            Write-Host -Object "    $($tool.Name.PadRight(14))" -ForegroundColor $tc.Accent -NoNewline
            Write-Host -Object $version -ForegroundColor $tc.Text
        }
        else {
            Write-Host -Object "    $($tool.Name.PadRight(14))" -ForegroundColor $tc.Muted -NoNewline
            Write-Host -Object 'not found' -ForegroundColor $tc.Muted
        }
    }
    Write-Host ''
}

#endregion

