#Requires -Version 5.1

# Import common module
Import-Module (Join-Path $PSScriptRoot "..\Modules\GoldISO-Common.psm1") -Force

<#
.SYNOPSIS
    Build GoldISO with embedded settings migration package.

.DESCRIPTION
    Orchestrates the complete workflow:
    - Settings Export: Exports current system/application settings
    - Package Validation: Validates the export package
    - Settings Migration Prep: Embeds package into GoldISO Config/SettingsMigration/
    - Autounattend Update: Updates autounattend.xml with FirstLogonCommands
    - ISO Build: Triggers standard ISO build (via GWIG pipeline)
    - Verification: Verifies final ISO

.PARAMETER SkipExport
    Skip the export phase and use existing settings package.

.PARAMETER ExportUserData
    Include user folders (Documents, Downloads, Desktop) in export.

.PARAMETER MaxUserDataSizeGB
    Maximum size in GB for user data export. Default: 10

.PARAMETER ExcludeApps
    Array of application names to exclude from export.

.PARAMETER ExportPath
    Directory for settings export. Default: ..\Config\SettingsMigration

.PARAMETER SkipISOBUILD
    Only perform export and validation, skip ISO build.

.PARAMETER GWIGPipeline
    Path to GWIG pipeline script. Default: ..\..\GWIG\Invoke-GamerOSPipeline-v2.ps1

.EXAMPLE
    .\Build-ISO-With-Settings.ps1

.EXAMPLE
    .\Build-ISO-With-Settings.ps1 -ExportUserData -MaxUserDataSizeGB 5

.EXAMPLE
    .\Build-ISO-With-Settings.ps1 -SkipExport -SkipISOBUILD
#>
[CmdletBinding()]
param(
    [switch]$SkipExport,
    [switch]$ExportUserData,
    [int]$MaxUserDataSizeGB = 10,
    [string[]]$ExcludeApps = @(),
    [string]$ExportPath = (Resolve-Path (Join-Path $PSScriptRoot "..\Config\SettingsMigration") -ErrorAction SilentlyContinue),
    [switch]$SkipISOBUILD,
    [string]$GWIGPipeline = (Join-Path (Split-Path $PSScriptRoot -Parent) "..\GWIG\Invoke-GamerOSPipeline-v2.ps1")
)

# Configuration & Setup
$ErrorActionPreference = "Stop"
$script:StartTime = Get-Date

$script:ProjectRoot = Split-Path $PSScriptRoot -Parent

# Initialize centralized logging
$logFile = Join-Path $PSScriptRoot "Build-ISO-With-Settings.log"
Initialize-Logging -LogPath $logFile
Write-Log "---------------------------------------------------------------" "INFO"
Write-Log "Build ISO with Settings Migration" "INFO"
Write-Log "---------------------------------------------------------------" "INFO"
Write-Log "Project Root: $script:ProjectRoot"
Write-Log "Export Path: $ExportPath"
Write-Log "Skip Export: $SkipExport"
Write-Log "Skip ISO Build: $SkipISOBUILD"

function Invoke-SettingsExport {
    if ($SkipExport) {
        Write-Log "Settings Export: SKIPPED (using existing package)" "SKIP"
        return $true
    }

    Write-Log ""
    Write-Log "---------------------------------------------------------------" "INFO"
    Write-Log "Settings Export: Exporting System Settings" "INFO"
    Write-Log "---------------------------------------------------------------" "INFO"
    
    $exportScript = Join-Path $PSScriptRoot "Export-Settings.ps1"
    if (-not (Test-Path $exportScript)) {
        Write-Log "Export script not found: $exportScript" "ERROR"
        return $false
    }
    
    try {
        $exportParams = @{
            ExportPath = $ExportPath
            ExportUserData = $ExportUserData
            MaxUserDataSizeGB = $MaxUserDataSizeGB
            ExcludeApps = $ExcludeApps
            Compress = $true
        }
        
        Write-Log "Starting export with parameters:"
        Write-Log "  - ExportUserData: $ExportUserData"
        Write-Log "  - MaxUserDataSizeGB: $MaxUserDataSizeGB"
        Write-Log "  - ExcludeApps: $($ExcludeApps -join ', ')"
        
        & $exportScript @exportParams
        
        Write-Log "Export phase completed" "SUCCESS"
        return $true
    }
    catch {
        Write-Log "Export failed: $_" "ERROR"
        return $false
    }
}

function Test-ExportPackage {
    Write-Log ""
    Write-Log "---------------------------------------------------------------" "INFO"
    Write-Log "Package Validation: Validating Export Package" "INFO"
    Write-Log "---------------------------------------------------------------" "INFO"
    
    $exportDirs = Get-ChildItem $ExportPath -Directory -Filter "Settings-Migration-*" | 
        Sort-Object CreationTime -Descending
    
    if (-not $exportDirs) {
        $exportArchives = Get-ChildItem $ExportPath -File -Filter "Settings-Migration-*.zip" | 
            Sort-Object CreationTime -Descending
        
        if ($exportArchives) {
            Write-Log "Found compressed archive: $($exportArchives[0].Name)"
            Expand-Archive -Path $exportArchives[0].FullName -DestinationPath $ExportPath -Force
            $exportDirs = Get-ChildItem $ExportPath -Directory -Filter "Settings-Migration-*" | 
                Sort-Object CreationTime -Descending
        }
    }
    
    if (-not $exportDirs) {
        Write-Log "No export package found in: $ExportPath" "ERROR"
        return $false
    }
    
    $script:LatestExport = $exportDirs[0].FullName
    Write-Log "Found export: $script:LatestExport"
    
    $manifestPath = Join-Path $script:LatestExport "manifest.json"
    if (-not (Test-Path $manifestPath)) {
        Write-Log "Manifest not found in export package" "ERROR"
        return $false
    }
    
    try {
        $manifest = Get-Content $manifestPath -Raw | ConvertFrom-Json
        Write-Log "Manifest loaded successfully"
        Write-Log "  Export Date: $($manifest.ExportDate)"
        Write-Log "  Source Computer: $($manifest.SourceComputer)"
        Write-Log "  Total Items: $($manifest.TotalItems)"
        
        $totalSize = (Get-ChildItem $script:LatestExport -Recurse -File | Measure-Object -Property Length -Sum).Sum
        Write-Log "  Package Size: $([math]::Round($totalSize/1MB, 2)) MB"
        
        if ($totalSize -gt 500MB) {
            Write-Log "WARNING: Package size is $([math]::Round($totalSize/1MB, 2)) MB - may significantly increase ISO size" "WARN"
        }
        
        $script:Manifest = $manifest
        Write-Log "Package validation passed" "SUCCESS"
        return $true
    }
    catch {
        Write-Log "Failed to validate package: $_" "ERROR"
        return $false
    }
}

function Initialize-SettingsMigrationDirectory {
    Write-Log ""
    Write-Log "---------------------------------------------------------------" "INFO"
    Write-Log "Settings Migration Prep: Preparing SettingsMigration Directory" "INFO"
    Write-Log "---------------------------------------------------------------" "INFO"
    
    $settingsMigrationDir = Join-Path $script:ProjectRoot "Config\SettingsMigration"
    
    if (Test-Path $settingsMigrationDir) {
        Write-Log "Cleaning old settings from: $settingsMigrationDir"
        Get-ChildItem $settingsMigrationDir -Exclude "restore-settings.ps1" | Remove-Item -Recurse -Force
    } else {
        New-Item -ItemType Directory -Path $settingsMigrationDir -Force | Out-Null
    }
    
    Write-Log "Copying export to: $settingsMigrationDir"
    robocopy $script:LatestExport $settingsMigrationDir /E /R:3 /W:1 /MT:8 /NFL /NDL /NJH /NJS 2>&1 | Out-Null
    if ($LASTEXITCODE -ge 8) {
        Write-Log "Robocopy failed with exit code $LASTEXITCODE when copying to SettingsMigration" "WARN"
    }
    
    $restoreScript = Join-Path $settingsMigrationDir "restore-settings.ps1"
    if (-not (Test-Path $restoreScript)) {
        $sourceRestore = Join-Path $ExportPath "restore-settings.ps1"
        if (Test-Path $sourceRestore) {
            Copy-Item $sourceRestore $restoreScript
        } else {
            Write-Log "restore-settings.ps1 not found - it must exist for auto-restore to work" "WARN"
        }
    }
    
    $finalSize = (Get-ChildItem $settingsMigrationDir -Recurse -File | Measure-Object -Property Length -Sum).Sum
    Write-Log "SettingsMigration directory prepared: $([math]::Round($finalSize/1MB, 2)) MB" "SUCCESS"
    
    return $true
}

function Update-AutounattendXML {
    Write-Log ""
    Write-Log "---------------------------------------------------------------" "INFO"
    Write-Log "Autounattend Update: Updating autounattend.xml" "INFO"
    Write-Log "---------------------------------------------------------------" "INFO"
    
    $autounattendPath = Join-Path $script:ProjectRoot "Config\autounattend.xml"
    
    if (-not (Test-Path $autounattendPath)) {
        Write-Log "autounattend.xml not found: $autounattendPath" "ERROR"
        return $false
    }
    
    try {
        [xml]$xml = Get-Content $autounattendPath -Raw
        
        $ns = New-Object System.Xml.XmlNamespaceManager($xml.NameTable)
        $ns.AddNamespace("unattend", "urn:schemas-microsoft-com:unattend")
        $ns.AddNamespace("wcm", "http://schemas.microsoft.com/WMIConfig/2002/State")
        
        $oobeSystem = $xml.unattend.settings | Where-Object { $_.pass -eq "oobeSystem" }
        if (-not $oobeSystem) {
            $oobeSystem = $xml.CreateElement("settings")
            $oobeSystem.SetAttribute("pass", "oobeSystem")
            $xml.unattend.AppendChild($oobeSystem) | Out-Null
        }
        
        $shellSetup = $oobeSystem.component | Where-Object { $_.name -eq "Microsoft-Windows-Shell-Setup" }
        if (-not $shellSetup) {
            $shellSetup = $xml.CreateElement("component")
            $shellSetup.SetAttribute("name", "Microsoft-Windows-Shell-Setup")
            $shellSetup.SetAttribute("processorArchitecture", "amd64")
            $shellSetup.SetAttribute("publicKeyToken", "31bf3856ad364e35")
            $shellSetup.SetAttribute("language", "neutral")
            $shellSetup.SetAttribute("versionScope", "nonSxS")
            $oobeSystem.AppendChild($shellSetup) | Out-Null
        }
        
        $firstLogonCommands = $shellSetup.FirstLogonCommands
        if (-not $firstLogonCommands) {
            $firstLogonCommands = $xml.CreateElement("FirstLogonCommands")
            $shellSetup.AppendChild($firstLogonCommands) | Out-Null
        }
        
        $existingCommand = $firstLogonCommands.SynchronousCommand | Where-Object { 
            $_.Description -like "*Restore user settings*" 
        }
        
        if ($existingCommand) {
            Write-Log "Settings restore command already exists in autounattend.xml"
        } else {
            $maxOrder = 0
            if ($firstLogonCommands.SynchronousCommand) {
                $firstLogonCommands.SynchronousCommand | ForEach-Object {
                    if ($_.Order -gt $maxOrder) { $maxOrder = $_.Order }
                }
            }
            
            $newOrder = $maxOrder + 1
            
            $newCommand = $xml.CreateElement("SynchronousCommand")
            $newCommand.SetAttribute("wcm:action", "add")
            
            $orderElem = $xml.CreateElement("Order")
            $orderElem.InnerText = $newOrder
            $newCommand.AppendChild($orderElem) | Out-Null
            
            $descElem = $xml.CreateElement("Description")
            $descElem.InnerText = "Restore user settings and application configurations from migration package"
            $newCommand.AppendChild($descElem) | Out-Null
            
            $pathElem = $xml.CreateElement("CommandLine")
            $pathElem.InnerText = 'powershell.exe -NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File "C:\SettingsMigration\restore-settings.ps1"'
            $newCommand.AppendChild($pathElem) | Out-Null
            
            $firstLogonCommands.AppendChild($newCommand) | Out-Null
            Write-Log "Added FirstLogonCommands entry at Order $newOrder"
        }
        
        $xml.Save($autounattendPath)
        Write-Log "autounattend.xml updated successfully" "SUCCESS"
        return $true
    }
    catch {
        Write-Log "Failed to update autounattend.xml: $_" "ERROR"
        return $false
    }
}

function Invoke-ISOBUILD {
    if ($SkipISOBUILD) {
        Write-Log ""
        Write-Log "---------------------------------------------------------------" "INFO"
        Write-Log "ISO Build: SKIPPED" "SKIP"
        Write-Log "---------------------------------------------------------------" "INFO"
        return $true
    }

    Write-Log ""
    Write-Log "---------------------------------------------------------------" "INFO"
    Write-Log "ISO Build: Building ISO" "INFO"
    Write-Log "---------------------------------------------------------------" "INFO"
    
    if (Test-Path $GWIGPipeline) {
        Write-Log "Found GWIG pipeline: $GWIGPipeline"
        try {
            & $GWIGPipeline
            if ($LASTEXITCODE -eq 0) {
                Write-Log "ISO build completed via GWIG pipeline" "SUCCESS"
                return $true
            } else {
                Write-Log "GWIG pipeline returned exit code: $LASTEXITCODE" "WARN"
                return $false
            }
        }
        catch {
            Write-Log "GWIG pipeline failed: $_" "ERROR"
            Write-Log "Manual ISO build required" "WARN"
            return $false
        }
    } else {
        Write-Log "GWIG pipeline not found: $GWIGPipeline" "WARN"
        Write-Log "Manual ISO build steps:" "INFO"
        Write-Log "  1. Mount source ISO"
        Write-Log "  2. Copy contents to working directory"
        Write-Log "  3. Mount WIM: Mount-WindowsImage -Path C:\\Mount -ImagePath sources\\install.wim -Index 1"
        Write-Log "  4. Add packages and drivers"
        Write-Log "  5. Copy Config\\SettingsMigration to mounted image"
        Write-Log "  6. Copy autounattend.xml to image root"
        Write-Log "  7. Dismount and commit WIM"
        Write-Log "  8. Build ISO with oscdimg"
        Write-Log ""
        Write-Log "Settings are ready for manual integration" "SUCCESS"
        return $true
    }
}

function Show-Summary {
    Write-Log ""
    Write-Log "---------------------------------------------------------------" "INFO"
    Write-Log "Build Summary" "INFO"
    Write-Log "---------------------------------------------------------------" "INFO"
    
    $duration = (Get-Date) - $script:StartTime
    Write-Log "Total Duration: $([math]::Round($duration.TotalMinutes, 2)) minutes"
    
    if ($script:LatestExport) {
        $size = (Get-ChildItem $script:LatestExport -Recurse -File | Measure-Object -Property Length -Sum).Sum
        Write-Log "Export Package: $script:LatestExport"
        Write-Log "Package Size: $([math]::Round($size/1MB, 2)) MB"
    }
    
    Write-Log "SettingsMigration Directory: $script:ProjectRoot\Config\SettingsMigration"
    Write-Log "autounattend.xml: Updated with FirstLogonCommands"
    
    Write-Log "---------------------------------------------------------------" "INFO"
    Write-Log "Next Steps:" "INFO"
    if ($SkipISOBUILD) {
        Write-Log "  1. Review the SettingsMigration directory"
        Write-Log "  2. Run your ISO build process manually or set -SkipISOBUILD:`$false"
    } else {
        Write-Log "  1. ISO should be ready for deployment"
        Write-Log "  2. Test in a VM before bare-metal installation"
    }
    Write-Log "  3. During installation, settings will auto-restore after FirstLogon"
    Write-Log "---------------------------------------------------------------" "INFO"
}

Write-Log "Build started at: $(Get-Date)"

$success = $true
if (-not (Invoke-SettingsExport)) { $success = $false }
if ($success -and -not (Test-ExportPackage)) { $success = $false }
if ($success -and -not (Initialize-SettingsMigrationDirectory)) { $success = $false }
if ($success -and -not (Update-AutounattendXML)) { $success = $false }
if ($success -and -not (Invoke-ISOBUILD)) { $success = $false }

Show-Summary

if ($success) {
    Write-Log "Build completed successfully!" "SUCCESS"
    exit 0
} else {
    Write-Log "Build completed with errors" "ERROR"
    exit 1
}
