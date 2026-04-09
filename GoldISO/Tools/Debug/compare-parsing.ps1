#Requires -Version 5.1

# Check beginning of Export-Settings.ps1 for any issues
$file = "Scripts/Export-Settings.ps1"
$bytes = [System.IO.File]::ReadAllBytes($file)
$text = [System.Text.Encoding]::UTF8.GetString($bytes)

# Show first 20 lines
$lines = $text -split "`n"
Write-Host "=== First 20 lines ==="
for ($i = 0; $i -lt 20; $i++) {
    Write-Host "Line $($i+1): $($lines[$i])"
}

Write-Host ""
Write-Host "=== Checking for encoding differences ==="

# Also check Build-GoldISO to compare
$file2 = "Scripts/Build-GoldISO.ps1"
$content2 = Get-Content $file2 -Raw
$ast2 = [System.Management.Automation.Language.Parser]::ParseScriptBlock([scriptblock]::Create($content2), [ref]$null, [ref]$null)
Write-Host "Build-GoldISO.ps1 parses OK: $($ast2 -ne $null)"

# Try parsing Export-Settings with simpler approach
Write-Host ""
Write-Host "=== Trying parse ==="
try {
    $errors = $null
    $ast = [System.Management.Automation.Language.Parser]::ParseFile($file, [ref]$null, [ref]$errors)
    if ($errors) {
        foreach ($e in $errors) {
            Write-Host "Error: Line $($e.Extent.StartLineNumber) - $($e.Message)"
        }
    } else {
        Write-Host "No errors"
    }
} catch {
    Write-Host "Exception: $_"
}