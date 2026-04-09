#Requires -Version 5.1
<#
.SYNOPSIS
    Comprehensive system inventory and analysis report generator.

.DESCRIPTION
    Generates detailed system reports including hardware inventory, software list,
    configuration settings, performance metrics, and security status.
    Supports multiple output formats with executive and technical detail levels.

.PARAMETER DetailLevel
    Report detail level: Executive, Standard, or Technical. Default: Standard

.PARAMETER OutputFormat
    Output format: HTML, PDF (requires library), JSON, or CSV. Default: HTML

.PARAMETER Include
    Sections to include: All, Hardware, Software, Config, Security, Performance

.PARAMETER OutputPath
    Directory to save report. Default: $PSScriptRoot\..\Reports

.PARAMETER EmailTo
    Email address to send report to (requires SMTP configuration).

.EXAMPLE
    .\Get-SystemReport.ps1 -DetailLevel Technical -OutputFormat JSON

.EXAMPLE
    .\Get-SystemReport.ps1 -Include Hardware,Software -EmailTo admin@company.com
#>
[CmdletBinding()]
param(
    [ValidateSet("Executive", "Standard", "Technical")]
    [string]$DetailLevel = "Standard",

    [ValidateSet("HTML", "JSON", "CSV")]
    [string]$OutputFormat = "HTML",

    [ValidateSet("All", "Hardware", "Software", "Config", "Security", "Performance")]
    [string[]]$Include = @("All"),

    [string]$OutputPath = (Join-Path $PSScriptRoot "..\Reports"),

    [string]$EmailTo,

    [string]$EmailFrom = "$env:USERNAME@gmail.com",

    [PSCredential]$EmailCredential
)

#region """""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""
# Initialization
# """""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""

$ErrorActionPreference = "Continue"
$script:StartTime = Get-Date
$script:ReportData = @{
    GeneratedAt = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    ComputerName = $env:COMPUTERNAME
    GeneratedBy = $env:USERNAME
    DetailLevel = $DetailLevel
    Sections = @{}
}

$commonModule = Join-Path $PSScriptRoot "Modules\GoldISO-Common.psm1"
if (Test-Path $commonModule) {
    Import-Module $commonModule -Force
}

$timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
if (-not (Test-Path $OutputPath)) {
    New-Item -ItemType Directory -Path $OutputPath -Force | Out-Null
}

$script:LogFile = Join-Path $OutputPath "report-$timestamp.log"

function Write-ReportLog {
    param([string]$Message, [ValidateSet("INFO","WARN","ERROR","SUCCESS")][string]$Level = "INFO")
    $ts = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $entry = "[$ts] [$Level] $Message"
    Write-Host $entry -ForegroundColor $(switch($Level) { "ERROR"{"Red"} "WARN"{"Yellow"} "SUCCESS"{"Green"} default{"White"} })
    Add-Content -Path $script:LogFile -Value $entry -ErrorAction SilentlyContinue
}

Write-ReportLog "System Report Generation Started" "INFO"
Write-ReportLog "Detail Level: $DetailLevel | Format: $OutputFormat" "INFO"

#endregion

#region """""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""
# Data Collection Functions
# """""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""

function Get-HardwareInventory {
    if ($Include -notcontains "All" -and $Include -notcontains "Hardware") { return }

    Write-ReportLog "Collecting hardware inventory..." "INFO"
    $hardware = @{}

    # Computer System
    $cs = Get-CimInstance Win32_ComputerSystem
    $hardware.Computer = @{
        Manufacturer = $cs.Manufacturer
        Model = $cs.Model
        Type = if ($cs.PCSystemType -eq 1) { "Desktop" } elseif ($cs.PCSystemType -eq 2) { "Laptop" } else { "Other" }
        TotalPhysicalMemory = "$([math]::Round($cs.TotalPhysicalMemory / 1GB, 2)) GB"
    }

    # Processor
    $proc = Get-CimInstance Win32_Processor | Select-Object -First 1
    $hardware.Processor = @{
        Name = $proc.Name
        Cores = $proc.NumberOfCores
        LogicalProcessors = $proc.NumberOfLogicalProcessors
        BaseSpeed = "$([math]::Round($proc.MaxClockSpeed / 1000, 2)) GHz"
        Socket = $proc.SocketDesignation
    }

    # Memory modules
    $memory = Get-CimInstance Win32_PhysicalMemory | ForEach-Object {
        @{
            BankLabel = $_.BankLabel
            Capacity = "$([math]::Round($_.Capacity / 1GB, 2)) GB"
            Speed = "$($_.Speed) MHz"
            Manufacturer = $_.Manufacturer
            PartNumber = ($_.PartNumber -replace '\s+$', '')
        }
    }
    $hardware.Memory = @{
        TotalModules = $memory.Count
        TotalCapacity = "$([math]::Round(($memory | Measure-Object -Property { $_.Capacity -replace ' GB', '' } -Sum).Sum, 2)) GB"
        Modules = $memory
    }

    # Storage
    $disks = Get-PhysicalDisk | Where-Object { $_.BusType -ne 'File Backed Virtual' } | ForEach-Object {
        $partitions = $_ | Get-Partition -ErrorAction SilentlyContinue
        $volumes = $partitions | Get-Volume -ErrorAction SilentlyContinue | Where-Object { $_.DriveLetter }

        @{
            DeviceId = $_.DeviceId
            FriendlyName = $_.FriendlyName
            MediaType = $_.MediaType
            Size = "$([math]::Round($_.Size / 1GB, 2)) GB"
            HealthStatus = $_.HealthStatus
            OperationalStatus = $_.OperationalStatus -join ', '
            Volumes = $volumes | ForEach-Object {
                @{
                    DriveLetter = $_.DriveLetter
                    FileSystem = $_.FileSystemType
                    Size = "$([math]::Round($_.Size / 1GB, 2)) GB"
                    FreeSpace = "$([math]::Round($_.SizeRemaining / 1GB, 2)) GB"
                    UsedPercent = "$([math]::Round((($_.Size - $_.SizeRemaining) / $_.Size) * 100, 1))%"
                }
            }
        }
    }
    $hardware.Storage = @{
        DiskCount = $disks.Count
        Disks = $disks
    }

    # Graphics
    $gpus = Get-CimInstance Win32_VideoController | ForEach-Object {
        @{
            Name = $_.Name
            AdapterRAM = if ($_.AdapterRAM -gt 1GB) { "$([math]::Round($_.AdapterRAM / 1GB, 2)) GB" } else { "$([math]::Round($_.AdapterRAM / 1MB, 0)) MB" }
            Resolution = "$($_.CurrentHorizontalResolution) x $($_.CurrentVerticalResolution)"
            RefreshRate = "$($_.CurrentRefreshRate) Hz"
            DriverVersion = $_.DriverVersion
        }
    }
    $hardware.Graphics = @{
        GPUCount = $gpus.Count
        GPUs = $gpus
    }

    # Network
    $adapters = Get-CimInstance Win32_NetworkAdapter | Where-Object {
        $_.NetEnabled -eq $true -and $_.PhysicalAdapter -eq $true
    } | ForEach-Object {
        $config = $_ | Get-CimInstance -CimSession (Get-CimSession) -ClassName Win32_NetworkAdapterConfiguration | Where-Object { $_.IPEnabled }
        @{
            Name = $_.Name
            MACAddress = $_.MACAddress
            Speed = if ($_.Speed) { "$([math]::Round($_.Speed / 1000000000, 1)) Gbps" } else { "Unknown" }
            IPAddresses = $config.IPAddress
            DefaultGateway = $config.DefaultIPGateway
        }
    }
    $hardware.Network = @{
        AdapterCount = $adapters.Count
        Adapters = $adapters
    }

    if ($DetailLevel -eq "Technical") {
        # BIOS/UEFI
        $bios = Get-CimInstance Win32_BIOS
        $hardware.BIOS = @{
            Manufacturer = $bios.Manufacturer
            Name = $bios.Name
            Version = $bios.SMBIOSBIOSVersion
            ReleaseDate = $bios.ReleaseDate
        }

        # Motherboard
        $mb = Get-CimInstance Win32_BaseBoard
        $hardware.Motherboard = @{
            Manufacturer = $mb.Manufacturer
            Product = $mb.Product
            Version = $mb.Version
        }
    }

    $script:ReportData.Sections['Hardware'] = $hardware
    Write-ReportLog "Hardware inventory complete" "SUCCESS"
}

function Get-SoftwareInventory {
    if ($Include -notcontains "All" -and $Include -notcontains "Software") { return }

    Write-ReportLog "Collecting software inventory..." "INFO"
    $software = @{}

    # Installed programs
    $registryPaths = @(
        "HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*"
        "HKLM:\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*"
    )

    $programs = @()
    foreach ($path in $registryPaths) {
        $programs += Get-ItemProperty $path -ErrorAction SilentlyContinue |
            Where-Object { $_.DisplayName -and -not $_.SystemComponent } |
            Select-Object DisplayName, DisplayVersion, Publisher, InstallDate, @{N='Architecture';E={if ($path -match 'WOW6432Node') { 'x86' } else { 'x64' }}}, InstallLocation
    }

    $software.InstalledPrograms = @{
        Count = $programs.Count
        Programs = if ($DetailLevel -eq "Executive") {
            $programs | Select-Object -First 20 DisplayName, Publisher
        } else {
            $programs | Sort-Object DisplayName
        }
    }

    # Windows Features
    $features = Get-WindowsOptionalFeature -Online | Where-Object { $_.State -eq 'Enabled' }
    $software.WindowsFeatures = @{
        EnabledCount = $features.Count
        Features = if ($DetailLevel -eq "Executive") { @() } else { $features | Select-Object FeatureName }
    }

    # PowerShell Modules
    $modules = Get-Module -ListAvailable | Group-Object Name | ForEach-Object {
        $latest = $_.Group | Sort-Object Version -Descending | Select-Object -First 1
        @{
            Name = $latest.Name
            Version = $latest.Version
            Description = $latest.Description
        }
    }
    $software.PowerShellModules = @{
        Count = $modules.Count
        Modules = if ($DetailLevel -in @("Executive", "Standard")) { @() } else { $modules }
    }

    # Windows Version
    $os = Get-CimInstance Win32_OperatingSystem
    $software.OperatingSystem = @{
        Caption = $os.Caption
        Version = $os.Version
        BuildNumber = $os.BuildNumber
        Architecture = $os.OSArchitecture
        InstallDate = $os.InstallDate
        LastBootTime = $os.LastBootUpTime
    }

    $script:ReportData.Sections['Software'] = $software
    Write-ReportLog "Software inventory complete ($($programs.Count) programs)" "SUCCESS"
}

function Get-ConfigurationStatus {
    if ($Include -notcontains "All" -and $Include -notcontains "Config") { return }

    Write-ReportLog "Collecting configuration status..." "INFO"
    $config = @{}

    # Environment Variables
    $config.EnvironmentVariables = Get-ChildItem Env: | ForEach-Object {
        @{
            Name = $_.Name
            Value = if ($_.Name -match "SECRET|KEY|PASSWORD|TOKEN") { "***REDACTED***" } else { $_.Value }
        }
    } | Sort-Object Name

    # PowerShell Configuration
    $config.PowerShell = @{
        Version = $PSVersionTable.PSVersion.ToString()
        Edition = $PSVersionTable.PSEdition
        ExecutionPolicy = (Get-ExecutionPolicy)
        ProfilePath = $PROFILE
        ProfilesLoaded = @($PROFILE.AllUsersAllHosts, $PROFILE.AllUsersCurrentHost, $PROFILE.CurrentUserAllHosts, $PROFILE.CurrentUserCurrentHost | Where-Object { Test-Path $_ }).Count
    }

    # Windows Settings (if technical)
    if ($DetailLevel -eq "Technical") {
        $config.WindowsSettings = @{
            UACEnabled = (Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System" -Name "EnableLUA" -ErrorAction SilentlyContinue).EnableLUA -eq 1
            FirewallStatus = (Get-NetFirewallProfile | ForEach-Object { "$($_.Name): $($_.Enabled)" }) -join ', '
            RemoteDesktop = (Get-ItemProperty "HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server" -Name "fDenyTSConnections" -ErrorAction SilentlyContinue).fDenyTSConnections -eq 0
            PowerPlan = (Get-CimInstance Win32_PowerPlan -Namespace "root\cimv2\power" | Where-Object { $_.IsActive }).ElementName
        }
    }

    # Services Summary
    $services = Get-Service | Group-Object Status
    $config.Services = @{
        Running = ($services | Where-Object { $_.Name -eq 'Running' }).Count
        Stopped = ($services | Where-Object { $_.Name -eq 'Stopped' }).Count
        AutoNotRunning = (Get-Service | Where-Object { $_.StartType -eq 'Automatic' -and $_.Status -ne 'Running' }).Count
    }

    $script:ReportData.Sections['Configuration'] = $config
    Write-ReportLog "Configuration status complete" "SUCCESS"
}

function Get-SecurityStatus {
    if ($Include -notcontains "All" -and $Include -notcontains "Security") { return }

    Write-ReportLog "Collecting security status..." "INFO"
    $security = @{}

    # Windows Defender
    try {
        $defender = Get-MpComputerStatus
        $security.WindowsDefender = @{
            Enabled = $defender.AntivirusEnabled
            RealTimeProtection = $defender.RealTimeProtectionEnabled
            DefinitionVersion = $defender.AntivirusSignatureVersion
            DefinitionAge = $defender.AntivirusSignatureAge
            LastScan = $defender.FullScanAge
        }
    }
    catch {
        $security.WindowsDefender = @{ Enabled = "Unknown"; Error = $_.Exception.Message }
    }

    # Firewall Status
    $firewallProfiles = Get-NetFirewallProfile | ForEach-Object {
        @{
            Profile = $_.Name
            Enabled = $_.Enabled
            DefaultInbound = $_.DefaultInboundAction
            DefaultOutbound = $_.DefaultOutboundAction
        }
    }
    $security.Firewall = @{
        AllEnabled = ($firewallProfiles.Enabled -notcontains $false)
        Profiles = $firewallProfiles
    }

    # Critical Updates
    try {
        $updateSession = New-Object -ComObject Microsoft.Update.Session
        $updateSearcher = $updateSession.CreateUpdateSearcher()
        $pending = $updateSearcher.Search("IsInstalled=0 and IsHidden=0")

        $criticalUpdates = $pending.Updates | Where-Object { $_.IsImportant -or $_.AutoSelectOnWebSites }
        $security.Updates = @{
            PendingCount = $pending.Updates.Count
            CriticalPending = $criticalUpdates.Count
            Updates = if ($DetailLevel -eq "Technical") {
                $criticalUpdates | ForEach-Object { $_.Title }
            } else { @() }
        }
    }
    catch {
        $security.Updates = @{ Error = "Could not check updates" }
    }

    # Local Users (technical only)
    if ($DetailLevel -eq "Technical") {
        $users = Get-CimInstance Win32_UserAccount -Filter "LocalAccount=True" | ForEach-Object {
            @{
                Name = $_.Name
                Disabled = $_.Disabled
                PasswordRequired = $_.PasswordRequired
                PasswordChangeable = $_.PasswordChangeable
                PasswordExpires = $_.PasswordExpires
            }
        }
        $security.LocalUsers = @{
            Count = $users.Count
            EnabledAdmins = ($users | Where-Object { $_.Name -eq 'Administrator' -and -not $_.Disabled }).Count
            Users = $users
        }
    }

    $script:ReportData.Sections['Security'] = $security
    Write-ReportLog "Security status complete" "SUCCESS"
}

function Get-PerformanceMetrics {
    if ($Include -notcontains "All" -and $Include -notcontains "Performance") { return }

    Write-ReportLog "Collecting performance metrics..." "INFO"
    $performance = @{}

    # CPU Usage
    $cpu = Get-Counter '\Processor(_Total)\% Processor Time' -SampleInterval 1 -MaxSamples 3
    $performance.CPU = @{
        CurrentUsage = "$([math]::Round(($cpu.CounterSamples | Select-Object -Last 1).CookedValue, 1))%"
        AverageUsage = "$([math]::Round(($cpu.CounterSamples | Measure-Object CookedValue -Average).Average, 1))%"
    }

    # Memory Usage
    $os = Get-CimInstance Win32_OperatingSystem
    $performance.Memory = @{
        Total = "$([math]::Round($os.TotalVisibleMemorySize / 1MB, 2)) GB"
        Available = "$([math]::Round($os.FreePhysicalMemory / 1MB, 2)) GB"
        UsedPercent = "$([math]::Round((($os.TotalVisibleMemorySize - $os.FreePhysicalMemory) / $os.TotalVisibleMemorySize) * 100, 1))%"
        CommittedPercent = "$([math]::Round(($os.TotalVirtualMemorySize / ($os.TotalVisibleMemorySize + $os.TotalVirtualMemorySize)) * 100, 1))%"
    }

    # Disk Usage
    $diskPerf = Get-Counter '\LogicalDisk(_Total)\% Free Space' -ErrorAction SilentlyContinue
    $performance.Disk = @{
        AverageFreeSpace = if ($diskPerf) { "$([math]::Round(($diskPerf.CounterSamples | Measure-Object CookedValue -Average).Average, 1))%" } else { "N/A" }
    }

    # Top Processes by CPU
    $topCpu = Get-Process | Sort-Object CPU -Descending | Select-Object -First 5 | ForEach-Object {
        @{
            Name = $_.ProcessName
            Id = $_.Id
            CPU = $_.CPU
            Memory = "$([math]::Round($_.WorkingSet64 / 1MB, 1)) MB"
        }
    }
    $performance.TopProcesses = @{
        ByCPU = $topCpu
    }

    # Boot Time
    $bootTime = (Get-Date) - $os.LastBootUpTime
    $performance.SystemUptime = @{
        Days = $bootTime.Days
        Hours = $bootTime.Hours
        Minutes = $bootTime.Minutes
        TotalHours = [math]::Round($bootTime.TotalHours, 1)
    }

    $script:ReportData.Sections['Performance'] = $performance
    Write-ReportLog "Performance metrics complete" "SUCCESS"
}

#endregion

#region """""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""
# Report Generation
# """""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""

function Export-HTMLReport {
    $reportFile = Join-Path $OutputPath "SystemReport-$timestamp.html"

    $html = @"
<!DOCTYPE html>
<html>
<head>
    <title>System Report - $($env:COMPUTERNAME)</title>
    <style>
        body { font-family: 'Segoe UI', Tahoma, Geneva, Verdana, sans-serif; margin: 0; background: #f0f2f5; }
        .header { background: linear-gradient(135deg, #667eea 0%, #764ba2 100%); color: white; padding: 30px; }
        .header h1 { margin: 0; font-size: 2em; }
        .header p { margin: 10px 0 0 0; opacity: 0.9; }
        .container { max-width: 1400px; margin: 0 auto; padding: 20px; }
        .summary { display: grid; grid-template-columns: repeat(auto-fit, minmax(250px, 1fr)); gap: 20px; margin: 20px 0; }
        .summary-card { background: white; padding: 20px; border-radius: 8px; box-shadow: 0 2px 8px rgba(0,0,0,0.1); }
        .summary-card h3 { margin: 0 0 10px 0; color: #667eea; font-size: 0.9em; text-transform: uppercase; }
        .summary-card .value { font-size: 2em; font-weight: bold; color: #333; }
        .section { background: white; margin: 20px 0; border-radius: 8px; box-shadow: 0 2px 8px rgba(0,0,0,0.1); overflow: hidden; }
        .section-header { background: #f8f9fa; padding: 15px 20px; border-bottom: 1px solid #e9ecef; }
        .section-header h2 { margin: 0; color: #333; font-size: 1.3em; }
        .section-content { padding: 20px; }
        table { width: 100%; border-collapse: collapse; }
        th, td { padding: 12px; text-align: left; border-bottom: 1px solid #e9ecef; }
        th { background: #667eea; color: white; font-weight: 600; }
        tr:hover { background: #f8f9fa; }
        .badge { display: inline-block; padding: 4px 12px; border-radius: 12px; font-size: 0.85em; font-weight: 600; }
        .badge-success { background: #d4edda; color: #155724; }
        .badge-warning { background: #fff3cd; color: #856404; }
        .badge-danger { background: #f8d7da; color: #721c24; }
        .grid-2 { display: grid; grid-template-columns: 1fr 1fr; gap: 20px; }
        .metric { display: flex; justify-content: space-between; padding: 10px 0; border-bottom: 1px solid #e9ecef; }
        .metric:last-child { border-bottom: none; }
        .footer { text-align: center; padding: 30px; color: #6c757d; font-size: 0.9em; }
    </style>
</head>
<body>
    <div class="header">
        <h1>System Report</h1>
        <p>$($env:COMPUTERNAME) | Generated: $($script:ReportData.GeneratedAt) | Detail: $DetailLevel</p>
    </div>

    <div class="container">
        <div class="summary">
"@

    # Add summary cards based on available data
    if ($script:ReportData.Sections.ContainsKey('Hardware')) {
        $hw = $script:ReportData.Sections.Hardware
        $html += @"
            <div class="summary-card">
                <h3>Memory</h3>
                <div class="value">$($hw.Memory.TotalCapacity)</div>
            </div>
            <div class="summary-card">
                <h3>Storage</h3>
                <div class="value">$($hw.Storage.DiskCount) Disks</div>
            </div>
"@
    }

    if ($script:ReportData.Sections.ContainsKey('Software')) {
        $sw = $script:ReportData.Sections.Software
        $html += @"
            <div class="summary-card">
                <h3>Installed Programs</h3>
                <div class="value">$($sw.InstalledPrograms.Count)</div>
            </div>
"@
    }

    if ($script:ReportData.Sections.ContainsKey('Performance')) {
        $perf = $script:ReportData.Sections.Performance
        $html += @"
            <div class="summary-card">
                <h3>System Uptime</h3>
                <div class="value">$($perf.SystemUptime.Days)d $($perf.SystemUptime.Hours)h</div>
            </div>
"@
    }

    $html += "        </div>`n"

    # Add detailed sections
    foreach ($sectionName in $script:ReportData.Sections.Keys | Sort-Object) {
        $section = $script:ReportData.Sections[$sectionName]
        $html += @"
        <div class="section">
            <div class="section-header">
                <h2>$sectionName</h2>
            </div>
            <div class="section-content">
                <pre>$($section | ConvertTo-Json -Depth 5)</pre>
            </div>
        </div>
"@
    }

    $html += @"
    </div>

    <div class="footer">
        Report generated by GoldISO System Reporter | Log: $script:LogFile
    </div>
</body>
</html>
"@

    $html | Set-Content $reportFile -Encoding UTF8
    Write-ReportLog "HTML report saved: $reportFile" "SUCCESS"
    return $reportFile
}

function Export-JSONReport {
    $reportFile = Join-Path $OutputPath "SystemReport-$timestamp.json"
    $script:ReportData | ConvertTo-Json -Depth 10 | Set-Content $reportFile -Encoding UTF8
    Write-ReportLog "JSON report saved: $reportFile" "SUCCESS"
    return $reportFile
}

function Export-CSVReports {
    $csvDir = Join-Path $OutputPath "CSV-Report-$timestamp"
    New-Item -ItemType Directory -Path $csvDir -Force | Out-Null

    # Export each section as separate CSV
    foreach ($section in $script:ReportData.Sections.Keys) {
        $data = $script:ReportData.Sections[$section]
        $csvFile = Join-Path $csvDir "$section.csv"

        # Flatten nested objects for CSV
        $flatData = @()
        if ($data -is [hashtable]) {
            foreach ($key in $data.Keys) {
                $item = $data[$key]
                if ($item -is [array]) {
                    $flatData += $item | ForEach-Object { $_ | Add-Member -NotePropertyName "Category" -NotePropertyValue $key -PassThru }
                }
                else {
                    $flatData += [PSCustomObject]@{ Category = $key; Value = ($item | ConvertTo-Json -Compress) }
                }
            }
        }

        if ($flatData.Count -gt 0) {
            $flatData | Export-Csv $csvFile -NoTypeInformation
        }
    }

    Write-ReportLog "CSV reports saved to: $csvDir" "SUCCESS"
    return $csvDir
}

#endregion

#region """""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""
# Main Execution
# """""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""

Get-HardwareInventory
Get-SoftwareInventory
Get-ConfigurationStatus
Get-SecurityStatus
Get-PerformanceMetrics

# Export report
$reportPath = switch ($OutputFormat) {
    "HTML" { Export-HTMLReport }
    "JSON" { Export-JSONReport }
    "CSV" { Export-CSVReports }
}

$duration = (Get-Date) - $script:StartTime
Write-ReportLog "Report generation complete in $($duration.ToString('mm\:ss'))" "SUCCESS"
Write-ReportLog "Report saved to: $reportPath" "SUCCESS"

if ($EmailTo) {
    try {
        $smtpServer = "smtp.gmail.com"
        $smtpPort = 587
        $useSSL = $true
        
        $mailParams = @{
            From = $EmailFrom
            To = $EmailTo
            Subject = "System Report - $env:COMPUTERNAME"
            Body = "System report generated on $env:COMPUTERNAME at $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss').`n`nSee attached report."
            SmtpServer = $smtpServer
            Port = $smtpPort
            UseSSL = $useSSL
            Attachments = $reportPath
        }
        
        if ($EmailCredential) {
            $mailParams.Credential = $EmailCredential
        }
        
        Send-MailMessage @mailParams -ErrorAction Stop
        Write-ReportLog "Report sent to: $EmailTo" "SUCCESS"
    } catch {
        Write-ReportLog "Email failed: $($_.Exception.Message)" "WARNING"
        Write-ReportLog "Report saved to: $reportPath" "INFO"
    }
}
