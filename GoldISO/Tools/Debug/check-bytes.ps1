$bytes = [System.IO.File]::ReadAllBytes('C:\Users\C-Man\GoldISO\Scripts\Apply-Image.ps1')[0..50]
$bytes | ForEach-Object { '{0:X2}' -f $_ }