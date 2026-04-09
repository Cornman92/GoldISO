$scripts = Get-ChildItem -Path Scripts -Filter *.ps1 -Recurse
$results = @()
foreach ($s in $scripts) {
    $content = Get-Content $s.FullName -Raw
    $issues = @()
    if ($content -match '[^\x00-\x7F]') { $issues += 'Unicode' }
    if ($content -notmatch '\$ErrorActionPreference\s*=') { $issues += 'NoErrorPref' }
    if ($content -notmatch 'Import-Module.*GoldISO-Common|Initialize-Logging|GoldISO-Common\.psm1') { $issues += 'NoModuleImport' }
    if ($issues.Count -gt 0) {
        $results += [PSCustomObject]@{ Name = $s.Name; Path = $s.FullName; Issues = $issues -join ',' }
    }
}
$results | Where-Object { $_.Issues -ne '' } | Format-Table -AutoSize