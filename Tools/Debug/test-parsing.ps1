$errors = $null
$tokens = $null
$ast = [System.Management.Automation.Language.Parser]::ParseFile('C:\Users\C-Man\GoldISO\Scripts\Apply-Image.ps1', [ref]$tokens, [ref]$errors)
Write-Host "Error count: $($errors.Count)"
if ($errors.Count -gt 0) {
    Write-Host "First 3 errors:"
    $errors | Select-Object -First 3 | ForEach-Object { Write-Host $_.Message }
}