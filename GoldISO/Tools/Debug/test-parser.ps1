$parseResult = [System.Management.Automation.PSParser]::Tokenize((Get-Content 'C:\Users\C-Man\GoldISO\Scripts\Apply-Image.ps1' -Raw), [ref]$null)
Write-Host "Token count: $($parseResult.Count)"
Write-Host "First 10 tokens:"
$parseResult | Select-Object -First 10 | ForEach-Object { Write-Host "  $($_.Type): $($_.Content)" }