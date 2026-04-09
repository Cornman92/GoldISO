#Requires -Version 5.1

$content = Get-Content "Scripts/Export-Settings.ps1" -Raw -ErrorAction SilentlyContinue
if ($content) {
    $tokens = $null
    $errors = $null
    [System.Management.Automation.Language.Parser]::ParseScriptBlock([scriptblock]::Create($content), [ref]$tokens, [ref]$errors)
    if ($errors) {
        $errors | ForEach-Object { 
            Write-Host "Line $($_.Extent.StartLineNumber): $($_.Message)" 
        }
    } else {
        Write-Host "No parse errors"
    }
}