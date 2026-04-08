[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingWriteHost', '', Justification = 'QOL functions require colored interactive output')]
param()

#region ── sudo / Elevated Shell ─────────────────────────────────────────────

function Invoke-Elevated {
    <#
    .SYNOPSIS
        Re-run the last command (or a given command) in a new elevated PowerShell window.
    .PARAMETER Command
        Command string to run elevated. Omit to re-run the last history entry.
    .EXAMPLE
        sudo
        sudo "netsh int ip reset"
    #>
    [CmdletBinding()]
    [Alias('sudo')]
    param(
        [Parameter(Position = 0)]
        [string]$Command
    )

    if ([string]::IsNullOrWhiteSpace($Command)) {
        $last = Get-History -Count 1 -ErrorAction SilentlyContinue
        $Command = if ($last) { $last.CommandLine } else { 'pwsh' }
    }

    $encodedCmd = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($Command))
    Start-Process -FilePath 'pwsh' -ArgumentList "-NoExit -EncodedCommand $encodedCmd" -Verb RunAs
}

#endregion

#region ── watch ─────────────────────────────────────────────────────────────

function Invoke-Watch {
    <#
    .SYNOPSIS
        Repeat a command every N seconds until Ctrl+C.
    .PARAMETER ScriptBlock
        Command to repeat.
    .PARAMETER Interval
        Seconds between runs (default: 2).
    .PARAMETER ClearScreen
        Clear screen before each run.
    .EXAMPLE
        watch { Get-Date }
        watch 5 { Get-Process | Sort-Object CPU -Desc | Select -First 10 }
    #>
    [CmdletBinding()]
    [Alias('watch')]
    param(
        [Parameter(Mandatory, Position = 0)]
        [scriptblock]$ScriptBlock,

        [Parameter(Position = 1)]
        [ValidateRange(1, 3600)]
        [int]$Interval = 2,

        [switch]$ClearScreen
    )

    Write-Host "  Watching every ${Interval}s — press Ctrl+C to stop" -ForegroundColor DarkGray
    while ($true) {
        if ($ClearScreen) { Clear-Host }
        Write-Host "  [$( Get-Date -Format 'HH:mm:ss' )]" -ForegroundColor DarkGray
        try { & $ScriptBlock } catch { Write-Warning $_.Exception.Message }
        Start-Sleep -Seconds $Interval
    }
}

#endregion

#region ── weather ───────────────────────────────────────────────────────────

function Get-Weather {
    <#
    .SYNOPSIS
        Show weather forecast in the terminal via wttr.in.
    .PARAMETER Location
        City name or coordinates. Defaults to auto-detected location.
    .PARAMETER Format
        'full' (default multi-day), 'oneline', or 'forecast3'.
    .EXAMPLE
        weather
        weather "New York"
        weather -Format oneline
    #>
    [CmdletBinding()]
    [Alias('weather')]
    param(
        [Parameter(Position = 0)]
        [string]$Location = '',

        [ValidateSet('full', 'oneline', 'forecast3')]
        [string]$Format = 'full'
    )

    $loc = [Uri]::EscapeDataString($Location)
    $url = switch ($Format) {
        'oneline'   { "https://wttr.in/${loc}?format=3" }
        'forecast3' { "https://wttr.in/${loc}?format=v2" }
        default     { "https://wttr.in/${loc}?T" }
    }

    try {
        $response = Invoke-RestMethod -Uri $url -TimeoutSec 10 -Headers @{ 'User-Agent' = 'curl/8.0' }
        Write-Host $response -ForegroundColor Cyan
    }
    catch {
        Write-Warning "Weather unavailable: $($_.Exception.Message)"
    }
}

#endregion

#region ── cheat sheet ───────────────────────────────────────────────────────

function Get-Cheat {
    <#
    .SYNOPSIS
        Quick command reference via cht.sh.
    .PARAMETER Topic
        Command or concept to look up (e.g., 'curl', 'git', 'powershell/regex').
    .EXAMPLE
        cheat curl
        cheat "git rebase"
        cheat powershell/foreach
    #>
    [CmdletBinding()]
    [Alias('cheat')]
    param(
        [Parameter(Mandatory, Position = 0)]
        [string]$Topic
    )

    $topic = $Topic -replace ' ', '+'
    $url = "https://cht.sh/$topic"
    try {
        $response = Invoke-RestMethod -Uri $url -TimeoutSec 10 -Headers @{ 'User-Agent' = 'curl/8.0' }
        # Strip ANSI escape codes for cleaner output in older terminals
        $clean = $response -replace '\x1b\[[0-9;]*m', ''
        Write-Host $clean
    }
    catch {
        Write-Warning "Cheat sheet unavailable: $($_.Exception.Message)"
    }
}

#endregion

#region ── terminal title ────────────────────────────────────────────────────

function Set-WindowTitle {
    <#
    .SYNOPSIS
        Set the terminal tab/window title.
    .PARAMETER Title
        Title string. Omit to reset to default.
    .EXAMPLE
        title "Build Running"
        title  # resets
    #>
    [CmdletBinding()]
    [Alias('title')]
    param(
        [Parameter(Position = 0)]
        [string]$Title = $env:USERNAME
    )

    $Host.UI.RawUI.WindowTitle = $Title
}

#endregion

#region ── history search ────────────────────────────────────────────────────

function Search-History {
    <#
    .SYNOPSIS
        Search PSReadLine command history for a pattern.
    .PARAMETER Pattern
        Regex or literal string to match.
    .PARAMETER Last
        Limit results to last N matching entries.
    .EXAMPLE
        fh git
        fh "build-iso" -Last 5
    #>
    [CmdletBinding()]
    [Alias('fh')]
    param(
        [Parameter(Mandatory, Position = 0)]
        [string]$Pattern,

        [int]$Last = 50
    )

    $histPath = (Get-PSReadLineOption).HistorySavePath
    if (-not (Test-Path $histPath)) {
        Write-Warning "History file not found: $histPath"
        return
    }

    $results = Select-String -Path $histPath -Pattern $Pattern -ErrorAction SilentlyContinue |
        Select-Object -Last $Last

    if (-not $results) {
        Write-Host "  No history matches for: $Pattern" -ForegroundColor DarkGray
        return
    }

    $tc = $Global:Theme
    foreach ($r in $results) {
        Write-Host "  $($r.LineNumber.ToString().PadLeft(6))" -ForegroundColor $tc.Muted -NoNewline
        $highlighted = $r.Line -replace "(?i)($([regex]::Escape($Pattern)))", "`e[93m`$1`e[0m"
        Write-Host "  $highlighted"
    }
}

#endregion

#region ── temp directory ────────────────────────────────────────────────────

function New-TempDirectory {
    <#
    .SYNOPSIS
        Create a unique temp directory and cd into it.
    .EXAMPLE
        tmp
    #>
    [CmdletBinding()]
    [Alias('tmp')]
    param()

    $tempDir = Join-Path $env:TEMP "ps-tmp-$(Get-Random -Maximum 99999)"
    $null = New-Item -Path $tempDir -ItemType Directory -Force
    Set-Location $tempDir
    Write-Host "  Created and moved to: $tempDir" -ForegroundColor (($Global:Theme).Success)
}

#endregion

#region ── number conversions ────────────────────────────────────────────────

function ConvertTo-Hex {
    <#
    .SYNOPSIS
        Convert a decimal integer to hex.
    .EXAMPLE
        hex 255      # -> 0xFF
        255 | hex
    #>
    [CmdletBinding()]
    [Alias('hex')]
    param(
        [Parameter(Mandatory, ValueFromPipeline, Position = 0)]
        [long]$Number
    )
    process { '0x{0:X}' -f $Number }
}

function ConvertFrom-Hex {
    <#
    .SYNOPSIS
        Convert a hex value to decimal.
    .EXAMPLE
        dec 0xFF     # -> 255
        dec FF       # -> 255
    #>
    [CmdletBinding()]
    [Alias('dec')]
    param(
        [Parameter(Mandatory, ValueFromPipeline, Position = 0)]
        [string]$HexValue
    )
    process {
        $clean = $HexValue -replace '^0x', ''
        [Convert]::ToInt64($clean, 16)
    }
}

#endregion

#region ── base64 ────────────────────────────────────────────────────────────

function ConvertTo-Base64 {
    <#
    .SYNOPSIS
        Encode a string or file to base64.
    .EXAMPLE
        b64 "hello world"
        Get-Content file.bin | b64
    #>
    [CmdletBinding()]
    [Alias('b64')]
    param(
        [Parameter(Mandatory, ValueFromPipeline, Position = 0)]
        [string]$InputObject
    )
    process { [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($InputObject)) }
}

function ConvertFrom-Base64 {
    <#
    .SYNOPSIS
        Decode a base64 string to text.
    .EXAMPLE
        unb64 "aGVsbG8gd29ybGQ="
    #>
    [CmdletBinding()]
    [Alias('unb64')]
    param(
        [Parameter(Mandatory, ValueFromPipeline, Position = 0)]
        [string]$InputObject
    )
    process { [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($InputObject)) }
}

#endregion

#region ── repeat ────────────────────────────────────────────────────────────

function Invoke-Repeat {
    <#
    .SYNOPSIS
        Run a script block N times.
    .PARAMETER Times
        How many times to repeat.
    .PARAMETER ScriptBlock
        Code to execute each iteration.
    .EXAMPLE
        repeat 3 { Write-Host "ping" }
    #>
    [CmdletBinding()]
    [Alias('repeat')]
    param(
        [Parameter(Mandatory, Position = 0)]
        [ValidateRange(1, 10000)]
        [int]$Times,

        [Parameter(Mandatory, Position = 1)]
        [scriptblock]$ScriptBlock
    )

    for ($i = 1; $i -le $Times; $i++) {
        & $ScriptBlock
    }
}

#endregion

#region ── PATH deduplication ────────────────────────────────────────────────

function Repair-PathDuplicates {
    <#
    .SYNOPSIS
        Remove duplicate and optionally missing entries from PATH.
    .PARAMETER RemoveMissing
        Also strip directories that no longer exist on disk.
    .PARAMETER Apply
        Write cleaned PATH back to the Process scope (and optionally User).
    .EXAMPLE
        dedup-path
        dedup-path -RemoveMissing -Apply
    #>
    [CmdletBinding(SupportsShouldProcess)]
    [Alias('dedup-path')]
    param(
        [switch]$RemoveMissing,
        [switch]$Apply
    )

    $entries = $env:PATH -split ';' | Where-Object { $_ -ne '' }
    $seen = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    $cleaned = [System.Collections.Generic.List[string]]::new()
    $removed = [System.Collections.Generic.List[string]]::new()

    foreach ($entry in $entries) {
        if (-not $seen.Add($entry)) {
            $removed.Add("  [DUP]  $entry")
            continue
        }
        if ($RemoveMissing -and -not (Test-Path $entry -PathType Container)) {
            $removed.Add("  [MISS] $entry")
            continue
        }
        $cleaned.Add($entry)
    }

    Write-Host "`n  PATH entries: $($entries.Count) → $($cleaned.Count)" -ForegroundColor Cyan
    if ($removed.Count -gt 0) {
        Write-Host "  Removed:" -ForegroundColor Yellow
        $removed | ForEach-Object { Write-Host $_ -ForegroundColor DarkGray }
    } else {
        Write-Host "  No duplicates found." -ForegroundColor Green
    }

    if ($Apply -and $PSCmdlet.ShouldProcess('PATH', 'Apply cleaned PATH')) {
        $newPath = $cleaned -join ';'
        $env:PATH = $newPath
        Write-Host "  Applied to current session." -ForegroundColor Green
    }
}

#endregion

#region ── size alias ────────────────────────────────────────────────────────

# 'size' → calls Get-DirectorySize from 05-Functions-Core.ps1
Set-Alias -Name 'size' -Value Get-DirectorySize -Option AllScope -Force

#endregion
