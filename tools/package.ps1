#requires -Version 7.4
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot
. (Join-Path $root '.dd/core.ps1')
if (-not (Test-Path (Join-Path $root '.dd/templates/common/dd.psd1'))) { throw 'The native dd.psd1 template is missing.' }
foreach ($file in (Get-DDRuntimeFiles)) {
    if (-not (Test-Path -LiteralPath (Join-Path $root ".dd/$file") -PathType Leaf)) { throw "Missing runtime file: .dd/$file" }
}
$output = Join-Path $root 'dist'
$archive = Join-Path $output 'dd.zip'
if (Test-Path $archive) { throw 'dist/dd.zip already exists. Move the previous package aside before packaging again.' }
[IO.Directory]::CreateDirectory($output) | Out-Null
$stage = Join-Path $output ('stage-' + [guid]::NewGuid().ToString('N'))
try {
    [IO.Directory]::CreateDirectory($stage) | Out-Null
    foreach ($file in @('dd.ps1', 'profile.ps1', 'bootstrap.ps1', 'README.md')) { Copy-Item (Join-Path $root $file) $stage }
    Copy-DDRuntime (Join-Path $stage '.dd')
    foreach ($folder in @('schema', 'docs', 'examples')) { Copy-Item (Join-Path $root $folder) (Join-Path $stage $folder) -Recurse }
    $files = @(Get-ChildItem $stage -Recurse -File -Force | ForEach-Object {
        @{ path = [IO.Path]::GetRelativePath($stage, $_.FullName).Replace('\', '/'); sha256 = (Get-FileHash $_.FullName -Algorithm SHA256).Hash.ToLowerInvariant() }
    })
    $listed = @($files | ForEach-Object { $_.path })
    foreach ($required in (Get-DDReleaseFiles)) {
        if ($listed -notcontains $required) { throw "Staged release is missing $required" }
    }
    [IO.File]::WriteAllText((Join-Path $stage 'release.json'), (@{ schema = 1; version = $script:DDVersion; files = $files } | ConvertTo-Json -Depth 5))
    [IO.Compression.ZipFile]::CreateFromDirectory($stage, $archive)
}
finally { if (Test-Path -LiteralPath $stage) { Remove-Item -LiteralPath $stage -Recurse -Force } }
$hash = (Get-FileHash $archive -Algorithm SHA256).Hash.ToLowerInvariant()
[IO.File]::WriteAllText((Join-Path $output 'dd.zip.sha256'), "$hash  dd.zip`n")
Write-Host "Packaged dd $($script:DDVersion): $archive ($hash)"