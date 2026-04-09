$errors = $null
$tokens = $null
$ast = [System.Management.Automation.Language.Parser]::ParseFile('C:\Users\C-Man\GoldISO\Scripts\Apply-Image.ps1', [ref]$tokens, [ref]$errors)

# Get raw content
$content = Get-Content 'C:\Users\C-Man\GoldISO\Scripts\Apply-Image.ps1' -Raw

# Check lines 25-35
$lines = $content -split "`n"
Write-Host "Lines 25-35 (0-indexed 24-34):"
for ($i = 24; $i -lt 35 -and $i -lt $lines.Length; $i++) {
    Write-Host "Line $($i+1): $($lines[$i])"
}