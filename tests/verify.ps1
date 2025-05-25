#requires -Version 7.4
$ErrorActionPreference = 'Stop'
# ci-exit.ps1 wraps bootstrap/dependencies/smoke to assert runner exit-code handling.
$indirect = @('verify.ps1', 'ci-exit.ps1', 'bootstrap.ps1')
$windowsOnly = @('compiler-environment.ps1', 'gui.ps1')
$ordered = @('contracts.ps1', 'manifest.ps1', 'extensions-manifest.ps1', 'extensions.ps1', 'targets.ps1', 'requirements.ps1', 'discovery.ps1', 'presets.ps1', 'archives.ps1', 'adoption.ps1', 'smoke.ps1', 'mcp.ps1', 'vscode.ps1', 'cmake-declarations.ps1', 'dependencies.ps1', 'dependency-roundtrip.ps1', 'externalproject.ps1')
if ($IsWindows) { $ordered += $windowsOnly }
$available = @(Get-ChildItem -LiteralPath $PSScriptRoot -File -Filter '*.ps1' | ForEach-Object Name)
$unlisted = @($available | Where-Object { $_ -notin ($ordered + $indirect + $windowsOnly) })
if ($unlisted.Count) { throw "Regression scripts are not wired into verify.ps1: $($unlisted -join ', ')" }
foreach ($test in $ordered) {
    if ($test -notin $available) { throw "Missing regression script: $test" }
    $arguments = @('-NoProfile', '-File', (Join-Path $PSScriptRoot $test))
    if ($test -in @('smoke.ps1', 'vscode.ps1')) { $arguments += '-Build' }
    & pwsh @arguments
    if ($LASTEXITCODE -ne 0) { throw "Regression test failed: $test" }
}
Write-Host "PASS: $($ordered.Count) regression scripts on $([Runtime.InteropServices.RuntimeInformation]::OSDescription)."
exit 0