<#
.SYNOPSIS
    .NET Toolbox module for C-Man's PowerShell Profile.
.DESCRIPTION
    Solution/project explorer, NuGet dependency tree viewer, migration
    runner shortcuts, dotnet watch manager, assembly inspector, coverage
    report viewer, and source generator helpers.
.NOTES
    Module: 22-DotnetToolbox.ps1
    Requires: PowerShell 5.1+, .NET SDK
#>

#region ── Solution Explorer ──────────────────────────────────────────────────

<#
.SYNOPSIS
    Displays a solution or project structure tree.
.DESCRIPTION
    Parses .sln files to show all projects, or scans a directory tree
    for .csproj/.fsproj files with their target frameworks and types.
.PARAMETER Path
    Path to .sln file or directory. Defaults to current directory.
.EXAMPLE
    Show-DotnetSolution
.EXAMPLE
    slnx .\Better11.sln
#>
function Show-DotnetSolution {
    [CmdletBinding()]
    [OutputType([void])]
    param(
        [Parameter(Position = 0)]
        [string]$Path = (Get-Location).Path
    )

    Write-Host "`n  .NET Solution Explorer" -ForegroundColor $script:Theme.Primary
    Write-Host "  $('â•' * 60)" -ForegroundColor $script:Theme.Muted

    $slnFile = if (Test-Path -Path $Path -PathType Leaf) {
        $Path
    }
    else {
        Get-ChildItem -Path $Path -Filter '*.sln' -ErrorAction SilentlyContinue | Select-Object -First 1 -ExpandProperty FullName
    }

    if ($null -ne $slnFile -and (Test-Path -Path $slnFile)) {
        $slnName = Split-Path -Path $slnFile -Leaf
        Write-Host "  Solution: $slnName" -ForegroundColor $script:Theme.Accent
        Write-Host ''

        $content = Get-Content -Path $slnFile
        $projects = $content | Where-Object -FilterScript { $_ -match '^Project\(' } | ForEach-Object -Process {
            if ($_ -match '"([^"]+)",\s*"([^"]+)"') {
                [PSCustomObject]@{ Name = $Matches[1]; Path = $Matches[2] }
            }
        }

        foreach ($proj in ($projects | Sort-Object -Property Name)) {
            $projPath = Join-Path -Path (Split-Path -Path $slnFile -Parent) -ChildPath $proj.Path
            $icon = if ($proj.Path -match '\.csproj$') { 'C#' }
                elseif ($proj.Path -match '\.fsproj$') { 'F#' }
                elseif ($proj.Path -match '\.vbproj$') { 'VB' }
                else { '──' }

            $tfm = ''
            $outputType = ''
            if (Test-Path -Path $projPath) {
                $projContent = Get-Content -Path $projPath -Raw -ErrorAction SilentlyContinue
                if ($projContent -match '<TargetFramework[s]?>(.*?)</TargetFramework[s]?>') {
                    $tfm = $Matches[1]
                }
                if ($projContent -match '<OutputType>(.*?)</OutputType>') {
                    $outputType = $Matches[1]
                }
            }

            Write-Host "  $icon " -ForegroundColor $script:Theme.Accent -NoNewline
            Write-Host "$($proj.Name.PadRight(35))" -ForegroundColor $script:Theme.Text -NoNewline
            Write-Host "$($tfm.PadRight(20))" -ForegroundColor $script:Theme.Info -NoNewline
            Write-Host "$outputType" -ForegroundColor $script:Theme.Muted
        }
    }
    else {
        # Scan for project files
        $projFiles = Get-ChildItem -Path $Path -Include '*.csproj', '*.fsproj' -Recurse -Depth 5 -ErrorAction SilentlyContinue
        if ($projFiles.Count -eq 0) {
            Write-Host '  No .sln or project files found.' -ForegroundColor $Global:Theme.Muted
            return
        }

        foreach ($pf in ($projFiles | Sort-Object -Property Name)) {
            $content = Get-Content -Path $pf.FullName -Raw -ErrorAction SilentlyContinue
            $tfm = if ($content -match '<TargetFramework[s]?>(.*?)</TargetFramework[s]?>') { $Matches[1] } else { '?' }
            $relPath = $pf.FullName.Replace($Path, '.').Replace('\', '/')

            Write-Host "  $($pf.BaseName.PadRight(35))" -ForegroundColor $script:Theme.Text -NoNewline
            Write-Host "$($tfm.PadRight(20))" -ForegroundColor $script:Theme.Info -NoNewline
            Write-Host "$relPath" -ForegroundColor $script:Theme.Muted
        }
    }

    Write-Host ''
}

#endregion

#region ── NuGet Dependency Tree ──────────────────────────────────────────────

<#
.SYNOPSIS
    Shows NuGet package dependency tree for a project.
.PARAMETER Path
    Path to .csproj file or directory.
.PARAMETER Outdated
    Show only outdated packages.
.PARAMETER Vulnerable
    Check for known vulnerabilities.
.EXAMPLE
    Show-NuGetDependencies
.EXAMPLE
    nuget-tree -Outdated
#>
function Show-NuGetDependencies {
    [CmdletBinding()]
    [OutputType([void])]
    param(
        [Parameter(Position = 0)]
        [string]$Path = (Get-Location).Path,

        [Parameter()]
        [switch]$Outdated,

        [Parameter()]
        [switch]$Vulnerable
    )

    if (-not (Get-Command -Name 'dotnet' -ErrorAction SilentlyContinue)) {
        Write-Warning -Message 'dotnet CLI not found.'
        return
    }

    Write-Host "`n  NuGet Dependencies" -ForegroundColor $script:Theme.Primary
    Write-Host "  $('─' * 60)" -ForegroundColor $script:Theme.Muted

    $args = @('list', $Path, 'package')
    if ($Outdated) { $args += '--outdated' }
    if ($Vulnerable) { $args += '--vulnerable' }

    $output = & dotnet @args 2>&1
    $currentProject = ''

    foreach ($line in $output) {
        if ($line -match '^\s*Project\s+.(.+).$') {
            $currentProject = $Matches[1]
            Write-Host "`n  [$currentProject]" -ForegroundColor $script:Theme.Accent
        }
        elseif ($line -match '^\s*>\s+(\S+)\s+(\S+)\s*(\S*)') {
            $pkgName = $Matches[1]
            $requested = $Matches[2]
            $latest = $Matches[3]

            $color = if (-not [string]::IsNullOrEmpty($latest) -and $latest -ne $requested) {
                $Global:Theme.Warning
            }
            else { $Global:Theme.Text }

            Write-Host "    $($pkgName.PadRight(40))" -ForegroundColor $color -NoNewline
            Write-Host "$($requested.PadRight(15))" -ForegroundColor $script:Theme.Muted -NoNewline
            if (-not [string]::IsNullOrEmpty($latest) -and $latest -ne $requested) {
                Write-Host "→ $latest" -ForegroundColor $script:Theme.Success
            }
            else {
                Write-Host '' -ForegroundColor $Global:Theme.Muted
            }
        }
    }
    Write-Host ''
}

#endregion

#region ── Migration Runner ───────────────────────────────────────────────────

<#
.SYNOPSIS
    EF Core migration shortcuts.
.PARAMETER Action
    Migration action to perform.
.PARAMETER Name
    Migration name for 'add' action.
.PARAMETER Project
    Project path for EF commands.
.PARAMETER Context
    DbContext class name.
.EXAMPLE
    Invoke-EFMigration -Action add -Name 'AddUserTable'
.EXAMPLE
    efm add AddUserTable
#>
function Invoke-EFMigration {
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([void])]
    param(
        [Parameter(Mandatory, Position = 0)]
        [ValidateSet('add', 'remove', 'list', 'update', 'script', 'revert')]
        [string]$Action,

        [Parameter(Position = 1)]
        [string]$Name,

        [Parameter()]
        [string]$Project,

        [Parameter()]
        [string]$Context
    )

    if (-not (Get-Command -Name 'dotnet' -ErrorAction SilentlyContinue)) {
        Write-Warning -Message 'dotnet CLI not found.'
        return
    }

    $baseArgs = @('ef', 'migrations')
    if (-not [string]::IsNullOrEmpty($Project)) { $baseArgs += @('--project', $Project) }
    if (-not [string]::IsNullOrEmpty($Context)) { $baseArgs += @('--context', $Context) }

    switch ($Action) {
        'add' {
            if ([string]::IsNullOrEmpty($Name)) {
                Write-Warning -Message 'Migration name required for add.'
                return
            }
            if ($PSCmdlet.ShouldProcess($Name, 'Add migration')) {
                & dotnet @baseArgs add $Name 2>&1
            }
        }
        'remove' {
            if ($PSCmdlet.ShouldProcess('last migration', 'Remove')) {
                & dotnet @baseArgs remove 2>&1
            }
        }
        'list' {
            & dotnet @baseArgs list 2>&1
        }
        'update' {
            $target = if (-not [string]::IsNullOrEmpty($Name)) { $Name } else { '' }
            if ($PSCmdlet.ShouldProcess($target, 'Update database')) {
                $updateArgs = @('ef', 'database', 'update')
                if (-not [string]::IsNullOrEmpty($target)) { $updateArgs += $target }
                if (-not [string]::IsNullOrEmpty($Project)) { $updateArgs += @('--project', $Project) }
                if (-not [string]::IsNullOrEmpty($Context)) { $updateArgs += @('--context', $Context) }
                & dotnet @updateArgs 2>&1
            }
        }
        'script' {
            $scriptArgs = @('ef', 'migrations', 'script', '--idempotent')
            if (-not [string]::IsNullOrEmpty($Project)) { $scriptArgs += @('--project', $Project) }
            & dotnet @scriptArgs 2>&1
        }
        'revert' {
            $target = if (-not [string]::IsNullOrEmpty($Name)) { $Name } else { '0' }
            if ($PSCmdlet.ShouldProcess($target, 'Revert database')) {
                $revertArgs = @('ef', 'database', 'update', $target)
                if (-not [string]::IsNullOrEmpty($Project)) { $revertArgs += @('--project', $Project) }
                & dotnet @revertArgs 2>&1
            }
        }
    }
}

#endregion

#region ── Watch Manager ──────────────────────────────────────────────────────

<#
.SYNOPSIS
    Enhanced dotnet watch with project selection.
.PARAMETER Project
    Project to watch.
.PARAMETER Action
    Watch action: run, test, build.
.PARAMETER LaunchProfile
    Launch profile name.
.PARAMETER NoHotReload
    Disable hot reload.
.EXAMPLE
    Start-DotnetWatch -Action run -LaunchProfile Development
.EXAMPLE
    dnwatch test
#>
function Start-DotnetWatch {
    [CmdletBinding()]
    [OutputType([void])]
    param(
        [Parameter(Position = 0)]
        [ValidateSet('run', 'test', 'build')]
        [string]$Action = 'run',

        [Parameter()]
        [string]$Project,

        [Parameter()]
        [string]$LaunchProfile,

        [Parameter()]
        [switch]$NoHotReload
    )

    if (-not (Get-Command -Name 'dotnet' -ErrorAction SilentlyContinue)) {
        Write-Warning -Message 'dotnet CLI not found.'
        return
    }

    $args = @('watch', $Action)
    if (-not [string]::IsNullOrEmpty($Project)) { $args += @('--project', $Project) }
    if (-not [string]::IsNullOrEmpty($LaunchProfile)) { $args += @('--launch-profile', $LaunchProfile) }
    if ($NoHotReload) { $args += '--no-hot-reload' }

    Write-Host "  Starting dotnet watch $Action..." -ForegroundColor $script:Theme.Info
    & dotnet @args
}

#endregion

#region ── Assembly Inspector ──────────────────────────────────────────────────

<#
.SYNOPSIS
    Inspects a .NET assembly for metadata.
.PARAMETER Path
    Path to the .dll or .exe file.
.EXAMPLE
    Show-AssemblyInfo -Path .\bin\Release\MyApp.dll
#>
function Show-AssemblyInfo {
    [CmdletBinding()]
    [OutputType([void])]
    param(
        [Parameter(Mandatory, Position = 0)]
        [ValidateScript({ Test-Path -Path $_ })]
        [string]$Path
    )

    Write-Host "`n  Assembly Info" -ForegroundColor $script:Theme.Primary
    Write-Host "  $('─' * 50)" -ForegroundColor $script:Theme.Muted

    try {
        $bytes = [System.IO.File]::ReadAllBytes((Resolve-Path -Path $Path).Path)
        $assembly = [System.Reflection.Assembly]::Load($bytes)
        $name = $assembly.GetName()

        $props = [ordered]@{
            'Name'           = $name.Name
            'Version'        = $name.Version.ToString()
            'Culture'        = if ([string]::IsNullOrEmpty($name.CultureName)) { 'neutral' } else { $name.CultureName }
            'PublicKeyToken' = if ($name.GetPublicKeyToken().Count -gt 0) {
                ($name.GetPublicKeyToken() | ForEach-Object -Process { $_.ToString('x2') }) -join ''
            } else { '(none)' }
            'Runtime'        = $assembly.ImageRuntimeVersion
            'Types'          = $assembly.GetTypes().Count
            'File'           = Split-Path -Path $Path -Leaf
            'Size'           = "$('{0:N1}' -f ((Get-Item -Path $Path).Length / 1KB)) KB"
        }

        foreach ($key in $props.Keys) {
            Write-Host "  $($key.PadRight(18))" -ForegroundColor $script:Theme.Accent -NoNewline
            Write-Host "$($props[$key])" -ForegroundColor $script:Theme.Text
        }

        # Referenced assemblies
        $refs = $assembly.GetReferencedAssemblies()
        if ($refs.Count -gt 0) {
            Write-Host "`n  References ($($refs.Count)):" -ForegroundColor $script:Theme.Primary
            foreach ($ref in ($refs | Sort-Object -Property Name)) {
                Write-Host "    $($ref.Name.PadRight(40)) $($ref.Version)" -ForegroundColor $script:Theme.Muted
            }
        }
    }
    catch {
        Write-Warning -Message "Cannot load assembly: $($_.Exception.Message)"
    }
    Write-Host ''
}

#endregion

#region ── Project Scaffolding ────────────────────────────────────────────────

<#
.SYNOPSIS
    Quick dotnet new with common project setups.
.PARAMETER Template
    Project template.
.PARAMETER Name
    Project name.
.PARAMETER Framework
    Target framework.
.PARAMETER Output
    Output directory.
.EXAMPLE
    New-DotnetQuickProject -Template webapi -Name MyApi -Framework net9.0
.EXAMPLE
    dnnew classlib MyLib
#>
function New-DotnetQuickProject {
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([void])]
    param(
        [Parameter(Mandatory, Position = 0)]
        [string]$Template,

        [Parameter(Mandatory, Position = 1)]
        [string]$Name,

        [Parameter()]
        [string]$Framework,

        [Parameter()]
        [string]$Output
    )

    if (-not (Get-Command -Name 'dotnet' -ErrorAction SilentlyContinue)) {
        Write-Warning -Message 'dotnet CLI not found.'
        return
    }

    if (-not $PSCmdlet.ShouldProcess($Name, "dotnet new $Template")) { return }

    $args = @('new', $Template, '--name', $Name)
    if (-not [string]::IsNullOrEmpty($Framework)) { $args += @('--framework', $Framework) }
    if (-not [string]::IsNullOrEmpty($Output)) { $args += @('--output', $Output) }

    & dotnet @args 2>&1
    if ($LASTEXITCODE -eq 0) {
        Write-Host "  Created: $Name ($Template)" -ForegroundColor $script:Theme.Success
    }
}

#endregion

#region ── Coverage Report ────────────────────────────────────────────────────

<#
.SYNOPSIS
    Runs tests with coverage and shows summary.
.PARAMETER Project
    Test project path.
.PARAMETER MinCoverage
    Minimum coverage percentage to pass.
.EXAMPLE
    Invoke-DotnetCoverage -MinCoverage 80
#>
function Invoke-DotnetCoverage {
    [CmdletBinding()]
    [OutputType([void])]
    param(
        [Parameter()]
        [string]$Project,

        [Parameter()]
        [ValidateRange(0, 100)]
        [int]$MinCoverage = 0
    )

    if (-not (Get-Command -Name 'dotnet' -ErrorAction SilentlyContinue)) {
        Write-Warning -Message 'dotnet CLI not found.'
        return
    }

    $args = @('test')
    if (-not [string]::IsNullOrEmpty($Project)) { $args += $Project }
    $args += @('--collect:"XPlat Code Coverage"', '--results-directory', './TestResults')

    Write-Host "  Running tests with coverage..." -ForegroundColor $script:Theme.Info
    & dotnet @args 2>&1

    # Find and display coverage summary
    $coverageFiles = Get-ChildItem -Path './TestResults' -Filter 'coverage.cobertura.xml' -Recurse -ErrorAction SilentlyContinue |
        Sort-Object -Property LastWriteTime -Descending |
        Select-Object -First 1

    if ($null -ne $coverageFiles) {
        $xml = [xml](Get-Content -Path $coverageFiles.FullName)
        $lineRate = [math]::Round([double]$xml.coverage.'line-rate' * 100, 1)
        $branchRate = [math]::Round([double]$xml.coverage.'branch-rate' * 100, 1)

        $lineColor = if ($lineRate -ge 80) { $Global:Theme.Success } elseif ($lineRate -ge 60) { $Global:Theme.Warning } else { $Global:Theme.Error }
        $branchColor = if ($branchRate -ge 80) { $Global:Theme.Success } elseif ($branchRate -ge 60) { $Global:Theme.Warning } else { $Global:Theme.Error }

        Write-Host "`n  Coverage Summary:" -ForegroundColor $script:Theme.Primary
        Write-Host "    Line coverage:   $lineRate%" -ForegroundColor $lineColor
        Write-Host "    Branch coverage: $branchRate%" -ForegroundColor $branchColor

        if ($MinCoverage -gt 0 -and $lineRate -lt $MinCoverage) {
            Write-Host "    BELOW MINIMUM ($MinCoverage%)" -ForegroundColor $script:Theme.Error
        }
    }
    Write-Host ''
}

#endregion

#region ── Aliases ─────────────────────────────────────────────────────────────

Set-Alias -Name 'slnx'        -Value 'Show-DotnetSolution'       -Scope Global -Force
Set-Alias -Name 'nuget-tree'  -Value 'Show-NuGetDependencies'    -Scope Global -Force
Set-Alias -Name 'efm'         -Value 'Invoke-EFMigration'        -Scope Global -Force
Set-Alias -Name 'dnwatch'     -Value 'Start-DotnetWatch'         -Scope Global -Force
Set-Alias -Name 'asminfo'     -Value 'Show-AssemblyInfo'         -Scope Global -Force
Set-Alias -Name 'dnnew'       -Value 'New-DotnetQuickProject'    -Scope Global -Force
Set-Alias -Name 'dncov'       -Value 'Invoke-DotnetCoverage'     -Scope Global -Force

#endregion

#region ── Tab Completion ─────────────────────────────────────────────────────

Register-ArgumentCompleter -CommandName 'New-DotnetQuickProject' -ParameterName 'Template' -ScriptBlock {
    param($commandName, $parameterName, $wordToComplete, $commandAst, $fakeBoundParameters)

    @('console', 'classlib', 'webapi', 'web', 'mvc', 'razor', 'blazorserver', 'blazorwasm',
      'worker', 'grpc', 'xunit', 'nunit', 'mstest', 'wpf', 'winforms', 'maui') |
        Where-Object -FilterScript { $_ -like "${wordToComplete}*" } |
        ForEach-Object -Process {
            [System.Management.Automation.CompletionResult]::new($_, $_, 'ParameterValue', $_)
        }
}

#endregion

