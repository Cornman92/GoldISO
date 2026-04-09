#Requires -Version 5.1
$file = "Scripts/Export-Settings.ps1"
$bytes = [System.IO.File]::ReadAllBytes($file)
$text = [System.Text.Encoding]::UTF8.GetString($bytes)
$lines = $text -split "`n"

# Show transition from line 37 to 38
Write-Host "Line 37:" 
Write-Host ("  Raw: " + $lines[36])
Write-Host "  Hex: " -NoNewline
for ($j = 0; $j -lt $lines[36].Length; $j++) {
    Write-Host ("{0:X2} " -f [int]$lines[36][$j]) -NoNewline
}
Write-Host ""
Write-Host ""

Write-Host "Line 38:"
Write-Host ("  Raw: " + $lines[37])
Write-Host "  Hex: " -NoNewline
for ($j = 0; $j -lt $lines[37].Length; $j++) {
    Write-Host ("{0:X2} " -f [int]$lines[37][$j]) -NoNewline
}
Write-Host ""

# Compare to Build-GoldISO.ps1 structure
Write-Host ""
Write-Host "=== Comparing with Build-GoldISO.ps1 ==="
Write-Host ""

$file2 = "Scripts/Build-GoldISO.ps1"
$bytes2 = [System.IO.File]::ReadAllBytes($file2)
$text2 = [System.Text.Encoding]::UTF8.GetString($bytes2)
$lines2 = $text2 -split "`n"

for ($i = 0; $i -lt 50; $i++) {
    if ($lines2[$i] -match "param\(|CmdletBinding|#>") {
        Write-Host "Build-GoldISO.ps1 Line $($i+1): $($lines2[$i])"
    }
}