#requires -Version 7.4
$ErrorActionPreference = 'Stop'

function Test-RunnerExit([string]$Body, [int]$Expected, [string]$Name) {
    $wrapper = '$ErrorActionPreference = ''Stop''' + "`n" + $Body + "`n" + 'if (Test-Path -LiteralPath variable:\LASTEXITCODE) { exit $LASTEXITCODE }'
    $encoded = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($wrapper))
    $output = @(& pwsh -NoProfile -NonInteractive -EncodedCommand $encoded 2>&1)
    $actual = $LASTEXITCODE
    if ($actual -ne $Expected) { throw "GitHub-style invocation of $Name returned $actual instead of ${Expected}:`n$($output -join "`n")" }
    Write-Host "PASS: $Name returns $Expected with GitHub Actions exit handling."
}

Test-RunnerExit '& pwsh -NoProfile -Command "exit 7"' 7 'native failure control'
Test-RunnerExit 'throw "Intentional assertion failure"' 1 'assertion failure control'
foreach ($test in @('smoke.ps1', 'dependencies.ps1', 'bootstrap.ps1')) {
    $path = (Join-Path $PSScriptRoot $test).Replace("'", "''")
    Test-RunnerExit ". '$path'" 0 $test
}
exit 0