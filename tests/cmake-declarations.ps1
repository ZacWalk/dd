#requires -Version 7.4
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot
. (Join-Path $root '.dd/core.ps1')
. (Join-Path $root '.dd/dependencies.ps1')
$fixture = Join-Path ([IO.Path]::GetTempPath()) ('dd-cmake-deps-' + [guid]::NewGuid().ToString('N'))
[IO.Directory]::CreateDirectory((Join-Path $fixture 'cmake')) | Out-Null
$path = Join-Path $fixture 'cmake/dd-dependencies.json'
[IO.File]::WriteAllText($path, '{"schema":1,"dependencies":{}}')
$before = [IO.File]::ReadAllText($path)
$null = Install-DDDependency $fixture 'platform-h' $null $null $true
if ([IO.File]::ReadAllText($path) -cne $before) { throw 'Dry-run modified declarations.' }
$added = Install-DDDependency $fixture 'platform-h' $null $null $false
if ($added.method -ne 'fetchcontent' -or $added.commit -ne '8e9be5de233d1797ce7a2b50fe663042469611a9') { throw 'Incorrect default integration or pin.' }
$after = [IO.File]::ReadAllText($path)
$repeat = Install-DDDependency $fixture 'platform-h' $null $null $false
if ($repeat.changed -or [IO.File]::ReadAllText($path) -cne $after) { throw 'Repeated install modified declarations.' }
$external = Install-DDDependency $fixture 'spike-db' $null $null $false 'externalproject'
if ($external.method -ne 'externalproject') { throw 'ExternalProject selection lost.' }
if ((Test-Path (Join-Path $fixture '.git')) -or (Test-Path (Join-Path $fixture 'deps')) -or (Test-Path (Join-Path $fixture 'build'))) { throw 'Declaration install fetched sources or mutated Git.' }
if (@(Get-DDDependencies $fixture).Count -ne 2) { throw 'Declaration list incomplete.' }
Write-Host "PASS: pinned FetchContent/ExternalProject declarations, dry-run and repeated install without Git mutations. Fixture: $fixture"
exit 0