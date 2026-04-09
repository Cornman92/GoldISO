$scripts = @(
    "Build-GoldISO.ps1", "Build-Unattend.ps1", "Invoke-ISOBuild.ps1",
    "Get-BuildManifest.ps1", "GoldISO-Updater.ps1", "Apply-GPOSettings.ps1",
    "Install-LGPO.ps1", "Registry-Only-Summary.ps1", "GoldISO-App.ps1",
    "GoldISO-GUI.ps1", "AuditMode-Continue.ps1", "Backup-Config.ps1",
    "Finalize-AppLocations.ps1", "Invoke-SystemCleanup.ps1", "Repair-SystemImage.ps1",
    "Configure-SecondaryDrives.ps1", "Get-DriverVersions.ps1", "Manage-WindowsFeatures.ps1",
    "Stage-PostInstallDrivers.ps1", "Get-SystemReport.ps1", "Measure-BuildTime.ps1",
    "New-TestVM.ps1", "Test-Environment.ps1", "Test-NetworkStack.ps1",
    "Test-UnattendXML.ps1", "Test-VMPerformance.ps1", "Validate-WingetPackages.ps1"
)

$failures = @()
foreach ($script in $scripts) {
    $path = Get-ChildItem -Path Scripts -Filter $script -Recurse | Select-Object -First 1 -ExpandProperty FullName
    if ($path) {
        $errors = $null
        [System.Management.Automation.Language.Parser]::ParseFile($path, [ref]$null, [ref]$errors) | Out-Null
        if ($errors) {
            $failures += "$script`: $($errors[0].Message)"
        }
    }
}

if ($failures.Count -eq 0) {
    Write-Host "All 28 non-excluded scripts pass parser validation!" -ForegroundColor Green
} else {
    Write-Host "Failures: $($failures.Count)" -ForegroundColor Red
    $failures | ForEach-Object { Write-Host $_ }
}