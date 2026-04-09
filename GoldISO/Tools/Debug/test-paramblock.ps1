$errors = $null
$tokens = $null
$ast = [System.Management.Automation.Language.Parser]::ParseFile('C:\Users\C-Man\GoldISO\Scripts\Apply-Image.ps1', [ref]$tokens, [ref]$errors)

# Find the param block
$paramBlock = $ast.ParamBlock
Write-Host "ParamBlock: $paramBlock"
Write-Host "ParamBlock attributes: $($paramBlock.Attributes)"
Write-Host "ParamBlock parameters: $($paramBlock.Parameters)"

# Let me check what the issue is more specifically
Write-Host "`nErrors:"
$errors | ForEach-Object { 
    Write-Host "  Line $($_.Extent.StartLineNumber): $($_.Message)" 
}