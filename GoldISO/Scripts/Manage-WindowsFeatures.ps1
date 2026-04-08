#Requires -Version 5.1
#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Windows features and packages management for GoldISO customization.

.DESCRIPTION
    Manages Windows optional features, capabilities, and packages for creating
    streamlined GoldISO builds. Supports enabling/disabling features, adding
    capabilities, and generating feature templates.

.PARAMETER Action
    Action to perform: Enable, Disable, List, ExportTemplate, ImportTemplate, Analyze.

.PARAMETER FeatureName
    Name of the feature to enable/disable (supports wildcards for multiple).

.PARAMETER TemplatePath
    Path for importing/exporting feature templates.

.PARAMETER ExportAll
    Export all features (not just modified ones).

.PARAMETER Online
    Apply changes to online image (current system).

.PARAMETER ImagePath
    Path to offline WIM/VHD for modification.

.PARAMETER WhatIf
    Show what would be changed without applying.

.EXAMPLE
    .\Manage-WindowsFeatures.ps1 -Action List -Online

.EXAMPLE
    .\Manage-WindowsFeatures.ps1 -Action Disable -FeatureName "Internet-Explorer-Optional-*" -Online

.EXAMPLE
    .\Manage-WindowsFeatures.ps1 -Action ExportTemplate -TemplatePath ".\my-features.xml"
#>
[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [Parameter(Mandatory = $true)]
    [ValidateSet("Enable", "Disable", "List", "ExportTemplate", "ImportTemplate", "Analyze")]
    [string]$Action,

    [string]$FeatureName,

    [string]$TemplatePath,

    [switch]$ExportAll,

    [switch]$Online,

    [string]$ImagePath,

    [switch]$WhatIf
)

#region ─────────────────────────────────────────────────────────────────────────────
# Initialization
# ─────────────────────────────────────────────────────────────────────────────

$ErrorActionPreference = "Continue"
$script:StartTime = Get-Date
$script:ModifiedFeatures = [System.Collections.Generic.List[hashtable]]::new()

$commonModule = Join-Path $PSScriptRoot "Modules\GoldISO-Common.psm1"
if (Test-Path $commonModule) {
    Import-Module $commonModule -Force
}

$script:LogFile = Join-Path $PSScriptRoot "..\Logs\FeatureManage-$(Get-Date -Format 'yyyyMMdd-HHmmss').log"
New-Item -ItemType Directory -Path (Split-Path $script:LogFile) -Force -ErrorAction SilentlyContinue | Out-Null

function Write-FeatureLog {
    param(
        [string]$Message,
        [ValidateSet("INFO", "WARN", "ERROR", "SUCCESS", "ACTION")][string]$Level = "INFO"
    )
    $ts = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $entry = "[$ts] [$Level] $Message"

    $color = switch ($Level) {
        "ERROR" { "Red" }
        "WARN" { "Yellow" }
        "SUCCESS" { "Green" }
        "ACTION" { "Cyan" }
        default { "White" }
    }
    Write-Host $entry -ForegroundColor $color
    Add-Content -Path $script:LogFile -Value $entry -ErrorAction SilentlyContinue
}

# Validate parameters
if (-not $Online -and -not $ImagePath -and $Action -in @("Enable", "Disable")) {
    $Online = $true
    Write-FeatureLog "Neither -Online nor -ImagePath specified, defaulting to -Online" "WARN"
}

Write-FeatureLog "Windows Features Management Started" "ACTION"
Write-FeatureLog "Action: $Action | Online: $Online | WhatIf: $WhatIf" "INFO"

#endregion

#region ─────────────────────────────────────────────────────────────────────────────
# Core Functions
# ─────────────────────────────────────────────────────────────────────────────

function Get-TargetFeatures {
    param([string]$Pattern)

    try {
        $params = @{}
        if ($Online) {
            $params.Online = $true
        }
        elseif ($ImagePath) {
            $params.Path = $ImagePath
        }

        $allFeatures = Get-WindowsOptionalFeature @params -ErrorAction Stop

        if ($Pattern) {
            return $allFeatures | Where-Object { $_.FeatureName -like $Pattern }
        }
        return $allFeatures
    }
    catch {
        Write-FeatureLog "Error retrieving features: $_" "ERROR"
        return @()
    }
}

function Enable-TargetFeature {
    param([string]$Name)

    Write-FeatureLog "Enabling feature: $Name" "ACTION"

    if ($WhatIf) {
        Write-FeatureLog "[WHATIF] Would enable: $Name" "INFO"
        return $true
    }

    try {
        $params = @{ FeatureName = $Name; All = $true; ErrorAction = 'Stop' }
        if ($Online) { $params.Online = $true } else { $params.Path = $ImagePath }

        $result = Enable-WindowsOptionalFeature @params

        if ($result.RestartNeeded) {
            Write-FeatureLog "  Feature enabled, restart required" "WARN"
        }
        else {
            Write-FeatureLog "  Feature enabled successfully" "SUCCESS"
        }

        $script:ModifiedFeatures.Add(@{ Name = $Name; Action = "Enabled"; RestartNeeded = $result.RestartNeeded })
        return $true
    }
    catch {
        Write-FeatureLog "  Failed to enable: $_" "ERROR"
        return $false
    }
}

function Disable-TargetFeature {
    param([string]$Name)

    Write-FeatureLog "Disabling feature: $Name" "ACTION"

    if ($WhatIf) {
        Write-FeatureLog "[WHATIF] Would disable: $Name" "INFO"
        return $true
    }

    try {
        $params = @{ FeatureName = $Name; ErrorAction = 'Stop' }
        if ($Online) { $params.Online = $true } else { $params.Path = $ImagePath }

        $result = Disable-WindowsOptionalFeature @params

        if ($result.RestartNeeded) {
            Write-FeatureLog "  Feature disabled, restart required" "WARN"
        }
        else {
            Write-FeatureLog "  Feature disabled successfully" "SUCCESS"
        }

        $script:ModifiedFeatures.Add(@{ Name = $Name; Action = "Disabled"; RestartNeeded = $result.RestartNeeded })
        return $true
    }
    catch {
        Write-FeatureLog "  Failed to disable: $_" "ERROR"
        return $false
    }
}

function Export-FeatureTemplate {
    param([string]$Path, [switch]$All)

    Write-FeatureLog "Exporting feature template to: $Path" "ACTION"

    $features = Get-TargetFeatures
    if (-not $All) {
        $features = $features | Where-Object { $_.State -ne 'Disabled' }
    }

    $template = @{
        ExportDate = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
        ComputerName = $env:COMPUTERNAME
        FeatureCount = $features.Count
        Features = $features | ForEach-Object {
            @{
                Name = $_.FeatureName
                State = $_.State
                Enabled = ($_.State -eq 'Enabled')
            }
        }
    }

    $template | ConvertTo-Json -Depth 3 | Set-Content $Path -Encoding UTF8
    Write-FeatureLog "Template exported: $Path ($($features.Count) features)" "SUCCESS"
}

function Import-FeatureTemplate {
    param([string]$Path)

    Write-FeatureLog "Importing feature template from: $Path" "ACTION"

    if (-not (Test-Path $Path)) {
        Write-FeatureLog "Template file not found: $Path" "ERROR"
        return
    }

    try {
        $template = Get-Content $Path | ConvertFrom-Json
        Write-FeatureLog "Template loaded: $($template.ComputerName) ($($template.FeatureCount) features)" "INFO"

        $applied = 0
        $failed = 0

        foreach ($feature in $template.Features) {
            $current = Get-TargetFeatures -Pattern $feature.Name | Select-Object -First 1

            if (-not $current) {
                Write-FeatureLog "  Feature not found on this system: $($feature.Name)" "WARN"
                continue
            }

            if ($feature.Enabled -and $current.State -ne 'Enabled') {
                if (Enable-TargetFeature -Name $feature.Name) { $applied++ } else { $failed++ }
            }
            elseif (-not $feature.Enabled -and $current.State -eq 'Enabled') {
                if (Disable-TargetFeature -Name $feature.Name) { $applied++ } else { $failed++ }
            }
            else {
                Write-FeatureLog "  Already in desired state: $($feature.Name)" "INFO"
            }
        }

        Write-FeatureLog "Template applied: $applied changes, $failed failures" "SUCCESS"
    }
    catch {
        Write-FeatureLog "Failed to import template: $_" "ERROR"
    }
}

function Get-FeatureAnalysis {
    Write-FeatureLog "Analyzing Windows features..." "ACTION"

    $features = Get-TargetFeatures

    $analysis = @{
        Total = $features.Count
        Enabled = ($features | Where-Object { $_.State -eq 'Enabled' }).Count
        Disabled = ($features | Where-Object { $_.State -eq 'Disabled' }).Count
        EnablePending = ($features | Where-Object { $_.State -eq 'EnablePending' }).Count
        DisablePending = ($features | Where-Object { $_.State -eq 'DisablePending' }).Count
        ByCategory = @{}
    }

    # Categorize features
    $categories = @{
        "Media" = @("Media", "MediaPlayer", "DirectPlay")
        "Legacy" = @("Internet-Explorer", "Legacy", "SMB1", "DirectPlay")
        "Net" = @("Net", "TFTP", "Telnet", "SMB")
        "HyperV" = @("Hyper-V", "HyperV", "Containers")
        "Printing" = @("Printing", "Print", "Fax")
        "Remote" = @("Remote", "RDP", "RPC", "RSAT")
    }

    foreach ($cat in $categories.Keys) {
        $catFeatures = @()
        foreach ($pattern in $categories[$cat]) {
            $catFeatures += $features | Where-Object { $_.FeatureName -like "*$pattern*" -and $_.State -eq 'Enabled' }
        }
        $analysis.ByCategory[$cat] = ($catFeatures | Select-Object -Unique).Count
    }

    # Display results
    Write-FeatureLog "Feature Analysis Results:" "INFO"
    Write-FeatureLog "  Total Features: $($analysis.Total)" "INFO"
    Write-FeatureLog "  Enabled: $($analysis.Enabled)" "INFO"
    Write-FeatureLog "  Disabled: $($analysis.Disabled)" "INFO"

    Write-FeatureLog "`nBy Category (Enabled):" "INFO"
    foreach ($cat in $analysis.ByCategory.Keys | Sort-Object) {
        Write-FeatureLog "  $cat`: $($analysis.ByCategory[$cat])" "INFO"
    }

    # Recommendations
    Write-FeatureLog "`nOptimization Recommendations:" "INFO"

    if ($analysis.ByCategory['Legacy'] -gt 0) {
        Write-FeatureLog "  Consider disabling legacy features: IE, SMB1, DirectPlay ($($analysis.ByCategory['Legacy']) enabled)" "WARN"
    }
    if ($analysis.ByCategory['Net'] -gt 3) {
        Write-FeatureLog "  Review network features: TFTP/Telnet may not be needed ($($analysis.ByCategory['Net']) enabled)" "WARN"
    }

    return $analysis
}

#endregion

#region ─────────────────────────────────────────────────────────────────────────────
# Action Execution
# ─────────────────────────────────────────────────────────────────────────────

switch ($Action) {
    "List" {
        $features = Get-TargetFeatures -Pattern $FeatureName
        Write-FeatureLog "Found $($features.Count) features:" "INFO"

        $features | Sort-Object FeatureName | Format-Table FeatureName, State, @{N='Description';E={$_.Description.Substring(0, [Math]::Min(50, $_.Description.Length))}} -AutoSize
    }

    "Enable" {
        if (-not $FeatureName) {
            Write-FeatureLog "FeatureName required for Enable action" "ERROR"
            exit 1
        }

        $features = Get-TargetFeatures -Pattern $FeatureName
        Write-FeatureLog "Found $($features.Count) matching features to enable" "INFO"

        foreach ($feature in $features | Where-Object { $_.State -ne 'Enabled' }) {
            Enable-TargetFeature -Name $feature.FeatureName
        }
    }

    "Disable" {
        if (-not $FeatureName) {
            Write-FeatureLog "FeatureName required for Disable action" "ERROR"
            exit 1
        }

        $features = Get-TargetFeatures -Pattern $FeatureName
        Write-FeatureLog "Found $($features.Count) matching features to disable" "INFO"

        foreach ($feature in $features | Where-Object { $_.State -eq 'Enabled' }) {
            Disable-TargetFeature -Name $feature.FeatureName
        }
    }

    "ExportTemplate" {
        if (-not $TemplatePath) {
            $TemplatePath = Read-Host "Enter template export path"
        }
        Export-FeatureTemplate -Path $TemplatePath -All:$ExportAll
    }

    "ImportTemplate" {
        if (-not $TemplatePath) {
            $TemplatePath = Read-Host "Enter template import path"
        }
        Import-FeatureTemplate -Path $TemplatePath
    }

    "Analyze" {
        Get-FeatureAnalysis
    }
}

#endregion

#region ─────────────────────────────────────────────────────────────────────────────
# Summary
# ─────────────────────────────────────────────────────────────────────────────

$duration = (Get-Date) - $script:StartTime
Write-FeatureLog "========================================" "INFO"
Write-FeatureLog "Operation Complete" "SUCCESS"
Write-FeatureLog "Duration: $($duration.ToString('mm\:ss'))" "INFO"

if ($script:ModifiedFeatures.Count -gt 0) {
    Write-FeatureLog "Modified Features: $($script:ModifiedFeatures.Count)" "INFO"
    $restartNeeded = $script:ModifiedFeatures | Where-Object { $_.RestartNeeded }
    if ($restartNeeded) {
        Write-FeatureLog "Restart required to complete changes" "WARN"
    }
}

Write-FeatureLog "Log saved to: $script:LogFile" "INFO"
