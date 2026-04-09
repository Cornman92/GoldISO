#Requires -Version 5.1
#Requires -Modules Pester
<#
.SYNOPSIS
    Pester tests for disk layout template files.
.DESCRIPTION
    Validates that all disk layout pairs (.xml + .json) exist, are parseable,
    and contain the required metadata. Also verifies variable substitution
    produces valid XML when defaults are applied.
.NOTES
    Run with: Invoke-Pester -Path .\DiskLayouts.Tests.ps1
#>

BeforeAll {
    $script:ProjectRoot = Join-Path $PSScriptRoot ".."
    $script:LayoutsDir  = Join-Path $script:ProjectRoot "Config\DiskLayouts"

    $script:ExpectedLayouts = @(
        "GamerOS-3Disk",
        "SingleDisk-DevGaming",
        "SingleDisk-Generic"
    )
}

Describe "Disk Layout File Pairs" {
    foreach ($layout in $script:ExpectedLayouts) {
        Context "Layout: $layout" {
            It "XML file exists" {
                $xmlPath = Join-Path $script:LayoutsDir "$layout.xml"
                Test-Path $xmlPath | Should -Be $true
            }

            It "JSON file exists" {
                $jsonPath = Join-Path $script:LayoutsDir "$layout.json"
                Test-Path $jsonPath | Should -Be $true
            }

            It "XML file is well-formed after variable substitution" {
                $xmlPath  = Join-Path $script:LayoutsDir "$layout.xml"
                $jsonPath = Join-Path $script:LayoutsDir "$layout.json"

                $xmlContent = Get-Content $xmlPath -Raw
                # Apply variable substitution using JSON defaults
                if (Test-Path $jsonPath) {
                    $meta = Get-Content $jsonPath -Raw | ConvertFrom-Json
                    if ($meta.variables) {
                        foreach ($varName in $meta.variables.PSObject.Properties.Name) {
                            $defaultVal = $meta.variables.$varName.default
                            $xmlContent = $xmlContent -replace [regex]::Escape("{{$varName}}"), $defaultVal
                        }
                    }
                }

                # Strip XML declaration and wrap to validate as fragment
                $xmlContent = $xmlContent -replace '^\s*<\?xml[^?]*\?>\s*', ''
                { [xml]"<root xmlns:wcm=`"http://schemas.microsoft.com/WMIConfig/2002/State`">$xmlContent</root>" } |
                    Should -Not -Throw
            }
        }
    }
}

Describe "Disk Layout JSON Schema" {
    foreach ($layout in $script:ExpectedLayouts) {
        Context "JSON content: $layout" {
            BeforeAll {
                $jsonPath = Join-Path $script:LayoutsDir "$layout.json"
                $script:meta = $null
                if (Test-Path $jsonPath) {
                    $script:meta = Get-Content $jsonPath -Raw | ConvertFrom-Json
                }
            }

            It "JSON is parseable" {
                $script:meta | Should -Not -BeNullOrEmpty
            }

            It "JSON has 'name' field" {
                $script:meta.name | Should -Not -BeNullOrEmpty
            }

            It "JSON has 'variables' field" {
                $script:meta.variables | Should -Not -BeNullOrEmpty
            }

            It "JSON has 'disks' field" {
                $script:meta.disks | Should -Not -BeNullOrEmpty
            }

            It "Each variable has a 'default' value" {
                foreach ($varName in $script:meta.variables.PSObject.Properties.Name) {
                    $script:meta.variables.$varName.default | Should -Not -BeNullOrEmpty -Because "variable '$varName' must have a default"
                }
            }
        }
    }
}

Describe "GamerOS-3Disk Layout Specifics" {
    BeforeAll {
        $xmlPath  = Join-Path $script:LayoutsDir "GamerOS-3Disk.xml"
        $jsonPath = Join-Path $script:LayoutsDir "GamerOS-3Disk.json"
        $script:meta = Get-Content $jsonPath -Raw | ConvertFrom-Json

        $xmlContent = Get-Content $xmlPath -Raw
        foreach ($varName in $script:meta.variables.PSObject.Properties.Name) {
            $defaultVal = $script:meta.variables.$varName.default
            $xmlContent = $xmlContent -replace [regex]::Escape("{{$varName}}"), $defaultVal
        }
        $xmlContent = $xmlContent -replace '^\s*<\?xml[^?]*\?>\s*', ''
        $script:xml = [xml]"<root xmlns:wcm=`"http://schemas.microsoft.com/WMIConfig/2002/State`" xmlns=`"urn:schemas-microsoft-com:unattend`">$xmlContent</root>"
    }

    It "Has diskCount of 3" {
        $script:meta.diskCount | Should -Be 3
    }

    It "Contains Disk ID 0 (SSD)" {
        $script:xml.OuterXml | Should -Match "DiskID.*0|0.*DiskID"
    }

    It "Contains Disk ID 1 (HDD)" {
        $script:xml.OuterXml | Should -Match "DiskID.*1|1.*DiskID"
    }

    It "Contains Disk ID 2 (NVMe)" {
        $script:xml.OuterXml | Should -Match "DiskID.*2|2.*DiskID"
    }

    It "Protected drive letters list includes D, E, C, R" {
        $protected = $script:meta.driveLetters.protected
        $protected | Should -Contain "D"
        $protected | Should -Contain "E"
        $protected | Should -Contain "C"
        $protected | Should -Contain "R"
    }

    It "Windows partition size default is 845838 MB" {
        $script:meta.variables.WINDOWS_PARTITION_SIZE.default | Should -Be "845838"
    }

    It "NVMe overprovisioning size default is 92160 MB (90 GB)" {
        $script:meta.variables.OVERPROVISIONING_SIZE.default | Should -Be "92160"
    }

    It "No {{VARIABLE}} placeholders remain after substitution" {
        $script:xml.OuterXml | Should -Not -Match '\{\{[A-Z_]+\}\}'
    }
}

Describe "Disk Layout Naming Convention" {
    It "No layout files use the deprecated -Layout suffix" {
        $deprecated = Get-ChildItem -Path $script:LayoutsDir -Filter "*-Layout.*" -ErrorAction SilentlyContinue
        $deprecated.Count | Should -Be 0 -Because "layout files must not use the -Layout suffix"
    }

    It "Every XML layout file has a matching JSON file" {
        $xmlFiles = Get-ChildItem -Path $script:LayoutsDir -Filter "*.xml" -ErrorAction SilentlyContinue |
            Where-Object { $_.Name -ne "README.md" }
        foreach ($xmlFile in $xmlFiles) {
            $baseName = [System.IO.Path]::GetFileNameWithoutExtension($xmlFile.Name)
            $jsonPath = Join-Path $script:LayoutsDir "$baseName.json"
            Test-Path $jsonPath | Should -Be $true -Because "layout '$baseName' must have a companion .json file"
        }
    }
}
