#Requires -Version 5.1
#Requires -RunAsAdministrator

Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase

# Load common module
$scriptDir = $PSScriptRoot
$commonModule = Join-Path $scriptDir "Modules\GoldISO-Common.psm1"
if (Test-Path $commonModule) { Import-Module $commonModule -Force }

# Load XAML
$xamlFile = Join-Path $scriptDir "GoldISO-GUI.xaml"
[xml]$xaml = Get-Content $xamlFile
$reader = New-Object System.Xml.XmlNodeReader $xaml
$Window = [Windows.Markup.XamlReader]::Load($reader)

# Map UI Elements
$xaml.SelectNodes("//*[@Name]") | ForEach-Object {
    Set-Variable -Name ("UI_" + $_.Name) -Value $Window.FindName($_.Name) -Scope Script
}

# --- NAVIGATION LOGIC ---
$script:Pages = @("PageConfig", "PageTune", "PageApps", "PageBuild", "PageMain", "PageDev")
function Switch-Page {
    param($TargetPageName)
    foreach ($p in $script:Pages) {
        $uiPage = Get-Variable ("UI_" + $p) -ValueOnly
        if ($p -eq $TargetPageName) {
            $uiPage.Visibility = "Visible"
        } else {
            $uiPage.Visibility = "Collapsed"
        }
    }
}

# Wiring Nav Buttons
$UI_NavConfig.Add_Checked({ Switch-Page "PageConfig" })
$UI_NavTune.Add_Checked({ Switch-Page "PageTune" })
$UI_NavApps.Add_Checked({ Switch-Page "PageApps" })
$UI_NavBuild.Add_Checked({ 
    Switch-Page "PageBuild"
    Update-UsbDrives
})
$UI_NavMain.Add_Checked({ Switch-Page "PageMain" })
$UI_NavDev.Add_Checked({ Switch-Page "PageDev" })

# --- USB DEPLOYMENT LOGIC (V3.0) ---
function Update-UsbDrives {
    try {
        $drives = Get-Disk | Where-Object { $_.BusType -eq 'USB' -and $_.OperationalStatus -eq 'Online' }
        $UI_UsbDriveList.ItemsSource = $drives | ForEach-Object { 
            "Disk $($_.Number): $($_.FriendlyName) ($([math]::Round($_.Size / 1GB, 1)) GB)" 
        }
        if ($drives.Count -gt 0) { $UI_UsbDriveList.SelectedIndex = 0 }
    } catch {
        Write-GuiLog "Failed to query USB disks: $_" "ERROR"
    }
}

$UI_RefreshUsb.Add_Click({ Update-UsbDrives })

$UI_ModeUsb.Add_Checked({ $UI_UsbSelectionArea.Visibility = "Visible" })
$UI_ModeIso.Add_Checked({ $UI_UsbSelectionArea.Visibility = "Collapsed" })

# --- LOGGING REDIRECTION ---
function Write-ToConsole {
    param($Message, $Level = "INFO")
    $Window.Dispatcher.Invoke({
        $color = switch ($Level) {
            "ERROR" { [Windows.Media.Brushes]::Red }
            "WARN" { [Windows.Media.Brushes]::Yellow }
            "SUCCESS" { [Windows.Media.Brushes]::LimeGreen }
            "INFO" { [Windows.Media.Brushes]::Cyan }
            default { [Windows.Media.Brushes]::LightGray }
        }
        $tr = New-Object System.Windows.Documents.TextRange($UI_ConsoleOutput.Document.ContentEnd, $UI_ConsoleOutput.Document.ContentEnd)
        $tr.Text = "[$Level] $Message`r"
        $tr.ApplyPropertyValue([System.Windows.Documents.TextElement]::ForegroundProperty, $color)
        $UI_ConsoleOutput.ScrollToEnd()
    })
}

function Write-GuiLog {
    param([string]$Message, [string]$Level = "INFO")
    Write-Log -Message $Message -Level $Level
    Write-ToConsole -Message $Message -Level $Level
}

# --- DATA BINDING ---
$script:AppCollection = New-Object System.Collections.ObjectModel.ObservableCollection[PSObject]
$UI_AppList.ItemsSource = $script:AppCollection

function Import-Apps {
    $packagePath = "C:\ProgramData\GoldISO\Config\winget-packages.json"
    if (-not (Test-Path $packagePath)) { return }
    try {
        $json = Get-Content $packagePath -Raw | ConvertFrom-Json
        $script:AppCollection.Clear()
        foreach ($source in $json.Sources) {
            foreach ($pkg in $source.Packages) {
                $script:AppCollection.Add([PSCustomObject]@{
                    Name = $pkg.PackageIdentifier.Split('.')[-1]
                    Id = $pkg.PackageIdentifier
                    IsSelected = [bool]($pkg.Optional -eq $false) 
                })
            }
        }
    } catch { Write-GuiLog "Failed to load apps: $_" "ERROR" }
}

function Save-CurrentManifest {
    $path = $UI_ManifestEditor.Tag
    if ($path -and $UI_ManifestEditor.Text) {
        try {
            $UI_ManifestEditor.Text | Set-Content $path -Force
            Write-GuiLog "Saved changes to $(Split-Path $path -Leaf)" "SUCCESS"
            if ($path -match "build-manifest.json") { Import-ConfigFromFile $path }
        } catch { Write-GuiLog "Failed to save: $_" "ERROR" }
    }
}

function Import-ConfigFromFile {
    param($Path)
    if (Test-Path $Path) {
        $script:Config = Get-Content $Path -Raw | ConvertFrom-Json
        # Populate UI
        $UI_CfgGamingDrive.SelectedItem = $script:Config.drives.gaming
        $UI_CfgAppsDrive.SelectedItem = $script:Config.drives.apps
        $UI_CfgMediaDrive.SelectedItem = $script:Config.drives.media
        $UI_CfgAppsSize.Value = $script:Config.partitions.apps_size_gb
        $UI_CfgScratchSize.Value = $script:Config.partitions.scratch_size_gb
        $UI_CfgWipeAll.IsChecked = [bool](-not $script:Config.target.wipe_all_secondary)
        $UI_CfgCompName.Text = $script:Config.identity.computer_name_prefix
        $UI_CfgOwner.Text = $script:Config.identity.owner_name
        $UI_CfgAutoStartApp.IsChecked = [bool]$script:Config.identity.auto_start_app
        
        # Performance/Tuning Page
        $UI_CfgGameMode.IsChecked = $script:Config.optimizations.game_mode
        $UI_CfgHAGS.IsChecked = $script:Config.optimizations.hags
        $UI_CfgNoHPET.IsChecked = $script:Config.optimizations.hpet_disabled
        $UI_CfgMSIMode.IsChecked = $script:Config.optimizations.msi_mode_enabled
        
        # Network
        $UI_CfgDnsPri.Text = $script:Config.network.dns_primary
        $UI_CfgNoIPv6.IsChecked = $script:Config.network.disable_ipv6
        $UI_CfgTCPWin.IsChecked = $script:Config.network.tcp_window_scaling
        
        # Privacy
        $UI_CfgNoTelemetry.IsChecked = $script:Config.optimizations.telemetry_disabled
        $UI_CfgNoDiag.IsChecked = $script:Config.privacy.disable_diag_data
        $UI_CfgNoLocation.IsChecked = $script:Config.privacy.disable_location
        $UI_CfgDefender.IsChecked = $script:Config.optimizations.win_defender_enabled
        
        # Visuals
        $UI_CfgAcrylic.IsChecked = $script:Config.visuals.acrylic_enabled
        $UI_CfgNoStartSound.IsChecked = $script:Config.visuals.disable_startup_sound
        $UI_CfgFontSmooth.IsChecked = $script:Config.visuals.font_smoothing
    }
}

# --- HANDLERS ---
$UI_BrowseSource.Add_Click({
    $fd = New-Object Microsoft.Win32.OpenFileDialog
    if ($fd.ShowDialog()) { $UI_SourcePath.Text = $fd.FileName }
})

$UI_LoadManifest.Add_Click({
    $path = "C:\ProgramData\GoldISO\Config\build-manifest.json"
    $UI_ManifestEditor.Tag = $path
    $UI_ManifestEditor.Text = Get-Content $path -Raw
})

$UI_SaveConfig.Add_Click({
    if ($script:Config) {
        $script:Config.drives.gaming = $UI_CfgGamingDrive.SelectedItem
        $script:Config.drives.apps = $UI_CfgAppsDrive.SelectedItem
        $script:Config.drives.media = $UI_CfgMediaDrive.SelectedItem
        $script:Config.partitions.apps_size_gb = [int]$UI_CfgAppsSize.Value
        $script:Config.partitions.scratch_size_gb = [int]$UI_CfgScratchSize.Value
        $script:Config.target.wipe_all_secondary = [bool](-not $UI_CfgWipeAll.IsChecked)
        $script:Config.identity.computer_name_prefix = $UI_CfgCompName.Text
        $script:Config.identity.owner_name = $UI_CfgOwner.Text
        $script:Config.identity.auto_start_app = [bool]$UI_CfgAutoStartApp.IsChecked
        $script:Config.optimizations.game_mode = [bool]$UI_CfgGameMode.IsChecked
        $script:Config.optimizations.hags = [bool]$UI_CfgHAGS.IsChecked
        $script:Config.optimizations.hpet_disabled = [bool]$UI_CfgNoHPET.IsChecked
        $script:Config.optimizations.msi_mode_enabled = [bool]$UI_CfgMSIMode.IsChecked
        $script:Config.network.dns_primary = $UI_CfgDnsPri.Text
        $script:Config.network.disable_ipv6 = [bool]$UI_CfgNoIPv6.IsChecked
        $script:Config.network.tcp_window_scaling = [bool]$UI_CfgTCPWin.IsChecked
        $script:Config.optimizations.telemetry_disabled = [bool]$UI_CfgNoTelemetry.IsChecked
        $script:Config.privacy.disable_diag_data = [bool]$UI_CfgNoDiag.IsChecked
        $script:Config.privacy.disable_location = [bool]$UI_CfgNoLocation.IsChecked
        $script:Config.optimizations.win_defender_enabled = [bool]$UI_CfgDefender.IsChecked
        $script:Config.visuals.acrylic_enabled = [bool]$UI_CfgAcrylic.IsChecked
        $script:Config.visuals.disable_startup_sound = [bool]$UI_CfgNoStartSound.IsChecked
        $script:Config.visuals.font_smoothing = [bool]$UI_CfgFontSmooth.IsChecked

        $path = "C:\ProgramData\GoldISO\Config\build-manifest.json"
        $script:Config | ConvertTo-Json -Depth 10 | Set-Content $path -Force
        Write-GuiLog "V2.0 Configuration Saved." "SUCCESS"
    }
})

# --- MAINTENANCE HANDLERS (V3.0) ---
$UI_ExportProject.Add_Click({
    $sd = New-Object Microsoft.Win32.SaveFileDialog
    $sd.Filter = "GoldISO Package (*.goldiso)|*.goldiso"
    $sd.FileName = "GoldISO-Export-$(Get-Date -Format 'yyyyMMdd').goldiso"
    if ($sd.ShowDialog()) {
        try {
            $exportPath = $sd.FileName
            $tempDir = Join-Path $env:TEMP "GoldISO_Export"
            if (Test-Path $tempDir) { Remove-Item $tempDir -Recurse -Force }
            New-Item -ItemType Directory -Path $tempDir -Force | Out-Null
            
            # Copy items to export
            $projectRoot = Split-Path $script:ProjectRoot -Parent
            $items = @("Config", "Drivers", "Applications", "Scripts")
            foreach ($item in $items) {
                $src = Join-Path $projectRoot $item
                if (Test-Path $src) {
                    Copy-Item $src (Join-Path $tempDir $item) -Recurse -Force
                }
            }
            
            if (Test-Path $exportPath) { Remove-Item $exportPath -Force }
            Compress-Archive -Path "$tempDir\*" -DestinationPath $exportPath -Force
            Write-GuiLog "Project exported successfully to $exportPath" "SUCCESS"
        } catch {
            Write-GuiLog "Failed to export project: $_" "ERROR"
        }
    }
})

$UI_BackupConfig.Add_Click({
    $path = "C:\ProgramData\GoldISO\Backups"
    if (-not (Test-Path $path)) { New-Item -ItemType Directory -Path $path -Force }
    $stamp = Get-Date -Format "yyyyMMdd-HHmmss"
    $backupFile = Join-Path $path "Config-Backup-$stamp.zip"
    Compress-Archive -Path "C:\ProgramData\GoldISO\Config\*" -DestinationPath $backupFile
    Write-GuiLog "Config backup created: $backupFile" "SUCCESS"
})

$UI_ImportProject.Add_Click({
    $fd = New-Object Microsoft.Win32.OpenFileDialog
    $fd.Filter = "GoldISO Package (*.goldiso)|*.goldiso"
    if ($fd.ShowDialog()) {
        try {
            $importPath = $fd.FileName
            $projectRoot = Split-Path $script:ProjectRoot -Parent
            Write-GuiLog "Importing project package: $(Split-Path $importPath -Leaf)..." "INFO"
            
            # Extract and overwrite
            Expand-Archive -Path $importPath -DestinationPath $projectRoot -Force
            Write-GuiLog "Project successfully imported and restored." "SUCCESS"
            
            # Reload current manifest to reflect changes
            Import-ConfigFromFile "C:\ProgramData\GoldISO\Config\build-manifest.json"
        } catch {
            Write-GuiLog "Failed to import project: $_" "ERROR"
        }
    }
})

$UI_RestoreConfig.Add_Click({
    $fd = New-Object Microsoft.Win32.OpenFileDialog
    $fd.InitialDirectory = "C:\ProgramData\GoldISO\Backups"
    $fd.Filter = "Backup Files (*.zip)|*.zip"
    if ($fd.ShowDialog()) {
        try {
            Expand-Archive -Path $fd.FileName -DestinationPath "C:\ProgramData\GoldISO\Config" -Force
            Import-ConfigFromFile "C:\ProgramData\GoldISO\Config\build-manifest.json"
            Write-GuiLog "Configuration restored from backup." "SUCCESS"
        } catch {
            Write-GuiLog "Restore failed: $_" "ERROR"
        }
    }
})

$UI_ImportWIM.Add_Click({
    $fd = New-Object Microsoft.Win32.OpenFileDialog
    $fd.Filter = "Windows Image Files (*.wim)|*.wim"
    if ($fd.ShowDialog()) {
        try {
            $dest = Join-Path $script:ProjectRoot "Packages\import-$(Split-Path $fd.FileName -Leaf)"
            Copy-Item $fd.FileName $dest -Force
            
            # Metadata Extraction (V3.1 Professional)
            $images = Get-WindowsImage -ImagePath $dest
            Write-GuiLog "WIM Metadata Extracted for $(Split-Path $dest -Leaf):" "INFO"
            foreach ($img in $images) {
                Write-GuiLog "  Index [$($img.ImageIndex)]: $($img.ImageName) ($($img.ImageEditionId))" "INFO"
            }
            Write-GuiLog "WIM successfully imported to project packages." "SUCCESS"
        } catch {
            Write-GuiLog "WIM Import/Metadata failed: $_" "ERROR"
        }
    }
})

$UI_TestInVM.Add_Click({
    $iso = $UI_SourcePath.Text
    if (Test-Path $iso) {
        Write-GuiLog "Initializing Hyper-V Sandbox..." "INFO"
        Start-ThreadJob -ScriptBlock {
            param($scriptPath, $isoPath)
            $win = [System.Windows.Application]::Current.Windows | Where-Object { $_.Title -match "GoldISO" } | Select-Object -First 1
            $guiLog = { param($m, $l) $win.Dispatcher.Invoke({ $win.FindName("ConsoleOutput").AppendText("[$l] $m`r") }) }
            # Dot-source and call function
            . $scriptPath
            Start-SandboxVM -ISOPath $isoPath
        } -ArgumentList (Join-Path $scriptDir "Build-GoldISO.ps1"), $iso
    }
})

$UI_StartBuild.Add_Click({
    if (-not (Test-Path $UI_SourcePath.Text)) { Write-GuiLog "Missing Source ISO" "ERROR"; return }
    
    $isUsbMode = [bool]$UI_ModeUsb.IsChecked
    if ($isUsbMode -and -not $UI_UsbDriveList.SelectedItem) {
        Write-GuiLog "Please select a target USB disk first." "WARN"
        return
    }

    if ($isUsbMode) {
        $msg = "WARNING: This will PERMANENTLY WIPE the selected USB disk. Proceed?"
        $res = [System.Windows.MessageBox]::Show($msg, "Confirm USB Flash", "YesNo", "Warning")
        if ($res -ne "Yes") { return }
    }

    $UI_StartBuild.IsEnabled = $false
    $targetName = if ($isUsbMode) { "USB: " + $UI_UsbDriveList.SelectedItem } else { "Local ISO" }
    Write-GuiLog "Starting GoldISO V3.0 Build Pipeline -> $targetName" "SUCCESS"
    
    $buildScript = Join-Path $scriptDir "Build-GoldISO.ps1"
    $sourceISO = $UI_SourcePath.Text
    
    Start-ThreadJob -ScriptBlock {
        param($scriptPath, $isoPath, $isUsb, $usbId)
        try {
            $win = [System.Windows.Application]::Current.Windows | Where-Object { $_.Title -match "GoldISO" } | Select-Object -First 1
            $guiLog = { param($m, $l) $win.Dispatcher.Invoke({
                $con = $win.FindName("ConsoleOutput")
                $pb = $win.FindName("GlobalProgress")
                $st = $win.FindName("StatusIndicator")
                $color = switch ($l) { "ERROR" {[Windows.Media.Brushes]::Red} "SUCCESS" {[Windows.Media.Brushes]::LimeGreen} "INFO" {[Windows.Media.Brushes]::Cyan} default {[Windows.Media.Brushes]::White} }
                $tr = New-Object System.Windows.Documents.TextRange($con.Document.ContentEnd, $con.Document.ContentEnd)
                $tr.Text = "[$l] $m`r"; $tr.ApplyPropertyValue([System.Windows.Documents.TextElement]::ForegroundProperty, $color); $con.ScrollToEnd()
                if ($m -match "Flashing") { $pb.Value = 70; $st.Text = "Flashing USB..." }
            })}

            # If USB mode, we might need a separate script or just call Build-GoldISO with a -FlashToUsb flag
            $params = @{
                SourceISOPath = $isoPath
                SkipDependencyDownload = $true
            }
            if ($isUsb) { 
                $params.Add("TargetUsbDisk", $usbId)
                $params.Add("FlashToUsb", $true)
            }
            if ($win.FindName("SyncVentoy").IsChecked) {
                $params.Add("SyncVentoy", $true)
            }

            & $scriptPath @params
            
            &$guiLog "Build Pipeline Complete!" "SUCCESS"
            $win.Dispatcher.Invoke({ $win.FindName("StartBuild").IsEnabled = $true; $win.FindName("GlobalProgress").Value = 100 })
        } catch { &$guiLog "Operation Failed: $_" "ERROR"; $win.Dispatcher.Invoke({ $win.FindName("StartBuild").IsEnabled = $true }) }
    } -ArgumentList $buildScript, $sourceISO, $isUsbMode, ($UI_UsbDriveList.SelectedItem -split ' ')[1]
})

$Window.Add_Loaded({
    $drives = 65..90 | ForEach-Object { [char]$_ }
    $UI_CfgGamingDrive.ItemsSource = $drives; $UI_CfgAppsDrive.ItemsSource = $drives; $UI_CfgMediaDrive.ItemsSource = $drives
    Import-ConfigFromFile "C:\ProgramData\GoldISO\Config\build-manifest.json"
    Import-Apps
    Write-GuiLog "GoldISO V2.0 Control Center Ready." "SUCCESS"
})

$Window.ShowDialog() | Out-Null
