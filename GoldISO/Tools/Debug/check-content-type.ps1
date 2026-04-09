# Let me compare what's different between running directly vs parsing
# Try to find what's really going on with a simpler test

# First, let's see what's the actual type of the content being parsed
$content = Get-Content 'C:\Users\C-Man\GoldISO\Scripts\Apply-Image.ps1' -Raw
Write-Host "Content type: $($content.GetType().FullName)"
Write-Host "Content length: $($content.Length)"

# Check if there are any hidden characters
$hiddenPattern = "[^\x09\x0A\x0D\x20-\x7E\x80-\xFF]"
if ($content -match $hiddenPattern) {
    Write-Host "Found hidden/non-ASCII characters!"
    $matches.Value | ForEach-Object { Write-Host "  Found: $($_)" }
} else {
    Write-Host "No hidden characters found - content is ASCII/UTF-8 clean"
}

# Try parsing a smaller snippet
$snippet = @"
#Requires -Version 5.1

[CmdletBinding()]
param(
    [string]`$Test = ""
)
"@
$errors2 = $null
$tokens2 = $null
$ast2 = [System.Management.Automation.Language.Parser]::ParseScriptBlock($snippet, [ref]$tokens2, [ref]$errors2)
Write-Host "`nSnippet parse errors: $($errors2.Count)"