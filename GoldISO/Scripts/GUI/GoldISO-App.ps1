#Requires -Version 5.1
#Requires -RunAsAdministrator

Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase

$AppRoot = "C:\ProgramData\GoldISO"
$ManifestPath = Join-Path $AppRoot "Config\build-manifest.json"

# Load current config if exists
if (Test-Path $ManifestPath) {
    $Config = Get-Content $ManifestPath -Raw | ConvertFrom-Json
}

# Simple XAML UI
[xml]$xaml = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        Title="GoldISO Control Center (Target)" Height="450" Width="600"
        Background="#121212" Foreground="#E0E0E0">
    <Grid Margin="20">
        <StackPanel>
            <TextBlock Text="GoldISO System Management" FontSize="20" FontWeight="Bold" Margin="0,0,0,20" Foreground="#D4AF37"/>
            
            <GroupBox Header="Gaming Junctions" Margin="0,0,0,15" Foreground="#D4AF37">
                <StackPanel Margin="10">
                    <TextBlock Text="Current Gaming Drive: C:\Gaming" Margin="0,0,0,10"/>
                    <Button Name="UpdateJunctions" Content="REFRESH JUNCTIONS" Height="35" Background="#2D2D30" Foreground="White"/>
                </StackPanel>
            </GroupBox>

            <GroupBox Header="Performance Toggles" Margin="0,0,0,15" Foreground="#D4AF37">
                <StackPanel Margin="10">
                    <CheckBox Name="ToggleGameMode" Content="Windows Game Mode" Foreground="White" Margin="0,5"/>
                    <CheckBox Name="ToggleHAGS" Content="Hardware GPU Scheduling" Foreground="White" Margin="0,5"/>
                    <Button Name="RestoreDefaults" Content="RESTORE FACTORY DEFAULTS (ROLLBACK)" Margin="0,10,0,0" Height="25" FontSize="10" Background="#222222" Foreground="#888888"/>
                </StackPanel>
            </GroupBox>

            <Button Name="SaveSettings" Content="APPLY &amp; SAVE" Height="45" Background="#D4AF37" Foreground="Black" FontWeight="Bold"/>
            <TextBlock Name="StatusText" Text="Ready." Foreground="#888888" Margin="0,10,0,0" HorizontalAlignment="Center"/>
        </StackPanel>
    </Grid>
</Window>
"@

$reader = New-Object System.Xml.XmlNodeReader $xaml
$Window = [Windows.Markup.XamlReader]::Load($reader)

# Map Elements
$UI_UpdateJunctions = $Window.FindName("UpdateJunctions")
$UI_ToggleGameMode = $Window.FindName("ToggleGameMode")
$UI_ToggleHAGS = $Window.FindName("ToggleHAGS")
$UI_RestoreDefaults = $Window.FindName("RestoreDefaults")
$UI_SaveSettings = $Window.FindName("SaveSettings")
$UI_StatusText = $Window.FindName("StatusText")

# State Management (V3.1 Professional)
$SnapshotPath = Join-Path $AppRoot "Config\registry-snapshot.json"

# Initialize state
if ($Config) {
    $UI_ToggleGameMode.IsChecked = $Config.optimizations.game_mode
    $UI_ToggleHAGS.IsChecked = $Config.optimizations.hags
}

$UI_UpdateJunctions.Add_Click({
    $UI_StatusText.Text = "Updating junctions..."
    try {
        $targetDrive = if ($Config) { $Config.drives.gaming } else { "D" }
        $targetPath = "$($targetDrive):\Gaming"
        
        if (-not (Test-Path $targetPath)) { New-Item -ItemType Directory -Path $targetPath -Force | Out-Null }
        if (Test-Path "C:\Gaming") {
            if ((Get-Item "C:\Gaming").LinkType -eq "Junction") { Remove-Item "C:\Gaming" -Force }
            else { Move-Item "C:\Gaming\*" $targetPath -Force -ErrorAction SilentlyContinue }
        }
        
        New-Item -ItemType Junction -Path "C:\Gaming" -Value $targetPath -Force | Out-Null
        $UI_StatusText.Text = "Junction Created: C:\Gaming -> $targetPath"
    } catch {
        $UI_StatusText.Text = "Junction Failed: $_"
    }
})

$UI_SaveSettings.Add_Click({
    try {
        # Create Snapshot before first apply
        if (-not (Test-Path $SnapshotPath)) {
            $snap = @{
                GameMode = (Get-ItemProperty -Path "HKCU:\Software\Microsoft\GameBar" -Name "AllowAutoGameMode" -ErrorAction SilentlyContinue).AllowAutoGameMode
                HAGS = (Get-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Control\GraphicsDrivers" -Name "HwSchMode" -ErrorAction SilentlyContinue).HwSchMode
            }
            $snap | ConvertTo-Json | Set-Content $SnapshotPath -Force
        }

        # Apply Game Mode
        $gmVal = if ($UI_ToggleGameMode.IsChecked) { 1 } else { 0 }
        Set-ItemProperty -Path "HKCU:\Software\Microsoft\GameBar" -Name "AllowAutoGameMode" -Value $gmVal
        
        # Apply HAGS (Requires HKLM)
        $hagsVal = if ($UI_ToggleHAGS.IsChecked) { 2 } else { 1 } # 2 = Enabled, 1 = Disabled
        Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Control\GraphicsDrivers" -Name "HwSchMode" -Value $hagsVal
        
        # Handle Auto-Start (V3.1)
        $regPath = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Run"
        if ($Config.identity.auto_start_app) {
            Set-ItemProperty -Path $regPath -Name "GoldISO_App" -Value "powershell.exe -WindowStyle Hidden -File $AppRoot\Scripts\GoldISO-App.ps1"
        } else {
            Remove-ItemProperty -Path $regPath -Name "GoldISO_App" -ErrorAction SilentlyContinue
        }

        $UI_StatusText.Text = "System settings applied. Restart recommended."
    } catch {
        $UI_StatusText.Text = "Error applying registry: $_"
    }
})

$UI_RestoreDefaults.Add_Click({
    if (Test-Path $SnapshotPath) {
        try {
            $snap = Get-Content $SnapshotPath -Raw | ConvertFrom-Json
            Set-ItemProperty -Path "HKCU:\Software\Microsoft\GameBar" -Name "AllowAutoGameMode" -Value $snap.GameMode
            Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Control\GraphicsDrivers" -Name "HwSchMode" -Value $snap.HAGS
            $UI_StatusText.Text = "Rollback successful. Registry restored to original state."
        } catch {
            $UI_StatusText.Text = "Restore failed: $_"
        }
    } else {
        $UI_StatusText.Text = "No snapshot found. Manual reset required."
    }
})

$Window.ShowDialog() | Out-Null
