<#
.SYNOPSIS
    Clipboard Ring & History module for C-Man's PowerShell Profile.
.DESCRIPTION
    Provides a persistent clipboard history buffer with recall by index
    or fuzzy search, paste-transform operations (base64, JSON pretty,
    trim, uppercase, lowercase, URI encode), and session persistence.
.NOTES
    Module: 20-ClipboardRing.ps1
    Requires: PowerShell 5.1+
#>

#region ── Configuration ──────────────────────────────────────────────────────

$script:ClipRingFile = Join-Path -Path $script:ProfileRoot -ChildPath 'Cache' -AdditionalChildPath 'clipboard-ring.json'
$script:ClipRingMaxSize = 50
$script:ClipRingMaxItemLength = 10000
$script:ClipRing = [System.Collections.Generic.List[hashtable]]::new()
$script:ClipRingWatcherActive = $false

#endregion

#region ── Persistence ────────────────────────────────────────────────────────

<#
.SYNOPSIS
    Loads the clipboard ring from disk.
#>
function Import-ClipboardRing {
    [CmdletBinding()]
    [OutputType([void])]
    param()

    if (Test-Path -Path $script:ClipRingFile) {
        try {
            $data = Get-Content -Path $script:ClipRingFile -Raw | ConvertFrom-Json
            $script:ClipRing.Clear()
            foreach ($item in $data) {
                $script:ClipRing.Add(@{
                    Content   = $item.Content
                    Timestamp = $item.Timestamp
                    Source    = $item.Source
                    Length    = $item.Length
                })
            }
        }
        catch {
            $script:ClipRing.Clear()
        }
    }
}

<#
.SYNOPSIS
    Saves the clipboard ring to disk.
#>
function Export-ClipboardRing {
    [CmdletBinding()]
    [OutputType([void])]
    param()

    try {
        $data = $script:ClipRing | ForEach-Object -Process {
            [PSCustomObject]@{
                Content   = $_['Content']
                Timestamp = $_['Timestamp']
                Source    = $_['Source']
                Length    = $_['Length']
            }
        }
        $data | ConvertTo-Json -Depth 3 | Set-Content -Path $script:ClipRingFile -Force
    }
    catch {
        Write-Warning -Message "Failed to save clipboard ring: $($_.Exception.Message)"
    }
}

#endregion

#region ── Ring Operations ────────────────────────────────────────────────────

<#
.SYNOPSIS
    Adds an item to the clipboard ring.
.DESCRIPTION
    Pushes content onto the ring buffer, deduplicating and enforcing
    the maximum ring size. Newest entries are at the front.
.PARAMETER Content
    The text content to add.
.PARAMETER Source
    Optional source identifier (e.g., 'manual', 'watch').
.EXAMPLE
    Push-ClipboardRing -Content 'some text'
#>
function Push-ClipboardRing {
    [CmdletBinding()]
    [OutputType([void])]
    param(
        [Parameter(Mandatory, Position = 0)]
        [ValidateNotNullOrEmpty()]
        [string]$Content,

        [Parameter()]
        [string]$Source = 'manual'
    )

    # Truncate overly long items
    if ($Content.Length -gt $script:ClipRingMaxItemLength) {
        $Content = $Content.Substring(0, $script:ClipRingMaxItemLength)
    }

    # Deduplicate - remove existing identical entry
    $existing = $script:ClipRing | Where-Object -FilterScript { $_['Content'] -eq $Content }
    if ($null -ne $existing) {
        $script:ClipRing.Remove($existing)
    }

    # Push to front
    $entry = @{
        Content   = $Content
        Timestamp = [datetime]::UtcNow.ToString('o')
        Source    = $Source
        Length    = $Content.Length
    }

    $script:ClipRing.Insert(0, $entry)

    # Enforce max size
    while ($script:ClipRing.Count -gt $script:ClipRingMaxSize) {
        $script:ClipRing.RemoveAt($script:ClipRing.Count - 1)
    }

    Export-ClipboardRing
}

<#
.SYNOPSIS
    Copies content to clipboard and adds to the ring.
.DESCRIPTION
    Sets the clipboard content and pushes it to the clipboard ring.
    This is the primary way to add items to the ring.
.PARAMETER Content
    The text to copy.
.EXAMPLE
    Set-ClipboardRing -Content 'Hello World'
.EXAMPLE
    'some text' | clip+
#>
function Set-ClipboardRing {
    [CmdletBinding()]
    [OutputType([void])]
    param(
        [Parameter(Mandatory, Position = 0, ValueFromPipeline)]
        [string]$Content
    )

    process {
        if (Get-Command -Name 'Set-Clipboard' -ErrorAction SilentlyContinue) {
            Set-Clipboard -Value $Content
        }
        Push-ClipboardRing -Content $Content -Source 'set'
        Write-Host "  Copied to clipboard + ring ($('{0:N0}' -f $Content.Length) chars)." -ForegroundColor $script:Theme.Success
    }
}

<#
.SYNOPSIS
    Captures the current clipboard content into the ring.
.DESCRIPTION
    Reads whatever is currently on the clipboard and pushes it to the ring.
.EXAMPLE
    Save-ClipboardToRing
#>
function Save-ClipboardToRing {
    [CmdletBinding()]
    [OutputType([void])]
    param()

    if (-not (Get-Command -Name 'Get-Clipboard' -ErrorAction SilentlyContinue)) {
        Write-Warning -Message 'Get-Clipboard not available.'
        return
    }

    $content = Get-Clipboard -Raw
    if ([string]::IsNullOrEmpty($content)) {
        Write-Host '  Clipboard is empty.' -ForegroundColor $Global:Theme.Muted
        return
    }

    Push-ClipboardRing -Content $content -Source 'capture'
    Write-Host "  Captured clipboard to ring ($('{0:N0}' -f $content.Length) chars)." -ForegroundColor $script:Theme.Success
}

#endregion

#region ── Display & Recall ───────────────────────────────────────────────────

<#
.SYNOPSIS
    Shows the clipboard ring history.
.DESCRIPTION
    Lists clipboard ring entries with index numbers, timestamps,
    and content previews.
.PARAMETER Count
    Number of entries to show. Default shows all.
.EXAMPLE
    Show-ClipboardRing
.EXAMPLE
    clipls -Count 10
#>
function Show-ClipboardRing {
    [CmdletBinding()]
    [OutputType([void])]
    param(
        [Parameter(Position = 0)]
        [ValidateRange(1, 100)]
        [int]$Count = 0
    )

    Write-Host "`n  Clipboard Ring ($($script:ClipRing.Count) entries)" -ForegroundColor $script:Theme.Primary
    Write-Host "  $('─' * 60)" -ForegroundColor $script:Theme.Muted

    if ($script:ClipRing.Count -eq 0) {
        Write-Host '  (empty)' -ForegroundColor $Global:Theme.Muted
        return
    }

    $displayCount = if ($Count -gt 0) { [math]::Min($Count, $script:ClipRing.Count) } else { $script:ClipRing.Count }

    for ($i = 0; $i -lt $displayCount; $i++) {
        $entry = $script:ClipRing[$i]
        $preview = $entry['Content'] -replace '[\r\n]+', ' '
        if ($preview.Length -gt 55) {
            $preview = $preview.Substring(0, 52) + '...'
        }

        $timestamp = [datetime]::Parse($entry['Timestamp']).ToLocalTime().ToString('HH:mm')
        $sizeDisplay = if ($entry['Length'] -gt 1000) {
            "$('{0:N1}' -f ($entry['Length'] / 1000))KB"
        }
        else {
            "$($entry['Length'])B"
        }

        $indexStr = "[$i]".PadRight(5)
        Write-Host "  $indexStr" -ForegroundColor $script:Theme.Accent -NoNewline
        Write-Host " $timestamp" -ForegroundColor $script:Theme.Muted -NoNewline
        Write-Host " $($sizeDisplay.PadRight(7))" -ForegroundColor $script:Theme.Muted -NoNewline
        Write-Host " $preview" -ForegroundColor $script:Theme.Text
    }
    Write-Host ''
}

<#
.SYNOPSIS
    Recalls a clipboard ring entry to the clipboard.
.DESCRIPTION
    Copies a ring entry by index back to the system clipboard.
.PARAMETER Index
    Ring entry index (0-based, 0 = most recent).
.EXAMPLE
    Get-ClipboardRingItem -Index 3
.EXAMPLE
    clip- 3
#>
function Get-ClipboardRingItem {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory, Position = 0)]
        [ValidateRange(0, 100)]
        [int]$Index
    )

    if ($Index -ge $script:ClipRing.Count) {
        Write-Warning -Message "Index $Index out of range (0-$($script:ClipRing.Count - 1))."
        return $null
    }

    $content = $script:ClipRing[$Index]['Content']

    if (Get-Command -Name 'Set-Clipboard' -ErrorAction SilentlyContinue) {
        Set-Clipboard -Value $content
    }

    $preview = $content
    if ($preview.Length -gt 60) {
        $preview = $preview.Substring(0, 57) + '...'
    }
    Write-Host "  Recalled [$Index]: $preview" -ForegroundColor $script:Theme.Success

    return $content
}

<#
.SYNOPSIS
    Searches the clipboard ring with fuzzy matching.
.DESCRIPTION
    Searches ring entries for a pattern and returns matching items.
.PARAMETER Pattern
    Text pattern to search for (supports wildcards).
.PARAMETER Recall
    Copy the first match back to clipboard.
.EXAMPLE
    Search-ClipboardRing -Pattern '*github*'
.EXAMPLE
    clipsearch 'https'
#>
function Search-ClipboardRing {
    [CmdletBinding()]
    [OutputType([void])]
    param(
        [Parameter(Mandatory, Position = 0)]
        [string]$Pattern,

        [Parameter()]
        [switch]$Recall
    )

    $matches = [System.Collections.Generic.List[hashtable]]::new()
    $indices = [System.Collections.Generic.List[int]]::new()

    for ($i = 0; $i -lt $script:ClipRing.Count; $i++) {
        $content = $script:ClipRing[$i]['Content']
        if ($content -match [regex]::Escape($Pattern) -or $content -like "*$Pattern*") {
            $matches.Add($script:ClipRing[$i])
            $indices.Add($i)
        }
    }

    Write-Host "`n  Search: '$Pattern' ($($matches.Count) match(es))" -ForegroundColor $script:Theme.Primary
    Write-Host "  $('─' * 50)" -ForegroundColor $script:Theme.Muted

    if ($matches.Count -eq 0) {
        Write-Host '  No matches.' -ForegroundColor $Global:Theme.Muted
        return
    }

    for ($j = 0; $j -lt $matches.Count; $j++) {
        $entry = $matches[$j]
        $idx = $indices[$j]
        $preview = $entry['Content'] -replace '[\r\n]+', ' '
        if ($preview.Length -gt 55) {
            $preview = $preview.Substring(0, 52) + '...'
        }

        Write-Host "  [$idx] " -ForegroundColor $script:Theme.Accent -NoNewline
        Write-Host $preview -ForegroundColor $Global:Theme.Text
    }

    if ($Recall -and $matches.Count -gt 0) {
        $null = Get-ClipboardRingItem -Index $indices[0]
    }
    Write-Host ''
}

#endregion

#region ── Paste-Transform Operations ─────────────────────────────────────────

<#
.SYNOPSIS
    Transforms clipboard content with a specified operation.
.DESCRIPTION
    Applies a transformation to the current clipboard content and
    updates the clipboard with the result. Supports base64 encode/decode,
    JSON pretty-print, trim, case changes, URI encode/decode, and more.
.PARAMETER Operation
    The transformation to apply.
.PARAMETER FromRing
    Use a ring entry instead of current clipboard.
.EXAMPLE
    Invoke-ClipboardTransform -Operation Base64Encode
.EXAMPLE
    clipx json
.EXAMPLE
    clipx trim
#>
function Invoke-ClipboardTransform {
    [CmdletBinding()]
    [OutputType([void])]
    param(
        [Parameter(Mandatory, Position = 0)]
        [ValidateSet('Base64Encode', 'Base64Decode', 'JsonPretty', 'JsonMinify',
                     'Trim', 'Upper', 'Lower', 'TitleCase',
                     'UriEncode', 'UriDecode', 'HtmlEncode', 'HtmlDecode',
                     'LineSort', 'LineUnique', 'LineReverse', 'LineCount',
                     'Md5Hash', 'Sha256Hash', 'EscapeRegex')]
        [string]$Operation,

        [Parameter()]
        [int]$FromRing = -1
    )

    # Get source content
    $content = if ($FromRing -ge 0 -and $FromRing -lt $script:ClipRing.Count) {
        $script:ClipRing[$FromRing]['Content']
    }
    elseif (Get-Command -Name 'Get-Clipboard' -ErrorAction SilentlyContinue) {
        Get-Clipboard -Raw
    }
    else {
        Write-Warning -Message 'Cannot read clipboard.'
        return
    }

    if ([string]::IsNullOrEmpty($content)) {
        Write-Host '  Clipboard is empty.' -ForegroundColor $Global:Theme.Muted
        return
    }

    $result = switch ($Operation) {
        'Base64Encode' {
            [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes([System.Text.Encoding]::UTF8.GetBytes($content)))
        }
        'Base64Decode' {
            try {
                [System.Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($content.Trim()))
            }
            catch {
                Write-Warning -Message 'Invalid Base64 content.'
                return
            }
        }
        'JsonPretty' {
            try {
                $content | ConvertFrom-Json | ConvertTo-Json -Depth 20
            }
            catch {
                Write-Warning -Message 'Invalid JSON content.'
                return
            }
        }
        'JsonMinify' {
            try {
                ($content | ConvertFrom-Json | ConvertTo-Json -Depth 20 -Compress)
            }
            catch {
                Write-Warning -Message 'Invalid JSON content.'
                return
            }
        }
        'Trim'       { $content.Trim() }
        'Upper'      { $content.ToUpperInvariant() }
        'Lower'      { $content.ToLowerInvariant() }
        'TitleCase'  { (Get-Culture).TextInfo.ToTitleCase($content.ToLower()) }
        'UriEncode'  { [uri]::EscapeDataString($content) }
        'UriDecode'  { [uri]::UnescapeDataString($content) }
        'HtmlEncode' { [System.Net.WebUtility]::HtmlEncode($content) }
        'HtmlDecode' { [System.Net.WebUtility]::HtmlDecode($content) }
        'LineSort'   { ($content -split "`n" | Sort-Object) -join "`n" }
        'LineUnique' { ($content -split "`n" | Sort-Object -Unique) -join "`n" }
        'LineReverse' { ($content -split "`n" | ForEach-Object -Process { $_ })[-1..0] -join "`n" }
        'LineCount'  {
            $count = ($content -split "`n").Count
            Write-Host "  Lines: $count" -ForegroundColor $script:Theme.Info
            return
        }
        'Md5Hash' {
            $bytes = [System.Text.Encoding]::UTF8.GetBytes($content)
            $hash = [System.Security.Cryptography.MD5]::Create().ComputeHash($bytes)
            ($hash | ForEach-Object -Process { $_.ToString('x2') }) -join ''
        }
        'Sha256Hash' {
            $bytes = [System.Text.Encoding]::UTF8.GetBytes($content)
            $hash = [System.Security.Cryptography.SHA256]::Create().ComputeHash($bytes)
            ($hash | ForEach-Object -Process { $_.ToString('x2') }) -join ''
        }
        'EscapeRegex' { [regex]::Escape($content) }
    }

    if ($null -ne $result) {
        if (Get-Command -Name 'Set-Clipboard' -ErrorAction SilentlyContinue) {
            Set-Clipboard -Value $result
        }
        Push-ClipboardRing -Content $result -Source "transform:$Operation"

        $preview = $result
        if ($preview.Length -gt 60) {
            $preview = $preview.Substring(0, 57) + '...'
        }

        Write-Host "  $Operation → clipboard ($('{0:N0}' -f $result.Length) chars)" -ForegroundColor $script:Theme.Success
        Write-Host "  $preview" -ForegroundColor $script:Theme.Muted
    }
}

#endregion

#region ── Ring Management ────────────────────────────────────────────────────

<#
.SYNOPSIS
    Clears the clipboard ring history.
.EXAMPLE
    Clear-ClipboardRing
#>
function Clear-ClipboardRing {
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([void])]
    param()

    if (-not $PSCmdlet.ShouldProcess('Clipboard ring', 'Clear all entries')) {
        return
    }

    $count = $script:ClipRing.Count
    $script:ClipRing.Clear()
    Export-ClipboardRing

    Write-Host "  Cleared $count entries from clipboard ring." -ForegroundColor $script:Theme.Warning
}

<#
.SYNOPSIS
    Removes a specific entry from the clipboard ring.
.PARAMETER Index
    The index of the entry to remove.
.EXAMPLE
    Remove-ClipboardRingItem -Index 3
#>
function Remove-ClipboardRingItem {
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([void])]
    param(
        [Parameter(Mandatory, Position = 0)]
        [ValidateRange(0, 100)]
        [int]$Index
    )

    if ($Index -ge $script:ClipRing.Count) {
        Write-Warning -Message "Index $Index out of range."
        return
    }

    $preview = $script:ClipRing[$Index]['Content']
    if ($preview.Length -gt 40) { $preview = $preview.Substring(0, 37) + '...' }

    if ($PSCmdlet.ShouldProcess("[$Index] $preview", 'Remove from ring')) {
        $script:ClipRing.RemoveAt($Index)
        Export-ClipboardRing
        Write-Host "  Removed entry [$Index]." -ForegroundColor $script:Theme.Warning
    }
}

#endregion

#region ── Aliases ─────────────────────────────────────────────────────────────

Set-Alias -Name 'clip+'       -Value 'Set-ClipboardRing'         -Scope Global -Force
Set-Alias -Name 'clip-'       -Value 'Get-ClipboardRingItem'     -Scope Global -Force
Set-Alias -Name 'clipls'      -Value 'Show-ClipboardRing'        -Scope Global -Force
Set-Alias -Name 'clipsearch'  -Value 'Search-ClipboardRing'      -Scope Global -Force
Set-Alias -Name 'clipx'       -Value 'Invoke-ClipboardTransform' -Scope Global -Force
Set-Alias -Name 'clipclear'   -Value 'Clear-ClipboardRing'       -Scope Global -Force
Set-Alias -Name 'clipsave'    -Value 'Save-ClipboardToRing'      -Scope Global -Force
Set-Alias -Name 'cliprm'      -Value 'Remove-ClipboardRingItem'  -Scope Global -Force

#endregion

#region ── Tab Completion ─────────────────────────────────────────────────────

Register-ArgumentCompleter -CommandName 'Invoke-ClipboardTransform' -ParameterName 'Operation' -ScriptBlock {
    param($commandName, $parameterName, $wordToComplete, $commandAst, $fakeBoundParameters)

    @('Base64Encode', 'Base64Decode', 'JsonPretty', 'JsonMinify',
      'Trim', 'Upper', 'Lower', 'TitleCase',
      'UriEncode', 'UriDecode', 'HtmlEncode', 'HtmlDecode',
      'LineSort', 'LineUnique', 'LineReverse', 'LineCount',
      'Md5Hash', 'Sha256Hash', 'EscapeRegex') |
        Where-Object -FilterScript { $_ -like "${wordToComplete}*" } |
        ForEach-Object -Process {
            [System.Management.Automation.CompletionResult]::new($_, $_, 'ParameterValue', $_)
        }
}

#endregion

#region ── Initialize ─────────────────────────────────────────────────────────

Import-ClipboardRing

#endregion

