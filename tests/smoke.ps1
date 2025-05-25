#requires -Version 7.4
param([switch]$Build)
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot
$driver = Join-Path $root 'dd.ps1'
$workspace = Join-Path ([IO.Path]::GetTempPath()) ('dd-test-' + [guid]::NewGuid().ToString('N'))
[IO.Directory]::CreateDirectory($workspace) | Out-Null
function Invoke-TestDD([string[]]$Values, [int]$Expected = 0) {
    $output = & pwsh -NoProfile -File $driver --project $workspace --json @Values
    $code = $LASTEXITCODE
    $result = $output | ConvertFrom-Json
    if ($code -ne $Expected -or $result.exitCode -ne $Expected) { throw "Expected $Expected, got ${code}: $output" }
    return $result
}
$null = Invoke-TestDD @('help')
$null = Invoke-TestDD @('init') 2
$planned = Invoke-TestDD @('init', '--type', 'cli', '--name', 'sample', '--dry-run')
if (@(Get-ChildItem $workspace -Force).Count -ne 0) { throw 'Dry-run changed destination.' }
if ($planned.data.dependencies.Count) { throw 'CLI template requested dependencies.' }
if ($IsLinux) { $null = Invoke-TestDD @('init', '--type', 'gui', '--name', 'sample') 2 }
$null = Invoke-TestDD @('init', '--type', 'cli', '--name', 'sample')
$null = Invoke-TestDD @('init', '--type', 'cli', '--name', 'sample') 2
if (-not (Test-Path (Join-Path $workspace 'dd.psd1'))) { throw 'Missing manifest.' }
if ($planned.data.files -notcontains 'dd.psd1') { throw 'Scaffold plan names the wrong manifest.' }
if ((Test-Path (Join-Path $workspace 'dd.toml')) -or (Test-Path (Join-Path $workspace '.dd/lib'))) { throw 'Scaffold includes obsolete manifest/parser files.' }
$mcp = Get-Content (Join-Path $workspace '.vscode/mcp.json') -Raw | ConvertFrom-Json
if ($mcp.servers.dd.command -ne 'pwsh' -or $mcp.servers.dd.args[3] -ne '${workspaceFolder}/.dd/mcp/server.ps1' -or $mcp.servers.dd.args -contains '-AllowExecution') { throw 'Unexpected MCP template scope or execution defaults.' }
if (Test-Path (Join-Path $workspace '.dd/mcp/server.js')) { throw 'Scaffold retained the previous MCP bundle.' }
if ($Build) {
    $null = Invoke-TestDD @('doctor')
    $null = Invoke-TestDD @('test')
    $run = Invoke-TestDD @('run', 'app', '--', '--help')
    if ($run.data.stdout -notmatch 'Usage:') { throw 'CLI help output missing.' }
}
$manifestPath = Join-Path $workspace 'dd.psd1'
$content = [IO.File]::ReadAllText($manifestPath).Replace('schema = 1', "schema = 1`n    'unsupported-setting' = `$true")
[IO.File]::WriteAllText($manifestPath, $content)
$invalid = Invoke-TestDD @('build') 2
if ($invalid.errors[0] -notmatch 'Unsupported schema') { throw 'Unknown manifest setting was not rejected.' }
Write-Host "PASS: init, dry-run, conflicts, JSON, and requested build checks. Fixture retained: $workspace"
exit 0