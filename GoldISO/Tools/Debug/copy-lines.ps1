$src = 'C:\Users\C-Man\GoldISO\Scripts\Apply-Image.ps1'
$lines = Get-Content $src
Set-Content -Path 'C:\Users\C-Man\GoldISO\Scripts\Apply-Image-fixed.ps1' -Value $lines

Write-Host "Copied $(($lines | Measure-Object -Line).Lines) lines to fixed file"