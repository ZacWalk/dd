#requires -Version 7.4
param([switch]$Build)
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot
$fixture = Join-Path ([IO.Path]::GetTempPath()) ('dd-vscode space-' + [guid]::NewGuid().ToString('N'))
[IO.Directory]::CreateDirectory($fixture) | Out-Null
$created = & pwsh -NoProfile -File (Join-Path $root 'dd.ps1') init --type cli --name vscode-test --project $fixture --json
if ($LASTEXITCODE -ne 0) { throw "Scaffold failed: $created" }
$launch = Get-Content (Join-Path $fixture '.vscode/launch.json') -Raw | ConvertFrom-Json
$tasks = Get-Content (Join-Path $fixture '.vscode/tasks.json') -Raw | ConvertFrom-Json
$settings = Get-Content (Join-Path $fixture '.vscode/settings.json') -Raw | ConvertFrom-Json
$properties = Get-Content (Join-Path $fixture '.vscode/c_cpp_properties.json') -Raw | ConvertFrom-Json
$extensions = Get-Content (Join-Path $fixture '.vscode/extensions.json') -Raw | ConvertFrom-Json
$workflow = Get-Content (Join-Path $fixture '.github/workflows/ci.yml') -Raw
$readme = Get-Content (Join-Path $fixture 'README.md') -Raw
if (-not $workflow.Contains('os: ["windows-latest", "ubuntu-24.04"]') -or $workflow.Contains('@CI_RUNNERS@')) { throw 'CLI workflow has the wrong host matrix.' }
foreach ($step in @('./dd.ps1 dep install --non-interactive', './dd.ps1 doctor --non-interactive', './dd.ps1 test --non-interactive')) {
    if (-not $workflow.Contains($step)) { throw "Missing CI gate: $step" }
}
if (-not $workflow.Contains('contents: read') -or -not $workflow.Contains('persist-credentials: false')) { throw 'Generated CI permissions are too broad.' }
if (-not $readme.Contains('https://github.com/OWNER/vscode-test/actions/workflows/ci.yml/badge.svg')) { throw 'Generated README badge does not match the project name and workflow.' }
if ($settings.'C_Cpp.default.cppStandard' -ne 'c++20') { throw 'VS Code must default to C++20.' }
if (@($properties.configurations | Where-Object cppStandard -ne 'c++20').Count) { throw 'IntelliSense must use C++20 on every host.' }
if ($extensions.recommendations -notcontains 'ms-vscode.cpptools') { throw 'Missing C++ debugger extension recommendation.' }
if ($launch.configurations.Count -ne 2) { throw 'Expected Windows and Linux debug configurations.' }
foreach ($configuration in $launch.configurations) {
    if ($configuration.preLaunchTask -notin $tasks.tasks.label -or $configuration.cwd -ne '${workspaceFolder}') { throw 'Debugger is not wired to the project build task.' }
}
$task = $tasks.tasks | Where-Object label -eq 'dd: build debug'
if ($task.type -ne 'process' -or $task.command -ne 'pwsh' -or $task.args -notcontains 'debug' -or $task.args -contains 'run') { throw 'Debug task must build through dd without launching a second process.' }
$platform = if ($IsWindows) { 'x64-windows' } else { 'x64-linux' }
$configuration = $launch.configurations | Where-Object type -eq $(if ($IsWindows) { 'cppvsdbg' } else { 'cppdbg' })
if ($launch.configurations[0].type -ne $configuration.type) { throw 'Native F5 configuration should be listed first.' }
$program = $configuration.program.Replace('${workspaceFolder}', $fixture)
$manifest = Import-PowerShellDataFile (Join-Path $fixture 'dd.psd1')
$expected = Join-Path $fixture $manifest.targets[0]['debug-path'].Replace('{platform}', $platform).Replace('{exe}', $(if ($IsWindows) { '.exe' } else { '' }))
if ([IO.Path]::GetFullPath($program) -ne [IO.Path]::GetFullPath($expected)) { throw 'Launch program differs from the manifest Debug binary.' }
if ($Build) {
    $arguments = @($task.args | ForEach-Object { $_.Replace('${workspaceFolder}', $fixture) })
    & $task.command @arguments
    if ($LASTEXITCODE -ne 0 -or -not (Test-Path $program)) { throw 'F5 pre-launch build did not produce the configured binary.' }
    $database = Join-Path $fixture "build/$platform/debug/compile_commands.json"
    $commands = Get-Content $database -Raw | ConvertFrom-Json
    $appCompile = @($commands | Where-Object { $_.file.Replace('\', '/').EndsWith('/src/main.cpp') })
    if ($appCompile.Count -ne 1 -or $appCompile[0].command -notmatch '[-/]std[=:]c\+\+20') { throw 'Application compilation is not configured for C++20.' }
    $output = & $program --help
    if ($LASTEXITCODE -ne 0 -or $output -notmatch 'Usage: vscode-test') { throw 'Configured Debug binary did not run.' }
}
Write-Host "PASS: VS Code debugger/task wiring, C++20 configuration and requested pre-launch build checks. Fixture: $fixture"