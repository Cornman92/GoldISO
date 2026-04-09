# Simpler test - check for any non-ASCII character in the script
$content = Get-Content 'C:\Users\C-Man\GoldISO\Scripts\Apply-Image.ps1' -Raw

# Find positions of characters with code > 127 (non-ASCII)
$problemPositions = @()
for ($i = 0; $i -lt $content.Length; $i++) {
    $c = [int]$content[$i]
    if ($c -gt 127) {
        $problemPositions += $i
    }
}

Write-Host "Found $($problemPositions.Count) non-ASCII characters"
if ($problemPositions.Count -gt 0) {
    Write-Host "First few positions: $($problemPositions[0..9] -join ', ')"
    foreach ($pos in $problemPositions[0..5]) {
        $ch = $content[$pos]
        $code = [int]$ch
        Write-Host "Position ${pos}: char '$ch' (code $code)"
        $start = [Math]::Max(0, $pos - 10)
        $len = [Math]::Min($content.Length - $start, 20)
        Write-Host "  Context: ...$($content.Substring($start, $len))..."
    }
}