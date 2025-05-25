#requires -Version 7.4
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot
$fixture = Join-Path ([IO.Path]::GetTempPath()) ('dd-targets-' + [guid]::NewGuid().ToString('N'))
[IO.Directory]::CreateDirectory($fixture) | Out-Null
function Check-DD([string[]]$Values, [int]$Expected = 0) {
    $output = & pwsh -NoProfile -File (Join-Path $root 'dd.ps1') --project $fixture --json @Values
    if ($LASTEXITCODE -ne $Expected) { throw "Unexpected result: $output" }
    return $output | ConvertFrom-Json
}
$null = Check-DD @('init', '--type', 'cli', '--name', 'multi-app')
$single = Check-DD @('run', '--', '--help')
if ($single.data.stdout -notmatch 'Usage: multi-app') { throw 'Single-target inference failed.' }
$manifestPath = Join-Path $fixture 'dd.psd1'
$original = [IO.File]::ReadAllText($manifestPath)
$extra = @'
        @{
            id = 'worker'
            kind = 'cli'
            'cmake-target' = 'worker'
            'debug-path' = 'build/{platform}/debug/bin/worker{exe}'
            'release-path' = 'build/{platform}/release/bin/worker{exe}'
        },
'@
$multiple = $original.Replace('targets = @(', 'targets = @(' + "`n" + $extra)
[IO.File]::WriteAllText($manifestPath, $multiple)
[IO.File]::WriteAllText((Join-Path $fixture 'src/worker.cpp'), "#include <iostream>`nint main() { std::cout << `"worker ready\\n`"; }`n")
[IO.File]::AppendAllText((Join-Path $fixture 'CMakeLists.txt'), "`nadd_executable(worker src/worker.cpp)`n")
$listed = Check-DD @('targets')
if ($listed.data.targets.Count -ne 2) { throw 'Targets not discoverable.' }
$null = Check-DD @('run') 2
$null = Check-DD @('run', 'missing') 2
$worker = Check-DD @('run', 'worker')
if ($worker.data.stdout -notmatch 'worker ready') { throw 'Explicit worker did not launch.' }
[IO.File]::WriteAllText($manifestPath, $multiple.Replace('project = @{', "project = @{`n        'default-target' = 'worker'"))
$default = Check-DD @('run')
if ($default.data.stdout -notmatch 'worker ready') { throw 'Configured default did not launch.' }
$explicit = Check-DD @('run', 'app', '--', '--help')
if ($explicit.data.stdout -notmatch 'Usage: multi-app') { throw 'Explicit target did not override default.' }
$launchPath = Join-Path $fixture '.vscode/launch.json'
$before = [IO.File]::ReadAllText($launchPath)
$preview = Check-DD @('targets', '--vscode', '--dry-run')
if ($preview.data.added.Count -ne 2 -or [IO.File]::ReadAllText($launchPath) -cne $before) { throw 'Launch preview incorrect.' }
$null = Check-DD @('targets', '--vscode') 2
$applied = Check-DD @('targets', '--vscode', '--yes')
if (-not $applied.data.changed) { throw 'Launch entries not added.' }
$repeat = Check-DD @('targets', '--vscode', '--yes')
if ($repeat.data.changed) { throw 'Launch generation should be idempotent.' }
Write-Host "PASS: multiple apps, explicit/default/inferred targets, ambiguous automation and additive launch configuration. Fixture: $fixture"
exit 0