$bytes = [System.IO.File]::ReadAllBytes("Scripts/Export-Settings.ps1")
Write-Host "First 10 bytes: $($bytes[0..9] -join ', ')"
if ($bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) {
    Write-Host "UTF8 BOM detected!"
} else {
    Write-Host "No UTF8 BOM"
}