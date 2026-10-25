#requires -Version 7.4
$ErrorActionPreference = 'Stop'
. (Join-Path (Split-Path $PSScriptRoot) '.dd/core.ps1')
$root = [IO.Path]::GetTempPath()
$script:DDLogs = [Collections.Generic.List[string]]::new()
$null = Invoke-DDProcess git @('--version') $root
if ($script:DDLogs.Count) { throw 'Read-only process created a log.' }
# The first log a process writes clears dd's logs, JUnit reports and launch output
# older than two weeks, and nothing else. A temp directory of its own keeps the
# check away from the caller's real logs even when this script runs by itself.
$pruneTemp = Join-Path $root ('dd-prune-' + [guid]::NewGuid().ToString('N').Substring(0, 8))
$savedTemp = @{ TEMP = $env:TEMP; TMP = $env:TMP; TMPDIR = $env:TMPDIR }
try {
    foreach ($folder in @('dd-logs', 'dd-launch', 'dd-logs/sub')) { [IO.Directory]::CreateDirectory((Join-Path $pruneTemp $folder)) | Out-Null }
    $old = [DateTime]::UtcNow.AddDays(-20)
    $stale = @('dd-logs/old.log', 'dd-launch/old.stdout.log', 'dd-ctest-old.xml')
    $kept = @('dd-logs/new.log', 'dd-logs/old.txt', 'dd-logs/sub/old.log', 'dd-launch/old.txt', 'other-old.log', 'dd-ctest-old.txt')
    foreach ($name in $stale + $kept) {
        $path = Join-Path $pruneTemp $name
        [IO.File]::WriteAllText($path, 'x')
        if ($name -ne 'dd-logs/new.log') { [IO.File]::SetLastWriteTimeUtc($path, $old) }
    }
    $env:TEMP = $pruneTemp; $env:TMP = $pruneTemp; $env:TMPDIR = $pruneTemp
    $script:DDLogsPruned = $false
    $null = Invoke-DDProcess git @('--version') $root -Log
    $left = @($stale | Where-Object { Test-Path -LiteralPath (Join-Path $pruneTemp $_) })
    $lost = @($kept | Where-Object { -not (Test-Path -LiteralPath (Join-Path $pruneTemp $_)) })
    if ($left.Count -or $lost.Count) { throw "Log pruning kept [$($left -join ', ')] and removed [$($lost -join ', ')]." }
}
finally {
    $env:TEMP = $savedTemp.TEMP; $env:TMP = $savedTemp.TMP; $env:TMPDIR = $savedTemp.TMPDIR
    Remove-Item -LiteralPath $pruneTemp -Recurse -Force -ErrorAction SilentlyContinue
}
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