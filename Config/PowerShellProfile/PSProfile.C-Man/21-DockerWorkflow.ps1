<#
.SYNOPSIS
    Docker Workflow module for C-Man's PowerShell Profile.
.DESCRIPTION
    Compose project manager, container health dashboard, image cleanup/prune
    scheduler, volume inspector, build cache analyzer, multi-stage build
    helpers, and Dockerfile linter wrapper.
.NOTES
    Module: 21-DockerWorkflow.ps1
    Requires: PowerShell 5.1+, Docker or Podman
#>

#region ── Helpers ─────────────────────────────────────────────────────────────

function Get-ContainerRuntime {
    [CmdletBinding()]
    [OutputType([string])]
    param()

    if (Get-Command -Name 'docker' -ErrorAction SilentlyContinue) { return 'docker' }
    if (Get-Command -Name 'podman' -ErrorAction SilentlyContinue) { return 'podman' }
    return $null
}

function Invoke-ContainerCommand {
    [CmdletBinding()]
    [OutputType([string[]])]
    param(
        [Parameter(Mandatory)]
        [string[]]$Arguments
    )

    $runtime = Get-ContainerRuntime
    if ($null -eq $runtime) {
        Write-Warning -Message 'No container runtime found (docker/podman).'
        return @()
    }
    return @(& $runtime @Arguments 2>&1)
}

#endregion

#region ── Container Dashboard ────────────────────────────────────────────────

<#
.SYNOPSIS
    Displays a live container health dashboard.
.DESCRIPTION
    Shows all containers with status, health, CPU/memory usage, ports,
    and uptime in a color-coded table format.
.PARAMETER All
    Include stopped containers.
.EXAMPLE
    Show-ContainerDashboard
.EXAMPLE
    cdash -All
#>
function Show-ContainerDashboard {
    [CmdletBinding()]
    [OutputType([void])]
    param(
        [Parameter()]
        [switch]$All
    )

    $runtime = Get-ContainerRuntime
    if ($null -eq $runtime) { Write-Warning -Message 'No container runtime found.'; return }

    Write-Host "`n  Container Dashboard ($runtime)" -ForegroundColor $script:Theme.Primary
    Write-Host "  $('â•' * 70)" -ForegroundColor $script:Theme.Muted

    $format = '{{.ID}}|{{.Names}}|{{.Image}}|{{.Status}}|{{.Ports}}|{{.Size}}'
    $args = @('ps', '--format', $format, '--no-trunc')
    if ($All) { $args += '-a' }

    $containers = @(& $runtime @args 2>$null)

    if ($containers.Count -eq 0) {
        Write-Host '  No containers found.' -ForegroundColor $Global:Theme.Muted
        return
    }

    foreach ($line in $containers) {
        $parts = $line -Split '\|', 6
        if ($parts.Count -lt 4) { continue }

        $id = $parts[0].Substring(0, [math]::Min(12, $parts[0].Length))
        $name = $parts[1]
        $image = $parts[2]
        if ($image.Length -gt 25) { $image = $image.Substring(0, 22) + '...' }
        $status = $parts[3]
        $ports = if ($parts.Count -ge 5) { $parts[4] } else { '' }
        if ($ports.Length -gt 30) { $ports = $ports.Substring(0, 27) + '...' }

        $isRunning = $status -match '^Up'
        $isHealthy = $status -match 'healthy'
        $isUnhealthy = $status -match 'unhealthy'

        $statusIcon = if ($isUnhealthy) { '!!' } elseif ($isHealthy) { '✓' } elseif ($isRunning) { 'â–¶' } else { 'â– ' }
        $statusColor = if ($isUnhealthy) { $Global:Theme.Error } elseif ($isRunning) { $Global:Theme.Success } else { $Global:Theme.Muted }

        Write-Host "  $statusIcon " -ForegroundColor $statusColor -NoNewline
        Write-Host "$($id.PadRight(14))" -ForegroundColor $script:Theme.Accent -NoNewline
        Write-Host "$($name.PadRight(22))" -ForegroundColor $script:Theme.Text -NoNewline
        Write-Host "$($image.PadRight(27))" -ForegroundColor $script:Theme.Muted -NoNewline

        $statusShort = if ($status.Length -gt 18) { $status.Substring(0, 15) + '...' } else { $status }
        Write-Host "$statusShort" -ForegroundColor $statusColor
        if (-not [string]::IsNullOrEmpty($ports)) {
            Write-Host "           Ports: $ports" -ForegroundColor $script:Theme.Muted
        }
    }

    # Stats summary
    $statsArgs = @('stats', '--no-stream', '--format', '{{.Name}}|{{.CPUPerc}}|{{.MemUsage}}')
    $stats = @(& $runtime @statsArgs 2>$null)
    if ($stats.Count -gt 0) {
        Write-Host "`n  Resource Usage:" -ForegroundColor $script:Theme.Primary
        foreach ($stat in $stats) {
            $sp = $stat -Split '\|'
            if ($sp.Count -lt 3) { continue }
            $cpuVal = $sp[1] -replace '%', ''
            $cpuColor = if ([double]::TryParse($cpuVal, [ref]$null) -and [double]$cpuVal -gt 80) { $Global:Theme.Error }
                elseif ([double]::TryParse($cpuVal, [ref]$null) -and [double]$cpuVal -gt 50) { $Global:Theme.Warning }
                else { $Global:Theme.Success }

            Write-Host "    $($sp[0].PadRight(22))" -ForegroundColor $script:Theme.Text -NoNewline
            Write-Host "CPU: $($sp[1].PadRight(10))" -ForegroundColor $cpuColor -NoNewline
            Write-Host "Mem: $($sp[2])" -ForegroundColor $script:Theme.Muted
        }
    }
    Write-Host ''
}

#endregion

#region ── Image Management ───────────────────────────────────────────────────

<#
.SYNOPSIS
    Shows container images with size analysis.
.PARAMETER Dangling
    Show only dangling (untagged) images.
.PARAMETER SortBy
    Sort images by 'size' or 'date'.
.EXAMPLE
    Show-ContainerImages -SortBy size
#>
function Show-ContainerImages {
    [CmdletBinding()]
    [OutputType([void])]
    param(
        [Parameter()]
        [switch]$Dangling,

        [Parameter()]
        [ValidateSet('size', 'date', 'name')]
        [string]$SortBy = 'date'
    )

    $runtime = Get-ContainerRuntime
    if ($null -eq $runtime) { Write-Warning -Message 'No container runtime found.'; return }

    Write-Host "`n  Container Images" -ForegroundColor $script:Theme.Primary
    Write-Host "  $('─' * 70)" -ForegroundColor $script:Theme.Muted

    $format = '{{.Repository}}:{{.Tag}}|{{.ID}}|{{.Size}}|{{.CreatedSince}}'
    $args = @('images', '--format', $format)
    if ($Dangling) { $args += @('--filter', 'dangling=true') }

    $images = @(& $runtime @args 2>$null)

    if ($images.Count -eq 0) {
        Write-Host '  No images found.' -ForegroundColor $Global:Theme.Muted
        return
    }

    foreach ($line in $images) {
        $parts = $line -Split '\|'
        if ($parts.Count -lt 4) { continue }

        $repo = $parts[0]
        if ($repo.Length -gt 40) { $repo = $repo.Substring(0, 37) + '...' }
        $id = $parts[1].Substring(0, [math]::Min(12, $parts[1].Length))
        $size = $parts[2]
        $age = $parts[3]

        Write-Host "  $($repo.PadRight(42))" -ForegroundColor $script:Theme.Text -NoNewline
        Write-Host "$($id.PadRight(14))" -ForegroundColor $script:Theme.Accent -NoNewline
        Write-Host "$($size.PadRight(12))" -ForegroundColor $script:Theme.Warning -NoNewline
        Write-Host "$age" -ForegroundColor $script:Theme.Muted
    }

    # Total size
    $totalOutput = Invoke-ContainerCommand -Arguments @('system', 'df', '--format', '{{.Type}}\t{{.TotalCount}}\t{{.Size}}')
    if ($totalOutput.Count -gt 0) {
        Write-Host "`n  Disk Usage:" -ForegroundColor $script:Theme.Primary
        foreach ($line in $totalOutput) {
            Write-Host "    $line" -ForegroundColor $script:Theme.Muted
        }
    }
    Write-Host ''
}

<#
.SYNOPSIS
    Performs intelligent image cleanup.
.DESCRIPTION
    Removes dangling images, stopped containers, unused networks, and
    optionally build cache. Shows space reclaimed.
.PARAMETER IncludeBuildCache
    Also prune build cache.
.PARAMETER DryRun
    Show what would be removed without removing.
.PARAMETER Force
    Skip confirmation prompts.
.EXAMPLE
    Invoke-ContainerCleanup -IncludeBuildCache
.EXAMPLE
    dclean -Force
#>
function Invoke-ContainerCleanup {
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([void])]
    param(
        [Parameter()]
        [switch]$IncludeBuildCache,

        [Parameter()]
        [switch]$DryRun,

        [Parameter()]
        [switch]$Force
    )

    $runtime = Get-ContainerRuntime
    if ($null -eq $runtime) { Write-Warning -Message 'No container runtime found.'; return }

    Write-Host "`n  Container Cleanup ($runtime)" -ForegroundColor $script:Theme.Primary
    Write-Host "  $('─' * 50)" -ForegroundColor $script:Theme.Muted

    # Check what would be cleaned
    $danglingImages = @(& $runtime images -f 'dangling=true' -q 2>$null)
    $stoppedContainers = @(& $runtime ps -a -f 'status=exited' -q 2>$null)
    $unusedVolumes = @(& $runtime volume ls -f 'dangling=true' -q 2>$null)

    Write-Host "  Dangling images:      $($danglingImages.Count)" -ForegroundColor $script:Theme.Warning
    Write-Host "  Stopped containers:   $($stoppedContainers.Count)" -ForegroundColor $script:Theme.Warning
    Write-Host "  Unused volumes:       $($unusedVolumes.Count)" -ForegroundColor $script:Theme.Warning

    if ($DryRun) {
        Write-Host "`n  (dry run - no changes made)" -ForegroundColor $script:Theme.Info
        return
    }

    $total = $danglingImages.Count + $stoppedContainers.Count + $unusedVolumes.Count
    if ($total -eq 0 -and -not $IncludeBuildCache) {
        Write-Host '  Nothing to clean.' -ForegroundColor $Global:Theme.Success
        return
    }

    if (-not $Force) {
        $confirm = Read-Host -Prompt "`n  Proceed with cleanup? (y/N)"
        if ($confirm -notmatch '^[yY]') {
            Write-Host '  Aborted.' -ForegroundColor $script:Theme.Muted
            return
        }
    }

    if ($PSCmdlet.ShouldProcess('containers and images', 'Prune')) {
        $pruneArgs = @('system', 'prune', '-f')
        if ($IncludeBuildCache) { $pruneArgs += '--volumes' }

        $output = & $runtime @pruneArgs 2>&1
        foreach ($line in $output) {
            if ($line -match 'reclaimed|deleted|removed') {
                Write-Host "  $line" -ForegroundColor $script:Theme.Success
            }
        }
    }
}

#endregion

#region ── Compose Management ─────────────────────────────────────────────────

<#
.SYNOPSIS
    Shows compose project status across directories.
.DESCRIPTION
    Finds docker-compose files in the current directory or specified
    path and shows service status for each project.
.PARAMETER Path
    Directory to scan for compose files.
.EXAMPLE
    Show-ComposeProjects
#>
function Show-ComposeProjects {
    [CmdletBinding()]
    [OutputType([void])]
    param(
        [Parameter(Position = 0)]
        [string]$Path = (Get-Location).Path
    )

    $runtime = Get-ContainerRuntime
    if ($null -eq $runtime) { Write-Warning -Message 'No container runtime found.'; return }

    Write-Host "`n  Compose Projects" -ForegroundColor $script:Theme.Primary
    Write-Host "  $('─' * 60)" -ForegroundColor $script:Theme.Muted

    $composeFiles = Get-ChildItem -Path $Path -Include 'docker-compose.yml', 'docker-compose.yaml', 'compose.yml', 'compose.yaml' -Recurse -Depth 3 -ErrorAction SilentlyContinue

    if ($composeFiles.Count -eq 0) {
        Write-Host '  No compose files found.' -ForegroundColor $Global:Theme.Muted
        return
    }

    foreach ($file in $composeFiles) {
        $projectDir = Split-Path -Path $file.FullName -Parent
        $projectName = Split-Path -Path $projectDir -Leaf

        Write-Host "`n  [$projectName] " -ForegroundColor $script:Theme.Accent -NoNewline
        Write-Host $file.FullName -ForegroundColor $Global:Theme.Muted

        $compose = if ($runtime -eq 'docker') { 'docker compose' } else { 'podman-compose' }
        $status = & $runtime compose -f $file.FullName ps --format 'table {{.Name}}\t{{.Status}}\t{{.Ports}}' 2>$null

        if ($null -ne $status -and $status.Count -gt 0) {
            foreach ($line in $status) {
                $color = if ($line -match 'running|Up') { $Global:Theme.Success }
                    elseif ($line -match 'exited|Exit') { $Global:Theme.Error }
                    else { $Global:Theme.Text }
                Write-Host "    $line" -ForegroundColor $color
            }
        }
        else {
            Write-Host '    (not running)' -ForegroundColor $script:Theme.Muted
        }
    }
    Write-Host ''
}

<#
.SYNOPSIS
    Quick compose operations on the current directory.
.PARAMETER Action
    Compose action to perform.
.PARAMETER Service
    Specific service name (optional).
.PARAMETER Detach
    Run in detached mode for 'up'.
.EXAMPLE
    Invoke-ComposeAction -Action up -Detach
.EXAMPLE
    dca down
#>
function Invoke-ComposeAction {
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([void])]
    param(
        [Parameter(Mandatory, Position = 0)]
        [ValidateSet('up', 'down', 'restart', 'stop', 'start', 'logs', 'build', 'pull', 'ps')]
        [string]$Action,

        [Parameter(Position = 1)]
        [string]$Service,

        [Parameter()]
        [switch]$Detach
    )

    $runtime = Get-ContainerRuntime
    if ($null -eq $runtime) { Write-Warning -Message 'No container runtime found.'; return }

    $composeFile = @('docker-compose.yml', 'docker-compose.yaml', 'compose.yml', 'compose.yaml') |
        ForEach-Object -Process { Join-Path -Path (Get-Location).Path -ChildPath $_ } |
        Where-Object -FilterScript { Test-Path -Path $_ } |
        Select-Object -First 1

    if ($null -eq $composeFile) {
        Write-Warning -Message 'No compose file found in current directory.'
        return
    }

    if (-not $PSCmdlet.ShouldProcess($composeFile, "compose $Action")) { return }

    $args = @('compose', '-f', $composeFile, $Action)
    if ($Action -eq 'up' -and $Detach) { $args += '-d' }
    if ($Action -eq 'logs') { $args += @('--tail', '50', '-f') }
    if (-not [string]::IsNullOrEmpty($Service)) { $args += $Service }

    & $runtime @args
}

#endregion

#region ── Volume Inspector ───────────────────────────────────────────────────

<#
.SYNOPSIS
    Inspects container volumes with size and mount info.
.EXAMPLE
    Show-ContainerVolumes
#>
function Show-ContainerVolumes {
    [CmdletBinding()]
    [OutputType([void])]
    param()

    $runtime = Get-ContainerRuntime
    if ($null -eq $runtime) { Write-Warning -Message 'No container runtime found.'; return }

    Write-Host "`n  Container Volumes" -ForegroundColor $script:Theme.Primary
    Write-Host "  $('─' * 60)" -ForegroundColor $script:Theme.Muted

    $format = '{{.Name}}|{{.Driver}}|{{.Mountpoint}}'
    $volumes = @(& $runtime volume ls --format $format 2>$null)

    if ($volumes.Count -eq 0) {
        Write-Host '  No volumes found.' -ForegroundColor $Global:Theme.Muted
        return
    }

    foreach ($vol in $volumes) {
        $parts = $vol -Split '\|'
        if ($parts.Count -lt 3) { continue }
        $name = $parts[0]
        if ($name.Length -gt 35) { $name = $name.Substring(0, 32) + '...' }
        $driver = $parts[1]
        $mount = $parts[2]

        Write-Host "  $($name.PadRight(37))" -ForegroundColor $script:Theme.Accent -NoNewline
        Write-Host "$($driver.PadRight(10))" -ForegroundColor $script:Theme.Text -NoNewline
        Write-Host "$mount" -ForegroundColor $script:Theme.Muted
    }
    Write-Host ''
}

#endregion

#region ── Container Logs & Exec ──────────────────────────────────────────────

<#
.SYNOPSIS
    Tails container logs with optional filtering.
.PARAMETER Container
    Container name or ID.
.PARAMETER Lines
    Number of lines to tail. Default is 50.
.PARAMETER Follow
    Follow log output.
.PARAMETER Filter
    Grep-style filter pattern.
.EXAMPLE
    Get-ContainerLogs -Container myapp -Lines 100 -Follow
#>
function Get-ContainerLogs {
    [CmdletBinding()]
    [OutputType([void])]
    param(
        [Parameter(Mandatory, Position = 0)]
        [string]$Container,

        [Parameter()]
        [ValidateRange(1, 10000)]
        [int]$Lines = 50,

        [Parameter()]
        [switch]$Follow,

        [Parameter()]
        [string]$Filter
    )

    $runtime = Get-ContainerRuntime
    if ($null -eq $runtime) { Write-Warning -Message 'No container runtime found.'; return }

    $args = @('logs', '--tail', $Lines.ToString())
    if ($Follow) { $args += '-f' }
    $args += $Container

    if (-not [string]::IsNullOrEmpty($Filter)) {
        & $runtime @args 2>&1 | Where-Object -FilterScript { $_ -match $Filter }
    }
    else {
        & $runtime @args 2>&1
    }
}

<#
.SYNOPSIS
    Enters a running container with an interactive shell.
.PARAMETER Container
    Container name or ID.
.PARAMETER Shell
    Shell to use. Default auto-detects (bash, sh).
.PARAMETER User
    User to exec as.
.EXAMPLE
    Enter-Container -Container myapp
.EXAMPLE
    cexec myapp
#>
function Enter-Container {
    [CmdletBinding()]
    [OutputType([void])]
    param(
        [Parameter(Mandatory, Position = 0)]
        [string]$Container,

        [Parameter()]
        [ValidateSet('bash', 'sh', 'zsh', 'powershell', 'cmd')]
        [string]$Shell,

        [Parameter()]
        [string]$User
    )

    $runtime = Get-ContainerRuntime
    if ($null -eq $runtime) { Write-Warning -Message 'No container runtime found.'; return }

    if ([string]::IsNullOrEmpty($Shell)) {
        # Auto-detect shell
        $bashCheck = & $runtime exec $Container which bash 2>$null
        $Shell = if ($LASTEXITCODE -eq 0) { 'bash' } else { 'sh' }
    }

    $args = @('exec', '-it')
    if (-not [string]::IsNullOrEmpty($User)) { $args += @('-u', $User) }
    $args += @($Container, $Shell)

    & $runtime @args
}

#endregion

#region ── Build Helpers ──────────────────────────────────────────────────────

<#
.SYNOPSIS
    Analyzes build cache usage and layer sizes.
.EXAMPLE
    Show-BuildCacheAnalysis
#>
function Show-BuildCacheAnalysis {
    [CmdletBinding()]
    [OutputType([void])]
    param()

    $runtime = Get-ContainerRuntime
    if ($null -eq $runtime) { Write-Warning -Message 'No container runtime found.'; return }

    Write-Host "`n  Build Cache Analysis" -ForegroundColor $script:Theme.Primary
    Write-Host "  $('─' * 50)" -ForegroundColor $script:Theme.Muted

    $df = @(& $runtime system df -v 2>$null)
    $inBuildCache = $false

    foreach ($line in $df) {
        if ($line -match 'Build cache') {
            $inBuildCache = $true
            Write-Host "  $line" -ForegroundColor $script:Theme.Accent
            continue
        }
        if ($inBuildCache) {
            if ([string]::IsNullOrWhiteSpace($line) -or $line -match '^[A-Z]') {
                $inBuildCache = $false
                continue
            }
            Write-Host "  $line" -ForegroundColor $script:Theme.Muted
        }
    }

    $dfSummary = @(& $runtime system df 2>$null)
    if ($dfSummary.Count -gt 0) {
        Write-Host "`n  Summary:" -ForegroundColor $script:Theme.Primary
        foreach ($line in $dfSummary) {
            Write-Host "    $line" -ForegroundColor $script:Theme.Text
        }
    }
    Write-Host ''
}

<#
.SYNOPSIS
    Shows the layer history of a container image.
.PARAMETER Image
    Image name or ID.
.EXAMPLE
    Show-ImageLayers -Image myapp:latest
#>
function Show-ImageLayers {
    [CmdletBinding()]
    [OutputType([void])]
    param(
        [Parameter(Mandatory, Position = 0)]
        [string]$Image
    )

    $runtime = Get-ContainerRuntime
    if ($null -eq $runtime) { Write-Warning -Message 'No container runtime found.'; return }

    Write-Host "`n  Image Layers: $Image" -ForegroundColor $script:Theme.Primary
    Write-Host "  $('─' * 60)" -ForegroundColor $script:Theme.Muted

    $format = '{{.CreatedBy}}|{{.Size}}'
    $history = @(& $runtime history --no-trunc --format $format $Image 2>$null)

    foreach ($line in $history) {
        $parts = $line -Split '\|'
        if ($parts.Count -lt 2) { continue }
        $cmd = $parts[0]
        if ($cmd.Length -gt 60) { $cmd = $cmd.Substring(0, 57) + '...' }
        $size = $parts[1]

        $sizeColor = if ($size -match '[0-9]+[MG]B' -and $size -notmatch '^0') { $Global:Theme.Warning } else { $Global:Theme.Muted }
        Write-Host "  $($size.PadRight(12))" -ForegroundColor $sizeColor -NoNewline
        Write-Host "$cmd" -ForegroundColor $script:Theme.Text
    }
    Write-Host ''
}

#endregion

#region ── Aliases ─────────────────────────────────────────────────────────────

Set-Alias -Name 'cdash'     -Value 'Show-ContainerDashboard'  -Scope Global -Force
Set-Alias -Name 'cimages'   -Value 'Show-ContainerImages'     -Scope Global -Force
Set-Alias -Name 'dclean'    -Value 'Invoke-ContainerCleanup'  -Scope Global -Force
Set-Alias -Name 'dprojects' -Value 'Show-ComposeProjects'     -Scope Global -Force
Set-Alias -Name 'dca'       -Value 'Invoke-ComposeAction'     -Scope Global -Force
Set-Alias -Name 'dvols'     -Value 'Show-ContainerVolumes'    -Scope Global -Force
Set-Alias -Name 'clogs'     -Value 'Get-ContainerLogs'        -Scope Global -Force
Set-Alias -Name 'cexec'     -Value 'Enter-Container'          -Scope Global -Force
Set-Alias -Name 'dlayers'   -Value 'Show-ImageLayers'         -Scope Global -Force
Set-Alias -Name 'dcache'    -Value 'Show-BuildCacheAnalysis'  -Scope Global -Force

#endregion

#region ── Tab Completion ─────────────────────────────────────────────────────

$containerNameCompleter = {
    param($commandName, $parameterName, $wordToComplete, $commandAst, $fakeBoundParameters)

    $runtime = Get-ContainerRuntime
    if ($null -eq $runtime) { return }

    $names = @(& $runtime ps -a --format '{{.Names}}' 2>$null)
    $names | Where-Object -FilterScript { $_ -like "${wordToComplete}*" } | ForEach-Object -Process {
        [System.Management.Automation.CompletionResult]::new($_, $_, 'ParameterValue', $_)
    }
}

Register-ArgumentCompleter -CommandName @('Get-ContainerLogs', 'Enter-Container') -ParameterName 'Container' -ScriptBlock $containerNameCompleter

$imageNameCompleter = {
    param($commandName, $parameterName, $wordToComplete, $commandAst, $fakeBoundParameters)

    $runtime = Get-ContainerRuntime
    if ($null -eq $runtime) { return }

    $images = @(& $runtime images --format '{{.Repository}}:{{.Tag}}' 2>$null)
    $images | Where-Object -FilterScript { $_ -like "${wordToComplete}*" -and $_ -ne '<none>:<none>' } | ForEach-Object -Process {
        [System.Management.Automation.CompletionResult]::new($_, $_, 'ParameterValue', $_)
    }
}

Register-ArgumentCompleter -CommandName 'Show-ImageLayers' -ParameterName 'Image' -ScriptBlock $imageNameCompleter

#endregion

