$errors = $null
$tokens = $null
$ast = [System.Management.Automation.Language.Parser]::ParseFile('C:\Users\C-Man\GoldISO\Scripts\Apply-Image.ps1', [ref]$tokens, [ref]$errors)

Write-Host "All $($errors.Count) errors:"
$errors | ForEach-Object {
    Write-Host "  Line $($_.Extent.StartLineNumber): $($_.Message)"
}