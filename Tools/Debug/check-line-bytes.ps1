# Get bytes around line 28
$bytes = [System.IO.File]::ReadAllBytes('C:\Users\C-Man\GoldISO\Scripts\Apply-Image.ps1')

# Find the position of line 28 (after newlines)
$content = [System.Text.Encoding]::UTF8.GetString($bytes)
$lines = $content -split "`n"
$line27End = ($lines[0..26] -join "`n").Length + 1  # +1 for the newline we split on

Write-Host "Line 27 ends at byte position: $line27End"
$endPos = $line27End
Write-Host "Next 50 bytes from position $endPos:"
$bytes[$endPos..($endPos+49)] | ForEach-Object { '{0:X2}' -f $_ }