$errors = $null
$tokens = $null
$ast = [System.Management.Automation.Language.Parser]::ParseFile('C:\Users\C-Man\GoldISO\Scripts\Apply-Image.ps1', [ref]$tokens, [ref]$errors)

Write-Host "AST type: $($ast.GetType().FullName)"
Write-Host "AST extent start: $($ast.Extent.StartLineNumber), end: $($ast.Extent.EndLineNumber)"

# Show first few tokens
Write-Host "`nFirst 20 tokens:"
$tokens | Select-Object -First 20 | ForEach-Object {
    Write-Host "  Type: $($_.Type), Content: '$($_.Text)'"
}

# Show the 30-40 tokens to see around CmdletBinding
Write-Host "`nTokens 30-50:"
$tokens[30..50] | ForEach-Object {
    Write-Host "  Type: $($_.Type), Content: '$($_.Text)'"
}