@{
    Run = @{
        Path = "."
        PassThru = $true
    }
    
    Output = @{
        Verbosity = "Detailed"
        StackTraceVerbosity = "Full"
    }
    
    TestResult = @{
        Enabled = $true
        OutputPath = "Results\TestResults.xml"
        OutputFormat = "NUnitXml"
    }
    
    CodeCoverage = @{
        Enabled = $false
        OutputFormat = "JaCoCo"
    }
    
    Should = @{
        ErrorAction = "Stop"
    }
    
    Debug = @{
        ShowFullErrors = $true
        ShowNavigationMarkers = $true
        WriteDebugMessagesFrom = @("*")
    }
}
