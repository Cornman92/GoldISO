# Fix Unicode characters in scripts - replace with ASCII equivalents

$scriptsDir = 'C:\Users\C-Man\GoldISO\Scripts'

# Unicode replacement mapping
$replacements = @{
    [char]0x2014 = '-'      # em dash —
    [char]0x2013 = '-'     # en dash –
    [char]0x201C = '"'     # left smart quote "
    [char]0x201D = '"'     # right smart quote "
    [char]0x2018 = "'"     # left single quote '
    [char]0x2019 = "'"     # right single quote '
    [char]0x2022 = '-'     # bullet •
    [char]0x00AE = '(R)'   # registered trademark ®
    [char]0x2122 = '(TM)'  # trademark ™
    [char]0x00A0 = ' '     # non-breaking space
    [char]0x2026 = '...'   # ellipsis …
    [char]0x00E2 = ''      # corrupted char that looks like â
}

$fixedCount = 0
$files = Get-ChildItem -Path $scriptsDir -Filter '*.ps1' -Recurse

foreach ($file in $files) {
    $content = Get-Content $file.FullName -Raw
    $originalContent = $content
    
    foreach ($char in $replacements.Keys) {
        if ($content.Contains([string]$char)) {
            $content = $content.Replace([string]$char, $replacements[$char])
        }
    }
    
    # Also remove any remaining non-ASCII characters (corrupted/control chars)
    $cleanContent = ''
    for ($i = 0; $i -lt $content.Length; $i++) {
        $c = [int]$content[$i]
        if ($c -lt 128 -or $c -eq 9 -or $c -eq 10 -or $c -eq 13) {
            $cleanContent += $content[$i]
        }
    }
    $content = $cleanContent
    
    if ($content -ne $originalContent) {
        Set-Content -Path $file.FullName -Value $content -NoNewline
        Write-Host "Fixed: $($file.Name)"
        $fixedCount++
    }
}

Write-Host "`nTotal files fixed: $fixedCount"