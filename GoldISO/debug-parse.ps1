$file = "Scripts/Export-Settings.ps1"
$content = [System.IO.File]::ReadAllText($file)

# Write with UTF8 NO BOM to temp file
$temp = "$env:TEMP\ExportSettingsTest.ps1"
$utf8NoBom = New-Object System.Text.UTF8Encoding $false
[System.IO.File]::WriteAllText($temp, $content, $utf8NoBom)

# Now parse original file with ParseFile
$errors1 = $null
$tokens1 = $null
[System.Management.Automation.Language.Parser]::ParseFile($file, [ref]$tokens1, [ref]$errors1)

Write-Host "=== ParseFile on original ==="
if ($errors1) {
    $errors1 | ForEach-Object { Write-Host "Error: $($_.Message)" }
} else {
    Write-Host "OK"
}

# Parse temp file
$errors2 = $null
$tokens2 = $null
[System.Management.Automation.Language.Parser]::ParseFile($temp, [ref]$tokens2, [ref]$errors2)

Write-Host ""
Write-Host "=== ParseFile on temp (no BOM) ==="
if ($errors2) {
    $errors2 | ForEach-Object { Write-Host "Error: $($_.Message)" }
} else {
    Write-Host "OK"
}

# Check byte difference
$origBytes = [System.IO.File]::ReadAllBytes($file)
$tempBytes = [System.IO.File]::ReadAllBytes($temp)
Write-Host ""
Write-Host "Original first 20 bytes: $($origBytes[0..19] -join ', ')"
Write-Host "Temp first 20 bytes: $($tempBytes[0..19] -join ', ')"

Remove-Item $temp -ErrorAction SilentlyContinue