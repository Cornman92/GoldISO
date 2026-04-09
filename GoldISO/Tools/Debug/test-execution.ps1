#Requires -Version 5.1

Write-Host "=== Test 1: Run Export-Settings.ps1 with -? ==="
$errFile = "$env:TEMP\err1.txt"
try {
    $proc = Start-Process powershell.exe -ArgumentList "-NoProfile", "-NonInteractive", "-File", "Scripts/Export-Settings.ps1", "-?" -Wait -PassThru -RedirectStandardError $errFile -WindowStyle Hidden
    Write-Host "Exit code: $($proc.ExitCode)"
    if (Test-Path $errFile) { Get-Content $errFile | Select-Object -First 5 }
} catch { Write-Host "Error: $_" }
Remove-Item $errFile -ErrorAction SilentlyContinue

Write-Host ""
Write-Host "=== Test 2: Dot-source Export-Settings.ps1 ==="
try {
    . ./Scripts/Export-Settings.ps1 -ErrorAction Stop -WarningAction Stop
} catch {
    Write-Host "Error: $($_.Exception.Message)"
}

Write-Host ""
Write-Host "=== Test 3: Get-Content + Invoke-Expression ==="
try {
    $content = Get-Content "Scripts/Export-Settings.ps1" -Raw
    $sb = [scriptblock]::Create($content)
    Invoke-Command -ScriptBlock $sb
} catch {
    Write-Host "Error: $($_.Exception.Message)"
}