$errors = $null
$tokens = $null
$ast = [System.Management.Automation.Language.Parser]::ParseFile('C:\Users\C-Man\GoldISO\Scripts\Apply-Image.ps1', [ref]$tokens, [ref]$errors)

# List all child AST nodes
Write-Host "AST children:"
$ast.EndBlock.Statements | ForEach-Object {
    Write-Host "  Statement: $($_.GetType().FullName)"
    $_.GetChildNodes() | ForEach-Object {
        Write-Host "    Child: $($_.GetType().FullName)"
    }
}

# Let me check if there's something before param block
Write-Host "`nChecking for NamedBlock:"
$ast | Get-Member -MemberType Properties | ForEach-Object { Write-Host "  $($_.Name)" }

# Try to find param block by different method
Write-Host "`nDirect scriptblock search:"
$script:scriptblock = $ast
$ast.FindAll({ $args[0] -is [System.Management.Automation.Language.ParamBlockAst] }, $true) | ForEach-Object {
    Write-Host "Found ParamBlock: $_"
}