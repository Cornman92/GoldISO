<#
.SYNOPSIS
    Package Health Dashboard for C-Man's PowerShell Profile.
.DESCRIPTION
    Cross-manager outdated package check (winget, choco, scoop, npm, pip,
    dotnet tool, PS modules), security audit, and unified color-coded
    health report via a single command.
.NOTES
    Module: 19-PackageHealth.ps1
    Requires: PowerShell 5.1+
#>

#region ── Manager Detection ──────────────────────────────────────────────────

function Test-ManagerAvailable {
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory, Position = 0)]
        [string]$Name
    )

    return ($null -ne (Get-Command -Name $Name -ErrorAction SilentlyContinue))
}

#endregion

#region ── Individual Manager Checks ──────────────────────────────────────────

<#
.SYNOPSIS
    Gets outdated winget packages.
#>
function Get-WingetOutdated {
    [CmdletBinding()]
    [OutputType([PSCustomObject[]])]
    param()

    if (-not (Test-ManagerAvailable -Name 'winget')) { return @() }

    try {
        $output = & winget upgrade --include-unknown 2>$null
        $results = [System.Collections.Generic.List[PSCustomObject]]::new()

        $headerFound = $false
        foreach ($line in $output) {
            if ($line -match '^\-{2,}') {
                $headerFound = $true
                continue
            }
            if (-not $headerFound) { continue }
            if ([string]::IsNullOrWhiteSpace($line)) { continue }
            if ($line -match 'upgrades available') { continue }

            # Parse winget output: Name  Id  Version  Available  Source
            if ($line -match '^\s*(.+?)\s{2,}(\S+)\s+(\S+)\s+(\S+)') {
                $results.Add([PSCustomObject]@{
                    Manager   = 'winget'
                    Name      = $Matches[1].Trim()
                    Id        = $Matches[2]
                    Current   = $Matches[3]
                    Available = $Matches[4]
                })
            }
        }
        return $results.ToArray()
    }
    catch {
        Write-Warning -Message "winget check failed: $($_.Exception.Message)"
        return @()
    }
}

<#
.SYNOPSIS
    Gets outdated Chocolatey packages.
#>
function Get-ChocolateyOutdated {
    [CmdletBinding()]
    [OutputType([PSCustomObject[]])]
    param()

    if (-not (Test-ManagerAvailable -Name 'choco')) { return @() }

    try {
        $output = & choco outdated --limit-output 2>$null
        $results = [System.Collections.Generic.List[PSCustomObject]]::new()

        foreach ($line in $output) {
            if ($line -match '^(.+?)\|(.+?)\|(.+?)\|') {
                $results.Add([PSCustomObject]@{
                    Manager   = 'choco'
                    Name      = $Matches[1]
                    Id        = $Matches[1]
                    Current   = $Matches[2]
                    Available = $Matches[3]
                })
            }
        }
        return $results.ToArray()
    }
    catch {
        return @()
    }
}

<#
.SYNOPSIS
    Gets outdated Scoop packages.
#>
function Get-ScoopOutdated {
    [CmdletBinding()]
    [OutputType([PSCustomObject[]])]
    param()

    if (-not (Test-ManagerAvailable -Name 'scoop')) { return @() }

    try {
        $output = & scoop status 2>$null
        $results = [System.Collections.Generic.List[PSCustomObject]]::new()

        foreach ($line in $output) {
            if ($line -match '^\s*(\S+)\s+(\S+)\s+(\S+)') {
                $name = $Matches[1]
                if ($name -eq 'Name' -or $name -match '^\-') { continue }
                $results.Add([PSCustomObject]@{
                    Manager   = 'scoop'
                    Name      = $name
                    Id        = $name
                    Current   = $Matches[2]
                    Available = $Matches[3]
                })
            }
        }
        return $results.ToArray()
    }
    catch {
        return @()
    }
}

<#
.SYNOPSIS
    Gets outdated npm global packages.
#>
function Get-NpmOutdated {
    [CmdletBinding()]
    [OutputType([PSCustomObject[]])]
    param()

    if (-not (Test-ManagerAvailable -Name 'npm')) { return @() }

    try {
        $output = & npm outdated -g --json 2>$null | ConvertFrom-Json -ErrorAction SilentlyContinue
        $results = [System.Collections.Generic.List[PSCustomObject]]::new()

        if ($null -ne $output) {
            foreach ($prop in $output.PSObject.Properties) {
                $results.Add([PSCustomObject]@{
                    Manager   = 'npm'
                    Name      = $prop.Name
                    Id        = $prop.Name
                    Current   = $prop.Value.current
                    Available = $prop.Value.latest
                })
            }
        }
        return $results.ToArray()
    }
    catch {
        return @()
    }
}

<#
.SYNOPSIS
    Gets outdated pip packages.
#>
function Get-PipOutdated {
    [CmdletBinding()]
    [OutputType([PSCustomObject[]])]
    param()

    if (-not (Test-ManagerAvailable -Name 'pip')) { return @() }

    try {
        $output = & pip list --outdated --format=json 2>$null | ConvertFrom-Json -ErrorAction SilentlyContinue
        $results = [System.Collections.Generic.List[PSCustomObject]]::new()

        if ($null -ne $output) {
            foreach ($pkg in $output) {
                $results.Add([PSCustomObject]@{
                    Manager   = 'pip'
                    Name      = $pkg.name
                    Id        = $pkg.name
                    Current   = $pkg.version
                    Available = $pkg.latest_version
                })
            }
        }
        return $results.ToArray()
    }
    catch {
        return @()
    }
}

<#
.SYNOPSIS
    Gets outdated dotnet tools.
#>
function Get-DotnetToolOutdated {
    [CmdletBinding()]
    [OutputType([PSCustomObject[]])]
    param()

    if (-not (Test-ManagerAvailable -Name 'dotnet')) { return @() }

    try {
        $tools = & dotnet tool list -g 2>$null
        $results = [System.Collections.Generic.List[PSCustomObject]]::new()

        $headerFound = $false
        foreach ($line in $tools) {
            if ($line -match '^\-{2,}') {
                $headerFound = $true
                continue
            }
            if (-not $headerFound) { continue }
            if ([string]::IsNullOrWhiteSpace($line)) { continue }

            if ($line -match '^\s*(\S+)\s+(\S+)') {
                $toolName = $Matches[1]
                $currentVersion = $Matches[2]

                # Check for update via nuget search
                $search = & dotnet tool search $toolName --take 1 2>$null
                $latestVersion = $null
                foreach ($sLine in $search) {
                    if ($sLine -match "^\s*$([regex]::Escape($toolName))\s+(\S+)") {
                        $latestVersion = $Matches[1]
                    }
                }

                if ($null -ne $latestVersion -and $latestVersion -ne $currentVersion) {
                    $results.Add([PSCustomObject]@{
                        Manager   = 'dotnet'
                        Name      = $toolName
                        Id        = $toolName
                        Current   = $currentVersion
                        Available = $latestVersion
                    })
                }
            }
        }
        return $results.ToArray()
    }
    catch {
        return @()
    }
}

<#
.SYNOPSIS
    Gets outdated PowerShell modules.
#>
function Get-PSModuleOutdated {
    [CmdletBinding()]
    [OutputType([PSCustomObject[]])]
    param()

    try {
        $installed = Get-InstalledModule -ErrorAction SilentlyContinue
        $results = [System.Collections.Generic.List[PSCustomObject]]::new()

        foreach ($mod in $installed) {
            try {
                $online = Find-Module -Name $mod.Name -ErrorAction SilentlyContinue |
                    Select-Object -First 1

                if ($null -ne $online -and $online.Version -gt $mod.Version) {
                    $results.Add([PSCustomObject]@{
                        Manager   = 'pwsh'
                        Name      = $mod.Name
                        Id        = $mod.Name
                        Current   = $mod.Version.ToString()
                        Available = $online.Version.ToString()
                    })
                }
            }
            catch {
                # Skip modules that can't be checked
            }
        }
        return $results.ToArray()
    }
    catch {
        return @()
    }
}

#endregion

#region ── Security Audit ─────────────────────────────────────────────────────

<#
.SYNOPSIS
    Runs npm security audit on the current project.
.DESCRIPTION
    Executes npm audit and returns a summary of vulnerabilities.
.EXAMPLE
    Invoke-NpmAuditCheck
#>
function Invoke-NpmAuditCheck {
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter()]
        [string]$Path = (Get-Location).Path
    )

    $pkgJson = Join-Path -Path $Path -ChildPath 'package.json'
    if (-not (Test-Path -Path $pkgJson)) {
        return $null
    }

    if (-not (Test-ManagerAvailable -Name 'npm')) { return $null }

    try {
        $output = & npm audit --json 2>$null | ConvertFrom-Json -ErrorAction SilentlyContinue
        if ($null -eq $output) { return $null }

        $vuln = $output.metadata.vulnerabilities
        return [PSCustomObject]@{
            Total    = if ($vuln.PSObject.Properties.Name -contains 'total') { $vuln.total } else { 0 }
            Critical = if ($vuln.PSObject.Properties.Name -contains 'critical') { $vuln.critical } else { 0 }
            High     = if ($vuln.PSObject.Properties.Name -contains 'high') { $vuln.high } else { 0 }
            Moderate = if ($vuln.PSObject.Properties.Name -contains 'moderate') { $vuln.moderate } else { 0 }
            Low      = if ($vuln.PSObject.Properties.Name -contains 'low') { $vuln.low } else { 0 }
        }
    }
    catch {
        return $null
    }
}

#endregion

#region ── Unified Health Report ──────────────────────────────────────────────

<#
.SYNOPSIS
    Comprehensive package health dashboard.
.DESCRIPTION
    Checks all available package managers for outdated packages and
    displays a unified color-coded report. Optionally includes security
    audits and PS module checks.
.PARAMETER Managers
    Specific managers to check. Default checks all available.
.PARAMETER IncludeSecurity
    Include npm security audit.
.PARAMETER IncludePSModules
    Include PowerShell module update check (can be slow).
.PARAMETER Quick
    Only check fast managers (winget, scoop, npm, pip). Skips choco, dotnet, PS modules.
.EXAMPLE
    Get-PackageHealth
.EXAMPLE
    health -Quick
.EXAMPLE
    Get-PackageHealth -Managers winget,npm -IncludeSecurity
#>
function Get-PackageHealth {
    [CmdletBinding()]
    [OutputType([void])]
    param(
        [Parameter(Position = 0)]
        [ValidateSet('winget', 'choco', 'scoop', 'npm', 'pip', 'dotnet', 'pwsh')]
        [string[]]$Managers,

        [Parameter()]
        [switch]$IncludeSecurity,

        [Parameter()]
        [switch]$IncludePSModules,

        [Parameter()]
        [switch]$Quick
    )

    $sw = [System.Diagnostics.Stopwatch]::StartNew()

    Write-Host "`n  Package Health Dashboard" -ForegroundColor $script:Theme.Primary
    Write-Host "  $('â•' * 60)" -ForegroundColor $script:Theme.Muted
    Write-Host "  Scanning..." -ForegroundColor $script:Theme.Info

    # Determine which managers to check
    $allManagers = @{
        winget = @{ Check = 'Get-WingetOutdated';      Command = 'winget'; Slow = $false }
        choco  = @{ Check = 'Get-ChocolateyOutdated';   Command = 'choco';  Slow = $true }
        scoop  = @{ Check = 'Get-ScoopOutdated';        Command = 'scoop';  Slow = $false }
        npm    = @{ Check = 'Get-NpmOutdated';          Command = 'npm';    Slow = $false }
        pip    = @{ Check = 'Get-PipOutdated';          Command = 'pip';    Slow = $false }
        dotnet = @{ Check = 'Get-DotnetToolOutdated';   Command = 'dotnet'; Slow = $true }
        pwsh   = @{ Check = 'Get-PSModuleOutdated';     Command = $null;    Slow = $true }
    }

    if ($null -eq $Managers -or $Managers.Count -eq 0) {
        if ($Quick) {
            $Managers = @('winget', 'scoop', 'npm', 'pip')
        }
        else {
            $Managers = @($allManagers.Keys)
        }
    }

    if (-not $IncludePSModules -and 'pwsh' -in $Managers -and -not $PSBoundParameters.ContainsKey('Managers')) {
        $Managers = $Managers | Where-Object -FilterScript { $_ -ne 'pwsh' }
    }

    $allOutdated = [System.Collections.Generic.List[PSCustomObject]]::new()
    $checkedManagers = 0
    $availableManagers = 0

    foreach ($mgr in $Managers) {
        $info = $allManagers[$mgr]
        $command = $info['Command']

        # Check availability
        if ($null -ne $command -and -not (Test-ManagerAvailable -Name $command)) {
            continue
        }
        if ($mgr -eq 'pwsh') {
            # Always available via Get-InstalledModule
        }

        $availableManagers++
        Write-Host "  Checking $mgr..." -ForegroundColor $script:Theme.Muted -NoNewline

        $checkSw = [System.Diagnostics.Stopwatch]::StartNew()
        $outdated = & $info['Check']
        $checkSw.Stop()

        $count = @($outdated).Count
        $color = if ($count -eq 0) { $Global:Theme.Success } elseif ($count -lt 5) { $Global:Theme.Warning } else { $Global:Theme.Error }
        Write-Host "`r  $($mgr.PadRight(10))" -ForegroundColor $script:Theme.Accent -NoNewline
        Write-Host " $count outdated" -ForegroundColor $color -NoNewline
        Write-Host " ($($checkSw.ElapsedMilliseconds)ms)" -ForegroundColor $script:Theme.Muted

        foreach ($item in $outdated) {
            $allOutdated.Add($item)
        }
        $checkedManagers++
    }

    # Security audit
    $auditResult = $null
    if ($IncludeSecurity) {
        Write-Host "`n  Security Audit" -ForegroundColor $script:Theme.Primary
        Write-Host "  $('─' * 50)" -ForegroundColor $script:Theme.Muted

        $auditResult = Invoke-NpmAuditCheck
        if ($null -ne $auditResult) {
            $critColor = if ($auditResult.Critical -gt 0) { $Global:Theme.Error } else { $Global:Theme.Success }
            $highColor = if ($auditResult.High -gt 0) { $Global:Theme.Error } else { $Global:Theme.Success }
            $modColor = if ($auditResult.Moderate -gt 0) { $Global:Theme.Warning } else { $Global:Theme.Success }

            Write-Host "  npm: " -ForegroundColor $script:Theme.Accent -NoNewline
            Write-Host "Critical: $($auditResult.Critical) " -ForegroundColor $critColor -NoNewline
            Write-Host "High: $($auditResult.High) " -ForegroundColor $highColor -NoNewline
            Write-Host "Moderate: $($auditResult.Moderate) " -ForegroundColor $modColor -NoNewline
            Write-Host "Low: $($auditResult.Low)" -ForegroundColor $script:Theme.Muted
        }
        else {
            Write-Host '  No package.json found or npm unavailable.' -ForegroundColor $Global:Theme.Muted
        }
    }

    # Summary
    $sw.Stop()
    Write-Host "`n  $('â•' * 60)" -ForegroundColor $script:Theme.Muted

    $totalOutdated = $allOutdated.Count
    $summaryColor = if ($totalOutdated -eq 0) { $Global:Theme.Success }
        elseif ($totalOutdated -lt 10) { $Global:Theme.Warning }
        else { $Global:Theme.Error }

    Write-Host "  Total: " -ForegroundColor $script:Theme.Text -NoNewline
    Write-Host "$totalOutdated outdated" -ForegroundColor $summaryColor -NoNewline
    Write-Host " across $checkedManagers manager(s)" -ForegroundColor $script:Theme.Muted -NoNewline
    Write-Host " ($($sw.ElapsedMilliseconds)ms)" -ForegroundColor $script:Theme.Muted

    # Detail table if packages found
    if ($totalOutdated -gt 0 -and $totalOutdated -le 30) {
        Write-Host "`n  Outdated Packages:" -ForegroundColor $script:Theme.Primary
        Write-Host "  $('─' * 60)" -ForegroundColor $script:Theme.Muted

        $grouped = $allOutdated | Group-Object -Property Manager
        foreach ($group in $grouped | Sort-Object -Property Name) {
            Write-Host "`n  [$($group.Name)]" -ForegroundColor $script:Theme.Accent
            foreach ($pkg in ($group.Group | Sort-Object -Property Name)) {
                Write-Host "    $($pkg.Name.PadRight(30))" -ForegroundColor $script:Theme.Text -NoNewline
                Write-Host " $($pkg.Current.PadRight(12))" -ForegroundColor $script:Theme.Warning -NoNewline
                Write-Host " → $($pkg.Available)" -ForegroundColor $script:Theme.Success
            }
        }
    }
    elseif ($totalOutdated -gt 30) {
        Write-Host "`n  Too many to list. Run individual checks for details." -ForegroundColor $script:Theme.Muted
    }

    Write-Host ''
}

<#
.SYNOPSIS
    Updates all outdated packages for a specific manager.
.PARAMETER Manager
    Package manager to update with.
.PARAMETER DryRun
    Show what would be updated without executing.
.EXAMPLE
    Update-AllPackages -Manager winget
.EXAMPLE
    Update-AllPackages -Manager npm -DryRun
#>
function Update-AllPackages {
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([void])]
    param(
        [Parameter(Mandatory, Position = 0)]
        [ValidateSet('winget', 'choco', 'scoop', 'npm', 'pip')]
        [string]$Manager,

        [Parameter()]
        [switch]$DryRun
    )

    if (-not $PSCmdlet.ShouldProcess($Manager, 'Update all packages')) {
        return
    }

    Write-Host "  Updating all $Manager packages..." -ForegroundColor $script:Theme.Info

    $command = switch ($Manager) {
        'winget' { 'winget upgrade --all --include-unknown' }
        'choco'  { 'choco upgrade all -y' }
        'scoop'  { 'scoop update *' }
        'npm'    { 'npm update -g' }
        'pip'    { 'pip list --outdated --format=json | ConvertFrom-Json | ForEach-Object { pip install -U $_.name }' }
    }

    if ($DryRun) {
        Write-Host "  Would run: $command" -ForegroundColor $Global:Theme.Muted
    }
    else {
        Invoke-Expression -Command $command
    }
}

#endregion

#region ── Aliases ─────────────────────────────────────────────────────────────

Set-Alias -Name 'health'     -Value 'Get-PackageHealth'    -Scope Global -Force
Set-Alias -Name 'pkgupdate'  -Value 'Update-AllPackages'   -Scope Global -Force

#endregion

