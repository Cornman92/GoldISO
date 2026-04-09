#Requires -Version 5.1
# Check for hidden characters in Export-Settings.ps1

$file = "Scripts/Export-Settings.ps1"
$bytes = [System.IO.File]::ReadAllBytes($file)
$text = [System.Text.Encoding]::UTF8.GetString($bytes)

# Show lines 35-45 with line numbers
$lines = $text -split "`n"
for ($i = 34; $i -lt 45 -and $i -lt $lines.Count; $i++) {
    $line = $lines[$i]
    $cleanLine = $line -replace '[^\x20-\x7E\x09\x0A\x0D]', { "[{0:X2}]" -f [int]$_.Value[0] }
    Write-Host "Line $($i+1): $cleanLine"
    Write-Host "  Hex first 30: " -NoNewline
    for ($j = 0; $j -lt [Math]::Min(30, $line.Length); $j++) {
        Write-Host ("{0:X2} " -f [int]$line[$j]) -NoNewline
    }
    Write-Host ""
}