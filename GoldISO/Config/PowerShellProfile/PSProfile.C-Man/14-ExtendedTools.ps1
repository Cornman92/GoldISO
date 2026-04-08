[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingWriteHost', '', Justification = 'Tool output requires colored display')]
param()

#region ── npm / Node Aliases ─────────────────────────────────────────────────

if (Get-Command -Name 'npm' -ErrorAction SilentlyContinue) {
    function Invoke-NpmInstall { & npm install @args }
    function Invoke-NpmRun { & npm run @args }
    function Invoke-NpmStart { & npm start @args }
    function Invoke-NpmTest { & npm test @args }
    function Invoke-NpmBuild { & npm run build @args }
    function Invoke-NpmDev { & npm run dev @args }
    function Invoke-NpmAudit { & npm audit @args }
    function Invoke-NpmOutdated { & npm outdated @args }
    function Invoke-NpmUpdate { & npm update @args }

    Set-Alias -Name 'ni'   -Value Invoke-NpmInstall  -Option AllScope -Force
    Set-Alias -Name 'nr'   -Value Invoke-NpmRun      -Option AllScope -Force
    Set-Alias -Name 'ns'   -Value Invoke-NpmStart    -Option AllScope -Force
    Set-Alias -Name 'nt'   -Value Invoke-NpmTest     -Option AllScope -Force
    Set-Alias -Name 'nb'   -Value Invoke-NpmBuild    -Option AllScope -Force
    Set-Alias -Name 'nd'   -Value Invoke-NpmDev      -Option AllScope -Force
    Set-Alias -Name 'nau'  -Value Invoke-NpmAudit    -Option AllScope -Force
    Set-Alias -Name 'nout' -Value Invoke-NpmOutdated -Option AllScope -Force
    Set-Alias -Name 'nup'  -Value Invoke-NpmUpdate   -Option AllScope -Force

    Register-ArgumentCompleter -CommandName 'npm' -Native -ScriptBlock {
        param($wordToComplete, $commandAst, $cursorPosition)
        $commandText = $commandAst.ToString()
        if ($commandText -match '^\s*npm\s+run\s+') {
            # Complete npm scripts from package.json
            $pkgPath = Join-Path -Path (Get-Location).Path -ChildPath 'package.json'
            if (Test-Path -Path $pkgPath) {
                try {
                    $pkg = Get-Content -Path $pkgPath -Raw | ConvertFrom-Json
                    if ($pkg.scripts) {
                        $pkg.scripts.PSObject.Properties.Name |
                            Where-Object -FilterScript { $_ -like "$wordToComplete*" } |
                            ForEach-Object -Process {
                                [System.Management.Automation.CompletionResult]::new($_, $_, 'ParameterValue', "Script: $_")
                            }
                    }
                }
                catch {
                    # Silently continue
                }
            }
        }
        elseif ($commandText -match '^\s*npm\s*$' -or ($commandText -match '^\s*npm\s+(\S+)$' -and $wordToComplete)) {
            @('install', 'run', 'start', 'test', 'build', 'init', 'publish', 'audit',
              'outdated', 'update', 'uninstall', 'ls', 'link', 'pack', 'ci', 'cache',
              'config', 'exec', 'explain', 'find-dupes', 'fund', 'search', 'view') |
                Where-Object -FilterScript { $_ -like "$wordToComplete*" } |
                ForEach-Object -Process {
                    [System.Management.Automation.CompletionResult]::new($_, $_, 'ParameterValue', "npm $_")
                }
        }
    }
}

#endregion

#region ── pip / Python Aliases ────────────────────────────────────────────────

if (Get-Command -Name 'pip' -ErrorAction SilentlyContinue) {
    function Invoke-PipInstall { & pip install @args }
    function Invoke-PipFreeze { & pip freeze @args }
    function Invoke-PipList { & pip list @args }
    function Invoke-PipOutdated { & pip list --outdated @args }
    function Invoke-PipUpgrade { & pip install --upgrade @args }
    function Invoke-PipUninstall { & pip uninstall @args }

    Set-Alias -Name 'pipi' -Value Invoke-PipInstall   -Option AllScope -Force
    Set-Alias -Name 'pipf' -Value Invoke-PipFreeze    -Option AllScope -Force
    Set-Alias -Name 'pipl' -Value Invoke-PipList       -Option AllScope -Force
    Set-Alias -Name 'pipo' -Value Invoke-PipOutdated   -Option AllScope -Force
    Set-Alias -Name 'pipu' -Value Invoke-PipUpgrade    -Option AllScope -Force
    Set-Alias -Name 'pipx' -Value Invoke-PipUninstall  -Option AllScope -Force
}

#endregion

#region ── Podman Aliases ─────────────────────────────────────────────────────

if (Get-Command -Name 'podman' -ErrorAction SilentlyContinue) {
    function Invoke-PodmanPS { & podman ps @args }
    function Invoke-PodmanPSAll { & podman ps -a @args }
    function Invoke-PodmanImages { & podman images @args }
    function Invoke-PodmanBuild { & podman build @args }
    function Invoke-PodmanRun { & podman run @args }
    function Invoke-PodmanCompose { & podman compose @args }
    function Invoke-PodmanPrune { & podman system prune -af @args }

    Set-Alias -Name 'pps'  -Value Invoke-PodmanPS      -Option AllScope -Force
    Set-Alias -Name 'ppsa' -Value Invoke-PodmanPSAll   -Option AllScope -Force
    Set-Alias -Name 'pim'  -Value Invoke-PodmanImages  -Option AllScope -Force
    Set-Alias -Name 'pbld' -Value Invoke-PodmanBuild   -Option AllScope -Force
    Set-Alias -Name 'prun' -Value Invoke-PodmanRun     -Option AllScope -Force
    Set-Alias -Name 'pdc'  -Value Invoke-PodmanCompose -Option AllScope -Force
    Set-Alias -Name 'ppr'  -Value Invoke-PodmanPrune   -Option AllScope -Force
}

#endregion

#region ── WSL Integration ────────────────────────────────────────────────────

if (Get-Command -Name 'wsl' -ErrorAction SilentlyContinue) {
    function Invoke-WSLDefault { & wsl @args }
    function Get-WSLDistributions { & wsl --list --verbose }
    function Stop-WSLAll { & wsl --shutdown }
    function Enter-WSL {
        <#
        .SYNOPSIS
            Enter a WSL distribution.
        .PARAMETER Distribution
            Name of the WSL distribution. Defaults to the default distro.
        #>
        [CmdletBinding()]
        param(
            [Parameter(Position = 0)]
            [string]$Distribution
        )

        if ($Distribution) {
            & wsl -d $Distribution
        }
        else {
            & wsl
        }
    }

    Set-Alias -Name 'wslls' -Value Get-WSLDistributions -Option AllScope -Force
    Set-Alias -Name 'wslx'  -Value Stop-WSLAll          -Option AllScope -Force
}

#endregion

#region ── InvokeBuild / Nuke / Taskfile ──────────────────────────────────────

# InvokeBuild
if (Get-Module -Name InvokeBuild -ListAvailable -ErrorAction SilentlyContinue) {
    function Invoke-ProjectBuild {
        <#
        .SYNOPSIS
            Run InvokeBuild with the project's .build.ps1 or build.ps1.
        .PARAMETER Task
            Build task to run.
        #>
        [CmdletBinding()]
        [Alias('ib')]
        param(
            [Parameter(Position = 0)]
            [string]$Task = '.'
        )

        $buildFile = Get-ChildItem -Path . -Filter '*.build.ps1' -ErrorAction SilentlyContinue |
            Select-Object -First 1
        if (-not $buildFile) {
            $buildFile = Get-ChildItem -Path . -Filter 'build.ps1' -ErrorAction SilentlyContinue |
                Select-Object -First 1
        }

        if ($buildFile) {
            Invoke-Build -Task $Task -File $buildFile.FullName
        }
        else {
            Write-Warning -Message 'No build script found (*.build.ps1 or build.ps1)'
        }
    }
}

# Taskfile (task runner)
if (Get-Command -Name 'task' -ErrorAction SilentlyContinue) {
    function Invoke-Taskfile { & task @args }
    function Get-TaskfileList { & task --list @args }

    Set-Alias -Name 'tf'  -Value Invoke-Taskfile  -Option AllScope -Force
    Set-Alias -Name 'tfl' -Value Get-TaskfileList  -Option AllScope -Force
}

#endregion

#region ── Operator-Grade Tools ───────────────────────────────────────────────

function Compare-ProfileState {
    <#
    .SYNOPSIS
        Drift detection - compare current profile state against a known baseline.
        Detects modified, added, or missing files.
    .PARAMETER BaselinePath
        Path to baseline snapshot JSON. If not provided, creates one.
    #>
    [CmdletBinding()]
    [Alias('drift')]
    param(
        [Parameter(Position = 0)]
        [string]$BaselinePath
    )

    $tc = $script:Theme
    $snapshotPath = if ($BaselinePath) { $BaselinePath }
                    else {
                        Join-Path -Path $script:ProfileRoot -ChildPath 'Cache' |
                            Join-Path -ChildPath 'profile-baseline.json'
                    }

    # Build current state
    $currentState = @{}
    Get-ChildItem -Path $script:ProfileRoot -Recurse -File -ErrorAction SilentlyContinue |
        Where-Object -FilterScript { $_.FullName -notmatch '[\\/](Logs|Cache)[\\/]' } |
        ForEach-Object -Process {
            $relativePath = $_.FullName.Substring($script:ProfileRoot.Length + 1)
            $currentState[$relativePath] = @{
                Hash     = (Get-FileHash -Path $_.FullName -Algorithm SHA256).Hash
                Size     = $_.Length
                Modified = $_.LastWriteTime.ToString('o')
            }
        }

    # If no baseline exists, create it
    if (-not (Test-Path -Path $snapshotPath)) {
        $currentState | ConvertTo-Json -Depth 5 |
            Set-Content -Path $snapshotPath -Encoding UTF8
        Write-Host -Object "  Baseline created at: $snapshotPath" -ForegroundColor $tc.Success
        Write-Host -Object "  $($currentState.Count) files tracked." -ForegroundColor $tc.Muted
        return
    }

    # Compare against baseline
    $baseline = Get-Content -Path $snapshotPath -Raw | ConvertFrom-Json -AsHashtable

    $modified = [System.Collections.Generic.List[string]]::new()
    $added = [System.Collections.Generic.List[string]]::new()
    $removed = [System.Collections.Generic.List[string]]::new()

    foreach ($file in $currentState.Keys) {
        if ($baseline.ContainsKey($file)) {
            if ($currentState[$file].Hash -ne $baseline[$file].Hash) {
                $modified.Add($file)
            }
        }
        else {
            $added.Add($file)
        }
    }

    foreach ($file in $baseline.Keys) {
        if (-not $currentState.ContainsKey($file)) {
            $removed.Add($file)
        }
    }

    # Report
    Write-Host -Object "`n  Profile Drift Report:" -ForegroundColor $tc.Primary
    if ($modified.Count -eq 0 -and $added.Count -eq 0 -and $removed.Count -eq 0) {
        Write-Host -Object '  No drift detected. Profile matches baseline.' -ForegroundColor $tc.Success
    }
    else {
        if ($modified.Count -gt 0) {
            Write-Host -Object "`n  Modified ($($modified.Count)):" -ForegroundColor $tc.Warning
            foreach ($file in $modified) {
                Write-Host -Object "    ~ $file" -ForegroundColor $tc.Warning
            }
        }
        if ($added.Count -gt 0) {
            Write-Host -Object "`n  Added ($($added.Count)):" -ForegroundColor $tc.Success
            foreach ($file in $added) {
                Write-Host -Object "    + $file" -ForegroundColor $tc.Success
            }
        }
        if ($removed.Count -gt 0) {
            Write-Host -Object "`n  Removed ($($removed.Count)):" -ForegroundColor $tc.Error
            foreach ($file in $removed) {
                Write-Host -Object "    - $file" -ForegroundColor $tc.Error
            }
        }
    }
    Write-Host ''
}

function Update-ProfileBaseline {
    <#
    .SYNOPSIS
        Refresh the profile drift detection baseline to current state.
    #>
    [CmdletBinding()]
    param()

    $snapshotPath = Join-Path -Path $script:ProfileRoot -ChildPath 'Cache' |
        Join-Path -ChildPath 'profile-baseline.json'

    if (Test-Path -Path $snapshotPath) {
        Remove-Item -Path $snapshotPath -Force
    }

    Compare-ProfileState
}

function Invoke-ProfileSelfTest {
    <#
    .SYNOPSIS
        Self-healing profile test - verify all modules load, fix what's fixable.
    #>
    [CmdletBinding()]
    [Alias('selftest')]
    param()

    $tc = $Global:Theme
    Write-Host -Object "`n  Profile Self-Test:" -ForegroundColor $tc.Primary

    $checks = @(
        @{
            Name  = 'Profile root exists'
            Test  = { Test-Path -Path $script:ProfileRoot }
            Fix   = { $null = New-Item -Path $script:ProfileRoot -ItemType Directory -Force }
        }
        @{
            Name  = 'Config file valid'
            Test  = {
                $configPath = Join-Path -Path $script:ProfileRoot -ChildPath 'Config' | Join-Path -ChildPath 'profile-config.json'
                if (Test-Path -Path $configPath) {
                    try { $null = Get-Content -Path $configPath -Raw | ConvertFrom-Json; $true } catch { $false }
                }
                else { $false }
            }
            Fix   = {
                $configPath = Join-Path -Path $script:ProfileRoot -ChildPath 'Config' | Join-Path -ChildPath 'profile-config.json'
                $Global:ProfileConfig | ConvertTo-Json -Depth 5 | Set-Content -Path $configPath -Encoding UTF8
            }
        }
        @{
            Name  = 'All Profile.d modules parseable'
            Test  = {
                $profileD = Join-Path -Path $script:ProfileRoot -ChildPath 'Profile.d'
                $allGood = $true
                Get-ChildItem -Path $profileD -Filter '*.ps1' -ErrorAction SilentlyContinue | ForEach-Object -Process {
                    try {
                        $null = [System.Management.Automation.Language.Parser]::ParseFile(
                            $_.FullName, [ref]$null, [ref]$null)
                    }
                    catch { $allGood = $false }
                }
                $allGood
            }
            Fix   = $null
        }
        @{
            Name  = 'Log directories exist'
            Test  = {
                $sessionDir = Join-Path -Path $script:ProfileRoot -ChildPath 'Logs' | Join-Path -ChildPath 'sessions'
                $errorDir = Join-Path -Path $script:ProfileRoot -ChildPath 'Logs' | Join-Path -ChildPath 'errors'
                (Test-Path -Path $sessionDir) -and (Test-Path -Path $errorDir)
            }
            Fix   = {
                $null = New-Item -Path (Join-Path -Path $script:ProfileRoot -ChildPath 'Logs' | Join-Path -ChildPath 'sessions') -ItemType Directory -Force
                $null = New-Item -Path (Join-Path -Path $script:ProfileRoot -ChildPath 'Logs' | Join-Path -ChildPath 'errors') -ItemType Directory -Force
            }
        }
        @{
            Name  = 'PSReadLine available'
            Test  = { $null -ne (Get-Module -Name PSReadLine -ListAvailable) }
            Fix   = $null
        }
        @{
            Name  = 'Git available'
            Test  = { $null -ne (Get-Command -Name 'git' -ErrorAction SilentlyContinue) }
            Fix   = $null
        }
        @{
            Name  = 'Oh-My-Posh available'
            Test  = { $null -ne (Get-Command -Name 'oh-my-posh' -ErrorAction SilentlyContinue) }
            Fix   = $null
        }
    )

    $passed = 0
    $failed = 0
    $fixed = 0

    foreach ($check in $checks) {
        $result = try { & $check.Test } catch { $false }
        if ($result) {
            Write-Host -Object "    $([char]0x2713) $($check.Name)" -ForegroundColor $tc.Success
            $passed++
        }
        else {
            if ($check.Fix) {
                try {
                    & $check.Fix
                    Write-Host -Object "    $([char]0x2699) $($check.Name) - AUTO-FIXED" -ForegroundColor $tc.Warning
                    $fixed++
                }
                catch {
                    Write-Host -Object "    $([char]0x2717) $($check.Name) - FIX FAILED" -ForegroundColor $tc.Error
                    $failed++
                }
            }
            else {
                Write-Host -Object "    $([char]0x2717) $($check.Name)" -ForegroundColor $tc.Error
                $failed++
            }
        }
    }

    Write-Host -Object "`n    Passed: $passed  Fixed: $fixed  Failed: $failed" -ForegroundColor $tc.Primary
    Write-Host ''
}

#endregion

#region ── CI/CD Shortcuts ────────────────────────────────────────────────────

function Open-GitHubActions {
    <#
    .SYNOPSIS
        Open the GitHub Actions page for the current repo in browser.
    #>
    [CmdletBinding()]
    [Alias('gha')]
    param()

    $remote = & git remote get-url origin 2>$null
    if ($remote) {
        $url = $remote -replace '\.git$', '' -replace 'git@github\.com:', 'https://github.com/'
        Start-Process -FilePath "$url/actions"
    }
    else {
        Write-Warning -Message 'Not in a git repo or no remote configured.'
    }
}

function Open-GitHubPR {
    <#
    .SYNOPSIS
        Open GitHub pull request page for current branch.
    #>
    [CmdletBinding()]
    [Alias('ghpr')]
    param()

    $remote = & git remote get-url origin 2>$null
    $branch = & git rev-parse --abbrev-ref HEAD 2>$null
    if ($remote -and $branch) {
        $url = $remote -replace '\.git$', '' -replace 'git@github\.com:', 'https://github.com/'
        Start-Process -FilePath "$url/compare/$branch`?expand=1"
    }
    else {
        Write-Warning -Message 'Not in a git repo or no remote configured.'
    }
}

function Open-GitHubRepo {
    <#
    .SYNOPSIS
        Open the GitHub repo page for the current project in browser.
    #>
    [CmdletBinding()]
    [Alias('ghrepo')]
    param()

    $remote = & git remote get-url origin 2>$null
    if ($remote) {
        $url = $remote -replace '\.git$', '' -replace 'git@github\.com:', 'https://github.com/'
        Start-Process -FilePath $url
    }
    else {
        Write-Warning -Message 'Not in a git repo or no remote configured.'
    }
}

#endregion

