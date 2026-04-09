$src = "C:\Users\C-Man\GoldISO\Scripts\Apply-Image.ps1"
$content = Get-Content $src -Raw
$pos = $content.IndexOf("[CmdletBinding()]")
$start = [Math]::Max(0, $pos - 50)
$end = [Math]::Min($content.Length, $pos + 20)
Write-Host "Content around CmdletBinding:"
$content.Substring($start, $end - $start) | ForEach-Object { "[$_]" }