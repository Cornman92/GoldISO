$content = Get-Content 'C:\Users\C-Man\GoldISO\Scripts\Apply-Image.ps1' -Raw
$lines = $content -split "`n"

# Find line containing position 1129
$charCount = 0
for ($i = 0; $i -lt $lines.Length; $i++) {
    $lineLen = $lines[$i].Length + 1  # +1 for newline
    if ($charCount + $lineLen -gt 1129) {
        Write-Host "Line $($i+1): $($lines[$i])"
        break
    }
    $charCount += $lineLen
}

# Also check line 8310
$charCount = 0
for ($i = 0; $i -lt $lines.Length; $i++) {
    $lineLen = $lines[$i].Length + 1
    if ($charCount + $lineLen -gt 8310) {
        Write-Host "Line $($i+1): $($lines[$i])"
        break
    }
    $charCount += $lineLen
}