[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingWriteHost', '', Justification = 'Update status display requires Write-Host')]
param()

#region ── Profile Auto-Updater ───────────────────────────────────────────────

<#
.SYNOPSIS
    Optional self-updating profile from a git repository.
    Checks for updates on shell startup (configurable frequency)
    and can pull updates with a single command.
#>

$script:UpdateCachePath = Join-Path -Path $script:ProfileRoot -ChildPath 'Cache' |
    Join-Path -ChildPath 'update-state.json'

$script:UpdateState = @{
    LastCheck       = $null
    LastUpdate      = $null
    RemoteUrl       = $null
    CurrentCommit   = $null
    UpdateAvailable = $false
}

# Load cached state
if (Test-Path -Path $script:UpdateCachePath) {
    try {
        $cached = Get-Content -Path $script:UpdateCachePath -Raw | ConvertFrom-Json
        $cached.PSObject.Properties | ForEach-Object -Process {
            $script:UpdateState[$_.Name] = $_.Value
        }
    }
    catch {
        # Silently continue with defaults
    }
}

function Save-UpdateState {
    <#
    .SYNOPSIS
        Persist update state to cache file.
    #>
    [CmdletBinding()]
    param()

    $script:UpdateState | ConvertTo-Json -Depth 3 |
        Set-Content -Path $script:UpdateCachePath -Encoding UTF8
}

function Initialize-ProfileRepo {
    <#
    .SYNOPSIS
        Initialize the profile directory as a git repo for auto-updates.
    .PARAMETER RemoteUrl
        Git remote URL to track for updates.
    .EXAMPLE
        Initialize-ProfileRepo -RemoteUrl 'https://github.com/c-man/powershell-profile.git'
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$RemoteUrl
    )

    $tc = $Global:Theme
    Push-Location -Path $script:ProfileRoot
    try {
        # Check if already a git repo
        $isRepo = & git rev-parse --is-inside-work-tree 2>$null
        if ($LASTEXITCODE -ne 0) {
            Write-Host -Object '  Initializing profile as git repo...' -ForegroundColor $tc.Info
            & git init
            & git remote add origin $RemoteUrl
        }
        else {
            # Update remote URL
            $existingRemote = & git remote get-url origin 2>$null
            if ($existingRemote -ne $RemoteUrl) {
                & git remote set-url origin $RemoteUrl
            }
        }

        $script:UpdateState.RemoteUrl = $RemoteUrl
        $script:UpdateState.CurrentCommit = & git rev-parse HEAD 2>$null
        Save-UpdateState

        Write-Host -Object "  Profile repo configured: $RemoteUrl" -ForegroundColor $tc.Success
    }
    finally {
        Pop-Location
    }
}

function Test-ProfileUpdate {
    <#
    .SYNOPSIS
        Check if profile updates are available from the remote repo.
    .PARAMETER Force
        Check even if within the cooldown period.
    #>
    [CmdletBinding()]
    [Alias('checkupdate')]
    param(
        [switch]$Force
    )

    $tc = $script:Theme

    # Verify this is a git repo
    Push-Location -Path $script:ProfileRoot
    try {
        $isRepo = & git rev-parse --is-inside-work-tree 2>$null
        if ($LASTEXITCODE -ne 0) {
            Write-Host -Object '  Profile is not a git repo. Use Initialize-ProfileRepo first.' -ForegroundColor $tc.Muted
            return $false
        }

        # Check cooldown (don't check more than once per hour unless forced)
        if (-not $Force -and $script:UpdateState.LastCheck) {
            $lastCheck = [DateTime]::Parse($script:UpdateState.LastCheck)
            if ((Get-Date) - $lastCheck -lt [TimeSpan]::FromHours(1)) {
                if ($script:UpdateState.UpdateAvailable) {
                    Write-Host -Object '  Update available (cached check).' -ForegroundColor $tc.Warning
                    return $true
                }
                return $false
            }
        }

        Write-Host -Object '  Checking for profile updates...' -ForegroundColor $tc.Muted

        # Fetch without merging
        & git fetch origin --quiet 2>$null
        if ($LASTEXITCODE -ne 0) {
            Write-Host -Object '  Could not reach remote. Skipping update check.' -ForegroundColor $tc.Muted
            return $false
        }

        # Compare local vs remote
        $localHead = & git rev-parse HEAD 2>$null
        $remoteHead = & git rev-parse 'origin/main' 2>$null
        if ($LASTEXITCODE -ne 0) {
            $remoteHead = & git rev-parse 'origin/master' 2>$null
        }

        $script:UpdateState.LastCheck = (Get-Date).ToString('o')
        $script:UpdateState.CurrentCommit = $localHead

        if ($localHead -ne $remoteHead -and $remoteHead) {
            $behind = & git rev-list --count HEAD..origin/main 2>$null
            if ($LASTEXITCODE -ne 0) {
                $behind = & git rev-list --count HEAD..origin/master 2>$null
            }

            $script:UpdateState.UpdateAvailable = $true
            Save-UpdateState

            Write-Host -Object "  Profile update available ($behind commits behind)." -ForegroundColor $tc.Warning
            Write-Host -Object '  Run Update-Profile to apply.' -ForegroundColor $tc.Info
            return $true
        }
        else {
            $script:UpdateState.UpdateAvailable = $false
            Save-UpdateState
            Write-Host -Object '  Profile is up to date.' -ForegroundColor $tc.Success
            return $false
        }
    }
    finally {
        Pop-Location
    }
}

function Update-Profile {
    <#
    .SYNOPSIS
        Pull latest profile changes from the remote git repo.
    .PARAMETER Force
        Force update even with local changes (stashes them first).
    .PARAMETER DryRun
        Show what would change without applying.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [switch]$Force,

        [switch]$DryRun
    )

    $tc = $Global:Theme

    Push-Location -Path $script:ProfileRoot
    try {
        $isRepo = & git rev-parse --is-inside-work-tree 2>$null
        if ($LASTEXITCODE -ne 0) {
            Write-Warning -Message 'Profile is not a git repo. Use Initialize-ProfileRepo first.'
            return
        }

        # Check for local changes
        $localChanges = & git status --porcelain 2>$null
        if ($localChanges -and -not $Force) {
            Write-Host -Object '  Local profile changes detected:' -ForegroundColor $tc.Warning
            $localChanges | ForEach-Object -Process {
                Write-Host -Object "    $_" -ForegroundColor $tc.Muted
            }
            Write-Host -Object '  Use -Force to stash and update, or commit your changes first.' -ForegroundColor $tc.Info
            return
        }

        if ($DryRun) {
            & git fetch origin --quiet 2>$null
            $mainBranch = 'main'
            $branchExists = & git rev-parse --verify "origin/$mainBranch" 2>$null
            if ($LASTEXITCODE -ne 0) { $mainBranch = 'master' }

            Write-Host -Object "`n  Changes that would be applied:" -ForegroundColor $tc.Primary
            & git log --oneline "HEAD..origin/$mainBranch" 2>$null | ForEach-Object -Process {
                Write-Host -Object "    $_" -ForegroundColor $tc.Text
            }
            return
        }

        if ($PSCmdlet.ShouldProcess('Profile', 'Pull latest changes')) {
            # Stash local changes if forcing
            $stashed = $false
            if ($localChanges -and $Force) {
                Write-Host -Object '  Stashing local changes...' -ForegroundColor $tc.Warning
                & git stash push -m "Auto-stash before profile update $(Get-Date -Format 'yyyy-MM-dd HH:mm')"
                $stashed = $true
            }

            # Pull changes
            Write-Host -Object '  Pulling updates...' -ForegroundColor $tc.Info
            $pullOutput = & git pull origin 2>&1
            $pullExitCode = $LASTEXITCODE

            if ($pullExitCode -eq 0) {
                $script:UpdateState.LastUpdate = (Get-Date).ToString('o')
                $script:UpdateState.UpdateAvailable = $false
                $script:UpdateState.CurrentCommit = & git rev-parse HEAD 2>$null
                Save-UpdateState

                Write-Host -Object '  Profile updated successfully.' -ForegroundColor $tc.Success
                Write-Host -Object '  Restart your shell to apply changes.' -ForegroundColor $tc.Info
            }
            else {
                Write-Host -Object '  Update failed:' -ForegroundColor $tc.Error
                Write-Host -Object "  $pullOutput" -ForegroundColor $tc.Muted
            }

            # Restore stashed changes
            if ($stashed) {
                Write-Host -Object '  Restoring local changes...' -ForegroundColor $tc.Info
                & git stash pop
            }
        }
    }
    finally {
        Pop-Location
    }
}

function Get-ProfileDiff {
    <#
    .SYNOPSIS
        Show what changed between current profile and last update, or between
        current state and remote.
    .PARAMETER Remote
        Compare against remote instead of last commit.
    #>
    [CmdletBinding()]
    [Alias('pdiff')]
    param(
        [switch]$Remote
    )

    $tc = $script:Theme
    Push-Location -Path $script:ProfileRoot
    try {
        $isRepo = & git rev-parse --is-inside-work-tree 2>$null
        if ($LASTEXITCODE -ne 0) {
            Write-Warning -Message 'Profile is not a git repo.'
            return
        }

        if ($Remote) {
            & git fetch origin --quiet 2>$null
            $mainBranch = 'main'
            $branchExists = & git rev-parse --verify "origin/$mainBranch" 2>$null
            if ($LASTEXITCODE -ne 0) { $mainBranch = 'master' }
            $diff = & git diff "HEAD..origin/$mainBranch" --stat 2>$null
        }
        else {
            $diff = & git diff --stat 2>$null
        }

        if ($diff) {
            Write-Host -Object "`n  Profile Changes:" -ForegroundColor $tc.Primary
            $diff | ForEach-Object -Process {
                if ($_ -match '\+') {
                    Write-Host -Object "    $_" -ForegroundColor $tc.Success
                }
                elseif ($_ -match '-') {
                    Write-Host -Object "    $_" -ForegroundColor $tc.Error
                }
                else {
                    Write-Host -Object "    $_" -ForegroundColor $tc.Text
                }
            }
        }
        else {
            Write-Host -Object '  No changes detected.' -ForegroundColor $tc.Muted
        }
    }
    finally {
        Pop-Location
    }
    Write-Host ''
}

function Get-ProfileVersion {
    <#
    .SYNOPSIS
        Display current profile version info (commit, date, remote).
    #>
    [CmdletBinding()]
    [Alias('pversion')]
    param()

    $tc = $script:Theme
    Push-Location -Path $script:ProfileRoot
    try {
        $isRepo = & git rev-parse --is-inside-work-tree 2>$null
        if ($LASTEXITCODE -ne 0) {
            Write-Host -Object '  Profile: Not version controlled' -ForegroundColor $tc.Muted
            return
        }

        $commit = & git rev-parse --short HEAD 2>$null
        $commitDate = & git log -1 --format='%ci' 2>$null
        $branch = & git rev-parse --abbrev-ref HEAD 2>$null
        $remote = & git remote get-url origin 2>$null

        Write-Host -Object "`n  Profile Version:" -ForegroundColor $tc.Primary
        Write-Host -Object "    Commit:  $commit" -ForegroundColor $tc.Text
        Write-Host -Object "    Date:    $commitDate" -ForegroundColor $tc.Text
        Write-Host -Object "    Branch:  $branch" -ForegroundColor $tc.Accent
        if ($remote) {
            Write-Host -Object "    Remote:  $remote" -ForegroundColor $tc.Muted
        }
        if ($script:UpdateState.LastCheck) {
            Write-Host -Object "    Checked: $($script:UpdateState.LastCheck)" -ForegroundColor $tc.Muted
        }
    }
    finally {
        Pop-Location
    }
    Write-Host ''
}

#endregion

