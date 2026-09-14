#requires -Version 7.4
param([switch]$Build)
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot
. (Join-Path $root '.dd/core.ps1')
$fixture = Join-Path ([IO.Path]::GetTempPath()) ('dd-library-' + [guid]::NewGuid().ToString('N'))
[IO.Directory]::CreateDirectory($fixture) | Out-Null
function Check-DD([string[]]$Values, [int]$Expected = 0) {
    $output = & pwsh -NoProfile -File (Join-Path $root 'dd.ps1') --project $fixture --json @Values
    if ($LASTEXITCODE -ne $Expected) { throw "Unexpected result: $output" }
    return $output | ConvertFrom-Json
}

$plan = Check-DD @('init', '--type', 'library', '--name', 'sample-lib', '--dry-run')
if ($plan.data.type -ne 'library') { throw 'Library type was not planned.' }
foreach ($expected in @('include/applib.h', 'src/applib.c', 'src/main.c', 'tests/lib_tests.c')) {
    if ($plan.data.files -notcontains $expected) { throw "Scaffold plan omits $expected" }
}
if ($plan.data.dependencies.Count) { throw 'Library scaffolds must not declare dependencies.' }
if (@(Get-ChildItem -LiteralPath $fixture -Force).Count) { throw 'Dry run wrote files.' }
$null = Check-DD @('init', '--type', 'library', '--name', 'sample-lib')

# A library repository is two targets: the library itself and the example CLI that
# exercises it. The CLI is the default so `dd run` stays meaningful.
$manifest = Read-DDManifest $fixture
if ($manifest.project.type -ne 'library') { throw 'Manifest project type is not library.' }
if ($manifest.targets.Count -ne 2) { throw 'Expected a library target and an example CLI target.' }
$library = @($manifest.targets | Where-Object kind -eq 'library')
$example = @($manifest.targets | Where-Object kind -eq 'cli')
if ($library.Count -ne 1 -or $example.Count -ne 1) { throw 'Expected exactly one library and one CLI target.' }
if ($manifest.project['default-target'] -ne $example[0].id) { throw 'The example CLI should be the default target.' }

# {libprefix}/{lib} must carry the MSVC/gcc naming split the way {exe} carries ".exe".
if ((Expand-DDTargetPath $library[0]['release-path'] 'x64-windows') -ne 'build/x64-windows/release/lib/applib.lib') { throw 'Windows static library expansion changed.' }
if ((Expand-DDTargetPath $library[0]['release-path'] 'x64-linux') -ne 'build/x64-linux/release/lib/libapplib.a') { throw 'Linux static library expansion changed.' }
if ((Expand-DDTargetPath $example[0]['debug-path'] 'x64-linux') -ne 'build/x64-linux/debug/bin/app') { throw 'Executable expansion regressed.' }

$model = Import-PowerShellDataFile -LiteralPath (Join-Path $fixture 'dd.psd1')
if (-not (Test-Json -Json ($model | ConvertTo-Json -Depth 20) -SchemaFile (Join-Path $root 'schema/dd.schema.json'))) { throw 'Library scaffold does not match the published schema.' }

$listed = Check-DD @('targets')
$libraryMeta = @($listed.data.targets | Where-Object id -eq $library[0].id)
if ($libraryMeta[0].runnable) { throw 'Library targets must not report as runnable.' }
if (-not @($listed.data.targets | Where-Object { $_.id -eq $example[0].id -and $_.runnable }).Count) { throw 'The example CLI should be runnable.' }
if ($libraryMeta[0].platforms.Count -ne 2) { throw 'Library targets should support Windows and Linux.' }

# Selection must refuse before configuring anything, so the failure is instant and clear.
foreach ($verb in @('run', 'launch')) {
    $refused = Check-DD @($verb, $library[0].id) 2
    if (($refused.errors -join ' ') -notmatch 'library') { throw "$verb should explain that a library has no executable." }
}

$preview = Check-DD @('targets', '--vscode', '--dry-run')
if (@($preview.data.added | Where-Object { $_.program -match 'applib' }).Count) { throw 'Library targets must not get debugger launch entries.' }

if ($Build) {
    $null = Check-DD @('build', 'release')
    $platform = if ($IsWindows) { 'x64-windows' } else { 'x64-linux' }
    $archive = Join-Path $fixture (Expand-DDTargetPath $library[0]['release-path'] $platform)
    if (-not (Test-Path -LiteralPath $archive)) { throw "Static library was not produced at $archive" }
    $binary = Join-Path $fixture (Expand-DDTargetPath $example[0]['release-path'] $platform)
    if (-not (Test-Path -LiteralPath $binary)) { throw "Example CLI was not produced at $binary" }
    $run = Check-DD @('run', '--', '--help')
    if ($run.data.stdout -notmatch 'Usage: sample-lib') { throw 'Example CLI did not report its usage.' }
    $null = Check-DD @('test', '--label', 'lib')
    $null = Check-DD @('test', '--app', $library[0].id)
    $null = Check-DD @('test')
}

Write-Host "PASS: library scaffolding, two-target manifest, archive path macros, run/launch refusal and launch-entry exclusion. Fixture: $fixture"
exit 0
