[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingWriteHost', '', Justification = 'Interactive profile output')]
param()

#region -- PSReadLine Configuration -------------------------------------------

<#
.SYNOPSIS
    Advanced PSReadLine setup: predictive IntelliSense, fuzzy history,
    smart keybindings, deduplication, and sensitive command filtering.
#>

# Ensure PSReadLine is available
if (-not (Get-Module -Name PSReadLine -ListAvailable)) {
    Write-Warning -Message 'PSReadLine not found. Skipping readline configuration.'
    return
}

Import-Module -Name PSReadLine -ErrorAction SilentlyContinue

$script:PSReadLineOptions = @{
    EditMode                      = 'Windows'
    HistoryNoDuplicates           = $Global:ProfileConfig.HistoryDeduplicate
    HistorySearchCursorMovesToEnd = $true
    MaximumHistoryCount           = $Global:ProfileConfig.HistoryMaxCount
    PredictionSource              = 'HistoryAndPlugin'
    PredictionViewStyle           = 'ListView'
    BellStyle                     = 'None'
    ShowToolTips                  = $true
    WordDelimiters                = ';:,.[]{}()/\|!?^&*-=+''"-��?'
    PromptText                    = '> '
}

# PredictionSource HistoryAndPlugin requires PS 7.2+
if ($PSVersionTable.PSVersion.Major -lt 7 -or
    ($PSVersionTable.PSVersion.Major -eq 7 -and $PSVersionTable.PSVersion.Minor -lt 2)) {
    $script:PSReadLineOptions['PredictionSource'] = 'History'
    $script:PSReadLineOptions['PredictionViewStyle'] = 'InlineView'
}

if (-not $Global:ProfileConfig.EnablePredictiveIntelliSense) {
    $script:PSReadLineOptions['PredictionSource'] = 'None'
}

# Apply Matrix theme colors to PSReadLine
$script:PSReadLineColors = @{
    Command          = "$([char]0x1b)[92m"       # Bright green
    Parameter        = "$([char]0x1b)[36m"       # Cyan
    Operator         = "$([char]0x1b)[37m"       # White
    Variable         = "$([char]0x1b)[32m"       # Green
    String           = "$([char]0x1b)[33m"       # Yellow
    Number           = "$([char]0x1b)[35m"       # Magenta
    Type             = "$([char]0x1b)[34m"       # Blue
    Comment          = "$([char]0x1b)[90m"       # Dark gray
    Keyword          = "$([char]0x1b)[92m"       # Bright green
    Error            = "$([char]0x1b)[91m"       # Bright red
    Selection        = "$([char]0x1b)[30;47m"    # Black on white
    InlinePrediction = "$([char]0x1b)[90m"       # Dark gray
    ListPrediction   = "$([char]0x1b)[32m"       # Green
    Member           = "$([char]0x1b)[36m"       # Cyan
    Emphasis         = "$([char]0x1b)[96m"       # Bright cyan
    Default          = "$([char]0x1b)[37m"       # White
}

try {
    Set-PSReadLineOption @script:PSReadLineOptions
    Set-PSReadLineOption -Colors $script:PSReadLineColors
}
catch {
    Write-Warning -Message "PSReadLine options error: $($_.Exception.Message)"
}

#endregion

#region -- Keybindings --------------------------------------------------------

# Ctrl+R: Fuzzy reverse history search
Set-PSReadLineKeyHandler -Key 'Ctrl+r' -Function ReverseSearchHistory

# Ctrl+f: Forward word completion from inline prediction
Set-PSReadLineKeyHandler -Key 'Ctrl+f' -Function ForwardWord

# Ctrl+Shift+A: Select all
Set-PSReadLineKeyHandler -Key 'Ctrl+shift+a' -Function SelectAll

# Alt+a: Accept next suggestion word
Set-PSReadLineKeyHandler -Key 'Alt+a' -Function AcceptNextSuggestionWord

# Ctrl+Space: Show menu complete
Set-PSReadLineKeyHandler -Key 'Ctrl+Spacebar' -Function MenuComplete

# F2: Toggle prediction view style
Set-PSReadLineKeyHandler -Key 'F2' -BriefDescription 'TogglePredictionView' -LongDescription 'Toggle between ListView and InlineView for predictions' -ScriptBlock {
    $currentStyle = (Get-PSReadLineOption).PredictionViewStyle
    if ($currentStyle -eq 'InlineView') {
        Set-PSReadLineOption -PredictionViewStyle ListView
    }
    else {
        Set-PSReadLineOption -PredictionViewStyle InlineView
    }
}

# Ctrl+Shift+C: Copy entire command line to clipboard
Set-PSReadLineKeyHandler -Key 'Ctrl+shift+c' -BriefDescription 'CopyCommandToClipboard' -LongDescription 'Copy the entire command line to clipboard' -ScriptBlock {
    $line = $null
    [Microsoft.PowerShell.PSConsoleReadLine]::GetBufferState([ref]$line, [ref]$null)
    if ($null -ne $line) {
        Set-Clipboard -Value $line
    }
}

# Ctrl+Shift+V: Paste from clipboard and trim
Set-PSReadLineKeyHandler -Key 'Ctrl+shift+v' -BriefDescription 'SmartPaste' -LongDescription 'Paste from clipboard with leading/trailing whitespace trimmed' -ScriptBlock {
    $clipboard = Get-Clipboard -Raw
    if ($null -ne $clipboard) {
        $clipboard = $clipboard.Trim()
        [Microsoft.PowerShell.PSConsoleReadLine]::Insert($clipboard)
    }
}

# Alt+Up: Navigate to parent directory
Set-PSReadLineKeyHandler -Key 'Alt+UpArrow' -BriefDescription 'GoUp' -LongDescription 'Navigate to parent directory' -ScriptBlock {
    [Microsoft.PowerShell.PSConsoleReadLine]::RevertLine()
    [Microsoft.PowerShell.PSConsoleReadLine]::Insert('Set-Location -Path ..')
    [Microsoft.PowerShell.PSConsoleReadLine]::AcceptLine()
}

# Alt+Left: Navigate back in directory stack
Set-PSReadLineKeyHandler -Key 'Alt+LeftArrow' -BriefDescription 'GoBack' -LongDescription 'Navigate back in directory stack' -ScriptBlock {
    [Microsoft.PowerShell.PSConsoleReadLine]::RevertLine()
    [Microsoft.PowerShell.PSConsoleReadLine]::Insert('Pop-Location')
    [Microsoft.PowerShell.PSConsoleReadLine]::AcceptLine()
}

# Ctrl+L: Clear screen (override default to also reset prompt position)
Set-PSReadLineKeyHandler -Key 'Ctrl+l' -BriefDescription 'ClearAndRedraw' -LongDescription 'Clear screen and redraw prompt' -ScriptBlock {
    [Console]::Clear()
    [Microsoft.PowerShell.PSConsoleReadLine]::InvokePrompt()
}

# F1: Show custom help for keybindings
Set-PSReadLineKeyHandler -Key 'F1' -BriefDescription 'ShowProfileHelp' -LongDescription 'Display profile keybinding reference' -ScriptBlock {
    [Microsoft.PowerShell.PSConsoleReadLine]::RevertLine()
    [Microsoft.PowerShell.PSConsoleReadLine]::Insert('Show-ProfileKeybindings')
    [Microsoft.PowerShell.PSConsoleReadLine]::AcceptLine()
}

# Ctrl+Alt+P: Toggle prediction source
Set-PSReadLineKeyHandler -Key 'Ctrl+Alt+p' -BriefDescription 'TogglePrediction' -LongDescription 'Toggle predictive IntelliSense on/off' -ScriptBlock {
    $current = (Get-PSReadLineOption).PredictionSource
    if ($current -eq 'None') {
        if ($PSVersionTable.PSVersion.Major -ge 7 -and $PSVersionTable.PSVersion.Minor -ge 2) {
            Set-PSReadLineOption -PredictionSource HistoryAndPlugin
        }
        else {
            Set-PSReadLineOption -PredictionSource History
        }
    }
    else {
        Set-PSReadLineOption -PredictionSource None
    }
}

# Parenthesis/bracket auto-pairing
Set-PSReadLineKeyHandler -Key '(' -BriefDescription 'InsertPairedParens' -LongDescription 'Insert matching parentheses' -ScriptBlock {
    param($key, $arg)
    $selectionStart = $null
    $selectionLength = $null
    [Microsoft.PowerShell.PSConsoleReadLine]::GetSelectionState([ref]$selectionStart, [ref]$selectionLength)
    $line = $null
    $cursor = $null
    [Microsoft.PowerShell.PSConsoleReadLine]::GetBufferState([ref]$line, [ref]$cursor)

    if ($selectionStart -ne -1) {
        $selectedText = $line.Substring($selectionStart, $selectionLength)
        [Microsoft.PowerShell.PSConsoleReadLine]::Replace($selectionStart, $selectionLength, "($selectedText)")
        [Microsoft.PowerShell.PSConsoleReadLine]::SetCursorPosition($selectionStart + $selectionLength + 2)
    }
    else {
        [Microsoft.PowerShell.PSConsoleReadLine]::Insert('()')
        [Microsoft.PowerShell.PSConsoleReadLine]::SetCursorPosition($cursor + 1)
    }
}

Set-PSReadLineKeyHandler -Key '[' -BriefDescription 'InsertPairedBrackets' -LongDescription 'Insert matching brackets' -ScriptBlock {
    param($key, $arg)
    $selectionStart = $null
    $selectionLength = $null
    [Microsoft.PowerShell.PSConsoleReadLine]::GetSelectionState([ref]$selectionStart, [ref]$selectionLength)
    $line = $null
    $cursor = $null
    [Microsoft.PowerShell.PSConsoleReadLine]::GetBufferState([ref]$line, [ref]$cursor)

    if ($selectionStart -ne -1) {
        $selectedText = $line.Substring($selectionStart, $selectionLength)
        [Microsoft.PowerShell.PSConsoleReadLine]::Replace($selectionStart, $selectionLength, "[$selectedText]")
        [Microsoft.PowerShell.PSConsoleReadLine]::SetCursorPosition($selectionStart + $selectionLength + 2)
    }
    else {
        [Microsoft.PowerShell.PSConsoleReadLine]::Insert('[]')
        [Microsoft.PowerShell.PSConsoleReadLine]::SetCursorPosition($cursor + 1)
    }
}

Set-PSReadLineKeyHandler -Key '{' -BriefDescription 'InsertPairedBraces' -LongDescription 'Insert matching braces' -ScriptBlock {
    param($key, $arg)
    $selectionStart = $null
    $selectionLength = $null
    [Microsoft.PowerShell.PSConsoleReadLine]::GetSelectionState([ref]$selectionStart, [ref]$selectionLength)
    $line = $null
    $cursor = $null
    [Microsoft.PowerShell.PSConsoleReadLine]::GetBufferState([ref]$line, [ref]$cursor)

    if ($selectionStart -ne -1) {
        $selectedText = $line.Substring($selectionStart, $selectionLength)
        [Microsoft.PowerShell.PSConsoleReadLine]::Replace($selectionStart, $selectionLength, "{$selectedText}")
        [Microsoft.PowerShell.PSConsoleReadLine]::SetCursorPosition($selectionStart + $selectionLength + 2)
    }
    else {
        [Microsoft.PowerShell.PSConsoleReadLine]::Insert('{}')
        [Microsoft.PowerShell.PSConsoleReadLine]::SetCursorPosition($cursor + 1)
    }
}

Set-PSReadLineKeyHandler -Key '"' -BriefDescription 'InsertPairedQuotes' -LongDescription 'Insert matching double quotes' -ScriptBlock {
    param($key, $arg)
    $line = $null
    $cursor = $null
    [Microsoft.PowerShell.PSConsoleReadLine]::GetBufferState([ref]$line, [ref]$cursor)

    # If next char is already a quote, just move past it
    if ($cursor -lt $line.Length -and $line[$cursor] -eq '"') {
        [Microsoft.PowerShell.PSConsoleReadLine]::SetCursorPosition($cursor + 1)
    }
    else {
        $selectionStart = $null
        $selectionLength = $null
        [Microsoft.PowerShell.PSConsoleReadLine]::GetSelectionState([ref]$selectionStart, [ref]$selectionLength)
        if ($selectionStart -ne -1) {
            $selectedText = $line.Substring($selectionStart, $selectionLength)
            [Microsoft.PowerShell.PSConsoleReadLine]::Replace($selectionStart, $selectionLength, "`"$selectedText`"")
            [Microsoft.PowerShell.PSConsoleReadLine]::SetCursorPosition($selectionStart + $selectionLength + 2)
        }
        else {
            [Microsoft.PowerShell.PSConsoleReadLine]::Insert('""')
            [Microsoft.PowerShell.PSConsoleReadLine]::SetCursorPosition($cursor + 1)
        }
    }
}

Set-PSReadLineKeyHandler -Key "'" -BriefDescription 'InsertPairedSingleQuotes' -LongDescription 'Insert matching single quotes' -ScriptBlock {
    param($key, $arg)
    $line = $null
    $cursor = $null
    [Microsoft.PowerShell.PSConsoleReadLine]::GetBufferState([ref]$line, [ref]$cursor)

    if ($cursor -lt $line.Length -and $line[$cursor] -eq "'") {
        [Microsoft.PowerShell.PSConsoleReadLine]::SetCursorPosition($cursor + 1)
    }
    else {
        $selectionStart = $null
        $selectionLength = $null
        [Microsoft.PowerShell.PSConsoleReadLine]::GetSelectionState([ref]$selectionStart, [ref]$selectionLength)
        if ($selectionStart -ne -1) {
            $selectedText = $line.Substring($selectionStart, $selectionLength)
            [Microsoft.PowerShell.PSConsoleReadLine]::Replace($selectionStart, $selectionLength, "'$selectedText'")
            [Microsoft.PowerShell.PSConsoleReadLine]::SetCursorPosition($selectionStart + $selectionLength + 2)
        }
        else {
            [Microsoft.PowerShell.PSConsoleReadLine]::Insert("''")
            [Microsoft.PowerShell.PSConsoleReadLine]::SetCursorPosition($cursor + 1)
        }
    }
}

#endregion

#region -- History Filtering --------------------------------------------------

if ($Global:ProfileConfig.HistoryFilterSensitive) {
    $sensitivePatterns = $Global:ProfileConfig.SensitivePatterns
    if ($null -eq $sensitivePatterns -or $sensitivePatterns.Count -eq 0) {
        $sensitivePatterns = @('password', 'secret', 'token', 'apikey', 'ConvertTo-SecureString')
    }

    Set-PSReadLineOption -AddToHistoryHandler {
        param([string]$line)
        foreach ($pattern in $sensitivePatterns) {
            if ($line -match $pattern) {
                return $false
            }
        }
        # Skip very short commands (typos)
        if ($line.Length -lt 2) {
            return $false
        }
        return $true
    }.GetNewClosure()
}

#endregion

#region -- Keybinding Help ----------------------------------------------------

function Show-ProfileKeybindings {
    <#
    .SYNOPSIS
        Displays the custom keybinding reference card.
    #>
    [CmdletBinding()]
    param()

    $tc = $Global:Theme
    Write-Host ''
    Write-Host -Object '  +--------------------------------------------------+' -ForegroundColor $tc.Primary
    Write-Host -Object '  �         KEYBINDING REFERENCE CARD                �' -ForegroundColor $tc.Primary
    Write-Host -Object '  �--------------------------------------------------�' -ForegroundColor $tc.Primary

    $bindings = @(
        @('Ctrl+R',         'Fuzzy reverse history search')
        @('Ctrl+F',         'Accept next suggestion word')
        @('Ctrl+Space',     'Menu complete (tab on steroids)')
        @('Ctrl+Shift+C',   'Copy command line to clipboard')
        @('Ctrl+Shift+V',   'Smart paste (trimmed)')
        @('Ctrl+L',         'Clear screen & redraw')
        @('Ctrl+Alt+P',     'Toggle predictive IntelliSense')
        @('Alt+Up',         'Go to parent directory')
        @('Alt+Left',       'Pop directory stack (go back)')
        @('Alt+A',          'Accept next suggestion word')
        @('F1',             'Show this help')
        @('F2',             'Toggle prediction view style')
        @('( [ { " ''',     'Auto-pair / surround selection')
    )

    foreach ($binding in $bindings) {
        $keyStr = $binding[0].PadRight(18)
        Write-Host -Object "  � " -ForegroundColor $tc.Primary -NoNewline
        Write-Host -Object $keyStr -ForegroundColor $tc.Accent -NoNewline
        Write-Host -Object $binding[1].PadRight(31) -ForegroundColor $tc.Text -NoNewline
        Write-Host -Object '�' -ForegroundColor $tc.Primary
    }

    Write-Host -Object '  +--------------------------------------------------+' -ForegroundColor $tc.Primary
    Write-Host ''
}

#endregion
