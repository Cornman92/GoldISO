$result = Invoke-Pester -Path Tests -PassThru
Write-Host "Failed: $($result.FailedCount)"
Write-Host "Skipped: $($result.SkippedCount)"
$result.TestResult | Where-Object { $_.Result -eq "Failed" } | ForEach-Object { Write-Host "FAILED: $($_.Describe) - $($_.Name)" }