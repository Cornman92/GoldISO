#Requires -Version 5.1
<#
.SYNOPSIS
    Common utilities for GoldISO scripts.
.DESCRIPTION
    Shared functions for logging, validation, and common operations across all GoldISO scripts.
.NOTES
    Import with: Import-Module (Join-Path $PSScriptRoot "Modules\GoldISO-Common.psm1") -Force
#>

# Script-level variables
$script:LogFile = $null
$script:LogInitialized = $false
$script:DebugLoggingEnabled = $false
$script:SystemDataDir = "C:\ProgramData\GoldISO"
$script:CentralLogDir = Join-Path $script:SystemDataDir "Logs"

# Checkpoint / progress state
$script:CheckpointFilePath = $null
$script:CheckpointData = $null
$script:BuildProgressStart = $null

# DotSource External Site Configuration if it exists (requirement: outside project path)
$siteConfig = Join-Path $script:SystemDataDir "Config\SiteConfiguration.ps1"
if (Test-Path $siteConfig) {
    . $siteConfig
}

function Get-GoldISODefaultLogPath {
    [CmdletBinding()]
    param()

    $logFileName = "GoldISO-$(Get-Date -Format 'yyyyMMdd').log"
    $candidateDirs = @(
        $script:CentralLogDir,
        (Join-Path $env:LOCALAPPDATA "GoldISO\Logs"),
        (Join-Path $env:TEMP "GoldISO\Logs"),
        (Join-Path (Get-GoldISORoot) "Logs")
    ) | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Select-Object -Unique

    foreach ($dir in $candidateDirs) {
        try {
            if (-not (Test-Path $dir)) {
                New-Item -ItemType Directory -Path $dir -Force -ErrorAction Stop | Out-Null
            }

            $testFile = Join-Path $dir ".write-test.tmp"
            Set-Content -Path $testFile -Value "test" -Encoding UTF8 -ErrorAction Stop
            Remove-Item -Path $testFile -Force -ErrorAction SilentlyContinue

            return (Join-Path $dir $logFileName)
        }
        catch {
            continue
        }
    }

    return $null
}

<#
.SYNOPSIS
    Initializes the logging system.
.DESCRIPTION
    Sets up the log file path and ensures the log directory exists.
.PARAMETER LogPath
    Full path to the log file.
.EXAMPLE
    Initialize-Logging -LogPath "C:\Scripts\Logs\build.log"
#>
function Initialize-Logging {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$LogPath
    )
    
    $script:LogFile = $LogPath
    $logDir = Split-Path $LogPath -Parent
    
    if ($logDir -and -not (Test-Path $logDir)) {
        New-Item -ItemType Directory -Path $logDir -Force -ErrorAction Stop | Out-Null
    }
    
    $script:LogInitialized = $true
    
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    "[$timestamp] [INIT] Logging initialized: $LogPath" | Set-Content $LogPath -Encoding UTF8 -ErrorAction Stop
}

<#
.SYNOPSIS
    Writes a log message with timestamp and level.
.DESCRIPTION
    Outputs colored messages to console and writes to log file.
    Supports multiple log levels with color coding.
    Standardized log levels: INFO, WARN, WARNING, ERROR, SUCCESS, SKIP, DEBUG
.PARAMETER Message
    The message to log.
.PARAMETER Level
    Log level: INFO, WARN, WARNING, ERROR, SUCCESS, SKIP, DEBUG. Default: INFO.
    Note: WARN and WARNING are aliases (both use Yellow color).
.PARAMETER NoConsole
    Suppress console output (log file only).
.EXAMPLE
    Write-GoldISOLog -Message "Starting build" -Level "INFO"
    Write-GoldISOLog -Message "File not found" -Level "ERROR"
    Write-GoldISOLog -Message "Debug details" -Level "DEBUG" -NoConsole
#>
function Write-GoldISOLog {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Message,

        [ValidateSet("INFO", "WARN", "WARNING", "ERROR", "SUCCESS", "SKIP", "DEBUG")]
        [string]$Level = "INFO",

        [switch]$NoConsole
    )

    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"

    # Normalize WARN/WARNING to WARN for consistent log file formatting
    $normalizedLevel = if ($Level -eq "WARNING") { "WARN" } else { $Level }
    $entry = "[$timestamp] [$normalizedLevel] $Message"

    if (-not $NoConsole) {
        $colorMap = @{
            INFO = "White"
            WARN = "Yellow"
            WARNING = "Yellow"
            ERROR = "Red"
            SUCCESS = "Green"
            SKIP = "Cyan"
            DEBUG = "Gray"
        }
        Write-Host $entry -ForegroundColor $colorMap[$Level]
    }

    # Ensure central logging if not explicitly initialized
    if (-not $script:LogInitialized) {
        $candidateLogPaths = @(
            (Join-Path $script:CentralLogDir "GoldISO-$(Get-Date -Format 'yyyyMMdd').log"),
            (Join-Path (Join-Path $env:LOCALAPPDATA "GoldISO\Logs") "GoldISO-$(Get-Date -Format 'yyyyMMdd').log"),
            (Join-Path (Join-Path $env:TEMP "GoldISO\Logs") "GoldISO-$(Get-Date -Format 'yyyyMMdd').log"),
            (Join-Path (Join-Path (Get-GoldISORoot) "Logs") "GoldISO-$(Get-Date -Format 'yyyyMMdd').log")
        ) | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Select-Object -Unique

        foreach ($candidateLogPath in $candidateLogPaths) {
            try {
                Initialize-Logging -LogPath $candidateLogPath
                break
            }
            catch {
                $script:LogInitialized = $false
                $script:LogFile = $null
            }
        }

        if (-not $script:LogInitialized) {
            return
        }
    }

    # Write to log file (including DEBUG only if explicitly enabled)
    if ($script:LogInitialized -and $script:LogFile) {
        if ($Level -ne "DEBUG" -or $script:DebugLoggingEnabled) {
            Add-Content -Path $script:LogFile -Value $entry -Encoding UTF8 -ErrorAction SilentlyContinue
        }
    }
}

# Alias for backward compatibility and ease of use
Set-Alias -Name "Write-Log" -Value "Write-GoldISOLog" -Scope Global

<#
.SYNOPSIS
    Tests if the current session has Administrator privileges.
.DESCRIPTION
    Returns $true if running as Administrator, otherwise writes error and exits.
.PARAMETER ExitIfNotAdmin
    If specified, exits with code 1 when not running as Administrator.
.EXAMPLE
    Test-GoldISOAdmin -ExitIfNotAdmin
#>
function Test-GoldISOAdmin {
    [CmdletBinding()]
    param(
        [switch]$ExitIfNotAdmin
    )
    
    $isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
        [Security.Principal.WindowsBuiltInRole]::Administrator
    )
    
    if (-not $isAdmin) {
        Write-GoldISOLog -Message "This script requires Administrator privileges" -Level "ERROR"
        if ($ExitIfNotAdmin) {
            exit 1
        }
        return $false
    }
    
    Write-GoldISOLog -Message "Administrator privileges confirmed" -Level "SUCCESS"
    return $true
}

<#
.SYNOPSIS
    Validates that a path exists and is accessible.
.DESCRIPTION
    Checks if a file or directory exists. Optionally creates directories.
.PARAMETER Path
    The path to validate.
.PARAMETER Type
    Type to validate: File, Directory, or Any.
.PARAMETER CreateIfMissing
    Creates the directory if it doesn't exist (for Directory type only).
.EXAMPLE
    Test-GoldISOPath -Path "C:\Scripts" -Type Directory -CreateIfMissing
#>
function Test-GoldISOPath {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path,
        
        [ValidateSet("File", "Directory", "Any")]
        [string]$Type = "Any",
        
        [switch]$CreateIfMissing
    )
    
    if (Test-Path $Path) {
        $item = Get-Item $Path
        
        switch ($Type) {
            "File" {
                if (-not $item.PSIsContainer) {
                    return $true
                }
            }
            "Directory" {
                if ($item.PSIsContainer) {
                    return $true
                }
            }
            "Any" { return $true }
        }
        
        Write-GoldISOLog -Message "Path exists but is wrong type: $Path (expected $Type)" -Level "ERROR"
        return $false
    }
    
    if ($CreateIfMissing -and $Type -eq "Directory") {
        try {
            New-Item -ItemType Directory -Path $Path -Force | Out-Null
            Write-GoldISOLog -Message "Created directory: $Path" -Level "SUCCESS"
            return $true
        }
        catch {
            Write-GoldISOLog -Message "Failed to create directory: $Path" -Level "ERROR"
            return $false
        }
    }
    
    Write-GoldISOLog -Message "Path not found: $Path" -Level "ERROR"
    return $false
}

<#
.SYNOPSIS
    Formats bytes to human-readable size.
.DESCRIPTION
    Converts byte values to KB, MB, GB, or TB as appropriate.
.PARAMETER Bytes
    The byte value to format.
.PARAMETER DecimalPlaces
    Number of decimal places to show. Default: 2.
.EXAMPLE
    Format-GoldISOSize -Bytes 1073741824
    # Returns: "1.00 GB"
#>
function Format-GoldISOSize {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [long]$Bytes,
        
        [int]$DecimalPlaces = 2
    )
    
    $units = @("B", "KB", "MB", "GB", "TB")
    $unitIndex = 0
    $size = [double]$Bytes
    
    while ($size -ge 1024 -and $unitIndex -lt $units.Count - 1) {
        $size /= 1024
        $unitIndex++
    }
    
    return "{0:N$DecimalPlaces} {1}" -f $size, $units[$unitIndex]
}

<#
.SYNOPSIS
    Tests if running in Windows PE environment.
.DESCRIPTION
    Detects WinPE through multiple methods for reliability.
.EXAMPLE
    if (Test-GoldISOWinPE) { Write-Host "In WinPE" }
#>
function Test-GoldISOWinPE {
    [CmdletBinding()]
    param()
    
    # Method 1: Check for WinPE.exe
    if (Test-Path "X:\Windows\System32\WinPE.exe" -ErrorAction SilentlyContinue) {
        return $true
    }
    
    # Method 2: Check registry EditionID
    try {
        $edition = (Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion" -Name "EditionID" -ErrorAction Stop).EditionID
        if ($edition -eq "WindowsPE") {
            return $true
        }
    }
    catch { }
    
    # Method 3: Check for MiniNT key (WinPE marker)
    if (Test-Path "HKLM:\SYSTEM\CurrentControlSet\Control\MiniNT" -ErrorAction SilentlyContinue) {
        return $true
    }
    
    return $false
}

<#
.SYNOPSIS
    Gets the GoldISO base directory.
.DESCRIPTION
    Returns the path to the GoldISO project root, detecting from various locations.
.EXAMPLE
    $goldISO = Get-GoldISORoot
#>
function Get-GoldISORoot {
    [CmdletBinding()]
    param()

    # Module lives at Scripts/Modules/GoldISO-Common.psm1
    # Project root is two levels up from the module file.
    $candidatePaths = @(
        (Join-Path $PSScriptRoot "..\.."),  # Scripts/Modules -> Scripts -> ProjectRoot
        (Join-Path $PSScriptRoot ".."),     # if module is directly in Scripts/
        $PSScriptRoot                       # fallback: module dir itself
    )

    # Reliable project root markers (in priority order)
    $markers = @(
        "Docs\CLAUDE.md",
        "Config\autounattend.xml",
        "Scripts\Modules\GoldISO-Common.psm1",
        "autounattend.xml"
    )

    foreach ($path in $candidatePaths) {
        $resolvedPath = Resolve-Path $path -ErrorAction SilentlyContinue
        if (-not $resolvedPath) { continue }

        foreach ($marker in $markers) {
            if (Test-Path (Join-Path $resolvedPath $marker)) {
                return $resolvedPath.Path
            }
        }
    }

    # Final fallback: return two levels up (best guess)
    $fallback = Resolve-Path (Join-Path $PSScriptRoot "..\..") -ErrorAction SilentlyContinue
    return if ($fallback) { $fallback.Path } else { $PSScriptRoot }
}

<#
.SYNOPSIS
    Executes a command with timeout and captures output.
.DESCRIPTION
    Runs a process with specified timeout and returns exit code and output.
.PARAMETER FilePath
    Executable to run.
.PARAMETER ArgumentList
    Arguments for the executable.
.PARAMETER TimeoutSeconds
    Maximum time to wait. Default: 3600 (1 hour).
.EXAMPLE
    Invoke-GoldISOCommand -FilePath "dism.exe" -ArgumentList @("/Get-ImageInfo", "/ImageFile:test.wim")
#>
function Invoke-GoldISOCommand {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$FilePath,
        
        [string[]]$ArgumentList = @(),
        
        [int]$TimeoutSeconds = 3600
    )
    
    $output = [System.Collections.Generic.List[string]]::new()
    
    try {
        $psi = New-Object System.Diagnostics.ProcessStartInfo
        $psi.FileName = $FilePath
        $psi.Arguments = $ArgumentList -join " "
        $psi.RedirectStandardOutput = $true
        $psi.RedirectStandardError = $true
        $psi.UseShellExecute = $false
        $psi.CreateNoWindow = $true
        
        $process = New-Object System.Diagnostics.Process
        $process.StartInfo = $psi
        
        # Event handlers for output
        $stdoutHandler = {
            if (-not [string]::IsNullOrWhiteSpace($EventArgs.Data)) {
                $output.Add($EventArgs.Data)
            }
        }
        $stderrHandler = {
            if (-not [string]::IsNullOrWhiteSpace($EventArgs.Data)) {
                $output.Add("[STDERR] $($EventArgs.Data)")
            }
        }
        
        Register-ObjectEvent -InputObject $process -EventName OutputDataReceived -Action $stdoutHandler | Out-Null
        Register-ObjectEvent -InputObject $process -EventName ErrorDataReceived -Action $stderrHandler | Out-Null
        
        $process.Start() | Out-Null
        $process.BeginOutputReadLine()
        $process.BeginErrorReadLine()
        
        # Wait with timeout
        $completed = $process.WaitForExit($TimeoutSeconds * 1000)
        
        if (-not $completed) {
            $process.Kill()
            Write-GoldISOLog -Message "Command timed out after $TimeoutSeconds seconds: $FilePath" -Level "ERROR"
            return @{ ExitCode = -1; Output = $output; TimedOut = $true }
        }
        
        # Allow time for async output
        Start-Sleep -Milliseconds 500
        
        return @{ ExitCode = $process.ExitCode; Output = $output; TimedOut = $false }
    }
    catch {
        Write-GoldISOLog -Message "Failed to execute command: $_" -Level "ERROR"
        return @{ ExitCode = -1; Output = $output; TimedOut = $false; Error = $_ }
    }
}

function Get-ComponentHash {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path,
        
        [ValidateSet("MD5", "SHA1", "SHA256")]
        [string]$Algorithm = "SHA256"
    )
    
    if (-not (Test-Path $Path)) {
        Write-GoldISOLog -Message "Path not found: $Path" -Level "ERROR"
        return $null
    }
    
    try {
        $hash = Get-FileHash -Path $Path -Algorithm $Algorithm -ErrorAction Stop
        return $hash.Hash
    }
    catch {
        $errMsg = $_.Exception.Message
        Write-GoldISOLog -Message "Failed to hash $Path`: $errMsg" -Level "ERROR"
        return $null
    }
}

function Test-DiskTopology {
    [CmdletBinding()]
    param(
        [int]$ExpectedDiskCount = 3,
        [int]$ExpectedUnallocatedGB = 90,
        [int]$TargetDiskNumber = 2
    )
    
    $disks = Get-Disk | Where-Object { $_.OperationalStatus -eq "Online" }
    $diskCount = $disks.Count
    
    $result = [PSCustomObject]@{
        DiskCount = $diskCount
        ExpectedDiskCount = $ExpectedDiskCount
        TargetDiskNumber = $TargetDiskNumber
        DiskCountValid = ($diskCount -ge $ExpectedDiskCount)
        UnallocatedGB = 0
        UnallocatedValid = $false
        PartitionsValid = $false
        IsValid = $false
    }
    
    $targetDisk = $disks | Where-Object { $_.Number -eq $TargetDiskNumber } | Select-Object -First 1
    
    if ($targetDisk) {
        $result.UnallocatedGB = [math]::Round($targetDisk.AllocatedSize / 1GB, 0)
        
        $partitioning = Get-Partition -DiskNumber $TargetDiskNumber -ErrorAction SilentlyContinue
        $result.PartitionsValid = ($partitioning.Count -ge 2)
        $result.UnallocatedValid = ($result.UnallocatedGB -ge $ExpectedUnallocatedGB)
    }
    
    $result.IsValid = $result.DiskCountValid -and $result.UnallocatedValid -and $result.PartitionsValid
    
    return $result
}

function Import-BuildManifest {
    [CmdletBinding()]
    param(
        [string]$Path = ""
    )
    
    $ProjectRoot = Split-Path $PSScriptRoot -Parent
    if (-not $Path) {
        $Path = Join-Path $ProjectRoot "Config\build-manifest.json"
    }
    
    if (-not (Test-Path $Path)) {
        Write-GoldISOLog -Message "Build manifest not found: $Path" -Level "ERROR"
        return $null
    }
    
    try {
        $content = Get-Content $Path -Raw -ErrorAction Stop
        return $content | ConvertFrom-Json
    }
    catch {
        Write-GoldISOLog -Message "Failed to parse build manifest: $_" -Level "ERROR"
        return $null
    }
}

function Export-BuildManifest {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [object]$Manifest,
        
        [string]$Path = ""
    )
    
    $ProjectRoot = Split-Path $PSScriptRoot -Parent
    if (-not $Path) {
        $Path = Join-Path $ProjectRoot "Config\build-manifest.json"
    }
    
    try {
        $json = $Manifest | ConvertTo-Json -Depth 10 -ErrorAction Stop
        Set-Content -Path $Path -Value $json -Encoding UTF8 -ErrorAction Stop
        Write-GoldISOLog -Message "Build manifest saved: $Path" -Level "SUCCESS"
        return $true
    }
    catch {
        Write-GoldISOLog -Message "Failed to save build manifest: $_" -Level "ERROR"
        return $false
    }
}

<#
.SYNOPSIS
    Starts transcript logging for a script.
.DESCRIPTION
    Begins logging all output to a transcript file in the Logs directory.
.PARAMETER ScriptName
    Name of the script for the transcript file.
.EXAMPLE
    Start-GoldISOTranscript -ScriptName "Build-GoldISO"
#>
function Start-GoldISOTranscript {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$ScriptName
    )
    
    $logDir = Join-Path (Get-GoldISORoot) "Scripts\Logs"
    if (-not (Test-Path $logDir)) {
        New-Item -ItemType Directory -Path $logDir -Force | Out-Null
    }
    
    $timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
    $transcriptPath = Join-Path $logDir "${ScriptName}-${timestamp}.log"
    
    try {
        Start-Transcript -Path $transcriptPath -Force -ErrorAction Stop | Out-Null
        Write-GoldISOLog -Message "Transcript started: $transcriptPath" -Level "INFO"
        return $transcriptPath
    }
    catch {
        Write-GoldISOLog -Message "Failed to start transcript: $_" -Level "WARN"
        return $null
    }
}

<#
.SYNOPSIS
    Stops transcript logging.
.DESCRIPTION
    Stops the active transcript if one exists.
.EXAMPLE
    Stop-GoldISOTranscript
#>
function Stop-GoldISOTranscript {
    [CmdletBinding()]
    param()
    
    try {
        Stop-Transcript -ErrorAction SilentlyContinue | Out-Null
        Write-GoldISOLog -Message "Transcript stopped" -Level "INFO"
    }
    catch {
        # Transcript may not be running, ignore error
    }
}

<#
.SYNOPSIS
    Validates available disk space.
.DESCRIPTION
    Checks if the specified drive has sufficient free space.
.PARAMETER Drive
    Drive letter to check (e.g., "C").
.PARAMETER RequiredGB
    Required free space in gigabytes.
.PARAMETER CreateIfMissing
    Creates the directory if it doesn't exist (for Directory type only).
.EXAMPLE
    Test-GoldISODiskSpace -Drive "C" -RequiredGB 50
#>
function Test-GoldISODiskSpace {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Drive,
        
        [Parameter(Mandatory = $true)]
        [int]$RequiredGB
    )
    
    $drivePath = "$Drive`:"
    $volume = Get-CimInstance -ClassName Win32_LogicalDisk -Filter "DeviceID='$drivePath'" -ErrorAction SilentlyContinue
    
    if (-not $volume) {
        Write-GoldISOLog -Message "Could not query drive $drivePath" -Level "ERROR"
        return $false
    }
    
    $freeGB = [math]::Round($volume.FreeSpace / 1GB, 2)
    $totalGB = [math]::Round($volume.Size / 1GB, 2)
    
    if ($freeGB -lt $RequiredGB) {
        Write-GoldISOLog -Message "Insufficient disk space on $drivePath`: ${freeGB}GB free, ${RequiredGB}GB required" -Level "ERROR"
        return $false
    }
    
    Write-GoldISOLog -Message "Disk space check passed: ${freeGB}GB free of ${totalGB}GB on $drivePath" -Level "SUCCESS"
    return $true
}

<#
.SYNOPSIS
    Validates that required external commands are available.
.DESCRIPTION
    Checks if required executables (dism, oscdimg, etc.) are in PATH or common locations.
.PARAMETER Command
    Name of the command to check.
.PARAMETER AlternativePaths
    Array of alternative paths to check if not in PATH.
.EXAMPLE
    Test-GoldISOCommand -Command "dism"
    Test-GoldISOCommand -Command "oscdimg" -AlternativePaths @("${env:ProgramFiles(x86)}\Windows Kits\10\Assessment and Deployment Kit\Deployment Tools\amd64\Oscdimg\oscdimg.exe")
#>
function Test-GoldISOCommand {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Command,
        
        [string[]]$AlternativePaths = @()
    )
    
    # Check if command is in PATH
    $cmd = Get-Command $Command -ErrorAction SilentlyContinue
    if ($cmd) {
        Write-GoldISOLog -Message "$Command available at: $($cmd.Source)" -Level "SUCCESS"
        return @{ Available = $true; Path = $cmd.Source }
    }
    
    # Check alternative paths
    foreach ($path in $AlternativePaths) {
        if (Test-Path $path) {
            Write-GoldISOLog -Message "$Command found at: $path" -Level "SUCCESS"
            return @{ Available = $true; Path = $path }
        }
    }
    
    Write-GoldISOLog -Message "$Command not found in PATH or common locations" -Level "ERROR"
    return @{ Available = $false; Path = $null }
}

<#
.SYNOPSIS
    Creates and throws a terminating error with proper formatting.
.DESCRIPTION
    Creates and throws a terminating error record for critical failures.
.PARAMETER Message
    Error message.
.PARAMETER ErrorId
    Error identifier for categorization.
.EXAMPLE
    Invoke-GoldISOErrorThrow -Message "Failed to mount WIM" -ErrorId "MountFailure"
#>
function Invoke-GoldISOErrorThrow {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Message,
        
        [string]$ErrorId = "GoldISOError"
    )
    
    Write-GoldISOLog -Message $Message -Level "ERROR"
    $exception = New-Object System.Exception $Message
    $errorRecord = New-Object System.Management.Automation.ErrorRecord $exception, $ErrorId, "OperationStopped", $null
    throw $errorRecord
}

<#
.SYNOPSIS
    Registers a cleanup action to run on script exit.
.DESCRIPTION
    Sets up a trap to execute cleanup code when the script exits or errors.
.PARAMETER ScriptBlock
    Code to execute for cleanup.
.EXAMPLE
    Register-GoldISOCleanup -ScriptBlock { Dismount-Image }
#>
function Register-GoldISOCleanup {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [scriptblock]$ScriptBlock
    )
    
    $script:CleanupActions = $script:CleanupActions + $ScriptBlock
}

<#
.SYNOPSIS
    Executes all registered cleanup actions.
.DESCRIPTION
    Runs all cleanup script blocks registered with Register-GoldISOCleanup.
.EXAMPLE
    Invoke-GoldISOCleanup
#>
function Invoke-GoldISOCleanup {
    [CmdletBinding()]
    param()
    
    if ($script:CleanupActions) {
        Write-GoldISOLog -Message "Running cleanup actions..." -Level "INFO"
        foreach ($action in $script:CleanupActions) {
            try {
                & $action
            }
            catch {
                Write-GoldISOLog -Message "Cleanup action failed: $_" -Level "WARN"
            }
        }
    }
}

<#
.SYNOPSIS
    Initializes the build checkpoint system.
.DESCRIPTION
    Loads an existing checkpoint file (resuming) or creates a fresh one.
    Returns $true when resuming from a previously interrupted build.
.PARAMETER CheckpointPath
    Path to the checkpoint JSON file. Defaults to Logs\build.checkpoint.json
    under the project root.
.EXAMPLE
    $resuming = Initialize-Checkpoint -CheckpointPath "C:\Build\checkpoint.json"
#>
function Initialize-Checkpoint {
    [CmdletBinding()]
    param(
        [string]$CheckpointPath = ""
    )

    if (-not $CheckpointPath) {
        $root = Get-GoldISORoot
        $CheckpointPath = Join-Path $root "Logs\build.checkpoint.json"
    }

    $script:CheckpointFilePath = $CheckpointPath

    if (Test-Path $CheckpointPath) {
        try {
            $raw = Get-Content $CheckpointPath -Raw -ErrorAction Stop | ConvertFrom-Json
            # Convert Phases PSCustomObject → hashtable for ContainsKey support
            $phases = @{}
            if ($raw.Phases) {
                $raw.Phases.PSObject.Properties | ForEach-Object { $phases[$_.Name] = $_.Value }
            }
            $script:CheckpointData = @{
                StartTime = $raw.StartTime
                Phases    = $phases
            }
            $phaseCount = $phases.Count
            Write-GoldISOLog "Loaded checkpoint with $phaseCount completed phase(s): $CheckpointPath" "INFO"
            return $true
        }
        catch {
            Write-GoldISOLog "Checkpoint file unreadable, starting fresh: $_" "WARN"
        }
    }

    # Fresh start — ensure directory exists
    $checkpointDir = Split-Path $CheckpointPath -Parent
    if ($checkpointDir -and -not (Test-Path $checkpointDir)) {
        New-Item -ItemType Directory -Path $checkpointDir -Force | Out-Null
    }

    $script:CheckpointData = @{
        StartTime = (Get-Date -Format "o")
        Phases    = @{}
    }

    try {
        $script:CheckpointData | ConvertTo-Json -Depth 5 |
            Set-Content $CheckpointPath -Encoding UTF8 -ErrorAction Stop
    }
    catch {
        Write-GoldISOLog "Could not write checkpoint file: $_" "WARN"
    }

    Write-GoldISOLog "Checkpoint initialized: $CheckpointPath" "INFO"
    return $false
}

<#
.SYNOPSIS
    Tests whether a build phase has already been completed.
.DESCRIPTION
    Returns $true when the named phase exists in the loaded checkpoint data.
    Always returns $false if Initialize-Checkpoint has not been called yet.
.PARAMETER Phase
    Phase name, e.g. "Initialize", "InjectDrivers".
.EXAMPLE
    if (-not (Test-PhaseComplete "InjectDrivers")) { ... }
#>
function Test-PhaseComplete {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Phase
    )

    if (-not $script:CheckpointData) { return $false }
    return $script:CheckpointData.Phases.ContainsKey($Phase)
}

<#
.SYNOPSIS
    Records a completed build phase to the checkpoint file.
.DESCRIPTION
    Adds an entry for the phase (with completion timestamp and duration) and
    immediately persists the checkpoint JSON to disk.
.PARAMETER Phase
    Phase name to mark complete.
.PARAMETER Duration
    Elapsed time for the phase (TimeSpan).
.EXAMPLE
    Save-Checkpoint -Phase "InjectDrivers" -Duration ((Get-Date) - $phaseStart)
#>
function Save-Checkpoint {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Phase,

        [Parameter(Mandatory = $true)]
        [timespan]$Duration
    )

    if (-not $script:CheckpointData) {
        Write-GoldISOLog "Checkpoint not initialized - call Initialize-Checkpoint first" "WARN"
        return
    }

    $script:CheckpointData.Phases[$Phase] = @{
        CompletedAt     = (Get-Date -Format "o")
        DurationSeconds = [math]::Round($Duration.TotalSeconds, 1)
    }

    if ($script:CheckpointFilePath) {
        try {
            $script:CheckpointData | ConvertTo-Json -Depth 5 |
                Set-Content $script:CheckpointFilePath -Encoding UTF8 -ErrorAction Stop
        }
        catch {
            Write-GoldISOLog "Failed to persist checkpoint: $_" "WARN"
        }
    }

    $durSec = [math]::Round($Duration.TotalSeconds)
    Write-GoldISOLog -Message "Checkpoint saved - phase '$Phase' done in ${durSec}s" -Level "INFO"
}

<#
.SYNOPSIS
    Starts the build progress timer.
.DESCRIPTION
    Records the start time used by Write-BuildProgress to compute elapsed time.
    Call once at the beginning of a build before the first Write-BuildProgress.
.EXAMPLE
    Start-BuildProgress
#>
function Start-BuildProgress {
    [CmdletBinding()]
    param()

    $script:BuildProgressStart = Get-Date
    Write-GoldISOLog "Build progress tracking started" "INFO"
}

<#
.SYNOPSIS
    Updates the PowerShell progress bar for the current build phase.
.DESCRIPTION
    Writes a Write-Progress update and logs the phase transition.
    Percent complete is capped at 99 until the build finishes.
.PARAMETER Phase
    Human-readable phase name shown in the status line.
.PARAMETER PhaseNumber
    Current phase number (0-based start is fine).
.PARAMETER TotalPhases
    Total number of phases in the build pipeline.
.EXAMPLE
    Write-BuildProgress -Phase "Driver Injection" -PhaseNumber 4 -TotalPhases 10
#>
function Write-BuildProgress {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Phase,

        [Parameter(Mandatory = $true)]
        [int]$PhaseNumber,

        [Parameter(Mandatory = $true)]
        [int]$TotalPhases
    )

    $pct = if ($TotalPhases -gt 0) {
        [math]::Min([math]::Round(($PhaseNumber / $TotalPhases) * 100), 99)
    } else { 0 }

    $elapsed = if ($script:BuildProgressStart) {
        "$([math]::Round(((Get-Date) - $script:BuildProgressStart).TotalMinutes, 1))m"
    } else { "0m" }

    Write-Progress -Activity "GoldISO Build" `
        -Status "[$PhaseNumber/$TotalPhases] $Phase - ${elapsed} elapsed" `
        -PercentComplete $pct

    Write-GoldISOLog "[$PhaseNumber/$TotalPhases] $Phase" "INFO"
}

<#
.SYNOPSIS
    Mounts a WIM file to a specified directory.
.DESCRIPTION
    Mounts a Windows Imaging Format (WIM) file for offline servicing.
.PARAMETER WIMPath
    Path to the WIM file.
.PARAMETER MountPath
    Directory to mount the WIM.
.PARAMETER Index
    Image index to mount (default: 6 for Windows 11 Pro).
.EXAMPLE
    Mount-GoldISOWIM -WIMPath "C:\ISO\sources\install.wim" -MountPath "C:\Mount" -Index 6
#>
function Mount-GoldISOWIM {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$WIMPath,
        
        [Parameter(Mandatory = $true)]
        [string]$MountPath,
        
        [int]$Index = 6
    )
    
    if (-not (Test-Path $WIMPath)) {
        Write-GoldISOLog -Message "WIM not found: $WIMPath" -Level "ERROR"
        return $false
    }
    
    if (Test-Path $MountPath) {
        # Check if already mounted
        try {
            $mountedImages = Get-WindowsImage -Mounted -ErrorAction Stop | Where-Object { $_.Path -eq $MountPath }
            if ($mountedImages) {
                Write-GoldISOLog -Message "WIM already mounted at $MountPath" -Level "WARN"
                return $true
            }
        }
        catch {
            Write-GoldISOLog -Message "Warning: Could not query mounted images (DISM service may be unavailable): $_" -Level "WARN"
        }
    } else {
        New-Item -ItemType Directory -Path $MountPath -Force | Out-Null
    }
    
    try {
        Write-GoldISOLog -Message "Mounting WIM: $WIMPath (Index: $Index) to $MountPath" -Level "INFO"
        Mount-WindowsImage -ImagePath $WIMPath -Path $MountPath -Index $Index -ErrorAction Stop | Out-Null
        Write-GoldISOLog -Message "WIM mounted successfully" -Level "SUCCESS"
        return $true
    }
    catch {
        Write-GoldISOLog -Message "Failed to mount WIM: $_" -Level "ERROR"
        return $false
    }
}

<#
.SYNOPSIS
    Dismounts a mounted WIM image.
.DESCRIPTION
    Dismounts a previously mounted Windows Imaging Format (WIM) file.
.PARAMETER MountPath
    The mount path of the WIM.
.PARAMETER Save
    Save changes to the WIM (default: $true).
.PARAMETER Discard
    Discard changes without saving (overrides -Save).
.EXAMPLE
    Dismount-GoldISOWIM -MountPath "C:\Mount" -Save
#>
function Dismount-GoldISOWIM {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$MountPath,
        
        [switch]$Discard
    )
    
    $mountedImage = Get-WindowsImage -Mounted -ErrorAction SilentlyContinue | Where-Object { $_.Path -eq $MountPath }
    if (-not $mountedImage) {
        Write-GoldISOLog -Message "No WIM mounted at $MountPath" -Level "WARN"
        return $true
    }
    
    try {
        if ($Discard) {
            Write-GoldISOLog -Message "Dismounting WIM and discarding changes..." -Level "INFO"
            Dismount-WindowsImage -Path $MountPath -Discard -ErrorAction SilentlyContinue | Out-Null
            Write-GoldISOLog -Message "WIM unmounted (discarded)" -Level "SUCCESS"
        } else {
            Write-GoldISOLog -Message "Dismounting WIM and saving changes..." -Level "INFO"
            Dismount-WindowsImage -Path $MountPath -Save -ErrorAction Stop | Out-Null
            Write-GoldISOLog -Message "WIM unmounted and saved" -Level "SUCCESS"
        }
        return $true
    }
    catch {
        Write-GoldISOLog -Message "Failed to dismount WIM: $_" -Level "ERROR"
        return $false
    }
}

<#
.SYNOPSIS
    Exports a WIM to a new file with compression.
.DESCRIPTION
    Exports a Windows image to optimize size and enable compression.
.PARAMETER SourceWIM
    Source WIM file path.
.PARAMETER DestWIM
    Destination WIM file path.
.PARAMETER Index
    Image index to export (default: 6).
.PARAMETER Compression
    Compression type: None, Fast, or Maximum (default: Maximum).
.EXAMPLE
    Export-GoldISOWIM -SourceWIM "install.wim" -DestWIM "optimized.wim" -Index 6 -Compression Maximum
#>
function Export-GoldISOWIM {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$SourceWIM,
        
        [Parameter(Mandatory = $true)]
        [string]$DestWIM,
        
        [int]$Index = 6,
        
        [ValidateSet("None", "Fast", "Maximum")]
        [string]$Compression = "Maximum"
    )
    
    if (-not (Test-Path $SourceWIM)) {
        Write-GoldISOLog -Message "Source WIM not found: $SourceWIM" -Level "ERROR"
        return $false
    }
    
    try {
        Write-GoldISOLog -Message "Exporting WIM with $Compression compression..." -Level "INFO"
        Export-WindowsImage -SourceImagePath $SourceWIM -SourceIndex $Index `
            -DestinationImagePath $DestWIM -CompressionType $Compression `
            -ErrorAction Stop | Out-Null
        
        if (-not (Test-Path $DestWIM)) {
            throw "Export failed - destination WIM not created"
        }
        $wimSize = [math]::Round((Get-Item $DestWIM).Length / 1GB, 2)
        Write-GoldISOLog -Message "WIM exported: $DestWIM ($wimSize GB)" -Level "SUCCESS"
        return $true
    }
    catch {
        Write-GoldISOLog -Message "WIM export failed: $_" -Level "ERROR"
        return $false
    }
}

<#
.SYNOPSIS
    Mounts an ISO image and returns the drive letter.
.DESCRIPTION
    Mounts an ISO disk image and returns the assigned drive letter.
.PARAMETER ISOPath
    Path to the ISO file.
.PARAMETER AllowAlreadyMounted
    Return existing mount if ISO is already mounted.
.EXAMPLE
    $drive = Mount-GoldISOImage -ISOPath "C:\Source\Windows11.iso"
#>
function Mount-GoldISOImage {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$ISOPath,
        
        [switch]$AllowAlreadyMounted
    )
    
    if (-not (Test-Path $ISOPath)) {
        Write-GoldISOLog -Message "ISO not found: $ISOPath" -Level "ERROR"
        return $null
    }
    
    # Check if already mounted
    $mounted = Get-DiskImage -ImagePath $ISOPath -ErrorAction SilentlyContinue
    if ($mounted -and $mounted.Attached) {
        $driveLetter = ($mounted | Get-Volume).DriveLetter
        if ($driveLetter) {
            if ($AllowAlreadyMounted) {
                Write-GoldISOLog -Message "ISO already mounted at drive: $driveLetter" -Level "WARN"
                return $driveLetter
            } else {
                Write-GoldISOLog -Message "ISO already mounted, reusing drive: $driveLetter" -Level "INFO"
                return $driveLetter
            }
        }
    }
    
    try {
        Write-GoldISOLog -Message "Mounting ISO: $([System.IO.Path]::GetFileName($ISOPath))" -Level "INFO"
        $image = Mount-DiskImage -ImagePath $ISOPath -PassThru -ErrorAction Stop
        $driveLetter = ($image | Get-Volume).DriveLetter
        Write-GoldISOLog -Message "ISO mounted at drive: $driveLetter`:" -Level "SUCCESS"
        return $driveLetter
    }
    catch {
        Write-GoldISOLog -Message "Failed to mount ISO: $_" -Level "ERROR"
        return $null
    }
}

<#
.SYNOPSIS
    Dismounts an ISO image.
.DESCRIPTION
    Dismounts a previously mounted ISO disk image.
.PARAMETER ISOPath
    Path to the ISO file, or $null to dismount all.
.PARAMETER IgnoreErrors
    Suppress error messages if ISO is not mounted.
.EXAMPLE
    Dismount-GoldISOImage -ISOPath "C:\Source\Windows11.iso"
#>
function Dismount-GoldISOImage {
    [CmdletBinding()]
    param(
        [string]$ISOPath,
        
        [switch]$IgnoreErrors
    )
    
    try {
        if ($ISOPath) {
            $image = Get-DiskImage -ImagePath $ISOPath -ErrorAction SilentlyContinue
            if ($image -and $image.Attached) {
                Dismount-DiskImage -ImagePath $ISOPath -ErrorAction Stop | Out-Null
                Write-GoldISOLog -Message "ISO dismounted: $([System.IO.Path]::GetFileName($ISOPath))" -Level "SUCCESS"
            } else {
                if (-not $IgnoreErrors) {
                    Write-GoldISOLog -Message "ISO was not mounted: $([System.IO.Path]::GetFileName($ISOPath))" -Level "WARN"
                }
            }
        } else {
            # Dismount all mounted ISOs
            $mountedISOs = Get-DiskImage | Where-Object { $_.ImageType -eq 'ISO' -and $_.Attached }
            foreach ($iso in $mountedISOs) {
                Dismount-DiskImage -ImagePath $iso.ImagePath -ErrorAction SilentlyContinue | Out-Null
                Write-GoldISOLog -Message "Dismounted: $([System.IO.Path]::GetFileName($iso.ImagePath))" -Level "INFO"
            }
        }
        return $true
    }
    catch {
        if (-not $IgnoreErrors) {
            Write-GoldISOLog -Message "Failed to dismount ISO: $_" -Level "WARN"
        }
        return $false
    }
}

<#
.SYNOPSIS
    Copies ISO contents to a destination directory.
.DESCRIPTION
    Copies all files from a mounted ISO drive to a destination directory.
.PARAMETER SourceDrive
    Drive letter of the mounted ISO (e.g., "D").
.PARAMETER DestDir
    Destination directory path.
.PARAMETER VerifyWIM
    Verify that install.wim exists after copy (default: $true).
.EXAMPLE
    Copy-GoldISOContents -SourceDrive "D" -DestDir "C:\ISO\Contents"
#>
function Copy-GoldISOContents {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$SourceDrive,
        
        [Parameter(Mandatory = $true)]
        [string]$DestDir,
        
        [switch]$SkipWIMVerification
    )
    
    $drivePath = "$SourceDrive`:\"
    if (-not (Test-Path $drivePath)) {
        Write-GoldISOLog -Message "Source drive not found: $drivePath" -Level "ERROR"
        return $false
    }
    
    if (-not (Test-Path $DestDir)) {
        New-Item -ItemType Directory -Path $DestDir -Force | Out-Null
    }
    
    try {
        Write-GoldISOLog -Message "Copying ISO contents from ${SourceDrive}:\ to $DestDir..." -Level "INFO"
        robocopy $drivePath $DestDir /E /R:3 /W:5 /NP /NFL /NDL | Out-Null
        # Robocopy exit codes: 0-7 = success, 8+ = error
        if ($LASTEXITCODE -ge 8) {
            throw "Robocopy failed with exit code $LASTEXITCODE"
        }
        
        if (-not $SkipWIMVerification) {
            $wimPath = Join-Path $DestDir "sources\install.wim"
            if (Test-Path $wimPath) {
                $sizeGB = [math]::Round((Get-Item $wimPath).Length / 1GB, 2)
                Write-GoldISOLog -Message "ISO contents copied successfully (install.wim: $sizeGB GB)" -Level "SUCCESS"
                return $true
            } else {
                Write-GoldISOLog -Message "install.wim not found after copy" -Level "ERROR"
                return $false
            }
        } else {
            Write-GoldISOLog -Message "ISO contents copied successfully" -Level "SUCCESS"
            return $true
        }
    }
    catch {
        Write-GoldISOLog -Message "Failed to copy ISO contents: $_" -Level "ERROR"
        return $false
    }
}

<#
.SYNOPSIS
    Creates a bootable ISO from source directory contents.
.DESCRIPTION
    Uses oscdimg.exe to create a bootable ISO image from prepared source files.
.PARAMETER SourceDir
    Directory containing ISO source files (must include boot files).
.PARAMETER OutputPath
    Full path for the output ISO file.
.PARAMETER Label
    Volume label for the ISO (default: "GAMEROS").
.PARAMETER OscdimgPath
    Optional: Path to oscdimg.exe (auto-detected if not specified).
.EXAMPLE
    New-GoldISOImage -SourceDir "C:\ISO\Source" -OutputPath "C:\Output\GamerOS.iso"
#>
function New-GoldISOImage {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$SourceDir,
        
        [Parameter(Mandatory = $true)]
        [string]$OutputPath,
        
        [string]$Label = "GAMEROS",
        
        [string]$OscdimgPath
    )
    
    if (-not (Test-Path $SourceDir)) {
        Write-GoldISOLog -Message "Source directory not found: $SourceDir" -Level "ERROR"
        return $false
    }
    
    # Resolve oscdimg path if not provided
    if (-not $OscdimgPath) {
        $OscdimgPath = Resolve-OscdimgPath
    }
    
    if (-not $OscdimgPath -or -not (Test-Path $OscdimgPath)) {
        Write-GoldISOLog -Message "oscdimg.exe not found. Install Windows ADK Deployment Tools." -Level "ERROR"
        return $false
    }
    
    # Verify boot files exist
    $efiBoot = Join-Path $SourceDir "efi\microsoft\boot\efisys.bin"
    $etfsBoot = Join-Path $SourceDir "boot\etfsboot.com"
    
    if (-not (Test-Path $efiBoot)) {
        Write-GoldISOLog -Message "EFI boot file not found: $efiBoot" -Level "ERROR"
        return $false
    }
    
    if (-not (Test-Path $etfsBoot)) {
        Write-GoldISOLog -Message "BIOS boot file not found: $etfsBoot" -Level "ERROR"
        return $false
    }
    
    # Ensure output directory exists
    $outputDir = Split-Path $OutputPath -Parent
    if ([string]::IsNullOrWhiteSpace($outputDir)) {
        $outputDir = "."
    }
    if (-not (Test-Path $outputDir)) {
        New-Item -ItemType Directory -Path $outputDir -Force | Out-Null
    }
    
    try {
        Write-GoldISOLog -Message "Building ISO: $OutputPath" -Level "INFO"
        
        $bootData = "-bootdata:2#p0,e,b$etfsBoot#pEF,e,b$efiBoot"
        & $OscdimgPath $bootData -o -u2 -udfver102 "-l$Label" $SourceDir $OutputPath 2>&1 | Out-Null
        
        if (Test-Path $OutputPath) {
            $sizeGB = [math]::Round((Get-Item $OutputPath).Length / 1GB, 2)
            Write-GoldISOLog -Message "ISO created: $OutputPath ($sizeGB GB)" -Level "SUCCESS"
            return $true
        } else {
            Write-GoldISOLog -Message "ISO creation failed - output file not found" -Level "ERROR"
            return $false
        }
    }
    catch {
        Write-GoldISOLog -Message "ISO creation failed: $_" -Level "ERROR"
        return $false
    }
}

<#
.SYNOPSIS
    Resolves the path to oscdimg.exe.
.DESCRIPTION
    Attempts to find oscdimg.exe in PATH or common Windows ADK installation locations.
.EXAMPLE
    $oscdimg = Resolve-OscdimgPath
#>
function Resolve-OscdimgPath {
    [CmdletBinding()]
    param()
    
    # Check PATH first
    $inPath = Get-Command oscdimg.exe -ErrorAction SilentlyContinue
    if ($inPath) {
        return $inPath.Source
    }
    
    # Common ADK installation paths
    $adkPaths = @(
        "${env:ProgramFiles(x86)}\Windows Kits\10\Assessment and Deployment Kit\Deployment Tools\amd64\Oscdimg\oscdimg.exe",
        "$env:ProgramFiles\Windows Kits\10\Assessment and Deployment Kit\Deployment Tools\amd64\Oscdimg\oscdimg.exe",
        "${env:ProgramFiles(x86)}\Windows Kits\11\Assessment and Deployment Kit\Deployment Tools\amd64\Oscdimg\oscdimg.exe",
        "$env:ProgramFiles\Windows Kits\11\Assessment and Deployment Kit\Deployment Tools\amd64\Oscdimg\oscdimg.exe",
        "${env:ProgramFiles(x86)}\Windows Kits\8.1\Assessment and Deployment Kit\Deployment Tools\amd64\Oscdimg\oscdimg.exe"
    )
    
    foreach ($path in $adkPaths) {
        if (Test-Path $path) {
            return $path
        }
    }
    
    return $null
}

function Set-GoldISODebugLogging {
    [CmdletBinding()]
    param([bool]$Enabled = $true)
    $script:DebugLoggingEnabled = $Enabled
}

# Export all functions
Export-ModuleMember -Function @(
    "Get-GoldISODefaultLogPath",
    "Initialize-Logging",
    "Write-GoldISOLog",
    "Test-GoldISOAdmin",
    "Test-GoldISOPath",
    "Format-GoldISOSize",
    "Test-GoldISOWinPE",
    "Get-GoldISORoot",
    "Invoke-GoldISOCommand",
    "Get-ComponentHash",
    "Test-DiskTopology",
    "Import-BuildManifest",
    "Export-BuildManifest",
    "Start-GoldISOTranscript",
    "Stop-GoldISOTranscript",
    "Test-GoldISODiskSpace",
    "Test-GoldISOCommand",
    "Invoke-GoldISOErrorThrow",
    "Register-GoldISOCleanup",
    "Invoke-GoldISOCleanup",
    "Set-GoldISODebugLogging",
    "Initialize-Checkpoint",
    "Test-PhaseComplete",
    "Save-Checkpoint",
    "Start-BuildProgress",
    "Write-BuildProgress",
    # WIM/ISO Operations
    "Mount-GoldISOWIM",
    "Dismount-GoldISOWIM",
    "Export-GoldISOWIM",
    "Mount-GoldISOImage",
    "Dismount-GoldISOImage",
    "Copy-GoldISOContents",
    "New-GoldISOImage",
    "Resolve-OscdimgPath"
)
