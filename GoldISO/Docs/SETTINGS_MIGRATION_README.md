# GoldISO Settings Migration System

## Overview

The Settings Migration System captures your current Windows system configuration, application settings, and user data, then automatically restores them during a fresh Windows installation using GoldISO.

**Key Features:**
- Fully automated export and restore workflow
- Preserves browser bookmarks, extensions, and settings
- Saves development tool configurations (VS Code, Git, etc.)
- Maintains game launcher libraries and settings
- Restores Windows Explorer, taskbar, and theme preferences
- Optional user data backup (Documents, Downloads, Desktop)
- Hardware settings reference (display, audio)

---

## Quick Start

### Export and Build ISO with One Command

```powershell
# From the GoldISO project root
.\Scripts\Build-ISO-With-Settings.ps1
```

### What Happens:
1. Exports all system and application settings
2. Validates the export package
3. Embeds settings into the ISO structure
4. Updates autounattend.xml with auto-restore commands
5. Builds the final ISO (or prepares for manual build)

---

## Usage Options

### Include User Data (Documents, Downloads, etc.)

```powershell
.\Build-ISO-With-Settings.ps1 -ExportUserData -MaxUserDataSizeGB 5
```

### Exclude Specific Applications

```powershell
.\Build-ISO-With-Settings.ps1 -ExcludeApps @("Chrome", "Firefox")
```

### Use Existing Export (Skip Re-Export)

```powershell
.\Build-ISO-With-Settings.ps1 -SkipExport
```

### Export Only (No ISO Build)

```powershell
.\Build-ISO-With-Settings.ps1 -SkipISOBUILD
```

---

## Individual Scripts

### Export Settings Only

```powershell
.\Scripts\Export-Settings.ps1 -ExportUserData -Compress
```

**Parameters:**
- `-ExportPath` - Where to save the export (default: `..\Config\SettingsMigration`)
- `-ExportUserData` - Include Documents, Downloads, Desktop, Pictures
- `-MaxUserDataSizeGB` - Size limit for user data (default: 10)
- `-ExcludeApps` - Apps to skip: `@("Chrome", "VSCode")`
- `-IncludeWifiPasswords` - Include WiFi passwords (with confirmation)
- `-Compress` - Create ZIP archive

### Restore Settings Manually

If you need to restore settings outside of the automated process:

```powershell
.\Config\SettingsMigration\restore-settings.ps1 -SettingsPath "C:\SettingsMigration"
```

---

## What Gets Exported

### System Settings (Registry)
- Windows Explorer preferences (view modes, hidden files, etc.)
- Taskbar position, size, and behavior
- Desktop wallpaper and theme settings
- Start menu layout
- Search preferences
- Power plans
- Mouse and keyboard settings
- Regional and language settings

### Web Browsers
- **Chrome**: Bookmarks, preferences, extensions list
- **Edge**: Bookmarks, settings
- **Firefox**: Profile settings, bookmarks, history

### Development Tools
- **VS Code**: Settings, keybindings, snippets, extensions list
- **Git**: Global configuration (.gitconfig, .gitignore_global)
- **PowerShell**: Profile scripts
- **Oh My Posh**: Themes and configuration

### Game Launchers
- **Steam**: Library paths, user settings (NOT game files)
- **Epic Games**: Launcher settings
- **GOG Galaxy**: Configuration

### Media & Communication
- **Discord**: Settings, login state
- **Spotify**: Preferences
- **VLC**: Configuration

### System Utilities
- **Everything**: Search indexes, bookmarks
- **7-Zip**: Settings
- **Notepad++**: Configuration, themes, custom languages
- **Windows Terminal**: Settings and state

### User Data (Optional)
- Desktop shortcuts and files
- Documents folder
- Downloads folder
- Pictures folder
- Videos folder
- Music folder

### Hardware Settings (Reference Only)
- Display configuration (for reference)
- Audio device list (for reference)
- WiFi profiles (optional, with passwords if requested)

---

## Security Considerations

### What's NOT Exported (For Security)
- Browser passwords (use browser sync instead)
- Credential manager data
- Windows login passwords
- Sensitive registry keys
- Encrypted files

### WiFi Passwords
WiFi passwords are **NOT** exported by default. To include them:

```powershell
.\Export-Settings.ps1 -IncludeWifiPasswords
```

You'll be prompted to type "YES" to confirm. Passwords are stored in plain text - use with caution.

---

## How It Works

### Export Phase

```
┌─────────────────┐     ┌──────────────────┐     ┌─────────────────────┐
│  Your System    │ --> │ Export-Settings  │ --> │ Settings Package    │
│  (Current)      │     │    .ps1          │     │ (ZIP or Folder)     │
└─────────────────┘     └──────────────────┘     └─────────────────────┘
                                                              │
                                                              v
                                                  ┌─────────────────────┐
                                                  │ Config/             │
                                                  │ SettingsMigration/  │
                                                  └─────────────────────┘
```

### Installation Phase

```
┌─────────────────┐     ┌──────────────────┐     ┌─────────────────────┐
│   GoldISO       │ --> │  Windows Setup   │ --> │   FirstLogon        │
│  (with embedded │     │  (Copy Settings  │     │   (Auto-Restore     │
│   settings)     │     │   to C: drive)   │     │   Settings)         │
└─────────────────┘     └──────────────────┘     └─────────────────────┘
                                                              │
                                                              v
                                                  ┌─────────────────────┐
                                                  │  System Ready with  │
                                                  │  Your Settings!     │
                                                  └─────────────────────┘
```

---

## Directory Structure

```
GoldISO/
├── Scripts/
│   ├── Export-Settings.ps1              # Export your current settings
│   ├── Build-ISO-With-Settings.ps1      # Master orchestrator
│   └── Get.ps1                          # (existing)
├── Config/
│   ├── SettingsMigration/               # Embedded in ISO
│   │   ├── restore-settings.ps1         # Auto-restore script
│   │   ├── manifest.json                # Export metadata
│   │   ├── registry/                    # Registry exports
│   │   ├── appdata/                     # Application configs
│   │   ├── user-folders/                # User data (optional)
│   │   └── hardware/                    # Hardware settings
│   └── autounattend.xml                 # Already configured!
└── Win11-25H2x64v2.iso                  # Final ISO
```

---

## autounattend.xml Integration

The system is already integrated into `autounattend.xml`:

```xml
<!-- In FirstLogonCommands section -->
<SynchronousCommand wcm:action="add">
  <Order>40</Order>
  <Description>Restore Settings from Migration Package</Description>
  <CommandLine>powershell.exe -NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -Command "if (Test-Path 'C:\SettingsMigration\restore-settings.ps1') { &amp; 'C:\SettingsMigration\restore-settings.ps1' -LogPath 'C:\SettingsMigration\restore.log' }"</CommandLine>
  <RequiresUserInput>false</RequiresUserInput>
</SynchronousCommand>
```

This command:
1. Runs automatically after first user logon
2. Checks if the settings package exists
3. Executes the restore script silently
4. Logs all activity to `C:\SettingsMigration\restore.log`

---

## Troubleshooting

### Export Issues

**"Export script not found"**
- Ensure you're running from the `Scripts\` directory
- Check that `Export-Settings.ps1` exists

**"Access denied" errors**
- Run PowerShell as Administrator
- Some registry keys may be locked by the system (these are skipped)

**Large export size**
- User data folders can be large
- Use `-MaxUserDataSizeGB` to limit size
- Exclude specific apps with `-ExcludeApps`

### Restore Issues

**Settings not restored after installation**
- Check `C:\SettingsMigration\restore.log` for errors
- Verify the SettingsMigration folder was copied during install
- Ensure the restore script exists in the package

**Applications not showing settings**
- Some apps may need to be installed first
- The restore happens before all apps are fully set up
- Run `restore-settings.ps1` manually after app installation

**Conflicts with existing settings**
- The restore merges settings (doesn't overwrite if files exist)
- Registry imports may fail for already-configured keys
- Check the log for specific conflict messages

### Manual Restoration

If automatic restore fails:

```powershell
# Find the settings package
$settingsPath = "C:\SettingsMigration"

# Run restore manually
& "$settingsPath\restore-settings.ps1" -Verbose
```

---

## Best Practices

### Before Export
1. Close all applications to ensure settings are flushed to disk
2. Clean up unnecessary files (reduce export size)
3. Update applications to latest versions
4. Verify browser sync is working (backup for passwords)

### Build Process
1. Run export first: `.\Export-Settings.ps1`
2. Review the export manifest: `Config\SettingsMigration\manifest.json`
3. Check export size - large packages slow down installation
4. Test in a VM before bare-metal deployment

### After Installation
1. Check `C:\SettingsMigration\restore.log` for any errors
2. Verify critical apps are working with restored settings
3. Re-sync browsers to get passwords
4. Reconfigure any hardware-specific settings (displays, audio)

---

## Size Guidelines

| Component | Typical Size | Recommendation |
|-----------|--------------|----------------|
| Registry | 1-5 MB | Always include |
| Chrome | 10-50 MB | Include |
| VS Code | 1-5 MB | Include |
| Steam | 1-10 MB | Include (configs only) |
| Discord | 5-20 MB | Include |
| User Data | Variable | Use -MaxUserDataSizeGB |
| **Total** | **50-200 MB** | Keep under 500 MB |

**Note:** Larger packages increase ISO size and installation time.

---

## Advanced Usage

### Custom Restore Script

Modify `Config\SettingsMigration\restore-settings.ps1` to add custom logic:

```powershell
# Add to the Restore-AppSettings function
"MyCustomApp" {
    Copy-AppData -Source $appDir.FullName -DestRoot $env:APPDATA -SubPath "MyCustomApp"
}
```

### Scheduled Exports

Create a scheduled task to export settings weekly:

```powershell
$action = New-ScheduledTaskAction -Execute "powershell.exe" -Argument "-File C:\Users\C-Man\GoldISO\Scripts\Export-Settings.ps1"
$trigger = New-ScheduledTaskTrigger -Weekly -DaysOfWeek Sunday -At "2:00 AM"
Register-ScheduledTask -TaskName "GoldISO-Settings-Export" -Action $action -Trigger $trigger
```

### Multiple Machine Deployment

For deploying to multiple machines with similar configs:

1. Export from reference machine
2. Keep the export in `Config\SettingsMigration\`
3. Build ISO once
4. Deploy to all machines

---

## Files Reference

| File | Purpose | Location |
|------|---------|----------|
| `Export-Settings.ps1` | Captures current system state | `Scripts\` |
| `Build-ISO-With-Settings.ps1` | Orchestrates full workflow | `Scripts\` |
| `restore-settings.ps1` | Restores settings during install | `Config\SettingsMigration\` |
| `manifest.json` | Export metadata & checksums | `Config\SettingsMigration\` |
| `autounattend.xml` | Unattended install config | `Config\` |

---

## Support & Feedback

For issues or feature requests:
1. Check the log files: `export.log` and `restore.log`
2. Review this README for common solutions
3. Examine the manifest.json for export details

---

## Summary

The Settings Migration System makes it easy to:
- ✅ Preserve your Windows customization
- ✅ Keep application settings across reinstalls
- ✅ Automate the entire process
- ✅ Reduce post-install configuration time

**Run this command to get started:**
```powershell
.\Scripts\Build-ISO-With-Settings.ps1 -ExportUserData
```
