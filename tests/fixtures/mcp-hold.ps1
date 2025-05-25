#requires -Version 7.4
$ErrorActionPreference = 'Stop'
$request = [Console]::In.ReadLine() | ConvertFrom-Json
$child = [Diagnostics.Process]::new()
$child.StartInfo = [Diagnostics.ProcessStartInfo]::new((Join-Path $PSHOME $(if ($IsWindows) { 'pwsh.exe' } else { 'pwsh' })))
$child.StartInfo.UseShellExecute = $false
foreach ($argument in @('-NoProfile','-NonInteractive','-Command','[Threading.ManualResetEventSlim]::new($false).Wait(30000)')) { $child.StartInfo.ArgumentList.Add($argument) }
$null = $child.Start()
try {
    [IO.File]::WriteAllText((Join-Path $request.projectRoot 'hold.json'), (@{ parent = $PID; child = $child.Id } | ConvertTo-Json -Compress))
    $null = $child.WaitForExit(30000)
    [Console]::Out.WriteLine('{"schema":1,"data":{},"files":[]}')
} finally { if (-not $child.HasExited) { $child.Kill($true) }; $child.Dispose() }