#requires -Version 7.4
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot
$fixture = Join-Path ([IO.Path]::GetTempPath()) ('dd-commands space-' + [guid]::NewGuid().ToString('N'))
[IO.Directory]::CreateDirectory((Join-Path $fixture 'tools')) | Out-Null
Copy-Item (Join-Path $PSScriptRoot 'fixtures/project-command.ps1') (Join-Path $fixture 'tools/command.ps1')
$manifest = @'
@{
    schema = 1
    project = @{ name = 'commands'; type = 'gui' }
    build = @{ 'x64-windows' = @{ debug = 'debug'; release = 'release' } }
    targets = @(@{ id = 'desktop'; kind = 'gui'; 'cmake-target' = 'app'; 'debug-path' = 'build/debug/app.exe'; 'release-path' = 'build/release/app.exe' })
    commands = @{
        version = @{
            description = 'Fixture version update'
            script = 'tools/command.ps1'
            effects = 'write'
            'supports-dry-run' = $true
            'timeout-secs' = 2
            parameters = @{
                part = @{ type = 'string'; choices = @('minor', 'patch'); default = 'patch' }
                text = @{ type = 'string'; required = $true }
                count = @{ type = 'integer'; default = 1 }
                fail = @{ type = 'boolean'; default = $false }
                invalid = @{ type = 'boolean'; default = $false }
                stall = @{ type = 'boolean'; default = $false }
            }
        }
    }
}
'@
[IO.File]::WriteAllText((Join-Path $fixture 'dd.psd1'), $manifest)
function Check-DD([string[]]$Values, [int]$Expected = 0) {
    $output = & pwsh -NoProfile -File (Join-Path $root 'dd.ps1') --project $fixture --json @Values
    if ($LASTEXITCODE -ne $Expected) { throw "Unexpected result: $output" }
    return $output | ConvertFrom-Json
}
$commands = Check-DD @('commands')
if ($commands.data.commands.Count -ne 1 -or $commands.data.commands[0].name -ne 'version') { throw 'Command discovery failed.' }
$help = Check-DD @('help', 'version')
if ($help.data.parameters.part.default -ne 'patch') { throw 'Command help lacks parameter defaults.' }
$null = Check-DD @('targets')
if (Test-Path (Join-Path $fixture 'request.json')) { throw 'Discovery executed project code.' }
$null = Check-DD @('version', '--text', 'hello') 2
$null = Check-DD @('version', '--text', 'hello', '--part', 'bad', '--yes') 2
$null = Check-DD @('version', '--yes') 2
$null = Check-DD @('version', '--text', 'hello', '--unknown', 'value', '--yes') 2
$null = Check-DD @('version', '--text', 'hello', '--count', '1.5', '--yes') 2
$null = Check-DD @('version', '--text', 'hello', '--fail', 'not-bool', '--yes') 2
$null = Check-DD @('version', '--text', 'first', '--text', 'second', '--yes') 2
$preview = Check-DD @('version', '--text=--literal with "quotes"; $value', '--count=-2', '--dry-run')
if (Test-Path (Join-Path $fixture 'request.json')) { throw 'Fixture dry-run modified project.' }
if ($preview.data.result.parameters.text -cne '--literal with "quotes"; $value' -or $preview.data.result.parameters.count -ne -2 -or $preview.data.result.parameters.part -ne 'patch') { throw 'Typed request/arguments changed.' }
$applied = Check-DD @('version', '--text=', '--part', 'minor', '--yes')
if (-not (Test-Path (Join-Path $fixture 'request.json')) -or $applied.data.result.parameters.text -cne '') { throw 'Confirmed command failed to apply.' }
$null = Check-DD @('version', '--text', 'hello', '--fail', 'true', '--yes') 7
$null = Check-DD @('version', '--text', 'hello', '--invalid', 'true', '--yes') 1
$timed = Check-DD @('version', '--text', 'hello', '--stall', 'true', '--yes') 1
if ($timed.errors[0] -notmatch 'timed out') { throw 'Timeout did not report failure.' }
$path = Join-Path $fixture 'dd.psd1'
[IO.File]::WriteAllText($path, $manifest.Replace("'supports-dry-run' = `$true", "'supports-dry-run' = `$false"))
$null = Check-DD @('version', '--text', 'hello', '--dry-run') 2
[IO.File]::WriteAllText($path, $manifest.Replace('tools/command.ps1', 'tools/missing.ps1'))
$missing = Check-DD @('commands')
if ($missing.data.commands[0].scriptExists) { throw 'Missing script discovery is incorrect.' }
$null = Check-DD @('version', '--text', 'hello', '--yes') 3
$unsupported = if ($IsWindows) { 'x64-linux' } else { 'x64-windows' }
[IO.File]::WriteAllText($path, $manifest.Replace("effects = 'write'", "effects = 'write'; platforms = @('$unsupported')"))
$null = Check-DD @('version', '--text', 'hello', '--yes') 2
[IO.File]::WriteAllText($path, $manifest.Replace('version = @{', 'inspect = @{').Replace("effects = 'write'", "effects = 'read'"))
$null = Check-DD @('inspect', '--text', 'inspection')
Copy-Item (Join-Path $root 'examples/version.ps1') (Join-Path $fixture 'tools/command.ps1') -Force
[IO.File]::WriteAllText($path, $manifest)
[IO.File]::WriteAllText((Join-Path $fixture 'VERSION'), "1.2.3`n")
$bump = Check-DD @('version', '--text', 'example', '--part', 'minor', '--dry-run')
if ($bump.data.result.next -ne '1.3.0' -or [IO.File]::ReadAllText((Join-Path $fixture 'VERSION')).Trim() -ne '1.2.3') { throw 'Version preview failed.' }
$bump = Check-DD @('version', '--text', 'example', '--part', 'minor', '--yes')
if ($bump.data.result.next -ne '1.3.0' -or [IO.File]::ReadAllText((Join-Path $fixture 'VERSION')).Trim() -ne '1.3.0') { throw 'Version apply failed.' }
Write-Host "PASS: project command discovery, typed parameters, confirmations, JSON protocol and failures. Fixture: $fixture"
exit 0