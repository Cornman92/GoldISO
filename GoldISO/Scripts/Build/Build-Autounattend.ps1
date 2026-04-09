#Requires -Version 5.1

# Import common module
$modulePath = Join-Path $PSScriptRoot "Modules\GoldISO-Common.psm1"
if (Test-Path $modulePath) {
    Import-Module $modulePath -Force
}

# Import common module for logging and utilities
Import-Module (Join-Path $PSScriptRoot "Modules\GoldISO-Common.psm1") -Force

<#
.SYNOPSIS
    Builds autounattend.xml with customizable disk layout and configuration.
.DESCRIPTION
    Generates a customized autounattend.xml file for Windows deployment.
    Supports multiple disk layouts including single-disk and multi-disk configurations.
    Can embed scripts and stage drivers for offline installation.
.PARAMETER ProfilePath
    Path to the JSON profile containing base configuration.
.PARAMETER OutputPath
    Path where the generated autounattend.xml will be saved.
.PARAMETER DiskLayout
    Disk layout template to use. Options: GamerOS-3Disk, SingleDisk-DevGaming, SingleDisk-Basic
.PARAMETER EmbedScripts
    Embed PowerShell scripts into the autounattend.xml for execution during setup.
.PARAMETER StageDrivers
    Stage drivers from the Installers\Drivers directory for offline injection.
.EXAMPLE
    .\Build-Autounattend.ps1 -ProfilePath ".\Config\Profiles\gaming.json" -OutputPath "C:\temp\autounattend.xml"
.EXAMPLE
    .\Build-Autounattend.ps1 -ProfilePath ".\Config\Profiles\gaming.json" -OutputPath "C:\temp\autounattend.xml" -DiskLayout "SingleDisk-DevGaming" -EmbedScripts
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$ProfilePath,

    [Parameter(Mandatory = $true)]
    [string]$OutputPath,

    [Parameter()]
    [ValidateSet("GamerOS-3Disk", "SingleDisk-DevGaming", "SingleDisk-Generic")]
    [string]$DiskLayout = "GamerOS-3Disk",

    [Parameter()]
    [switch]$EmbedScripts,

    [Parameter()]
    [switch]$StageDrivers
)

$ErrorActionPreference = "Stop"

# Resolve paths
$script:ProjectRoot = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
$script:BasePath = Join-Path $script:ProjectRoot "Config\DiskLayouts"

function Write-Status {
    param(
        [string]$Message,
        [ValidateSet("Info", "Success", "Warning", "Error")]
        [string]$Level = "Info"
    )
    $colorMap = @{
        "Info"    = "White"
        "Success" = "Green"
        "Warning" = "Yellow"
        "Error"   = "Red"
    }
    Write-Host "[$Level] $Message" -ForegroundColor $colorMap[$Level]
}

function Get-DiskConfiguration {
    param([string]$DiskLayout)

    $diskConfigFile = Join-Path $script:BasePath "$DiskLayout.xml"
    $diskJsonFile   = Join-Path $script:BasePath "$DiskLayout.json"

    if (-not (Test-Path $diskConfigFile)) {
        Write-Status "Disk layout XML not found: $diskConfigFile" "Error"
        throw "Disk layout configuration not found: $DiskLayout"
    }

    Write-Status "Loading disk configuration: $DiskLayout" "Info"
    $diskContent = Get-Content $diskConfigFile -Raw

    # Apply variable substitution using defaults from the companion JSON file
    if (Test-Path $diskJsonFile) {
        $layoutMeta = Get-Content $diskJsonFile -Raw | ConvertFrom-Json
        if ($layoutMeta.variables) {
            foreach ($varName in $layoutMeta.variables.PSObject.Properties.Name) {
                $defaultVal = $layoutMeta.variables.$varName.default
                $diskContent = $diskContent -replace [regex]::Escape("{{$varName}}"), $defaultVal
            }
        }
    } else {
        Write-Status "No companion JSON found for layout '$DiskLayout' " skipping variable substitution" "Warning"
    }

    return $diskContent
}

function Get-BuildProfile {
    param([string]$ProfilePath)

    if (-not (Test-Path $ProfilePath)) {
        Write-Status "Profile not found: $ProfilePath" "Error"
        throw "Profile file not found"
    }

    Write-Status "Loading profile: $ProfilePath" "Info"
    $profileContent = Get-Content $ProfilePath -Raw | ConvertFrom-Json
    return $profileContent
}

function Get-ScriptToEmbed {
    param([string]$ScriptName)

    $scriptPath = Join-Path $script:ProjectRoot "Config\Unattend\Modules\Scripts" $ScriptName

    if (-not (Test-Path $scriptPath)) {
        Write-Status "Script not found: $scriptPath" "Warning"
        return $null
    }

    return Get-Content $scriptPath -Raw
}

function Build-DiskConfigurationSection {
    param([string]$DiskLayout)

    # Get the raw XML with variables already substituted
    $diskConfigRaw = Get-DiskConfiguration -DiskLayout $DiskLayout

    # Strip the XML declaration if present so we can embed this as a fragment
    $diskConfigRaw = $diskConfigRaw -replace '^\s*<\?xml[^?]*\?>\s*', ''

    # Validate that the resulting fragment is well-formed
    try {
        $null = [xml]"<root xmlns:wcm=`"http://schemas.microsoft.com/WMIConfig/2002/State`">$diskConfigRaw</root>"
    } catch {
        throw "Disk layout '$DiskLayout' produced invalid XML after variable substitution: $($_.Exception.Message)"
    }

    Write-Status "Disk configuration section built for layout: $DiskLayout" "Info"
    return $diskConfigRaw.Trim()
}

function Build-FirstLogonCommands {
    param(
        [string]$DiskLayout,
        [switch]$IncludePostInstallDrivers
    )

    $commandsXml = ""
    $commandOrder = 1

    # Layout-specific folder creation
    if ($DiskLayout -eq "SingleDisk-DevGaming") {
        Write-Status "Adding FirstLogonCommand for Dev/Gaming folder creation" "Info"

        $folderScript = Get-ScriptToEmbed -ScriptName "Create-DevGamingFolders.ps1"

        if ($folderScript) {
            $encodedCommand = [Convert]::ToBase64String([System.Text.Encoding]::Unicode.GetBytes($folderScript))

            $commandsXml += @"
                    <SynchronousCommand wcm:action="add">
                        <CommandLine>powershell.exe -ExecutionPolicy Bypass -EncodedCommand $encodedCommand</CommandLine>
                        <Description>Create Dev and Gaming Folders</Description>
                        <Order>$commandOrder</Order>
                    </SynchronousCommand>
"@
            $commandOrder++
        }
    }

    if ($DiskLayout -eq "GamerOS-3Disk") {
        Write-Status "Adding FirstLogonCommands for GamerOS-3Disk folder creation on D: and E:" "Info"

        # Drive letter protection must run first so D: and E: are available
        $protectScript = Get-ScriptToEmbed -ScriptName "ProtectLetters.ps1"
        if ($protectScript) {
            $encodedProtect = [Convert]::ToBase64String([System.Text.Encoding]::Unicode.GetBytes($protectScript))
            $commandsXml += @"
                    <SynchronousCommand wcm:action="add">
                        <CommandLine>powershell.exe -NoProfile -ExecutionPolicy Bypass -EncodedCommand $encodedProtect</CommandLine>
                        <Description>Protect Reserved Drive Letters (D, E, R, etc.) from Removable Media</Description>
                        <Order>$commandOrder</Order>
                    </SynchronousCommand>
"@
            $commandOrder++
        }

        $commandsXml += @"
                    <SynchronousCommand wcm:action="add">
                        <CommandLine>powershell.exe -NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -Command "foreach (`$f in @('P-Apps','Scratch')) { `$p = Join-Path 'D:\' `$f; if (-not (Test-Path `$p)) { New-Item -ItemType Directory -Path `$p -Force | Out-Null } }"</CommandLine>
                        <Description>Create GamerOS Folders on D: (P-Apps, Scratch)</Description>
                        <Order>$commandOrder</Order>
                    </SynchronousCommand>
"@
        $commandOrder++

        $commandsXml += @"
                    <SynchronousCommand wcm:action="add">
                        <CommandLine>powershell.exe -NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -Command "foreach (`$f in @('Media','Backups')) { `$p = Join-Path 'E:\' `$f; if (-not (Test-Path `$p)) { New-Item -ItemType Directory -Path `$p -Force | Out-Null } }"</CommandLine>
                        <Description>Create GamerOS Folders on E: (Media, Backups)</Description>
                        <Order>$commandOrder</Order>
                    </SynchronousCommand>
"@
        $commandOrder++
    }

    # Add post-install driver command
    if ($IncludePostInstallDrivers) {
        Write-Status "Adding FirstLogonCommand for post-install drivers" "Info"

        $driverInstallCommand = @'
powershell.exe -ExecutionPolicy Bypass -Command "$stagePath='C:\Windows\Setup\Drivers\PostInstall'; $logPath='C:\$WinREAgent\Logs\PostInstallDrivers.log'; if (Test-Path $stagePath) { & 'C:\Windows\Setup\Drivers\Install-PostInstallDrivers.ps1' -DriverSourcePath $stagePath -LogPath $logPath } else { Write-Host 'Post-install drivers not found' }"
'@

        $commandsXml += @"
                    <SynchronousCommand wcm:action="add">
                        <CommandLine>$($driverInstallCommand.Trim())</CommandLine>
                        <Description>Install Post-Setup Drivers (Audio, Video, APOs, Extensions)</Description>
                        <Order>$commandOrder</Order>
                    </SynchronousCommand>
"@
        $commandOrder++
    }

    return $commandsXml
}

function Build-AutounattendXml {
    param(
        [object]$ProfileData,  # Renamed from $Profile to avoid automatic variable conflict
        [string]$DiskLayout,
        [switch]$EmbedScripts
    )

    # Check if post-install drivers are enabled in profile
    $includePostInstallDrivers = $false
    if ($ProfileData -and $ProfileData.drivers) {
        $drivers = $ProfileData.drivers
        if ($drivers.postInstallFromUSB -or $drivers.postInstallCategories -or $drivers.postInstallOptions) {
            $includePostInstallDrivers = $true
        }
    }

    $diskConfigSection = Build-DiskConfigurationSection -DiskLayout $DiskLayout
    $firstLogonCommands = Build-FirstLogonCommands -DiskLayout $DiskLayout -IncludePostInstallDrivers:$includePostInstallDrivers

    # Base XML structure
    $xmlHeader = @'
<?xml version="1.0" encoding="utf-8"?>
<unattend xmlns="urn:schemas-microsoft-com:unattend">
    <settings pass="windowsPE">
        <component name="Microsoft-Windows-Setup" processorArchitecture="amd64" publicKeyToken="31bf3856ad364e35" language="neutral" versionScope="nonSxS" xmlns:wcm="http://schemas.microsoft.com/WMIConfig/2002/State" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance">
'@

    $xmlFooterPart1 = @'
        </component>
    </settings>
    <settings pass="oobeSystem">
        <component name="Microsoft-Windows-Shell-Setup" processorArchitecture="amd64" publicKeyToken="31bf3856ad364e35" language="neutral" versionScope="nonSxS" xmlns:wcm="http://schemas.microsoft.com/WMIConfig/2002/State" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance">
            <OOBE>
                <HideEULAPage>true</HideEULAPage>
                <HideOEMRegistrationScreen>true</HideOEMRegistrationScreen>
                <HideOnlineAccountScreens>true</HideOnlineAccountScreens>
                <HideWirelessSetupInOOBE>true</HideWirelessSetupInOOBE>
                <SkipMachineOOBE>true</SkipMachineOOBE>
                <SkipUserOOBE>true</SkipUserOOBE>
            </OOBE>
            <FirstLogonCommands>
'@

    $xmlFooterPart2 = @'
            </FirstLogonCommands>
        </component>
    </settings>
</unattend>
'@

    $xmlFooter = $xmlFooterPart1 + $firstLogonCommands + $xmlFooterPart2

    # Combine all sections
    $fullXml = $xmlHeader + $diskConfigSection + $xmlFooter

    return $fullXml
}

# ==========================================
# MAIN EXECUTION
# ==========================================

try {
    Write-Status "==========================================" "Info"
    Write-Status "Building Autounattend Configuration" "Info"
    Write-Status "==========================================" "Info"

    # Load profile
    $buildProfile = Get-BuildProfile -ProfilePath $ProfilePath

    # Build XML content
    $xmlContent = Build-AutounattendXml -ProfileData $buildProfile -DiskLayout $DiskLayout -EmbedScripts:$EmbedScripts

    # Ensure output directory exists
    $outputDir = Split-Path $OutputPath -Parent
    if (-not (Test-Path $outputDir)) {
        New-Item -ItemType Directory -Path $outputDir -Force | Out-Null
    }

    # Write XML to file
    $xmlContent | Out-File -FilePath $OutputPath -Encoding UTF8

    Write-Status "Autounattend.xml created: $OutputPath" "Success"
    Write-Status "Disk Layout: $DiskLayout" "Success"

    if ($EmbedScripts) {
        Write-Status "Scripts embedded: Yes" "Success"
    }

    # Validation summary
    $null = [xml]$xmlContent  # Validate XML parsing
    Write-Status "XML validation: Passed" "Success"
}
catch {
    Write-Status "BUILD FAILED: $_" "Error"
    exit 1
}
