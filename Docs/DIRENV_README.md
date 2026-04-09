# direnv Configuration for GoldISO

## Installation Summary

direnv has been installed and configured for your PowerShell environment.

### What was installed

1. **direnv** - Installed via Scoop to `C:\Users\C-Man\scoop\apps\direnv\current\`
2. **`.envrc`** - Project environment configuration file in the GoldISO root
3. **PowerShell Integration** - Custom functions added to load environment variables automatically

### Environment Variables Set

When in the GoldISO project directory, the following environment variables are automatically loaded:

| Variable                      | Value                                    |
| ----------------------------- | ---------------------------------------- |
| `GOLDISO_ROOT`                | Project root path                        |
| `GOLDISO_SCRIPTS`             | `C:/Users/C-Man/GoldISO/Scripts`         |
| `GOLDISO_CONFIG`              | `C:/Users/C-Man/GoldISO/Config`          |
| `GOLDISO_TESTS`               | `C:/Users/C-Man/GoldISO/Tests`           |
| `GOLDISO_BUILD_VERBOSE`       | `true`                                   |
| `POWERSHELL_EXECUTIONPOLICY`  | `RemoteSigned`                           |

### Available Aliases (in .envrc)

- `build` - Run CompleteBuild.ps1
- `test-pwsh` - Run Pester tests
- `gold-backup` - Run Backup-Config.ps1
- `gold-apply` - Run Apply-Image.ps1

Note: These aliases work in Git Bash. For PowerShell, use the full command names or create PowerShell aliases.

### How It Works

1. When you open a new PowerShell window, direnv is automatically configured
2. When you `cd` into the GoldISO directory, environment variables are loaded
3. The `Set-Location` command has been wrapped to automatically update environment variables

### Security

- `.envrc.local` and `.envrc.override` are in `.gitignore` for local-only changes
- The `.envrc` prevents loading in production environments (checks for "prod" in hostname)

### Commands

```powershell
# Allow the .envrc file (required after changes)
direnv allow

# Check status
direnv status

# Revoke permission
direnv revoke

# Manually export environment (for debugging)
direnv export bash
```

### Troubleshooting

#### direnv: error couldn't find a configuration directory

- The XDG environment variables are set in your profile automatically

#### Environment variables not loading

1. Ensure you're using the wrapped `Set-Location` (cd) command
2. Run `direnv status` to check if the .envrc is allowed
3. Run `direnv allow` to approve the .envrc

#### Git Bash not found

- direnv requires bash (included with Git for Windows)
- If Git is not at `C:\Program Files\Git\bin\bash.exe`, update `$env:DIRENV_BASH`
