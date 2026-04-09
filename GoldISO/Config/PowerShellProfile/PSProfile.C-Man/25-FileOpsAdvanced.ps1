<#
.SYNOPSIS
    Advanced File Operations module for C-Man's PowerShell Profile.
.DESCRIPTION
    Bulk rename engine (regex, sequential, date-based), duplicate finder
    (hash-based), directory tree diff, file watcher with action triggers,
    junction/symlink manager, and large file finder.
.NOTES
    Module: 25-FileOpsAdvanced.ps1
    Requires: PowerShell 5.1+
#>

#region ── Bulk Rename ────────────────────────────────────────────────────────

<#
.SYNOPSIS
    Bulk renames files with regex, sequential, or date-based patterns.
.PARAMETER Path
    Directory containing files to rename.
.PARAMETER Filter
    File filter pattern (e.g. '*.jpg').
.PARAMETER Pattern
    Regex pattern to match in filenames.
.PARAMETER Replacement
    Replacement string (supports regex capture groups).
.PARAMETER Sequential
    Rename files with sequential numbering.
.PARAMETER Prefix
    Prefix for sequential naming.
.PARAMETER DateFormat
    Prepend file date in specified format.
.PARAMETER DryRun
    Preview changes without renaming.
.EXAMPLE
    Rename-BulkFiles -Path . -Filter '*.jpg' -Pattern 'IMG_' -Replacement 'Photo_' -DryRun
.EXAMPLE
    bulkrename -Path . -Filter '*.log' -Sequential -Prefix 'log_'
#>
function Rename-BulkFiles {
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([void])]
    param(
        [Parameter(Position = 0)]
        [string]$Path = (Get-Location).Path,

        [Parameter()]
        [string]$Filter = '*',

        [Parameter(ParameterSetName = 'Regex')]
        [string]$Pattern,

        [Parameter(ParameterSetName = 'Regex')]
        [string]$Replacement,

        [Parameter(ParameterSetName = 'Sequential')]
        [switch]$Sequential,

        [Parameter(ParameterSetName = 'Sequential')]
        [string]$Prefix = 'file_',

        [Parameter()]
        [string]$DateFormat,

        [Parameter()]
        [switch]$DryRun
    )

    $files = Get-ChildItem -Path $Path -Filter $Filter -File -ErrorAction SilentlyContinue | Sort-Object -Property Name

    if ($files.Count -eq 0) {
        Write-Host '  No files matched.' -ForegroundColor $Global:Theme.Muted
        return
    }

    Write-Host "`n  Bulk Rename Preview ($($files.Count) files)" -ForegroundColor $script:Theme.Primary
    Write-Host "  $('─' * 60)" -ForegroundColor $script:Theme.Muted

    $counter = 1
    $padWidth = $files.Count.ToString().Length
    $renames = [System.Collections.Generic.List[hashtable]]::new()

    foreach ($file in $files) {
        $newName = $file.Name

        if ($Sequential) {
            $ext = $file.Extension
            $numStr = $counter.ToString().PadLeft($padWidth, '0')
            $newName = "${Prefix}${numStr}${ext}"
            $counter++
        }
        elseif (-not [string]::IsNullOrEmpty($Pattern)) {
            $newName = $file.Name -replace $Pattern, $Replacement
        }

        if (-not [string]::IsNullOrEmpty($DateFormat)) {
            $dateStr = $file.LastWriteTime.ToString($DateFormat)
            $newName = "${dateStr}_${newName}"
        }

        if ($newName -ne $file.Name) {
            $renames.Add(@{ Old = $file.Name; New = $newName; FullPath = $file.FullName })
            Write-Host "  $($file.Name)" -ForegroundColor $script:Theme.Warning -NoNewline
            Write-Host " → " -ForegroundColor $script:Theme.Muted -NoNewline
            Write-Host "$newName" -ForegroundColor $script:Theme.Success
        }
    }

    if ($renames.Count -eq 0) {
        Write-Host '  No renames needed.' -ForegroundColor $Global:Theme.Muted
        return
    }

    if ($DryRun) {
        Write-Host "`n  (dry run - $($renames.Count) would be renamed)" -ForegroundColor $script:Theme.Info
        return
    }

    foreach ($r in $renames) {
        if ($PSCmdlet.ShouldProcess($r['Old'], "Rename to $($r['New'])")) {
            Rename-Item -Path $r['FullPath'] -NewName $r['New'] -ErrorAction SilentlyContinue
        }
    }

    Write-Host "`n  Renamed $($renames.Count) file(s)." -ForegroundColor $script:Theme.Success
    Write-Host ''
}

#endregion

#region ── Duplicate Finder ───────────────────────────────────────────────────

<#
.SYNOPSIS
    Finds duplicate files using SHA256 hashing.
.PARAMETER Path
    Directory to scan.
.PARAMETER Recurse
    Scan subdirectories.
.PARAMETER MinSizeKB
    Minimum file size to check (skip tiny files).
.EXAMPLE
    Find-DuplicateFiles -Path 'C:\Users\$env:USERNAME\Pictures' -Recurse
.EXAMPLE
    dupes -Path . -MinSizeKB 100
#>
function Find-DuplicateFiles {
    [CmdletBinding()]
    [OutputType([void])]
    param(
        [Parameter(Position = 0)]
        [string]$Path = (Get-Location).Path,

        [Parameter()]
        [switch]$Recurse,

        [Parameter()]
        [ValidateRange(0, 1048576)]
        [int]$MinSizeKB = 1
    )

    Write-Host "`n  Duplicate File Finder" -ForegroundColor $script:Theme.Primary
    Write-Host "  $('─' * 60)" -ForegroundColor $script:Theme.Muted
    Write-Host '  Scanning and hashing...' -ForegroundColor $Global:Theme.Info

    $minBytes = $MinSizeKB * 1024
    $params = @{ Path = $Path; File = $true; ErrorAction = 'SilentlyContinue' }
    if ($Recurse) { $params['Recurse'] = $true }

    $files = Get-ChildItem @params | Where-Object -FilterScript { $_.Length -ge $minBytes }

    if ($files.Count -eq 0) {
        Write-Host '  No files to check.' -ForegroundColor $Global:Theme.Muted
        return
    }

    # Group by size first (fast pre-filter)
    $sizeGroups = $files | Group-Object -Property Length | Where-Object -FilterScript { $_.Count -gt 1 }

    $hashMap = @{}
    $dupeCount = 0
    $wasteMB = 0

    foreach ($group in $sizeGroups) {
        foreach ($file in $group.Group) {
            try {
                $hash = (Get-FileHash -Path $file.FullName -Algorithm SHA256 -ErrorAction Stop).Hash
                if (-not $hashMap.ContainsKey($hash)) {
                    $hashMap[$hash] = [System.Collections.Generic.List[object]]::new()
                }
                $hashMap[$hash].Add($file)
            }
            catch { }
        }
    }

    $duplicates = $hashMap.GetEnumerator() | Where-Object -FilterScript { $_.Value.Count -gt 1 }

    if (($duplicates | Measure-Object).Count -eq 0) {
        Write-Host '  No duplicates found.' -ForegroundColor $Global:Theme.Success
        return
    }

    foreach ($entry in $duplicates) {
        $dupeFiles = $entry.Value
        $sizeMB = [math]::Round($dupeFiles[0].Length / 1MB, 2)
        $wastedBytes = $dupeFiles[0].Length * ($dupeFiles.Count - 1)
        $wasteMB += $wastedBytes / 1MB
        $dupeCount += $dupeFiles.Count - 1

        Write-Host "`n  Hash: $($entry.Key.Substring(0, 16))... ($sizeMB MB x $($dupeFiles.Count))" -ForegroundColor $script:Theme.Warning
        foreach ($f in $dupeFiles) {
            $relPath = $f.FullName.Replace($Path, '.')
            Write-Host "    $relPath" -ForegroundColor $script:Theme.Text
        }
    }

    Write-Host "`n  Summary: $dupeCount duplicate(s), $([math]::Round($wasteMB, 1)) MB wasted" -ForegroundColor $script:Theme.Accent
    Write-Host ''
}

#endregion

#region ── Large File Finder ──────────────────────────────────────────────────

<#
.SYNOPSIS
    Finds the largest files in a directory tree.
.PARAMETER Path
    Root directory to scan.
.PARAMETER Top
    Number of files to show.
.PARAMETER MinSizeMB
    Minimum file size in MB.
.EXAMPLE
    Find-LargeFiles -Path 'C:\Users' -Top 20 -MinSizeMB 100
.EXAMPLE
    bigfiles -Top 30
#>
function Find-LargeFiles {
    [CmdletBinding()]
    [OutputType([void])]
    param(
        [Parameter(Position = 0)]
        [string]$Path = (Get-Location).Path,

        [Parameter()]
        [ValidateRange(1, 100)]
        [int]$Top = 15,

        [Parameter()]
        [double]$MinSizeMB = 10
    )

    Write-Host "`n  Large Files (>$MinSizeMB MB)" -ForegroundColor $script:Theme.Primary
    Write-Host "  $('─' * 60)" -ForegroundColor $script:Theme.Muted

    $minBytes = [long]($MinSizeMB * 1MB)
    $files = Get-ChildItem -Path $Path -Recurse -File -ErrorAction SilentlyContinue |
        Where-Object -FilterScript { $_.Length -ge $minBytes } |
        Sort-Object -Property Length -Descending |
        Select-Object -First $Top

    if ($files.Count -eq 0) {
        Write-Host '  No large files found.' -ForegroundColor $Global:Theme.Muted
        return
    }

    $totalMB = 0
    foreach ($f in $files) {
        $sizeMB = [math]::Round($f.Length / 1MB, 1)
        $totalMB += $sizeMB
        $sizeStr = if ($sizeMB -ge 1024) { "$([math]::Round($sizeMB / 1024, 1)) GB" } else { "$sizeMB MB" }
        $relPath = $f.FullName.Replace($Path, '.').Replace('\', '/')
        if ($relPath.Length -gt 50) { $relPath = '...' + $relPath.Substring($relPath.Length - 47) }

        $color = if ($sizeMB -gt 1000) { $script:Theme.Error } elseif ($sizeMB -gt 100) { $Global:Theme.Warning } else { $Global:Theme.Text }
        Write-Host "  $($sizeStr.PadLeft(10))" -ForegroundColor $color -NoNewline
        Write-Host "  $relPath" -ForegroundColor $script:Theme.Muted
    }

    $totalStr = if ($totalMB -ge 1024) { "$([math]::Round($totalMB / 1024, 1)) GB" } else { "$([math]::Round($totalMB)) MB" }
    Write-Host "`n  Total: $totalStr across $($files.Count) file(s)" -ForegroundColor $script:Theme.Accent
    Write-Host ''
}

#endregion

#region ── File Watcher ───────────────────────────────────────────────────────

<#
.SYNOPSIS
    Watches a directory for file changes with action triggers.
.PARAMETER Path
    Directory to watch.
.PARAMETER Filter
    File filter (e.g. '*.cs').
.PARAMETER Action
    ScriptBlock to execute on change.
.PARAMETER IncludeSubdirectories
    Watch subdirectories.
.EXAMPLE
    Start-FileWatcher -Path . -Filter '*.ps1' -Action { Write-Host "Changed: $($Event.SourceEventArgs.Name)" }
.EXAMPLE
    fwatch -Path ./src -Filter '*.cs'
#>
function Start-FileWatcher {
    [CmdletBinding()]
    [OutputType([void])]
    param(
        [Parameter(Position = 0)]
        [string]$Path = (Get-Location).Path,

        [Parameter()]
        [string]$Filter = '*.*',

        [Parameter()]
        [scriptblock]$Action,

        [Parameter()]
        [switch]$IncludeSubdirectories
    )

    $watcher = [System.IO.FileSystemWatcher]::new()
    $watcher.Path = (Resolve-Path -Path $Path).Path
    $watcher.Filter = $Filter
    $watcher.IncludeSubdirectories = $IncludeSubdirectories
    $watcher.NotifyFilter = [System.IO.NotifyFilters]::FileName -bor
        [System.IO.NotifyFilters]::LastWrite -bor
        [System.IO.NotifyFilters]::DirectoryName

    $defaultAction = {
        $changeType = $Event.SourceEventArgs.ChangeType
        $name = $Event.SourceEventArgs.Name
        $time = Get-Date -Format 'HH:mm:ss'
        Write-Host "  [$time] $changeType`: $name" -ForegroundColor Cyan
    }

    $handler = if ($null -ne $Action) { $Action } else { $defaultAction }

    $null = Register-ObjectEvent -InputObject $watcher -EventName 'Changed' -Action $handler -SourceIdentifier 'FileWatcher_Changed'
    $null = Register-ObjectEvent -InputObject $watcher -EventName 'Created' -Action $handler -SourceIdentifier 'FileWatcher_Created'
    $null = Register-ObjectEvent -InputObject $watcher -EventName 'Deleted' -Action $handler -SourceIdentifier 'FileWatcher_Deleted'
    $null = Register-ObjectEvent -InputObject $watcher -EventName 'Renamed' -Action $handler -SourceIdentifier 'FileWatcher_Renamed'

    $watcher.EnableRaisingEvents = $true

    Write-Host "  Watching: $($watcher.Path)" -ForegroundColor $script:Theme.Success
    Write-Host "  Filter:   $Filter" -ForegroundColor $script:Theme.Muted
    Write-Host "  Press Ctrl+C to stop, or run Stop-FileWatcher" -ForegroundColor $script:Theme.Info
    $Global:ActiveFileWatcher = $watcher
}

<#
.SYNOPSIS
    Stops the active file watcher.
.EXAMPLE
    Stop-FileWatcher
#>
function Stop-FileWatcher {
    [CmdletBinding()]
    [OutputType([void])]
    param()

    @('FileWatcher_Changed', 'FileWatcher_Created', 'FileWatcher_Deleted', 'FileWatcher_Renamed') |
        ForEach-Object -Process { Unregister-Event -SourceIdentifier $_ -ErrorAction SilentlyContinue }

    if ($null -ne $Global:ActiveFileWatcher) {
        $Global:ActiveFileWatcher.EnableRaisingEvents = $false
        $Global:ActiveFileWatcher.Dispose()
        $Global:ActiveFileWatcher = $null
    }

    Write-Host '  File watcher stopped.' -ForegroundColor $Global:Theme.Warning
}

#endregion

#region ── Symlink Manager ────────────────────────────────────────────────────

<#
.SYNOPSIS
    Creates or lists symbolic links and junctions.
.PARAMETER Target
    Target path.
.PARAMETER Link
    Link path.
.PARAMETER Junction
    Create a junction instead of symlink.
.PARAMETER List
    List symlinks in a directory.
.EXAMPLE
    New-SymbolicLink -Target 'C:\Users\$env:USERNAME\Documents' -Link 'C:\Docs'
.EXAMPLE
    symlink -List .
#>
function New-SymbolicLink {
    [CmdletBinding(SupportsShouldProcess, DefaultParameterSetName = 'Create')]
    [OutputType([void])]
    param(
        [Parameter(Mandatory, Position = 0, ParameterSetName = 'Create')]
        [string]$Target,

        [Parameter(Mandatory, Position = 1, ParameterSetName = 'Create')]
        [string]$Link,

        [Parameter(ParameterSetName = 'Create')]
        [switch]$Junction,

        [Parameter(Mandatory, ParameterSetName = 'List')]
        [string]$List
    )

    if ($PSCmdlet.ParameterSetName -eq 'List') {
        Write-Host "`n  Symbolic Links in: $List" -ForegroundColor $script:Theme.Primary
        Write-Host "  $('─' * 50)" -ForegroundColor $script:Theme.Muted

        $items = Get-ChildItem -Path $List -Force -ErrorAction SilentlyContinue |
            Where-Object -FilterScript { $_.Attributes -match 'ReparsePoint' }

        if ($items.Count -eq 0) {
            Write-Host '  None found.' -ForegroundColor $Global:Theme.Muted
            return
        }

        foreach ($item in $items) {
            $target = $item.Target
            $icon = if ($item.PSIsContainer) { 'DIR' } else { 'FILE' }
            Write-Host "  [$icon] $($item.Name)" -ForegroundColor $script:Theme.Accent -NoNewline
            Write-Host " → $target" -ForegroundColor $script:Theme.Muted
        }
        Write-Host ''
        return
    }

    if (-not $PSCmdlet.ShouldProcess("$Link → $Target", 'Create link')) { return }

    $type = if ($Junction) { 'Junction' } elseif (Test-Path -Path $Target -PathType Container) { 'SymbolicLink' } else { 'SymbolicLink' }

    try {
        New-Item -ItemType $type -Path $Link -Target $Target -Force | Out-Null
        Write-Host "  Created $type`: $Link → $Target" -ForegroundColor $script:Theme.Success
    }
    catch {
        Write-Warning -Message "Failed: $($_.Exception.Message). Try running as admin."
    }
}

#endregion

#region ── Directory Diff ─────────────────────────────────────────────────────

<#
.SYNOPSIS
    Compares two directory trees.
.PARAMETER Left
    First directory.
.PARAMETER Right
    Second directory.
.PARAMETER ContentCompare
    Also compare file contents (slow for large trees).
.EXAMPLE
    Compare-DirectoryTree -Left './v1' -Right './v2'
.EXAMPLE
    dirdiff ./old ./new
#>
function Compare-DirectoryTree {
    [CmdletBinding()]
    [OutputType([void])]
    param(
        [Parameter(Mandatory, Position = 0)]
        [ValidateScript({ Test-Path -Path $_ -PathType Container })]
        [string]$Left,

        [Parameter(Mandatory, Position = 1)]
        [ValidateScript({ Test-Path -Path $_ -PathType Container })]
        [string]$Right,

        [Parameter()]
        [switch]$ContentCompare
    )

    Write-Host "`n  Directory Diff" -ForegroundColor $script:Theme.Primary
    Write-Host "  L: $Left" -ForegroundColor $script:Theme.Muted
    Write-Host "  R: $Right" -ForegroundColor $script:Theme.Muted
    Write-Host "  $('─' * 60)" -ForegroundColor $script:Theme.Muted

    $leftFiles = Get-ChildItem -Path $Left -Recurse -File -ErrorAction SilentlyContinue |
        ForEach-Object -Process { @{ Rel = $_.FullName.Replace($Left, ''); Size = $_.Length; Full = $_.FullName } }
    $rightFiles = Get-ChildItem -Path $Right -Recurse -File -ErrorAction SilentlyContinue |
        ForEach-Object -Process { @{ Rel = $_.FullName.Replace($Right, ''); Size = $_.Length; Full = $_.FullName } }

    $leftMap = @{}; $leftFiles | ForEach-Object -Process { $leftMap[$_['Rel']] = $_ }
    $rightMap = @{}; $rightFiles | ForEach-Object -Process { $rightMap[$_['Rel']] = $_ }

    $allKeys = @($leftMap.Keys + $rightMap.Keys | Sort-Object -Unique)
    $added = 0; $removed = 0; $modified = 0; $same = 0

    foreach ($key in $allKeys) {
        $inLeft = $leftMap.ContainsKey($key)
        $inRight = $rightMap.ContainsKey($key)

        if ($inLeft -and -not $inRight) {
            Write-Host "  - $key" -ForegroundColor $script:Theme.Error
            $removed++
        }
        elseif (-not $inLeft -and $inRight) {
            Write-Host "  + $key" -ForegroundColor $script:Theme.Success
            $added++
        }
        elseif ($leftMap[$key]['Size'] -ne $rightMap[$key]['Size']) {
            Write-Host "  ~ $key (size: $($leftMap[$key]['Size']) → $($rightMap[$key]['Size']))" -ForegroundColor $script:Theme.Warning
            $modified++
        }
        elseif ($ContentCompare) {
            $lHash = (Get-FileHash -Path $leftMap[$key]['Full'] -Algorithm SHA256).Hash
            $rHash = (Get-FileHash -Path $rightMap[$key]['Full'] -Algorithm SHA256).Hash
            if ($lHash -ne $rHash) {
                Write-Host "  ~ $key (content differs)" -ForegroundColor $script:Theme.Warning
                $modified++
            }
            else { $same++ }
        }
        else { $same++ }
    }

    Write-Host "`n  +$added -$removed ~$modified =$same" -ForegroundColor $Global:Theme.Accent
    Write-Host ''
}

#endregion

#region ── Aliases ─────────────────────────────────────────────────────────────

Set-Alias -Name 'bulkrename' -Value 'Rename-BulkFiles'       -Scope Global -Force
Set-Alias -Name 'dupes'      -Value 'Find-DuplicateFiles'    -Scope Global -Force
Set-Alias -Name 'bigfiles'   -Value 'Find-LargeFiles'        -Scope Global -Force
Set-Alias -Name 'fwatch'     -Value 'Start-FileWatcher'      -Scope Global -Force
Set-Alias -Name 'fwstop'     -Value 'Stop-FileWatcher'       -Scope Global -Force
Set-Alias -Name 'symlink'    -Value 'New-SymbolicLink'       -Scope Global -Force
Set-Alias -Name 'dirdiff'    -Value 'Compare-DirectoryTree'  -Scope Global -Force

#endregion

