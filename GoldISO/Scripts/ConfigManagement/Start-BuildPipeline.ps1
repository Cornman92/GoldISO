#Requires -Version 5.1
<#
.SYNOPSIS
    Automated CI/CD pipeline script for GoldISO builds.

.DESCRIPTION
    Orchestrates the complete GoldISO build pipeline with stages:
    - Environment validation
    - Source validation (autounattend.xml, settings)
    - Build execution
    - Post-build validation
    - Artifact generation
    - Optional deployment to test VM

.PARAMETER SkipTests
    Skip validation stages.

.PARAMETER DeployToVM
    Automatically deploy built ISO to test Hyper-V VM.

.PARAMETER VMName
    Name for test VM. Default: GoldISO-Test-$(Get-Date -Format yyyyMMdd)

.PARAMETER Notify
    Send notification on completion (requires webhook configuration).

.PARAMETER KeepArtifacts
    Number of build artifacts to keep. Default: 5

.PARAMETER Branch
    Git branch to build from. Default: current branch

.PARAMETER Mode
    Pipeline execution mode:
      Quick    " Build + validate, no VM deploy (default)
      VM       " All stages including VM deploy
      Validate " Validation only, no build

.EXAMPLE
    .\Start-BuildPipeline.ps1

.EXAMPLE
    .\Start-BuildPipeline.ps1 -Mode VM -VMName "GoldISO-Test"

.EXAMPLE
    .\Start-BuildPipeline.ps1 -Mode Validate

.EXAMPLE
    .\Start-BuildPipeline.ps1 -KeepArtifacts 3 -Verbose
#>
[CmdletBinding()]
param(
    [ValidateSet("Quick", "VM", "Validate")]
    [string]$Mode = "Quick",
    [switch]$SkipTests,
    [switch]$DeployToVM,
    [string]$VMName = "GoldISO-Test-$(Get-Date -Format yyyyMMdd-HHmmss)",
    [switch]$Notify,
    [int]$KeepArtifacts = 5,
    [string]$Branch
)

#region """""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""
# Initialization
# """""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""

$ErrorActionPreference = "Stop"
$script:StartTime = Get-Date
$script:StageResults = [System.Collections.Generic.List[hashtable]]::new()
$script:PipelineStatus = "Running"

$commonModule = Join-Path $PSScriptRoot "Modules\GoldISO-Common.psm1"
if (Test-Path $commonModule) {
    Import-Module $commonModule -Force
}

$script:LogDir = Join-Path $PSScriptRoot "..\Logs\Pipeline"
$timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
$script:LogFile = Join-Path $script:LogDir "pipeline-$timestamp.log"
$script:ArtifactDir = Join-Path $PSScriptRoot "..\Artifacts"

New-Item -ItemType Directory -Path $script:LogDir -Force -ErrorAction SilentlyContinue | Out-Null
New-Item -ItemType Directory -Path $script:ArtifactDir -Force -ErrorAction SilentlyContinue | Out-Null

function Write-PipelineLog {
    param(
        [string]$Message,
        [ValidateSet("INFO", "WARN", "ERROR", "SUCCESS", "STAGE")][string]$Level = "INFO"
    )
    $ts = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $entry = "[$ts] [$Level] $Message"

    $color = switch ($Level) {
        "ERROR" { "Red" }
        "WARN" { "Yellow" }
        "SUCCESS" { "Green" }
        "STAGE" { "Cyan" }
        default { "White" }
    }
    Write-Host $entry -ForegroundColor $color
    Add-Content -Path $script:LogFile -Value $entry -ErrorAction SilentlyContinue
}

function Invoke-PipelineStage {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Name,

        [Parameter(Mandatory = $true)]
        [scriptblock]$ScriptBlock,

        [switch]$ContinueOnError
    )

    Write-PipelineLog "========================================" "STAGE"
    Write-PipelineLog "STAGE: $Name" "STAGE"
    Write-PipelineLog "========================================" "STAGE"

    $stageStart = Get-Date
    $result = @{
        Name = $Name
        StartTime = $stageStart
        EndTime = $null
        Duration = $null
        Status = "Running"
        Error = $null
        Output = $null
    }

    try {
        $result.Output = & $ScriptBlock 2>&1
        $result.Status = "Success"
        Write-PipelineLog "$Name completed successfully" "SUCCESS"
    }
    catch {
        $result.Status = "Failed"
        $result.Error = $_.Exception.Message
        Write-PipelineLog "$Name failed: $($_.Exception.Message)" "ERROR"
        if (-not $ContinueOnError) {
            throw
        }
    }

    $result.EndTime = Get-Date
    $result.Duration = $result.EndTime - $stageStart
    $script:StageResults.Add($result)

    return $result
}

Write-PipelineLog "GoldISO Build Pipeline Started" "STAGE"
Write-PipelineLog "Timestamp: $timestamp" "INFO"
Write-PipelineLog "Mode: $Mode" "INFO"
Write-PipelineLog "Working Directory: $(Get-Location)" "INFO"

# Mode overrides: VM enables VM deploy; Validate disables build
if ($Mode -eq "VM")      { $DeployToVM = $true }
if ($Mode -eq "Validate") { $SkipTests  = $false }

#endregion

#region """""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""
# Pipeline Stages
# """""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""

$stage_EnvCheck = {
    Write-PipelineLog "Validating build environment..." "INFO"

    # Check required tools
    $requiredTools = @(
        @{ Name = "PowerShell"; Command = "Get-Host"; Version = "5.1" }
        @{ Name = "DISM"; Command = "Get-Command dism"; Version = $null }
        @{ Name = "oscdimg"; Command = "Get-Command oscdimg -ErrorAction SilentlyContinue"; Version = $null }
    )

    foreach ($tool in $requiredTools) {
        try {
            Invoke-Expression $tool.Command | Out-Null
            Write-PipelineLog "  $($tool.Name): OK" "SUCCESS"
        }
        catch {
            throw "Required tool not found: $($tool.Name)"
        }
    }

    # Check disk space
    $cDrive = Get-Volume -DriveLetter C
    $freeGB = [math]::Round($cDrive.SizeRemaining / 1GB, 2)
    if ($freeGB -lt 20) {
        throw "Insufficient disk space: $freeGB GB free (minimum 20 GB required)"
    }
    Write-PipelineLog "  Disk Space: $freeGB GB free" "SUCCESS"

    # Check admin privileges
    $isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
        [Security.Principal.WindowsBuiltInRole]::Administrator)
    if (-not $isAdmin) {
        throw "Administrator privileges required"
    }
    Write-PipelineLog "  Admin Privileges: Confirmed" "SUCCESS"

    return @{ DiskSpaceGB = $freeGB; IsAdmin = $isAdmin }
}

$stage_SourceValidation = {
    if ($SkipTests) {
        Write-PipelineLog "Skipping source validation (SkipTests specified)" "WARN"
        return
    }

    Write-PipelineLog "Validating source files..." "INFO"

    # Run PSScriptAnalyzer lint
    $lintScript = Join-Path $PSScriptRoot "Invoke-Lint.ps1"
    if (Test-Path $lintScript) {
        Write-PipelineLog "  Running PSScriptAnalyzer lint..." "INFO"
        $lintExit = 0
        & $lintScript -ErrorAction SilentlyContinue
        $lintExit = $LASTEXITCODE
        if ($lintExit -ne 0) {
            throw "Lint check failed " fix script errors before building"
        }
        Write-PipelineLog "  Lint: Passed" "SUCCESS"
    }

    # Validate autounattend.xml exists
    $unattendPath = Join-Path (Get-GoldISORoot) "autounattend.xml"
    if (-not (Test-Path $unattendPath)) {
        throw "autounattend.xml not found at: $unattendPath"
    }
    Write-PipelineLog "  autounattend.xml: Found" "SUCCESS"

    # Run XML validation
    $testScript = Join-Path $PSScriptRoot "Test-UnattendXML.ps1"
    if (Test-Path $testScript) {
        $testOutput = & $testScript -PassThru
        if ($testOutput.Status -ne "Passed") {
            throw "autounattend.xml validation failed: $($testOutput.Status)"
        }
        Write-PipelineLog "  autounattend.xml validation: Passed ($($testOutput.Passed) tests)" "SUCCESS"
    }

    # Check git status if in repo
    try {
        $gitStatus = git status --short 2>$null
        if ($gitStatus) {
            Write-PipelineLog "  Git Status: Uncommitted changes detected" "WARN"
            Write-PipelineLog "    $($gitStatus -join "`n    ")" "WARN"
        }
        else {
            Write-PipelineLog "  Git Status: Clean" "SUCCESS"
        }

        # Get branch info
        $currentBranch = git branch --show-current 2>$null
        Write-PipelineLog "  Git Branch: $currentBranch" "INFO"
    }
    catch {
        Write-PipelineLog "  Git: Not a repository or git not available" "INFO"
    }

    return @{ UnattendValid = $true }
}

$stage_Build = {
    Write-PipelineLog "Starting ISO build..." "INFO"

    $buildScript = Join-Path $PSScriptRoot "Build-GoldISO.ps1"
    if (-not (Test-Path $buildScript)) {
        throw "Build script not found: $buildScript"
    }

    $outputIso = Join-Path $script:ArtifactDir "GoldISO-$timestamp.iso"

    # Execute build with logging
    $buildOutput = & $buildScript -OutputISO $outputIso 2>&1
    $buildOutput | ForEach-Object { Write-PipelineLog "  BUILD: $_" "INFO" }

    if ($LASTEXITCODE -ne 0) {
        throw "Build script failed with exit code $LASTEXITCODE"
    }

    if (-not (Test-Path $outputIso)) {
        throw "Build completed but ISO not found at: $outputIso"
    }

    $isoSize = (Get-Item $outputIso).Length
    Write-PipelineLog "Build completed: $outputIso ($([math]::Round($isoSize / 1MB, 2)) MB)" "SUCCESS"

    return @{ ISOPath = $outputIso; ISOSize = $isoSize }
}

$stage_PostBuildValidation = {
    if ($SkipTests) {
        Write-PipelineLog "Skipping post-build validation" "WARN"
        return
    }

    Write-PipelineLog "Validating build artifacts..." "INFO"

    $isoPath = ($script:StageResults | Where-Object { $_.Name -eq "Build" }).Output.ISOPath

    if (-not (Test-Path $isoPath)) {
        throw "ISO file not found for validation"
    }

    # Mount ISO for validation
    try {
        $mount = Mount-DiskImage -ImagePath $isoPath -StorageType ISO -PassThru -ErrorAction Stop
        $driveLetter = ($mount | Get-Volume).DriveLetter

        # Check required files exist on ISO
        $requiredFiles = @("sources\install.wim", "sources\boot.wim", "autounattend.xml")
        $missingFiles = @()

        foreach ($file in $requiredFiles) {
            $fullPath = "$driveLetter`:\$file"
            if (-not (Test-Path $fullPath)) {
                $missingFiles += $file
            }
        }

        Dismount-DiskImage -ImagePath $isoPath -ErrorAction SilentlyContinue

        if ($missingFiles.Count -gt 0) {
            throw "Missing required files on ISO: $($missingFiles -join ', ')"
        }

        Write-PipelineLog "  ISO structure: Valid" "SUCCESS"
    }
    catch {
        Dismount-DiskImage -ImagePath $isoPath -ErrorAction SilentlyContinue
        throw "ISO validation failed: $_"
    }

    return @{ StructureValid = $true }
}

$stage_ArtifactCleanup = {
    Write-PipelineLog "Cleaning old artifacts (keeping $KeepArtifacts)..." "INFO"

    $artifacts = Get-ChildItem $script:ArtifactDir -Filter "GoldISO-*.iso" | Sort-Object LastWriteTime -Descending

    if ($artifacts.Count -gt $KeepArtifacts) {
        $toDelete = $artifacts | Select-Object -Skip $KeepArtifacts
        foreach ($artifact in $toDelete) {
            try {
                Remove-Item $artifact.FullName -Force
                Write-PipelineLog "  Removed: $($artifact.Name)" "INFO"
            }
            catch {
                Write-PipelineLog "  Could not remove: $($artifact.Name)" "WARN"
            }
        }
    }

    Write-PipelineLog "Artifact cleanup completed" "SUCCESS"
    return @{ Kept = $KeepArtifacts; Removed = $toDelete.Count }
}

$stage_DeployToVM = {
    if (-not $DeployToVM) {
        Write-PipelineLog "Skipping VM deployment (not requested)" "INFO"
        return
    }

    Write-PipelineLog "Deploying to test VM: $VMName..." "INFO"

    $isoPath = ($script:StageResults | Where-Object { $_.Name -eq "Build" }).Output.ISOPath

    $deployScript = Join-Path $PSScriptRoot "New-TestVM.ps1"
    if (-not (Test-Path $deployScript)) {
        throw "VM deployment script not found: $deployScript"
    }

    $deployOutput = & $deployScript -VMName $VMName -ISOPath $isoPath -StartAfterCreation 2>&1
    $deployOutput | ForEach-Object { Write-PipelineLog "  DEPLOY: $_" "INFO" }

    if ($LASTEXITCODE -ne 0) {
        throw "VM deployment failed"
    }

    Write-PipelineLog "VM deployed successfully: $VMName" "SUCCESS"
    return @{ VMName = $VMName; ISOUsed = $isoPath }
}

#endregion

#region """""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""
# Main Execution
# """""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""

try {
    # Execute stages
    Invoke-PipelineStage -Name "Environment Check" -ScriptBlock $stage_EnvCheck
    Invoke-PipelineStage -Name "Source Validation" -ScriptBlock $stage_SourceValidation -ContinueOnError:$SkipTests

    if ($Mode -ne "Validate") {
        Invoke-PipelineStage -Name "Build" -ScriptBlock $stage_Build
        Invoke-PipelineStage -Name "Post-Build Validation" -ScriptBlock $stage_PostBuildValidation -ContinueOnError:$SkipTests
        Invoke-PipelineStage -Name "Artifact Cleanup" -ScriptBlock $stage_ArtifactCleanup -ContinueOnError
        Invoke-PipelineStage -Name "Deploy to VM" -ScriptBlock $stage_DeployToVM -ContinueOnError
    }

    $script:PipelineStatus = "Success"
}
catch {
    $script:PipelineStatus = "Failed"
    Write-PipelineLog "Pipeline failed: $_" "ERROR"
}

# Generate pipeline report
$totalDuration = (Get-Date) - $script:StartTime

Write-PipelineLog "========================================" "STAGE"
Write-PipelineLog "PIPELINE SUMMARY" "STAGE"
Write-PipelineLog "========================================" "STAGE"

foreach ($stage in $script:StageResults) {
    $statusColor = switch ($stage.Status) {
        "Success" { "SUCCESS" }
        "Failed" { "ERROR" }
        default { "WARN" }
    }
    Write-PipelineLog "$($stage.Name): $($stage.Status) ($([math]::Round($stage.Duration.TotalSeconds, 1))s)" $statusColor
}

Write-PipelineLog "----------------------------------------" "INFO"
Write-PipelineLog "Total Duration: $($totalDuration.ToString('hh\:mm\:ss'))" "INFO"
Write-PipelineLog "Final Status: $script:PipelineStatus" $(if($script:PipelineStatus -eq "Success"){"SUCCESS"}else{"ERROR"})

# Export pipeline report
$pipelineReport = @{
    Timestamp = $timestamp
    Status = $script:PipelineStatus
    Duration = $totalDuration.ToString()
    Stages = $script:StageResults | ForEach-Object {
        @{
            Name = $_.Name
            Status = $_.Status
            Duration = $_.Duration.ToString()
            Error = $_.Error
        }
    }
}

$reportPath = Join-Path $script:LogDir "pipeline-report-$timestamp.json"
$pipelineReport | ConvertTo-Json -Depth 5 | Set-Content $reportPath
Write-PipelineLog "Pipeline report saved to: $reportPath" "INFO"

# Exit with appropriate code
exit $(if ($script:PipelineStatus -eq "Success") { 0 } else { 1 })
