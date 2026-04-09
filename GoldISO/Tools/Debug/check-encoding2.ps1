$bytes = [System.IO.File]::ReadAllBytes('C:\Users\C-Man\GoldISO\Scripts\Apply-Image.ps1')
Write-Host "First 10 bytes: $($bytes[0..9] | ForEach-Object { '{0:X2}' -f $_ })"
Write-Host "Total file size: $($bytes.Length)"