[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingWriteHost', '', Justification = 'Tool status requires colored output')]
param()

#region ─────────────────────────────────────────────────────────────────────────────
# Tool Registry & Management
# Lazy-loading, auto-install, version checking for 48+ CLI tools
# Package managers: Scoop (primary), Winget (fallback)
# ─────────────────────────────────────────────────────────────────────────────

$script:ToolRegistry = @{
    # Prompt/Shell Enhancement
    'oh-my-posh' = @{
        Scoop = 'oh-my-posh'
        Winget = 'OhMyPosh.OhMyPosh'
        VersionCmd = 'oh-my-posh --version'
        Description = 'Prompt theme engine'
        Category = 'Prompt'
    }
    'posh-git' = @{
        Scoop = 'posh-git'
        Winget = 'Microsoft.PowerShell'
        VersionCmd = '$PSVersionTable.PSVersion'
        Description = 'Git in PowerShell prompt'
        Category = 'Prompt'
    }
    'starship' = @{
        Scoop = 'starship'
        Winget = 'Starship.Starship'
        VersionCmd = 'starship --version'
        Description = 'Cross-shell prompt'
        Category = 'Prompt'
    }
    'zoxide' = @{
        Scoop = 'zoxide'
        Winget = 'ajeetdsouza.zoxide'
        VersionCmd = 'zoxide --version'
        Description = 'Smarter cd command'
        Category = 'Navigation'
    }

    # File Navigation
    'fzf' = @{
        Scoop = 'fzf'
        Winget = 'fzf'
        VersionCmd = 'fzf --version'
        Description = 'Fuzzy finder'
        Category = 'Navigation'
    }
    'eza' = @{
        Scoop = 'eza'
        Winget = 'eza-community.eza'
        VersionCmd = 'eza --version'
        Description = 'Modern ls alternative'
        Category = 'FileOps'
    }
    'fd' = @{
        Scoop = 'fd'
        Winget = 'fd.fd'
        VersionCmd = 'fd --version'
        Description = 'Fast find alternative'
        Category = 'Search'
    }
    'ranger' = @{
        Scoop = 'ranger'
        Winget = 'ranger.ranger'
        VersionCmd = 'ranger --version'
        Description = 'TUI file manager'
        Category = 'Navigation'
    }

    # Output/Display
    'bat' = @{
        Scoop = 'bat'
        Winget = 'sharkdp.bat'
        VersionCmd = 'bat --version'
        Description = 'Cat with syntax highlighting'
        Category = 'Output'
    }
    'tldr' = @{
        Scoop = 'tldr'
        Winget = 'tldr-pages.tldr'
        VersionCmd = 'tldr --version'
        Description = 'Simplified man pages'
        Category = 'Help'
    }
    'bottom' = @{
        Scoop = 'bottom'
        Winget = 'bottom.bottom'
        VersionCmd = 'btm --version'
        Description = 'System monitor'
        Category = 'System'
    }
    'dust' = @{
        Scoop = 'dust'
        Winget = $null
        VersionCmd = 'dust --version'
        Description = 'Disk usage analyzer'
        Category = 'System'
    }
    'duf' = @{
        Scoop = 'duf'
        Winget = $null
        VersionCmd = 'duf --version'
        Description = 'Disk usage friendly'
        Category = 'System'
    }

    # Search/Processing
    'ripgrep' = @{
        Scoop = 'ripgrep'
        Winget = 'BurntSushi.ripgrep'
        VersionCmd = 'rg --version'
        Description = 'Modern grep'
        Category = 'Search'
    }
    'jq' = @{
        Scoop = 'jq'
        Winget = 'jq-labs jq'
        VersionCmd = 'jq --version'
        Description = 'JSON processor'
        Category = 'Processing'
    }
    'shellcheck' = @{
        Scoop = 'shellcheck'
        Winget = 'koalaman.shellcheck'
        VersionCmd = 'shellcheck --version'
        Description = 'Shell script linter'
        Category = 'Lint'
    }
    'hyperfine' = @{
        Scoop = 'hyperfine'
        Winget = 'hyperfine.hyperfine'
        VersionCmd = 'hyperfine --version'
        Description = 'Benchmarking tool'
        Category = 'Performance'
    }

    # Git Tools
    'gh' = @{
        Scoop = 'gh'
        Winget = 'GitHub.cli'
        VersionCmd = 'gh --version'
        Description = 'GitHub CLI'
        Category = 'Git'
    }
    'glab' = @{
        Scoop = 'glab'
        Winget = 'GitLab.cli'
        VersionCmd = 'glab --version'
        Description = 'GitLab CLI'
        Category = 'Git'
    }
    'git-delta' = @{
        Scoop = 'git-delta'
        Winget = 'git-delta.git-delta'
        VersionCmd = 'git-delta --version'
        Description = 'Better git diff'
        Category = 'Git'
    }
    'lazygit' = @{
        Scoop = 'lazygit'
        Winget = 'lazygit.lazygit'
        VersionCmd = 'lazygit --version'
        Description = 'TUI for git'
        Category = 'Git'
    }
    'gitui' = @{
        Scoop = 'gitui'
        Winget = 'gitui.gitui'
        VersionCmd = 'gitui --version'
        Description = 'Fast git TUI'
        Category = 'Git'
    }

    # Downloads
    'yt-dlp' = @{
        Scoop = 'yt-dlp'
        Winget = 'yt-dlp.yt-dlp'
        VersionCmd = 'yt-dlp --version'
        Description = 'YouTube downloader'
        Category = 'Download'
    }
    'aria2' = @{
        Scoop = 'aria2'
        Winget = $null
        VersionCmd = 'aria2c --version'
        Description = 'Download accelerator'
        Category = 'Download'
    }
    'wget' = @{
        Scoop = 'wget'
        Winget = $null
        VersionCmd = 'wget --version'
        Description = 'Download utility'
        Category = 'Download'
    }
    'curl' = @{
        Scoop = 'curl'
        Winget = $null
        VersionCmd = 'curl --version'
        Description = 'HTTP client'
        Category = 'Network'
    }

    # Network
    'nmap' = @{
        Scoop = 'nmap'
        Winget = 'nmap.nmap'
        VersionCmd = 'nmap --version'
        Description = 'Network scanner'
        Category = 'Network'
    }
    'netcat' = @{
        Scoop = 'netcat'
        Winget = $null
        VersionCmd = 'nc -h'
        Description = 'Network utility'
        Category = 'Network'
    }
    'mosh' = @{
        Scoop = 'mosh'
        Winget = 'mobile-shell.mosh'
        VersionCmd = 'mosh --version'
        Description = 'Mobile shell'
        Category = 'Network'
    }
    'fping' = @{
        Scoop = 'fping'
        Winget = $null
        VersionCmd = 'fping -v'
        Description = 'Fast ping'
        Category = 'Network'
    }
    'httpie' = @{
        Scoop = 'httpie'
        Winget = 'cli-httpie.httpie'
        VersionCmd = 'http --version'
        Description = 'HTTP client alternative'
        Category = 'Network'
    }

    # Dev Tools
    'docker' = @{
        Scoop = 'docker'
        Winget = 'Docker.DockerDesktop'
        VersionCmd = 'docker --version'
        Description = 'Container runtime'
        Category = 'DevOps'
    }
    'gradle' = @{
        Scoop = 'gradle'
        Winget = 'Apache.Gradle'
        VersionCmd = 'gradle --version'
        Description = 'Build tool (Java)'
        Category = 'Build'
    }
    'maven' = @{
        Scoop = 'maven'
        Winget = 'Apache.Maven'
        VersionCmd = 'mvn --version'
        Description = 'Build tool (Java)'
        Category = 'Build'
    }
    'yarn' = @{
        Scoop = 'yarn'
        Winget = 'Yarn.Yarn'
        VersionCmd = 'yarn --version'
        Description = 'Package manager (Node)'
        Category = 'PackageManager'
    }
    'pnpm' = @{
        Scoop = 'pnpm'
        Winget = 'pnpm.pnpm'
        VersionCmd = 'pnpm --version'
        Description = 'Fast Node package manager'
        Category = 'PackageManager'
    }
    'uv' = @{
        Scoop = 'uv'
        Winget = 'astral-sh.uv'
        VersionCmd = 'uv --version'
        Description = 'Fast Python package manager'
        Category = 'PackageManager'
    }
    'poetry' = @{
        Scoop = 'poetry'
        Winget = 'Poetry.Poetry'
        VersionCmd = 'poetry --version'
        Description = 'Python dependency management'
        Category = 'PackageManager'
    }

    # Build/VM
    'packer' = @{
        Scoop = 'packer'
        Winget = 'HashiCorp.Packer'
        VersionCmd = 'packer --version'
        Description = 'Image builder'
        Category = 'DevOps'
    }
    'vagrant' = @{
        Scoop = 'vagrant'
        Winget = 'HashiCorp.Vagrant'
        VersionCmd = 'vagrant --version'
        Description = 'VM manager'
        Category = 'DevOps'
    }

    # AI/ML
    'ollama' = @{
        Scoop = 'ollama'
        Winget = 'Ollama.Ollama'
        VersionCmd = 'ollama --version'
        Description = 'Local LLM'
        Category = 'AI'
    }
    'llm' = @{
        Scoop = 'llm'
        Winget = $null
        VersionCmd = 'llm --version'
        Description = 'CLI for LLMs'
        Category = 'AI'
    }

    # Cloud/Security
    'gcloud' = @{
        Scoop = 'gcloud'
        Winget = 'Google.CloudSDK'
        VersionCmd = 'gcloud --version'
        Description = 'GCP CLI'
        Category = 'Cloud'
    }
    'vault' = @{
        Scoop = 'vault'
        Winget = 'HashiCorp.Vault'
        VersionCmd = 'vault --version'
        Description = 'Secrets management'
        Category = 'Security'
    }
    '1password-cli' = @{
        Scoop = '1password-cli'
        Winget = '1Password.1Password'
        VersionCmd = 'op --version'
        Description = 'Password manager'
        Category = 'Security'
    }
    'awscli' = @{
        Scoop = 'aws'
        Winget = 'Amazon.AWSCLIV2'
        VersionCmd = 'aws --version'
        Description = 'AWS CLI'
        Category = 'Cloud'
    }

    # Terminal
    'tmux' = @{
        Scoop = 'tmux'
        Winget = 'tmux.tmux'
        VersionCmd = 'tmux -V'
        Description = 'Terminal multiplexer'
        Category = 'Terminal'
    }
}

$script:LoadedTools = @{}
$script:ScoopBucketsNeeded = @('extras', 'games')
$script:ScoopBucketsAdded = $false

function Initialize-ScoopBuckets {
    if ($script:ScoopBucketsAdded) { return }
    
    $cacheFile = Join-Path -Path $script:ProfileRoot -ChildPath 'Cache' | Join-Path -ChildPath 'scoop-buckets.cache'
    $cacheAge = if (Test-Path $cacheFile) { (Get-Date) - (Get-Item $cacheFile).LastWriteTime } else { [TimeSpan]::FromDays(7) }
    
    if ($cacheAge.TotalHours -lt 168) {
        $script:ScoopBucketsAdded = $true
        return
    }
    
    foreach ($bucket in $script:ScoopBucketsNeeded) {
        $buckets = scoop bucket list 2>&1 | Out-String
        if ($buckets -notmatch $bucket) {
            scoop bucket add $bucket 2>&1 | Out-Null
        }
    }
    
    $null = New-Item -Path $cacheFile -ItemType File -Force
    $script:ScoopBucketsAdded = $true
}

function Get-ToolStatus {
    <#
    .SYNOPSIS
        Check if a tool is available and get its version.
    .PARAMETER Name
        Tool name from registry.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateScript({ $script:ToolRegistry.ContainsKey($_) })]
        [string]$Name
    )
    
    if ($script:LoadedTools.ContainsKey($Name)) {
        return $script:LoadedTools[$Name]
    }
    
    $tool = $script:ToolRegistry[$Name]
    $cmd = Get-Command -Name $Name -ErrorAction SilentlyContinue
    
    if ($cmd) {
        $version = try { 
            if ($tool.VersionCmd) {
                $result = Invoke-Expression -Command $tool.VersionCmd 2>$null
                if ($result -match '(\d+\.\d+\.\d+)') { $matches[1] }
                elseif ($result -is [string]) { $result.Split(' ')[0] }
                else { 'unknown' }
            }
        } catch { 'unknown' }
        
        $status = [PSCustomObject]@{
            Name = $Name
            Available = $true
            Path = $cmd.Source
            Version = $version
            Category = $tool.Category
            Description = $tool.Description
            Installed = $true
        }
    }
    else {
        $status = [PSCustomObject]@{
            Name = $Name
            Available = $false
            Path = $null
            Version = $null
            Category = $tool.Category
            Description = $tool.Description
            Installed = $false
        }
    }
    
    $script:LoadedTools[$Name] = $status
    return $status
}

function Install-Tool {
    <#
    .SYNOPSIS
        Install a tool using scoop (primary) or winget (fallback).
    .PARAMETER Name
        Tool name to install.
    .PARAMETER Force
        Reinstall even if already installed.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateScript({ $script:ToolRegistry.ContainsKey($_) })]
        [string]$Name,
        [switch]$Force
    )
    
    $status = Get-ToolStatus -Name $Name
    if ($status.Available -and -not $Force) {
        Write-Warning -Message "$Name is already installed at $($status.Path)"
        return $false
    }
    
    $tool = $script:ToolRegistry[$Name]
    $scoopExists = Get-Command -Name 'scoop' -ErrorAction SilentlyContinue
    $wingetExists = Get-Command -Name 'winget' -ErrorAction SilentlyContinue
    
    $installed = $false
    
    if ($scoopExists -and $tool.Scoop) {
        Initialize-ScoopBuckets
        try {
            if ($Force) {
                scoop update $tool.Scoop 2>$null
            }
            scoop install $tool.Scoop -i
            $installed = $true
            Write-Host -Object "Installed $Name via scoop" -ForegroundColor Green
        }
        catch {
            Write-Warning -Message "Scoop install failed: $($_.Exception.Message)"
        }
    }
    
    if (-not $installed -and $wingetExists -and $tool.Winget) {
        try {
            winget install --id $tool.Winget --silent --accept-package-agreements --accept-source-agreements
            $installed = $true
            Write-Host -Object "Installed $Name via winget" -ForegroundColor Green
        }
        catch {
            Write-Warning -Message "Winget install failed: $($_.Exception.Message)"
        }
    }
    
    if ($installed) {
        $script:LoadedTools.Remove($Name)
        $null = Get-ToolStatus -Name $Name
        return $true
    }
    
    Write-Error -Message "Failed to install $Name"
    return $false
}

function Update-Tool {
    <#
    .SYNOPSIS
        Check for updates and update a tool if available.
    .PARAMETER Name
        Tool name to update.
    .PARAMETER CheckOnly
        Only check for updates without installing.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateScript({ $script:ToolRegistry.ContainsKey($_) })]
        [string]$Name,
        [switch]$CheckOnly
    )
    
    $status = Get-ToolStatus -Name $Name
    if (-not $status.Available) {
        Write-Warning -Message "$Name is not installed"
        return $null
    }
    
    $scoopExists = Get-Command -Name 'scoop' -ErrorAction SilentlyContinue
    $wingetExists = Get-Command -Name 'winget' -ErrorAction SilentlyContinue
    
    if ($scoopExists) {
        $tool = $script:ToolRegistry[$Name]
        $updateInfo = scoop checkup $tool.Scoop 2>$null
        
        if ($CheckOnly) {
            return [PSCustomObject]@{
                Name = $Name
                CurrentVersion = $status.Version
                UpdateAvailable = $updateInfo -match 'update'
            }
        }
        
        if ($updateInfo -match 'update') {
            scoop update $tool.Scoop
            Write-Host -Object "Updated $Name" -ForegroundColor Green
        }
    }
    
    $script:LoadedTools.Remove($Name)
    return Get-ToolStatus -Name $Name
}

function Remove-Tool {
    <#
    .SYNOPSIS
        Uninstall a tool.
    .PARAMETER Name
        Tool name to remove.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateScript({ $script:ToolRegistry.ContainsKey($_) })]
        [string]$Name
    )
    
    $status = Get-ToolStatus -Name $Name
    if (-not $status.Available) {
        Write-Warning -Message "$Name is not installed"
        return $false
    }
    
    $scoopExists = Get-Command -Name 'scoop' -ErrorAction SilentlyContinue
    $wingetExists = Get-Command -Name 'winget' -ErrorAction SilentlyContinue
    
    $removed = $false
    
    if ($scoopExists) {
        $tool = $script:ToolRegistry[$Name]
        try {
            scoop uninstall $tool.Scoop
            $removed = $true
            Write-Host -Object "Removed $Name via scoop" -ForegroundColor Green
        }
        catch {
            Write-Warning -Message "Scoop remove failed: $($_.Exception.Message)"
        }
    }
    
    if (-not $removed -and $wingetExists -and $script:ToolRegistry[$Name].Winget) {
        try {
            winget uninstall --id $script:ToolRegistry[$Name].Winget --silent
            $removed = $true
            Write-Host -Object "Removed $Name via winget" -ForegroundColor Green
        }
        catch {
            Write-Warning -Message "Winget remove failed: $($_.Exception.Message)"
        }
    }
    
    if ($removed) {
        $script:LoadedTools.Remove($Name)
        return $true
    }
    
    Write-Error -Message "Failed to remove $Name"
    return $false
}

function Show-ToolList {
    <#
    .SYNOPSIS
        List all tools with their status.
    .PARAMETER Category
        Filter by category.
    .PARAMETER InstalledOnly
        Show only installed tools.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Position = 0)]
        [string]$Category,
        [switch]$InstalledOnly
    )
    
    $tc = $Global:Theme
    
    $tools = @()
    foreach ($name in $script:ToolRegistry.Keys | Sort-Object) {
        $status = Get-ToolStatus -Name $name
        
        if ($InstalledOnly -and -not $status.Available) { continue }
        if ($Category -and $status.Category -ne $Category) { continue }
        
        $tools += $status
    }
    
    Write-Host ''
    Write-Host -Object "  ╔════════════════════════════════════════════════════════════════╗" -ForegroundColor $tc.Primary
    Write-Host -Object "  ║                    TOOL REGISTRY STATUS                        ║" -ForegroundColor $tc.Primary
    Write-Host -Object "  ╠════════════════════════════════════════════════════════════════╣" -ForegroundColor $tc.Primary
    
    foreach ($tool in $tools) {
        $statusIcon = if ($tool.Available) { '✓' } else { '✗' }
        $statusColor = if ($tool.Available) { $tc.GitClean } else { $tc.Error }
        
        Write-Host -Object "  ║ " -NoNewline -ForegroundColor $tc.Primary
        Write-Host -Object $statusIcon.PadRight(2) -NoNewline -ForegroundColor $statusColor
        Write-Host -Object $tool.Name.PadRight(18) -NoNewline -ForegroundColor $tc.Accent
        Write-Host -Object $tool.Category.PadRight(12) -NoNewline -ForegroundColor $tc.Muted
        Write-Host -Object $tool.Version.PadRight(12) -NoNewline -ForegroundColor $tc.Text
        Write-Host -Object $tool.Description.PadRight(20) -NoNewline -ForegroundColor $tc.Text
        Write-Host -Object " ║" -ForegroundColor $tc.Primary
    }
    
    Write-Host -Object "  ╚════════════════════════════════════════════════════════════════╝" -ForegroundColor $tc.Primary
    Write-Host ''
    Write-Host -Object "  Total: $($tools.Count) tools" -ForegroundColor $tc.Muted
    if ($InstalledOnly) {
        $installed = ($tools | Where-Object { $_.Available }).Count
        Write-Host -Object "  Installed: $installed" -ForegroundColor $tc.Muted
    }
}

function Initialize-ToolOnDemand {
    <#
    .SYNOPSIS
        Lazy-load a tool, installing if necessary.
    .PARAMETER Name
        Tool name to initialize.
    .PARAMETER AutoInstall
        Install tool if not available.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateScript({ $script:ToolRegistry.ContainsKey($_) })]
        [string]$Name,
        [switch]$AutoInstall
    )
    
    $status = Get-ToolStatus -Name $Name
    
    if (-not $status.Available) {
        if ($AutoInstall -or $Global:ProfileConfig.EnableToolAutoInstall) {
            $null = Install-Tool -Name $Name
            $status = Get-ToolStatus -Name $Name
        }
    }
    
    return $status
}

Set-Alias -Name 'tool' -Value Get-ToolStatus -Option AllScope -Force
Set-Alias -Name 'tool-install' -Value Install-Tool -Option AllScope -Force
Set-Alias -Name 'tool-update' -Value Update-Tool -Option AllScope -Force
Set-Alias -Name 'tool-remove' -Value Remove-Tool -Option AllScope -Force
Set-Alias -Name 'tool-list' -Value Show-ToolList -Option AllScope -Force
Set-Alias -Name 'tool-search' -Value Search-Tool -Option AllScope -Force
Set-Alias -Name 'install-tools' -Value Install-ToolsBulk -Option AllScope -Force
Set-Alias -Name 'update-tools' -Value Update-ToolsAll -Option AllScope -Force

function Search-Tool {
    <#
    .SYNOPSIS
        Search for tools by name or category.
    .PARAMETER Query
        Search term.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, Position = 0)]
        [string]$Query
    )
    
    $tc = $Global:Theme
    $Query = $Query.ToLower()
    
    $results = @()
    foreach ($name in $script:ToolRegistry.Keys) {
        $tool = $script:ToolRegistry[$name]
        if ($name.ToLower().Contains($Query) -or 
            $tool.Description.ToLower().Contains($Query) -or
            $tool.Category.ToLower().Contains($Query)) {
            $results += [PSCustomObject]@{
                Name = $name
                Category = $tool.Category
                Description = $tool.Description
                Available = (Get-ToolStatus -Name $name).Available
            }
        }
    }
    
    if ($results.Count -eq 0) {
        Write-Warning -Message "No tools found matching '$Query'"
        return
    }
    
    Write-Host ""
    Write-Host "  Search results for '$Query':" -ForegroundColor $tc.Primary
    foreach ($r in $results) {
        $statusIcon = if ($r.Available) { "[+] " } else { "[ ] " }
        $statusColor = if ($r.Available) { $tc.GitClean } else { $tc.Muted }
        Write-Host "  $statusIcon$($r.Name.PadRight(15)) - $($r.Category.PadRight(12)) - $($r.Description)" -ForegroundColor $statusColor
    }
    Write-Host ""
}

function Install-ToolsBulk {
    <#
    .SYNOPSIS
        Install multiple tools at once.
    .PARAMETER Tools
        Comma-separated list of tool names.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, Position = 0)]
        [string]$Tools
    )
    
    $toolList = $Tools -split ',' | ForEach-Object { $_.Trim() }
    $tc = $Global:Theme
    
    Write-Host "  Installing $($toolList.Count) tools..." -ForegroundColor $tc.Primary
    
    $success = 0
    $failed = 0
    
    foreach ($toolName in $toolList) {
        if ($script:ToolRegistry.ContainsKey($toolName)) {
            $result = Install-Tool -Name $toolName -AutoInstall
            if ($result) { $success++ } else { $failed++ }
        }
        else {
            Write-Warning -Message "Unknown tool: $toolName"
            $failed++
        }
    }
    
    Write-Host "  Installed: $success, Failed: $failed" -ForegroundColor $(if ($failed -eq 0) { $tc.GitClean } else { $tc.Error })
}

function Update-ToolsAll {
    <#
    .SYNOPSIS
        Update all installed tools.
    #>
    [CmdletBinding()]
    param()
    
    $tc = $Global:Theme
    
    Write-Host "  Checking for updates..." -ForegroundColor $tc.Primary
    
    $updates = 0
    foreach ($name in $script:ToolRegistry.Keys) {
        $status = Get-ToolStatus -Name $name
        if ($status.Available) {
            $updateInfo = Update-Tool -Name $name -CheckOnly
            if ($updateInfo.UpdateAvailable) {
                Write-Host "  Updating $name..." -ForegroundColor $tc.Warning
                Update-Tool -Name $name
                $updates++
            }
        }
    }
    
    if ($updates -eq 0) {
        Write-Host "  All tools are up to date!" -ForegroundColor $tc.GitClean
    }
    else {
        Write-Host "  Updated $updates tools" -ForegroundColor $tc.GitClean
    }
}

function Show-ProfileStats {
    <#
    .SYNOPSIS
        Display profile statistics and status.
    #>
    [CmdletBinding()]
    param()
    
    $tc = $Global:Theme
    
    Write-Host ""
    Write-Host "  ╔══════════════════════════════════════════════════════════════╗" -ForegroundColor $tc.Primary
    Write-Host "  ║              PROFILE STATISTICS                             ║" -ForegroundColor $tc.Primary
    Write-Host "  ╠══════════════════════════════════════════════════════════════╣" -ForegroundColor $tc.Primary
    
    # Load time
    $loadTime = if ($Global:ProfileLoadTimeMs) { "$Global:ProfileLoadTimeMs ms" } else { "N/A" }
    Write-Host "  ║ Load Time:     $($loadTime.PadRight(48))║" -ForegroundColor $tc.Text
    
    # Theme
    $theme = if ($Global:ProfileConfig.Theme) { $Global:ProfileConfig.Theme } else { "Default" }
    Write-Host "  ║ Theme:        $($theme.PadRight(48))║" -ForegroundColor $tc.Text
    
    # Prompt mode
    $promptMode = if ($script:PromptMode) { $script:PromptMode } else { "Custom" }
    Write-Host "  ║ Prompt:       $($promptMode.PadRight(48))║" -ForegroundColor $tc.Text
    
    # Modules loaded
    $moduleCount = $script:ProfileLoadTimes.Count
    Write-Host "  ║ Modules:      $($moduleCount.ToString().PadRight(48))║" -ForegroundColor $tc.Text
    
    # Tools
    $totalTools = $script:ToolRegistry.Count
    $installedTools = 0
    foreach ($name in $script:ToolRegistry.Keys) {
        if ((Get-ToolStatus -Name $name).Available) { $installedTools++ }
    }
    Write-Host "  ║ Tools:        $($installedTools.ToString() + '/' + $totalTools.ToString()).PadRight(48)║" -ForegroundColor $tc.Text
    
    # Config
    $configPath = Join-Path -Path $script:ProfileRoot -ChildPath 'Config' | Join-Path -ChildPath 'profile-config.json'
    $configExists = if (Test-Path -Path $configPath) { "Yes" } else { "No" }
    Write-Host "  ║ Config File:  $($configExists.PadRight(48))║" -ForegroundColor $tc.Text
    
    Write-Host "  ╚══════════════════════════════════════════════════════════════╝" -ForegroundColor $tc.Primary
    Write-Host ""
    
    # Show top modules by load time
    if ($script:ProfileLoadTimes.Count -gt 0) {
        Write-Host "  Top 5 slowest modules:" -ForegroundColor $tc.Accent
        $slowest = $script:ProfileLoadTimes | Sort-Object -Property TimeMs -Descending | Select-Object -First 5
        foreach ($m in $slowest) {
            $status = if ($m.Status -eq 'OK') { "[OK]" } else { "[ERR]" }
            $statusColor = if ($m.Status -eq 'OK') { $tc.GitClean } else { $tc.Error }
            Write-Host "    $($m.Module.PadRight(30)) $($m.TimeMs.ToString().PadLeft(6)) ms $status" -ForegroundColor $statusColor
        }
        Write-Host ""
    }
}

Set-Alias -Name 'profile-stats' -Value Show-ProfileStats -Option AllScope -Force

Write-Host -Object "Tools registry loaded ($($script:ToolRegistry.Count) tools)" -ForegroundColor $Global:Theme.Muted

#endregion