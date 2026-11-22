#requires -Version 7.4
[CmdletBinding()]
param(
    [string]$Workspace = (Split-Path (Split-Path $PSScriptRoot)),
    [string[]]$Project,
    [string]$BuildDir,
    [string]$FilePattern = '*',
    [string]$ClangTidy = 'clang-tidy',
    [ValidateRange(1, 32)][int]$Jobs = 4,
    [string]$Output = (Join-Path ([IO.Path]::GetTempPath()) ("csa-" + [guid]::NewGuid())),
    [switch]$List
)
$ErrorActionPreference = 'Stop'
$Workspace = (Resolve-Path -LiteralPath $Workspace).Path
$projects = if ($Project) {
    foreach ($p in $Project) { Get-Item -LiteralPath (Join-Path $Workspace $p) }
} else {
    Get-ChildItem -LiteralPath $Workspace -Directory | Where-Object { Test-Path (Join-Path $_.FullName '.csa.psd1') }
}
if (!$projects) { throw "No CSA projects under $Workspace" }
if ($BuildDir -and @($projects).Count -ne 1) { throw '-BuildDir requires one project' }
$null = New-Item -ItemType Directory -Path $Output
$Output = (Resolve-Path -LiteralPath $Output).Path
$reportable = @{}
$tasks = foreach ($p in $projects) {
    $cfg = Import-PowerShellDataFile -LiteralPath (Join-Path $p.FullName '.csa.psd1')
    $dir = if ($BuildDir) { $BuildDir } else { Join-Path $p.FullName $cfg.Build }
    $db = Get-Content -LiteralPath (Join-Path $dir 'compile_commands.json') -Raw | ConvertFrom-Json
    $owned = @{}
    $paths = & git -C $p.FullName -c core.quotepath=false ls-files -- @($cfg.Paths)
    if ($LASTEXITCODE) { throw "git ls-files failed for $p" }
    foreach ($path in $paths) {
        $full = [IO.Path]::GetFullPath((Join-Path $p.FullName $path))
        $owned[$full] = $true
        $reportable[$full] = $true
    }
    $sources = @($db | ForEach-Object { [IO.Path]::GetFullPath($_.file, $_.directory) } |
        Where-Object { $_ -match '\.(c|cc|cpp|cxx)$' -and $owned.ContainsKey($_) } | Sort-Object -Unique)
    if (!$sources) { throw "No owned compile commands for $($p.Name) in $dir" }
    $projectOut = New-Item -ItemType Directory -Path (Join-Path $Output $p.Name)
    $owned.Keys | Where-Object { $_ -match '\.(c|cc|cpp|cxx)$' -and $_ -notin $sources } |
        Sort-Object | Set-Content -LiteralPath (Join-Path $projectOut 'not-in-build.txt')
    $sources = @($sources | Where-Object { $_ -like $FilePattern })
    if (!$sources) { throw "No matching inputs for $($p.Name): $FilePattern" }
    $sources | Set-Content -LiteralPath (Join-Path $projectOut 'inputs.txt')
    # Match actual tracked headers, not every header included by an owned TU.
    $headers = @($owned.Keys | Where-Object { $_ -match '\.(h|hh|hpp|hxx|inl|inc)$' } |
        ForEach-Object { [regex]::Escape(($_ -replace '\\','/')).Replace('/', '[\\/]') })
    $filter = if ($headers.Count) { '^(' + ($headers -join '|') + ')$' } else { '^$' }
    $config = Join-Path $projectOut 'config.json'
    @{ Checks = '-*,clang-analyzer-*,-clang-analyzer-optin.performance.Padding,-clang-analyzer-security.insecureAPI.DeprecatedOrUnsafeBufferHandling'
       HeaderFilterRegex = $filter; SystemHeaders = $false } | ConvertTo-Json | Set-Content -LiteralPath $config
    Write-Host "$($p.Name): $($sources.Count) translation units"
    foreach ($s in $sources) {
        $name = [IO.Path]::GetRelativePath($p.FullName, $s) -replace '[\\/]','_'
        [pscustomobject]@{ Source=$s; Build=$dir; Config=$config; Log=(Join-Path $projectOut "$name.log")
            Msvc=($IsWindows -and $s -match '\.(cc|cpp|cxx)$' -and $db[0].command -match '(?i)\bcl\.exe') }
    }
}
Write-Host "Report: $Output"
if ($List) { return }
$exe = (Get-Command $ClangTidy -CommandType Application -ErrorAction Stop | Select-Object -First 1).Source
$results = $tasks | ForEach-Object -Parallel {
    $extra = if ($IsWindows) { '--extra-arg=/Y-' }
    if ($_.Msvc) { $extra = @($extra, '--extra-arg=/clang:-fdelayed-template-parsing') }
    $argsList = @("--config-file=$($_.Config)", '-p', $_.Build) + @($extra | Where-Object { $_ }) + $_.Source
    & $using:exe @argsList > $_.Log 2>&1
    $rc = $LASTEXITCODE
    [pscustomobject]@{ Source=$_.Source; Exit=$rc; Log=$_.Log }
} -ThrottleLimit $Jobs
$results | Sort-Object Source | Export-Csv -LiteralPath (Join-Path $Output 'results.csv') -NoTypeInformation
$findings = @(Select-String -LiteralPath $results.Log -Pattern '^(.*):\d+:\d+: warning: .+ \[clang-analyzer-[^]]+\]$' |
    Where-Object { $reportable.ContainsKey([IO.Path]::GetFullPath($_.Matches[0].Groups[1].Value)) } |
    ForEach-Object Line | Sort-Object -Unique)
$findings | Set-Content -LiteralPath (Join-Path $Output 'findings.txt')
Write-Host "$($results.Count) translation units; $($findings.Count) distinct analyzer diagnostics"
if (@($results | Where-Object Exit -ne 0).Count) { throw "Analysis incomplete; see results.csv in $Output" }
