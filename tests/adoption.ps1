#requires -Version 7.4
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot
$fixture = Join-Path ([IO.Path]::GetTempPath()) ('dd-adoption-' + [guid]::NewGuid().ToString('N'))
[IO.Directory]::CreateDirectory($fixture) | Out-Null
function Check-DD([string[]]$Values, [int]$Expected = 0) {
    $output = & pwsh -NoProfile -File (Join-Path $root 'dd.ps1') --project $fixture --json @Values
    if ($LASTEXITCODE -ne $Expected) { throw "Unexpected result: $output" }
    return $output | ConvertFrom-Json
}
$null = Check-DD @('init', '--type', 'cli', '--name', 'adoption')
$dependencyFile = Join-Path $fixture 'cmake/dd-dependencies.json'
Move-Item $dependencyFile (Join-Path $fixture 'saved-dependencies.json')
$null = Check-DD @('build', 'debug') 5
$manifestPath = Join-Path $fixture 'dd.psd1'
$text = [IO.File]::ReadAllText($manifestPath).Replace('schema = 1', "schema = 1`n    dependencies = @{ owner = 'application' }")
[IO.File]::WriteAllText($manifestPath, $text)
$cmake = Join-Path $fixture 'CMakeLists.txt'
[IO.File]::WriteAllText($cmake, [IO.File]::ReadAllText($cmake).Replace('dd_load_dependencies("${CMAKE_CURRENT_SOURCE_DIR}/cmake/dd-dependencies.json")', ''))
$reported = Check-DD @('dep', 'list')
if ($reported.data.inventoryKnown -ne $false -or $reported.data.owner -ne 'application') { throw 'Application dependencies were reported as empty.' }
$null = Check-DD @('dep', 'install', 'platform-h') 2
$presetsPath = Join-Path $fixture 'CMakePresets.json'
$presets = Get-Content $presetsPath -Raw | ConvertFrom-Json -AsHashtable
foreach ($preset in $presets.configurePresets) {
    if (-not $preset.hidden) {
        $preset.name = 'c-' + $preset.name
        $preset.binaryDir = '${sourceDir}/out/${presetName}'
    }
}
foreach ($preset in $presets.buildPresets) { $preset.name = 'b-' + $preset.name; $preset.configurePreset = 'c-' + $preset.configurePreset }
foreach ($preset in $presets.testPresets) { $preset.name = 't-' + $preset.name; $preset.configurePreset = 'c-' + $preset.configurePreset }
[IO.File]::WriteAllText($presetsPath, ($presets | ConvertTo-Json -Depth 15))
foreach ($hostName in @('windows','linux')) {
    foreach ($config in @('debug','release')) {
        $text = $text.Replace("'$hostName-$config'", "@{ configure = 'c-$hostName-$config'; build = 'b-$hostName-$config'; test = 't-$hostName-$config' }")
    }
}
$native = if ($IsWindows) { 'windows' } else { 'linux' }
$text = $text.Replace('build/{platform}/debug/bin/app{exe}', "out/c-$native-debug/bin/app{exe}").Replace('build/{platform}/release/bin/app{exe}', "out/c-$native-release/bin/app{exe}").Replace("'windows-ide'", "'c-windows-ide'")
[IO.File]::WriteAllText($manifestPath, $text)
[IO.File]::AppendAllText($cmake, @'

set_tests_properties(app_help app_unit PROPERTIES LABELS "app;happy")
add_test(NAME intentional_failure COMMAND ${CMAKE_COMMAND} -E false)
set_tests_properties(intentional_failure PROPERTIES LABELS "failure")
'@)
$null = Check-DD @('build','debug','--app','missing') 2
$focused = Check-DD @('test','--app','app','--label','happy')
if (@($focused.data.results | Where-Object status -eq 'tested').Count -ne 2) { throw 'Focused tests must run both configurations.' }
$null = Check-DD @('test','--name','^no-match$') 1
$failure = Check-DD @('test','--label','failure') 1
if ($failure.data.testFailures[0].name -ne 'intentional_failure' -or $failure.errors[0] -notmatch 'intentional_failure') { throw 'Failing CTest names were not surfaced.' }
$clean = Check-DD @('clean','both','--dry-run')
if ($clean.data.paths.Count -ne 2 -or @($clean.data.paths | Where-Object { $_ -notmatch '[\\/]out[\\/]' }).Count) { throw 'Cleanup did not honor configured paths.' }
[IO.File]::AppendAllText($presetsPath, "`n")
$null = Check-DD @('clean','both','--dry-run') 2
if (Test-Path $dependencyFile) { throw 'Application-owned build created managed declarations.' }
$source = Join-Path $fixture 'src/main.cpp'
[IO.File]::WriteAllText($source, @'
#include <chrono>
#include <thread>
#include <iostream>
int main(int argc, char** argv) {
    if (argc > 1) { std::cout << argv[1] << std::endl; }
    std::this_thread::sleep_for(std::chrono::minutes(5));
}
'@)
$launched = Check-DD @('launch','app','--','argument with spaces')
$process = Get-Process -Id $launched.data.pid -ErrorAction Stop
try {
    if ($launched.data.status -ne 'started' -or $process.HasExited) { throw 'Persistent process did not survive dd exit.' }
    if ($launched.data.executable -notmatch '[\\/]out[\\/]') { throw 'Launch ignored target output paths.' }
    $timer = [Diagnostics.Stopwatch]::StartNew()
    $logged = ''
    while ($timer.Elapsed.TotalSeconds -lt 5 -and -not $logged) {
        if (Test-Path $launched.data.stdoutLog) {
            $stream = [IO.File]::Open($launched.data.stdoutLog, 'Open', 'Read', 'ReadWrite')
            $reader = [IO.StreamReader]::new($stream)
            try { $logged = $reader.ReadToEnd().Trim() } finally { $reader.Dispose() }
        }
        if (-not $logged) { $null = $process.WaitForExit(100) }
    }
    if ($logged -ne 'argument with spaces') { throw 'Launch arguments or file-backed stdout were not preserved.' }
} finally { if (-not $process.HasExited) { $process.Kill($true); $process.WaitForExit() }; $process.Dispose() }
$null = Check-DD @('run','app','--timeout','1') 1
Write-Host "PASS: existing-project presets, ownership, focused tests/failures, safe cleanup and detached launch. Fixture: $fixture"
exit 0