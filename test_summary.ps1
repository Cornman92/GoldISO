$result = Invoke-Pester -Path Tests -PassThru
Write-Host "Passed: $($result.PassedCount)"
Write-Host "Failed: $($result.FailedCount)"
Write-Host "Skipped: $($result.SkippedCount)"