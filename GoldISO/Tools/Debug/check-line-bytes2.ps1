$bytes = [System.IO.File]::ReadAllBytes('C:\Users\C-Man\GoldISO\Scripts\Apply-Image.ps1')
$content = [System.Text.Encoding]::UTF8.GetString($bytes)
$lines = $content -split "`n"
$lineCount = 0
foreach ($l in $lines[0..26]) { $lineCount += $l.Length + 1 }
$pos = $lineCount

Write-Host "Line 27 ends at byte position: $pos"
Write-Host "Next 50 bytes from position:"
$bytes[$pos..($pos+49)] | ForEach-Object { '{0:X2}' -f $_ }