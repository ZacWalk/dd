#requires -Version 7.4
$ErrorActionPreference = 'Stop'
. (Join-Path (Split-Path $PSScriptRoot) '.dd/core.ps1')
$root = [IO.Path]::GetTempPath()
$script:DDLogs = [Collections.Generic.List[string]]::new()
$null = Invoke-DDProcess git @('--version') $root
if ($script:DDLogs.Count) { throw 'Read-only process created a log.' }
$summary = Get-DDDiagnostics "C:\sample\a.cpp(10): warning C4100: unused`nC:\sample\a.cpp(20): warning C4100: unused`n/tmp/main.cpp:2:3: error: bad expression"
if ($summary.total -ne 3 -or ($summary.byCode | Where-Object Name -eq 'C4100').Count -ne 2) { throw 'Diagnostic grouping failed.' }
$rendered = & { Write-DDHumanResult @{ results = @(@{ configuration = 'debug'; status = 'built'; log = 'C:\logs\build.log'; diagnostics = $summary }) } } 6>&1 | Out-String
foreach ($expected in @('debug built', '3 diagnostics', 'Worst files', 'Most frequent codes', 'C:\sample\a.cpp', 'C4100', 'C:\logs\build.log')) {
    if (-not $rendered.Contains($expected)) { throw "Human build summary omitted '$expected':`n$rendered" }
}
if ($rendered -match '(?m)^\s*\{') { throw 'Human build output fell back to raw JSON.' }
$failed = & { Write-DDHumanResult @{ results = @(); testFailures = @(@{ name = 'intentional_failure' }) } } 6>&1 | Out-String
if (-not $failed.Contains('intentional_failure')) { throw 'Human output omitted failing test names.' }
$threw = $false
try { $null = Get-DDPath $root '../escape' } catch { $threw = $true }
if (-not $threw) { throw 'Path traversal accepted.' }
$options = Read-DDOptions @('run', 'app', '--', 'space value', '--flag', '')
if ($options.forwarded.Count -ne 3 -or $options.forwarded[0] -ne 'space value' -or $options.forwarded[2] -ne '') { throw 'Argument forwarding changed tokens.' }
Write-Host 'PASS: read-only logging, grouped diagnostics, human triage rendering, path boundaries and exact argument tokens.'