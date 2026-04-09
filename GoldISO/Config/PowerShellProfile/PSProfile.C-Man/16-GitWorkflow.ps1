<#
.SYNOPSIS
    Git Workflow Automation module for C-Man's PowerShell Profile.
.DESCRIPTION
    Provides interactive branch cleanup, PR drafting from terminal,
    conventional commit builder, merge conflict resolver helpers,
    stash manager with descriptions, and worktree shortcuts.
.NOTES
    Module: 16-GitWorkflow.ps1
    Requires: PowerShell 5.1+, Git
#>

#region -- Helpers -------------------------------------------------------------

function Test-GitRepo {
    [CmdletBinding()]
    [OutputType([bool])]
    param()

    $result = & git rev-parse --is-inside-work-tree 2>&1
    return ($LASTEXITCODE -eq 0 -and $result -eq 'true')
}

function Get-GitCurrentBranch {
    [CmdletBinding()]
    [OutputType([string])]
    param()

    return (& git branch --show-current 2>$null)
}

function Get-GitDefaultBranch {
    [CmdletBinding()]
    [OutputType([string])]
    param()

    $remote = & git remote 2>$null | Select-Object -First 1
    if ([string]::IsNullOrEmpty($remote)) { $remote = 'origin' }

    $head = & git symbolic-ref "refs/remotes/$remote/HEAD" 2>$null
    if ($head -match '/(\w+)$') {
        return $Matches[1]
    }

    foreach ($candidate in @('main', 'master', 'develop')) {
        $exists = & git show-ref --verify "refs/heads/$candidate" 2>$null
        if ($LASTEXITCODE -eq 0) { return $candidate }
    }

    return 'main'
}

function Get-GitRemoteUrl {
    [CmdletBinding()]
    [OutputType([string])]
    param()

    $url = & git remote get-url origin 2>$null
    if ($url -match 'github\.com[:/](.+?)(?:\.git)?$') {
        return "https://github.com/$($Matches[1])"
    }
    if ($url -match 'dev\.azure\.com[:/](.+?)(?:\.git)?$') {
        return "https://dev.azure.com/$($Matches[1])"
    }
    return $url
}

#endregion

#region -- Conventional Commit Builder ----------------------------------------

<#
.SYNOPSIS
    Builds a conventional commit message interactively.
.DESCRIPTION
    Prompts for commit type, scope, description, body, and breaking change
    flag. Produces a message following the Conventional Commits specification.
.PARAMETER Type
    Commit type (feat, fix, docs, style, refactor, perf, test, build, ci, chore).
.PARAMETER Scope
    Optional scope for the commit.
.PARAMETER Description
    Short commit description.
.PARAMETER Body
    Optional long-form body.
.PARAMETER BreakingChange
    Mark as a breaking change.
.PARAMETER Execute
    Actually run git commit with the built message.
.EXAMPLE
    New-ConventionalCommit -Type feat -Scope auth -Description 'add OAuth2 flow' -Execute
.EXAMPLE
    ccommit
#>
function New-ConventionalCommit {
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([string])]
    param(
        [Parameter(Position = 0)]
        [ValidateSet('feat', 'fix', 'docs', 'style', 'refactor', 'perf', 'test', 'build', 'ci', 'chore')]
        [string]$Type,

        [Parameter(Position = 1)]
        [string]$Scope,

        [Parameter(Position = 2)]
        [string]$Description,

        [Parameter()]
        [string]$Body,

        [Parameter()]
        [switch]$BreakingChange,

        [Parameter()]
        [switch]$Execute
    )

    if (-not (Test-GitRepo)) {
        Write-Warning -Message 'Not in a git repository.'
        return
    }

    # Interactive mode if parameters not provided
    if ([string]::IsNullOrEmpty($Type)) {
        Write-Host "`n  Conventional Commit Builder" -ForegroundColor $Global:Theme.Primary
        Write-Host "  $('-' * 50)" -ForegroundColor $Global:Theme.Muted

        $types = @(
            @{ Key = 'feat';     Desc = 'A new feature' }
            @{ Key = 'fix';      Desc = 'A bug fix' }
            @{ Key = 'docs';     Desc = 'Documentation only' }
            @{ Key = 'style';    Desc = 'Code style (formatting, semicolons)' }
            @{ Key = 'refactor'; Desc = 'Code refactoring' }
            @{ Key = 'perf';     Desc = 'Performance improvement' }
            @{ Key = 'test';     Desc = 'Adding or updating tests' }
            @{ Key = 'build';    Desc = 'Build system or dependencies' }
            @{ Key = 'ci';       Desc = 'CI configuration' }
            @{ Key = 'chore';    Desc = 'Other changes (non-src/test)' }
        )

        for ($i = 0; $i -lt $types.Count; $i++) {
            $num = ($i + 1).ToString().PadLeft(2)
            Write-Host "  $num) " -ForegroundColor $Global:Theme.Accent -NoNewline
            Write-Host "$($types[$i].Key.PadRight(12))" -ForegroundColor $Global:Theme.Text -NoNewline
            Write-Host $types[$i].Desc -ForegroundColor $Global:Theme.Muted
        }

        $selection = Read-Host -Prompt "`n  Select type (1-10)"
        $idx = [int]$selection - 1
        if ($idx -lt 0 -or $idx -ge $types.Count) {
            Write-Warning -Message 'Invalid selection.'
            return
        }
        $Type = $types[$idx].Key
    }

    if ([string]::IsNullOrEmpty($Scope)) {
        $Scope = Read-Host -Prompt '  Scope (optional, press Enter to skip)'
    }

    if ([string]::IsNullOrEmpty($Description)) {
        $Description = Read-Host -Prompt '  Description (required)'
        if ([string]::IsNullOrEmpty($Description)) {
            Write-Warning -Message 'Description is required.'
            return
        }
    }

    if ([string]::IsNullOrEmpty($Body) -and -not $PSBoundParameters.ContainsKey('Body')) {
        $Body = Read-Host -Prompt '  Body (optional, press Enter to skip)'
    }

    if (-not $PSBoundParameters.ContainsKey('BreakingChange')) {
        $bcInput = Read-Host -Prompt '  Breaking change? (y/N)'
        $BreakingChange = $bcInput -match '^[yY]'
    }

    # Build message
    $header = $Type
    if (-not [string]::IsNullOrEmpty($Scope)) {
        $header += "($Scope)"
    }
    if ($BreakingChange) {
        $header += '!'
    }
    $header += ": $Description"

    $message = $header
    if (-not [string]::IsNullOrEmpty($Body)) {
        $message += "`n`n$Body"
    }
    if ($BreakingChange) {
        $message += "`n`nBREAKING CHANGE: $Description"
    }

    Write-Host "`n  Commit message:" -ForegroundColor $Global:Theme.Primary
    Write-Host "  $header" -ForegroundColor $Global:Theme.Accent

    if ($Execute -or -not $PSBoundParameters.ContainsKey('Execute')) {
        if (-not $Execute) {
            $confirm = Read-Host -Prompt "`n  Execute commit? (Y/n)"
            $Execute = $confirm -notmatch '^[nN]'
        }

        if ($Execute -and $PSCmdlet.ShouldProcess($header, 'git commit')) {
            & git commit -m $header --message $Body 2>&1
            if ($LASTEXITCODE -eq 0) {
                Write-Host '  Committed successfully.' -ForegroundColor $Global:Theme.Success
            }
        }
    }

    return $message
}

#endregion

#region -- Branch Cleanup -----------------------------------------------------

<#
.SYNOPSIS
    Interactively cleans up merged and stale branches.
.DESCRIPTION
    Lists local branches that have been merged into the default branch
    or are stale (no commits in a configurable number of days). Prompts
    for confirmation before deleting.
.PARAMETER StaleDays
    Days of inactivity before a branch is considered stale. Default is 30.
.PARAMETER Force
    Delete branches without interactive confirmation.
.PARAMETER IncludeRemote
    Also prune remote tracking branches.
.EXAMPLE
    Invoke-BranchCleanup
.EXAMPLE
    Invoke-BranchCleanup -StaleDays 14 -Force
#>
function Invoke-BranchCleanup {
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([void])]
    param(
        [Parameter()]
        [ValidateRange(1, 365)]
        [int]$StaleDays = 30,

        [Parameter()]
        [switch]$Force,

        [Parameter()]
        [switch]$IncludeRemote
    )

    if (-not (Test-GitRepo)) {
        Write-Warning -Message 'Not in a git repository.'
        return
    }

    $defaultBranch = Get-GitDefaultBranch
    $currentBranch = Get-GitCurrentBranch
    $protectedBranches = @($defaultBranch, 'develop', 'staging', 'release')

    Write-Host "`n  Branch Cleanup" -ForegroundColor $Global:Theme.Primary
    Write-Host "  Default: $defaultBranch | Current: $currentBranch" -ForegroundColor $Global:Theme.Muted
    Write-Host "  $('-' * 60)" -ForegroundColor $Global:Theme.Muted

    # Fetch to ensure up-to-date
    & git fetch --prune 2>$null

    # Get merged branches
    $merged = @(& git branch --merged $defaultBranch 2>$null |
        ForEach-Object -Process { $_.Trim().TrimStart('* ') } |
        Where-Object -FilterScript { $_ -ne $currentBranch -and $_ -notin $protectedBranches -and -not [string]::IsNullOrEmpty($_) })

    # Get stale branches
    $cutoff = (Get-Date).AddDays(-$StaleDays)
    $allBranches = @(& git for-each-ref --sort=-committerdate --format='%(refname:short)|%(committerdate:iso8601)' refs/heads/ 2>$null)

    $stale = @()
    foreach ($line in $allBranches) {
        $parts = $line -split '\|'
        if ($parts.Count -ne 2) { continue }
        $branchName = $parts[0]
        $lastCommit = [datetime]::Parse($parts[1])

        if ($lastCommit -lt $cutoff -and $branchName -ne $currentBranch -and $branchName -notin $protectedBranches -and $branchName -notin $merged) {
            $stale += @{ Name = $branchName; LastCommit = $lastCommit }
        }
    }

    if ($merged.Count -eq 0 -and $stale.Count -eq 0) {
        Write-Host '  No branches to clean up.' -ForegroundColor $Global:Theme.Success
        return
    }

    # Display merged
    if ($merged.Count -gt 0) {
        Write-Host "`n  Merged branches ($($merged.Count)):" -ForegroundColor $Global:Theme.Success
        foreach ($b in $merged) {
            Write-Host "    ? $b" -ForegroundColor $Global:Theme.Text
        }
    }

    # Display stale
    if ($stale.Count -gt 0) {
        Write-Host "`n  Stale branches ($($stale.Count), >$($StaleDays) days):" -ForegroundColor $Global:Theme.Warning
        foreach ($s in $stale) {
            $age = [math]::Floor(((Get-Date) - $s.LastCommit).TotalDays)
            Write-Host "    ? $($s.Name.PadRight(35)) ($($age)d ago)" -ForegroundColor $Global:Theme.Warning
        }
    }

    # Confirm
    $allToDelete = $merged + ($stale | ForEach-Object -Process { $_.Name })
    if (-not $Force) {
        $confirm = Read-Host -Prompt "`n  Delete $($allToDelete.Count) branch(es)? (y/N)"
        if ($confirm -notmatch '^[yY]') {
            Write-Host '  Aborted.' -ForegroundColor $Global:Theme.Muted
            return
        }
    }

    # Delete
    foreach ($branch in $allToDelete) {
        if ($PSCmdlet.ShouldProcess($branch, 'Delete branch')) {
            $output = & git branch -d $branch 2>&1
            if ($LASTEXITCODE -ne 0) {
                $output = & git branch -D $branch 2>&1
            }
            Write-Host "  Deleted: $branch" -ForegroundColor $Global:Theme.Muted
        }
    }

    if ($IncludeRemote) {
        & git remote prune origin 2>$null
        Write-Host '  Pruned remote tracking branches.' -ForegroundColor $Global:Theme.Muted
    }

    Write-Host "`n  Cleanup complete." -ForegroundColor $Global:Theme.Success
}

#endregion

#region -- Stash Manager ------------------------------------------------------

<#
.SYNOPSIS
    Enhanced stash list with descriptions and age.
.EXAMPLE
    Show-GitStashes
#>
function Show-GitStashes {
    [CmdletBinding()]
    [OutputType([void])]
    param()

    if (-not (Test-GitRepo)) {
        Write-Warning -Message 'Not in a git repository.'
        return
    }

    $stashes = @(& git stash list --format='%gd|%s|%ar' 2>$null)

    Write-Host "`n  Git Stashes" -ForegroundColor $Global:Theme.Primary
    Write-Host "  $('-' * 60)" -ForegroundColor $Global:Theme.Muted

    if ($stashes.Count -eq 0) {
        Write-Host '  (no stashes)' -ForegroundColor $Global:Theme.Muted
        return
    }

    foreach ($stash in $stashes) {
        $parts = $stash -split '\|', 3
        if ($parts.Count -lt 3) { continue }
        $ref = $parts[0]
        $msg = $parts[1]
        $age = $parts[2]

        Write-Host "  $($ref.PadRight(12))" -ForegroundColor $Global:Theme.Accent -NoNewline
        Write-Host "$($msg.PadRight(40))" -ForegroundColor $Global:Theme.Text -NoNewline
        Write-Host " $age" -ForegroundColor $Global:Theme.Muted
    }
    Write-Host ''
}

<#
.SYNOPSIS
    Stash changes with a descriptive message.
.PARAMETER Message
    Description for the stash entry.
.PARAMETER IncludeUntracked
    Also stash untracked files.
.EXAMPLE
    Save-GitStash -Message 'WIP: refactoring auth module' -IncludeUntracked
#>
function Save-GitStash {
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([void])]
    param(
        [Parameter(Mandatory, Position = 0)]
        [ValidateNotNullOrEmpty()]
        [string]$Message,

        [Parameter()]
        [switch]$IncludeUntracked
    )

    if (-not (Test-GitRepo)) {
        Write-Warning -Message 'Not in a git repository.'
        return
    }

    if (-not $PSCmdlet.ShouldProcess($Message, 'git stash push')) {
        return
    }

    $args = @('stash', 'push', '-m', $Message)
    if ($IncludeUntracked) { $args += '--include-untracked' }

    & git @args 2>&1
    if ($LASTEXITCODE -eq 0) {
        Write-Host "  Stashed: $Message" -ForegroundColor $Global:Theme.Success
    }
}

<#
.SYNOPSIS
    Applies a stash by index with optional drop.
.PARAMETER Index
    Stash index number (0-based).
.PARAMETER Drop
    Remove the stash after applying.
.EXAMPLE
    Restore-GitStash -Index 0 -Drop
#>
function Restore-GitStash {
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([void])]
    param(
        [Parameter(Position = 0)]
        [ValidateRange(0, 100)]
        [int]$Index = 0,

        [Parameter()]
        [switch]$Drop
    )

    if (-not (Test-GitRepo)) {
        Write-Warning -Message 'Not in a git repository.'
        return
    }

    $stashRef = "stash@{$Index}"

    if (-not $PSCmdlet.ShouldProcess($stashRef, 'Restore stash')) {
        return
    }

    $action = if ($Drop) { 'pop' } else { 'apply' }
    & git stash $action $stashRef 2>&1

    if ($LASTEXITCODE -eq 0) {
        $verb = if ($Drop) { 'Popped' } else { 'Applied' }
        Write-Host "  $verb stash $stashRef." -ForegroundColor $Global:Theme.Success
    }
}

#endregion

#region -- Merge Conflict Helpers ---------------------------------------------

<#
.SYNOPSIS
    Lists files with merge conflicts.
.DESCRIPTION
    Scans the working tree for files containing conflict markers and
    displays them with conflict count.
.EXAMPLE
    Get-MergeConflicts
#>
function Get-MergeConflicts {
    [CmdletBinding()]
    [OutputType([void])]
    param()

    if (-not (Test-GitRepo)) {
        Write-Warning -Message 'Not in a git repository.'
        return
    }

    $conflicted = @(& git diff --name-only --diff-filter=U 2>$null)

    Write-Host "`n  Merge Conflicts" -ForegroundColor $Global:Theme.Primary
    Write-Host "  $('-' * 60)" -ForegroundColor $Global:Theme.Muted

    if ($conflicted.Count -eq 0) {
        Write-Host '  No conflicts detected.' -ForegroundColor $Global:Theme.Success
        return
    }

    foreach ($file in $conflicted) {
        $markers = @(Select-String -Path $file -Pattern '^<{7}\s' -ErrorAction SilentlyContinue)
        $count = $markers.Count
        $icon = if ($count -gt 3) { '!!' } else { '?' }
        $color = if ($count -gt 3) { $Global:Theme.Error } else { $Global:Theme.Warning }
        Write-Host "  $icon " -ForegroundColor $color -NoNewline
        Write-Host "$($file.PadRight(45))" -ForegroundColor $Global:Theme.Text -NoNewline
        Write-Host " $count conflict(s)" -ForegroundColor $color
    }

    Write-Host "`n  Total: $($conflicted.Count) file(s) with conflicts." -ForegroundColor $Global:Theme.Warning
}

<#
.SYNOPSIS
    Resolves all conflicts in a file by choosing ours or theirs.
.PARAMETER Path
    File path with conflicts.
.PARAMETER Strategy
    Resolution strategy: 'ours' or 'theirs'.
.EXAMPLE
    Resolve-MergeConflict -Path 'src/app.cs' -Strategy theirs
#>
function Resolve-MergeConflict {
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([void])]
    param(
        [Parameter(Mandatory, Position = 0)]
        [ValidateNotNullOrEmpty()]
        [string]$Path,

        [Parameter(Mandatory, Position = 1)]
        [ValidateSet('ours', 'theirs')]
        [string]$Strategy
    )

    if (-not (Test-GitRepo)) {
        Write-Warning -Message 'Not in a git repository.'
        return
    }

    if (-not $PSCmdlet.ShouldProcess("$Path ($Strategy)", 'Resolve conflict')) {
        return
    }

    & git checkout "--$Strategy" -- $Path 2>&1
    & git add $Path 2>&1

    if ($LASTEXITCODE -eq 0) {
        Write-Host "  Resolved '$Path' using $Strategy." -ForegroundColor $Global:Theme.Success
    }
}

#endregion

#region -- Worktree Shortcuts -------------------------------------------------

<#
.SYNOPSIS
    Lists all git worktrees.
.EXAMPLE
    Show-GitWorktrees
#>
function Show-GitWorktrees {
    [CmdletBinding()]
    [OutputType([void])]
    param()

    if (-not (Test-GitRepo)) {
        Write-Warning -Message 'Not in a git repository.'
        return
    }

    Write-Host "`n  Git Worktrees" -ForegroundColor $Global:Theme.Primary
    Write-Host "  $('-' * 60)" -ForegroundColor $Global:Theme.Muted

    $worktrees = @(& git worktree list --porcelain 2>$null)
    $current = (Get-Location).Path

    $wt = $null
    foreach ($line in $worktrees) {
        if ($line -match '^worktree\s+(.+)$') {
            if ($null -ne $wt) {
                $icon = if ($wt.Path -eq $current) { '?' } else { ' ' }
                Write-Host "  $icon $($wt.Path.PadRight(40))" -ForegroundColor $Global:Theme.Text -NoNewline
                Write-Host " $($wt.Branch)" -ForegroundColor $Global:Theme.Accent
            }
            $wt = @{ Path = $Matches[1]; Branch = '' }
        }
        elseif ($line -match '^branch\s+refs/heads/(.+)$' -and $null -ne $wt) {
            $wt.Branch = $Matches[1]
        }
    }

    if ($null -ne $wt) {
        $icon = if ($wt.Path -eq $current) { '?' } else { ' ' }
        Write-Host "  $icon $($wt.Path.PadRight(40))" -ForegroundColor $Global:Theme.Text -NoNewline
        Write-Host " $($wt.Branch)" -ForegroundColor $Global:Theme.Accent
    }
    Write-Host ''
}

<#
.SYNOPSIS
    Creates a new git worktree for a branch.
.PARAMETER Branch
    Branch name to create worktree for.
.PARAMETER Path
    Directory path for the worktree. Defaults to ../repo-branch.
.PARAMETER CreateBranch
    Create a new branch if it does not exist.
.EXAMPLE
    New-GitWorktree -Branch 'feature/auth' -CreateBranch
#>
function New-GitWorktree {
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([void])]
    param(
        [Parameter(Mandatory, Position = 0)]
        [ValidateNotNullOrEmpty()]
        [string]$Branch,

        [Parameter(Position = 1)]
        [string]$Path,

        [Parameter()]
        [switch]$CreateBranch
    )

    if (-not (Test-GitRepo)) {
        Write-Warning -Message 'Not in a git repository.'
        return
    }

    if ([string]::IsNullOrEmpty($Path)) {
        $repoName = Split-Path -Path (& git rev-parse --show-toplevel 2>$null) -Leaf
        $safeBranch = $Branch -replace '[/\\]', '-'
        $Path = Join-Path -Path (Split-Path -Path (& git rev-parse --show-toplevel 2>$null) -Parent) -ChildPath "${repoName}-${safeBranch}"
    }

    if (-not $PSCmdlet.ShouldProcess("$Path ($Branch)", 'Create worktree')) {
        return
    }

    $args = @('worktree', 'add', $Path)
    if ($CreateBranch) {
        $args += @('-b', $Branch)
    }
    else {
        $args += $Branch
    }

    & git @args 2>&1
    if ($LASTEXITCODE -eq 0) {
        Write-Host "  Worktree created: $Path ($Branch)" -ForegroundColor $Global:Theme.Success
    }
}

#endregion

#region -- PR Draft -----------------------------------------------------------

<#
.SYNOPSIS
    Opens a pull request draft in the browser.
.DESCRIPTION
    Pushes the current branch and opens the GitHub/Azure DevOps
    new PR page in the default browser.
.PARAMETER Title
    PR title. Defaults to the last commit message.
.PARAMETER Base
    Base branch for the PR. Defaults to the repository default branch.
.PARAMETER Draft
    Open as draft PR.
.PARAMETER Push
    Push branch to remote before opening PR page.
.EXAMPLE
    Open-PullRequest -Title 'Add OAuth2 flow' -Draft -Push
.EXAMPLE
    pr -Push
#>
function Open-PullRequest {
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([void])]
    param(
        [Parameter(Position = 0)]
        [string]$Title,

        [Parameter()]
        [string]$Base,

        [Parameter()]
        [switch]$Draft,

        [Parameter()]
        [switch]$Push
    )

    if (-not (Test-GitRepo)) {
        Write-Warning -Message 'Not in a git repository.'
        return
    }

    $branch = Get-GitCurrentBranch
    if ([string]::IsNullOrEmpty($Base)) {
        $Base = Get-GitDefaultBranch
    }

    if ($Push) {
        if ($PSCmdlet.ShouldProcess($branch, 'Push to remote')) {
            & git push -u origin $branch 2>&1
        }
    }

    if ([string]::IsNullOrEmpty($Title)) {
        $Title = & git log -1 --format='%s' 2>$null
    }

    $remoteUrl = Get-GitRemoteUrl
    if ([string]::IsNullOrEmpty($remoteUrl)) {
        Write-Warning -Message 'Could not determine remote URL.'
        return
    }

    $encodedTitle = [uri]::EscapeDataString($Title)

    if ($remoteUrl -match 'github\.com') {
        $prUrl = "$remoteUrl/compare/${Base}...${branch}?expand=1&title=${encodedTitle}"
        if ($Draft) { $prUrl += '&draft=1' }
    }
    elseif ($remoteUrl -match 'dev\.azure\.com') {
        $prUrl = "$remoteUrl/pullrequestcreate?sourceRef=${branch}&targetRef=${Base}&title=${encodedTitle}"
    }
    else {
        Write-Warning -Message "Unsupported remote host: $remoteUrl"
        return
    }

    Write-Host "  Opening PR: $branch ? $Base" -ForegroundColor $Global:Theme.Success
    Start-Process -FilePath $prUrl
}

#endregion

#region -- Git Log Helpers ----------------------------------------------------

<#
.SYNOPSIS
    Pretty git log with graph and colors.
.PARAMETER Count
    Number of commits to show. Default is 15.
.PARAMETER All
    Show all branches.
.EXAMPLE
    Show-GitLog -Count 20 -All
#>
function Show-GitLog {
    [CmdletBinding()]
    [OutputType([void])]
    param(
        [Parameter(Position = 0)]
        [ValidateRange(1, 200)]
        [int]$Count = 15,

        [Parameter()]
        [switch]$All
    )

    if (-not (Test-GitRepo)) {
        Write-Warning -Message 'Not in a git repository.'
        return
    }

    $args = @('log', "--max-count=$Count", '--graph', '--abbrev-commit',
        '--format=%C(bold cyan)%h%C(reset) %C(white)%s%C(reset) %C(dim)(%ar)%C(reset) %C(bold green)%an%C(reset)%C(bold yellow)%d%C(reset)')

    if ($All) { $args += '--all' }

    & git @args
}

<#
.SYNOPSIS
    Shows what changed between two branches.
.PARAMETER Source
    Source branch. Default is current branch.
.PARAMETER Target
    Target branch. Default is the repository default branch.
.PARAMETER FilesOnly
    Show only file names, not full diff.
.EXAMPLE
    Show-GitBranchDiff -Target main -FilesOnly
#>
function Show-GitBranchDiff {
    [CmdletBinding()]
    [OutputType([void])]
    param(
        [Parameter(Position = 0)]
        [string]$Source,

        [Parameter(Position = 1)]
        [string]$Target,

        [Parameter()]
        [switch]$FilesOnly
    )

    if (-not (Test-GitRepo)) {
        Write-Warning -Message 'Not in a git repository.'
        return
    }

    if ([string]::IsNullOrEmpty($Source)) { $Source = Get-GitCurrentBranch }
    if ([string]::IsNullOrEmpty($Target)) { $Target = Get-GitDefaultBranch }

    Write-Host "`n  Changes: $Source vs $Target" -ForegroundColor $Global:Theme.Primary
    Write-Host "  $('-' * 50)" -ForegroundColor $Global:Theme.Muted

    if ($FilesOnly) {
        $files = @(& git diff --name-status "$Target...$Source" 2>$null)
        foreach ($file in $files) {
            if ($file -match '^(\w)\s+(.+)$') {
                $status = $Matches[1]
                $name = $Matches[2]
                $color = switch ($status) {
                    'A' { $Global:Theme.Success }
                    'D' { $Global:Theme.Error }
                    'M' { $Global:Theme.Warning }
                    default { $Global:Theme.Text }
                }
                Write-Host "  $status $name" -ForegroundColor $color
            }
        }

        $stats = & git diff --stat "$Target...$Source" 2>$null | Select-Object -Last 1
        Write-Host "`n  $stats" -ForegroundColor $Global:Theme.Muted
    }
    else {
        & git diff "$Target...$Source" 2>$null
    }
}

#endregion

#region -- Quick Actions ------------------------------------------------------

<#
.SYNOPSIS
    Amends the last commit with staged changes.
.PARAMETER NoEdit
    Keep the existing commit message.
.EXAMPLE
    Update-LastCommit -NoEdit
#>
function Update-LastCommit {
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([void])]
    param(
        [Parameter()]
        [switch]$NoEdit
    )

    if (-not (Test-GitRepo)) {
        Write-Warning -Message 'Not in a git repository.'
        return
    }

    if (-not $PSCmdlet.ShouldProcess('HEAD', 'Amend commit')) {
        return
    }

    $args = @('commit', '--amend')
    if ($NoEdit) { $args += '--no-edit' }

    & git @args 2>&1
}

<#
.SYNOPSIS
    Undoes the last N commits keeping changes staged.
.PARAMETER Count
    Number of commits to undo. Default is 1.
.EXAMPLE
    Undo-GitCommit -Count 2
#>
function Undo-GitCommit {
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([void])]
    param(
        [Parameter(Position = 0)]
        [ValidateRange(1, 20)]
        [int]$Count = 1
    )

    if (-not (Test-GitRepo)) {
        Write-Warning -Message 'Not in a git repository.'
        return
    }

    if (-not $PSCmdlet.ShouldProcess("HEAD~$Count", 'Soft reset')) {
        return
    }

    & git reset --soft "HEAD~$Count" 2>&1
    if ($LASTEXITCODE -eq 0) {
        Write-Host "  Undid $Count commit(s). Changes are staged." -ForegroundColor $Global:Theme.Success
    }
}

#endregion

#region -- Aliases -------------------------------------------------------------

Set-Alias -Name 'ccommit'   -Value 'New-ConventionalCommit'  -Scope Global -Force
Set-Alias -Name 'gcleanup'  -Value 'Invoke-BranchCleanup'    -Scope Global -Force
Set-Alias -Name 'gstashes'  -Value 'Show-GitStashes'         -Scope Global -Force
Set-Alias -Name 'gsave'     -Value 'Save-GitStash'           -Scope Global -Force
Set-Alias -Name 'grestore'  -Value 'Restore-GitStash'        -Scope Global -Force
Set-Alias -Name 'gconflict' -Value 'Get-MergeConflicts'      -Scope Global -Force
Set-Alias -Name 'gwt'       -Value 'Show-GitWorktrees'       -Scope Global -Force
Set-Alias -Name 'gwtnew'    -Value 'New-GitWorktree'         -Scope Global -Force
Set-Alias -Name 'pr'        -Value 'Open-PullRequest'        -Scope Global -Force
Set-Alias -Name 'glog'      -Value 'Show-GitLog'             -Scope Global -Force
Set-Alias -Name 'gdiff'     -Value 'Show-GitBranchDiff'      -Scope Global -Force
Set-Alias -Name 'gamend'    -Value 'Update-LastCommit'        -Scope Global -Force
Set-Alias -Name 'gundo'     -Value 'Undo-GitCommit'          -Scope Global -Force

#endregion

#region -- Tab Completion -----------------------------------------------------

Register-ArgumentCompleter -CommandName 'Resolve-MergeConflict' -ParameterName 'Path' -ScriptBlock {
    param($commandName, $parameterName, $wordToComplete, $commandAst, $fakeBoundParameters)

    $conflicted = @(& git diff --name-only --diff-filter=U 2>$null)
    $conflicted | Where-Object -FilterScript { $_ -like "${wordToComplete}*" } | ForEach-Object -Process {
        [System.Management.Automation.CompletionResult]::new($_, $_, 'ParameterValue', $_)
    }
}

Register-ArgumentCompleter -CommandName @('Show-GitBranchDiff', 'New-GitWorktree') -ParameterName 'Branch' -ScriptBlock {
    param($commandName, $parameterName, $wordToComplete, $commandAst, $fakeBoundParameters)

    $branches = @(& git branch --format='%(refname:short)' 2>$null)
    $branches | Where-Object -FilterScript { $_ -like "${wordToComplete}*" } | ForEach-Object -Process {
        [System.Management.Automation.CompletionResult]::new($_, $_, 'ParameterValue', $_)
    }
}

#endregion
