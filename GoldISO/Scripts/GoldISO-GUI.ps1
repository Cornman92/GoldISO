#Requires -Version 5.1
#Requires -RunAsAdministrator

Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase

# Inject WPF Converters
$converterSource = @"
using System;
using System.Windows;
using System.Windows.Data;
using System.Globalization;

namespace GoldISO.Converters {
    public class StartupToVisibilityConverter : IValueConverter {
        public object Convert(object value, Type targetType, object parameter, CultureInfo culture) {
            if (value != null && value.ToString().Contains("Delayed")) return Visibility.Visible;
            return Visibility.Collapsed;
        }
        public object ConvertBack(object value, Type targetType, object parameter, CultureInfo culture) { return null; }
    }

    public class StartupToEnabledConverter : IValueConverter {
        public object Convert(object value, Type targetType, object parameter, CultureInfo culture) {
            if (value != null && value.ToString().Contains("Delayed")) return true;
            return false;
        }
        public object ConvertBack(object value, Type targetType, object parameter, CultureInfo culture) { return null; }
    }
}
"@
Add-Type -TypeDefinition $converterSource -ReferencedAssemblies PresentationFramework, PresentationCore, WindowsBase

# Load common module
$scriptDir = $PSScriptRoot
$commonModule = Join-Path $scriptDir "Modules\GoldISO-Common.psm1"
if (Test-Path $commonModule) { Import-Module $commonModule -Force }

# Initialize Project Root
if (-not $script:ProjectRoot) {
    try {
        $script:ProjectRoot = Get-GoldISORoot
    } catch {
        $script:ProjectRoot = Split-Path $scriptDir -Parent
    }
}

$logPath = Join-Path $script:ProjectRoot "Log\gui-startup.log"
if ($logPath -and -not (Test-Path (Split-Path $logPath))) { 
    New-Item -ItemType Directory -Path (Split-Path $logPath) -Force | Out-Null
}

try {
    # Load XAML
    $xamlFile = Join-Path $scriptDir "GoldISO-GUI.xaml"
    if (-not (Test-Path $xamlFile)) { throw "XAML file not found: $xamlFile" }
    [xml]$xaml = Get-Content $xamlFile
    $reader = New-Object System.Xml.XmlNodeReader $xaml
    $Window = [Windows.Markup.XamlReader]::Load($reader)
    Add-Content $logPath "$(Get-Date): XAML Loaded Successfully"

    # Map UI Elements
    $xaml.SelectNodes("//*[@Name]") | ForEach-Object {
        $name = $_.Name
        $element = $Window.FindName($name)
        if ($element) {
            Set-Variable -Name ("UI_" + $name) -Value $element -Scope Script
        } else {
            if ($name -eq "Window") { $script:UI_Window = $element }
            Add-Content $logPath "$(Get-Date): WARNING: Could not find element named '$name'"
        }
    }
    
    # Register Resources
    $Window.Resources.Add("StartupToVisibilityConverter", [GoldISO.Converters.StartupToVisibilityConverter]::new())
    $Window.Resources.Add("StartupToEnabledConverter", [GoldISO.Converters.StartupToEnabledConverter]::new())
} catch {
    $err = "FATAL ERROR during UI initialization: $_`n$($_.ScriptStackTrace)"
    Add-Content $logPath "$(Get-Date): $err"
    [System.Windows.MessageBox]::Show($err, "GoldISO GUI Error")
    exit 1
}

# --- NAVIGATION LOGIC ---
$script:Pages = @("PageConfig", "PageTune", "PageApps", "PageBuild", "PageMain", "PageDev", "PageServices", "PageDrivers", "PageDebloat", "PageRegistry")

function Set-GoldISOPage {
    param($TargetPageName)
    foreach ($p in $script:Pages) {
        $uiPage = Get-Variable ("UI_" + $p) -ValueOnly
        if ($uiPage) {
            $uiPage.Visibility = if ($p -eq $TargetPageName) { "Visible" } else { "Collapsed" }
        }
    }
}

$UI_NavConfig.Add_Checked({ Set-GoldISOPage "PageConfig" })
$UI_NavTune.Add_Checked({ Set-GoldISOPage "PageTune" })
$UI_NavApps.Add_Checked({ Set-GoldISOPage "PageApps" })
$UI_NavBuild.Add_Checked({ Set-GoldISOPage "PageBuild" })
$UI_NavMain.Add_Checked({ Set-GoldISOPage "PageMain" })
$UI_NavDev.Add_Checked({ Set-GoldISOPage "PageDev" })
$UI_NavServices.Add_Checked({ 
    Set-GoldISOPage "PageServices" 
    Update-ServicesView
})
$UI_NavDrivers.Add_Checked({ Set-GoldISOPage "PageDrivers" })
$UI_NavDebloat.Add_Checked({ 
    Set-GoldISOPage "PageDebloat"
    Update-DebloatListView
})
$UI_NavRegistry.Add_Checked({ Set-GoldISOPage "PageRegistry" })

# --- USB DEPLOYMENT LOGIC ---
$UI_RefreshUsb.Add_Click({
    $UI_UsbDriveList.ItemsSource = Get-Disk | Where-Object { $_.BusType -eq 'USB' } | ForEach-Object { "$($_.Number): $($_.FriendlyName) ($([Math]::Round($_.Size/1GB, 1)) GB)" }
})

$UI_ModeUsb.Add_Checked({ $UI_UsbSelectionArea.Visibility = "Visible" })
$UI_ModeIso.Add_Checked({ $UI_UsbSelectionArea.Visibility = "Collapsed" })

# --- LOGGING UTILITY ---
function Write-GuiLog {
    param($Message, $Level = "INFO")
    $UI_Window.Dispatcher.Invoke({
        $color = switch ($Level) {
            "ERROR"   { [Windows.Media.Brushes]::Red }
            "SUCCESS" { [Windows.Media.Brushes]::LimeGreen }
            "WARN"    { [Windows.Media.Brushes]::Orange }
            "INFO"    { [Windows.Media.Brushes]::Cyan }
            default   { [Windows.Media.Brushes]::White }
        }
        $tr = New-Object System.Windows.Documents.TextRange($UI_ConsoleOutput.Document.ContentEnd, $UI_ConsoleOutput.Document.ContentEnd)
        $tr.Text = "[$Level] $(Get-Date -Format 'HH:mm:ss') - $Message`r"
        $tr.ApplyPropertyValue([System.Windows.Documents.TextElement]::ForegroundProperty, $color)
        $UI_ConsoleOutput.ScrollToEnd()
    })
}

# --- CONFIGURATION ENGINE ---
function Import-ConfigFromFile {
    param($Path)
    if (Test-Path $Path) {
        $script:Config = Get-Content $Path | ConvertFrom-Json
        $UI_CfgCompName.Text = $script:Config.identity.computer_name_prefix
        $UI_CfgOwner.Text = $script:Config.identity.owner_name
        $UI_CfgAppsSize.Value = $script:Config.partitions.apps_size_gb
        $UI_CfgScratchSize.Value = $script:Config.partitions.scratch_size_gb
        $UI_CfgGamingDrive.SelectedItem = $script:Config.drives.gaming
        $UI_CfgAppsDrive.SelectedItem = $script:Config.drives.apps
        $UI_CfgMediaDrive.SelectedItem = $script:Config.drives.media
        $UI_CfgWipeAll.IsChecked = (-not $script:Config.target.wipe_all_secondary)
        $UI_CfgGameMode.IsChecked = $script:Config.optimizations.game_mode
        $UI_CfgHAGS.IsChecked = $script:Config.optimizations.hags
        $UI_CfgNoHPET.IsChecked = $script:Config.optimizations.hpet_disabled
        $UI_CfgMSIMode.IsChecked = $script:Config.optimizations.msi_mode_enabled
        $UI_CfgDnsPri.Text = $script:Config.network.dns_primary
        $UI_CfgNoIPv6.IsChecked = $script:Config.network.disable_ipv6
        $UI_CfgTCPWin.IsChecked = $script:Config.network.tcp_window_scaling
        $UI_CfgNoTelemetry.IsChecked = $script:Config.optimizations.telemetry_disabled
        $UI_CfgNoDiag.IsChecked = $script:Privacy.disable_diag_data
        $UI_CfgNoLocation.IsChecked = $script:Privacy.disable_location
        $UI_CfgDefender.IsChecked = $script:Config.optimizations.win_defender_enabled
        $UI_CfgAcrylic.IsChecked = $script:Config.visuals.acrylic_enabled
        $UI_CfgNoStartSound.IsChecked = $script:Config.visuals.disable_startup_sound
        $UI_CfgFontSmooth.IsChecked = $script:Config.visuals.font_smoothing
    }
}

# --- SERVICES LOGIC (V3.1) ---
$script:ServiceCollection = New-Object System.Collections.ObjectModel.ObservableCollection[PSObject]
$UI_ServiceGrid.ItemsSource = $script:ServiceCollection

function Update-ServicesView {
    $script:ServiceCollection.Clear()
    $svcFile = Join-Path $script:ProjectRoot "Config\services-db.json"
    if (-not (Test-Path $svcFile)) { return }
    $db = Get-Content $svcFile | ConvertFrom-Json
    
    $confFile = "C:\ProgramData\GoldISO\Config\services-config.json"
    $config = if (Test-Path $confFile) { Get-Content $confFile | ConvertFrom-Json } else { @{} }
    $script:ServiceWarningsSuppressed = if ($config._suppressWarning) { $true } else { $false }

    $hasHighRisk = $false
    foreach ($svc in $db) {
        $saved = $config.$($svc.Name)
        if (-not $saved) { $saved = @{ Startup = "Automatic"; DelayS = 120 } }
        
        $riskText = switch($svc.Risk) { 0 {"Low"} 1 {"Moderate"} 2 {"High"} }
        $riskColor = switch($svc.Risk) { 0 {"#88FF88"} 1 {"#FFFF88"} 2 {"#FF8888"} }

        if ($svc.Risk -eq 2 -and ($saved.Startup -match "Delayed" -or $saved.Startup -eq "Disabled")) { $hasHighRisk = $true }

        $script:ServiceCollection.Add([PSCustomObject]@{
            Name = $svc.Name
            DisplayName = $svc.DisplayName
            Description = $svc.Description
            Startup = $saved.Startup
            DelayS = $saved.DelayS
            RiskText = $riskText
            RiskColor = $riskColor
        })
    }

    if ($hasHighRisk -and -not $script:ServiceWarningsSuppressed) {
        Write-GuiLog "DANGER: High-risk service configurations detected (Delayed/Disabled on Critical Services)." "WARN"
    }
}

$UI_SaveServices.Add_Click({
    $settings = @{ "_suppressWarning" = $script:ServiceWarningsSuppressed }
    foreach ($item in $script:ServiceCollection) {
        $settings[$item.Name] = @{ Startup = $item.Startup; DelayS = [int]$item.DelayS }
    }
    $settings | ConvertTo-Json | Set-Content "C:\ProgramData\GoldISO\Config\services-config.json" -Force
    Write-GuiLog "Services configuration saved." "SUCCESS"
})

# --- DRIVER STORE LOGIC (V3.1 Professional) ---
$script:DriverCollection = New-Object System.Collections.ObjectModel.ObservableCollection[PSObject]
$UI_DriverGrid.ItemsSource = $script:DriverCollection

$UI_ScanDrivers.Add_Click({
    if (-not (Test-Path $UI_SourcePath.Text)) { Write-GuiLog "Valid Source ISO required for scan." "WARN"; return }
    Write-GuiLog "Mounting image for driver metadata scan..." "INFO"
    
    Start-ThreadJob -ScriptBlock {
        param($isoPath, $root)
        try {
            $mount = Join-Path $root "Temp\Scan"
            if (-not (Test-Path $mount)) { New-Item -ItemType Directory -Path $mount -Force }
            Mount-WindowsImage -ImagePath $isoPath -Index 1 -Path $mount -ReadOnly
            $drivers = Get-WindowsDriver -Path $mount
            Dismount-WindowsImage -Path $mount -Discard
            return $drivers
        } catch { throw $_ }
    } -ArgumentList $UI_SourcePath.Text, $script:ProjectRoot | Receive-Job -Wait -AutoRemoveJob | ForEach-Object {
        $script:DriverCollection.Add([PSCustomObject]@{
            IsSelected = $false
            PublishedName = $_.PublishedName
            ClassName = $_.ClassName
            ProviderName = $_.ProviderName
            DriverVersion = $_.DriverVersion
        })
    }
})

# --- DEBLOAT LOGIC (V3.1 Professional) ---
$script:DebloatCollection = New-Object System.Collections.ObjectModel.ObservableCollection[PSObject]
$UI_DebloatGrid.ItemsSource = $script:DebloatCollection

$script:RecommendedDebloat = @("Microsoft.XboxApp", "Microsoft.WindowsFeedbackHub", "Microsoft.YourPhone", "Microsoft.ZuneVideo", "Microsoft.SkypeApp", "Microsoft.People")

function Update-DebloatListView {
    if ($script:DebloatCollection.Count -gt 0) { return }
    foreach ($app in $script:RecommendedDebloat) {
        $script:DebloatCollection.Add([PSCustomObject]@{ IsSelected = $false; Name = $app; RiskLevel = "Safe" })
    }
}

$UI_DebloatSelectRecommended.Add_Click({
    foreach ($item in $script:DebloatCollection) { $item.IsSelected = $true }
    $UI_DebloatGrid.Items.Refresh()
})

# --- REGISTRY LOGIC (V3.1 Professional) ---
$script:RegistryQueue = New-Object System.Collections.ObjectModel.ObservableCollection[PSObject]
$UI_RegistryGrid.ItemsSource = $script:RegistryQueue

$UI_ImportRegFile.Add_Click({
    $fd = New-Object Microsoft.Win32.OpenFileDialog
    if ($fd.ShowDialog()) {
        try {
            $lines = Get-Content $fd.FileName
            $currentKey = ""
            foreach ($line in $lines) {
                if ($line -match "^\[(.*)\]$") { $currentKey = $matches[1] }
                elseif ($line -match "^""(.*)""=(.*)$") {
                    $hive = if ($currentKey -match "HKEY_LOCAL_MACHINE") { "HKLM" } else { "HKCU" }
                    $path = $currentKey -replace "^HKEY_LOCAL_MACHINE\\|^HKEY_CURRENT_USER\\", ""
                    $script:RegistryQueue.Add([PSCustomObject]@{ Hive = $hive; Path = $path; Name = $matches[1]; Data = $matches[2] })
                }
            }
            Write-GuiLog "REG File imported." "SUCCESS"
        } catch { Write-GuiLog "REG error: $_" "ERROR" }
    }
})

# --- BUILD HUB & HANDLERS ---
$UI_BrowseSource.Add_Click({
    $fd = New-Object Microsoft.Win32.OpenFileDialog
    if ($fd.ShowDialog()) { $UI_SourcePath.Text = $fd.FileName }
})

$UI_StartBuild.Add_Click({
    if (-not (Test-Path $UI_SourcePath.Text)) { Write-GuiLog "Missing Source ISO" "ERROR"; return }
    
    $isUsbMode = [bool]$UI_ModeUsb.IsChecked
    $usbId = if ($isUsbMode) { ($UI_UsbDriveList.SelectedItem -split ' ')[0].Replace(":", "") } else { $null }

    $UI_StartBuild.IsEnabled = $false
    Write-GuiLog "Starting Production-Grade Build Pipeline..." "SUCCESS"

    Start-ThreadJob -ScriptBlock {
        param($iso, $isUsb, $usbId, $scriptPath)
        try {
            $win = [System.Windows.Application]::Current.Windows | Where-Object { $_.Title -match "GoldISO" } | Select-Object -First 1
            $log = { param($m, $l) $win.Dispatcher.Invoke({
                $con = $win.FindName("ConsoleOutput")
                $tr = New-Object System.Windows.Documents.TextRange($con.Document.ContentEnd, $con.Document.ContentEnd)
                $tr.Text = "[$l] $m`r"; $con.ScrollToEnd()
            })}

            & $scriptPath -SourceISOPath $iso -FlashToUsb $isUsb -TargetUsbDisk $usbId
            &$log "Deployment Successful!" "SUCCESS"
        } catch { 
            $win.Dispatcher.Invoke({ [System.Windows.MessageBox]::Show("Build Failed: $_") })
        } finally {
            $win.Dispatcher.Invoke({ $win.FindName("StartBuild").IsEnabled = $true })
        }
    } -ArgumentList $UI_SourcePath.Text, $isUsbMode, $usbId, (Join-Path $scriptDir "Build-GoldISO.ps1")
})

# --- INITIALIZATION ---
$Window.Add_Loaded({
    $drives = 65..90 | ForEach-Object { [char]$_ }
    $UI_CfgGamingDrive.ItemsSource = $drives; $UI_CfgAppsDrive.ItemsSource = $drives; $UI_CfgMediaDrive.ItemsSource = $drives
    Import-ConfigFromFile "C:\ProgramData\GoldISO\Config\build-manifest.json"
    Write-GuiLog "GoldISO Pro V3.1 Orchestrator Loaded." "SUCCESS"
})

$Window.ShowDialog() | Out-Null
