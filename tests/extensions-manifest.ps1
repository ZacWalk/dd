#requires -Version 7.4
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot
. (Join-Path $root '.dd/core.ps1')
$fixture = Join-Path ([IO.Path]::GetTempPath()) ('dd-extension-schema-' + [guid]::NewGuid().ToString('N'))
[IO.Directory]::CreateDirectory($fixture) | Out-Null
$manifest = @'
@{
    schema = 1
    project = @{ name = 'metadata'; type = 'gui'; 'default-target' = 'desktop' }
    build = @{ 'x64-windows' = @{ debug = 'debug'; release = 'release' } }
    targets = @(@{ id = 'desktop'; kind = 'gui'; 'cmake-target' = 'desktop'; 'debug-path' = 'build/debug/app.exe'; 'release-path' = 'build/release/app.exe' })
    commands = @{
        version = @{
            description = 'Update the version'
            script = 'tools/version.ps1'
            effects = 'write'
            'supports-dry-run' = $true
            parameters = @{ part = @{ type = 'string'; choices = @('major', 'minor', 'patch'); default = 'patch' } }
        }
    }
}
'@
$path = Join-Path $fixture 'dd.psd1'
[IO.File]::WriteAllText($path, $manifest)
$data = Read-DDManifest $fixture
if ($data.commands.version.parameters.part.default -ne 'patch') { throw 'Command metadata not preserved.' }
if (-not (Test-Json -Json ($data | ConvertTo-Json -Depth 20) -SchemaFile (Join-Path $root 'schema/dd.schema.json'))) { throw 'Manifest model does not match the public schema.' }
foreach ($replacement in @(@('version = @{', 'run = @{'), @("'desktop' }", "'missing' }"), @('tools/version.ps1', '../version.ps1'), @("default = 'patch'", "default = 'invalid'"))) {
    [IO.File]::WriteAllText($path, $manifest.Replace($replacement[0], $replacement[1]))
    $failure = $null
    try { $null = Read-DDManifest $fixture } catch { $failure = $_.Exception }
    if (-not $failure -or $failure.Data['exitCode'] -ne 2) { throw "Invalid extension schema was accepted: $($replacement[1])" }
}
Write-Host 'PASS: host-independent command metadata, default target, reserved names, script paths and typed defaults.'
exit 0