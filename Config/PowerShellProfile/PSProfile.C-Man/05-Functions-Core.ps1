[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingWriteHost', '', Justification = 'UI display functions require Write-Host')]
param()

#region ── File Operations ──────────────────────────────────────

function Find-InFiles {
    <#
    .SYNOPSIS
        Recursive grep/search in files with context and colored output.
    .PARAMETER Pattern
        Regex pattern to search for.
    .PARAMETER Path
        Root directory to search. Defaults to current directory.
    .PARAMETER Include
        File pattern filter (e.g., *.cs, *.ps1).
    .PARAMETER Context
        Lines of context around each match.
    .EXAMPLE
        Find-InFiles -Pattern 'TODO' -Include '*.cs' -Context 2
    #>
    [CmdletBinding()]
    [Alias('fif')]
    param(
        [Parameter(Mandatory, Position = 0)]
        [string]$Pattern,

        [Parameter(Position = 1)]
        [string]$Path = '.',

        [string[]]$Include = @('*'),

        [int]$Context = 0
    )

    $params = @{
        Pattern     = $Pattern
        Path        = $Path
        Recurse     = $true
        Include     = $Include
        ErrorAction = 'SilentlyContinue'
    }
    if ($Context -gt 0) {
        $params['Context'] = $Context
    }

    Select-String @params | ForEach-Object -Process {
        $relativePath = Resolve-Path -Path $_.Path -Relative -ErrorAction SilentlyContinue
        if (-not $relativePath) { $relativePath = $_.Path }
        Write-Host -Object "$relativePath" -ForegroundColor $script:Theme.Accent -NoNewline
        Write-Host -Object ":$($_.LineNumber):" -ForegroundColor $script:Theme.Muted -NoNewline
        Write-Host -Object " $($_.Line.Trim())" -ForegroundColor $script:Theme.Text
    }
}

function Find-File {
    <#
    .SYNOPSIS
        Fast recursive file search by name pattern.
    .PARAMETER Name
        Wildcard pattern for file name.
    .PARAMETER Path
        Root search directory.
    .EXAMPLE
        Find-File -Name '*.sln'
    #>
    [CmdletBinding()]
    [Alias('ff')]
    param(
        [Parameter(Mandatory, Position = 0)]
        [string]$Name,

        [Parameter(Position = 1)]
        [string]$Path = '.'
    )

    Get-ChildItem -Path $Path -Filter $Name -Recurse -File -ErrorAction SilentlyContinue |
        ForEach-Object -Process {
            $relativePath = Resolve-Path -Path $_.FullName -Relative -ErrorAction SilentlyContinue
            if (-not $relativePath) { $relativePath = $_.FullName }
            $sizeKb = [math]::Round($_.Length / 1KB, 1)
            Write-Host -Object "  $relativePath" -ForegroundColor $script:Theme.Text -NoNewline
            Write-Host -Object " (${sizeKb}KB)" -ForegroundColor $script:Theme.Muted
        }
}

function Get-FileHash256 {
    <#
    .SYNOPSIS
        Quick SHA256 hash of a file.
    .PARAMETER Path
        File to hash.
    #>
    [CmdletBinding()]
    [Alias('sha')]
    param(
        [Parameter(Mandatory, Position = 0)]
        [ValidateScript({ Test-Path -Path $_ -PathType Leaf })]
        [string]$Path
    )

    (Get-FileHash -Path $Path -Algorithm SHA256).Hash.ToLower()
}

function Get-DirectorySize {
    <#
    .SYNOPSIS
        Calculate total size of a directory recursively.
    .PARAMETER Path
        Directory to measure.
    .PARAMETER Top
        Show top N largest files.
    #>
    [CmdletBinding()]
    [Alias('dirsize')]
    param(
        [Parameter(Position = 0)]
        [string]$Path = '.',

        [int]$Top = 10
    )

    $tc = $script:Theme
    $files = Get-ChildItem -Path $Path -Recurse -File -Force -ErrorAction SilentlyContinue
    $totalSize = ($files | Measure-Object -Property Length -Sum).Sum
    $totalCount = $files.Count

    $units = @('B', 'KB', 'MB', 'GB', 'TB')
    $unitIndex = 0
    $displaySize = [double]$totalSize
    while ($displaySize -ge 1024 -and $unitIndex -lt ($units.Count - 1)) {
        $displaySize /= 1024
        $unitIndex++
    }

    Write-Host -Object "`n  Total: " -ForegroundColor $tc.Primary -NoNewline
    Write-Host -Object "$([math]::Round($displaySize, 2)) $($units[$unitIndex])" -ForegroundColor $tc.Accent -NoNewline
    Write-Host -Object " ($totalCount files)" -ForegroundColor $tc.Muted

    if ($Top -gt 0) {
        Write-Host -Object "`n  Top $Top largest:" -ForegroundColor $tc.Primary
        $files | Sort-Object -Property Length -Descending | Select-Object -First $Top | ForEach-Object -Process {
            $sizeStr = if ($_.Length -ge 1GB) { "$([math]::Round($_.Length / 1GB, 2)) GB" }
                    elseif ($_.Length -ge 1MB) { "$([math]::Round($_.Length / 1MB, 1)) MB" }
                    else { "$([math]::Round($_.Length / 1KB, 1)) KB" }
            $relativePath = Resolve-Path -Path $_.FullName -Relative -ErrorAction SilentlyContinue
            Write-Host -Object "    $($sizeStr.PadLeft(12))" -ForegroundColor $tc.Warning -NoNewline
            Write-Host -Object "  $relativePath" -ForegroundColor $tc.Text
        }
    }
    Write-Host ''
}

#endregion

#region ── Clipboard Utilities ────────────────────────────────

function Copy-Path {
    <#
    .SYNOPSIS
        Copy current directory path to clipboard.
    #>
    [CmdletBinding()]
    [Alias('cpath')]
    param()

    $currentPath = (Get-Location).Path
    Set-Clipboard -Value $currentPath
    Write-Host -Object "  Copied: $currentPath" -ForegroundColor $script:Theme.Success
}

function Copy-FileContent {
    <#
    .SYNOPSIS
        Copy file contents to clipboard.
    .PARAMETER Path
        File to copy.
    #>
    [CmdletBinding()]
    [Alias('cfile')]
    param(
        [Parameter(Mandatory, Position = 0)]
        [ValidateScript({ Test-Path -Path $_ -PathType Leaf })]
        [string]$Path
    )

    $content = Get-Content -Path $Path -Raw
    Set-Clipboard -Value $content
    $lineCount = ($content -split "`n").Count
    Write-Host -Object "  Copied $lineCount lines from $(Split-Path -Path $Path -Leaf)" -ForegroundColor $script:Theme.Success
}

function Save-ClipboardToFile {
    <#
    .SYNOPSIS
        Save clipboard contents to a file.
    .PARAMETER Path
        Output file path.
    #>
    [CmdletBinding()]
    [Alias('cpaste')]
    param(
        [Parameter(Mandatory, Position = 0)]
        [string]$Path
    )

    Get-Clipboard -Raw | Set-Content -Path $Path -Encoding UTF8
    Write-Host -Object "  Saved clipboard to $Path" -ForegroundColor $script:Theme.Success
}

#endregion

#region ── System Information ─────────────────────────────────

function Get-SystemSummary {
    <#
    .SYNOPSIS
        Quick system information snapshot.
    #>
    [CmdletBinding()]
    [Alias('sysinfo')]
    param()

    $tc = $script:Theme
    $os = Get-CimInstance -ClassName Win32_OperatingSystem
    $cpu = Get-CimInstance -ClassName Win32_Processor | Select-Object -First 1
    $mem = $os
    $uptime = (Get-Date) - $os.LastBootUpTime
    $disk = Get-CimInstance -ClassName Win32_LogicalDisk -Filter "DeviceID='C:'"

    $usedMemPct = [math]::Round((($mem.TotalVisibleMemorySize - $mem.FreePhysicalMemory) / $mem.TotalVisibleMemorySize) * 100, 1)
    $usedDiskPct = [math]::Round((($disk.Size - $disk.FreeSpace) / $disk.Size) * 100, 1)

    Write-Host ''
    Write-Host -Object "  OS:     " -ForegroundColor $tc.Muted -NoNewline
    Write-Host -Object "$($os.Caption) ($($os.Version))" -ForegroundColor $tc.Text
    Write-Host -Object "  CPU:    " -ForegroundColor $tc.Muted -NoNewline
    Write-Host -Object "$($cpu.Name.Trim())" -ForegroundColor $tc.Text
    Write-Host -Object "  RAM:    " -ForegroundColor $tc.Muted -NoNewline
    Write-Host -Object "$([math]::Round($mem.TotalVisibleMemorySize / 1MB, 1)) GB ($usedMemPct% used)" -ForegroundColor $tc.Text
    Write-Host -Object "  Disk C: " -ForegroundColor $tc.Muted -NoNewline
    Write-Host -Object "$([math]::Round($disk.Size / 1GB, 0)) GB ($usedDiskPct% used)" -ForegroundColor $tc.Text
    Write-Host -Object "  Uptime: " -ForegroundColor $tc.Muted -NoNewline
    Write-Host -Object "$($uptime.Days)d $($uptime.Hours)h $($uptime.Minutes)m" -ForegroundColor $tc.Text
    Write-Host -Object "  Host:   " -ForegroundColor $tc.Muted -NoNewline
    Write-Host -Object "$($env:COMPUTERNAME)" -ForegroundColor $tc.Text
    Write-Host ''
}

function Get-PublicIP {
    <#
    .SYNOPSIS
        Returns your public IP address.
    #>
    [CmdletBinding()]
    [Alias('myip')]
    param()

    try {
        $response = Invoke-RestMethod -Uri 'https://api.ipify.org?format=json' -TimeoutSec 5
        Write-Host -Object "  Public IP: $($response.ip)" -ForegroundColor $script:Theme.Accent
    }
    catch {
        Write-Warning -Message "Could not retrieve public IP: $($_.Exception.Message)"
    }
}

function Get-ListeningPorts {
    <#
    .SYNOPSIS
        Show all listening TCP ports with owning process.
    .PARAMETER Port
        Filter by specific port number.
    #>
    [CmdletBinding()]
    [Alias('ports')]
    param(
        [Parameter(Position = 0)]
        [int]$Port
    )

    $connections = Get-NetTCPConnection -State Listen -ErrorAction SilentlyContinue
    if ($Port) {
        $connections = $connections | Where-Object -FilterScript { $_.LocalPort -eq $Port }
    }

    $connections | ForEach-Object -Process {
        $process = Get-Process -Id $_.OwningProcess -ErrorAction SilentlyContinue
        [PSCustomObject]@{
            Port    = $_.LocalPort
            Address = $_.LocalAddress
            PID     = $_.OwningProcess
            Process = if ($process) { $process.ProcessName } else { 'Unknown' }
        }
    } | Sort-Object -Property Port | Format-Table -AutoSize
}

function Stop-ProcessByPort {
    <#
    .SYNOPSIS
        Kill process occupying a specific port.
    .PARAMETER Port
        Port number to free up.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    [Alias('killport')]
    param(
        [Parameter(Mandatory, Position = 0)]
        [int]$Port
    )

    $connection = Get-NetTCPConnection -LocalPort $Port -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($null -eq $connection) {
        Write-Host -Object "  No process found on port $Port" -ForegroundColor $script:Theme.Warning
        return
    }

    $process = Get-Process -Id $connection.OwningProcess -ErrorAction SilentlyContinue
    $processName = if ($process) { $process.ProcessName } else { 'Unknown' }

    if ($PSCmdlet.ShouldProcess("$processName (PID: $($connection.OwningProcess)) on port $Port", 'Stop')) {
        Stop-Process -Id $connection.OwningProcess -Force
        Write-Host -Object "  Killed $processName (PID: $($connection.OwningProcess)) on port $Port" -ForegroundColor $script:Theme.Success
    }
}

#endregion

#region ── Text & Data Utilities ──────────────────────────────

function ConvertTo-PrettyJson {
    <#
    .SYNOPSIS
        Pretty-print JSON from string, file, or pipeline.
    .PARAMETER InputObject
        JSON string or object to format.
    .PARAMETER Depth
        JSON serialization depth.
    #>
    [CmdletBinding()]
    [Alias('pjson')]
    param(
        [Parameter(Mandatory, ValueFromPipeline, Position = 0)]
        [object]$InputObject,

        [int]$Depth = 10
    )

    process {
        if ($InputObject -is [string]) {
            try {
                $InputObject | ConvertFrom-Json | ConvertTo-Json -Depth $Depth
            }
            catch {
                Write-Warning -Message "Invalid JSON: $($_.Exception.Message)"
            }
        }
        else {
            $InputObject | ConvertTo-Json -Depth $Depth
        }
    }
}

function Measure-ScriptBlock {
    <#
    .SYNOPSIS
        Benchmark a script block, running it multiple times.
    .PARAMETER ScriptBlock
        Code to benchmark.
    .PARAMETER Iterations
        Number of iterations.
    .EXAMPLE
        Measure-ScriptBlock { Get-Process } -Iterations 10
    #>
    [CmdletBinding()]
    [Alias('bench')]
    param(
        [Parameter(Mandatory, Position = 0)]
        [scriptblock]$ScriptBlock,

        [int]$Iterations = 5
    )

    $times = [System.Collections.Generic.List[double]]::new()
    for ($i = 0; $i -lt $Iterations; $i++) {
        $sw = [System.Diagnostics.Stopwatch]::StartNew()
        $null = & $ScriptBlock
        $sw.Stop()
        $times.Add($sw.Elapsed.TotalMilliseconds)
    }

    $stats = $times | Measure-Object -Minimum -Maximum -Average
    $tc = $script:Theme
    Write-Host ''
    Write-Host -Object "  Benchmark ($Iterations iterations):" -ForegroundColor $tc.Primary
    Write-Host -Object "    Avg:  $([math]::Round($stats.Average, 2))ms" -ForegroundColor $tc.Text
    Write-Host -Object "    Min:  $([math]::Round($stats.Minimum, 2))ms" -ForegroundColor $tc.Success
    Write-Host -Object "    Max:  $([math]::Round($stats.Maximum, 2))ms" -ForegroundColor $tc.Warning
    Write-Host ''
}

function ConvertFrom-UnixTime {
    <#
    .SYNOPSIS
        Convert Unix timestamp to DateTime.
    .PARAMETER Timestamp
        Unix epoch seconds.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, Position = 0)]
        [long]$Timestamp
    )

    [DateTimeOffset]::FromUnixTimeSeconds($Timestamp).LocalDateTime
}

function ConvertTo-UnixTime {
    <#
    .SYNOPSIS
        Convert DateTime to Unix timestamp.
    .PARAMETER DateTime
        DateTime to convert. Defaults to now.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Position = 0)]
        [DateTime]$DateTime = (Get-Date)
    )

    [DateTimeOffset]::new($DateTime).ToUnixTimeSeconds()
}

function New-Password {
    <#
    .SYNOPSIS
        Generate a cryptographically random password.
    .PARAMETER Length
        Password length.
    .PARAMETER NoSymbols
        Exclude special characters.
    .PARAMETER CopyToClipboard
        Copy result to clipboard.
    #>
    [CmdletBinding()]
    [Alias('genpass')]
    param(
        [Parameter(Position = 0)]
        [ValidateRange(8, 128)]
        [int]$Length = 24,

        [switch]$NoSymbols,

        [switch]$CopyToClipboard
    )

    $chars = 'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789'
    if (-not $NoSymbols) {
        $chars += '!@#$%^&*()-_=+[]{}|;:,.<>?'
    }

    $rng = [System.Security.Cryptography.RandomNumberGenerator]::Create()
    $bytes = [byte[]]::new($Length)
    $rng.GetBytes($bytes)

    $password = -join ($bytes | ForEach-Object -Process { $chars[$_ % $chars.Length] })

    if ($CopyToClipboard) {
        Set-Clipboard -Value $password
        Write-Host -Object '  Password copied to clipboard.' -ForegroundColor $script:Theme.Success
    }

    return $password
}

function New-Guid {
    <#
    .SYNOPSIS
        Generate a new GUID and optionally copy to clipboard.
    .PARAMETER CopyToClipboard
        Copy result to clipboard.
    #>
    [CmdletBinding()]
    [Alias('guid')]
    param(
        [switch]$CopyToClipboard
    )

    $newGuid = [System.Guid]::NewGuid().ToString()
    if ($CopyToClipboard) {
        Set-Clipboard -Value $newGuid
        Write-Host -Object '  GUID copied to clipboard.' -ForegroundColor $script:Theme.Success
    }
    return $newGuid
}

#endregion

#region ── Process Utilities ────────────────────────────────

function Get-TopProcesses {
    <#
    .SYNOPSIS
        Show top processes by CPU or memory usage.
    .PARAMETER SortBy
        Sort by CPU or Memory.
    .PARAMETER Top
        Number of processes to show.
    #>
    [CmdletBinding()]
    [Alias('top')]
    param(
        [Parameter(Position = 0)]
        [ValidateSet('CPU', 'Memory')]
        [string]$SortBy = 'CPU',

        [int]$Top = 15
    )

    $sortProp = if ($SortBy -eq 'CPU') { 'CPU' } else { 'WorkingSet64' }

    Get-Process | Sort-Object -Property $sortProp -Descending | Select-Object -First $Top |
        Format-Table -Property @(
            @{ Label = 'PID'; Expression = { $_.Id }; Width = 8 }
            @{ Label = 'Name'; Expression = { $_.ProcessName }; Width = 25 }
            @{ Label = 'CPU(s)'; Expression = { [math]::Round($_.CPU, 1) }; Width = 10; Alignment = 'Right' }
            @{ Label = 'Mem(MB)'; Expression = { [math]::Round($_.WorkingSet64 / 1MB, 0) }; Width = 10; Alignment = 'Right' }
            @{ Label = 'Handles'; Expression = { $_.HandleCount }; Width = 10; Alignment = 'Right' }
        ) -AutoSize
}

function Find-ProcessByName {
    <#
    .SYNOPSIS
        Search for processes by name pattern.
    .PARAMETER Name
        Wildcard pattern to match.
    #>
    [CmdletBinding()]
    [Alias('pgrep')]
    param(
        [Parameter(Mandatory, Position = 0)]
        [string]$Name
    )

    Get-Process | Where-Object -FilterScript { $_.ProcessName -like "*$Name*" } |
        Format-Table -Property Id, ProcessName, CPU, @{
            Label = 'Mem(MB)'; Expression = { [math]::Round($_.WorkingSet64 / 1MB, 0) }
        } -AutoSize
}

function Stop-ProcessByName {
    <#
    .SYNOPSIS
        Kill all processes matching a name pattern.
    .PARAMETER Name
        Process name pattern to kill.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    [Alias('pkill')]
    param(
        [Parameter(Mandatory, Position = 0)]
        [string]$Name
    )

    $procs = Get-Process | Where-Object -FilterScript { $_.ProcessName -like "*$Name*" }
    foreach ($proc in $procs) {
        if ($PSCmdlet.ShouldProcess("$($proc.ProcessName) (PID: $($proc.Id))", 'Stop')) {
            Stop-Process -Id $proc.Id -Force
            Write-Host -Object "  Killed $($proc.ProcessName) (PID: $($proc.Id))" -ForegroundColor $script:Theme.Warning
        }
    }
}

#endregion

#region ── Environment Variable Helpers ───────────────────────

function Add-ToPath {
    <#
    .SYNOPSIS
        Add a directory to the PATH environment variable.
    .PARAMETER Path
        Directory to add.
    .PARAMETER Scope
        User, Machine, or Process scope.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, Position = 0)]
        [string]$Path,

        [ValidateSet('User', 'Machine', 'Process')]
        [string]$Scope = 'User'
    )

    $currentPath = [Environment]::GetEnvironmentVariable('PATH', $Scope)
    if ($currentPath -split ';' -notcontains $Path) {
        [Environment]::SetEnvironmentVariable('PATH', "$currentPath;$Path", $Scope)
        $env:PATH = "$env:PATH;$Path"
        Write-Host -Object "  Added to $Scope PATH: $Path" -ForegroundColor $script:Theme.Success
    }
    else {
        Write-Host -Object "  Already in PATH: $Path" -ForegroundColor $script:Theme.Muted
    }
}

function Show-Path {
    <#
    .SYNOPSIS
        Display PATH entries one per line, highlighting missing directories.
    #>
    [CmdletBinding()]
    [Alias('showpath')]
    param()

    $tc = $script:Theme
    $pathEntries = $env:PATH -split ';' | Where-Object -FilterScript { $_ -ne '' }
    $index = 0
    foreach ($entry in $pathEntries) {
        $exists = Test-Path -Path $entry -PathType Container
        $statusIcon = if ($exists) { [char]0x2713 } else { [char]0x2717 }
        $statusColor = if ($exists) { $tc.Success } else { $tc.Error }
        $indexStr = "$index".PadLeft(3)
        Write-Host -Object "  $statusIcon $indexStr " -ForegroundColor $statusColor -NoNewline
        Write-Host -Object $entry -ForegroundColor $tc.Text
        $index++
    }
}

#endregion