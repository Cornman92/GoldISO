#Requires -Version 5.1
#Requires -Modules Pester
<#
.SYNOPSIS
    Pester tests for build script parameter validation and XML/JSON correctness.
.DESCRIPTION
    Covers:
    - Build-GoldISO.ps1 parameter validation
    - Test-UnattendXML.ps1 bad-XML detection
    - Unattend pass fragment XML well-formedness
    - JSON schema validation for build profiles
.NOTES
    Run with: Invoke-Pester -Path .\BuildValidation.Tests.ps1
#>

BeforeAll {
    Import-Module (Join-Path $PSScriptRoot "TestHelpers.psm1") -Force
    $script:ProjectRoot = Join-Path $PSScriptRoot ".."
    $script:PassesDir   = Join-Path $script:ProjectRoot "Config\Unattend\Passes"
    $script:ProfilesDir = Join-Path $script:ProjectRoot "Config\Unattend\Profiles"
    $script:BuildScript  = Find-ScriptPath "Build-GoldISO.ps1"
    $script:TestUnattend = Find-ScriptPath "Test-UnattendXML.ps1"
}

# ---------------------------------------------------------------------------
# Build-GoldISO.ps1 parameter inspection
# ---------------------------------------------------------------------------
Describe "Build-GoldISO.ps1 Parameter Validation" {
    BeforeAll {
        $content = Get-Content $script:BuildScript -Raw -ErrorAction SilentlyContinue
        $script:buildContent = $content
    }

    It "Build-GoldISO.ps1 exists" {
        Test-Path $BuildScript | Should -Be $true
    }

    It "Contains -DiskLayout parameter" {
        $script:buildContent | Should -Match 'DiskLayout'
    }

    It "DiskLayout ValidateSet includes GamerOS-3Disk" {
        $script:buildContent | Should -Match 'GamerOS-3Disk'
    }

    It "DiskLayout ValidateSet includes SingleDisk-DevGaming" {
        $script:buildContent | Should -Match 'SingleDisk-DevGaming'
    }

    It "DiskLayout ValidateSet includes SingleDisk-Generic" {
        $script:buildContent | Should -Match 'SingleDisk-Generic'
    }

    It "DiskLayout ValidateSet does NOT include old name SingleDisk-Basic" {
        $script:buildContent | Should -Not -Match 'SingleDisk-Basic'
    }

    It "Contains -UseModular switch" {
        $script:buildContent | Should -Match 'UseModular'
    }

    It "Contains -ParallelDrivers switch" {
        $script:buildContent | Should -Match 'ParallelDrivers'
    }

    It "Contains -Resume switch" {
        $script:buildContent | Should -Match '\bResume\b'
    }

    It "Contains -SkipDriverInjection switch" {
        $script:buildContent | Should -Match 'SkipDriverInjection'
    }

    It "Script has PS 5.1 requirement" {
        $script:buildContent | Should -Match '#Requires -Version 5\.1'
    }

    It "Script has no parse errors" {
        $tokens = $null
        $parseErrors = $null
        [System.Management.Automation.Language.Parser]::ParseFile(
            $BuildScript, [ref]$tokens, [ref]$parseErrors
        ) | Out-Null
        $parseErrors.Count | Should -Be 0
    }
}

# ---------------------------------------------------------------------------
# Test-UnattendXML.ps1 bad-XML detection
# ---------------------------------------------------------------------------
Describe "Test-UnattendXML.ps1 rejects malformed XML" {
    BeforeAll {
        $script:badXmlPath = Join-Path $env:TEMP "bad-unattend-$(Get-Random).xml"
        @"
<?xml version="1.0" encoding="utf-8"?>
<unattend xmlns="urn:schemas-microsoft-com:unattend">
  <settings pass="oobeSystem">
    <unclosed_element>
</unattend>
"@ | Set-Content $script:badXmlPath -Encoding UTF8
    }

    AfterAll {
        if (Test-Path $script:badXmlPath) { Remove-Item $script:badXmlPath -Force }
    }

    It "Test-UnattendXML.ps1 exists" {
        Test-Path $script:TestUnattend | Should -Be $true
    }

    It "Test-UnattendXML.ps1 has no parse errors" {
        $tokens = $null
        $parseErrors = $null
        [System.Management.Automation.Language.Parser]::ParseFile(
            $script:TestUnattend, [ref]$tokens, [ref]$parseErrors
        ) | Out-Null
        $parseErrors.Count | Should -Be 0
    }

    It "Test-UnattendXML.ps1 exits non-zero when fed bad XML" {
        # Run script against the malformed file and capture exit code
        $proc = Start-Process powershell.exe -ArgumentList @(
            "-NoProfile", "-NonInteractive", "-ExecutionPolicy", "Bypass",
            "-File", $script:TestUnattend, "-UnattendPath", $script:badXmlPath
        ) -Wait -PassThru -NoNewWindow
        $proc.ExitCode | Should -Not -Be 0
    }
}

# ---------------------------------------------------------------------------
# Unattend pass XML fragment well-formedness
# ---------------------------------------------------------------------------
Describe "Unattend Pass Fragments - XML Well-formedness" {
    BeforeAll {
        $passFiles = Get-ChildItem -Path $script:PassesDir -Filter "*.xml" -ErrorAction SilentlyContinue
        $script:passFiles = $passFiles
    }

    foreach ($passFile in $script:passFiles) {
        Context "Pass: $($passFile.Name)" {
            It "$($passFile.Name) is well-formed XML (after stripping unresolved variables)" {
                $rawContent = Get-Content $passFile.FullName -Raw

                # Substitute remaining {{VARIABLE}} placeholders with dummy values for validation
                $xmlContent = $rawContent -replace '\{\{[A-Z0-9_]+\}\}', 'PLACEHOLDER'

                # Strip XML declaration for fragment validation
                $xmlContent = $xmlContent -replace '^\s*<\?xml[^?]*\?>\s*', ''

                { [xml]"<root xmlns:wcm=`"http://schemas.microsoft.com/WMIConfig/2002/State`" xmlns=`"urn:schemas-microsoft-com:unattend`">$xmlContent</root>" } |
                    Should -Not -Throw
            }
        }
    }
}

# ---------------------------------------------------------------------------
# JSON profile schema validation
# ---------------------------------------------------------------------------
Describe "Build Profile JSON Schema" {
    BeforeAll {
        $schemaPath  = Join-Path $script:ProfilesDir "_schema.json"
        $profilePath = Join-Path $script:ProfilesDir "gaming-gameros.json"

        $script:schema  = $null
        $script:profile = $null

        if (Test-Path $schemaPath)  { $script:schema  = Get-Content $schemaPath  -Raw | ConvertFrom-Json }
        if (Test-Path $profilePath) { $script:profile = Get-Content $profilePath -Raw | ConvertFrom-Json }
    }

    It "_schema.json exists" {
        Test-Path (Join-Path $script:ProfilesDir "_schema.json") | Should -Be $true
    }

    It "gaming-gameros.json exists" {
        Test-Path (Join-Path $script:ProfilesDir "gaming-gameros.json") | Should -Be $true
    }

    It "gaming-gameros.json is parseable JSON" {
        $script:profile | Should -Not -BeNullOrEmpty
    }

    It "_schema.json is parseable JSON" {
        $script:schema | Should -Not -BeNullOrEmpty
    }

    It "gaming-gameros.json has a name field" {
        $script:profile.name | Should -Not -BeNullOrEmpty
    }

    It "_schema.json has required properties defined" {
        # Schema should define at minimum: type and/or properties
        ($script:schema.type -or $script:schema.properties) | Should -Be $true
    }
}
