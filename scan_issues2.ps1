$scripts = Get-ChildItem -Path Scripts -Filter *.ps1 -Recurse
$results = @()
foreach ($s in $scripts) {
    $content = Get-Content $s.FullName -Raw
    $issues = @()
    if ($content -notmatch '#Requires -Version') { $issues += 'NoRequires' }
    if ($content -notmatch '\.SYNOPSIS') { $issues += 'NoSynopsis' }
    if ($content -match 'Write-Host.*-ForegroundColor.*(?<!ForegroundColor)Green(?<!Green)') { $issues += 'LocalWrite-Host' }
    if ($content -match 'function Write-Log') { $issues += 'LocalWriteLog' }
    $results += [PSCustomObject]@{ Name = $s.Name; Path = $s.FullName; Issues = $issues -join ',' }
}
$results | Where-Object { $_.Issues -ne '' } | Format-Table -AutoSize