# C-Man's Ultimate PowerShell Profile

## Quick Install

1. **Backup your existing profile** (if any):

    ```powershell
    if (Test-Path $PROFILE) { Copy-Item $PROFILE "$PROFILE.bak.$(Get-Date -Format 'yyyyMMdd_HHmmss')" }
    ```

2. **Extract the archive** to your PowerShell profile directory:

    ```powershell
    # For PowerShell 7+
    $profileDir = Split-Path $PROFILE.CurrentUserAllHosts -Parent
    # For Windows PowerShell 5.1
    # $profileDir = Split-Path $PROFILE -Parent
    ```

3. **Copy files**:

    ```powershell
    Copy-Item -Path .\Microsoft.PowerShell_profile.ps1 -Destination $PROFILE.CurrentUserAllHosts -Force
    @('Profile.d', 'Config', 'Themes', 'Templates', 'Templates.User') | ForEach-Object {
        Copy-Item -Path ".\$_" -Destination $profileDir -Recurse -Force
    }
    # Logs, Cache, and Vault directories are auto-created on first run
    ```

4. **Install recommended tools** (optional but recommended):

    ```powershell
    winget install JanDeDobbeleer.OhMyPosh     # Prompt engine
    winget install ajeetdsouza.zoxide           # Smart cd
    Install-Module PSScriptAnalyzer -Scope CurrentUser
    Install-Module Pester -Scope CurrentUser -MinimumVersion 5.0
    Install-Module Microsoft.PowerShell.SecretManagement -Scope CurrentUser
    Install-Module Microsoft.PowerShell.SecretStore -Scope CurrentUser
    ```

5. **Restart your terminal**.

## Detailed Installation Steps

### Step 1: Determine Your PowerShell Profile Path

Run one of the following commands based on your PowerShell version:

**PowerShell 7+:**

```powershell
Write-Host "Your profile path is:" -ForegroundColor Cyan
$PROFILE.CurrentUserAllHosts
```

**Windows PowerShell 5.1:**

```powershell
Write-Host "Your profile path is:" -ForegroundColor Cyan
$PROFILE
```

### Step 2: Create Profile Directory (If Needed)

If the directory doesn't exist, create it:

```powershell
$profileDir = Split-Path -Path $PROFILE.CurrentUserAllHosts -Parent
if (-not (Test-Path $profileDir)) {
    New-Item -ItemType Directory -Path $profileDir -Force
    Write-Host "Created profile directory: $profileDir" -ForegroundColor Green
}
```

### Step 3: Backup Existing Profile

Always backup your existing profile before installing:

```powershell
if (Test-Path $PROFILE.CurrentUserAllHosts) {
    $backupPath = "$PROFILE.CurrentUserAllHosts.bak.$(Get-Date -Format 'yyyyMMdd_HHmmss')"
    Copy-Item -Path $PROFILE.CurrentUserAllHosts -Destination $backupPath -Force
    Write-Host "Backed up existing profile to: $backupPath" -ForegroundColor Yellow
}
```

### Step 4: Install the Profile

Copy the profile files from the extracted archive:

```powershell
# Assuming you're in the extracted directory
Copy-Item -Path .\Microsoft.PowerShell_profile.ps1 -Destination $PROFILE.CurrentUserAllHosts -Force

@('Profile.d', 'Config', 'Themes', 'Templates', 'Templates.User') | ForEach-Object {
    $source = ".\$_"
    $destination = Join-Path -Path (Split-Path $PROFILE.CurrentUserAllHosts -Parent) -ChildPath $_
    if (Test-Path $source) {
        Copy-Item -Path $source -Destination $destination -Recurse -Force
        Write-Host "Copied: $_" -ForegroundColor Green
    }
}
```

### Step 5: Install Dependencies (Optional but Recommended)

Run these commands to install recommended tools:

```powershell
# Oh-My-Posh for enhanced prompt
winget install JanDeDobbeleer.OhMyPosh

# Zoxide for smart directory jumping
winget install ajeetdsouza.zoxide

# PowerShell modules for enhanced functionality
Install-Module PSScriptAnalyzer -Scope CurrentUser -Force
Install-Module Pester -Scope CurrentUser -Force -MinimumVersion 5.0
Install-Module Microsoft.PowerShell.SecretManagement -Scope CurrentUser -Force
Install-Module Microsoft.PowerShell.SecretStore -Scope CurrentUser -Force
```

### Step 6: Restart Your Terminal

Close and reopen your terminal application to load the new profile.

## Verification Steps

### Step 1: Check Profile Load Time

After restarting your terminal, you should see a startup message similar to:

```text
Profile loaded in XXXms
Aliases: ws, cln, scripts, dev, gs, ga, gc, OC
Use 'Show-Help' to display help
```

### Step 2: Verify Basic Functionality

Run these commands to verify the profile is working correctly:

```powershell
# Check if profile loaded successfully
$profileLoaded = Get-Variable -Name ProfileRoot -ErrorAction SilentlyContinue
if ($profileLoaded) {
    Write-Host "✓ Profile root variable is set" -ForegroundColor Green
} else {
    Write-Host "✗ Profile root variable is missing" -ForegroundColor Red
}

# Check if lazy loading is enabled
$lazyEnabled = $Global:ProfileConfig.EnableLazyLoading
if ($lazyEnabled) {
    Write-Host "✓ Lazy loading is enabled" -ForegroundColor Green
} else {
    Write-Host "✗ Lazy loading is disabled" -ForegroundColor Red
}

# Test a few core aliases
Test-Alias ws | Out-Null
if ($?) {
    Write-Host "✓ Core alias 'ws' is working" -ForegroundColor Green
} else {
    Write-Host "✗ Core alias 'ws' is not working" -ForegroundColor Red
}
```

```powershell
# Check if help function works
Show-Help | Out-Null
if ($?) {
    Write-Host "✓ Help system is functional" -ForegroundColor Green
} else {
    Write-Host "✗ Help system is not working" -ForegroundColor Red
}
```

```powershell
# Verify module load times tracking
if ($Global:ProfileLoadTimes.Count -gt 0) {
    Write-Host "✓ Module load times are being tracked ($($Global:ProfileLoadTimes.Count) modules)" -ForegroundColor Green
} else {
    Write-Host "✗ Module load times tracking is not working" -ForegroundColor Red
}
```

### Step 3: Test Lazy Loading

To verify that lazy loading is working correctly:

```powershell
# Check initial loaded deferred modules count
$initialCount = $script:LoadedDeferredModules.Count
Write-Host "Initially loaded deferred modules: $initialCount" -ForegroundColor Cyan

# Trigger loading of a deferred module (e.g., git-related command)
git --version | Out-Null

# Check if the module was loaded
$afterCount = $script:LoadedDeferredModules.Count
if ($afterCount -gt $initialCount) {
    Write-Host "✓ Lazy loading worked - new module loaded on demand" -ForegroundColor Green
} else {
    Write-Host "✗ Lazy loading may not be working correctly" -ForegroundColor Yellow
}
```

### Step 4: Check Logs Directory

Verify that logging is working:

```powershell
$logsDir = Join-Path -Path $script:ProfileRoot -ChildPath 'Logs'
if (Test-Path $logsDir) {
    Write-Host "✓ Logs directory exists" -ForegroundColor Green
    
    $sessionLogs = Join-Path $logsDir 'sessions'
    $errorLogs = Join-Path $logsDir 'errors'
    
    if (Test-Path $sessionLogs) {
        Write-Host "✓ Session logs directory exists" -ForegroundColor Green
    }
    
    if (Test-Path $errorLogs) {
        Write-Host "✓ Error logs directory exists" -ForegroundColor Green
    }
} else {
    Write-Host "✗ Logs directory is missing" -ForegroundColor Red
}
```

## Rollback Instructions

If you encounter issues with the new profile, follow these steps to restore your previous configuration:

### Step 1: Identify Your Backup

List your profile backups:

```powershell
$profileDir = Split-Path -Path $PROFILE.CurrentUserAllHosts -Parent
Get-ChildItem -Path $profileDir -Filter "Microsoft.PowerShell_profile.ps1.bak.*" | 
    Sort-Object LastWriteTime -Descending | 
    Select-Object Name, LastWriteTime
```

### Step 2: Restore from Backup

Choose the most recent backup (or the one you know is good) and restore it:

```powershell
# Replace 'BACKUP_FILENAME' with the actual backup file name from the list above
$backupFile = Join-Path -Path $profileDir -ChildPath 'BACKUP_FILENAME'
Copy-Item -Path $backupFile -Destination $PROFILE.CurrentUserAllHosts -Force
Write-Host "Profile restored from backup: $backupFile" -ForegroundColor Green
```

### Step 3: Restart Your Terminal

Close and reopen your terminal to use the restored profile.

### Step 4: Verify Restoration

Run the verification steps above to confirm your previous profile is working correctly.

### Emergency Rollback (If Terminal Won't Start)

If the profile prevents your terminal from starting properly:

1. Open a new terminal window or tab
2. Manually override the profile loading by starting PowerShell with `-NoProfile`:

   ```powershell
   pwsh -NoProfile  # For PowerShell 7+
   # or
   powershell -NoProfile  # For Windows PowerShell 5.1
   ```

3. Once in a clean session, restore your backup as described above
4. Restart your terminal normally

## Troubleshooting Common Issues

### Issue: Profile Takes Too Long to Load

**Solution:** Check the load times report:

```powershell
loadtimes  # Shows module load times
```

Consider disabling modules you don't use by editing `Microsoft.PowerShell_profile.ps1` and removing them from the `$script:ImmediateModules` or `$script:DeferredModules` arrays.

### Issue: Specific Function Not Working

**Solution:**

1. Check if it's a lazy-loaded function: `Get-Command <function-name>`
2. If it shows as a stub, try calling it once to trigger loading
3. Check error logs: `Get-Content (Join-Path $script:ProfileRoot 'Logs\errors\error_*.log') -Tail 20`

### Issue: Aliases Not Working

**Solution:**

1. Check if the alias module loaded: `Get-Module | Where-Object {$_.Name -like '*Alias*'}`
2. Reload aliases: `. (Join-Path $script:ProfileModulesPath '04-Aliases.ps1')`
3. Check if the underlying function exists: `Get-Command <function-behind-alias>`

### Issue: Theme Not Applying Correctly

**Solution:**

1. Verify Oh-My-Posh is installed: `oh-my-posh --version`
2. Try switching themes: `theme Matrix` (or Cyberpunk, Dracula, Monochrome)
3. Check your theme config: `Get-ProfileConfig | Select-Object -ExpandProperty Theme`

## Maintenance Commands

These commands help you maintain and troubleshoot your profile:

```powershell
# Show profile statistics and load times
Show-ProfileStats

# Reload the entire profile
Invoke-ProfileReload

# Edit your profile in your default editor
Edit-Profile

# Check for profile updates (if auto-updater is enabled)
Check-ProfileUpdate

# Update the profile (if auto-updater is enabled)
Update-Profile

# Show current configuration
Get-ProfileConfig

# Modify a configuration setting
Set-ProfileConfig -Key "Theme" -Value "Dracula"

# Enable/disable features
Set-ProfileConfig -Key "EnableLazyLoading" -Value $false
Set-ProfileConfig -Key "EnableSessionLogging" -Value $true
```

## Structure

```text
~/PowerShell/
├── Microsoft.PowerShell_profile.ps1   # Main loader (timed, modular)
├── Profile.d/                         # 21 modules loaded in sort order
│   ├── 00-Themes.ps1                  # 4 color themes (Matrix, Cyberpunk, Dracula, Mono)
│   ├── 01-PSReadLine.ps1              # Readline, predictions, keybindings, auto-pair
│   ├── 02-Prompt.ps1                  # Oh-My-Posh + pure-PS fallback prompt
│   ├── 03-Navigation.ps1              # Auto-cd, zoxide, bookmarks, dir history stack
│   ├── 04-Aliases.ps1                 # 70+ aliases (git, docker, dotnet, packages)
│   ├── 05-Functions-Core.ps1          # File ops, clipboard, system info, text utils
│   ├── 06-Functions-Dev.ps1           # Project mgmt, builds, code analysis
│   ├── 07-Functions-SysAdmin.ps1      # Services, network, firewall, Hyper-V, SSH
│   ├── 08-Completers.ps1             # Tab completion for git, winget, dotnet, docker
│   ├── 09-Banner.ps1                 # Startup banner (compact/expanded/off)
│   ├── 10-Logging.ps1                # Session transcripts, error logging
│   ├── 11-Management.ps1             # Lazy loading, config, profile help
│   ├── 12-Better11.ps1               # Better11 project integration
│   ├── 13-AutoUpdater.ps1            # Git-based profile self-updater
│   ├── 14-ExtendedTools.ps1          # npm/pip/Podman/WSL, drift detection, CI/CD
│   ├── 15-SecretVault.ps1            # Credential vault, tokens, SSH keys
│   ├── 16-GitWorkflow.ps1            # Conventional commits, branch cleanup, PR draft
│   ├── 17-EnvironmentSwitcher.ps1    # .env loader, profiles, snapshot rollback
│   ├── 18-Snippets.ps1              # Template engine (11 built-in, user-extensible)
│   ├── 19-PackageHealth.ps1          # Cross-manager outdated check, security audit
│   └── 20-ClipboardRing.ps1          # Clipboard history, search, 18 transforms
├── Config/profile-config.json         # All settings (JSON, hot-editable)
├── Themes/matrix-custom.omp.json      # Oh-My-Posh Matrix theme
├── Templates/                         # Built-in scaffold templates (auto-populated)
├── Templates.User/                    # Drop custom .tmpl files here
├── Vault/                             # DPAPI-encrypted secrets (auto-created)
├── Logs/{sessions,errors}/            # Transcripts and error logs
├── Cache/                             # Frecency DB, bookmarks, clipboard ring
├── Tests/Profile.Tests.ps1           # Pester 5 test suite (1,636 lines)
└── PSScriptAnalyzerSettings.psd1      # Linting rules
```

## Quick Reference

### Core

| Command            | Description                          |
|--------------------|--------------------------------------|
| `F1`               | Show keybinding reference            |
| `phelp`            | Full command reference               |
| `aliases`          | List all aliases by category         |
| `banner -Expanded` | Show full system dashboard           |
| `config`           | View profile settings                |
| `loadtimes`        | Module load performance              |
| `devenv`           | Dev tool version overview            |
| `theme Matrix`     | Switch color theme                   |

### Navigation

| Command        | Description                          |
|----------------|--------------------------------------|
| `go <name>`    | Jump to bookmarked directory         |
| `bm <name>`    | Bookmark current directory           |
| `z <query>`    | Frecency-based directory jump        |
| `up [N]`       | Navigate up N directories            |
| `bd` / `fd`    | Directory back / forward             |

### Secret Vault (15)

| Command           | Description                          |
|-------------------|--------------------------------------|
| `secset <n> <v>`  | Store a secret                       |
| `sec <name>`      | Retrieve a secret                    |
| `secls`           | List all secrets (values hidden)     |
| `seccp <name>`    | Copy secret to clipboard (auto-clear)|
| `tokenset <n> <v>`| Store expiring session token         |
| `token <name>`    | Retrieve token (checks expiry)       |
| `tokens`          | Show all tokens with status          |
| `sshkeys`         | List SSH agent keys                  |
| `sshadd`          | Start agent and add default keys     |
| `sshgen <name>`   | Generate Ed25519 SSH key             |

### Git Workflow (16)

| Command            | Description                          |
|--------------------|--------------------------------------|
| `ccommit`          | Interactive conventional commit      |
| `gcleanup`         | Clean merged/stale branches          |
| `gsave <msg>`      | Stash with description               |
| `gstashes`         | List stashes with age                |
| `grestore [N]`     | Apply stash by index                 |
| `gconflict`        | List files with merge conflicts      |
| `pr -Push`         | Push branch and open PR in browser   |
| `glog [N]`         | Pretty graph log                     |
| `gdiff`            | Branch diff vs default               |
| `gamend`           | Amend last commit                    |
| `gundo [N]`        | Soft reset last N commits            |
| `gwt` / `gwtnew`   | List / create worktrees              |

### Environment Switcher (17)

| Command              | Description                          |
|----------------------|--------------------------------------|
| `envload`            | Load .env from current directory     |
| `envload -Profile prod`| Load .env.prod                     |
| `envunload`          | Restore previous env variables       |
| `envstack`           | Show loaded environment stack        |
| `envdiff <a> <b>`    | Compare two .env files               |
| `envls`              | List available .env files            |
| `envauto`            | Enable auto-load on cd               |
| `envtemplate`        | Generate .env.example from .env      |

### Snippet & Scaffold (18)

| Command                          | Description                  |
|----------------------------------|------------------------------|
| `templates`                      | List all available templates |
| `scaffold cs-class MyService`    | Quick scaffold with name     |
| `scaffold ps-function Invoke-X`  | PowerShell function template |
| `scaffold mcp-server my-server`  | MCP server skeleton          |

Templates: `ps-function`, `ps-module`, `ps-pester`, `cs-class`, `cs-interface`, `cs-xunit`, `cs-viewmodel`, `xaml-page`, `mcp-server`, `jest-test`, `gitignore`

### Package Health (19)

| Command                    | Description                          |
|----------------------------|--------------------------------------|
| `health`                   | Full cross-manager outdated report   |
| `health -Quick`            | Fast managers only                   |
| `health -IncludeSecurity`  | Include npm audit                    |
| `pkgupdate winget`         | Update all packages for a manager    |

### Clipboard Ring (20)

| Command               | Description                          |
|-----------------------|--------------------------------------|
| `clip+ <text>`        | Copy to clipboard + ring             |
| `clip- <N>`           | Recall ring entry N                  |
| `clipls`              | Show ring history                    |
| `clipsearch <pat>`    | Fuzzy search the ring                |
| `clipx Base64Encode`  | Transform clipboard content          |
| `clipx JsonPretty`    | Pretty-print JSON on clipboard       |
| `clipclear`           | Clear ring history                   |

Transforms: Base64Encode/Decode, JsonPretty/Minify, Trim, Upper, Lower, TitleCase, UriEncode/Decode, HtmlEncode/Decode, LineSort/Unique/Reverse/Count, Md5Hash, Sha256Hash, EscapeRegex

## Themes

Switch with `Set-ProfileTheme -Name <theme> -Save`:

- **Matrix** (default) - Green on black
- **Cyberpunk** - Neon magenta/cyan
- **Dracula** - Purple/cyan dark theme
- **Monochrome** - Clean grayscale

## Running Tests

```powershell
Invoke-Pester -Path ./Tests/Profile.Tests.ps1 -Output Detailed
```

## Stats

- 21 modules, 11,777 lines of PowerShell
- ~250 functions, ~145 aliases
- 1,636 lines of Pester 5 tests
- 4 themes, 11 scaffold templates, 18 clipboard transforms
- Compatible with PowerShell 5.1 and 7+
- CaskaydiaCove Nerd Font support (graceful fallback)
