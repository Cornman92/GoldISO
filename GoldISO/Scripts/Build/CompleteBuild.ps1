#Requires -Version 5.1
#Requires -RunAsAdministrator

# Import common module
Import-Module (Join-Path (Split-Path $PSScriptRoot -Parent) "Modules\GoldISO-Common.psm1") -Force

# Initialize centralized logging
$script:LogFile = "$WorkingDir\complete-build.log"
Initialize-Logging -LogPath $script:LogFile

<#
.SYNOPSIS
    Complete WIM Build with Winhance Configuration Staging
.DESCRIPTION
    Enhanced build script that:
    1. Downloads missing dependencies (ADK, drivers, apps, ISO) unless -SkipDependencyDownload
    2. Copies source ISO to a working copy (original is never modified)
    3. Mounts the working copy and extracts contents
    4. Mounts WIM for offline servicing
    5. Injects drivers (offline)
    6. Injects packages (.msu, .cab, MSIX, APPX)
    7. Applies registry tweaks via offline hive loading
    8. Removes AppX packages
    9. Configures services
   10. Stages Winhance configuration for first-boot execution
   11. Copies autounattend.xml
   12. Copies portable apps
   13. Rebuilds ISO with UEFI boot support
.PARAMETER WorkingDir
    Working directory for ISO build (default: C:\GoldISO_Build)
.PARAMETER MountDir
    Mount point for WIM image (default: C:\Mount)
.PARAMETER OutputISO
    Output ISO path (default: C:\Users\C-Man\GoldISO\GamerOS-Win11x64Pro25H2.iso)
.PARAMETER WinhanceConfigPath
    Path to Winhance config file (default: ..\Config\GamerOS\WinHance_Config_20260316.winhance)
.PARAMETER SkipDriverInjection
    Skip driver injection (for testing)
.PARAMETER SkipPackageInjection
    Skip package injection (for testing)
.PARAMETER SkipPortableApps
    Skip portable apps copy (for testing)
.PARAMETER SkipWinhanceStaging
    Skip Winhance configuration staging
.PARAMETER SkipDependencyDownload
    Skip automatic download of missing dependencies (ADK, drivers, apps, ISO)
.EXAMPLE
    .\CompleteBuild.ps1
.EXAMPLE
    .\CompleteBuild.ps1 -SkipDriverInjection -Verbose
.EXAMPLE
    .\CompleteBuild.ps1 -WinhanceConfigPath "C:\Configs\custom.winhance"
#>
[CmdletBinding()]
param(
    [string]$WorkingDir = "C:\GoldISO_Build",
    [string]$MountDir = "C:\Mount",
    [string]$OutputISO = (Join-Path (Split-Path (Split-Path $PSScriptRoot -Parent) -Parent) "GamerOS-Win11x64Pro25H2-Complete.iso"),
    [string]$WinhanceConfigPath = "",
    [switch]$SkipDriverInjection,
    [switch]$SkipPackageInjection,
    [switch]$SkipPortableApps,
    [switch]$SkipWinhanceStaging,
    [switch]$NoCleanup,
    [switch]$SkipDependencyDownload,
    [string]$DriverManifest = ""
)

$ErrorActionPreference = "Continue"
$script:ProjectRoot = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent

# Resolve oscdimg.exe - PATH first, then well-known ADK install locations
function Resolve-OscdimgPath {
    $inPath = Get-Command oscdimg -ErrorAction SilentlyContinue
    if ($inPath) { return $inPath.Source }

    $adkCandidates = @(
        'C:\Program Files (x86)\Windows Kits\10\Assessment and Deployment Kit\Deployment Tools\amd64\Oscdimg\oscdimg.exe',
        'C:\Program Files\Windows Kits\10\Assessment and Deployment Kit\Deployment Tools\amd64\Oscdimg\oscdimg.exe'
    )
    foreach ($c in $adkCandidates) {
        if (Test-Path $c) {
            $dir = Split-Path $c -Parent
            if ($env:PATH -notlike "*$dir*") { $env:PATH = $env:PATH + ';' + $dir }
            return $c
        }
    }
    return $null
}

# --- DEPENDENCY DOWNLOAD PHASE
function Invoke-Dependencies {
    param(
        [string]$ProjectRoot,
        [string]$SourceISOPath,
        [string]$ManifestPath
    )

    Write-GoldISOLog -Message "==========================================" -Level "INFO"
    Write-GoldISOLog -Message "DEPENDENCY CHECK: Ensuring all prerequisites" -Level "INFO"
    Write-GoldISOLog -Message "==========================================" -Level "INFO"

    Initialize-ADK
    Get-SourceISO -ISOPath $SourceISOPath
    Initialize-Drivers -DriversDir (Join-Path $ProjectRoot "Drivers") -ManifestPath $ManifestPath
    Initialize-Applications -AppsDir (Join-Path $ProjectRoot "Applications")
}

function Initialize-ADK {
    $oscdimg = Resolve-OscdimgPath
    if ($oscdimg) {
        Write-Log "ADK/oscdimg: already installed at $oscdimg" "SUCCESS"
        $script:OscdimgPath = $oscdimg
        return
    }

    Write-Log "oscdimg not found - downloading Windows ADK Deployment Tools..."
    $adkSetup = "$env:TEMP\adksetup.exe"

    try {
        Invoke-WebRequest -Uri 'https://go.microsoft.com/fwlink/?linkid=2289980' `
            -OutFile $adkSetup -UseBasicParsing -ErrorAction Stop
        Write-Log ("  Downloaded ADK setup: " + [math]::Round((Get-Item $adkSetup).Length / 1MB, 1) + " MB")
    }
    catch {
        Write-Log "ERROR: Failed to download ADK setup - $_" "ERROR"
        exit 1
    }

    Write-Log "  Installing ADK Deployment Tools (quiet, Deployment Tools feature only)..."
    $proc = Start-Process $adkSetup `
        -ArgumentList '/quiet /norestart /features OptionId.DeploymentTools' `
        -Wait -PassThru
    if ($proc.ExitCode -notin @(0, 3010)) {
        Write-Log ("ERROR: ADK installer exited with code " + $proc.ExitCode) "ERROR"
        exit 1
    }
    Write-Log "ADK Deployment Tools installed successfully" "SUCCESS"
    Remove-Item $adkSetup -Force -ErrorAction SilentlyContinue

    $script:OscdimgPath = Resolve-OscdimgPath
    if (-not $script:OscdimgPath) {
        Write-Log "ERROR: oscdimg still not found after ADK install" "ERROR"
        exit 1
    }
}

function Get-SourceISO {
    param([string]$ISOPath)

    if (Test-Path $ISOPath) {
        $sizeGB = [math]::Round((Get-Item $ISOPath).Length / 1GB, 2)
        Write-Log ("Source ISO: present ($sizeGB GB) - $ISOPath") "SUCCESS"
        return
    }

    Write-Log ("Source ISO not found at: $ISOPath") "WARN"
    Write-Log "Please provide a Windows 11 25H2 x64 ISO at the specified path" "ERROR"
    exit 1
}

function Initialize-Drivers {
    param([string]$DriversDir, [string]$ManifestPath)

    if (-not $ManifestPath -or -not (Test-Path $ManifestPath)) {
        $ManifestPath = Join-Path $DriversDir "download-manifest.json"
    }

    if (-not (Test-Path $ManifestPath)) {
        Write-Log "No driver download manifest found - skipping driver download check." "WARN"
        return
    }

    Write-Log "Checking driver manifest: $ManifestPath"
    try {
        $manifest = Get-Content $ManifestPath -Raw | ConvertFrom-Json
    }
    catch {
        Write-Log "ERROR: Failed to parse driver manifest - $_" "ERROR"
        return
    }

    $downloadDir = Join-Path $DriversDir "_DOWNLOADED_"
    New-Item -ItemType Directory -Path $downloadDir -Force | Out-Null

    foreach ($entry in $manifest.drivers) {
        if ($entry._disabled -eq $true) { continue }

        $category = $entry.category
        $catDir = Join-Path $DriversDir $category
        $infCount = if (Test-Path $catDir) {
            (Get-ChildItem $catDir -Recurse -Filter "*.inf" -ErrorAction SilentlyContinue).Count
        } else { 0 }

        if ($infCount -gt 0) {
            Write-Log ("  $category`: already present ($infCount .inf files)") "SUCCESS"
            continue
        }

        Write-Log ("  $category`: no drivers found - downloading from manifest...")

        $url = $entry.url
        $filename = if ($entry.filename) { $entry.filename } else { Split-Path $url -Leaf }
        $dlPath = Join-Path $downloadDir $filename

        try {
            if (-not (Test-Path $dlPath)) {
                Write-Log ("    Downloading: $url")
                Invoke-WebRequest -Uri $url -OutFile $dlPath -UseBasicParsing -ErrorAction Stop
                Write-Log ("    Downloaded: " + [math]::Round((Get-Item $dlPath).Length / 1MB, 1) + " MB")
            }
            
            if ($entry.sha256) {
                Write-Log "    Verifying SHA256 integrity..."
                $actualHash = (Get-FileHash $dlPath -Algorithm SHA256).Hash
                if ($actualHash -ne $entry.sha256) {
                    throw "Hash Mismatch!"
                }
                Write-Log "    Integrity Verified." "SUCCESS"
            }

            New-Item -ItemType Directory -Path $catDir -Force | Out-Null
            $ext = [System.IO.Path]::GetExtension($filename).ToLower()
            switch ($ext) {
                ".zip" { Expand-Archive -Path $dlPath -DestinationPath $catDir -Force }
                ".cab" { & expand.exe $dlPath -F:* $catDir | Out-Null }
                default { Copy-Item $dlPath $catDir -Force }
            }
            Write-Log ("    Extracted to: $catDir") "SUCCESS"
        }
        catch {
            Write-GoldISOLog -Message "WARNING: Failed to download/extract $category`: $_" -Level "WARN"
        }
    }
}

function Initialize-Applications {
    param([string]$AppsDir)

    $manifestPath = Join-Path $AppsDir "download-manifest.json"
    if (-not (Test-Path $manifestPath)) {
        Write-Log "No application download manifest found - skipping app download check." "WARN"
        return
    }

    Write-Log "Checking application manifest: $manifestPath"
    try {
        $manifest = Get-Content $manifestPath -Raw | ConvertFrom-Json
    }
    catch {
        Write-Log "ERROR: Failed to parse application manifest - $_" "ERROR"
        return
    }

    foreach ($app in $manifest.applications) {
        if ($app._disabled -eq $true) { continue }

        $checkPath = if ($app.checkFile) {
            Join-Path $AppsDir $app.checkFile
        } else {
            Join-Path $AppsDir $app.filename
        }

        if (Test-Path $checkPath) {
            Write-Log ("  " + $app.name + ": already present") "SUCCESS"
            continue
        }

        Write-Log ("  " + $app.name + ": not found - manual download required") "WARN"
    }
}

# --- WINHANCE CONFIGURATION STAGING
function Invoke-WinhanceStaging {
    param(
        [string]$MountPath,
        [string]$ConfigPath
    )
    
    Write-Log "=========================================="
    Write-Log "STEP: Staging Winhance Configuration"
    Write-Log "=========================================="
    
    # Determine Winhance config path
    $winhanceSource = if ($ConfigPath -and (Test-Path $ConfigPath)) {
        $ConfigPath
    } else {
        # Search for Winhance config in project
        $searchPaths = @(
            (Join-Path $script:ProjectRoot "Config\GamerOS\WinHance_Config_20260316.winhance"),
            (Join-Path $script:ProjectRoot "Config\WinHance_Config_20260316.winhance"),
            (Join-Path $script:ProjectRoot "WinHance_Config_20260316.winhance")
        )
        $found = $searchPaths | Where-Object { Test-Path $_ } | Select-Object -First 1
        $found
    }
    
    if (-not $winhanceSource -or -not (Test-Path $winhanceSource)) {
        Write-Log "Winhance config not found - skipping staging" "WARN"
        Write-Log "  Searched for: WinHance_Config_20260316.winhance" "WARN"
        return
    }
    
    # Stage Winhance config
    $winhanceDest = "$MountPath\ProgramData\Winhance\Config"
    Write-Log "Staging Winhance configuration from: $winhanceSource"
    
    try {
        New-Item -ItemType Directory -Path $winhanceDest -Force | Out-Null
        Copy-Item -Path $winhanceSource -Destination "$winhanceDest\WinHance_Config.winhance" -Force
        Write-Log "Winhance config staged to: $winhanceDest" "SUCCESS"
    }
    catch {
        Write-Log "Failed to stage Winhance config: $_" "ERROR"
        return
    }
    
    # Stage Winhance modules if they exist
    $modulesSource = Join-Path $script:ProjectRoot "Config\GamerOS\Winhance-Modules"
    if (Test-Path $modulesSource) {
        $modulesDest = "$MountPath\ProgramData\Winhance\Modules"
        try {
            New-Item -ItemType Directory -Path $modulesDest -Force | Out-Null
            Copy-Item -Path "$modulesSource\*" -Destination $modulesDest -Recurse -Force
            Write-Log "Winhance modules staged to: $modulesDest" "SUCCESS"
        }
        catch {
            Write-Log "Failed to stage Winhance modules: $_" "WARN"
        }
    }
    
    # Create Winhance first-run marker
    $markerFile = "$MountPath\ProgramData\Winhance\.staged"
    try {
        "Staged: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')" | Set-Content -Path $markerFile
        Write-Log "Winhance staging complete" "SUCCESS"
    }
    catch {
        Write-Log "Failed to create staging marker: $_" "WARN"
    }
}

# --- OFFLINE REGISTRY HARDENING
function Invoke-OfflineRegistryHardening {
    param($MountPath, $RegistryJson)
    if (-not (Test-Path $RegistryJson)) { return }
    Write-Log "Applying Queued Registry Tweaks..." "INFO"
    $tweaks = Get-Content $RegistryJson -Raw | ConvertFrom-Json
    
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
            $subTweaks = $tweaks | Where-Object { $_.Hive -eq "HKLM" -or $_.Hive -eq $hiveName }
            foreach ($t in $subTweaks) {
                $target = "$mountPoint\$($t.Path)"
                Write-Log "  Injecting: $($t.Name)"
                $regType = if ($t.Type) { $t.Type } else { "REG_SZ" }
                reg add $target /v $t.Name /t $regType /d $t.Data /f 2>&1 | Out-Null
            }
            reg unload $mountPoint 2>&1 | Out-Null
        } catch {
            Write-Log "  Failed to process hive $hiveName`: $_" "WARN"
            reg unload $mountPoint 2>$null
        }
    }
}

# --- OFFLINE DEBLOAT
function Invoke-OfflineDebloat {
    param($MountPath, $ConfigJson)
    if (-not (Test-Path $ConfigJson)) { return }
    Write-Log "Purging Queued AppX Packages..." "INFO"
    $json = Get-Content $ConfigJson -Raw | ConvertFrom-Json
    $apps = $json.packages | Where-Object { $_.risk -eq "safe" -or $_.IsSelected }
    foreach ($app in $apps) {
        Write-Log "  Removing Package: $($app.name)"
        dism /Image:$MountPath /Remove-ProvisionedAppxPackage /PackageName:$app.name 2>&1 | Out-Null
    }
}

# --- DRIVER INJECTION
function Add-Drivers {
    param([string]$MountPath, [string]$DriversDir)
    Write-Log "Injecting drivers from: $DriversDir"
    
    $driverCategories = @(
        "Audio Processing Objects (APOs)",
        "Extensions",
        "IDE ATA ATAPI controllers",
        "Monitors",
        "Network adapters",
        "Software components",
        "Sound, video and game controllers",
        "Storage controllers",
        "System devices"
    )
    
    $failedDrivers = @()
    
    foreach ($category in $driverCategories) {
        $categoryPath = Join-Path $DriversDir $category
        if (-not (Test-Path $categoryPath)) {
            Write-Log "  Skipping: $category (not found)" "WARN"
            continue
        }
        
        $infFiles = Get-ChildItem $categoryPath -Recurse -File -Filter "*.inf"
        if ($infFiles.Count -eq 0) {
            Write-Log "  Skipping: $category (no .inf files)" "WARN"
            continue
        }
        
        Write-Log "  Injecting $category ($($infFiles.Count) drivers)..."
        
        try {
            $result = dism /Image:$MountPath /Add-Driver /Driver:$categoryPath /Recurse /ForceUnsigned 2>&1 | Out-String
            if ($result -match "driver\(s\) installed") {
                Write-Log "    $category`: OK" "SUCCESS"
            } else {
                Write-Log "    $category`: Completed with warnings" "WARN"
            }
        }
        catch {
            Write-Log "    $category`: Failed - $_" "ERROR"
            $failedDrivers += $category
        }
    }
    
    if ($failedDrivers.Count -gt 0) {
        Write-Log "Failed driver categories: $($failedDrivers -join ', ')" "ERROR"
    } else {
        Write-Log "Driver injection complete" "SUCCESS"
    }
}

# --- PACKAGE INJECTION
function Add-Packages {
    param([string]$MountPath, [string]$PackagesDir)
    Write-Log "Injecting packages from: $PackagesDir"
    
    if (-not (Test-Path $PackagesDir)) {
        Write-Log "Packages directory not found, skipping" "WARN"
        return
    }
    
    # .msu updates
    $msuFiles = Get-ChildItem $PackagesDir -File -Filter "*.msu"
    foreach ($msu in $msuFiles) {
        Write-Log "  Installing: $($msu.Name)..."
        try {
            Add-WindowsPackage -Path $MountPath -PackagePath $msu.FullName -NoRestart -ErrorAction SilentlyContinue | Out-Null
            Write-GoldISOLog -Message "    OK" -Level "SUCCESS"
        }
        catch {
            Write-Log "    Skipped: $_" "WARN"
        }
    }
    
    # .cab updates
    $cabFiles = Get-ChildItem $PackagesDir -File -Filter "*.cab"
    foreach ($cab in $cabFiles) {
        Write-Log "  Installing: $($cab.Name)..."
        try {
            Add-WindowsPackage -Path $MountPath -PackagePath $cab.FullName -NoRestart -ErrorAction SilentlyContinue | Out-Null
            Write-GoldISOLog -Message "    OK" -Level "SUCCESS"
        }
        catch {
            Write-Log "    Skipped: $_" "WARN"
        }
    }
    
    Write-Log "Package injection complete" "SUCCESS"
}

# --- WIM OPERATIONS (using GoldISO-Common module functions)
# Mount-GoldISOWIM, Dismount-GoldISOWIM, Export-GoldISOWIM

# --- ISO OPERATIONS (using GoldISO-Common module functions)
# Mount-GoldISOImage, Dismount-GoldISOImage, Copy-GoldISOContents, New-GoldISOImage, Resolve-OscdimgPath

function Copy-AnswerFile {
    param([string]$ISODir, [string]$AnswerFile)
    Write-Log "Copying autounattend.xml to ISO root"
    Copy-Item -Path $AnswerFile -Destination "$ISODir\autounattend.xml" -Force
    Write-Log "Answer file copied" "SUCCESS"
}

function Copy-PortableApps {
    param([string]$ISODir, [string]$SourceDir)
    Write-Log "Copying portable apps from: $SourceDir"
    
    if (-not (Test-Path $SourceDir)) {
        Write-Log "Portable apps directory not found" "WARN"
        return
    }
    
    $destDir = Join-Path $ISODir "PortableApps"
    New-Item -ItemType Directory -Path $destDir -Force | Out-Null
    
    $items = Get-ChildItem $SourceDir -Directory
    foreach ($item in $items) {
        $srcPath = $item.FullName
        $dstPath = Join-Path $destDir $item.Name
        Copy-Item -Path $srcPath -Destination $dstPath -Recurse -Force
        Write-Log "  Copied: $($item.Name)"
    }
    
    Write-Log "Portable apps copied" "SUCCESS"
}

function Invoke-EmergencyDismount {
    Write-Log "Emergency cleanup: Checking for mounted images..." "WARN"
    
    $mounts = Get-WindowsImage -Mounted -ErrorAction SilentlyContinue
    foreach ($mount in $mounts) {
        Write-Log "  Forcefully unmounting: $($mount.MountPath)" "WARN"
        try {
            Dismount-WindowsImage -Path $mount.MountPath -Discard -ErrorAction Stop | Out-Null
        }
        catch {
            dism /Cleanup-Wim 2>&1 | Out-Null
        }
    }
}

# ==========================================
# MAIN EXECUTION
# ==========================================

try {
    Write-Log "=========================================="
    Write-Log "Complete Build System - Winhance Enhanced"
    Write-Log "=========================================="
    
    # Check admin
    Test-GoldISOAdmin -ExitIfNotAdmin
    
    # Setup paths
    $sourceISO = Join-Path $script:ProjectRoot "Win11-25H2x64v2.iso"
    $answerFile = Join-Path $script:ProjectRoot "autounattend.xml"
    
    if (-not (Test-Path $answerFile)) {
        Write-Log "ERROR: autounattend.xml not found at: $answerFile" "ERROR"
        exit 1
    }
    
    if (-not $SkipDependencyDownload) {
        Invoke-Dependencies -ProjectRoot $script:ProjectRoot -SourceISOPath $sourceISO -ManifestPath (Join-Path $script:ProjectRoot "Drivers\download-manifest.json")
    }
    
    # Setup working directory
    if (Test-Path $WorkingDir) {
        Remove-Item -Path $WorkingDir -Recurse -Force -ErrorAction SilentlyContinue
    }
    New-Item -ItemType Directory -Path $WorkingDir -Force | Out-Null
    
    # Create working copy of ISO
    $workingISO = Copy-WorkingISO -SourceISO $sourceISO -WorkingDir $WorkingDir
    $isoDrive = Mount-GoldISOImage -ISOPath $workingISO
    $isoContentsDir = Join-Path $WorkingDir "ISO"
    Copy-ISOContents -SourceDrive $isoDrive -DestDir $isoContentsDir
    Dismount-GoldISOImage -ISOPath $workingISO
    
    # Mount WIM
    $wimPath = Join-Path $isoContentsDir "sources\install.wim"
    Mount-GoldISOWIM -WIMPath $wimPath -MountPath $MountDir -Index 6
    
    # --- Driver Injection ---
    if (-not $SkipDriverInjection) { 
        Add-Drivers -MountPath $MountDir -DriversDir (Join-Path $script:ProjectRoot "Drivers") 
    }
    
    # --- Package Injection ---
    if (-not $SkipPackageInjection) { 
        Add-Packages -MountPath $MountDir -PackagesDir (Join-Path $script:ProjectRoot "Packages") 
    }
    
    # --- Registry Hardening ---
    $registryJson = Join-Path $script:ProjectRoot "Config\queued-registry.json"
    if (Test-Path $registryJson) {
        Invoke-OfflineRegistryHardening -MountPath $MountDir -RegistryJson $registryJson
    }
    
    # --- Debloating ---
    $debloatJson = Join-Path $script:ProjectRoot "Config\debloat-list.json"
    if (Test-Path $debloatJson) {
        Invoke-OfflineDebloat -MountPath $MountDir -ConfigJson $debloatJson
    }
    
    # --- Winhance Configuration Staging ---
    if (-not $SkipWinhanceStaging) {
        Invoke-WinhanceStaging -MountPath $MountDir -ConfigPath $WinhanceConfigPath
    }
    
    # --- Dismount and Export ---
    Dismount-GoldISOWIM -MountPath $MountDir -Save
    
    $singleIndexWIM = Join-Path $WorkingDir "install-single-index.wim"
    Export-GoldISOWIM -SourceWIM $wimPath -DestWIM $singleIndexWIM -Index 6 -Compression Maximum
    
    $finalWIM = Join-Path $isoContentsDir "sources\install.wim"
    Export-GoldISOWIM -SourceWIM $singleIndexWIM -DestWIM $finalWIM -Index 1 -Compression Maximum
    
    # --- Copy files and build ISO ---
    Copy-AnswerFile -ISODir $isoContentsDir -AnswerFile $answerFile
    
    if (-not $SkipPortableApps) { 
        Copy-PortableApps -ISODir $isoContentsDir -SourceDir (Join-Path $script:ProjectRoot "Applications\Portableapps") 
    }
    
    $isoCreated = New-GoldISOImage -SourceDir $isoContentsDir -OutputPath $OutputISO
    
    # Cleanup
    if (-not $NoCleanup) {
        Remove-Item -Path $WorkingDir -Recurse -Force -ErrorAction SilentlyContinue
    }
}
catch {
    Write-GoldISOLog -Message "CRITICAL BUILD ERROR: $_" -Level "ERROR"
    $isoCreated = $false
}
finally {
    Invoke-EmergencyDismount
}

Write-GoldISOLog -Message "==========================================" -Level "INFO"
if ($isoCreated) {
    Write-GoldISOLog -Message "BUILD COMPLETED SUCCESSFULLY" -Level "SUCCESS"
    Write-GoldISOLog -Message "Output: $OutputISO" -Level "SUCCESS"
} else {
    Write-GoldISOLog -Message "BUILD FAILED" -Level "ERROR"
}
