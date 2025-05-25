#requires -Version 7.4
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot
. (Join-Path $root '.dd/core.ps1')
$fixture = Join-Path ([IO.Path]::GetTempPath()) ('dd-manifest-' + [guid]::NewGuid().ToString('N'))
[IO.Directory]::CreateDirectory($fixture) | Out-Null
$path = Join-Path $fixture 'dd.psd1'
$template = [IO.File]::ReadAllText((Join-Path $root '.dd/templates/common/dd.psd1')).Replace('@NAME@', 'sample').Replace('@TYPE@', 'cli')
function Assert-InvalidManifest([string]$Content, [string]$Expected) {
    [IO.File]::WriteAllText($path, $Content)
    $failure = $null
    try { $null = Read-DDManifest $fixture } catch { $failure = $_.Exception }
    if (-not $failure -or $failure.Data['exitCode'] -ne 2 -or $failure.Message -notmatch $Expected) { throw "Manifest should fail with exit 2 and '$Expected': $failure" }
}
[IO.File]::WriteAllText($path, "# Native data file with comments`n" + $template)
$manifest = Read-DDManifest $fixture
if ($manifest.project.name -ne 'sample' -or $manifest.targets -isnot [array] -or $manifest.targets.Count -ne 1) { throw 'Manifest structure changed.' }
if ($manifest.targets[0]['release-path'] -ne 'build/{platform}/release/bin/app{exe}') { throw 'Literal path placeholders changed.' }
$child = Join-Path $fixture 'child'
[IO.Directory]::CreateDirectory($child) | Out-Null
if ((Find-DDProject $child) -ne $fixture) { throw 'Project discovery failed.' }
Assert-InvalidManifest ($template.Replace('schema = 1', 'schema = 2')) 'Unsupported manifest schema'
Assert-InvalidManifest ($template.Replace('schema = 1', "schema = 1`n    unexpected = 42")) 'Unsupported schema'
Assert-InvalidManifest ($template.Replace('schema = 1', "schema = 1`n    schema = 1")) 'Invalid dd.psd1'
Assert-InvalidManifest '@{ schema = ' 'Invalid dd.psd1'
Assert-InvalidManifest ($template.Replace("id = 'app'", "id = 'app'; extra = 1")) 'Unsupported schema'
$sentinel = Join-Path $fixture 'must-not-exist.txt'
$expression = "([IO.File]::WriteAllText('$($sentinel.Replace("'", "''"))', 'executed'))"
Assert-InvalidManifest ($template.Replace("name = 'sample'", "name = $expression")) 'Invalid dd.psd1'
if (Test-Path -LiteralPath $sentinel) { throw 'Manifest executed code.' }
$legacy = Join-Path $fixture 'legacy'
[IO.Directory]::CreateDirectory($legacy) | Out-Null
[IO.File]::WriteAllText((Join-Path $legacy 'dd.toml'), 'schema = 1')
$failure = $null
try { $null = Find-DDProject $legacy } catch { $failure = $_.Exception }
if (-not $failure -or $failure.Message -notmatch 'Legacy dd.toml') { throw 'Legacy project should block ancestor discovery and explain migration.' }
Write-Host "PASS: native manifest data, comments, arrays, discovery, invalid schemas, non-execution and legacy guidance. Fixture: $fixture"