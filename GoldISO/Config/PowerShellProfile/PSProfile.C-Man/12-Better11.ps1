[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingWriteHost', '', Justification = 'Dev workflow display requires colored output')]
param()

#region ── Better11 Project Integration ───────────────────────────────────────

<#
.SYNOPSIS
    Better11 project-specific shortcuts, build commands, and workflow automation.
    Covers the C#/WinUI 3 app, PowerShell modules (BetterShell, BetterPE),
    and supporting infrastructure.
#>

if (-not $Global:ProfileConfig.Better11Integration) { return }

# Better11 project paths (configurable)
$script:B11Paths = @{
    Root        = $null
    Solution    = $null
    BetterShell = $null
    BetterPE    = $null
    Tests       = $null
    Docs        = $null
    Build       = $null
}

function Find-Better11Root {
    <#
    .SYNOPSIS
        Locate the Better11 project root from known paths or by searching.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param()

    # Check bookmark first
    if ($script:BookmarkStore -and $script:BookmarkStore.ContainsKey('b11')) {
        $bookmarkPath = $script:BookmarkStore['b11']
        if (Test-Path -Path $bookmarkPath) {
            return $bookmarkPath
        }
    }

    # Check common locations
    $searchPaths = @(
        (Join-Path -Path $env:USERPROFILE -ChildPath 'source\repos\Better11')
        (Join-Path -Path $env:USERPROFILE -ChildPath 'Documents\Better11')
        (Join-Path -Path $env:USERPROFILE -ChildPath 'Projects\Better11')
        'C:\Projects\Better11'
    )

    foreach ($path in $searchPaths) {
        if (Test-Path -Path $path) {
            return $path
        }
    }

    # Search from current directory upward
    $current = (Get-Location).Path
    while ($current) {
        if (Test-Path -Path (Join-Path -Path $current -ChildPath '*.sln') -PathType Leaf) {
            $slnFiles = Get-ChildItem -Path $current -Filter '*.sln'
            foreach ($sln in $slnFiles) {
                if ($sln.Name -match 'Better11|B11') {
                    return $current
                }
            }
        }
        $parent = Split-Path -Path $current -Parent
        if ($parent -eq $current) { break }
        $current = $parent
    }

    return $null
}

function Initialize-Better11Paths {
    <#
    .SYNOPSIS
        Discover and cache Better11 project structure paths.
    #>
    [CmdletBinding()]
    param()

    $root = Find-Better11Root
    if (-not $root) {
        return $false
    }

    $script:B11Paths.Root = $root
    $script:B11Paths.Solution = Get-ChildItem -Path $root -Filter '*.sln' -ErrorAction SilentlyContinue |
        Select-Object -First 1 -ExpandProperty FullName

    # Discover subproject paths
    $subDirs = @{
        BetterShell = @('BetterShell', 'src\BetterShell', 'Modules\BetterShell')
        BetterPE    = @('BetterPE', 'src\BetterPE', 'Modules\BetterPE')
        Tests       = @('Tests', 'tests', 'test', 'src\Tests')
        Docs        = @('docs', 'Docs', 'Documentation')
        Build       = @('build', 'Build', '.build')
    }

    foreach ($key in $subDirs.Keys) {
        foreach ($relPath in $subDirs[$key]) {
            $fullPath = Join-Path -Path $root -ChildPath $relPath
            if (Test-Path -Path $fullPath) {
                $script:B11Paths[$key] = $fullPath
                break
            }
        }
    }

    return $true
}

function Enter-Better11 {
    <#
    .SYNOPSIS
        Navigate to Better11 project root.
    .PARAMETER Component
        Navigate to a specific component: Root, Shell, PE, Tests, Docs, Build.
    #>
    [CmdletBinding()]
    [Alias('b11')]
    param(
        [Parameter(Position = 0)]
        [ValidateSet('Root', 'Shell', 'PE', 'Tests', 'Docs', 'Build')]
        [string]$Component = 'Root'
    )

    if (-not $script:B11Paths.Root) {
        if (-not (Initialize-Better11Paths)) {
            Write-Warning -Message 'Better11 project not found. Set bookmark: bm b11 <path-to-Better11>'
            return
        }
    }

    $targetPath = switch ($Component) {
        'Root'  { $script:B11Paths.Root }
        'Shell' { $script:B11Paths.BetterShell }
        'PE'    { $script:B11Paths.BetterPE }
        'Tests' { $script:B11Paths.Tests }
        'Docs'  { $script:B11Paths.Docs }
        'Build' { $script:B11Paths.Build }
    }

    if ($targetPath -and (Test-Path -Path $targetPath)) {
        Set-Location -Path $targetPath
        Write-Host -Object "  -> Better11/$Component" -ForegroundColor $script:Theme.Success
    }
    else {
        Write-Warning -Message "Better11 component '$Component' path not found."
    }
}

function Invoke-Better11Build {
    <#
    .SYNOPSIS
        Build Better11 solution or a specific project.
    .PARAMETER Project
        Specific project to build. If omitted, builds the full solution.
    .PARAMETER Configuration
        Build configuration (Debug/Release).
    .PARAMETER Clean
        Clean before building.
    #>
    [CmdletBinding()]
    [Alias('b11build')]
    param(
        [Parameter(Position = 0)]
        [string]$Project,

        [ValidateSet('Debug', 'Release')]
        [string]$Configuration = 'Debug',

        [switch]$Clean
    )

    $tc = $script:Theme
    if (-not $script:B11Paths.Root) {
        if (-not (Initialize-Better11Paths)) {
            Write-Warning -Message 'Better11 project not found.'
            return
        }
    }

    $buildTarget = if ($Project) {
        Get-ChildItem -Path $script:B11Paths.Root -Filter "$Project*.csproj" -Recurse |
            Select-Object -First 1 -ExpandProperty FullName
    }
    else {
        $script:B11Paths.Solution
    }

    if (-not $buildTarget) {
        Write-Warning -Message "Build target not found: $Project"
        return
    }

    $sw = [System.Diagnostics.Stopwatch]::StartNew()

    if ($Clean) {
        Write-Host -Object '  Cleaning...' -ForegroundColor $tc.Warning
        & dotnet clean $buildTarget --configuration $Configuration --verbosity quiet
    }

    Write-Host -Object "  Building: $(Split-Path -Path $buildTarget -Leaf) ($Configuration)" -ForegroundColor $tc.Info
    & dotnet build $buildTarget --configuration $Configuration --no-restore

    $sw.Stop()
    $buildTime = [math]::Round($sw.Elapsed.TotalSeconds, 1)

    if ($LASTEXITCODE -eq 0) {
        Write-Host -Object "  Build succeeded in ${buildTime}s" -ForegroundColor $tc.Success
    }
    else {
        Write-Host -Object "  Build FAILED after ${buildTime}s" -ForegroundColor $tc.Error
    }
}

function Invoke-Better11Test {
    <#
    .SYNOPSIS
        Run Better11 test suite with formatted output.
    .PARAMETER Filter
        Test name filter pattern.
    .PARAMETER Component
        Test a specific component (Shell, PE, Core).
    #>
    [CmdletBinding()]
    [Alias('b11test')]
    param(
        [string]$Filter,

        [ValidateSet('All', 'Shell', 'PE', 'Core')]
        [string]$Component = 'All'
    )

    $tc = $script:Theme
    if (-not $script:B11Paths.Root) {
        if (-not (Initialize-Better11Paths)) {
            Write-Warning -Message 'Better11 project not found.'
            return
        }
    }

    $testPath = if ($Component -ne 'All' -and $script:B11Paths.Tests) {
        $componentTestDir = Join-Path -Path $script:B11Paths.Tests -ChildPath $Component
        if (Test-Path -Path $componentTestDir) { $componentTestDir } else { $script:B11Paths.Tests }
    }
    else {
        if ($script:B11Paths.Tests) { $script:B11Paths.Tests } else { $script:B11Paths.Root }
    }

    $args_ = @('test', $testPath, '--verbosity', 'normal')
    if ($Filter) {
        $args_ += '--filter'
        $args_ += $Filter
    }

    Write-Host -Object "  Running tests: $Component$(if ($Filter) { " (filter: $Filter)" })" -ForegroundColor $tc.Info
    & dotnet @args_

    if ($LASTEXITCODE -eq 0) {
        Write-Host -Object '  All tests passed.' -ForegroundColor $tc.Success
    }
    else {
        Write-Host -Object '  Some tests FAILED.' -ForegroundColor $tc.Error
    }
}

function Invoke-Better11Analyze {
    <#
    .SYNOPSIS
        Run code analysis on Better11 (StyleCop + PSScriptAnalyzer).
    #>
    [CmdletBinding()]
    [Alias('b11lint')]
    param()

    $tc = $script:Theme
    if (-not $script:B11Paths.Root) {
        if (-not (Initialize-Better11Paths)) {
            Write-Warning -Message 'Better11 project not found.'
            return
        }
    }

    Write-Host -Object '  Running code analysis...' -ForegroundColor $tc.Info

    # .NET/StyleCop analysis
    if ($script:B11Paths.Solution) {
        Write-Host -Object "`n  [.NET / StyleCop]" -ForegroundColor $tc.Primary
        & dotnet build $script:B11Paths.Solution --no-restore /p:TreatWarningsAsErrors=true 2>&1 |
            Select-String -Pattern '(error|warning) (CS|SA|CA)\d+' | ForEach-Object -Process {
                if ($_.Line -match 'error') {
                    Write-Host -Object "    $($_.Line.Trim())" -ForegroundColor $tc.Error
                }
                else {
                    Write-Host -Object "    $($_.Line.Trim())" -ForegroundColor $tc.Warning
                }
            }
    }

    # PSScriptAnalyzer for PowerShell modules
    $psModulePaths = @($script:B11Paths.BetterShell, $script:B11Paths.BetterPE) | Where-Object -FilterScript { $_ -and (Test-Path -Path $_) }
    if ($psModulePaths.Count -gt 0 -and (Get-Module -Name PSScriptAnalyzer -ListAvailable)) {
        Write-Host -Object "`n  [PSScriptAnalyzer]" -ForegroundColor $tc.Primary
        foreach ($modulePath in $psModulePaths) {
            $results = Invoke-ScriptAnalyzer -Path $modulePath -Recurse -Severity Warning
            $moduleName = Split-Path -Path $modulePath -Leaf
            if ($results.Count -eq 0) {
                Write-Host -Object "    $moduleName`: Clean" -ForegroundColor $tc.Success
            }
            else {
                Write-Host -Object "    $moduleName`: $($results.Count) issues" -ForegroundColor $tc.Warning
                $results | Group-Object -Property Severity | ForEach-Object -Process {
                    Write-Host -Object "      $($_.Name): $($_.Count)" -ForegroundColor $tc.Muted
                }
            }
        }
    }

    Write-Host ''
}

function Get-Better11Status {
    <#
    .SYNOPSIS
        Quick overview of Better11 project state: git, builds, components.
    #>
    [CmdletBinding()]
    [Alias('b11status')]
    param()

    $tc = $script:Theme
    if (-not $script:B11Paths.Root) {
        if (-not (Initialize-Better11Paths)) {
            Write-Warning -Message 'Better11 project not found.'
            return
        }
    }

    Write-Host -Object "`n  Better11 Project Status:" -ForegroundColor $tc.Primary
    Write-Host -Object "  Root: $($script:B11Paths.Root)" -ForegroundColor $tc.Text

    # Git status
    Push-Location -Path $script:B11Paths.Root
    try {
        $branch = & git rev-parse --abbrev-ref HEAD 2>$null
        if ($LASTEXITCODE -eq 0) {
            $dirty = & git status --porcelain 2>$null
            $dirtyCount = ($dirty | Measure-Object).Count
            $ahead = & git rev-list --count HEAD@{upstream}..HEAD 2>$null
            $lastCommit = & git log -1 --format='%s (%cr)' 2>$null

            Write-Host -Object "  Branch:   $branch" -ForegroundColor $tc.Accent -NoNewline
            if ($dirtyCount -gt 0) {
                Write-Host -Object " ($dirtyCount uncommitted changes)" -ForegroundColor $tc.Warning
            }
            else {
                Write-Host -Object ' (clean)' -ForegroundColor $tc.Success
            }
            if ($ahead -gt 0) {
                Write-Host -Object "  Ahead:    $ahead commits ahead of upstream" -ForegroundColor $tc.Info
            }
            Write-Host -Object "  Latest:   $lastCommit" -ForegroundColor $tc.Muted
        }
    }
    finally {
        Pop-Location
    }

    # Component discovery
    Write-Host -Object "`n  Components:" -ForegroundColor $tc.Primary
    $components = @(
        @{ Name = 'Solution';    Path = $script:B11Paths.Solution }
        @{ Name = 'BetterShell'; Path = $script:B11Paths.BetterShell }
        @{ Name = 'BetterPE';    Path = $script:B11Paths.BetterPE }
        @{ Name = 'Tests';       Path = $script:B11Paths.Tests }
        @{ Name = 'Docs';        Path = $script:B11Paths.Docs }
        @{ Name = 'Build';       Path = $script:B11Paths.Build }
    )

    foreach ($comp in $components) {
        $exists = $comp.Path -and (Test-Path -Path $comp.Path)
        $icon = if ($exists) { [char]0x2713 } else { [char]0x2717 }
        $color = if ($exists) { $tc.Success } else { $tc.Muted }
        $pathStr = if ($exists) { $comp.Path } else { 'not found' }
        Write-Host -Object "    $icon $($comp.Name.PadRight(14))" -ForegroundColor $color -NoNewline
        Write-Host -Object $pathStr -ForegroundColor $tc.Muted
    }

    # Quick file counts
    if ($script:B11Paths.Root) {
        $csFiles = (Get-ChildItem -Path $script:B11Paths.Root -Filter '*.cs' -Recurse -ErrorAction SilentlyContinue |
            Where-Object -FilterScript { $_.FullName -notmatch '[\\/](bin|obj)[\\/]' }).Count
        $ps1Files = (Get-ChildItem -Path $script:B11Paths.Root -Filter '*.ps1' -Recurse -ErrorAction SilentlyContinue).Count
        $xamlFiles = (Get-ChildItem -Path $script:B11Paths.Root -Filter '*.xaml' -Recurse -ErrorAction SilentlyContinue |
            Where-Object -FilterScript { $_.FullName -notmatch '[\\/](bin|obj)[\\/]' }).Count

        Write-Host -Object "`n  Codebase:" -ForegroundColor $tc.Primary
        Write-Host -Object "    C# files:         $csFiles" -ForegroundColor $tc.Text
        Write-Host -Object "    PowerShell files:  $ps1Files" -ForegroundColor $tc.Text
        Write-Host -Object "    XAML files:        $xamlFiles" -ForegroundColor $tc.Text
    }

    Write-Host ''
}

function Invoke-Better11Publish {
    <#
    .SYNOPSIS
        Publish Better11 for release (self-contained, trimmed).
    .PARAMETER Runtime
        Target runtime identifier.
    .PARAMETER Configuration
        Build configuration.
    .PARAMETER OutputPath
        Publish output directory.
    #>
    [CmdletBinding()]
    [Alias('b11pub')]
    param(
        [string]$Runtime = 'win-x64',

        [ValidateSet('Debug', 'Release')]
        [string]$Configuration = 'Release',

        [string]$OutputPath
    )

    $tc = $script:Theme
    if (-not $script:B11Paths.Solution) {
        Write-Warning -Message 'Better11 solution not found.'
        return
    }

    if (-not $OutputPath) {
        $OutputPath = Join-Path -Path $script:B11Paths.Root -ChildPath 'publish'
    }

    Write-Host -Object "  Publishing Better11 ($Runtime, $Configuration)..." -ForegroundColor $tc.Info

    $publishArgs = @(
        'publish', $script:B11Paths.Solution
        '--configuration', $Configuration
        '--runtime', $Runtime
        '--self-contained', 'true'
        '--output', $OutputPath
        '-p:PublishSingleFile=true'
        '-p:PublishTrimmed=true'
        '-p:IncludeNativeLibrariesForSelfExtract=true'
    )

    & dotnet @publishArgs

    if ($LASTEXITCODE -eq 0) {
        $outputSize = (Get-ChildItem -Path $OutputPath -Recurse -File -ErrorAction SilentlyContinue |
            Measure-Object -Property Length -Sum).Sum
        $sizeMb = [math]::Round($outputSize / 1MB, 1)
        Write-Host -Object "  Published to: $OutputPath ($sizeMb MB)" -ForegroundColor $tc.Success
    }
    else {
        Write-Host -Object '  Publish FAILED.' -ForegroundColor $tc.Error
    }
}

function Open-Better11InVSCode {
    <#
    .SYNOPSIS
        Open Better11 project workspace in VS Code.
    #>
    [CmdletBinding()]
    [Alias('b11code')]
    param()

    if (-not $script:B11Paths.Root) {
        if (-not (Initialize-Better11Paths)) {
            Write-Warning -Message 'Better11 project not found.'
            return
        }
    }

    # Check for workspace file first
    $workspace = Get-ChildItem -Path $script:B11Paths.Root -Filter '*.code-workspace' -ErrorAction SilentlyContinue |
        Select-Object -First 1
    if ($workspace) {
        & code $workspace.FullName
    }
    else {
        & code $script:B11Paths.Root
    }
}

# Tab completion for Enter-Better11
Register-ArgumentCompleter -CommandName 'Enter-Better11' -ParameterName 'Component' -ScriptBlock {
    param($commandName, $parameterName, $wordToComplete, $commandAst, $fakeBoundParameters)
    @('Root', 'Shell', 'PE', 'Tests', 'Docs', 'Build') |
        Where-Object -FilterScript { $_ -like "$wordToComplete*" } |
        ForEach-Object -Process {
            [System.Management.Automation.CompletionResult]::new($_, $_, 'ParameterValue', "Better11: $_")
        }
}

# Auto-initialize on load if possible
$null = Initialize-Better11Paths

#endregion

