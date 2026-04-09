#Requires -Version 5.1
#Requires -RunAsAdministrator

# Import common module
Import-Module (Join-Path (Split-Path $PSScriptRoot -Parent) "Modules\GoldISO-Common.psm1") -Force

<#
.SYNOPSIS
    New Enhanced Standalone ISO Builder
.DESCRIPTION
    All-in-one standalone builder that combines:
    1. Source ISO extraction and WIM mounting
    2. Offline image modifications (registry, drivers, AppX)
    3. Dynamic autounattend.xml generation with embedded scripts
    4. Disk layout template support (single or multi-disk)
    5. Bootable ISO creation
    
    Standalone - requires only a source Windows ISO and this script.
.PARAMETER SourceISO
    Path to source Windows ISO (required)
.PARAMETER OutputISO
    Path for output ISO (default: GamerOS-Standalone.iso in script directory)
.PARAMETER WinhanceConfigPath
    Path to Winhance config file to embed
.PARAMETER DiskLayoutTemplate
    Disk layout to use: "SingleDisk" or "GamerOS-3Disk" (default: SingleDisk)
.PARAMETER DriversPath
    Path to drivers for injection
.PARAMETER RegistryTweaksPath
    Path to registry tweaks JSON
.PARAMETER EmbedAllScripts
    Embed all auxiliary scripts in autounattend Extensions
.PARAMETER WorkingDir
    Working directory (default: C:\GoldISO_Standalone)
.PARAMETER MountDir
    WIM mount directory (default: C:\Mount)
.PARAMETER ComputerName
    Computer name for installation (default: GAMER-PC)
.PARAMETER UserName
    Local user name (default: Gamer)
.PARAMETER SkipDriverInjection
    Skip driver injection
.PARAMETER SkipCleanup
    Skip cleanup of working directory
.EXAMPLE
    .\New-EnhancedStandaloneBuild.ps1 -SourceISO "C:\ISOs\Win11.iso"
.EXAMPLE
    .\New-EnhancedStandaloneBuild.ps1 -SourceISO "C:\ISOs\Win11.iso" -DiskLayoutTemplate "GamerOS-3Disk"
.EXAMPLE
    .\New-EnhancedStandaloneBuild.ps1 -SourceISO "C:\ISOs\Win11.iso" -WinhanceConfigPath "C:\Configs\custom.winhance" -EmbedAllScripts
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)]
    [string]$SourceISO,
    
    [Parameter()]
    [string]$OutputISO = "",
    
    [Parameter()]
    [string]$WinhanceConfigPath = "",
    
    [Parameter()]
    [ValidateSet("SingleDisk", "GamerOS-3Disk")]
    [string]$DiskLayoutTemplate = "SingleDisk",
    
    [Parameter()]
    [string]$DriversPath = "",
    
    [Parameter()]
    [string]$RegistryTweaksPath = "",
    
    [Parameter()]
    [switch]$EmbedAllScripts,
    
    [Parameter()]
    [string]$WorkingDir = "C:\GoldISO_Standalone",
    
    [Parameter()]
    [string]$MountDir = "C:\Mount",
    
    [Parameter()]
    [string]$ComputerName = "GAMER-PC",
    
    [Parameter()]
    [string]$UserName = "Gamer",
    
    [Parameter()]
    [switch]$SkipDriverInjection,
    
    [Parameter()]
    [switch]$SkipCleanup
)

# Initialize
$ErrorActionPreference = "Stop"
$script:ScriptRoot = $PSScriptRoot
$script:ProjectRoot = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent

# Initialize centralized logging
$script:LogFile = "$WorkingDir\standalone-build.log"
Initialize-Logging -LogPath $script:LogFile

if ([string]::IsNullOrEmpty($OutputISO)) {
    $OutputISO = Join-Path $script:ProjectRoot "GamerOS-Standalone.iso"
}

# ==========================================
# LOGGING (uses Write-GoldISOLog from GoldISO-Common module)
# ==========================================

# ==========================================
# PREREQUISITES
# ==========================================

function Test-Prerequisites {
    Write-GoldISOLog "Checking prerequisites..." "STEP"
    
    # Check source ISO
    if (-not (Test-Path $SourceISO)) {
        Write-GoldISOLog "Source ISO not found: $SourceISO" "ERROR"
        exit 1
    }
    
    $isoSize = [math]::Round((Get-Item $SourceISO).Length / 1GB, 2)
    Write-GoldISOLog "Source ISO: $SourceISO ($isoSize GB)" "SUCCESS"
    
    # Check oscdimg
    $script:OscdimgPath = Resolve-Oscdimg
    if (-not $script:OscdimgPath) {
        Write-GoldISOLog "oscdimg.exe not found. Install Windows ADK." "ERROR"
        exit 1
    }
    Write-GoldISOLog "oscdimg: $($script:OscdimgPath)" "SUCCESS"
    
    # Check DISM
    if (-not (Get-Command dism -ErrorAction SilentlyContinue)) {
        Write-GoldISOLog "DISM not found" "ERROR"
        exit 1
    }
    Write-GoldISOLog "DISM: Available" "SUCCESS"
    
    # Check Winhance config if provided
    if ($WinhanceConfigPath -and -not (Test-Path $WinhanceConfigPath)) {
        Write-GoldISOLog "Winhance config not found: $WinhanceConfigPath" "WARN"
        $script:WinhanceConfigPath = ""
    }
}

function Resolve-Oscdimg {
    $inPath = Get-Command oscdimg -ErrorAction SilentlyContinue
    if ($inPath) { return $inPath.Source }
    
    $adkPaths = @(
        'C:\Program Files (x86)\Windows Kits\10\Assessment and Deployment Kit\Deployment Tools\amd64\Oscdimg\oscdimg.exe',
        'C:\Program Files\Windows Kits\10\Assessment and Deployment Kit\Deployment Tools\amd64\Oscdimg\oscdimg.exe'
    )
    foreach ($path in $adkPaths) {
        if (Test-Path $path) { return $path }
    }
    return $null
}

# ==========================================
# DISK LAYOUT TEMPLATES
# ==========================================
function Get-DiskLayoutXML {
    param([string]$Template)
    
    $layouts = @{
        "SingleDisk" = @"
<DiskConfiguration>
  <WillShowUI>Never</WillShowUI>
  <Disk wcm:action="add">
    <DiskID>0</DiskID>
    <WillWipeDisk>true</WillWipeDisk>
    <CreatePartitions>
      <CreatePartition wcm:action="add">
        <Order>1</Order>
        <Type>EFI</Type>
        <Size>100</Size>
      </CreatePartition>
      <CreatePartition wcm:action="add">
        <Order>2</Order>
        <Type>MSR</Type>
        <Size>16</Size>
      </CreatePartition>
      <CreatePartition wcm:action="add">
        <Order>3</Order>
        <Type>Primary</Type>
        <Extend>true</Extend>
      </CreatePartition>
    </CreatePartitions>
    <ModifyPartitions>
      <ModifyPartition wcm:action="add">
        <Order>1</Order>
        <PartitionID>1</PartitionID>
        <Format>FAT32</Format>
        <Label>System</Label>
      </ModifyPartition>
      <ModifyPartition wcm:action="add">
        <Order>2</Order>
        <PartitionID>3</PartitionID>
        <Format>NTFS</Format>
        <Label>Windows</Label>
        <Letter>C</Letter>
      </ModifyPartition>
    </ModifyPartitions>
  </Disk>
</DiskConfiguration>
"@
        
        "GamerOS-3Disk" = @"
<DiskConfiguration>
  <WillShowUI>Never</WillShowUI>
  <!-- Disk 0: Apps SSD - wiped only, configured post-install -->
  <Disk wcm:action="add">
    <DiskID>0</DiskID>
    <WillWipeDisk>true</WillWipeDisk>
  </Disk>
  <!-- Disk 1: Media HDD - wiped only, configured post-install -->
  <Disk wcm:action="add">
    <DiskID>1</DiskID>
    <WillWipeDisk>true</WillWipeDisk>
  </Disk>
  <!-- Disk 2: Windows NVMe - EFI + MSR + Windows (extends full) -->
  <Disk wcm:action="add">
    <DiskID>2</DiskID>
    <WillWipeDisk>true</WillWipeDisk>
    <CreatePartitions>
      <CreatePartition wcm:action="add">
        <Order>1</Order>
        <Type>EFI</Type>
        <Size>300</Size>
      </CreatePartition>
      <CreatePartition wcm:action="add">
        <Order>2</Order>
        <Type>MSR</Type>
        <Size>16</Size>
      </CreatePartition>
      <CreatePartition wcm:action="add">
        <Order>3</Order>
        <Type>Primary</Type>
        <Extend>true</Extend>
      </CreatePartition>
    </CreatePartitions>
    <ModifyPartitions>
      <ModifyPartition wcm:action="add">
        <Order>1</Order>
        <PartitionID>1</PartitionID>
        <Format>FAT32</Format>
        <Label>System</Label>
      </ModifyPartition>
      <ModifyPartition wcm:action="add">
        <Order>2</Order>
        <PartitionID>3</PartitionID>
        <Format>NTFS</Format>
        <Label>Windows</Label>
        <Letter>C</Letter>
      </ModifyPartition>
    </ModifyPartitions>
  </Disk>
</DiskConfiguration>
"@
    }
    
    return $layouts[$Template]
}

# ==========================================
# AUTOUNATTEND GENERATION
# ==========================================
function New-AutounattendXML {
    param(
        [string]$DiskLayout,
        [string]$ComputerName,
        [string]$UserName,
        [string]$WinhanceBase64,
        [switch]$EmbedScripts
    )
    
    Write-GoldISOLog "Generating autounattend.xml..." "STEP"
    
    $diskConfig = Get-DiskLayoutXML -Template $DiskLayout
    $installToDisk = if ($DiskLayout -eq "GamerOS-3Disk") { 2 } else { 0 }
    
    # Base XML structure
    $xml = @"
<?xml version="1.0" encoding="utf-8"?>
<unattend xmlns="urn:schemas-microsoft-com:unattend" xmlns:wcm="http://schemas.microsoft.com/WMIConfig/2002/State">
  <settings pass="offlineServicing">
  </settings>
  <settings pass="windowsPE">
    <component name="Microsoft-Windows-Setup" processorArchitecture="amd64" publicKeyToken="31bf3856ad364e35" language="neutral" versionScope="nonSxS">
      <UserData>
        <ProductKey>
          <Key>VK7JG-NPHTM-C97JM-9MPGT-3V66T</Key>
        </ProductKey>
        <AcceptEula>true</AcceptEula>
      </UserData>
      <ImageInstall>
        <OSImage>
          <InstallFrom>
            <MetaData wcm:action="add">
              <Key>/IMAGE/INDEX</Key>
              <Value>6</Value>
            </MetaData>
          </InstallFrom>
          <InstallTo>
            <DiskID>$installToDisk</DiskID>
            <PartitionID>3</PartitionID>
          </InstallTo>
          <WillShowUI>Never</WillShowUI>
        </OSImage>
      </ImageInstall>
      $diskConfig
      <RunSynchronous>
        <RunSynchronousCommand wcm:action="add">
          <Order>1</Order>
          <Description>Enable Remote Desktop</Description>
          <Path>reg add "HKLM\SYSTEM\CurrentControlSet\Control\Terminal Server" /v fDenyTSConnections /t REG_DWORD /d 0 /f</Path>
        </RunSynchronousCommand>
      </RunSynchronous>
    </component>
  </settings>
  <settings pass="specialize">
    <component name="Microsoft-Windows-Shell-Setup" processorArchitecture="amd64" publicKeyToken="31bf3856ad364e35" language="neutral" versionScope="nonSxS">
      <ComputerName>$ComputerName</ComputerName>
      <TimeZone>Eastern Standard Time</TimeZone>
    </component>
    <component name="Microsoft-Windows-Deployment" processorArchitecture="amd64" publicKeyToken="31bf3856ad364e35" language="neutral" versionScope="nonSxS">
      <RunSynchronous>
        <RunSynchronousCommand wcm:action="add">
          <Order>1</Order>
          <Description>Configure Secondary Drives</Description>
          <Path>powershell.exe -ExecutionPolicy Bypass -Command "if (Test-Path 'C:\ProgramData\Winhance\Config\*.winhance') { New-Item -Path 'C:\ProgramData\Winhance' -Name '.configured' -ItemType File -Force | Out-Null }"
          <WillReboot>Never</WillReboot>
        </RunSynchronousCommand>
      </RunSynchronous>
    </component>
  </settings>
  <settings pass="oobeSystem">
    <component name="Microsoft-Windows-Shell-Setup" processorArchitecture="amd64" publicKeyToken="31bf3856ad364e35" language="neutral" versionScope="nonSxS">
      <UserAccounts>
        <LocalAccounts>
          <LocalAccount wcm:action="add">
            <Name>$UserName</Name>
            <Group>Administrators</Group>
            <Password>
              <Value></Value>
              <PlainText>true</PlainText>
            </Password>
          </LocalAccount>
        </LocalAccounts>
      </UserAccounts>
      <AutoLogon>
        <Username>$UserName</Username>
        <Enabled>true</Enabled>
        <LogonCount>1</LogonCount>
        <Password>
          <Value></Value>
          <PlainText>true</PlainText>
        </Password>
      </AutoLogon>
      <OOBE>
        <HideEULAPage>true</HideEULAPage>
        <HideOEMRegistrationScreen>true</HideOEMRegistrationScreen>
        <HideOnlineAccountScreens>true</HideOnlineAccountScreens>
        <HideWirelessSetupInOOBE>true</HideWirelessSetupInOOBE>
        <ProtectYourPC>3</ProtectYourPC>
      </OOBE>
      <FirstLogonCommands>
        <SynchronousCommand wcm:action="add">
          <Order>1</Order>
          <CommandLine>powershell.exe -ExecutionPolicy Bypass -Command "Get-WindowsUpdate -AcceptAll -AutoReboot"</CommandLine>
          <Description>Install Windows Updates</Description>
        </SynchronousCommand>
      </FirstLogonCommands>
    </component>
  </settings>
"@

    # Add Extensions with embedded content if provided
    if ($EmbedScripts -or $WinhanceBase64) {
        $xml += @"

  <Extensions xmlns="https://schneegans.de/windows/unattend-generator/">
"@
        
        # Embed Winhance config
        if ($WinhanceBase64) {
            $xml += @"
    <File path="C:\ProgramData\Winhance\Config\WinHance_Config.winhance">
$WinhanceBase64
    </File>
"@
        }
        
        $xml += @"
  </Extensions>
"@
    }
    
    $xml += @"
</unattend>
"@
    
    Write-GoldISOLog "autounattend.xml generated" "SUCCESS"
    return $xml
}

function ConvertTo-Base64String {
    param([string]$FilePath)
    
    if (-not (Test-Path $FilePath)) { return $null }
    
    $bytes = [System.IO.File]::ReadAllBytes($FilePath)
    return [Convert]::ToBase64String($bytes)
}

# ==========================================
# ISO OPERATIONS (using GoldISO-Common module functions)
# Mount-GoldISOImage, Dismount-GoldISOImage, Copy-GoldISOContents

# ==========================================
# WIM MODIFICATIONS
# ==========================================
# WIM mount/dismount now uses Mount-GoldISOWIM / Dismount-GoldISOWIM from module

function Invoke-RegistryTweaks {
    param([string]$MountPath)
    
    if ([string]::IsNullOrEmpty($RegistryTweaksPath) -or -not (Test-Path $RegistryTweaksPath)) {
        return
    }
    
    Write-GoldISOLog "Applying registry tweaks..." "STEP"
    
    try {
        $tweaks = Get-Content $RegistryTweaksPath -Raw | ConvertFrom-Json
    }
    catch {
        Write-GoldISOLog "Failed to parse registry tweaks" "WARN"
        return
    }
    
    $hives = @{
        "SYSTEM" = "$MountPath\Windows\System32\config\SYSTEM"
        "SOFTWARE" = "$MountPath\Windows\System32\config\SOFTWARE"
        "DEFAULT" = "$MountPath\Windows\System32\config\DEFAULT"
    }
    
    foreach ($hiveName in $hives.Keys) {
        $hivePath = $hives[$hiveName]
        $mountPoint = "HKLM\OFFLINE_$hiveName"
        
        try {
            reg load $mountPoint $hivePath 2>&1 | Out-Null
            
            $hiveTweaks = $tweaks | Where-Object { $_.Hive -eq $hiveName }
            foreach ($t in $hiveTweaks) {
                $target = "$mountPoint\$($t.Path)"
                $regType = if ($t.Type) { $t.Type } else { "REG_DWORD" }
                reg add $target /v $t.Name /t $regType /d $t.Data /f 2>&1 | Out-Null
            }
            
            reg unload $mountPoint 2>&1 | Out-Null
        }
        catch {
            reg unload $mountPoint 2>$null | Out-Null
        }
    }
    
    Write-GoldISOLog "Registry tweaks applied" "SUCCESS"
}

function Invoke-DriverInjection {
    param([string]$MountPath)
    
    if ($SkipDriverInjection -or [string]::IsNullOrEmpty($DriversPath) -or -not (Test-Path $DriversPath)) {
        return
    }
    
    Write-GoldISOLog "Injecting drivers..." "STEP"
    
    try {
        dism /Image:$MountPath /Add-Driver /Driver:$DriversPath /Recurse /ForceUnsigned 2>&1 | Out-Null
        Write-GoldISOLog "Drivers injected" "SUCCESS"
    }
    catch {
        Write-GoldISOLog "Driver injection had warnings" "WARN"
    }
}

# ==========================================
# ISO BUILD (using GoldISO-Common module functions)
# Export-GoldISOWIM, New-GoldISOImage

# ==========================================
# CLEANUP
# ==========================================
function Invoke-Cleanup {
    param([string]$Path)
    
    if ($SkipCleanup) {
        Write-GoldISOLog "Cleanup skipped" "WARN"
        return
    }
    
    try {
        if (Test-Path $Path) {
            Remove-Item -Path $Path -Recurse -Force -ErrorAction SilentlyContinue
            Write-GoldISOLog "Working directory cleaned" "SUCCESS"
        }
    }
    catch {
        Write-GoldISOLog "Cleanup incomplete" "WARN"
    }
}

# ==========================================
# MAIN EXECUTION
# ==========================================

try {
    Write-GoldISOLog "=========================================="
    Write-GoldISOLog "Enhanced Standalone Build"
    Write-GoldISOLog "Disk Layout: $DiskLayoutTemplate"
    Write-GoldISOLog "=========================================="
    
    Test-GoldISOAdmin -ExitIfNotAdmin
    Test-Prerequisites
    
    # Setup paths
    $isoContentDir = Join-Path $WorkingDir "ISO"
    $tempWIM = Join-Path $WorkingDir "optimized.wim"
    $wimPath = Join-Path $isoContentDir "sources\install.wim"
    
    # Mount and copy ISO
    $driveLetter = Mount-GoldISOImage -ISOPath $SourceISO
    Copy-GoldISOContents -SourceDrive $driveLetter -DestDir $isoContentDir
    Dismount-GoldISOImage -ISOPath $SourceISO
    
    # WIM Modifications
    Mount-GoldISOWIM -WIMPath $wimPath -MountPath $MountDir -Index 6
    Invoke-RegistryTweaks -MountPath $MountDir
    Invoke-DriverInjection -MountPath $MountDir
    Dismount-GoldISOWIM -MountPath $MountDir -Save
    
    # Export optimized WIM
    Export-GoldISOWIM -SourceWIM $wimPath -DestWIM $tempWIM -Index 6
    Move-Item -Path $tempWIM -Destination $wimPath -Force
    
    # Generate autounattend
    $winhanceB64 = if ($WinhanceConfigPath) { ConvertTo-Base64String -FilePath $WinhanceConfigPath } else { $null }
    $autounattend = New-AutounattendXML `
        -DiskLayout $DiskLayoutTemplate `
        -ComputerName $ComputerName `
        -UserName $UserName `
        -WinhanceBase64 $winhanceB64 `
        -EmbedScripts:$EmbedAllScripts
    
    # Write autounattend
    $unattendPath = Join-Path $isoContentDir "autounattend.xml"
    $autounattend | Set-Content -Path $unattendPath -Encoding UTF8 -Force
    Write-GoldISOLog "autounattend.xml written to ISO" "SUCCESS"
    
    # Build ISO
    $success = New-GoldISOImage -SourceDir $isoContentDir -OutputPath $OutputISO
    
    # Cleanup
    Invoke-Cleanup -Path $WorkingDir
    
    # Result
    Write-GoldISOLog "=========================================="
    if ($success) {
        Write-GoldISOLog "BUILD SUCCESSFUL" "SUCCESS"
        Write-GoldISOLog "Output: $OutputISO" "SUCCESS"
    }
    else {
        Write-GoldISOLog "BUILD FAILED" "ERROR"
        exit 1
    }
}
catch {
    Write-GoldISOLog "CRITICAL ERROR: $_" "ERROR"
    
    # Emergency cleanup
    $mounts = Get-WindowsImage -Mounted -ErrorAction SilentlyContinue
    foreach ($m in $mounts) {
        Dismount-WindowsImage -Path $m.MountPath -Discard -ErrorAction SilentlyContinue | Out-Null
    }
    
    Invoke-Cleanup -Path $WorkingDir
    exit 1
}
