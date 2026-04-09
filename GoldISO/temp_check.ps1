$excluded = @(
    "Capture-Image.ps1", "shrink-and-recovery.ps1", "Apply-Image.ps1",
    "Audit-Sysprep.ps1", "Backup-Macrium.ps1", "Build-ISO-With-Settings.ps1",
    "Configure-RamDisk.ps1", "Configure-RemoteAccess.ps1", "Create-AuditShortcuts.ps1",
    "Export-Settings.ps1", "Get.ps1", "Install-PostInstallDrivers.ps1",
    "install-ramdisk.ps1", "install-usb-apps.ps1", "Invoke-Lint.ps1",
    "Setup-DriveLetters.ps1", "Start-BuildPipeline.ps1", "Build-Autounattend.ps1",
    "CompleteBuild.ps1", "New-EnhancedStandaloneBuild.ps1", "Convert-WingetExport.ps1",
    "Scan-InstalledApps.ps1"
)
$all = Get-ChildItem -Path Scripts -Filter *.ps1 -Recurse | Select-Object -ExpandProperty Name
Write-Host "Total scripts: $($all.Count)"
Write-Host "Excluded: $($excluded.Count)"
$nonExcluded = $all | Where-Object { $_ -notin $excluded }
Write-Host "Non-excluded: $($nonExcluded.Count)"
Write-Host "---"
$nonExcluded