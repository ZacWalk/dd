#requires -Version 7.4
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot
$workspace = Join-Path ([IO.Path]::GetTempPath()) ('dd-deps-' + [guid]::NewGuid().ToString('N'))
[IO.Directory]::CreateDirectory($workspace) | Out-Null
function Check-DD([string[]]$Values, [int]$Expected = 0) {
    $output = & pwsh -NoProfile -File (Join-Path $root 'dd.ps1') --project $workspace --json @Values
    if ($LASTEXITCODE -ne $Expected) { throw "Unexpected result: $output" }
    return $output | ConvertFrom-Json
}
$null = Check-DD @('init', '--type', 'cli', '--name', 'dependency-test')
$null = Check-DD @('dep', 'install', 'unknown') 2
$null = Check-DD @('dep', 'install', '../escape') 2
$path = Join-Path $workspace 'cmake/dd-dependencies.json'
$before = [IO.File]::ReadAllText($path)
$catalogPlan = Check-DD @('dep', 'install', 'libdesktop', '--dry-run')
if ($catalogPlan.data.url -cne 'https://github.com/ZacWalk/libdesktop.git' -or [IO.File]::ReadAllText($path) -cne $before) { throw 'Catalog dry-run failed or changed declarations.' }
# A small CMake library at a fixed tag, so the fetch checks never follow anyone's
# default branch. cmake-declarations.ps1 checks the catalog's head resolution.
$url = 'https://github.com/leethomason/tinyxml2.git'
$null = Check-DD @('dep', 'install', 'tinyxml2', '--git', $url, '--ref', '10.0.0', '--dry-run')
if ([IO.File]::ReadAllText($path) -cne $before) { throw 'Dry-run changed declarations.' }
$added = Check-DD @('dep', 'install', 'tinyxml2', '--git', $url, '--ref', '10.0.0')
$pin = $added.data.commit
if ($pin -cne '321ea883b7190d4e85cae5512a12e5eaa8f8731f') { throw 'Wrong dependency pin.' }
$after = [IO.File]::ReadAllText($path)
$null = Check-DD @('dep', 'install', 'tinyxml2')
if ([IO.File]::ReadAllText($path) -cne $after) { throw 'Repeat installation changed declarations.' }
if ((Test-Path (Join-Path $workspace 'deps')) -or (Test-Path (Join-Path $workspace 'build'))) { throw 'Declaration install fetched sources.' }
$staged = & git -C $workspace diff --cached --name-only
if ($LASTEXITCODE -ne 0 -or $staged) { throw 'Dependency installation staged files.' }
$list = Check-DD @('dep', 'list')
if ($list.data.dependencies[0].status -ne 'declared') { throw 'Dependency not declared.' }
# Only branches and tags resolve remotely, so an abbreviated commit has to say so
# rather than report a bare git exit code; the declarations stay untouched.
$short = Check-DD @('dep', 'update', 'tinyxml2', '--ref', $pin.Substring(0, 7)) 5
if ($short.errors[0] -notmatch '^Remote ref not found: [0-9a-f]{7}\. Give a commit as its full 40-character SHA') { throw "Unhelpful short-commit error: $($short.errors[0])" }
if ([IO.File]::ReadAllText($path) -cne $after) { throw 'A failed update changed declarations.' }
$null = Check-DD @('build', 'debug')
$platform = if ($IsWindows) { 'x64-windows' } else { 'x64-linux' }
$source = Join-Path $workspace "build/$platform/debug/_deps/tinyxml2-$pin-src"
$head = (& git -C $source rev-parse HEAD).Trim()
if ($LASTEXITCODE -ne 0 -or $head -ne $pin) { throw 'FetchContent did not use the recorded commit.' }
$null = Check-DD @('build', 'debug')
$localWork = Join-Path $source 'local-work.txt'
[IO.File]::WriteAllText($localWork, 'Preserve this work.')
$failed = Check-DD @('build', 'debug') 1
if ($failed.errors[0] -notmatch 'Preserving modified or mismatched dependency') { throw 'Modified source should block configure.' }
$null = Check-DD @('clean', 'debug', '--dry-run') 5
if (-not (Test-Path $localWork)) { throw 'Local work lost.' }
$null = Check-DD @('dep', 'install')
Write-Host "PASS: FetchContent pin, declaration-only installs, repeat configure, unchanged Git index and dirty-cache preservation. Fixture: $workspace"
exit 0