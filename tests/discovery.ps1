#requires -Version 7.4
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot
$driver = Join-Path $root 'dd.ps1'
$fixture = Join-Path ([IO.Path]::GetTempPath()) ('dd-discovery-' + [guid]::NewGuid().ToString('N'))
[IO.Directory]::CreateDirectory($fixture) | Out-Null
function Invoke-At([string]$Directory, [string[]]$Values, [int]$Expected = 0) {
    # The child must inherit $Directory as its real working directory; Set-Location alone
    # does not update the process CWD that CreateProcess/fork inherits.
    $start = [Diagnostics.ProcessStartInfo]::new((Join-Path $PSHOME $(if ($IsWindows) { 'pwsh.exe' } else { 'pwsh' })))
    $start.WorkingDirectory = $Directory
    $start.UseShellExecute = $false
    $start.RedirectStandardOutput = $true
    $start.RedirectStandardError = $true
    foreach ($argument in @('-NoProfile', '-NonInteractive', '-File', $driver, '--json') + $Values) { $start.ArgumentList.Add($argument) }
    $process = [Diagnostics.Process]::new()
    $process.StartInfo = $start
    try {
        $null = $process.Start()
        $stdout = $process.StandardOutput.ReadToEndAsync()
        $stderr = $process.StandardError.ReadToEndAsync()
        $process.WaitForExit()
        $output = $stdout.GetAwaiter().GetResult()
        if ($process.ExitCode -ne $Expected) { throw "Unexpected exit $($process.ExitCode) for '$($Values -join ' ')' in ${Directory}: $output$($stderr.GetAwaiter().GetResult())" }
        return $output | ConvertFrom-Json
    }
    finally { $process.Dispose() }
}
$null = Invoke-At $fixture @('init', '--type', 'cli', '--name', 'discovery')
$manifestPath = Join-Path $fixture 'dd.psd1'
$requirement = "requirements = @{ tools = @{ cmake = @{ minimum = '999.0' } } }"
[IO.File]::WriteAllText($manifestPath, [IO.File]::ReadAllText($manifestPath).Replace('schema = 1', "schema = 1`n    $requirement"))
$child = Join-Path $fixture 'src'

# doctor, toolchain and dep must see the manifest from a subdirectory, not just the root.
$fromRoot = Invoke-At $fixture @('doctor') 3
$fromChild = Invoke-At $child @('doctor') 3
if ($fromRoot.data.ready -or $fromChild.data.ready) { throw 'Project requirements were ignored.' }
if (-not ($fromChild.data.issues -match 'cmake')) { throw 'Subdirectory doctor did not apply project requirements.' }
if ($fromChild.data.dependencyOwner -ne 'dd' -or -not $fromChild.data.inventoryKnown) { throw 'Subdirectory doctor lost dependency ownership.' }
$plan = Invoke-At $child @('toolchain', '--dry-run') 0
if (-not ($plan.data.issues -match 'cmake')) { throw 'Subdirectory toolchain plan ignored project requirements.' }
$listed = Invoke-At $child @('dep', 'list')
if ($listed.data.dependencies -isnot [array]) { throw 'Subdirectory dep list did not resolve the project.' }
$configured = Invoke-At $child @('mcp')
if ($configured.data.servers.dd.args -notcontains $fixture) { throw 'MCP registration used the subdirectory instead of the project root.' }

# Machine-level inspection must still work with no project anywhere above the cwd.
$orphan = Join-Path $fixture 'orphan'
[IO.Directory]::CreateDirectory($orphan) | Out-Null
[IO.File]::Delete($manifestPath)
$bare = Invoke-At $orphan @('doctor')
if (-not $bare.data.ready) { throw 'doctor outside a project must still report machine readiness.' }
if ($bare.data.dependencies.Count) { throw 'doctor outside a project reported project dependencies.' }
Write-Host "PASS: project discovery from subdirectories and project-less machine inspection. Fixture: $fixture"
exit 0
