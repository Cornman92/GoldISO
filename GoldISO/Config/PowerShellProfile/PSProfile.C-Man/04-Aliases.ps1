[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingWriteHost', '', Justification = 'Alias listing requires colored output')]
param()

# Git Aliases

if (Get-Command -Name 'git' -ErrorAction SilentlyContinue) {
    function Invoke-GitStatus { & git status @args }
    function Invoke-GitAdd { & git add @args }
    function Invoke-GitAddAll { & git add -A @args }
    function Invoke-GitCommit { & git commit @args }
    function Invoke-GitCommitMessage { & git commit -m @args }
    function Invoke-GitPush { & git push @args }
    function Invoke-GitPull { & git pull @args }
    function Invoke-GitFetch { & git fetch --all --prune @args }
    function Invoke-GitLog { & git log --oneline --graph --decorate -20 @args }
    function Invoke-GitLogFull { & git log --graph --abbrev-commit --decorate --all @args }
    function Invoke-GitDiff { & git diff @args }
    function Invoke-GitDiffStaged { & git diff --staged @args }
    function Invoke-GitBranch { & git branch @args }
    function Invoke-GitCheckout { & git checkout @args }
    function Invoke-GitStash { & git stash @args }
    function Invoke-GitStashPop { & git stash pop @args }
    function Invoke-GitReset { & git reset @args }
    function Invoke-GitRebase { & git rebase @args }
    function Invoke-GitCherry { & git cherry-pick @args }
    function Invoke-GitTag { & git tag @args }
    function Invoke-GitRemote { & git remote -v @args }
    function Invoke-GitClone { & git clone @args }
    function Invoke-GitAmend { & git commit --amend --no-edit @args }
    function Invoke-GitBlame { & git blame @args }
    function Invoke-GitClean { & git clean -fd @args }

    Set-Alias -Name 'gs'    -Value Invoke-GitStatus       -Scope Global -Force
    Set-Alias -Name 'ga'    -Value Invoke-GitAdd           -Scope Global -Force
    Set-Alias -Name 'gaa'   -Value Invoke-GitAddAll        -Scope Global -Force
    Set-Alias -Name 'gc'    -Value Invoke-GitCommit        -Scope Global -Force
    Set-Alias -Name 'gcm'   -Value Invoke-GitCommitMessage -Scope Global -Force
    Set-Alias -Name 'gp'    -Value Invoke-GitPush          -Scope Global -Force
    Set-Alias -Name 'gpl'   -Value Invoke-GitPull          -Scope Global -Force
    Set-Alias -Name 'gf'    -Value Invoke-GitFetch         -Scope Global -Force
    Set-Alias -Name 'gl'    -Value Invoke-GitLog           -Scope Global -Force
    Set-Alias -Name 'glf'   -Value Invoke-GitLogFull       -Scope Global -Force
    Set-Alias -Name 'gd'    -Value Invoke-GitDiff          -Scope Global -Force
    Set-Alias -Name 'gds'   -Value Invoke-GitDiffStaged    -Scope Global -Force
    Set-Alias -Name 'gb'    -Value Invoke-GitBranch        -Scope Global -Force
    Set-Alias -Name 'gco'   -Value Invoke-GitCheckout      -Scope Global -Force
    Set-Alias -Name 'gst'   -Value Invoke-GitStash         -Scope Global -Force
    Set-Alias -Name 'gsp'   -Value Invoke-GitStashPop      -Scope Global -Force
    Set-Alias -Name 'grs'   -Value Invoke-GitReset         -Scope Global -Force
    Set-Alias -Name 'grb'   -Value Invoke-GitRebase        -Scope Global -Force
    Set-Alias -Name 'gcp'   -Value Invoke-GitCherry        -Scope Global -Force
    Set-Alias -Name 'gt'    -Value Invoke-GitTag           -Scope Global -Force
    Set-Alias -Name 'grv'   -Value Invoke-GitRemote        -Scope Global -Force
    Set-Alias -Name 'gcl'   -Value Invoke-GitClone         -Scope Global -Force
    Set-Alias -Name 'gam'   -Value Invoke-GitAmend         -Scope Global -Force
    Set-Alias -Name 'gbl'   -Value Invoke-GitBlame         -Scope Global -Force
    Set-Alias -Name 'gcln'  -Value Invoke-GitClean         -Scope Global -Force
    
    # Quick git alias
    Set-Alias -Name 'g'      -Value git                    -Scope Global -Force
}

# System Aliases

function Invoke-ClearHost { Clear-Host }
function Invoke-ListDirectory { Get-ChildItem @args }
function Invoke-ListAll { Get-ChildItem -Force @args }
function Invoke-ListDetailed { Get-ChildItem -Force @args | Format-Table -AutoSize }
function Invoke-WhichCommand { (Get-Command @args).Source }
function Invoke-TouchFile {
    param([Parameter(Mandatory, Position = 0)][string]$Path)
    if (Test-Path -Path $Path) {
        (Get-Item -Path $Path).LastWriteTime = Get-Date
    }
    else {
        $null = New-Item -Path $Path -ItemType File -Force
    }
}
function Invoke-MakeDirectory {
    param([Parameter(Mandatory, Position = 0)][string]$Path)
    $null = New-Item -Path $Path -ItemType Directory -Force
    Set-Location -Path $Path
}
function Invoke-RemoveForce { Remove-Item -Recurse -Force @args }
function Invoke-Reload { & $PROFILE }
function Invoke-EditProfile { code $PROFILE }
function Invoke-OpenExplorer {
    param([Parameter(Position = 0)][string]$Path = '.')
    Start-Process -FilePath 'explorer.exe' -ArgumentList (Resolve-Path -Path $Path)
}
function Invoke-OpenTerminalHere { Start-Process -FilePath 'wt.exe' -ArgumentList "-d `"$(Get-Location)`"" }
function Invoke-CdFromClipboard {
    param()
    $clip = Get-Clipboard -ErrorAction SilentlyContinue
    if ($clip -and (Test-Path -Path $clip)) {
        Set-Location -Path $clip
    }
    else {
        Write-Warning -Message 'Clipboard does not contain a valid path'
    }
}

Set-Alias -Name 'c'       -Value Invoke-ClearHost       -Option AllScope -Force
Set-Alias -Name 'ls'      -Value Invoke-ListDirectory   -Option AllScope -Force
Set-Alias -Name 'la'      -Value Invoke-ListAll         -Option AllScope -Force
Set-Alias -Name 'll'      -Value Invoke-ListDetailed    -Option AllScope -Force
Set-Alias -Name 'which'   -Value Invoke-WhichCommand    -Option AllScope -Force
Set-Alias -Name 'touch'   -Value Invoke-TouchFile       -Option AllScope -Force
Set-Alias -Name 'mkcd'    -Value Invoke-MakeDirectory   -Option AllScope -Force
Set-Alias -Name 'rmrf'    -Value Invoke-RemoveForce     -Option AllScope -Force
Set-Alias -Name 'reload'  -Value Invoke-Reload          -Option AllScope -Force
Set-Alias -Name 'ep'      -Value Invoke-EditProfile     -Option AllScope -Force
Set-Alias -Name 'e.'      -Value Invoke-OpenExplorer    -Option AllScope -Force
Set-Alias -Name 'wt.'     -Value Invoke-OpenTerminalHere -Option AllScope -Force
Set-Alias -Name 'cdf'     -Value Invoke-CdFromClipboard -Option AllScope -Force

# Common typo fixes
Set-Alias -Name 'cls'     -Value Clear-Host             -Option AllScope -Force
Set-Alias -Name 'grep'    -Value Select-String          -Option AllScope -Force
Set-Alias -Name 'head'    -Value Select-Object          -Option AllScope -Force

# Tool Aliases

if (Get-Command -Name 'eza' -ErrorAction SilentlyContinue) {
    function Invoke-EzaDefault  { eza @args }
    function Invoke-EzaLong     { eza -l --git @args }
    function Invoke-EzaAll      { eza -a @args }
    function Invoke-EzaLongAll  { eza -la --git @args }
    function Invoke-EzaTree     { eza --tree --git-ignore @args }
    function Invoke-EzaTree2    { eza --tree -L 2 --git-ignore @args }
    Set-Alias -Name 'ls'   -Value Invoke-EzaDefault  -Option AllScope -Force
    Set-Alias -Name 'll'   -Value Invoke-EzaLong     -Option AllScope -Force
    Set-Alias -Name 'la'   -Value Invoke-EzaAll      -Option AllScope -Force
    Set-Alias -Name 'lla'  -Value Invoke-EzaLongAll  -Option AllScope -Force
    Set-Alias -Name 'tree' -Value Invoke-EzaTree     -Option AllScope -Force
    Set-Alias -Name 'lt'   -Value Invoke-EzaTree2    -Option AllScope -Force
}

if (Get-Command -Name 'bat' -ErrorAction SilentlyContinue) {
    function Invoke-BatPreview { bat --style=auto @args }
    Set-Alias -Name 'cat'     -Value bat                -Option AllScope -Force
    Set-Alias -Name 'preview' -Value Invoke-BatPreview  -Option AllScope -Force
}

if (Get-Command -Name 'ripgrep' -ErrorAction SilentlyContinue) {
    Set-Alias -Name 'rg'      -Value ripgrep             -Option AllScope -Force
    Set-Alias -Name 'grep'    -Value ripgrep             -Option AllScope -Force
}

if (Get-Command -Name 'fzf' -ErrorAction SilentlyContinue) {
    Set-Alias -Name 'fzf'     -Value fzf                  -Option AllScope -Force
}

if (Get-Command -Name 'fd' -ErrorAction SilentlyContinue) {
    Set-Alias -Name 'fd'      -Value fd                   -Option AllScope -Force
}

if (Get-Command -Name 'httpie' -ErrorAction SilentlyContinue) {
    Set-Alias -Name 'http'    -Value http                 -Option AllScope -Force
}

if (Get-Command -Name 'tldr' -ErrorAction SilentlyContinue) {
    Set-Alias -Name 'tldr'    -Value tldr                 -Option AllScope -Force
}

if (Get-Command -Name 'yt-dlp' -ErrorAction SilentlyContinue) {
    function Invoke-YtDlp { yt-dlp @args }
    Set-Alias -Name 'ytdl' -Value Invoke-YtDlp -Option AllScope -Force
}

if (Get-Command -Name 'gh' -ErrorAction SilentlyContinue) {
    Set-Alias -Name 'gh'      -Value gh                   -Option AllScope -Force
}

if (Get-Command -Name 'glab' -ErrorAction SilentlyContinue) {
    Set-Alias -Name 'glab'    -Value glab                 -Option AllScope -Force
}

if (Get-Command -Name 'lazygit' -ErrorAction SilentlyContinue) {
    Set-Alias -Name 'lg'      -Value lazygit              -Option AllScope -Force
}

if (Get-Command -Name 'gitui' -ErrorAction SilentlyContinue) {
    Set-Alias -Name 'gu'      -Value gitui                -Option AllScope -Force
}

if (Get-Command -Name 'git-delta' -ErrorAction SilentlyContinue) {
    Set-Alias -Name 'd'       -Value 'git-delta'          -Option AllScope -Force
}

if (Get-Command -Name 'starship' -ErrorAction SilentlyContinue) {
    Set-Alias -Name 'star'    -Value starship             -Option AllScope -Force
}

if (Get-Command -Name 'zoxide' -ErrorAction SilentlyContinue) {
    Set-Alias -Name 'z'       -Value 'zoxide'             -Option AllScope -Force
}

if (Get-Command -Name 'ollama' -ErrorAction SilentlyContinue) {
    Set-Alias -Name 'ollama'  -Value ollama               -Option AllScope -Force
}

if (Get-Command -Name 'llm' -ErrorAction SilentlyContinue) {
    Set-Alias -Name 'llm'     -Value llm                  -Option AllScope -Force
}

if (Get-Command -Name 'tmux' -ErrorAction SilentlyContinue) {
    Set-Alias -Name 'tmux'    -Value tmux                 -Option AllScope -Force
}

if (Get-Command -Name 'ranger' -ErrorAction SilentlyContinue) {
    Set-Alias -Name 'ranger'  -Value ranger                -Option AllScope -Force
}

if (Get-Command -Name 'hyperfine' -ErrorAction SilentlyContinue) {
    Set-Alias -Name 'bench'   -Value hyperfine             -Option AllScope -Force
}

if (Get-Command -Name 'bottom' -ErrorAction SilentlyContinue) {
    Set-Alias -Name 'btm'     -Value btm                   -Option AllScope -Force
}

if (Get-Command -Name 'duf' -ErrorAction SilentlyContinue) {
    Set-Alias -Name 'duf'     -Value duf                   -Option AllScope -Force
}

if (Get-Command -Name 'nmap' -ErrorAction SilentlyContinue) {
    Set-Alias -Name 'nmap'    -Value nmap                  -Option AllScope -Force
}

if (Get-Command -Name 'gcloud' -ErrorAction SilentlyContinue) {
    Set-Alias -Name 'gcloud'  -Value gcloud                -Option AllScope -Force
    Set-Alias -Name 'gcp'     -Value gcloud                -Option AllScope -Force
}

if (Get-Command -Name 'vault' -ErrorAction SilentlyContinue) {
    Set-Alias -Name 'vault'   -Value vault                 -Option AllScope -Force
}

if (Get-Command -Name 'op' -ErrorAction SilentlyContinue) {
    Set-Alias -Name 'op'      -Value op                    -Option AllScope -Force
}

if (Get-Command -Name 'packer' -ErrorAction SilentlyContinue) {
    Set-Alias -Name 'packer'  -Value packer                -Option AllScope -Force
}

if (Get-Command -Name 'vagrant' -ErrorAction SilentlyContinue) {
    Set-Alias -Name 'vagrant' -Value vagrant               -Option AllScope -Force
}

if (Get-Command -Name 'gradle' -ErrorAction SilentlyContinue) {
    Set-Alias -Name 'gradle'  -Value gradle                -Option AllScope -Force
}

if (Get-Command -Name 'mvn' -ErrorAction SilentlyContinue) {
    Set-Alias -Name 'mvn'     -Value mvn                   -Option AllScope -Force
}

if (Get-Command -Name 'yarn' -ErrorAction SilentlyContinue) {
    Set-Alias -Name 'yarn'    -Value yarn                  -Option AllScope -Force
}

if (Get-Command -Name 'pnpm' -ErrorAction SilentlyContinue) {
    Set-Alias -Name 'pnpm'    -Value pnpm                  -Option AllScope -Force
}

if (Get-Command -Name 'uv' -ErrorAction SilentlyContinue) {
    Set-Alias -Name 'uv'      -Value uv                    -Option AllScope -Force
}

if (Get-Command -Name 'poetry' -ErrorAction SilentlyContinue) {
    Set-Alias -Name 'poetry'  -Value poetry                -Option AllScope -Force
}

# Docker Aliases

if (Get-Command -Name 'docker' -ErrorAction SilentlyContinue) {
    function Invoke-DockerPS { & docker ps @args }
    function Invoke-DockerPSAll { & docker ps -a @args }
    function Invoke-DockerImages { & docker images @args }
    function Invoke-DockerCompose { & docker compose @args }
    function Invoke-DockerComposeUp { & docker compose up -d @args }
    function Invoke-DockerComposeDown { & docker compose down @args }
    function Invoke-DockerComposeLogs { & docker compose logs -f @args }
    function Invoke-DockerPrune { & docker system prune -af @args }
    function Invoke-DockerExecBash {
        param([Parameter(Mandatory, Position = 0)][string]$ContainerName)
        & docker exec -it $ContainerName /bin/bash
    }

    Set-Alias -Name 'dps'   -Value Invoke-DockerPS          -Option AllScope -Force
    Set-Alias -Name 'dpsa'  -Value Invoke-DockerPSAll       -Option AllScope -Force
    Set-Alias -Name 'di'    -Value Invoke-DockerImages      -Option AllScope -Force
    Set-Alias -Name 'dc'    -Value Invoke-DockerCompose     -Option AllScope -Force
    Set-Alias -Name 'dcu'   -Value Invoke-DockerComposeUp   -Option AllScope -Force
    Set-Alias -Name 'dcd'   -Value Invoke-DockerComposeDown -Option AllScope -Force
    Set-Alias -Name 'dcl'   -Value Invoke-DockerComposeLogs -Option AllScope -Force
    Set-Alias -Name 'dpr'   -Value Invoke-DockerPrune       -Option AllScope -Force
    Set-Alias -Name 'dex'   -Value Invoke-DockerExecBash    -Option AllScope -Force
}

# .NET / Build Aliases

if (Get-Command -Name 'dotnet' -ErrorAction SilentlyContinue) {
    function Invoke-DotnetBuild { & dotnet build @args }
    function Invoke-DotnetRun { & dotnet run @args }
    function Invoke-DotnetTest { & dotnet test @args }
    function Invoke-DotnetClean { & dotnet clean @args }
    function Invoke-DotnetRestore { & dotnet restore @args }
    function Invoke-DotnetPublish { & dotnet publish @args }
    function Invoke-DotnetWatch { & dotnet watch @args }
    function Invoke-DotnetFormat { & dotnet format @args }

    Set-Alias -Name 'dnb'  -Value Invoke-DotnetBuild   -Option AllScope -Force
    Set-Alias -Name 'dnr'  -Value Invoke-DotnetRun     -Option AllScope -Force
    Set-Alias -Name 'dnt'  -Value Invoke-DotnetTest    -Option AllScope -Force
    Set-Alias -Name 'dnc'  -Value Invoke-DotnetClean   -Option AllScope -Force
    Set-Alias -Name 'dns'  -Value Invoke-DotnetRestore -Option AllScope -Force
    Set-Alias -Name 'dnp'  -Value Invoke-DotnetPublish -Option AllScope -Force
    Set-Alias -Name 'dnw'  -Value Invoke-DotnetWatch   -Option AllScope -Force
    Set-Alias -Name 'dnf'  -Value Invoke-DotnetFormat  -Option AllScope -Force
}

# Package Manager Aliases

if (Get-Command -Name 'winget' -ErrorAction SilentlyContinue) {
    function Invoke-WingetSearch { & winget search @args }
    function Invoke-WingetInstall { & winget install @args }
    function Invoke-WingetUpgrade { & winget upgrade --all --include-unknown @args }
    function Invoke-WingetList { & winget list @args }

    Set-Alias -Name 'wgs' -Value Invoke-WingetSearch  -Option AllScope -Force
    Set-Alias -Name 'wgi' -Value Invoke-WingetInstall -Option AllScope -Force
    Set-Alias -Name 'wgu' -Value Invoke-WingetUpgrade -Option AllScope -Force
    Set-Alias -Name 'wgl' -Value Invoke-WingetList    -Option AllScope -Force
}

if (Get-Command -Name 'choco' -ErrorAction SilentlyContinue) {
    function Invoke-ChocoInstall { & choco install @args -y }
    function Invoke-ChocoUpgrade { & choco upgrade all -y @args }
    function Invoke-ChocoSearch { & choco search @args }
    function Invoke-ChocoList { & choco list @args }

    Set-Alias -Name 'chi' -Value Invoke-ChocoInstall -Option AllScope -Force
    Set-Alias -Name 'chu' -Value Invoke-ChocoUpgrade -Option AllScope -Force
    Set-Alias -Name 'chs' -Value Invoke-ChocoSearch  -Option AllScope -Force
    Set-Alias -Name 'chl' -Value Invoke-ChocoList    -Option AllScope -Force
}

if (Get-Command -Name 'scoop' -ErrorAction SilentlyContinue) {
    function Invoke-ScoopSearch { & scoop search @args }
    function Invoke-ScoopInstall { & scoop install @args }
    function Invoke-ScoopUpdate { & scoop update * @args }
    function Invoke-ScoopList { & scoop list @args }

    Set-Alias -Name 'scs' -Value Invoke-ScoopSearch  -Option AllScope -Force
    Set-Alias -Name 'sci' -Value Invoke-ScoopInstall -Option AllScope -Force
    Set-Alias -Name 'scu' -Value Invoke-ScoopUpdate  -Option AllScope -Force
    Set-Alias -Name 'scl' -Value Invoke-ScoopList    -Option AllScope -Force
}

# Alias Help

function Show-ProfileAliases {
    param(
        [Parameter(Position = 0)]
        [ValidateSet('Git', 'System', 'Docker', 'Dotnet', 'Package', 'Navigation', 'All')]
        [string]$Category = 'All'
    )

    $tc = $Global:Theme
    $aliasGroups = @{
        Git        = @('gs', 'ga', 'gaa', 'gc', 'gcm', 'gp', 'gpl', 'gf', 'gl', 'glf', 'gd', 'gds', 'gb', 'gco', 'gst', 'gsp', 'grs', 'grb', 'gcp', 'gt', 'grv', 'gcl', 'gam', 'gbl', 'gcln')
        System     = @('c', 'ls', 'la', 'll', 'which', 'touch', 'mkcd', 'rmrf', 'reload', 'ep', 'e.', 'wt.', 'cdf')
        Docker     = @('dps', 'dpsa', 'di', 'dc', 'dcu', 'dcd', 'dcl', 'dpr', 'dex')
        Dotnet     = @('dnb', 'dnr', 'dnt', 'dnc', 'dns', 'dnp', 'dnw', 'dnf')
        Package    = @('wgs', 'wgi', 'wgu', 'wgl', 'chi', 'chu', 'chs', 'chl', 'scs', 'sci', 'scu', 'scl')
        Navigation = @('up', 'bd', 'fd', 'dh', 'go', 'bm', 'bms', 'cdd', 'z')
    }

    $groups = if ($Category -eq 'All') { $aliasGroups.Keys } else { @($Category) }

    foreach ($group in ($groups | Sort-Object)) {
        Write-Host -Object "`n  [$group]" -ForegroundColor $tc.Primary
        foreach ($aliasName in $aliasGroups[$group]) {
            $a = Get-Alias -Name $aliasName -ErrorAction SilentlyContinue
            if ($a) {
                $defStr = $a.Definition
                Write-Host -Object "    $($aliasName.PadRight(8))" -ForegroundColor $tc.Accent -NoNewline
                Write-Host -Object " -> $defStr" -ForegroundColor $tc.Text
            }
        }
    }
    Write-Host ''
}

# ── Extra Tool Aliases ─────────────────────────────────────────────────────

# VS Code
function Invoke-VSCode {
    param([Parameter(Position = 0)][string]$Path = '.')
    code $Path
}
Set-Alias -Name 'vsc' -Value Invoke-VSCode -Option AllScope -Force

# Notepad++ (if installed)
if (Get-Command -Name 'notepad++' -ErrorAction SilentlyContinue) {
    function Invoke-NotepadPP { notepad++ @args }
    Set-Alias -Name 'np' -Value Invoke-NotepadPP -Option AllScope -Force
}
elseif (Test-Path "${env:ProgramFiles}\Notepad++\notepad++.exe") {
    function Invoke-NotepadPP { & "${env:ProgramFiles}\Notepad++\notepad++.exe" @args }
    Set-Alias -Name 'np' -Value Invoke-NotepadPP -Option AllScope -Force
}

# Formatting shortcuts
function Invoke-FormatTableAuto  { $input | Format-Table -AutoSize @args }
function Invoke-FormatListAll    { $input | Format-List * @args }
function Invoke-MeasureObjects   { $input | Measure-Object @args }
Set-Alias -Name 'ft'      -Value Invoke-FormatTableAuto -Option AllScope -Force
Set-Alias -Name 'fl'      -Value Invoke-FormatListAll   -Option AllScope -Force
Set-Alias -Name 'measure' -Value Invoke-MeasureObjects  -Option AllScope -Force

# Clipboard pipeline — pipe anything into clipboard
function Out-Clipboard {
    <#
    .SYNOPSIS
        Pipe output to the clipboard. Usage: Get-Process | Out-Clipboard
    #>
    [CmdletBinding()]
    param(
        [Parameter(ValueFromPipeline)]
        [object]$InputObject
    )
    begin   { $lines = [System.Collections.Generic.List[string]]::new() }
    process { $lines.Add(($InputObject | Out-String -Width 4096).TrimEnd()) }
    end     {
        $text = $lines -join "`n"
        Set-Clipboard -Value $text
        Write-Host "  Copied $($lines.Count) line(s) to clipboard." -ForegroundColor $script:Theme.Success
    }
}
Set-Alias -Name 'toclip' -Value Out-Clipboard -Option AllScope -Force