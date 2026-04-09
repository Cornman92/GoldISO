#Requires -Version 5.1

$file = "Scripts/Export-Settings.ps1"
$tempFile = "$env:TEMP\Export-Settings-fixed.ps1"

# Read original content
$content = [System.IO.File]::ReadAllText($file)

# Write to temp without BOM (UTF8 with BOM=false)
$utf8NoBom = New-Object System.Text.UTF8Encoding $false
[System.IO.File]::WriteAllText($tempFile, $content, $utf8NoBom)

# Now parse the new file
$errors = $null
$tokens = $null
[System.Management.Automation.Language.Parser]::ParseFile($tempFile, [ref]$tokens, [ref]$errors)
if ($errors) {
    Write-Host "Fixed version still has errors:"
    foreach ($e in $errors) {
        Write-Host "  Line $($e.Extent.StartLineNumber): $($e.Message)"
    }
} else {
    Write-Host "Fixed version parses OK!"
}

# Check for BOM in original
$bytes = [System.IO.File]::ReadAllBytes($file)
if ($bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) {
    Write-Host "Original has UTF8 BOM!"
}

# Check for Unicode line separators
if ($content.Contains([char]0x2028) -or $content.Contains([char]0x2029)) {
    Write-Host "File contains Unicode line separators!"
}

# Check for other hidden chars
$allBytes = [System.IO.File]::ReadAllBytes($file)
$suspicious = $allBytes | Where-Object { $_ -gt 127 -and $_ -lt 32 -and $_ -notin @(9,10,13) }
if ($suspicious) {
    Write-Host "Suspicious bytes found: $($suspicious | ForEach-Object { '{0:X2}' -f $_ })"
}

Remove-Item $tempFile -ErrorAction SilentlyContinue