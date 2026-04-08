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
$script:SystemDataDir = "C:\ProgramData\GoldISO"
$script:CentralLogDir = Join-Path $script:SystemDataDir "Logs"

# DotSource External Site Configuration if it exists (requirement: outside project path)
$siteConfig = Join-Path $script:SystemDataDir "Config\SiteConfiguration.ps1"
if (Test-Path $siteConfig) {
    . $siteConfig
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
        New-Item -ItemType Directory -Path $logDir -Force | Out-Null
    }
    
    $script:LogInitialized = $true
    
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    "[$timestamp] [INIT] Logging initialized: $LogPath" | Set-Content $LogPath -Encoding UTF8
}

<#
.SYNOPSIS
    Writes a log message with timestamp and level.
.DESCRIPTION
    Outputs colored messages to console and writes to log file.
    Supports multiple log levels with color coding.
.PARAMETER Message
    The message to log.
.PARAMETER Level
    Log level: INFO, WARN, ERROR, SUCCESS. Default: INFO.
.PARAMETER NoConsole
    Suppress console output (log file only).
.EXAMPLE
    Write-GoldISOLog -Message "Starting build" -Level "INFO"
    Write-GoldISOLog -Message "File not found" -Level "ERROR"
#>
function Write-GoldISOLog {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Message,
        
        [ValidateSet("INFO", "WARN", "ERROR", "SUCCESS")]
        [string]$Level = "INFO",
        
        [switch]$NoConsole
    )
    
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $entry = "[$timestamp] [$Level] $Message"
    
    if (-not $NoConsole) {
        $colorMap = @{
            INFO = "White"
            WARN = "Yellow"
            ERROR = "Red"
            SUCCESS = "Green"
        }
        Write-Host $entry -ForegroundColor $colorMap[$Level]
    }
    
    # Ensure central logging if not explicitly initialized
    if (-not $script:LogInitialized) {
        $defaultLog = Join-Path $script:CentralLogDir "GoldISO-$(Get-Date -Format 'yyyyMMdd').log"
        Initialize-Logging -LogPath $defaultLog
    }
    
    if ($script:LogInitialized -and $script:LogFile) {
        Add-Content -Path $script:LogFile -Value $entry -Encoding UTF8 -ErrorAction SilentlyContinue
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
    
    $possiblePaths = @(
        (Join-Path $PSScriptRoot "..")
        (Join-Path $PSScriptRoot "..\..")
    )
    
    foreach ($path in $possiblePaths) {
        $resolvedPath = Resolve-Path $path -ErrorAction SilentlyContinue
        if ($resolvedPath -and (Test-Path (Join-Path $resolvedPath "autounattend.xml"))) {
            return $resolvedPath
        }
    }
    
    # Return default even if not found
    return $possiblePaths[0]
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

# Export all functions
Export-ModuleMember -Function @(
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
    "Export-BuildManifest"
)
