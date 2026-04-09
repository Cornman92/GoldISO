# Find all PS1 files with non-ASCII characters
$scriptsDir = 'C:\Users\C-Man\GoldISO\Scripts'
$filesWithIssues = @()

Get-ChildItem -Path $scriptsDir -Filter '*.ps1' -Recurse | ForEach-Object {
    $content = Get-Content $_.FullName -Raw
    $hasNonAscii = $false
    for ($i = 0; $i -lt $content.Length; $i++) {
        if ([int]$content[$i] -gt 127) {
            $hasNonAscii = $true
            break
        }
    }
    if ($hasNonAscii) {
        $filesWithIssues += $_.FullName
        Write-Host "Issue found: $($_.Name)"
    }
}

Write-Host "`nTotal files with Unicode issues: $($filesWithIssues.Count)"