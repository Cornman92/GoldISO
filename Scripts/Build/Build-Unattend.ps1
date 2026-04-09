#Requires -Version 5.1

<#
.SYNOPSIS
    Builds autounattend.xml from modular pass files and JSON profiles.
.DESCRIPTION
    Assembles the final autounattend.xml file by:
    1. Loading a JSON profile from Config/Unattend/Profiles/
    2. Processing modular pass files from Config/Unattend/Passes/
    3. Applying variable substitutions from the profile
    4. Generating the final autounattend.xml
    
    This implements the modular architecture defined in the autounattend-modularization plan.
.PARAMETER ProfileName
    Name of the profile to use (e.g., "gaming-gameros"). Looks in Config/Unattend/Profiles/
.PARAMETER OutputPath
    Path where the generated autounattend.xml will be saved. Defaults to project root.
.PARAMETER BasePath
    Base path for Config/Unattend directory. Auto-detected if not specified.
.EXAMPLE
    .\Build-Unattend.ps1 -ProfileName "gaming-gameros"
    
    Generates autounattend.xml using the gaming-gameros profile.
.EXAMPLE
    .\Build-Unattend.ps1 -ProfileName "gaming-gameros" -OutputPath "D:\\autounattend.xml"
    
    Generates autounattend.xml and saves it to D:\ drive.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$ProfileName,
    
    [Parameter()]
    [string]$OutputPath = $null,
    
    [Parameter()]
    [string]$BasePath = $null
)

$ErrorActionPreference = "Stop"

if (Test-Path (Join-Path $PSScriptRoot "..\Modules\GoldISO-Common.psm1")) {
    Import-Module (Join-Path $PSScriptRoot "..\Modules\GoldISO-Common.psm1") -Force
}

# Initialize paths
if (-not $BasePath) {
    $script:ProjectRoot = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
    $BasePath = Join-Path $script:ProjectRoot "Config\Unattend"
}

$OutputPath = if ($OutputPath) { $OutputPath } else { Join-Path $script:ProjectRoot "autounattend.xml" }

# Define pass file order
$PassFiles = @(
    @{ Name = "offlineServicing"; File = "01-offlineServicing.xml"; Order = 1 },
    @{ Name = "windowsPE"; File = "02-windowsPE.xml"; Order = 2 },
    @{ Name = "generalize"; File = "03-generalize.xml"; Order = 3 },
    @{ Name = "specialize"; File = "04-specialize.xml"; Order = 4 },
    @{ Name = "auditSystem"; File = "05-auditSystem.xml"; Order = 5 },
    @{ Name = "auditUser"; File = "06-auditUser.xml"; Order = 6 },
    @{ Name = "oobeSystem"; File = "07-oobeSystem.xml"; Order = 7 }
)

function Write-Status {
    param([string]$Message, [string]$Level = "INFO")
    $timestamp = Get-Date -Format "HH:mm:ss"
    $color = switch ($Level) {
        "ERROR" { "Red" }
        "WARN" { "Yellow" }
        "SUCCESS" { "Green" }
        default { "White" }
    }
    Write-Host "[$timestamp] [$Level] $Message" -ForegroundColor $color
}

function Initialize-BuildEnvironment {
    Write-Status "Initializing build environment..."
    
    # Verify directories exist
    $requiredDirs = @(
        (Join-Path $BasePath "Core"),
        (Join-Path $BasePath "Passes"),
        (Join-Path $BasePath "Profiles")
    )
    
    foreach ($dir in $requiredDirs) {
        if (-not (Test-Path $dir)) {
            throw "Required directory not found: $dir"
        }
    }
    
    # Verify master template exists
    $masterPath = Join-Path $BasePath "Core\autounattend.master.xml"
    if (-not (Test-Path $masterPath)) {
        throw "Master template not found: $masterPath"
    }
    
    Write-Status "Build environment initialized successfully" "SUCCESS"
}

function Read-Profile {
    param([string]$Name)
    
    $profilePath = Join-Path $BasePath "Profiles\$Name.json"
    
    if (-not (Test-Path $profilePath)) {
        throw "Profile not found: $profilePath"
    }
    
    Write-Status "Loading profile: $Name"
    
    $profileContent = Get-Content $profilePath -Raw | ConvertFrom-Json -Depth 10
    
    Write-Status "Profile loaded: $($profileContent.name)" "SUCCESS"
    
    return $profileContent
}

function Read-PassFile {
    param([string]$PassFileName)
    
    $passPath = Join-Path $BasePath "Passes\$PassFileName"
    
    if (-not (Test-Path $passPath)) {
        Write-Status "Pass file not found: $passPath" "WARN"
        return $null
    }
    
    return Get-Content $passPath -Raw
}

function Expand-ProfileVariables {
    param(
        [string]$Content,
        [PSCustomObject]$Variables
    )
    
    $result = $Content
    
    # Process simple {{VARIABLE}} substitutions
    foreach ($prop in $Variables.PSObject.Properties) {
        $placeholder = "{{$($prop.Name)}}"
        $value = $prop.Value
        $result = $result.Replace($placeholder, $value)
    }
    
    return $result
}

function Build-AutounattendXml {
    param([PSCustomObject]$Config)
    
    Write-Status "Building autounattend.xml..."
    
    # Start XML document
    $xml = New-Object System.Xml.XmlDocument
    
    # Add declaration
    $declaration = $xml.CreateXmlDeclaration("1.0", "utf-8", $null)
    $xml.AppendChild($declaration) | Out-Null
    
    # Create root unattend element with namespaces
    $unattend = $xml.CreateElement("unattend", "urn:schemas-microsoft-com:unattend")
    $unattend.SetAttribute("xmlns:wcm", "http://schemas.microsoft.com/WMIConfig/2002/State")
    $xml.AppendChild($unattend) | Out-Null
    
    # Add comment with generation info
    $comment = $xml.CreateComment("
    Generated by Build-Unattend.ps1
    Profile: $($ProfileName)
    Version: $($Config.version)
    TargetOS: $($Config.targetOS)
    Generated: $(Get-Date -Format "yyyy-MM-dd HH:mm:ss")
    DO NOT EDIT DIRECTLY - Modify the profile and rebuild
    ")
    $unattend.AppendChild($comment) | Out-Null
    
    # Process each pass
    foreach ($passInfo in ($PassFiles | Sort-Object Order)) {
        $passName = $passInfo.Name
        $passFile = $passInfo.File
        
        Write-Status "Processing pass: $passName"
        
        $passContent = Read-PassFile -PassFileName $passFile
        
        if (-not $passContent) {
            # Create empty settings element if pass file doesn't exist
            $settings = $xml.CreateElement("settings", "urn:schemas-microsoft-com:unattend")
            $settings.SetAttribute("pass", $passName)
            $unattend.AppendChild($settings) | Out-Null
            continue
        }
        
        # Expand variables in pass content
        $passContent = Expand-ProfileVariables -Content $passContent -Variables $Config.variables
        
        # Parse pass XML
        $passXml = New-Object System.Xml.XmlDocument
        $passXml.LoadXml($passContent)
        
        # Import settings node into final document
        $settings = $xml.ImportNode($passXml.DocumentElement, $true)
        $unattend.AppendChild($settings) | Out-Null
    }
    
    # Add Extensions section with ExtractScript
    $extensions = $xml.CreateElement("Extensions", "urn:winhance:unattend")
    
    $extractScript = $xml.CreateElement("ExtractScript")
    $extractScript.InnerText = @'
param([xml] $Document);
$scriptsDir = 'C:\ProgramData\Winhance\Unattend\Scripts\';
foreach( $file in $Document.unattend.Extensions.File ) {
    $path = [System.Environment]::ExpandEnvironmentVariables($file.GetAttribute('path'));
    if( $path.StartsWith($scriptsDir) ) { mkdir -Path $scriptsDir -ErrorAction 'SilentlyContinue'; }
    $encoding = switch([System.IO.Path]::GetExtension($path)) {
        { $_ -in '.ps1', '.xml' } { [System.Text.Encoding]::UTF8; }
        { $_ -in '.reg', '.vbs', '.js' } { [System.Text.UnicodeEncoding]::new($false, $true); }
        default { [System.Text.Encoding]::Default; }
    };
    [System.IO.File]::WriteAllBytes($path, ($encoding.GetPreamble() + $encoding.GetBytes($file.InnerText.Trim())));
}
'@
    $extensions.AppendChild($extractScript) | Out-Null
    $unattend.AppendChild($extensions) | Out-Null
    
    return $xml
}

function Save-AutounattendXml {
    param(
        [System.Xml.XmlDocument]$Xml,
        [string]$Path
    )
    
    Write-Status "Saving autounattend.xml to: $Path"
    
    # Ensure output directory exists
    $outputDir = Split-Path $Path -Parent
    if (-not (Test-Path $outputDir)) {
        New-Item -ItemType Directory -Path $outputDir -Force | Out-Null
    }
    
    # Save with formatting
    $settings = New-Object System.Xml.XmlWriterSettings
    $settings.Indent = $true
    $settings.IndentChars = "  "
    $settings.NewLineChars = "`r`n"
    $settings.Encoding = [System.Text.Encoding]::UTF8
    
    $writer = [System.Xml.XmlWriter]::Create($Path, $settings)
    $Xml.WriteTo($writer)
    $writer.Close()
    
    Write-Status "autounattend.xml saved successfully" "SUCCESS"
}

function Show-BuildSummary {
    param(
        [string]$OutputPath,
        [PSCustomObject]$Profile
    )
    
    $fileInfo = Get-Item $OutputPath
    
    Write-Host ""
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host "     BUILD SUMMARY" -ForegroundColor Cyan
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host "Profile:     $($Profile.name)" -ForegroundColor White
    Write-Host "Version:     $($Profile.version)" -ForegroundColor White
    Write-Host "Target OS:   $($Profile.targetOS)" -ForegroundColor White
    Write-Host "Output Path: $OutputPath" -ForegroundColor White
    Write-Host "File Size:   $([math]::Round($fileInfo.Length / 1KB, 2)) KB" -ForegroundColor White
    Write-Host "Generated:   $($fileInfo.LastWriteTime)" -ForegroundColor White
    Write-Host "========================================" -ForegroundColor Cyan
}

# Main execution
try {
    Write-Status "Starting autounattend.xml build process..."
    
    Initialize-BuildEnvironment
    $config = Read-Profile -Name $ProfileName
    $xml = Build-AutounattendXml -Config $config
    Save-AutounattendXml -Xml $xml -Path $OutputPath
    Show-BuildSummary -OutputPath $OutputPath -Profile $config
    
    Write-Status "Build completed successfully!" "SUCCESS"
}
catch {
    Write-Status "Build failed: $_" "ERROR"
    throw
}
