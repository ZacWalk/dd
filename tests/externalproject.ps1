#requires -Version 7.4
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot
. (Join-Path $root '.dd/core.ps1')
. (Join-Path $root '.dd/dependencies.ps1')
$fixture = Join-Path ([IO.Path]::GetTempPath()) ('dd-external space-' + [guid]::NewGuid().ToString('N'))
[IO.Directory]::CreateDirectory($fixture) | Out-Null
function Run-DD([string[]]$Values) {
    $output = & pwsh -NoProfile -File (Join-Path $root 'dd.ps1') --project $fixture --json @Values
    if ($LASTEXITCODE -ne 0) { throw $output }
    return $output | ConvertFrom-Json
}
$null = Run-DD @('init', '--type', 'cli', '--name', 'external-test')
$annotated = Resolve-DDDependencyCommit $fixture 'https://github.com/madler/zlib.git' 'v1.3.1'
if ($annotated -ne '51b7f2abdade71cd9bb0e7a373ef2610ec6f9daf') { throw 'Annotated tag did not resolve to its peeled commit.' }
$declared = Run-DD @('dep', 'install', 'tinyxml2', '--git', 'https://github.com/leethomason/tinyxml2.git', '--ref', '10.0.0', '--method', 'externalproject')
$pin = '321ea883b7190d4e85cae5512a12e5eaa8f8731f'
if ($declared.data.commit -ne $pin -or $declared.data.method -ne 'externalproject') { throw 'Tag resolution or method failed.' }
if (Test-Path (Join-Path $fixture 'build')) { throw 'Declaration installed or built external code.' }
$null = Run-DD @('build', 'debug')
$platform = if ($IsWindows) { 'x64-windows' } else { 'x64-linux' }
$cache = Join-Path $fixture "build/$platform/debug/_deps"
$source = Join-Path $cache "tinyxml2-$pin-src"
if ((& git -C $source rev-parse HEAD).Trim() -ne $pin) { throw 'ExternalProject built a floating revision.' }
if (-not (Test-Path (Join-Path $cache "tinyxml2-$($pin.Substring(0, 16))-install/include/tinyxml2.h"))) { throw 'ExternalProject did not install into its private prefix.' }
$null = Run-DD @('build', 'debug')
$index = & git -C $fixture diff --cached --name-only
if ($LASTEXITCODE -ne 0 -or $index) { throw 'ExternalProject build modified the app Git index.' }
Write-Host "PASS: ExternalProject annotated tag resolution, separate CMake build and private install prefix. Fixture: $fixture"
exit 0