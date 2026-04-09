$content = Get-Content 'C:\Users\C-Man\GoldISO\Scripts\Apply-Image.ps1' -Raw
$bytes = [System.Text.Encoding]::UTF8.GetBytes($content)

# Find all non-printable characters
$nonAscii = @()
for ($i = 0; $i -lt $bytes.Length; $i++) {
    $b = $bytes[$i]
    # Skip regular ASCII (32-126), tab (9), newline (10), carriage return (13)
    if ($b -lt 32 -and $b -ne 9 -and $b -ne 10 -and $b -ne 13) {
        $lineNumber = ($content.Substring(0, $i) -split "`n").Count
        $nonAscii += "Position $i (Line $lineNumber): 0x{0:X2}" -f $b
    }
    # Also check for non-ASCII (128-255)
    if ($b -ge 128) {
        $lineNumber = ($content.Substring(0, $i) -split "`n").Count
        $nonAscii += "Position $i (Line $lineNumber): 0x{0:X2}" -f $b
    }
}

Write-Host "Found $($nonAscii.Count) non-ASCII/non-printable bytes:"
$nonAscii | Select-Object -First 20