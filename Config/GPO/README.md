# GoldISO Group Policy (GPO) Configuration

This directory contains Group Policy Object (GPO) settings that replace many of the previous registry-based configurations. Using GPO provides better manageability, auditability, and aligns with enterprise Windows deployment practices.

## Overview

The GoldISO project has migrated **57+ registry-based settings** to GPO format. These settings are now applied using Microsoft's **LGPO.exe** (Local Group Policy Object tool) during the OOBE FirstLogon phase.

## Files

| File | Purpose | Context |
|------|---------|---------|
| `Computer-Policy.txt` | Machine-wide (HKLM) policy settings | Applied to computer configuration |
| `User-Policy.txt` | User-specific (HKCU) policy settings | Applied to current user and Default user |
| `Apply-GPOSettings.ps1` | First-login script that applies policies | Called by FirstLogonCommands |
| `Install-LGPO.ps1` | Downloads and installs LGPO.exe | Called by Apply-GPOSettings.ps1 |
| `Backup/` | Directory for policy backups | Created automatically on application |

## Settings Migrated to GPO

### Privacy & Telemetry (18 settings)
- `AllowTelemetry` - Disable telemetry collection
- `DisableLocation` - Turn off location tracking
- `NoFeedbackHub` - Disable Windows Feedback
- `DisabledByGroupPolicy` - Disable advertising ID
- `AllowInputPersonalization` - Disable speech personalization
- `DoNotShowFeedbackNotifications` - Disable feedback requests
- `DisableSettingSync` - Disable settings synchronization

### Windows Update (8 settings)
- `NoAutoRebootWithLoggedOnUsers` - Prevent auto-restart
- `ExcludeWUDriversInQualityUpdate` - Exclude drivers from updates
- `DODownloadMode` - Disable Delivery Optimization
- `SetUpdateNotificationLevel` - Configure update notifications

### Gaming & Performance (6 settings)
- `AllowGameDVR` - Disable Game DVR
- `AllowBroadcasting` - Disable broadcasting
- `AllowStorageSenseGlobal` - Enable Storage Sense

### Explorer & UI (10 settings)
- `HideFileExt` - Show file extensions
- `Hidden` - Show hidden files
- `ShowRecent` / `ShowFrequent` - Disable recent in Quick Access
- `SnapAssist` - Disable Snap Assist
- `DisableSearchBoxSuggestions` - Disable Bing in search
- `TurnOffWindowsCopilot` - Disable Windows Copilot
- `RecallEnabled` - Disable Windows Recall
- `TurnOffClickToRun` - Disable Click to Run

### Security (8 settings)
- `ConsentPromptBehaviorAdmin` / `PromptOnSecureDesktop` - UAC configuration
- `BlockAADWorkplaceJoin` - Block workplace join prompts
- `EnableHello` - Disable Windows Hello for Business
- `AllowCortana` / `AllowCortanaAboveLock` - Disable Cortana

### App Privacy (7 settings)
- `LetAppsRunInBackground` - Control background apps
- `KFMBlockOptIn` - Prevent OneDrive folder backup
- `AutoDownload` - Configure Store auto-download

## Settings Remaining as Registry

The following categories remain as registry edits because they:
1. Have no GPO equivalent
2. Must be applied during WinPE/offline phase
3. Are low-level performance optimizations

### Performance & Hardware (Registry-only)
- `Win32PrioritySeparation` - CPU scheduler priority
- `SystemResponsiveness` - Multimedia responsiveness
- `GlobalTimerResolutionRequests` - Timer resolution
- `IRQ8Priority` - Interrupt priority
- `NtfsDisableLastAccessUpdate` - NTFS optimization
- `NtfsDisable8dot3NameCreation` - 8.3 filename generation
- `LargeSystemCache` - System cache sizing
- NVMe queue depth settings
- GPU/Hardware scheduling settings

### Services (Registry-only)
- Service startup types (SysMain, Spooler, DiagTrack, etc.)
- Driver service configurations

### WinPE/Offline Required
- Settings in `04-specialize.xml`
- Settings in `Invoke-ISOBuild.ps1` (offline registry modifications)

## How It Works

### First Login Execution Flow

1. **Order 5** in `07-oobeSystem.xml` - `Apply-GPOSettings.ps1` runs
2. Script checks for LGPO.exe, downloads if missing
3. Applies `Computer-Policy.txt` (HKLM settings)
4. Applies `User-Policy.txt` (HKCU settings) to current user
5. Applies `User-Policy.txt` to Default user profile
6. Creates backup in `Config/GPO/Backup/`
7. Runs `gpupdate /force` to refresh policies

### LGPO Text Format

The `.txt` policy files use LGPO's text format:

```
; Comments start with semicolon
Computer\Software\Policies\Microsoft\Windows\DataCollection\AllowTelemetry=DWORD:0
User\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced\HideFileExt=DWORD:0
```

Format: `Hive\Registry\Path\ValueName=Type:Value`

## Modifying Policies

### To add a new GPO setting:

1. Find the GPO registry path (use `gpedit.msc` or ADMX reference)
2. Add entry to `Computer-Policy.txt` (HKLM) or `User-Policy.txt` (HKCU)
3. Format: `Computer\SOFTWARE\Policies\...\ValueName=DWORD:1`

### Common Registry Types:
- `DWORD:0` or `DWORD:1` - Numbers
- `SZ:"string"` - String values
- `BINARY:hex` - Binary data

## Troubleshooting

### Verify GPO Applied
```powershell
# Check applied policies
gpresult /r

# Check specific registry path
Get-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection" -Name AllowTelemetry

# View LGPO log
cat "C:\ProgramData\Winhance\Logs\gpo-application.log"
```

### Manual LGPO Application
```powershell
# Apply computer policy
LGPO.exe /t C:\ProgramData\Winhance\GPO\Computer-Policy.txt

# Apply user policy
LGPO.exe /t C:\ProgramData\Winhance\GPO\User-Policy.txt /u $env:USERNAME

# Export current policy
LGPO.exe /b C:\Temp\policy-backup.txt
```

### If GPO Application Fails

The registry-only tweaks in `tweaks-system.cmd` and `tweaks-user.cmd` serve as a fallback for critical settings. Check logs:
- `C:\ProgramData\Winhance\Logs\gpo-application.log`
- `C:\ProgramData\Winhance\Logs\tweaks-system.log`
- `C:\ProgramData\Winhance\Logs\tweaks-user.log`

## Migration Summary

| Source File | Settings Removed | Settings Retained |
|-------------|------------------|-------------------|
| `tweaks-system.cmd` | 18 GPO-available | 23 registry-only |
| `tweaks-user.cmd` | 18 GPO-available | 6 registry-only |
| `07-oobeSystem.xml` | 14 duplicate reg entries | 35 other commands |

**Total Lines of Code Reduced:** ~200 lines of duplicate registry edits  
**Settings Consolidated:** 57 GPO + 29 registry-only = 86 optimized settings

## References

- [LGPO Documentation](https://docs.microsoft.com/en-us/windows/security/threat-protection/security-compliance-toolkit-10)
- [Group Policy Settings Reference for Windows 11](https://www.microsoft.com/download/details.aspx?id=25250)
- [ADMX Templates for Windows 11](https://www.microsoft.com/download/details.aspx?id=104123)

## Notes

- **Windows 11 Pro/Enterprise Required:** GPO settings have limited effect on Windows 11 Home edition
- **LGPO.exe:** Must be present or downloaded during first login
- **Idempotent:** Can safely re-run `Apply-GPOSettings.ps1` multiple times
- **Backup:** Previous policy state is backed up before application
