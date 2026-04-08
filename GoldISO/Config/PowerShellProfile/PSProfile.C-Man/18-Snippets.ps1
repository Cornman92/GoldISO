<#
.SYNOPSIS
    Snippet & Scaffold System for C-Man's PowerShell Profile.
.DESCRIPTION
    Insert boilerplate templates (PS function, C# class, xUnit test,
    XAML page, MCP server) with placeholder substitution. Supports
    user-extensible template directory and project-aware scaffolding.
.NOTES
    Module: 18-Snippets.ps1
    Requires: PowerShell 5.1+
#>

#region ── Configuration ──────────────────────────────────────────────────────

$script:BuiltInTemplateDir = Join-Path -Path $script:ProfileRoot -ChildPath 'Templates'
$script:UserTemplateDir = Join-Path -Path $script:ProfileRoot -ChildPath 'Templates.User'

foreach ($dir in @($script:BuiltInTemplateDir, $script:UserTemplateDir)) {
    if (-not (Test-Path -Path $dir)) {
        $null = New-Item -Path $dir -ItemType Directory -Force
    }
}

#endregion

#region ── Built-in Templates ─────────────────────────────────────────────────

$script:Templates = @{

    'ps-function' = @{
        Description = 'PowerShell advanced function with CmdletBinding'
        Extension   = '.ps1'
        Content     = @'
<#
.SYNOPSIS
    {{Description}}
.DESCRIPTION
    {{Description}}
.PARAMETER {{ParamName}}
    Parameter description.
.EXAMPLE
    {{FunctionName}}
.NOTES
    Author: {{Author}}
    Date:   {{Date}}
#>
function {{FunctionName}} {
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([void])]
    param(
        [Parameter(Mandatory, Position = 0)]
        [ValidateNotNullOrEmpty()]
        [string]${{ParamName}}
    )

    begin {
    }

    process {
        if ($PSCmdlet.ShouldProcess(${{ParamName}}, '{{FunctionName}}')) {
            # Implementation
        }
    }

    end {
    }
}
'@
        Placeholders = @{
            FunctionName = 'Verb-B11Noun'
            Description  = 'Brief description of the function'
            ParamName    = 'Name'
            Author       = $env:USERNAME
            Date         = (Get-Date -Format 'yyyy-MM-dd')
        }
    }

    'ps-module' = @{
        Description = 'PowerShell module manifest with functions'
        Extension   = '.psm1'
        Content     = @'
#Requires -Version 5.1

<#
.SYNOPSIS
    {{ModuleName}} module.
.DESCRIPTION
    {{Description}}
#>

# Import all public functions
$publicFunctions = Get-ChildItem -Path "$PSScriptRoot\Public\*.ps1" -ErrorAction SilentlyContinue
foreach ($function in $publicFunctions) {
    try {
        . $function.FullName
    }
    catch {
        Write-Error -Message "Failed to import function $($function.FullName): $_"
    }
}

# Import all private functions
$privateFunctions = Get-ChildItem -Path "$PSScriptRoot\Private\*.ps1" -ErrorAction SilentlyContinue
foreach ($function in $privateFunctions) {
    try {
        . $function.FullName
    }
    catch {
        Write-Error -Message "Failed to import function $($function.FullName): $_"
    }
}

Export-ModuleMember -Function $publicFunctions.BaseName
'@
        Placeholders = @{
            ModuleName  = 'MyModule'
            Description = 'Module description'
        }
    }

    'ps-pester' = @{
        Description = 'Pester 5 test file'
        Extension   = '.Tests.ps1'
        Content     = @'
#Requires -Module Pester

BeforeAll {
    . $PSScriptRoot\..\{{SourceFile}}
}

Describe '{{FunctionName}}' {
    BeforeEach {
        # Test setup
    }

    Context 'When called with valid input' {
        It 'Should return expected result' {
            $result = {{FunctionName}} -{{ParamName}} 'TestValue'
            $result | Should -Not -BeNullOrEmpty
        }

        It 'Should not throw' {
            { {{FunctionName}} -{{ParamName}} 'TestValue' } | Should -Not -Throw
        }
    }

    Context 'When called with invalid input' {
        It 'Should throw on null input' {
            { {{FunctionName}} -{{ParamName}} $null } | Should -Throw
        }

        It 'Should throw on empty input' {
            { {{FunctionName}} -{{ParamName}} '' } | Should -Throw
        }
    }

    Context 'Edge cases' {
        It 'Should handle special characters' {
            { {{FunctionName}} -{{ParamName}} 'test@#$' } | Should -Not -Throw
        }
    }
}
'@
        Placeholders = @{
            FunctionName = 'Verb-B11Noun'
            ParamName    = 'Name'
            SourceFile   = 'Source.ps1'
        }
    }

    'cs-class' = @{
        Description = 'C# class with constructor injection'
        Extension   = '.cs'
        Content     = @'
// <copyright file="{{ClassName}}.cs" company="Better11">
// Copyright (c) Better11. All rights reserved.
// </copyright>

namespace {{Namespace}};

using Microsoft.Extensions.Logging;

/// <summary>
/// {{Description}}.
/// </summary>
public sealed class {{ClassName}} : I{{ClassName}}
{
    private readonly ILogger<{{ClassName}}> logger;

    /// <summary>
    /// Initializes a new instance of the <see cref="{{ClassName}}"/> class.
    /// </summary>
    /// <param name="logger">The logger instance.</param>
    public {{ClassName}}(ILogger<{{ClassName}}> logger)
    {
        this.logger = logger ?? throw new ArgumentNullException(nameof(logger));
    }
}
'@
        Placeholders = @{
            ClassName   = 'MyService'
            Namespace   = 'Better11.Services'
            Description = 'Service description'
        }
    }

    'cs-interface' = @{
        Description = 'C# interface'
        Extension   = '.cs'
        Content     = @'
// <copyright file="I{{InterfaceName}}.cs" company="Better11">
// Copyright (c) Better11. All rights reserved.
// </copyright>

namespace {{Namespace}};

/// <summary>
/// Defines the contract for {{Description}}.
/// </summary>
public interface I{{InterfaceName}}
{
    /// <summary>
    /// {{MethodDescription}}.
    /// </summary>
    /// <param name="{{ParamName}}">The {{ParamName}} parameter.</param>
    /// <param name="cancellationToken">The cancellation token.</param>
    /// <returns>A <see cref="Result{T}"/> containing the result.</returns>
    Task<Result<{{ReturnType}}>> {{MethodName}}Async(
        {{ParamType}} {{ParamName}},
        CancellationToken cancellationToken = default);
}
'@
        Placeholders = @{
            InterfaceName   = 'MyService'
            Namespace       = 'Better11.Abstractions'
            Description     = 'the service'
            MethodName      = 'Execute'
            MethodDescription = 'Executes the operation'
            ParamName       = 'input'
            ParamType       = 'string'
            ReturnType      = 'bool'
        }
    }

    'cs-xunit' = @{
        Description = 'xUnit test class with NSubstitute'
        Extension   = '.cs'
        Content     = @'
// <copyright file="{{ClassName}}Tests.cs" company="Better11">
// Copyright (c) Better11. All rights reserved.
// </copyright>

namespace {{Namespace}}.Tests;

using NSubstitute;
using Xunit;
using Microsoft.Extensions.Logging;

/// <summary>
/// Tests for <see cref="{{ClassName}}"/>.
/// </summary>
public sealed class {{ClassName}}Tests
{
    private readonly {{ClassName}} sut;
    private readonly ILogger<{{ClassName}}> mockLogger;

    /// <summary>
    /// Initializes a new instance of the <see cref="{{ClassName}}Tests"/> class.
    /// </summary>
    public {{ClassName}}Tests()
    {
        this.mockLogger = Substitute.For<ILogger<{{ClassName}}>>();
        this.sut = new {{ClassName}}(this.mockLogger);
    }

    [Fact]
    public void Constructor_WithNullLogger_ThrowsArgumentNullException()
    {
        Assert.Throws<ArgumentNullException>(() => new {{ClassName}}(null!));
    }

    [Fact]
    public async Task {{MethodName}}Async_WithValidInput_ReturnsSuccess()
    {
        // Arrange
        var input = "test";

        // Act
        var result = await this.sut.{{MethodName}}Async(input);

        // Assert
        Assert.True(result.IsSuccess);
    }

    [Theory]
    [InlineData(null)]
    [InlineData("")]
    public async Task {{MethodName}}Async_WithInvalidInput_ReturnsFailure(string? input)
    {
        // Act
        var result = await this.sut.{{MethodName}}Async(input!);

        // Assert
        Assert.False(result.IsSuccess);
    }
}
'@
        Placeholders = @{
            ClassName  = 'MyService'
            Namespace  = 'Better11.Services'
            MethodName = 'Execute'
        }
    }

    'cs-viewmodel' = @{
        Description = 'WinUI 3 ViewModel with CommunityToolkit.Mvvm'
        Extension   = '.cs'
        Content     = @'
// <copyright file="{{ViewModelName}}.cs" company="Better11">
// Copyright (c) Better11. All rights reserved.
// </copyright>

namespace {{Namespace}}.ViewModels;

using CommunityToolkit.Mvvm.ComponentModel;
using CommunityToolkit.Mvvm.Input;
using Microsoft.Extensions.Logging;

/// <summary>
/// ViewModel for {{Description}}.
/// </summary>
public sealed partial class {{ViewModelName}} : BaseViewModel
{
    private readonly ILogger<{{ViewModelName}}> logger;

    [ObservableProperty]
    [NotifyPropertyChangedFor(nameof(CanExecute))]
    private string title = string.Empty;

    [ObservableProperty]
    private bool isLoading;

    /// <summary>
    /// Initializes a new instance of the <see cref="{{ViewModelName}}"/> class.
    /// </summary>
    /// <param name="logger">The logger instance.</param>
    public {{ViewModelName}}(ILogger<{{ViewModelName}}> logger)
    {
        this.logger = logger ?? throw new ArgumentNullException(nameof(logger));
    }

    /// <summary>
    /// Gets a value indicating whether the command can execute.
    /// </summary>
    public bool CanExecute => !string.IsNullOrEmpty(this.Title);

    [RelayCommand(CanExecute = nameof(CanExecute))]
    private async Task ExecuteAsync(CancellationToken cancellationToken)
    {
        try
        {
            this.IsLoading = true;
            // Implementation with ConfigureAwait(true) for UI context
            await Task.Delay(100, cancellationToken).ConfigureAwait(true);
        }
        catch (OperationCanceledException)
        {
            this.logger.LogDebug("Operation cancelled");
        }
        finally
        {
            this.IsLoading = false;
        }
    }
}
'@
        Placeholders = @{
            ViewModelName = 'MainViewModel'
            Namespace     = 'Better11.App'
            Description   = 'the main page'
        }
    }

    'xaml-page' = @{
        Description = 'WinUI 3 XAML page'
        Extension   = '.xaml'
        Content     = @'
<?xml version="1.0" encoding="utf-8"?>
<Page
    x:Class="{{Namespace}}.Views.{{PageName}}"
    xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
    xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
    xmlns:d="http://schemas.microsoft.com/expression/blend/2008"
    xmlns:mc="http://schemas.openxmlformats.org/markup-compatibility/2006"
    xmlns:viewmodels="using:{{Namespace}}.ViewModels"
    mc:Ignorable="d">

    <Grid Padding="24" RowSpacing="16">
        <Grid.RowDefinitions>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="*"/>
        </Grid.RowDefinitions>

        <!-- Header -->
        <TextBlock
            Grid.Row="0"
            Text="{{Title}}"
            Style="{StaticResource TitleTextBlockStyle}"/>

        <!-- Content -->
        <StackPanel Grid.Row="1" Spacing="8">
            <TextBlock Text="{{Description}}" Style="{StaticResource BodyTextBlockStyle}"/>
        </StackPanel>
    </Grid>
</Page>
'@
        Placeholders = @{
            PageName    = 'MainPage'
            Namespace   = 'Better11.App'
            Title       = 'Page Title'
            Description = 'Page content'
        }
    }

    'mcp-server' = @{
        Description = 'TypeScript MCP server skeleton (@better11/ scope)'
        Extension   = '.ts'
        Content     = @'
import { Server } from "@modelcontextprotocol/sdk/server/index.js";
import { StdioServerTransport } from "@modelcontextprotocol/sdk/server/stdio.js";
import {
  CallToolRequestSchema,
  ListToolsRequestSchema,
} from "@modelcontextprotocol/sdk/types.js";

const server = new Server(
  { name: "@better11/{{ServerName}}", version: "1.0.0" },
  { capabilities: { tools: {} } }
);

server.setRequestHandler(ListToolsRequestSchema, async () => ({
  tools: [
    {
      name: "{{ToolName}}",
      description: "{{ToolDescription}}",
      inputSchema: {
        type: "object" as const,
        properties: {
          {{ParamName}}: {
            type: "string",
            description: "{{ParamDescription}}",
          },
        },
        required: ["{{ParamName}}"],
      },
    },
  ],
}));

server.setRequestHandler(CallToolRequestSchema, async (request) => {
  const { name, arguments: args } = request.params;

  switch (name) {
    case "{{ToolName}}": {
      const {{ParamName}} = args?.{{ParamName}} as string;
      // Implementation
      return {
        content: [{ type: "text", text: `Result for ${{{ParamName}}}` }],
      };
    }
    default:
      throw new Error(`Unknown tool: ${name}`);
  }
});

async function main(): Promise<void> {
  const transport = new StdioServerTransport();
  await server.connect(transport);
}

main().catch(console.error);
'@
        Placeholders = @{
            ServerName       = 'my-server'
            ToolName         = 'my_tool'
            ToolDescription  = 'Tool description'
            ParamName        = 'input'
            ParamDescription = 'The input parameter'
        }
    }

    'jest-test' = @{
        Description = 'Jest ESM test file with unstable_mockModule'
        Extension   = '.test.ts'
        Content     = @'
import { jest, describe, it, expect, beforeEach } from "@jest/globals";

// ESM mock pattern
const mock{{MockName}} = {
  {{MockMethod}}: jest.fn(),
};

jest.unstable_mockModule("{{MockModule}}", () => ({
  default: mock{{MockName}},
  {{MockName}}: mock{{MockName}},
}));

// Dynamic import AFTER mocks
const { {{SubjectName}} } = await import("{{SubjectModule}}");

describe("{{SubjectName}}", () => {
  beforeEach(() => {
    jest.clearAllMocks();
  });

  it("should handle valid input", async () => {
    mock{{MockName}}.{{MockMethod}}.mockResolvedValueOnce({{MockReturn}});

    const result = await {{SubjectName}}({{TestInput}});

    expect(result).toBeDefined();
    expect(mock{{MockName}}.{{MockMethod}}).toHaveBeenCalledWith({{TestInput}});
  });

  it("should handle errors gracefully", async () => {
    mock{{MockName}}.{{MockMethod}}.mockRejectedValueOnce(new Error("test error"));

    await expect({{SubjectName}}({{TestInput}})).rejects.toThrow("test error");
  });
});
'@
        Placeholders = @{
            SubjectName   = 'myFunction'
            SubjectModule = '../src/index.js'
            MockName      = 'Dependency'
            MockModule    = '../src/dependency.js'
            MockMethod    = 'execute'
            MockReturn    = '{ success: true }'
            TestInput     = '"test-input"'
        }
    }

    'gitignore' = @{
        Description = '.gitignore for .NET + Node projects'
        Extension   = ''
        Content     = @'
# Build outputs
bin/
obj/
dist/
build/
out/

# Dependencies
node_modules/
packages/

# IDE
.vs/
.vscode/
.idea/
*.user
*.suo

# OS
Thumbs.db
.DS_Store

# Environment
.env
.env.local
.env.*.local

# Logs
*.log
logs/

# Coverage
coverage/
TestResults/
'@
        Placeholders = @{}
    }
}

#endregion

#region ── Template Engine ────────────────────────────────────────────────────

<#
.SYNOPSIS
    Creates a file from a template with placeholder substitution.
.DESCRIPTION
    Selects a built-in or user template, substitutes placeholders,
    and writes the result to a file. Placeholders use {{Name}} syntax.
.PARAMETER Template
    Template name to use.
.PARAMETER OutputPath
    Output file path. Auto-generated from template name if not specified.
.PARAMETER Placeholders
    Hashtable of placeholder values to substitute.
.PARAMETER Force
    Overwrite existing files.
.PARAMETER List
    List available templates instead of creating a file.
.EXAMPLE
    New-FromTemplate -Template 'cs-class' -Placeholders @{ ClassName = 'AuthService'; Namespace = 'Better11.Auth' }
.EXAMPLE
    scaffold cs-class AuthService
.EXAMPLE
    New-FromTemplate -List
#>
function New-FromTemplate {
    [CmdletBinding(SupportsShouldProcess, DefaultParameterSetName = 'Create')]
    [OutputType([void])]
    param(
        [Parameter(Mandatory, Position = 0, ParameterSetName = 'Create')]
        [ValidateNotNullOrEmpty()]
        [string]$Template,

        [Parameter(Position = 1, ParameterSetName = 'Create')]
        [string]$OutputPath,

        [Parameter(ParameterSetName = 'Create')]
        [hashtable]$Placeholders = @{},

        [Parameter(ParameterSetName = 'Create')]
        [switch]$Force,

        [Parameter(Mandatory, ParameterSetName = 'List')]
        [switch]$List
    )

    if ($List) {
        Show-Templates
        return
    }

    # Check built-in templates first, then user templates
    $tmpl = $null
    if ($script:Templates.ContainsKey($Template)) {
        $tmpl = $script:Templates[$Template]
    }
    else {
        # Check user template directory for .tmpl files
        $userFile = Join-Path -Path $script:UserTemplateDir -ChildPath "${Template}.tmpl"
        if (Test-Path -Path $userFile) {
            $tmpl = @{
                Description  = "User template: $Template"
                Extension    = ''
                Content      = (Get-Content -Path $userFile -Raw)
                Placeholders = @{}
            }
        }
    }

    if ($null -eq $tmpl) {
        Write-Warning -Message "Template '$Template' not found. Use -List to see available templates."
        return
    }

    # Merge default and provided placeholders
    $allPlaceholders = @{}
    if ($tmpl.ContainsKey('Placeholders')) {
        foreach ($key in $tmpl['Placeholders'].Keys) {
            $allPlaceholders[$key] = $tmpl['Placeholders'][$key]
        }
    }
    foreach ($key in $Placeholders.Keys) {
        $allPlaceholders[$key] = $Placeholders[$key]
    }

    # Always add common placeholders
    if (-not $allPlaceholders.ContainsKey('Author')) { $allPlaceholders['Author'] = $env:USERNAME }
    if (-not $allPlaceholders.ContainsKey('Date')) { $allPlaceholders['Date'] = (Get-Date -Format 'yyyy-MM-dd') }
    if (-not $allPlaceholders.ContainsKey('Year')) { $allPlaceholders['Year'] = (Get-Date -Format 'yyyy') }

    # Substitute placeholders
    $content = $tmpl['Content']
    foreach ($key in $allPlaceholders.Keys) {
        $content = $content -replace "\{\{$key\}\}", $allPlaceholders[$key]
    }

    # Determine output path
    if ([string]::IsNullOrEmpty($OutputPath)) {
        $primaryKey = switch -Regex ($Template) {
            'cs-'     { 'ClassName' }
            'ps-'     { 'FunctionName' }
            'xaml-'   { 'PageName' }
            'mcp-'    { 'ServerName' }
            'jest-'   { 'SubjectName' }
            default   { $null }
        }

        $baseName = if ($primaryKey -and $allPlaceholders.ContainsKey($primaryKey)) {
            $allPlaceholders[$primaryKey]
        }
        else {
            $Template
        }

        $extension = $tmpl['Extension']
        $OutputPath = Join-Path -Path (Get-Location).Path -ChildPath "${baseName}${extension}"
    }

    if ((Test-Path -Path $OutputPath) -and -not $Force) {
        Write-Warning -Message "File exists: $OutputPath. Use -Force to overwrite."
        return
    }

    if ($PSCmdlet.ShouldProcess($OutputPath, "Create from template '$Template'")) {
        $parentDir = Split-Path -Path $OutputPath -Parent
        if (-not (Test-Path -Path $parentDir)) {
            $null = New-Item -Path $parentDir -ItemType Directory -Force
        }

        Set-Content -Path $OutputPath -Value $content -NoNewline
        Write-Host "  Created: $OutputPath" -ForegroundColor $script:Theme.Success
        Write-Host "  Template: $Template ($($tmpl['Description']))" -ForegroundColor $script:Theme.Muted

        # Warn about remaining placeholders
        $remaining = [regex]::Matches($content, '\{\{(\w+)\}\}')
        if ($remaining.Count -gt 0) {
            $names = ($remaining | ForEach-Object -Process { $_.Groups[1].Value } | Sort-Object -Unique) -join ', '
            Write-Host "  Unresolved placeholders: $names" -ForegroundColor $script:Theme.Warning
        }
    }
}

<#
.SYNOPSIS
    Lists all available templates.
.EXAMPLE
    Show-Templates
#>
function Show-Templates {
    [CmdletBinding()]
    [OutputType([void])]
    param()

    Write-Host "`n  Available Templates" -ForegroundColor $script:Theme.Primary
    Write-Host "  $('─' * 60)" -ForegroundColor $script:Theme.Muted

    Write-Host "`n  Built-in:" -ForegroundColor $script:Theme.Accent
    foreach ($key in ($script:Templates.Keys | Sort-Object)) {
        $tmpl = $script:Templates[$key]
        $placeholderKeys = if ($tmpl.ContainsKey('Placeholders') -and $tmpl['Placeholders'].Count -gt 0) {
            ($tmpl['Placeholders'].Keys | Sort-Object) -join ', '
        }
        else { '(none)' }

        Write-Host "    $($key.PadRight(20))" -ForegroundColor $script:Theme.Text -NoNewline
        Write-Host " $($tmpl['Description'])" -ForegroundColor $script:Theme.Muted
        Write-Host "    $(' ' * 20) Params: $placeholderKeys" -ForegroundColor $script:Theme.Muted
    }

    # User templates
    $userTemplates = Get-ChildItem -Path $script:UserTemplateDir -Filter '*.tmpl' -ErrorAction SilentlyContinue
    if ($userTemplates.Count -gt 0) {
        Write-Host "`n  User-defined:" -ForegroundColor $script:Theme.Accent
        foreach ($file in $userTemplates) {
            $name = $file.BaseName
            Write-Host "    $($name.PadRight(20))" -ForegroundColor $script:Theme.Text -NoNewline
            Write-Host " $($file.Name) ($($file.Length) bytes)" -ForegroundColor $script:Theme.Muted
        }
    }

    Write-Host "`n  Usage: scaffold <template> [-Placeholders @{Key='Value'}]" -ForegroundColor $script:Theme.Info
    Write-Host ''
}

<#
.SYNOPSIS
    Quick scaffold with positional arguments for common templates.
.DESCRIPTION
    Shorthand for New-FromTemplate. The second parameter is used as
    the primary name (ClassName, FunctionName, etc.).
.PARAMETER Template
    Template name.
.PARAMETER Name
    Primary name (auto-mapped to the template's primary placeholder).
.PARAMETER Namespace
    Namespace for C# templates.
.EXAMPLE
    Invoke-Scaffold cs-class AuthService Better11.Auth
.EXAMPLE
    scaffold ps-function Invoke-B11Deploy
#>
function Invoke-Scaffold {
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([void])]
    param(
        [Parameter(Mandatory, Position = 0)]
        [string]$Template,

        [Parameter(Position = 1)]
        [string]$Name,

        [Parameter(Position = 2)]
        [string]$Namespace
    )

    $placeholders = @{}

    if (-not [string]::IsNullOrEmpty($Name)) {
        $primaryKey = switch -Regex ($Template) {
            '^cs-class$'      { 'ClassName' }
            '^cs-interface$'  { 'InterfaceName' }
            '^cs-xunit$'      { 'ClassName' }
            '^cs-viewmodel$'  { 'ViewModelName' }
            '^ps-function$'   { 'FunctionName' }
            '^ps-module$'     { 'ModuleName' }
            '^ps-pester$'     { 'FunctionName' }
            '^xaml-page$'     { 'PageName' }
            '^mcp-server$'    { 'ServerName' }
            '^jest-test$'     { 'SubjectName' }
            default           { 'Name' }
        }
        $placeholders[$primaryKey] = $Name
    }

    if (-not [string]::IsNullOrEmpty($Namespace)) {
        $placeholders['Namespace'] = $Namespace
    }

    New-FromTemplate -Template $Template -Placeholders $placeholders
}

#endregion

#region ── Aliases ─────────────────────────────────────────────────────────────

Set-Alias -Name 'scaffold'   -Value 'Invoke-Scaffold'    -Scope Global -Force
Set-Alias -Name 'templates'  -Value 'Show-Templates'     -Scope Global -Force
Set-Alias -Name 'tmpl'       -Value 'New-FromTemplate'   -Scope Global -Force

#endregion

#region ── Tab Completion ─────────────────────────────────────────────────────

Register-ArgumentCompleter -CommandName @('New-FromTemplate', 'Invoke-Scaffold') -ParameterName 'Template' -ScriptBlock {
    param($commandName, $parameterName, $wordToComplete, $commandAst, $fakeBoundParameters)

    $builtIn = $script:Templates.Keys
    $user = Get-ChildItem -Path $script:UserTemplateDir -Filter '*.tmpl' -ErrorAction SilentlyContinue |
        ForEach-Object -Process { $_.BaseName }

    ($builtIn + $user) | Where-Object -FilterScript { $_ -like "${wordToComplete}*" } | Sort-Object |
        ForEach-Object -Process {
            $desc = if ($script:Templates.ContainsKey($_)) { $script:Templates[$_]['Description'] } else { 'User template' }
            [System.Management.Automation.CompletionResult]::new($_, $_, 'ParameterValue', $desc)
        }
}

#endregion

