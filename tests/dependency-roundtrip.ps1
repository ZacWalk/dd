#requires -Version 7.4
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot
. (Join-Path $root '.dd/core.ps1')
. (Join-Path $root '.dd/requirements.ps1')
$fixture = Join-Path ([IO.Path]::GetTempPath()) ('dd-roundtrip-' + [guid]::NewGuid().ToString('N'))
[IO.Directory]::CreateDirectory($fixture) | Out-Null
function Run-DD([string[]]$Values, [string]$Directory = $fixture) {
    $output = & pwsh -NoProfile -File (Join-Path $root 'dd.ps1') --project $Directory --json @Values
    if ($LASTEXITCODE) { throw $output }
    return $output | ConvertFrom-Json
}
function Commit-Fixture([string]$Directory, [string]$Message) {
    & git -C $Directory add -- .
    if ($LASTEXITCODE) { throw 'Fixture staging failed.' }
    & git -C $Directory -c user.name=dd-test -c user.email=dd-test@example.invalid -c core.hooksPath=/dev/null commit -m $Message | Out-Null
    if ($LASTEXITCODE) { throw 'Fixture commit failed.' }
}
$null = Run-DD @('init', '--type', 'cli', '--name', 'roundtrip')
$added = Run-DD @('dep', 'install', 'spike-db')
$newPin = $added.data.commit
Commit-Fixture $fixture 'Record initial dependency pin'
$platform = if ($IsWindows) { 'x64-windows' } else { 'x64-linux' }
$null = Run-DD @('build', 'debug')
$newSource = Join-Path $fixture "build/$platform/debug/_deps/spike-db-$newPin-src"
$previousPin = (& git -C $newSource rev-parse HEAD^).Trim()
if ($LASTEXITCODE) { throw 'Test dependency needs a parent revision.' }
$updated = Run-DD @('dep', 'update', 'spike-db', '--ref', $previousPin)
if ($updated.data.commit -ne $previousPin) { throw 'Explicit dependency update used the wrong commit.' }
Commit-Fixture $fixture 'Record previous pin'
$clone = Join-Path ([IO.Path]::GetTempPath()) ('dd-roundtrip-clone-' + [guid]::NewGuid().ToString('N'))
& git clone -- $fixture $clone | Out-Null
if ($LASTEXITCODE) { throw 'Fixture clone failed.' }
$null = Run-DD @('dep', 'install') $clone
$restored = Run-DD @('dep', 'list') $clone
if ($restored.data.dependencies[0].recordedCommit -ne $previousPin -or (Test-Path (Join-Path $clone 'build'))) { throw 'Clone should contain declarations, not downloaded sources.' }
$null = Run-DD @('build', 'debug') $clone
$oldSource = Join-Path $clone "build/$platform/debug/_deps/spike-db-$previousPin-src"
if ((& git -C $oldSource rev-parse HEAD).Trim() -ne $previousPin) { throw 'Fresh-clone FetchContent used the wrong pin.' }
$localWork = Join-Path $oldSource 'local-work.txt'
[IO.File]::WriteAllText($localWork, 'Keep old dependency edits across declaration updates.')
$null = Run-DD @('dep', 'update', 'spike-db', '--ref', $newPin)
Commit-Fixture $fixture 'Advance dependency pin'
& git -C $clone pull --ff-only | Out-Null
if ($LASTEXITCODE) { throw 'Fixture pull failed.' }
$null = Run-DD @('dep', 'install') $clone
$restored = Run-DD @('dep', 'list') $clone
if ($restored.data.dependencies[0].recordedCommit -ne $newPin) { throw 'Updated declaration is incorrect.' }
Initialize-DDCompiler
$build = Join-Path $clone "build/$platform/debug"
$null = Invoke-DDProcess cmake @('--build', $build) $clone -Log
$source = Join-Path $clone "build/$platform/debug/_deps/spike-db-$newPin-src"
if ((& git -C $source rev-parse HEAD).Trim() -ne $newPin -or -not (Test-Path $localWork)) { throw 'CMake update used the wrong pin or lost old local work.' }
$status = & git -C $clone status --porcelain
if ($LASTEXITCODE -ne 0 -or $status) { throw 'Dependency fetching changed tracked/staged application state.' }
Write-Host "PASS: JSON pin update, native CMake reconfigure, revision-specific caches and preservation of old checkout edits. Fixtures: $fixture; $clone"
exit 0