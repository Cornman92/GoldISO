# GoldISO Module API Reference

## GoldISO-Common.psm1

Shared module providing core functions for all GoldISO scripts.

### Logging Functions

#### Initialize-Logging
Initializes logging system with timestamp and log file.
```powershell
Initialize-Logging -LogName "Build" -LogPath "Logs"
```

#### Write-GoldISOLog
Writes formatted log messages with severity levels.
```powershell
Write-GoldISOLog -Message "Build started" -Level "INFO"
# Levels: INFO, WARN, ERROR, SUCCESS
```

#### Start-GoldISOTranscript
Starts PowerShell transcript logging.
```powershell
Start-GoldISOTranscript -LogPath "Logs\transcript.txt"
```

#### Stop-GoldISOTranscript
Stops transcript and saves to file.
```powershell
Stop-GoldISOTranscript
```

### Validation Functions

#### Test-GoldISOAdmin
Checks for Administrator privileges, exits if not.
```powershell
Test-GoldISOAdmin -ExitIfNotAdmin
```

#### Test-GoldISOPath
Validates path exists and is accessible.
```powershell
Test-GoldISOPath -Path "C:\Mount"
```

#### Test-GoldISOWinPE
Detects if running in Windows PE environment.
```powershell
$isWinPE = Test-GoldISOWinPE
```

#### Test-GoldISODiskSpace
Checks available disk space meets minimum requirement.
```powershell
Test-GoldISODiskSpace -MinimumGB 30 -Path "C:\"
```

#### Test-GoldISOCommand
Verifies a command (exe/dll) exists and is executable.
```powershell
Test-GoldISOCommand -Command "dism.exe"
```

#### Test-DiskTopology
Validates disk configuration matches expected layout.
```powershell
Test-DiskTopology -ExpectedLayout "GamerOS-3Disk"
```

### Utility Functions

#### Get-GoldISORoot
Returns project root directory path.
```powershell
$root = Get-GoldISORoot
```

#### Format-GoldISOSize
Formats byte size to human-readable string.
```powershell
$size = Format-GoldISOSize -Bytes 1073741824  # Returns "1 GB"
```

#### Invoke-GoldISOCommand
Executes external command with logging and error handling.
```powershell
Invoke-GoldISOCommand -Command "dism.exe" -Arguments "/Online /Cleanup-Image /RestoreHealth"
```

#### Get-ComponentHash
Generates SHA256 hash for build components.
```powershell
$hash = Get-ComponentHash -Path "C:\Drivers"
```

### Manifest Functions

#### Import-BuildManifest
Loads build manifest JSON file.
```powershell
$manifest = Import-BuildManifest -Path "Config\build-manifest.json"
```

#### Export-BuildManifest
Saves build manifest to JSON file.
```powershell
Export-BuildManifest -Manifest $manifest -Path "Config\build-manifest.json"
```

### Checkpoint Functions

#### Initialize-Checkpoint
Initializes checkpoint system for resumable builds.
```powershell
Initialize-Checkpoint -CheckpointPath "C:\Build\checkpoint.json"
```

#### Test-PhaseComplete
Checks if a build phase is complete.
```powershell
if (Test-PhaseComplete -Phase "InjectDrivers") { ... }
```

#### Save-Checkpoint
Saves current phase completion status.
```powershell
Save-Checkpoint -Phase "InjectDrivers" -Duration ([TimeSpan]::FromSeconds(45))
```

### WIM Functions

#### Mount-GoldISOWIM
Mounts WIM file to specified path.
```powershell
Mount-GoldISOWIM -WIMPath "install.wim" -MountPath "C:\Mount" -Index 1
```

#### Dismount-GoldISOWIM
Dismounts WIM with save option.
```powershell
Dismount-GoldISOWIM -MountPath "C:\Mount" -Save
```

#### Export-GoldISOWIM
Exports WIM with optimal compression.
```powershell
Export-GoldISOWIM -SourcePath "C:\Mount" -OutputPath "installnew.wim"
```

### Build Functions

#### Resolve-OscdimgPath
Finds oscdimg.exe from ADK or cache.
```powershell
$oscdimg = Resolve-OscdimgPath
```

#### Start-BuildProgress
Outputs build progress to console.
```powershell
Start-BuildProgress -Phase "Driver Injection" -PhaseNumber 4 -TotalPhases 10
```

#### Write-BuildProgress
Updates progress bar display.
```powershell
Write-BuildProgress -Phase "Injecting Drivers" -PercentComplete 75
```

### Cleanup Functions

#### Register-GoldISOCleanup
Registers cleanup action to run on script end.
```powershell
Register-GoldISOCleanup -CleanupBlock { Dismount-WindowsImage ... }
```

#### Invoke-GoldISOCleanup
Executes all registered cleanup actions.
```powershell
Invoke-GoldISOCleanup
```

#### Invoke-GoldISOErrorThrow
Throws formatted error with logging.
```powershell
Invoke-GoldISOErrorThrow -Message "Mount failed" -ErrorRecord $_
```