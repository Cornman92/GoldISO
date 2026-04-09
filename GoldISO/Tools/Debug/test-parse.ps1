#Requires -Version 5.1

# Extract lines 38-46 from Export-Settings.ps1 and see if they parse
$file = "Scripts/Export-Settings.ps1"
$text = [System.IO.File]::ReadAllText($file)
$lines = $text -split "`n"

# Build a test script with only lines 1-5 and 38-46
$testScript = @"
#Requires -Version 5.1
# Comment
# Comment
# Comment
# Comment
# Comment
$(($lines[37..45]) -join "`n")
"@

# Try to parse this mini-script
try {
    $errors = $null
    $tokens = $null
    $ast = [System.Management.Automation.Language.Parser]::ParseScriptBlock([scriptblock]::Create($testScript), [ref]$tokens, [ref]$errors)
    if ($errors) {
        Write-Host "Mini script has errors:"
        foreach ($e in $errors) {
            Write-Host "  Line $($e.Extent.StartLineNumber): $($e.Message)"
        }
    } else {
        Write-Host "Mini script parses OK!"
    }
} catch {
    Write-Host "Exception: $_"
}

# Try different approach - save extracted lines to temp file
$tempFile = "$env:TEMP\test-script.ps1"
$testScript | Set-Content $tempFile -Encoding UTF8
Write-Host ""
Write-Host "Checking temp file: $tempFile"
$errors2 = $null
$tokens2 = $null
[System.Management.Automation.Language.Parser]::ParseFile($tempFile, [ref]$tokens2, [ref]$errors2)
if ($errors2) {
    Write-Host "Temp file has errors:"
    foreach ($e in $errors2) {
        Write-Host "  Line $($e.Extent.StartLineNumber): $($e.Message)"
    }
} else {
    Write-Host "Temp file parses OK!"
}
Remove-Item $tempFile -ErrorAction SilentlyContinue