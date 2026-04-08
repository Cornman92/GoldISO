[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingWriteHost', '', Justification = 'GoldISO shortcuts require colored output')]
param()

#region ── GoldISO / GWIG Quick Navigation & Build Shortcuts ─────────────────

$script:GoldISORoot = 'C:\Users\C-Man\GoldISO'
$script:GWIGRoot    = 'C:\Users\C-Man\GWIG'

function Enter-GoldISO {
    <#
    .SYNOPSIS
        Jump to GoldISO project root.
    #>
    [CmdletBinding()]
    [Alias('goldiso')]
    param()
    if (Test-Path $script:GoldISORoot) {
        Set-Location $script:GoldISORoot
    } else {
        Write-Warning "GoldISO root not found: $script:GoldISORoot"
    }
}

function Enter-GWIG {
    <#
    .SYNOPSIS
        Jump to GWIG pipeline project root.
    #>
    [CmdletBinding()]
    [Alias('gwig')]
    param()
    if (Test-Path $script:GWIGRoot) {
        Set-Location $script:GWIGRoot
    } else {
        Write-Warning "GWIG root not found: $script:GWIGRoot"
    }
}

function Invoke-BuildISO {
    <#
    .SYNOPSIS
        Run Build-GoldISO.ps1 from anywhere.
    .EXAMPLE
        build-iso
        build-iso -SkipDriverInjection -Verbose
    #>
    [CmdletBinding()]
    [Alias('build-iso')]
    param()
    $script = Join-Path $script:GoldISORoot 'Scripts\Build-GoldISO.ps1'
    if (Test-Path $script) {
        & $script @args
    } else {
        Write-Warning "Build script not found: $script"
    }
}

function Invoke-BuildPipeline {
    <#
    .SYNOPSIS
        Run Start-BuildPipeline.ps1 (full CI orchestration).
    .EXAMPLE
        build-pipeline
        build-pipeline -DeployToVM -Verbose
    #>
    [CmdletBinding()]
    [Alias('build-pipeline')]
    param()
    $script = Join-Path $script:GoldISORoot 'Scripts\Start-BuildPipeline.ps1'
    if (Test-Path $script) {
        & $script @args
    } else {
        Write-Warning "Pipeline script not found: $script"
    }
}

function Invoke-ValidateXML {
    <#
    .SYNOPSIS
        Validate autounattend.xml (runs Test-UnattendXML.ps1).
    .EXAMPLE
        validate-xml
        validate-xml -Verbose
    #>
    [CmdletBinding()]
    [Alias('validate-xml')]
    param()
    $script = Join-Path $script:GoldISORoot 'Scripts\Test-UnattendXML.ps1'
    if (Test-Path $script) {
        & $script @args
    } else {
        Write-Warning "Validator not found: $script"
    }
}

function Invoke-TestEnvironment {
    <#
    .SYNOPSIS
        Run Test-Environment.ps1 pre-flight checks.
    #>
    [CmdletBinding()]
    [Alias('test-env')]
    param()
    $script = Join-Path $script:GoldISORoot 'Scripts\Test-Environment.ps1'
    if (Test-Path $script) {
        & $script @args
    } else {
        Write-Warning "Test-Environment not found: $script"
    }
}

function Invoke-RunTests {
    <#
    .SYNOPSIS
        Run the full GoldISO Pester test suite.
    #>
    [CmdletBinding()]
    [Alias('run-tests')]
    param()
    $script = Join-Path $script:GoldISORoot 'Tests\Run-AllTests.ps1'
    if (Test-Path $script) {
        & $script @args
    } else {
        Write-Warning "Test runner not found: $script"
    }
}

#endregion
