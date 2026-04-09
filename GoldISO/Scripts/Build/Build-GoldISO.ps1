#Requires -Version 5.1
#Requires -RunAsAdministrator

<#
.SYNOPSIS
    Build GoldISO custom Windows 11 ISO
.DESCRIPTION
    Automated build script that:
    0. Downloads missing dependencies (ADK, drivers, apps, ISO) unless -SkipDependencyDownload
    1. Copies source ISO to a working copy (original is never modified)
    2. Mounts the working copy and extracts contents
    3. Mounts WIM for offline servicing
    4. Injects drivers (offline)
    5. Injects packages (.msu, .cab, MSIX, APPX)
    6. Copies autounattend.xml
    7. Copies portable apps
    8. Rebuilds ISO with UEFI boot support
# --- PROFESSIONAL HARDENING ENGINE (V3.1) ---

# Import common module for logging and utilities
Import-Module (Join-Path $PSScriptRoot "Modules\GoldISO-Common.psm1") -Force

$ErrorActionPreference = "Stop"

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
            Write-Log "  Failed to process hive $hiveName: $_" "WARN"
            reg unload $mountPoint 2>$null
        }
    }
}

function Invoke-OfflineServiceConfig {
    param($MountPath, $ServiceConfigJson)
    if (-not (Test-Path $ServiceConfigJson)) { return }
    Write-Log "Applying Service Configurations..." "INFO"
    $config = Get-Content $ServiceConfigJson -Raw | ConvertFrom-Json
    $services = $config.services
    
    $regPath = "$MountPath\Windows\System32\config\SYSTEM\ControlSet001\Services"
    $mountPoint = "HKLM\OFFLINE_SYSTEM"
    try {
        reg load $mountPoint "$MountPath\Windows\System32\config\SYSTEM" 2>&1 | Out-Null
        
        foreach ($svcName in $services.PSObject.Properties.Name) {
            $svc = $services.$svcName
            $startType = switch ($svc.Startup) {
                "Automatic" { 2 }
                "Automatic (Delayed)" { 2 }
                "Manual" { 3 }
                "Disabled" { 4 }
                default { 2 }
            }
            $target = "$mountPoint\ControlSet001\Services\$svcName"
            reg add $target /v Start /t REG_DWORD /d $startType /f 2>&1 | Out-Null
            
            if ($svc.Startup -eq "Automatic (Delayed)" -and $svc.DelayS -gt 0) {
                $delayedKey = "$target\Parameters"
                reg add $delayedKey /v ServiceDelayedAutostart /t REG_DWORD /d 1 /f 2>&1 | Out-Null
            }
            Write-Log "  Configured: $svcName -> $($svc.Startup)"
        }
        reg unload $mountPoint 2>&1 | Out-Null
    } catch {
        Write-Log "  Failed to configure services: $_" "WARN"
        reg unload $mountPoint 2>$null
    }
}

function Invoke-OfflineDebloat {
    param($MountPath, $ConfigJson)
    if (-not (Test-Path $ConfigJson)) { return }
    Write-Log "Purging Queued AppX Packages..." "INFO"
    $json = Get-Content $ConfigJson -Raw | ConvertFrom-Json
    $apps = $json.packages | Where-Object { $_.risk -eq "safe" -or $_.IsSelected }
    foreach ($app in $apps) {
        Write-Log "  Removing Package: $($app.name)"
        dism "/Image:$MountPath" /Remove-ProvisionedAppxPackage "/PackageName:$($app.name)" | Out-Null
    }
}

function Invoke-OfflineDriverStore {
    param($MountPath, $ConfigJson)
    if (-not (Test-Path $ConfigJson)) { return }
    Write-Log "Managing Driver Store..." "INFO"
    $drivers = Get-Content $ConfigJson | ConvertFrom-Json
    # 1. Removal
    foreach ($d in ($drivers | Where-Object { $_.IsSelected })) {
        Write-Log "  Purging Driver: $($d.PublishedName)"
        Remove-WindowsDriver -Path $MountPath -Driver $d.PublishedName -ErrorAction SilentlyContinue | Out-Null
    }
    # 2. Injection
    $injectDir = Join-Path $script:ProjectRoot "Drivers\For_Injection"
    if (Test-Path $injectDir) {
        Write-Log "  Injecting New Packages from $injectDir..."
        Add-WindowsDriver -Path $MountPath -Driver $injectDir -Recurse -Force | Out-Null
    }
}

function Invoke-FsutilOptimizations {
    param($MountPath)
    Write-Log "Executing Advanced Filesystem Hardening..." "INFO"
    # Registry based triggers for FS
    # Load SYSTEM hive for FS behaviors
    $sysHive = "HKLM\OFFLINE_SYSTEM"
    reg load $sysHive "$MountPath\Windows\System32\config\SYSTEM" | Out-Null
    
    # 8.3 Creation
    reg add "$sysHive\ControlSet001\Control\FileSystem" /v NtfsDisable8dot3NameCreation /t REG_DWORD /d 1 /f | Out-Null
    Write-Log "  8.3 Creation Disabled." "SUCCESS"
    
    # Last Access
    reg add "$sysHive\ControlSet001\Control\FileSystem" /v NtfsDisableLastAccessUpdate /t REG_DWORD /d 1 /f | Out-Null
    
    reg unload $sysHive | Out-Null

    # 8.3 Stripping (Live Progress)
    # We strip safe paths by default
    $stripPaths = @("$MountPath\Program Files", "$MountPath\Program Files (x86)", "$MountPath\Users")
    foreach ($p in $stripPaths) {
        Write-Log "  Stripping 8.3 names from: $(Split-Path $p -Leaf)..."
        fsutil 8dot3name strip /s /v $p | Out-Null # In prod, pipe to log parser for % progress
    }
}

    Working directory for ISO build (default: C:\GoldISO_Build)
.PARAMETER MountDir
    Mount point for WIM image (default: C:\Mount)
.PARAMETER OutputISO
    Output ISO path (default: C:\Users\C-Man\GoldISO\GamerOS-Win11x64Pro25H2.iso)
.PARAMETER SkipDriverInjection
    Skip driver injection (for testing)
.PARAMETER SkipPackageInjection
    Skip package injection (for testing)
.PARAMETER SkipPortableApps
    Skip portable apps copy (for testing)
.PARAMETER SkipDependencyDownload
    Skip automatic download of missing dependencies (ADK, drivers, apps, ISO)
.PARAMETER DriverManifest
    Path to driver download manifest JSON. Defaults to Drivers\download-manifest.json
.EXAMPLE
    .\Build-GoldISO.ps1
.EXAMPLE
    .\Build-GoldISO.ps1 -SkipDriverInjection -Verbose
.EXAMPLE
    .\Build-GoldISO.ps1 -SkipDependencyDownload
#>
[CmdletBinding()]
param(
    [string]$WorkingDir = "C:\GoldISO_Build",
    [string]$MountDir = "C:\Mount",
    [string]$OutputISO = (Join-Path (Split-Path $PSScriptRoot -Parent) "GamerOS-Win11x64Pro25H2.iso"),
    [switch]$SkipDriverInjection,
    [switch]$SkipPackageInjection,
    [switch]$SkipPortableApps,
    [switch]$NoCleanup,
    [switch]$SkipDependencyDownload,
    [string]$DriverManifest = "",

    # Multi-phase WIM handling
    [ValidateSet("Standard", "Audit", "Capture")][string]$BuildMode = "Standard",
    [string]$SourceISOPath = "",
    [string]$TargetUsbDisk = "",
    [switch]$FlashToUsb,
    [switch]$SyncVentoy,
    [string]$CaptureWIMPath = $null,
    [switch]$IncludeAuditScripts,
    [switch]$IncludeCaptureScripts,
    
    # GoldISO Professional Features (V3.1)
    [string]$ServiceConfigJson = "C:\ProgramData\GoldISO\Config\services-config.json",
    [string]$RegistryQueueJson = "C:\ProgramData\GoldISO\Config\queued-registry.json",
    [string]$DebloatListJson  = "C:\ProgramData\GoldISO\Config\debloat-list.json",
    [string]$DriverQueueJson   = "C:\ProgramData\GoldISO\Config\driver-queue.json",

    # Modular Answer File System (V3.2)
    [string]$ProfilePath = "",
    [bool]$UseModular = $true,

    # Build Performance (V3.2)
    [switch]$ParallelDrivers = $false,
    
    # Build Checkpoint System (V3.2)
    [switch]$Resume,
    [string]$CheckpointPath = "",
    [switch]$ClearCheckpoint,
    
    # Disk Layout Selection (V3.2)
    [ValidateSet("GamerOS-3Disk", "SingleDisk-DevGaming", "SingleDisk-Generic")]
    [string]$DiskLayout = "GamerOS-3Disk",

    # Build Optimization (V3.5)
    [switch]$SkipChecksum,
    [switch]$VerifyISO
)

# Initialize project root variable for use throughout the script
$script:ProjectRoot = Split-Path $PSScriptRoot -Parent

# ============================================================================
# HELPER FUNCTIONS
# ============================================================================

function Resolve-OscdimgPath {
    $inPath = Get-Command oscdimg -ErrorAction SilentlyContinue
    if ($inPath) { return $inPath.Source }

    $adkCandidates = @(
        'C:\Program Files (x86)\Windows Kits\10\Assessment and Deployment Kit\Deployment Tools\amd64\Oscdimg\oscdimg.exe',
        'C:\Program Files\Windows Kits\10\Assessment and Deployment Kit\Deployment Tools\amd64\Oscdimg\oscdimg.exe'
    )
    foreach ($c in $adkCandidates) {
        if (Test-Path $c) {
            # Add containing directory to session PATH so Invoke-Expression "oscdimg ..." works
            $dir = Split-Path $c -Parent
            if ($env:PATH -notlike "*$dir*") { $env:PATH = $env:PATH + ';' + $dir }
            return $c
        }
    }
    return $null
}

# ---------------------------------------------------------------------------
# DEPENDENCY DOWNLOAD PHASE
# ---------------------------------------------------------------------------
function Invoke-Dependencies {
    param(
        [string]$ProjectRoot,
        [string]$SourceISOPath,
        [string]$ManifestPath
    )

    Write-Log "=========================================="
    Write-Log "DEPENDENCY CHECK: Ensuring all prerequisites"
    Write-Log "=========================================="

    Initialize-ADK
    Get-SourceISO   -ISOPath $SourceISOPath
    Initialize-Drivers     -DriversDir (Join-Path $ProjectRoot "Drivers")     -ManifestPath $ManifestPath
    Initialize-Applications -AppsDir   (Join-Path $ProjectRoot "Applications")
}

# --- ADK / oscdimg -----------------------------------------------------------
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
    # Exit code 0 = success, 3010 = success + reboot recommended (not required here)
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
    Write-Log ("oscdimg now available: " + $script:OscdimgPath) "SUCCESS"
}

# --- Source ISO --------------------------------------------------------------
function Get-SourceISO {
    param([string]$ISOPath)

    if (Test-Path $ISOPath) {
        $sizeGB = [math]::Round((Get-Item $ISOPath).Length / 1GB, 2)
        Write-Log ("Source ISO: present ($sizeGB GB) - $ISOPath") "SUCCESS"
        return
    }

    Write-Log ("Source ISO not found at: $ISOPath") "WARN"
    Write-Log "Attempting to download Windows 11 25H2 ISO via Fido..."

    $fidoScript = "$env:TEMP\Fido.ps1"
    try {
        Invoke-WebRequest -Uri 'https://raw.githubusercontent.com/pbatard/Fido/master/Fido.ps1' `
            -OutFile $fidoScript -UseBasicParsing -ErrorAction Stop
    }
    catch {
        Write-Log "ERROR: Cannot download Fido helper - $_" "ERROR"
        Write-Log "Please manually place the Windows 11 25H2 x64 ISO at: $ISOPath" "ERROR"
        exit 1
    }

    Write-Log "  Running Fido - a browser window will open to select and download the ISO."
    Write-Log "  Target path: $ISOPath"
    try {
        # Fido writes to the current directory; we move afterwards
        $isoDir = Split-Path $ISOPath -Parent
        Push-Location $isoDir
        & powershell.exe -ExecutionPolicy Bypass -File $fidoScript -Win 11 -Rel "25H2" -Ed "Pro" -Lang "English" -Arch "x64" -GetUrl `
        | Where-Object { $_ -match '^https' } `
        | Select-Object -First 1 `
        | ForEach-Object {
            Write-Log "  Downloading ISO from Microsoft CDN..."
            Invoke-WebRequest -Uri $_ -OutFile $ISOPath -UseBasicParsing
        }
        Pop-Location
    }
    catch {
        Pop-Location -ErrorAction SilentlyContinue
        Write-Log "ERROR: ISO download via Fido failed - $_" "ERROR"
        Write-Log "Please manually place the Windows 11 25H2 x64 ISO at: $ISOPath" "ERROR"
        exit 1
    }
    Remove-Item $fidoScript -Force -ErrorAction SilentlyContinue

    if (-not (Test-Path $ISOPath)) {
        Write-Log "ERROR: ISO still not present after download attempt." "ERROR"
        exit 1
    }
    Write-Log ("Source ISO downloaded: " + [math]::Round((Get-Item $ISOPath).Length / 1GB, 2) + " GB") "SUCCESS"
}

# --- Drivers (manifest-driven) -----------------------------------------------
function Initialize-Drivers {
    param([string]$DriversDir, [string]$ManifestPath)

    if (-not $ManifestPath -or -not (Test-Path $ManifestPath)) {
        $ManifestPath = Join-Path $DriversDir "download-manifest.json"
    }

    if (-not (Test-Path $ManifestPath)) {
        Write-Log "No driver download manifest found - skipping driver download check." "WARN"
        Write-Log ("  Create " + $ManifestPath + " to enable automatic driver downloads.")
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
        # Skip entries explicitly disabled in the manifest
        if ($entry._disabled -eq $true) { continue }

        $category = $entry.category
        $catDir = Join-Path $DriversDir $category
        $infCount = if (Test-Path $catDir) {
            (Get-ChildItem $catDir -Recurse -Filter "*.inf" -ErrorAction SilentlyContinue).Count
        }
        else { 0 }

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
                $maxRetries = 3
                for ($i = 0; $i -lt $maxRetries; $i++) {
                    try {
                        Invoke-WebRequest -Uri $url -OutFile $dlPath -UseBasicParsing -ErrorAction Stop
                        break
                    } catch {
                        if ($i -eq $maxRetries - 1) { throw $_ }
                        Write-Log "    Retry $($i+1)/$($maxRetries): $_" "WARN"
                        Start-Sleep -Seconds 2
                    }
                }
                Write-Log ("    Downloaded: " + [math]::Round((Get-Item $dlPath).Length / 1MB, 1) + " MB")
            }
            
            # Integrity Check (V3.1 Professional)
            if ($entry.sha256) {
                Write-Log "    Verifying SHA256 integrity..."
                $actualHash = (Get-FileHash $dlPath -Algorithm SHA256).Hash
                if ($actualHash -ne $entry.sha256 -and $actualHash -ne $entry.sha256.ToUpper()) {
                    throw "Hash Mismatch! Expected: $($entry.sha256) | Got: $actualHash"
                }
                Write-Log "    Integrity Verified." "SUCCESS"
            }

            # Extract based on file extension
            New-Item -ItemType Directory -Path $catDir -Force | Out-Null
            $ext = [System.IO.Path]::GetExtension($filename).ToLower()
            switch ($ext) {
                ".zip" {
                    Expand-Archive -Path $dlPath -DestinationPath $catDir -Force
                    Write-Log ("    Extracted to: $catDir") "SUCCESS"
                }
                ".exe" {
                    # Run self-extracting driver installer silently to extract-only path
                    $extractArgs = if ($entry.extractArgs) { $entry.extractArgs } else { "/s /e /f `"$catDir`"" }
                    Start-Process $dlPath -ArgumentList $extractArgs -Wait | Out-Null
                    Write-Log ("    Extracted via installer to: $catDir") "SUCCESS"
                }
                ".cab" {
                    & expand.exe $dlPath -F:* $catDir | Out-Null
                    Write-Log ("    Expanded CAB to: $catDir") "SUCCESS"
                }
                default {
                    Write-Log ("    Unknown archive type '$ext' - copying file only") "WARN"
                    Copy-Item $dlPath $catDir -Force
                }
            }
        }
        catch {
            Write-Log ("    WARNING: Failed to download/extract $category`: $_") "WARN"
        }
    }
    Write-Log "Driver dependency check complete" "SUCCESS"
}

# --- Applications (manifest-driven, with GitHub-latest and ZIP support) -------
function Resolve-AppDownloadUrl {
    param($App)
    # GitHub latest release: resolve asset URL dynamically
    if ($App.githubRepo -and $App.assetPattern) {
        try {
            Write-Log ("    Querying GitHub latest release: " + $App.githubRepo)
            $apiUrl = "https://api.github.com/repos/" + $App.githubRepo + "/releases/latest"
            $release = Invoke-RestMethod -Uri $apiUrl -UseBasicParsing -ErrorAction Stop
            $asset = $release.assets | Where-Object { $_.name -like $App.assetPattern } | Select-Object -First 1
            if ($asset) {
                Write-Log ("    Latest release: " + $release.tag_name + " -> " + $asset.name)
                return @{ Url = $asset.browser_download_url; Filename = $asset.name }
            }
            Write-Log ("    WARNING: No asset matched pattern '" + $App.assetPattern + "'") "WARN"
        }
        catch {
            Write-Log ("    WARNING: GitHub API query failed - $_") "WARN"
        }
    }
    # Static URL fallback
    if ($App.url) {
        $fname = if ($App.filename) { $App.filename } else { Split-Path $App.url -Leaf }
        return @{ Url = $App.url; Filename = $fname }
    }
    return $null
}

function Initialize-Applications {
    param([string]$AppsDir)

    $manifestPath = Join-Path $AppsDir "download-manifest.json"
    if (-not (Test-Path $manifestPath)) {
        Write-Log "No application download manifest found - skipping app download check." "WARN"
        Write-Log ("  Create " + $manifestPath + " to enable automatic application downloads.")
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

        # Determine presence check path: use checkFile if specified, else filename
        $checkPath = if ($app.checkFile) {
            Join-Path $AppsDir $app.checkFile
        }
        else {
            Join-Path $AppsDir $app.filename
        }

        if (Test-Path $checkPath) {
            Write-Log ("  " + $app.name + ": already present") "SUCCESS"
            continue
        }

        Write-Log ("  " + $app.name + ": not found - resolving download...")
        $resolved = Resolve-AppDownloadUrl -App $app
        if (-not $resolved) {
            Write-Log ("  WARNING: No download URL for " + $app.name + " - skipping") "WARN"
            continue
        }

        $dlPath = Join-Path $AppsDir $resolved.Filename
        try {
            if (-not (Test-Path $dlPath)) {
                Write-Log ("    Downloading: " + $resolved.Url)
                Invoke-WebRequest -Uri $resolved.Url -OutFile $dlPath -UseBasicParsing -ErrorAction Stop
                $sizeMB = [math]::Round((Get-Item $dlPath).Length / 1MB, 1)
                Write-Log ("    Downloaded: " + $resolved.Filename + " ($sizeMB MB)") "SUCCESS"
            }
            else {
                Write-Log ("    Using cached: $dlPath")
            }

            # Extract ZIP to subdirectory if requested
            if ($app.extractToSubdir -and $resolved.Filename -like "*.zip") {
                $subDir = Join-Path $AppsDir $app.extractToSubdir
                Write-Log ("    Extracting to: $subDir")
                Expand-Archive -Path $dlPath -DestinationPath $subDir -Force -ErrorAction Stop
                Write-Log ("    Extracted: " + $app.name) "SUCCESS"
            }

            Write-Log ("  " + $app.name + ": ready") "SUCCESS"
        }
        catch {
            Write-Log ("  WARNING: Failed to download/extract " + $app.name + " - $_") "WARN"
        }
    }
    Write-Log "Application dependency check complete" "SUCCESS"
}

# ---------------------------------------------------------------------------
# ISO COPY - protect original, work from copy
# ---------------------------------------------------------------------------
function Copy-WorkingISO {
    param([string]$SourceISO, [string]$WorkingDir)

    $isoName = [System.IO.Path]::GetFileNameWithoutExtension($SourceISO)
    $copyPath = Join-Path $WorkingDir ($isoName + "-work.iso")

    if (Test-Path $copyPath) {
        $existGB = [math]::Round((Get-Item $copyPath).Length / 1GB, 2)
        $srcGB = [math]::Round((Get-Item $SourceISO).Length / 1GB, 2)
        if ($existGB -eq $srcGB) {
            Write-Log ("Working ISO copy already exists and matches source ($existGB GB): $copyPath") "SUCCESS"
            return $copyPath
        }
        Write-Log "Existing working ISO size mismatch - removing and re-copying." "WARN"
        Remove-Item $copyPath -Force
    }

    $srcGB = [math]::Round((Get-Item $SourceISO).Length / 1GB, 2)
    Write-Log ("Copying source ISO to working copy ($srcGB GB)...")
    Write-Log "  Source : $SourceISO"
    Write-Log "  Dest   : $copyPath"
    Write-Log "  (Original ISO will NOT be modified)"

    Copy-Item -Path $SourceISO -Destination $copyPath -Force
    Write-Log ("Working copy created: $copyPath") "SUCCESS"
    return $copyPath
}

function Test-Prerequisites {
    Write-Log "Checking prerequisites..."
    
    # Check DISM
    $dism = Get-Command dism -ErrorAction SilentlyContinue
    if (-not $dism) {
        Write-Log "ERROR: DISM not found" "ERROR"
        exit 1
    }
    Write-Log "DISM: OK"
    
    # Check oscdimg (from Windows ADK) - also search the standard ADK install path
    $script:OscdimgPath = Resolve-OscdimgPath
    if (-not $script:OscdimgPath) {
        Write-Log "WARNING: oscdimg not found. Dependency download will attempt to install ADK." "WARN"
    }
    else {
        Write-Log ("oscdimg: OK (" + $script:OscdimgPath + ")") "SUCCESS"
    }
    
    # Check source ISO
    $sourceISO = Join-Path $script:ProjectRoot "Win11-25H2x64v2.iso"
    if (-not (Test-Path $sourceISO)) {
        Write-Log "ERROR: Source ISO not found: $sourceISO" "ERROR"
        exit 1
    }
    Write-Log "Source ISO: OK ($sourceISO)" "SUCCESS"
    
    # Check autounattend.xml (now in Config subdirectory)
    $answerFile = Join-Path $script:ProjectRoot "Config\autounattend.xml"
    if (-not (Test-Path $answerFile)) {
        # Fallback to root for backward compatibility
        $answerFile = Join-Path $script:ProjectRoot "autounattend.xml"
        if (-not (Test-Path $answerFile)) {
            Write-Log "ERROR: autounattend.xml not found in Config or root" "ERROR"
            exit 1
        }
    }
    Write-Log "Answer file: OK ($answerFile)" "SUCCESS"
    
    # Check drivers directory
    $driversDir = Join-Path $script:ProjectRoot "Drivers"
    if (-not (Test-Path $driversDir)) {
        Write-Log "ERROR: Drivers directory not found: $driversDir" "ERROR"
        exit 1
    }
    $driverCount = (Get-ChildItem $driversDir -Recurse -File -Filter "*.inf" | Measure-Object).Count
    Write-Log "Drivers: OK ($driverCount .inf files)" "SUCCESS"
    
    # Check packages directory
    $packagesDir = Join-Path $script:ProjectRoot "Packages"
    if (-not (Test-Path $packagesDir)) {
        Write-Log "WARNING: Packages directory not found: $packagesDir" "WARN"
    }
    else {
        $packageCount = (Get-ChildItem $packagesDir -File | Measure-Object).Count
        Write-Log "Packages: OK ($packageCount files)" "SUCCESS"
    }
    
    # Check portable apps
    $portableDir = Join-Path $script:ProjectRoot "Applications\Portableapps"
    if (-not (Test-Path $portableDir)) {
        Write-Log "WARNING: Portable apps directory not found: $portableDir" "WARN"
    }
    else {
        Write-Log "Portable apps: OK" "SUCCESS"
    }
}

function New-WorkingDirectory {
    param([string]$Path)
    if (Test-Path $Path) {
        Write-Log "Cleaning existing working directory: $Path" "WARN"
        # Try to unmount WIM if mounted
        try {
            Dismount-WindowsImage -Path $Path -Discard -ErrorAction SilentlyContinue | Out-Null
        }
        catch {}
        # Remove old directory
        Remove-Item -Path $Path -Recurse -Force -ErrorAction SilentlyContinue
    }
    New-Item -ItemType Directory -Path $Path -Force | Out-Null
    Write-Log "Created working directory: $Path"
}

function Mount-SourceISO {
    param([string]$ISOPath, [string]$MountPath)
    Write-Log "Mounting source ISO: $ISOPath"
    
    # Check if already mounted
    $mounted = Get-DiskImage -ImagePath $ISOPath -ErrorAction SilentlyContinue
    if ($mounted) {
        $driveLetter = ($mounted | Get-Volume).DriveLetter
        if ($driveLetter) {
            Write-Log "ISO already mounted at drive: $driveLetter" "WARN"
            return $driveLetter
        }
    }
    
    try {
        $image = Mount-DiskImage -ImagePath $ISOPath -PassThru -ErrorAction Stop
        $driveLetter = ($image | Get-Volume).DriveLetter
        if (-not $driveLetter) {
            Write-Log "ERROR: ISO mounted but no drive letter assigned" "ERROR"
            exit 1
        }
        Write-Log "ISO mounted at drive: $driveLetter" "SUCCESS"
        return $driveLetter
    }
    catch {
        Write-Log "ERROR: Failed to mount ISO - $_" "ERROR"
        exit 1
    }
}

function Copy-ISOContents {
    param([string]$SourceDrive, [string]$DestDir)
    Write-Log "Copying ISO contents from ${SourceDrive}:\ to $DestDir"
    
    $drivePath = "$SourceDrive`:\"
    robocopy $drivePath $DestDir /E /R:3 /W:5
    
    if (Test-Path "$DestDir\sources\install.wim") {
        Write-Log "ISO contents copied successfully" "SUCCESS"
    }
    else {
        Write-Log "ERROR: install.wim not found after copy" "ERROR"
        exit 1
    }
}

function Mount-WIM {
    param([string]$WIMPath, [string]$MountPath, [int]$Index = 1)
    Write-Log "Mounting WIM: $WIMPath (Index: $Index) to $MountPath"
    
    if (Test-Path $MountPath) {
        Write-Log "Unmounting existing WIM mount: $MountPath" "WARN"
        Dismount-WindowsImage -Path $MountPath -Discard -ErrorAction SilentlyContinue | Out-Null
    }
    
    New-Item -ItemType Directory -Path $MountPath -Force | Out-Null
    Mount-WindowsImage -ImagePath $WIMPath -Path $MountPath -Index $Index -ErrorAction Stop | Out-Null
    Write-Log "WIM mounted successfully" "SUCCESS"
}

function Optimize-Image {
    param([string]$MountPath)
    Write-Log "Running DISM optimize commands on image..."
    
    # Optimize APPX packages
    Write-Log "  Optimizing APPX packages..."
    try {
        $null = dism "/Image:`"$MountPath`"" /Optimize-AppxProvisionedPackage 2>&1 | Out-String
        if ($LASTEXITCODE -eq 0) {
            Write-Log "    APPX optimization complete" "SUCCESS"
        }
        else {
            Write-Log "    APPX optimization completed with warnings" "WARN"
        }
    }
    catch {
        Write-Log "    APPX optimization skipped: $_" "WARN"
    }
    
    # Cleanup image / ResetBase
    Write-Log "  Running image cleanup..."
    try {
        $null = dism "/Image:`"$MountPath`"" /Cleanup-Image /StartComponentCleanup /ResetBase 2>&1 | Out-String
        if ($LASTEXITCODE -eq 0) {
            Write-Log "    Image cleanup complete" "SUCCESS"
        }
        else {
            Write-Log "    Image cleanup completed with warnings" "WARN"
        }
    }
    catch {
        Write-Log "    Image cleanup skipped: $_" "WARN"
    }
    
    Write-Log "Image optimization complete" "SUCCESS"
}

function Export-SingleIndexWIM {
    param(
        [string]$SourceWIMPath,
        [string]$SourceIndex,
        [string]$DestWIMPath,
        [string]$Compression = "Maximum"
    )
    Write-Log "Exporting WIM (single index, $Compression compression)..."
    Write-Log "  Source: $SourceWIMPath (Index: $SourceIndex)"
    Write-Log "  Dest: $DestWIMPath"
    
    # Remove destination if it exists (can't overwrite in use WIM)
    if (Test-Path $DestWIMPath) {
        Write-Log "Removing existing WIM: $DestWIMPath"
        Remove-Item $DestWIMPath -Force -ErrorAction SilentlyContinue
    }
    
    try {
        Export-WindowsImage -SourceImagePath $SourceWIMPath `
            -SourceIndex $SourceIndex `
            -DestinationImagePath $DestWIMPath `
            -Compression $Compression `
            -ErrorAction Stop | Out-Null
        
        $wimSize = [math]::Round((Get-Item $DestWIMPath).Length / 1GB, 2)
        Write-Log "WIM exported: $DestWIMPath ($wimSize GB)" "SUCCESS"
    }
    catch {
        Write-Log "Export failed: $_" "ERROR"
        throw
    }
}

function Add-DriversParallel {
    param([string]$MountPath, [string]$DriversDir)
    Write-Log "Injecting core drivers offline (PARALLEL mode - max 4 concurrent)..." "INFO"
    # Extensions, Software components, APOs, Audio, Monitors injected post-boot via pnputil.

    $driverCategories = @(
        "IDE ATA ATAPI controllers",
        "Network adapters",
        "Storage controllers",
        "System devices"
    )
    
    $runspacePool = [runspacefactory]::CreateRunspacePool(1, 4)
    try {
        $runspacePool.Open()
        
        $jobs = @()
        $results = [System.Collections.Concurrent.ConcurrentBag]::new()
        
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
            
            $powershell = [powershell]::Create().AddScript({
                param($MountPath, $Category, $CategoryPath)
                
                $result = dism "/Image:$MountPath" /Add-Driver "/Driver:$CategoryPath" /Recurse /ForceUnsigned 2>&1 | Out-String
                if ($result -match "driver\(s\) installed") {
                    @{ Category = $Category; Status = "Success"; Result = $result }
                } else {
                    @{ Category = $Category; Status = "Warning"; Result = $result }
                }
            }).AddParameter("MountPath", $MountPath).AddParameter("Category", $category).AddParameter("CategoryPath", $categoryPath)
            
            $powershell.RunspacePool = $runspacePool
            $jobs += [PSCustomObject]@{
                Job = $powershell
                AsyncResult = $powershell.BeginInvoke()
                Category = $category
            }
        }
        
        $completed = 0
        $total = $jobs.Count
        
        while ($completed -lt $total) {
            foreach ($job in $jobs) {
                if ($job.AsyncResult.IsCompleted) {
                    $result = $job.Job.EndInvoke($job.AsyncResult)
                    $results.Add($result)
                    $job.Job.Dispose()
                    $completed++
                    
                    if ($result.Status -eq "Success") {
                        Write-Log "  $($result.Category): OK" "SUCCESS"
                    } else {
                        Write-Log "  $($result.Category): Completed with warnings" "WARN"
                    }
                }
            }
            Start-Sleep -Milliseconds 200
        }
    }
    finally {
        if ($runspacePool) {
            $runspacePool.Close()
            $runspacePool.Dispose()
        }
    }
    
    Write-Log "Parallel driver injection complete ($jobs.Count categories)" "SUCCESS"
}

function Add-Drivers {
    param([string]$MountPath, [string]$DriversDir)
    Write-Log "Injecting drivers from: $DriversDir"
    
    # Categories to inject offline via DISM (core hardware needed before first boot).
    # Excluded from offline injection (require running OS for correct PnP enumeration):
    #   - Display adapters (NVIDIA)        -> post-boot pnputil
    #   - Universal Serial Bus controllers -> post-boot pnputil
    #   - Extensions                       -> post-boot pnputil
    #   - Software components              -> post-boot pnputil
    #   - Audio Processing Objects (APOs)  -> post-boot pnputil
    #   - Sound, video and game controllers-> post-boot pnputil
    #   - Monitors                         -> post-boot pnputil
    $driverCategories = @(
        "IDE ATA ATAPI controllers",
        "Network adapters",
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
            $result = dism "/Image:$MountPath" /Add-Driver "/Driver:`"$categoryPath`"" /Recurse /ForceUnsigned 2>&1 | Out-String
            
            # Parse result for success/failure count
            if ($result -match "driver\(s\) installed") {
                $catName = $category
                Write-Log "    $catName`: OK" "SUCCESS"
            }
            else {
                $catName = $category
                Write-Log "    $catName`: Completed with warnings" "WARN"
            }
        }
        catch {
            $catName = $category
            Write-Log "    $catName`: Failed - $_" "ERROR"
            $failedDrivers += $category
        }
    }
    
    if ($failedDrivers.Count -gt 0) {
        Write-Log "Failed driver categories: $($failedDrivers -join ', ')" "ERROR"
    }
    else {
        Write-Log "Driver injection complete" "SUCCESS"
    }
}

function Add-Packages {
    param([string]$MountPath, [string]$PackagesDir)
    Write-Log "Injecting packages from: $PackagesDir"
    
    if (-not (Test-Path $PackagesDir)) {
        Write-Log "Packages directory not found, skipping" "WARN"
        return
    }
    
    # .msu updates
    $msuFiles = Get-ChildItem $PackagesDir -File -Filter "*.msu"
    Write-Log "Found $($msuFiles.Count) .msu files"
    
    foreach ($msu in $msuFiles) {
        Write-Log "  Installing: $($msu.Name)..."
        try {
            $result = Add-WindowsPackage -Path $MountPath -PackagePath $msu.FullName -NoRestart -ErrorAction SilentlyContinue 2>&1 | Out-String
            if ($result -match "successfully" -or $result -match "installed") {
                Write-Log "    OK" "SUCCESS"
            }
            elseif ($result -match "already installed" -or $result -match "superseded") {
                Write-Log "    Skipped (already applied)" "WARN"
            }
            else {
                Write-Log "    Skipped (may be outdated): $($result.Substring(0, [Math]::Min(100, $result.Length)))" "WARN"
            }
        }
        catch {
            Write-Log "    Skipped: $_" "WARN"
        }
    }
    
    # .cab updates
    $cabFiles = Get-ChildItem $PackagesDir -File -Filter "*.cab"
    Write-Log "Found $($cabFiles.Count) .cab files"
    
    foreach ($cab in $cabFiles) {
        Write-Log "  Installing: $($cab.Name)..."
        try {
            Add-WindowsPackage -Path $MountPath -PackagePath $cab.FullName -NoRestart -ErrorAction SilentlyContinue | Out-Null
            Write-Log "    OK" "SUCCESS"
        }
        catch {
            Write-Log "    Skipped: $_" "WARN"
        }
    }
    
    # MSIX bundles
    $msixFiles = Get-ChildItem $PackagesDir -File -Filter "*.msixbundle"
    Write-Log "Found $($msixFiles.Count) .msixbundle files"
    
    foreach ($msix in $msixFiles) {
        Write-Log "  Installing: $($msix.Name)..."
        try {
            Add-AppxProvisionedPackage -Path $MountPath -PackagePath $msix.FullName -SkipLicense -ErrorAction SilentlyContinue | Out-Null
            Write-Log "    OK" "SUCCESS"
        }
        catch {
            Write-Log "    Skipped: $_" "WARN"
        }
    }
    
    # APPX packages
    $appxFiles = Get-ChildItem $PackagesDir -File -Filter "*.appx"
    Write-Log "Found $($appxFiles.Count) .appx files"
    
    foreach ($appx in $appxFiles) {
        Write-Log "  Installing: $($appx.Name)..."
        try {
            Add-AppxProvisionedPackage -Path $MountPath -PackagePath $appx.FullName -SkipLicense -ErrorAction SilentlyContinue | Out-Null
            Write-Log "    OK" "SUCCESS"
        }
        catch {
            Write-Log "    Skipped: $_" "WARN"
        }
    }
    
    Write-Log "Package injection complete" "SUCCESS"
}

function Copy-AnswerFile {
    param([string]$ISODir, [string]$AnswerFile)
    Write-Log "Copying autounattend.xml to ISO root"
    
    Copy-Item -Path $AnswerFile -Destination "$ISODir\autounattend.xml" -Force
    Write-Log "Answer file copied" "SUCCESS"
}

function Copy-PortableApps {
    param([string]$ISODir, [string]$SourceDir)
    Write-Log "Copying portable apps from: $SourceDir"
    
    # Define portable apps to include (27 apps, no games)
    $includeApps = @(
        "7-ZipPortable",
        "EverythingPortable",
        "FreeCommanderPortable",
        "Explorer++Portable",
        "FileVoyagerPortable",
        "AutorunsPortable",
        "BleachBitPortable",
        "ClamWinPortable",
        "EmsisoftEmergencyKitPortable",
        "InnoUnpackerPortable",
        "PortableApps.com",
        "JkDefragPortable",
        "CPU-ZPortable",
        "GPU-ZPortable",
        "HWiNFOPortable",
        "HWMonitorPortable",
        "FileZillaPortable",
        "ConsolePortable",
        "CopyQPortable",
        "DM2Portable",
        "FreeFileSyncPortable",
        "grepWinPortable",
        "DittoPortable",
        "DuplicateFilesFinderPortable",
        "fcpyPortable",
        "DaphnePortable",
        "CommonFiles"
    )
    
    $destDir = Join-Path $ISODir "PortableApps"
    if (-not (Test-Path $destDir)) {
        New-Item -ItemType Directory -Path $destDir -Force | Out-Null
    }
    
    $copied = 0
    $skipped = 0
    
    foreach ($app in $includeApps) {
        $srcPath = Join-Path $SourceDir $app
        if (Test-Path $srcPath) {
            $dstPath = Join-Path $destDir $app
            Copy-Item -Path $srcPath -Destination $dstPath -Recurse -Force
            Write-Log "  Copied: $app"
            $copied++
        }
        else {
            Write-Log "  Skipped (not found): $app" "WARN"
            $skipped++
        }
    }
    
    Write-Log "Portable apps: $copied copied, $skipped not found" "SUCCESS"
}

function Dismount-WIMImage {
    param([string]$MountPath, [switch]$Save)
    Write-Log "Unmounting WIM from: $MountPath"
    
    if (-not (Test-Path $MountPath)) {
        Write-Log "WIM not mounted, skipping"
        return
    }
    
    if ($Save) {
        Dismount-WindowsImage -Path $MountPath -Save -ErrorAction Stop | Out-Null
        Write-Log "WIM unmounted and saved" "SUCCESS"
    }
    else {
        Dismount-WindowsImage -Path $MountPath -Discard -ErrorAction SilentlyContinue | Out-Null
        Write-Log "WIM unmounted (discarded)" "WARN"
    }
}

function Dismount-ISO {
    param([string]$ISOPath)
    Write-Log "Dismounting ISO: $ISOPath"
    
    try {
        $image = Get-DiskImage -ImagePath $ISOPath -ErrorAction SilentlyContinue
        if ($image) {
            Dismount-DiskImage -ImagePath $ISOPath -ErrorAction SilentlyContinue | Out-Null
            Write-Log "ISO dismounted" "SUCCESS"
        }
    }
    catch {
        Write-Log "Could not dismount ISO: $_" "WARN"
    }
}

function Build-ISOImage {
    param([string]$ISODir, [string]$OutputPath)
    Write-Log "Rebuilding ISO: $OutputPath"
    
    # Resolve oscdimg - prefer the cached path, fall back to PATH search
    $oscdimgExe = if ($script:OscdimgPath -and (Test-Path $script:OscdimgPath)) {
        $script:OscdimgPath
    }
    else {
        Resolve-OscdimgPath
    }
    if (-not $oscdimgExe) {
        Write-Log "ERROR: oscdimg not found. Run without -SkipDependencyDownload to auto-install ADK." "ERROR"
        return $false
    }

    $efiBoot = "$ISODir\efi\microsoft\boot\efisys.bin"
    $etfsBoot = "$ISODir\boot\etfsboot.com"

    if (-not (Test-Path $efiBoot)) {
        Write-Log "ERROR: EFI boot file not found: $efiBoot" "ERROR"
        return $false
    }

    if (-not (Test-Path $etfsBoot)) {
        Write-Log "ERROR: ETFS boot file not found: $etfsBoot" "ERROR"
        return $false
    }

    $label = "GAMEROS"

    Write-Log ("Using oscdimg: $oscdimgExe")
    & $oscdimgExe ("-bootdata:2#p0,e,b$etfsBoot#pEF,e,b$efiBoot") -o -u2 -udfver102 "-l$label" $ISODir $OutputPath
    
    if (Test-Path $OutputPath) {
        $sizeGB = [math]::Round((Get-Item $OutputPath).Length / 1GB, 2)
        Write-Log "ISO created: $OutputPath ($sizeGB GB)" "SUCCESS"
        
        # Generate SHA256 checksum (unless skipped)
        if (-not $SkipChecksum) {
            Write-Log "Generating SHA256 checksum..."
            $checksumPath = $OutputPath + ".sha256"
            $hash = Get-FileHash $OutputPath -Algorithm SHA256
            "$($hash.Hash)  $([System.IO.Path]::GetFileName($OutputPath))" | Set-Content $checksumPath -Encoding UTF8
            Write-Log "Checksum saved: $checksumPath" "SUCCESS"
        }
        
        # Verify ISO integrity (optional)
        if ($VerifyISO -and (Test-Path $checksumPath)) {
            Write-Log "Verifying ISO integrity..."
            $storedHash = (Get-Content $checksumPath -Raw -ErrorAction SilentlyContinue).Split(' ')[0]
            $actualHash = (Get-FileHash $OutputPath -Algorithm SHA256).Hash
            if ($storedHash -eq $actualHash) {
                Write-Log "ISO integrity verified" "SUCCESS"
            } else {
                Write-Log "ISO integrity check FAILED - hash mismatch!" "ERROR"
                return $false
            }
        }
        
        return $true
    }
    else {
        Write-Log "ERROR: ISO creation failed" "ERROR"
        return $false
    }
}

# Multi-phase WIM handling functions
function Test-CaptureWIM {
    param([string]$Path)
    
    if (-not $Path) {
        # Auto-detect capture.wim
        $searchPaths = @(
            "C:\GoldISO\Capture.wim"
            "C:\Users\C-Man\GoldISO\Capture.wim"
            "D:\GoldISO\Capture.wim"
            "E:\GoldISO\Capture.wim"
        )
        
        foreach ($testPath in $searchPaths) {
            if (Test-Path $testPath) {
                $Path = $testPath
                break
            }
        }
    }
    
    if ($Path -and (Test-Path $Path)) {
        Write-Log "Found capture WIM: $Path" "SUCCESS"
        return $Path
    }
    
    return $null
}

function Copy-CaptureScripts {
    param([string]$ISODir)
    
    Write-Log "Copying capture/apply scripts to ISO..."
    
    $scriptsDir = Join-Path $ISODir "Scripts"
    if (-not (Test-Path $scriptsDir)) {
        New-Item -ItemType Directory -Path $scriptsDir -Force | Out-Null
    }
    
    $scripts = @(
        Join-Path $script:ProjectRoot "Scripts\Capture-Image.ps1"
        Join-Path $script:ProjectRoot "Scripts\Apply-Image.ps1"
        Join-Path $script:ProjectRoot "Scripts\AuditMode-Continue.ps1"
    )
    
    foreach ($script in $scripts) {
        if (Test-Path $script) {
            Copy-Item $script $scriptsDir -Force
            Write-Log "  Copied: $(Split-Path $script -Leaf)"
        }
        else {
            Write-Log "  Not found: $(Split-Path $script -Leaf)" "WARN"
        }
    }
    
    Write-Log "Capture scripts copied" "SUCCESS"
}

function Copy-AuditScripts {
    param([string]$ISODir)
    
    Write-Log "Copying audit mode scripts to ISO..."
    
    $scriptsDir = Join-Path $ISODir "Scripts"
    if (-not (Test-Path $scriptsDir)) {
        New-Item -ItemType Directory -Path $scriptsDir -Force | Out-Null
    }
    
    $auditScript = Join-Path $script:ProjectRoot "Scripts\AuditMode-Continue.ps1"
    if (Test-Path $auditScript) {
        Copy-Item $auditScript $scriptsDir -Force
        
        # Create shortcut for desktop
        $shortcutDir = Join-Path $ISODir "AuditDesktop"
        New-Item -ItemType Directory -Path $shortcutDir -Force | Out-Null
        
        $WshShell = New-Object -ComObject WScript.Shell
        $shortcut = $WshShell.CreateShortcut("$shortcutDir\Continue to OOBE.lnk")
        $shortcut.TargetPath = "powershell.exe"
        $shortcut.Arguments = "-ExecutionPolicy Bypass -File `"C:\Scripts\AuditMode-Continue.ps1`""
        $shortcut.WorkingDirectory = "C:\Scripts"
        $shortcut.Description = "Continue Windows Setup to OOBE"
        $shortcut.Save()
        
        Write-Log "Audit mode scripts and shortcut created" "SUCCESS"
    }
    else {
        Write-Log "Audit script not found" "WARN"
    }
}

function Get-WIMSourcePath {
    param(
        [string]$Mode,
        [string]$StandardWIM,
        [string]$CaptureWIM
    )
    
    switch ($Mode) {
        "Standard" {
            Write-Log "Build mode: Standard (using install.wim)"
            return $StandardWIM
        }
        "Capture" {
            if ($CaptureWIM -and (Test-Path $CaptureWIM)) {
                Write-Log "Build mode: Capture (using capture.wim)"
                return $CaptureWIM
            }
            else {
                Write-Log "Capture WIM not found, falling back to Standard mode" "WARN"
                return $StandardWIM
            }
        }
        "Audit" {
            Write-Log "Build mode: Audit (using install.wim with audit scripts)"
            return $StandardWIM
        }
        default {
            return $StandardWIM
        }
    }
}

# ==========================================
# MAIN EXECUTION
# ==========================================

function Invoke-EmergencyDismount {
    Write-Log "Emergency cleanup: Checking for mounted images..." "WARN"
    
    # 1. Standard PowerShell Unmount
    $mounts = Get-WindowsImage -Mounted -ErrorAction SilentlyContinue
    foreach ($mount in $mounts) {
        Write-Log "  Forcefully unmounting: $($mount.MountPath)" "WARN"
        try {
            Dismount-WindowsImage -Path $mount.MountPath -Discard -ErrorAction Stop | Out-Null
            Write-Log "    Unmounted successfully" "SUCCESS"
        }
        catch {
            Write-Log "    PS Unmount failed: $_. Attempting DISM legacy cleanup..." "WARN"
            $null = dism /Cleanup-Wim 2>&1
        }
    }
    
    # 2. Cleanup orphaned mount directories
    Invoke-PowerCleanup -Path "C:\Mnt"
    Invoke-PowerCleanup -Path "C:\Mount"
}

function Invoke-PowerCleanup {
    param([string]$Path)
    if (-not (Test-Path $Path)) { return }
    Write-Log "  PowerCleanup: Removing $Path..." "INFO"
    $maxRetries = 3
    for ($i = 0; $i -lt $maxRetries; $i++) {
        try {
            Remove-Item $Path -Recurse -Force -ErrorAction Stop
            return
        } catch {
            Write-Log "    Retry $($i+1)/${maxRetries}: Path locked. Waiting 2s..." "WARN"
            Start-Sleep -Seconds 2
        }
    }
    Write-Log "    Failed to remove $Path after $maxRetries retries." "ERROR"
}

function Remove-AppxPackagesByBlacklist {
    param([string]$MountPath)
    $blacklistPath = Join-Path $script:ProjectRoot "Config\debloat-list.json"
    if (-not (Test-Path $blacklistPath)) { return }

    Write-Log "Removing blacklisted Appx packages..."
    $debloatConfig = Get-Content $blacklistPath -Raw | ConvertFrom-Json
    $blacklist = $debloatConfig.blacklist
    if (-not $blacklist) { return }

    $provisioned = Get-AppxProvisionedPackage -Path $MountPath

    foreach ($app in $blacklist) {
        $match = $provisioned | Where-Object { $_.DisplayName -eq $app }
        if ($match) {
            Write-Log "  Removing: $app"
            Remove-AppxProvisionedPackage -Path $MountPath -PackageName $match.PackageName -ErrorAction SilentlyContinue | Out-Null
        }
    }
}

function Get-TargetNVMeDisk {
    Write-Log "Detecting primary NVMe disk ID..."
    $disks = Get-PhysicalDisk | Where-Object { $_.BusType -eq 'NVMe' -and $_.OperationalStatus -eq 'Online' } | Sort-Object Size
    if (-not $disks) {
        Write-Log "No NVMe disk found! Falling back to Disk 2 (likely to fail)." "ERROR"
        return 2
    }
    $target = $disks[0]
    Write-Log "Found NVMe: $($target.FriendlyName) (DeviceId: $($target.DeviceId))" "SUCCESS"
    return $target.DeviceId
}

# ---------------------------------------------------------------------------
# PHYSICAL USB DEPLOYMENT (V3.0)
# ---------------------------------------------------------------------------
function Initialize-UsbDisk {
    param([string]$DiskId, [string]$SourceISO)
    
    Write-Log "=========================================="
    Write-Log "PHYSICAL FLASH: Preparing USB Disk $DiskId"
    Write-Log "=========================================="
    
    $disk = Get-Disk -Number $DiskId -ErrorAction SilentlyContinue
    if (-not $disk) { throw "Disk $DiskId not found" }
    
    Write-Log "  Disk: $($disk.FriendlyName) ($([math]::Round($disk.Size / 1GB, 1)) GB)"
    Write-Log "  BusType: $($disk.BusType)"
    
    if ($disk.BusType -ne 'USB') {
        throw "Disk $DiskId is NOT a USB device. Aborting for safety."
    }

    Write-Log "  Clearing disk and initializing GPT..."
    Clear-Disk -Number $DiskId -RemoveData -RemoveOEM -Confirm:$false
    Initialize-Disk -Number $DiskId -PartitionStyle GPT -ErrorAction Stop

    Write-Log "  Creating UEFI Boot Partition (FAT32, 1GB)..."
    $bootPart = New-Partition -DiskNumber $DiskId -Size 1GB -AssignDriveLetter | Format-Volume -FileSystem FAT32 -NewFileSystemLabel "G-BOOT"
    $bootDrive = "$($bootPart.DriveLetter):"

    Write-Log "  Creating Data Partition (NTFS, Remainder)..."
    $dataPart = New-Partition -DiskNumber $DiskId -UseMaximumSize -AssignDriveLetter | Format-Volume -FileSystem NTFS -NewFileSystemLabel "G-DATA"
    $dataDrive = "$($dataPart.DriveLetter):"

    Write-Log "  Mounting Source ISO..."
    $isoDrive = Mount-SourceISO -ISOPath $SourceISO -MountPath "NONE"
    
    Write-Log "  Deploying boot files to $bootDrive..."
    robocopy "${isoDrive}\" "$bootDrive\" /E /R:3 /W:5 /XF install.swm install.wim install.esd /XD sources
    New-Item -ItemType Directory -Path "$bootDrive\sources" -Force | Out-Null
    Copy-Item "${isoDrive}\sources\boot.wim" "$bootDrive\sources\boot.wim" -Force

    Write-Log "  Deploying full image to $dataDrive..."
    robocopy "${isoDrive}\" "$dataDrive\" /E /R:3 /W:5
    
    Write-Log "Unmounting ISO..."
    Dismount-DiskImage -ImagePath $SourceISO | Out-Null
    
    Write-Log "USB Flash Complete! You can now boot from this drive." "SUCCESS"
}

# ---------------------------------------------------------------------------
# VIRTUAL SANDBOX (V3.0)
# ---------------------------------------------------------------------------
function Start-SandboxVM {
    param([string]$ISOPath)
    Write-Log "Launching Hyper-V Sandbox for ISO verification..."
    $vmName = "GoldISO_Sandbox_$(Get-Date -Format 'HHmm')"
    
    try {
        New-VM -Name $vmName -MemoryStartupBytes 4GB -Generation 2 -NewVHDPath "$env:TEMP\$vmName.vhdx" -NewVHDSizeBytes 60GB | Out-Null
        Set-VMMemory -VMName $vmName -DynamicMemoryEnabled $false
        Add-VMDvdDrive -VMName $vmName -Path $ISOPath
        Set-VMFirmware -VMName $vmName -FirstBootDevice (Get-VMDvdDrive -VMName $vmName)
        Start-VM -Name $vmName
        Write-Log "Sandbox VM '$vmName' is running." "SUCCESS"
    } catch {
        Write-Log "Failed to launch Sandbox: $_" "ERROR"
    }
}

try {
    Write-Log "=========================================="
    Write-Log "GoldISO Build System - Overhaul Edition"
    Write-Log "=========================================="
    
    # Initialize build progress tracking
    Start-BuildProgress
    Write-BuildProgress -Phase "Starting Build" -PhaseNumber 0 -TotalPhases 10
    
    # Initialize checkpoint system
    $resuming = Initialize-Checkpoint -CheckpointPath $CheckpointPath
    if ($resuming) {
        Write-Log "Resuming build from checkpoint" "INFO"
    }
    
    # Resolve source paths early
    $sourceISO = Join-Path $script:ProjectRoot "Win11-25H2x64v2.iso"
    $answerFilePlaceholder = Join-Path $script:ProjectRoot "Config\autounattend.xml"
    if (-not (Test-Path $answerFilePlaceholder)) {
        $answerFilePlaceholder = Join-Path $script:ProjectRoot "autounattend.xml"
    }

    # Modular Answer File System (V3.2)
    if ($UseModular) {
        if (-not $ProfilePath) {
            $ProfilePath = Join-Path $script:ProjectRoot "Config\profile.json"
        }
        if (Test-Path $ProfilePath) {
            Write-Log "Using Modular Answer File System with profile: $ProfilePath" "INFO"
            $buildAutounattend = Join-Path $script:ProjectRoot "Scripts\Build\Build-Autounattend.ps1"
            if (Test-Path $buildAutounattend) {
                $generatedXml = Join-Path $WorkingDir "autounattend-generated.xml"
                Write-Log "Generating autounattend.xml from profile..." "INFO"
                try {
                    & $buildAutounattend -ProfilePath $ProfilePath -OutputPath $generatedXml -DiskLayout $DiskLayout -ErrorAction Stop
                    if (Test-Path $generatedXml) {
                        $answerFilePlaceholder = $generatedXml
                        Write-Log "Generated modular autounattend.xml" "SUCCESS"
                    }
                } catch {
                    Write-Log "Failed to generate modular XML, falling back to legacy: $($_.Exception.Message)" "WARN"
                    $UseModular = $false
                }
            } else {
                Write-Log "Build-Autounattend.ps1 not found, falling back to legacy XML" "WARN"
                $UseModular = $false
            }
        } else {
            Write-Log "Profile not found at $ProfilePath, falling back to legacy XML" "WARN"
            $UseModular = $false
        }
    }

    if (-not $UseModular) {
        # Legacy: Config/ is canonical - keep root copy in sync
        Copy-Item -Path $answerFilePlaceholder -Destination (Join-Path $script:ProjectRoot "autounattend.xml") -Force
        Write-Log "Synced Config/autounattend.xml -> root (legacy mode)" "SUCCESS"
    }

    # Dynamic Disk Detection (Phase 3)
    $targetDiskID = Get-TargetNVMeDisk
    Write-Log "Target Disk ID: $targetDiskID"

    # Phase: Initialize
    if (-not (Test-PhaseComplete "Initialize")) {
        $phaseStart = Get-Date
        Test-GoldISOAdmin -ExitIfNotAdmin
        if (-not $SkipDependencyDownload) {
            Invoke-Dependencies -ProjectRoot $script:ProjectRoot -SourceISOPath $sourceISO -ManifestPath (Join-Path $script:ProjectRoot "Drivers\download-manifest.json")
        }
        Test-Prerequisites
        Save-Checkpoint -Phase "Initialize" -Duration ((Get-Date) - $phaseStart)
    } else {
        Write-Log "Phase Initialize already completed, skipping" "INFO"
    }

    # Phase: CopyISO
    if (-not (Test-PhaseComplete "CopyISO")) {
        $phaseStart = Get-Date
        New-WorkingDirectory -Path $WorkingDir
        $workingISO = Copy-WorkingISO -SourceISO $sourceISO -WorkingDir $WorkingDir
        $isoDrive = Mount-SourceISO -ISOPath $workingISO -MountPath $MountDir
        Save-Checkpoint -Phase "CopyISO" -Duration ((Get-Date) - $phaseStart)
    } else {
        Write-Log "Phase CopyISO already completed, skipping" "INFO"
        $workingISO = Join-Path $WorkingDir "*.iso" | Get-Item | Select-Object -First 1
        $isoDrive = Mount-SourceISO -ISOPath $workingISO -MountPath $MountDir
    }
    $isoContentsDir = Join-Path $WorkingDir "ISO"
    Copy-ISOContents -SourceDrive $isoDrive -DestDir $isoContentsDir
    Dismount-ISO -ISOPath $workingISO

    # Prepare Answer File with Dynamic Disk ID
    $answerFile = Join-Path $WorkingDir "autounattend.xml"
    Write-Log "Injecting target disk ID $targetDiskID into answer file..."
    $xmlContent = Get-Content $answerFilePlaceholder -Raw
    $xmlContent = $xmlContent -replace '<DiskID>\d+</DiskID>', "<DiskID>$targetDiskID</DiskID>"
    $xmlContent | Set-Content $answerFile -Encoding UTF8

    $standardWIM = Join-Path $isoContentsDir "sources\install.wim"
    
    # Phase 3: Multi-Edition Support (V3.0)
    # We query available editions and select the one from the manifest or default to 6
    $imageInfo = Get-WindowsImage -ImagePath $standardWIM
    $targetIndex = 6 # Default to Win11 Pro in standard retail ISOs
    Write-Log "Available Editions in WIM:"
    foreach ($img in $imageInfo) {
        Write-Log "  [$($img.ImageIndex)] $($img.ImageName)"
    }
    
    $wimPath = Get-WIMSourcePath -Mode $BuildMode -StandardWIM $standardWIM -CaptureWIM $null
    Write-BuildProgress -Phase "Mount WIM" -PhaseNumber 3 -TotalPhases 10

    # Phase: MountWIM and Servicing
    if (-not (Test-PhaseComplete "MountWIM")) {
        $phaseStart = Get-Date
        Mount-WIM -WIMPath $wimPath -MountPath $MountDir -Index $targetIndex
        Save-Checkpoint -Phase "MountWIM" -Duration ((Get-Date) - $phaseStart)
    } else {
        Write-Log "Phase MountWIM already completed, skipping" "INFO"
    }
    
    # Phase: InjectDrivers
    if (-not (Test-PhaseComplete "InjectDrivers")) {
        $phaseStart = Get-Date
        if (-not $SkipDriverInjection) {
            if ($ParallelDrivers) {
                Add-DriversParallel -MountPath $MountDir -DriversDir (Join-Path $script:ProjectRoot "Drivers")
            } else {
                Add-Drivers -MountPath $MountDir -DriversDir (Join-Path $script:ProjectRoot "Drivers")
            }
        }
        Write-BuildProgress -Phase "Driver Injection" -PhaseNumber 4 -TotalPhases 10
        Save-Checkpoint -Phase "InjectDrivers" -Duration ((Get-Date) - $phaseStart)
    } else {
        Write-Log "Phase InjectDrivers already completed, skipping" "INFO"
    }
    
    # Phase: InjectPackages
    if (-not (Test-PhaseComplete "InjectPackages")) {
        $phaseStart = Get-Date
        if (-not $SkipPackageInjection) { Add-Packages -MountPath $MountDir -PackagesDir (Join-Path $script:ProjectRoot "Packages") }
        Write-BuildProgress -Phase "Package Injection" -PhaseNumber 5 -TotalPhases 10
        Save-Checkpoint -Phase "InjectPackages" -Duration ((Get-Date) - $phaseStart)
    } else {
        Write-Log "Phase InjectPackages already completed, skipping" "INFO"
    }
    
    # Phase: Debloating
    if (-not (Test-PhaseComplete "Debloat")) {
        $phaseStart = Get-Date
        Invoke-OfflineDebloat -MountPath $MountDir -ConfigJson $DebloatListJson
        Write-BuildProgress -Phase "Debloating" -PhaseNumber 6 -TotalPhases 10
        Save-Checkpoint -Phase "Debloat" -Duration ((Get-Date) - $phaseStart)
    } else {
        Write-Log "Phase Debloat already completed, skipping" "INFO"
    }
    
    # Phase: RegistryHardening
    if (-not (Test-PhaseComplete "RegistryHardening")) {
        $phaseStart = Get-Date
        Invoke-OfflineDriverStore -MountPath $MountDir -ConfigJson $DriverQueueJson
        Invoke-OfflineRegistryHardening -MountPath $MountDir -RegistryJson $RegistryQueueJson
        Invoke-OfflineServiceConfig -MountPath $MountDir -ServiceConfigJson $ServiceConfigJson
        Invoke-FsutilOptimizations -MountPath $MountDir
        Save-Checkpoint -Phase "RegistryHardening" -Duration ((Get-Date) - $phaseStart)
    } else {
        Write-Log "Phase RegistryHardening already completed, skipping" "INFO"
    }


    # Phase 4: Post-Install Ecosystem Injection (V3.0)
    Write-Log "Injecting GoldISO Target-Side App and Themes..."
    $appPath = Join-Path $MountDir "ProgramData\GoldISO"
    New-Item -ItemType Directory -Path $appPath -Force | Out-Null
    Copy-Item (Join-Path $script:ProjectRoot "Scripts\GoldISO-App.ps1") (Join-Path $appPath "GoldISO-App.ps1") -Force
    Copy-Item (Join-Path $script:ProjectRoot "Config\build-manifest.json") (Join-Path $appPath "Config\build-manifest.json") -Force
    
    # Inject Theme Assets
    $wallpapersPath = Join-Path $MountDir "Windows\Web\Wallpaper\GoldISO"
    New-Item -ItemType Directory -Path $wallpapersPath -Force | Out-Null
    # (Assuming user will put wallpapers in ProjectRoot\Assets\Wallpapers)
    $assetSrc = Join-Path $script:ProjectRoot "Assets"
    if (Test-Path $assetSrc) {
        Copy-Item (Join-Path $assetSrc "Wallpapers\*") $wallpapersPath -Recurse -Force
    }
    
    # Phase: Optimize
    if (-not (Test-PhaseComplete "Optimize")) {
        $phaseStart = Get-Date
        Optimize-Image -MountPath $MountDir
        Dismount-WIMImage -MountPath $MountDir -Save
        Save-Checkpoint -Phase "Optimize" -Duration ((Get-Date) - $phaseStart)
    } else {
        Write-Log "Phase Optimize already completed, skipping" "INFO"
    }

    # Phase: ExportWIM
    if (-not (Test-PhaseComplete "ExportWIM")) {
        $phaseStart = Get-Date
        $singleIndexWIM = Join-Path $WorkingDir "install-single-index.wim"
        Export-SingleIndexWIM -SourceWIMPath $wimPath -SourceIndex 6 -DestWIMPath $singleIndexWIM -Compression Maximum
        $finalWIM = Join-Path $isoContentsDir "sources\install.wim"
        Export-SingleIndexWIM -SourceWIMPath $singleIndexWIM -SourceIndex 1 -DestWIMPath $finalWIM -Compression Maximum

        Copy-AnswerFile -ISODir $isoContentsDir -AnswerFile $answerFile
        if (-not $SkipPortableApps) { Copy-PortableApps -ISODir $isoContentsDir -SourceDir (Join-Path $script:ProjectRoot "Applications\Portableapps") }
        
        $isoCreated = Build-ISOImage -ISODir $isoContentsDir -OutputPath $OutputISO
        Save-Checkpoint -Phase "ExportWIM" -Duration ((Get-Date) - $phaseStart)
    } else {
        Write-Log "Phase ExportWIM already completed, skipping" "INFO"
        $isoCreated = $true
    }
    
    Write-BuildProgress -Phase "BuildISO" -PhaseNumber 10 -TotalPhases 10

    # Phase 2: Ventoy Plugin Support (V3.0)
    if ($SyncVentoy) {
        Write-Log "Generating Ventoy Plugin structure..."
        $ventoyDir = Join-Path $script:ProjectRoot "Ventoy"
        New-Item -ItemType Directory -Path (Join-Path $ventoyDir "script") -Force | Out-Null
        $vJson = @{
            control = @(
                @{ vtoy_auto_install = @( @{ image = "/$([System.IO.Path]::GetFileName($OutputISO))"; template = "/ventoy/script/autounattend.xml" } ) }
            )
        }
        $vJson | ConvertTo-Json -Depth 10 | Set-Content (Join-Path $ventoyDir "ventoy.json") -Force
        Copy-Item (Join-Path $script:ProjectRoot "Config\autounattend.xml") (Join-Path $ventoyDir "script\autounattend.xml") -Force
        Write-Log "Ventoy configuration ready at $ventoyDir" "SUCCESS"
    }
}
catch {
    Write-Log "CRITICAL BUILD ERROR: $_" "ERROR"
    Write-Log "Stack trace: $($_.ScriptStackTrace)" "ERROR"
    $isoCreated = $false
}
finally {
    Invoke-EmergencyDismount
    if ($FlashToUsb) {
        Initialize-UsbDisk -DiskId $TargetUsbDisk -SourceISO $SourceISOPath
        exit 0
    }
    if (-not $NoCleanup) {
        Invoke-PowerCleanup -Path $WorkingDir
    }
}

Write-Log "=========================================="
if ($isoCreated) {
    Write-Log "BUILD COMPLETED SUCCESSFULLY" "SUCCESS"
} else {
    Write-Log "BUILD FAILED" "ERROR"
}
Write-Log "=========================================="