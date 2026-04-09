# Read, clean ALL non-ASCII, and rewrite
$filePath = 'C:\Users\C-Man\GoldISO\Scripts\Apply-Image.ps1'
$bytes = [System.IO.File]::ReadAllBytes($filePath)

# Filter to only ASCII (0-127) plus tab(9), newline(10), carriage return(13)
$cleanBytes = @()
foreach ($b in $bytes) {
    if ($b -lt 128 -or $b -eq 9 -or $b -eq 10 -or $b -eq 13) {
        $cleanBytes += $b
    }
}

# Write as ASCII (no BOM)
$cleanContent = [System.Text.Encoding]::ASCII.GetString($cleanBytes)
[System.IO.File]::WriteAllText($filePath, $cleanContent, [System.Text.Encoding]::ASCII)

Write-Host "Done. File rewritten as ASCII."