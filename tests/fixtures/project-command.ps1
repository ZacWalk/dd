$ErrorActionPreference = 'Stop'
$request = [Console]::In.ReadLine() | ConvertFrom-Json -AsHashtable
$result = @{ schema = 1; data = $request; files = @() }
if ($request.parameters.Contains('fail') -and $request.parameters.fail) { [Console]::Error.WriteLine('Intentional fixture failure'); exit 7 }
if ($request.parameters.Contains('invalid') -and $request.parameters.invalid) { [Console]::Out.WriteLine('not JSON'); exit 0 }
if ($request.parameters.Contains('stall') -and $request.parameters.stall) {
    $wait = [Threading.ManualResetEvent]::new($false)
    try { $null = $wait.WaitOne(10000) } finally { $wait.Dispose() }
}
if (-not $request.dryRun -and $request.command -ne 'inspect') {
    [IO.File]::WriteAllText((Join-Path $request.projectRoot 'request.json'), ($request | ConvertTo-Json -Depth 10))
}
$result.files = @('request.json')
[Console]::Out.WriteLine(($result | ConvertTo-Json -Depth 10 -Compress))