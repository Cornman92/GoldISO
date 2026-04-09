param()

#region ── Git Tab Completion ─────────────────────────────────────────────────

if (Get-Command -Name 'git' -ErrorAction SilentlyContinue) {
    # Git branch completer for checkout, merge, rebase, etc.
    $script:GitBranchCommands = @('Invoke-GitCheckout', 'Invoke-GitRebase', 'Invoke-GitBranch')

    Register-ArgumentCompleter -CommandName $script:GitBranchCommands -ScriptBlock {
        param($commandName, $parameterName, $wordToComplete, $commandAst, $fakeBoundParameters)

        $branches = & git branch --format='%(refname:short)' 2>$null
        if ($branches) {
            $branches | Where-Object -FilterScript { $_ -like "$wordToComplete*" } | ForEach-Object -Process {
                [System.Management.Automation.CompletionResult]::new($_, $_, 'ParameterValue', "Branch: $_")
            }
        }
    }

    # Git remote branch completer
    Register-ArgumentCompleter -CommandName 'git' -Native -ScriptBlock {
        param($wordToComplete, $commandAst, $cursorPosition)

        $commandText = $commandAst.ToString()

        # Complete subcommands
        if ($commandText -match '^\s*git\s+$' -or ($commandText -match '^\s*git\s+(\S+)$' -and $wordToComplete)) {
            $subcommands = @('add', 'branch', 'checkout', 'clone', 'commit', 'diff', 'fetch', 'init',
                'log', 'merge', 'pull', 'push', 'rebase', 'remote', 'reset', 'stash', 'status', 'tag',
                'cherry-pick', 'revert', 'bisect', 'blame', 'clean', 'config', 'describe', 'format-patch',
                'grep', 'mv', 'notes', 'reflog', 'rm', 'shortlog', 'show', 'submodule', 'switch', 'worktree')

            $subcommands | Where-Object -FilterScript { $_ -like "$wordToComplete*" } | ForEach-Object -Process {
                [System.Management.Automation.CompletionResult]::new($_, $_, 'ParameterValue', "git $_")
            }
            return
        }

        # Complete branches for checkout/switch/merge/rebase
        if ($commandText -match 'git\s+(checkout|switch|merge|rebase|branch\s+-d)\s+') {
            $branches = & git branch --format='%(refname:short)' 2>$null
            $remoteBranches = & git branch -r --format='%(refname:short)' 2>$null
            $allBranches = @($branches) + @($remoteBranches | ForEach-Object -Process { $_ -replace '^origin/', '' })
            $allBranches | Select-Object -Unique | Where-Object -FilterScript { $_ -like "$wordToComplete*" } |
                ForEach-Object -Process {
                    [System.Management.Automation.CompletionResult]::new($_, $_, 'ParameterValue', "Branch: $_")
                }
            return
        }

        # Complete remotes
        if ($commandText -match 'git\s+(push|pull|fetch)\s+') {
            $remotes = & git remote 2>$null
            if ($remotes) {
                $remotes | Where-Object -FilterScript { $_ -like "$wordToComplete*" } | ForEach-Object -Process {
                    [System.Management.Automation.CompletionResult]::new($_, $_, 'ParameterValue', "Remote: $_")
                }
            }
            return
        }
    }
}

#endregion

#region ── Winget Tab Completion ──────────────────────────────────────────────

if (Get-Command -Name 'winget' -ErrorAction SilentlyContinue) {
    Register-ArgumentCompleter -CommandName 'winget' -Native -ScriptBlock {
        param($wordToComplete, $commandAst, $cursorPosition)

        $commandText = $commandAst.ToString()

        if ($commandText -match '^\s*winget\s*$' -or ($commandText -match '^\s*winget\s+(\S+)$' -and $wordToComplete)) {
            $subcommands = @('install', 'show', 'source', 'search', 'list', 'upgrade', 'uninstall',
                'hash', 'validate', 'settings', 'features', 'export', 'import', 'pin', 'configure')

            $subcommands | Where-Object -FilterScript { $_ -like "$wordToComplete*" } | ForEach-Object -Process {
                [System.Management.Automation.CompletionResult]::new($_, $_, 'ParameterValue', "winget $_")
            }
        }
    }
}

#endregion

#region ── Dotnet Tab Completion ──────────────────────────────────────────────

if (Get-Command -Name 'dotnet' -ErrorAction SilentlyContinue) {
    Register-ArgumentCompleter -CommandName 'dotnet' -Native -ScriptBlock {
        param($wordToComplete, $commandAst, $cursorPosition)

        $commandText = $commandAst.ToString()

        if ($commandText -match '^\s*dotnet\s*$' -or ($commandText -match '^\s*dotnet\s+(\S+)$' -and $wordToComplete)) {
            $subcommands = @('new', 'build', 'run', 'test', 'publish', 'clean', 'restore', 'pack',
                'add', 'remove', 'list', 'sln', 'store', 'watch', 'format', 'tool', 'workload',
                'nuget', 'sdk', 'dev-certs')

            $subcommands | Where-Object -FilterScript { $_ -like "$wordToComplete*" } | ForEach-Object -Process {
                [System.Management.Automation.CompletionResult]::new($_, $_, 'ParameterValue', "dotnet $_")
            }
            return
        }

        # Complete templates for 'dotnet new'
        if ($commandText -match 'dotnet\s+new\s+') {
            $templates = @('console', 'classlib', 'web', 'webapi', 'mvc', 'razor', 'blazorserver',
                'blazorwasm', 'grpc', 'worker', 'mstest', 'nunit', 'xunit', 'sln', 'gitignore',
                'editorconfig', 'nugetconfig', 'globaljson', 'tool-manifest', 'winforms', 'wpf',
                'maui', 'winui3')

            $templates | Where-Object -FilterScript { $_ -like "$wordToComplete*" } | ForEach-Object -Process {
                [System.Management.Automation.CompletionResult]::new($_, $_, 'ParameterValue', "Template: $_")
            }
        }
    }
}

#endregion

#region ── Docker Tab Completion ──────────────────────────────────────────────

if (Get-Command -Name 'docker' -ErrorAction SilentlyContinue) {
    Register-ArgumentCompleter -CommandName 'docker' -Native -ScriptBlock {
        param($wordToComplete, $commandAst, $cursorPosition)

        $commandText = $commandAst.ToString()

        if ($commandText -match '^\s*docker\s*$' -or ($commandText -match '^\s*docker\s+(\S+)$' -and $wordToComplete)) {
            $subcommands = @('build', 'compose', 'container', 'exec', 'image', 'images', 'inspect',
                'logs', 'network', 'ps', 'pull', 'push', 'rm', 'rmi', 'run', 'start', 'stop',
                'system', 'tag', 'top', 'volume', 'cp', 'create', 'diff', 'events', 'export',
                'history', 'import', 'info', 'kill', 'load', 'login', 'logout', 'pause', 'port',
                'rename', 'restart', 'save', 'search', 'stats', 'unpause', 'update', 'version', 'wait')

            $subcommands | Where-Object -FilterScript { $_ -like "$wordToComplete*" } | ForEach-Object -Process {
                [System.Management.Automation.CompletionResult]::new($_, $_, 'ParameterValue', "docker $_")
            }
        }
    }
}

#endregion

#region ── Profile Command Completion ─────────────────────────────────────────

# Tab complete for Set-ProfileTheme
Register-ArgumentCompleter -CommandName 'Set-ProfileTheme' -ParameterName 'Name' -ScriptBlock {
    param($commandName, $parameterName, $wordToComplete, $commandAst, $fakeBoundParameters)
    @('Matrix', 'Cyberpunk', 'Dracula', 'Monochrome') |
        Where-Object -FilterScript { $_ -like "$wordToComplete*" } |
        ForEach-Object -Process {
            [System.Management.Automation.CompletionResult]::new($_, $_, 'ParameterValue', "Theme: $_")
        }
}

# Tab complete for Show-ProfileAliases
Register-ArgumentCompleter -CommandName 'Show-ProfileAliases' -ParameterName 'Category' -ScriptBlock {
    param($commandName, $parameterName, $wordToComplete, $commandAst, $fakeBoundParameters)
    @('All', 'Git', 'System', 'Docker', 'Dotnet', 'Package', 'Navigation') |
        Where-Object -FilterScript { $_ -like "$wordToComplete*" } |
        ForEach-Object -Process {
            [System.Management.Automation.CompletionResult]::new($_, $_, 'ParameterValue', $_)
        }
}

#endregion

