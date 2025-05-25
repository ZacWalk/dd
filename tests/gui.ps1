#requires -Version 7.4
$ErrorActionPreference = 'Stop'
if (-not $IsWindows) { throw 'GUI validation requires Windows.' }
$root = Split-Path $PSScriptRoot
$workspace = Join-Path ([IO.Path]::GetTempPath()) ('dd-gui-' + [guid]::NewGuid().ToString('N'))
[IO.Directory]::CreateDirectory($workspace) | Out-Null
$output = & pwsh -NoProfile -File (Join-Path $root 'dd.ps1') init --type gui --name gui-sample --project $workspace --json
if ($LASTEXITCODE) { throw $output }
$declarations = Get-Content (Join-Path $workspace 'cmake/dd-dependencies.json') -Raw | ConvertFrom-Json
if ($declarations.dependencies.'platform-h'.method -ne 'fetchcontent' -or (Test-Path (Join-Path $workspace 'deps'))) { throw 'GUI init must declare platform-h for FetchContent without fetching it.' }
$workflow = Get-Content (Join-Path $workspace '.github/workflows/ci.yml') -Raw
if (-not $workflow.Contains('os: ["windows-latest"]') -or $workflow.Contains('ubuntu-24.04') -or $workflow.Contains('@CI_RUNNERS@')) { throw 'GUI workflow must run on Windows only.' }
$launch = Get-Content (Join-Path $workspace '.vscode/launch.json') -Raw | ConvertFrom-Json
if ($launch.configurations.Count -ne 1 -or $launch.configurations[0].type -ne 'cppvsdbg' -or $launch.configurations[0].preLaunchTask -ne 'dd: build debug') { throw 'GUI F5 configuration must use the Windows C++ debugger and dd Debug task.' }
$output = & pwsh -NoProfile -File (Join-Path $root 'dd.ps1') test --project $workspace --json
if ($LASTEXITCODE) { throw $output }
$result = $output | ConvertFrom-Json
$windows = @($result.data.results | Where-Object status -eq 'passed')
if ($windows.Count -ne 2 -or @($windows | Where-Object title -ne 'gui-sample').Count) { throw "Window title or smoke result mismatch: $output" }
$manifestPath = Join-Path $workspace 'dd.psd1'
$text = [IO.File]::ReadAllText($manifestPath).Replace("id = 'app'", "id = 'viewer'").Replace('/bin/app{exe}', '/bin/picture-viewer{exe}')
$editor = @'
	targets = @(
		@{ id = 'editor'; kind = 'gui'; 'cmake-target' = 'editor'; 'debug-path' = 'build/{platform}/debug/bin/picture-editor{exe}'; 'release-path' = 'build/{platform}/release/bin/picture-editor{exe}' }
'@
[IO.File]::WriteAllText($manifestPath, $text.Replace('    targets = @(', $editor))
[IO.File]::AppendAllText((Join-Path $workspace 'CMakeLists.txt'), @'

set_target_properties(app PROPERTIES OUTPUT_NAME picture-viewer)
platform_add_app(editor SOURCES src/main.cpp OUTPUT_NAME picture-editor)
'@)
$output = & pwsh -NoProfile -File (Join-Path $root 'dd.ps1') test --project $workspace --json
if ($LASTEXITCODE -or @(($output | ConvertFrom-Json).data.results | Where-Object status -eq 'passed').Count -ne 4) { throw "Multi-app GUI tests failed: $output" }
$output = & pwsh -NoProfile -File (Join-Path $root 'dd.ps1') launch editor --project $workspace --json
if ($LASTEXITCODE) { throw "GUI launch failed: $output" }
$launched = ($output | ConvertFrom-Json).data
$process = Get-Process -Id $launched.pid -ErrorAction Stop
try {
	if ($launched.executable -notmatch 'picture-editor.exe$') { throw 'Launch confused app IDs with binary names.' }
	$timer = [Diagnostics.Stopwatch]::StartNew()
	while ($timer.Elapsed.TotalSeconds -lt 20 -and -not $process.MainWindowHandle -and -not $process.HasExited) { $null = $process.WaitForExit(100); $process.Refresh() }
	if ($process.HasExited -or -not $process.MainWindowHandle) { throw 'Detached GUI did not remain open after driver exit.' }
} finally {
	if (-not $process.HasExited) { $null = $process.CloseMainWindow(); if (-not $process.WaitForExit(4000)) { $process.Kill($true); $process.WaitForExit() } }
	$process.Dispose()
}
$presetsPath = Join-Path $workspace 'CMakePresets.json'
$presets = Get-Content $presetsPath -Raw | ConvertFrom-Json -AsHashtable
($presets.configurePresets | Where-Object name -eq 'windows-ide').binaryDir = '${sourceDir}/custom-ide'
[IO.File]::WriteAllText($presetsPath, ($presets | ConvertTo-Json -Depth 20))
$output = & pwsh -NoProfile -File (Join-Path $root 'dd.ps1') ide --project $workspace --json
if ($LASTEXITCODE -or ($output | ConvertFrom-Json).data.solution -notmatch '[\\/]custom-ide[\\/]') { throw "Declared IDE preset was not honored: $output" }
Write-Host "PASS: GUI scaffold, two app IDs/output names, both builds, window smoke, persistent launch and custom IDE directory. Fixture: $workspace"
exit 0