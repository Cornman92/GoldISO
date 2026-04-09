#Requires -Version 5.1

# Test to see what's happening with file encoding/parsing

Write-Host "=== Testing Export-Settings.ps1 ==="
$file1 = "Scripts/Export-Settings.ps1"
$bytes1 = [System.IO.File]::ReadAllBytes($file1)
Write-Host "File exists: $(Test-Path $file1)"
Write-Host "First 20 bytes: $($bytes1[0..19] -join ', ')"

# Try parsing
$errors = $null
$tokens = $null
[System.Management.Automation.Language.Parser]::ParseFile($file1, [ref]$tokens, [ref]$errors)
if ($errors) {
    Write-Host "Parse errors:"
    $errors | ForEach-Object { Write-Host "  $($_.Message)" }
} else {
    Write-Host "Parsed OK!"
}

Write-Host ""
Write-Host "=== Testing Apply-Image.ps1 ==="
$file2 = "Scripts/Apply-Image.ps1"
$bytes2 = [System.IO.File]::ReadAllBytes($file2)
Write-Host "File exists: $(Test-Path $file2)"
Write-Host "First 20 bytes: $($bytes2[0..19] -join ', ')"

$errors2 = $null
$tokens2 = $null
[System.Management.Automation.Language.Parser]::ParseFile($file2, [ref]$tokens2, [ref]$errors2)
if ($errors2) {
    Write-Host "Parse errors:"
    $errors2 | ForEach-Object { Write-Host "  $($_.Message)" }
} else {
    Write-Host "Parsed OK!"
}

Write-Host ""
Write-Host "=== Testing Build-GoldISO.ps1 ==="
$file3 = "Scripts/Build-GoldISO.ps1"
$bytes3 = [System.IO.File]::ReadAllBytes($file3)
Write-Host "File exists: $(Test-Path $file3)"
Write-Host "First 20 bytes: $($bytes3[0..19] -join ', ')"

$errors3 = $null
$tokens3 = $null
[System.Management.Automation.Language.Parser]::ParseFile($file3, [ref]$tokens3, [ref]$errors3)
if ($errors3) {
    Write-Host "Parse errors:"
    $errors3 | ForEach-Object { Write-Host "  $($_.Message)" }
} else {
    Write-Host "Parsed OK!"
}