@{
    Severity     = @('Error', 'Warning', 'Information')

    IncludeRules = @('*')

    ExcludeRules = @(
        # Write-Host is intentional in interactive profiles
        'PSAvoidUsingWriteHost'
        # Global vars are required for profile state
        'PSAvoidGlobalVars'
        # Aliases defined in profile are intentional
        'PSAvoidUsingCmdletAliases'
        # Profile modules use dot-sourcing by design
        'PSAvoidUsingInvokeExpression'
    )

    Rules        = @{
        PSUseCompatibleSyntax  = @{
            Enable         = $true
            TargetVersions = @('5.1', '7.0', '7.4')
        }
        PSPlaceOpenBrace       = @{
            Enable             = $true
            OnSameLine         = $true
            NewLineAfter       = $true
            IgnoreOneLineBlock = $true
        }
        PSPlaceCloseBrace      = @{
            Enable             = $true
            NewLineAfter       = $false
            IgnoreOneLineBlock = $true
            NoEmptyLineBefore  = $false
        }
        PSUseConsistentIndentation = @{
            Enable          = $true
            IndentationSize = 4
            Kind            = 'space'
        }
        PSUseConsistentWhitespace  = @{
            Enable                                  = $true
            CheckInnerBrace                         = $true
            CheckOpenBrace                          = $true
            CheckOpenParen                          = $true
            CheckOperator                           = $true
            CheckPipe                               = $true
            CheckPipeForRedundantWhitespace         = $false
            CheckSeparator                          = $true
            IgnoreAssignmentOperatorInsideHashTable  = $true
        }
        PSAlignAssignmentStatement = @{
            Enable         = $true
            CheckHashtable = $false
        }
    }
}
