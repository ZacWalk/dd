#requires -Version 7.4
$ErrorActionPreference = 'Stop'
if (-not $IsWindows) { throw 'Compiler environment validation requires Windows.' }
$root = Split-Path $PSScriptRoot
. (Join-Path $root '.dd/core.ps1')
. (Join-Path $root '.dd/requirements.ps1')
$fixture = Join-Path ([IO.Path]::GetTempPath()) ('dd-compiler-env-' + [guid]::NewGuid().ToString('N'))
[IO.Directory]::CreateDirectory($fixture) | Out-Null
$previousLocal = $env:LOCALAPPDATA
$previousMarker = $env:DD_ENVIRONMENT_TEST_MARKER
try {
    $env:LOCALAPPDATA = $fixture
    $env:DD_ENVIRONMENT_TEST_MARKER = 'synthetic-first-value'
    Initialize-DDCompiler
    if (@(Get-ChildItem -LiteralPath $fixture -Recurse -Force -File).Count) { throw 'Compiler setup persisted environment data.' }
    $env:DD_ENVIRONMENT_TEST_MARKER = 'synthetic-current-value'
    Initialize-DDCompiler
    if ($env:DD_ENVIRONMENT_TEST_MARKER -ne 'synthetic-current-value') { throw 'Compiler reuse restored stale caller environment.' }
    $script:DDCompilerReady = $null
    Initialize-DDCompiler
    if ($env:DD_ENVIRONMENT_TEST_MARKER -ne 'synthetic-current-value') { throw 'Fresh compiler setup restored stale caller environment.' }
    if (@(Get-ChildItem -LiteralPath $fixture -Recurse -Force -File).Count) { throw 'Fresh compiler setup persisted environment data.' }
} finally {
    $env:LOCALAPPDATA = $previousLocal
    $env:DD_ENVIRONMENT_TEST_MARKER = $previousMarker
}
Write-Host 'PASS: compiler setup retains only per-process state and never persists caller environment.'
exit 0