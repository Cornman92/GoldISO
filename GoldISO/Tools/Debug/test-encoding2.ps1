# Test different ways of reading files

$testFile = "Scripts/Export-Settings.ps1"

Write-Host "=== Byte-level test ==="
$bytes = [System.IO.File]::ReadAllBytes($testFile)

# Show first 50 bytes as hex
Write-Host "First 50 bytes:"
for ($i = 0; $i -lt 50; $i++) {
    Write-Host ("{0:X2} " -f $bytes[$i]) -NoNewline
    if (($i + 1) % 10 -eq 0) { Write-Host "" }
}
Write-Host ""

# Now try reading with different encodings
Write-Host ""
Write-Host "=== UTF-8 ==="
$utf8 = [System.Text.Encoding]::UTF8.GetString($bytes)
Write-Host $utf8.Substring(0, 100)

Write-Host ""
Write-Host "=== ASCII ==="
$ascii = [System.Text.Encoding]::ASCII.GetString($bytes)
Write-Host $ascii.Substring(0, 100)

Write-Host ""
Write-Host "=== Default encoding ==="
$default = [System.Text.Encoding]::Default.GetString($bytes)
Write-Host $default.Substring(0, 100)