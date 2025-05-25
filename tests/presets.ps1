#requires -Version 7.4
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot
foreach ($module in @('core','execution','presets','dependencies','commands')) { . (Join-Path $root ".dd/$module.ps1") }
$fixture = Join-Path ([IO.Path]::GetTempPath()) ('dd-presets-' + [guid]::NewGuid().ToString('N'))
[IO.Directory]::CreateDirectory($fixture) | Out-Null
$null = Invoke-DDGit $fixture @('init')
$platform = Get-DDPlatform
$manifest = "@{ schema=1; dependencies=@{owner='application'}; project=@{name='presets';type='cli'}; build=@{'$platform'=@{debug=@{configure='custom';build='compile';test='check'};release=@{configure='custom';build='compile';test='check'}}}; targets=@(@{id='app';kind='cli';'cmake-target'='app';'debug-path'='out/app';'release-path'='out/app'}) }"
[IO.File]::WriteAllText((Join-Path $fixture 'dd.psd1'), $manifest)
[IO.File]::WriteAllText((Join-Path $fixture 'CMakeLists.txt'), "cmake_minimum_required(VERSION 3.24)`nproject(presets NONE)`n")
[IO.File]::WriteAllText((Join-Path $fixture 'included.json'), @'
{"version":5,"configurePresets":[
 {"name":"first","hidden":true,"environment":{"ONE":"1","SAME":"first"}},
 {"name":"second","hidden":true,"generator":"Ninja Multi-Config","environment":{"TWO":"2","SAME":"second"},"binaryDir":"${sourceDir}/$penv{DD_PRESET_TEST_DIR}"}
]}
'@)
[IO.File]::WriteAllText((Join-Path $fixture 'CMakePresets.json'), @'
{"version":5,"include":["included.json"],"configurePresets":[{"name":"custom","inherits":["first","second"]}],
"buildPresets":[{"name":"compile","configurePreset":"custom","configuration":"Debug"}],
"testPresets":[{"name":"check","configurePreset":"custom","configuration":"Debug"}]}
'@)
$previous = $env:DD_PRESET_TEST_DIR
try {
    $env:DD_PRESET_TEST_DIR = 'out'
    $catalog = Get-DDPresetCatalog $fixture
    $resolved = Resolve-DDPreset $catalog 'configurePresets' 'custom'
    if ($resolved.environment.ONE -ne '1' -or $resolved.environment.TWO -ne '2' -or $resolved.environment.SAME -ne 'first') { throw 'Inheritance priority or merge is incorrect.' }
    $mapping = Get-DDPresetMapping (Read-DDManifest $fixture) 'debug'
    $null = Invoke-DDConfigure $fixture $mapping 'debug'
    $null = Invoke-DDConfigure $fixture $mapping 'release'
    $null = Invoke-DDClean $fixture (Read-DDOptions @('clean','both','--dry-run'))
    $caught = $false
    try { $null = Invoke-DDClean $fixture (Read-DDOptions @('clean','debug','--dry-run')) } catch { $caught = $_.Exception.Message -match 'multi-config|shared' }
    if (-not $caught) { throw 'Single-config cleanup accepted a shared tree.' }
    $env:DD_PRESET_TEST_DIR = 'elsewhere'
    $caught = $false
    try { $null = Read-DDPresetState $fixture 'debug' } catch { $caught = $_.Exception.Message -match 'environment' }
    if (-not $caught) { throw 'Environment changes did not invalidate cleanup metadata.' }
} finally { $env:DD_PRESET_TEST_DIR = $previous }
Write-Host 'PASS: included/inherited presets, distinct phases, shared multi-config cleanup and environment invalidation.'
exit 0