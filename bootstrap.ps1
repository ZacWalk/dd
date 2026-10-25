param(
    [string]$Version = 'latest',
    [string]$InstallRoot,
    [switch]$RegisterProfile,
    [switch]$NoProfile,
    [string]$ProfilePath,
    [string]$ArchivePath,
    [string]$Sha256
)
$ErrorActionPreference = 'Stop'
if ($PSVersionTable.PSVersion -lt [version]'7.4') { throw 'dd requires PowerShell 7.4+. Install it from https://github.com/PowerShell/PowerShell/releases and rerun bootstrap in pwsh.' }
if (-not (Get-Command git -CommandType Application -ErrorAction SilentlyContinue)) { throw 'Git is required. Install Git using your OS package manager, then rerun bootstrap.' }
if ($RegisterProfile -and $NoProfile) { throw 'Choose either -RegisterProfile or -NoProfile.' }
if (-not $InstallRoot) {
    $InstallRoot = if ($IsWindows) { Join-Path $env:LOCALAPPDATA 'dd' } else { Join-Path $HOME '.local/share/dd' }
}
$InstallRoot = [IO.Path]::GetFullPath($InstallRoot)
$ancestor = $InstallRoot
while ($ancestor) {
    if ((Test-Path $ancestor) -and ((Get-Item -Force $ancestor).Attributes -band [IO.FileAttributes]::ReparsePoint)) { throw "Refusing linked installation path: $ancestor" }
    $parent = Split-Path $ancestor
    if ($parent -eq $ancestor) { break }
    $ancestor = $parent
}
$headers = @{ 'User-Agent' = 'dd-bootstrap'; Accept = 'application/vnd.github+json' }
if (-not $ArchivePath) {
    if ($Version -ne 'latest' -and $Version -notmatch '^v[0-9]+\.[0-9]+\.[0-9]+$') { throw 'Version must be latest or vMAJOR.MINOR.PATCH.' }
    $endpoint = if ($Version -eq 'latest') { 'latest' } else { "tags/$Version" }
    try { $release = Invoke-RestMethod "https://api.github.com/repos/ZacWalk/dd/releases/$endpoint" -Headers $headers }
    catch {
        $statusCode = if ($_.Exception.Response) { [int]$_.Exception.Response.StatusCode } else { [int]$_.Exception.StatusCode }
        if ($statusCode -eq 404) {
            throw "No published dd release was found for '$Version'. Publish a non-draft GitHub release containing dd.zip and dd.zip.sha256, or use the source-checkout instructions at https://github.com/ZacWalk/dd#try-the-source-checkout."
        }
        throw
    }
    $asset = @($release.assets | Where-Object name -eq 'dd.zip')
    $checksumAsset = @($release.assets | Where-Object name -eq 'dd.zip.sha256')
    if ($asset.Count -ne 1 -or $checksumAsset.Count -ne 1) { throw 'Release is missing dd.zip or dd.zip.sha256. No release may be published yet.' }
    foreach ($download in @($asset[0], $checksumAsset[0])) {
        if ($download.browser_download_url -notmatch '^https://github\.com/ZacWalk/dd/releases/download/') { throw 'Unexpected release download origin.' }
    }
    $ArchivePath = Join-Path ([IO.Path]::GetTempPath()) ('dd-release-' + [guid]::NewGuid().ToString('N') + '.zip')
    Invoke-WebRequest $asset[0].browser_download_url -OutFile $ArchivePath
    $checksumContent = (Invoke-WebRequest $checksumAsset[0].browser_download_url).Content
    $checksumText = if ($checksumContent -is [byte[]]) { [Text.Encoding]::UTF8.GetString($checksumContent) } else { [string]$checksumContent }
    $Sha256 = (($checksumText.Trim() -split '\s+')[0])
}
if ($Sha256 -notmatch '^[a-fA-F0-9]{64}$') { throw 'A SHA-256 checksum is required, including for local archive installation.' }
if ((Get-FileHash -LiteralPath $ArchivePath -Algorithm SHA256).Hash -ne $Sha256) { throw 'Archive checksum mismatch. Nothing installed.' }
[IO.Directory]::CreateDirectory($InstallRoot) | Out-Null
$stage = [IO.Path]::GetFullPath((Join-Path $InstallRoot ('.staging-' + [guid]::NewGuid().ToString('N'))))
# One handle validates and extracts, so entries cannot change between the two passes.
$zip = [IO.Compression.ZipFile]::OpenRead([IO.Path]::GetFullPath($ArchivePath))
try {
    $seen = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    $total = 0L
    foreach ($entry in $zip.Entries) {
        $name = $entry.FullName
        if ($name -match '(^/|\\|(^|/)\.\.(/|$)|:)' -or -not $seen.Add($name)) { throw "Unsafe archive entry: $name" }
        if ((($entry.ExternalAttributes -shr 16) -band 0xF000) -eq 0xA000) { throw 'Release archive contains a symlink.' }
        $total += $entry.Length
        if ($total -gt 256MB -or $seen.Count -gt 10000) { throw 'Release archive exceeds limits.' }
    }
    [IO.Directory]::CreateDirectory($stage) | Out-Null
    foreach ($entry in $zip.Entries) {
        if (-not $entry.Name) { continue }
        $destination = [IO.Path]::GetFullPath((Join-Path $stage $entry.FullName))
        if (-not $destination.StartsWith($stage + [IO.Path]::DirectorySeparatorChar, [StringComparison]::Ordinal)) { throw "Unsafe archive entry: $($entry.FullName)" }
        [IO.Directory]::CreateDirectory((Split-Path $destination)) | Out-Null
        [IO.Compression.ZipFileExtensions]::ExtractToFile($entry, $destination, $false)
    }
}
finally { $zip.Dispose() }
$manifestPath = Join-Path $stage 'release.json'
$manifest = Get-Content $manifestPath -Raw | ConvertFrom-Json
if ($manifest.schema -ne 1 -or $manifest.version -notmatch '^[0-9]+\.[0-9]+\.[0-9]+$') { throw 'Unsupported release manifest.' }
if ($Version -ne 'latest' -and $Version -ne "v$($manifest.version)") { throw 'Release version mismatch.' }
$expected = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
foreach ($file in $manifest.files) {
    if ($file.path -match '(^/|\\|(^|/)\.\.(/|$)|:)' -or -not $expected.Add($file.path)) { throw 'Invalid release file manifest.' }
    $path = Join-Path $stage $file.path
    if (-not (Test-Path -LiteralPath $path -PathType Leaf) -or (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash -ne $file.sha256) { throw "Release file verification failed: $($file.path)" }
}
foreach ($file in Get-ChildItem $stage -Recurse -File -Force) {
    $relative = [IO.Path]::GetRelativePath($stage, $file.FullName).Replace('\', '/')
    if ($relative -ne 'release.json' -and -not $expected.Contains($relative)) { throw "Unlisted release file: $relative" }
}
# Mirrors Get-DDReleaseFiles in .dd/core.ps1; tools/prepare.ps1 asserts the two agree.
foreach ($required in @('dd.ps1', 'profile.ps1', '.dd/core.ps1', '.dd/requirements.ps1', '.dd/presets.ps1', '.dd/execution.ps1', '.dd/dependencies.ps1', '.dd/commands.ps1', '.dd/project-commands.ps1', '.dd/dependencies.cmake', '.dd/catalog.json', '.dd/mcp/server.ps1', '.dd/mcp/tools.ps1', '.dd/mcp/invoke.ps1', '.dd/templates/common/dd.psd1', '.dd/templates/common/cmake/dd-dependencies.json')) {
    if (-not $expected.Contains($required)) { throw "Incomplete release: $required" }
}
$destination = Join-Path $InstallRoot ($manifest.version + '-' + $Sha256.Substring(0, 12).ToLowerInvariant())
if (-not (Test-Path $destination)) { Move-Item -LiteralPath $stage -Destination $destination }
else {
    foreach ($file in $manifest.files) {
        $path = Join-Path $destination $file.path
        if (-not (Test-Path $path) -or (Get-FileHash $path -Algorithm SHA256).Hash -ne $file.sha256) { throw 'An existing installed release was modified; refusing to overwrite it.' }
    }
}
if (-not $NoProfile -and -not $RegisterProfile -and -not [Console]::IsInputRedirected) {
    $RegisterProfile = (Read-Host 'Add dd to your PowerShell profile? This shadows the Unix dd utility in PowerShell on Linux. [y/N]') -eq 'y'
}
if ($RegisterProfile) {
    if (-not $ProfilePath) { $ProfilePath = $PROFILE.CurrentUserCurrentHost }
    $ProfilePath = [IO.Path]::GetFullPath($ProfilePath)
    $profileAncestor = $ProfilePath
    while ($profileAncestor) {
        if ((Test-Path $profileAncestor) -and (Get-Item -Force $profileAncestor).LinkType) { throw 'Refusing a linked profile path.' }
        $profileParent = Split-Path $profileAncestor
        if ($profileParent -eq $profileAncestor) { break }
        $profileAncestor = $profileParent
    }
    $existing = if (Test-Path $ProfilePath) { [IO.File]::ReadAllText($ProfilePath) } else { '' }
    $begin = '# BEGIN DD BUILD SYSTEM'
    $end = '# END DD BUILD SYSTEM'
    $pattern = '(?ms)^# BEGIN DD BUILD SYSTEM\r?\n.*?^# END DD BUILD SYSTEM(?:\r?\n)?'
    $blocks = [regex]::Matches($existing, $pattern)
    if ($blocks.Count -gt 1 -or (($existing.Contains($begin) -or $existing.Contains($end)) -and $blocks.Count -ne 1)) { throw 'Malformed dd profile markers. Repair them manually; profile unchanged.' }
    $outside = [regex]::Replace($existing, $pattern, '')
    if ($outside -match '(?im)\bfunction\s+(?:global:)?dd\b|\b(?:Set-Alias|New-Alias)\s+(?:-Name\s+)?dd\b') { throw 'An existing dd function or alias is preserved. Remove or rename it before requesting profile registration.' }
    $loader = (Join-Path $destination 'profile.ps1').Replace("'", "''")
    $block = "$begin`n. '$loader'`n$end`n"
    $updated = if ($blocks.Count) { $existing.Replace($blocks[0].Value, $block) } else { $existing.TrimEnd() + "`n" + $block }
    if ($updated -ne $existing) {
        [IO.Directory]::CreateDirectory((Split-Path $ProfilePath)) | Out-Null
        if (Test-Path $ProfilePath) {
            Copy-Item $ProfilePath ($ProfilePath + '.dd-backup-' + [DateTime]::UtcNow.ToString('yyyyMMddTHHmmssfffZ'))
            $stale = @(Get-ChildItem -LiteralPath (Split-Path $ProfilePath) -Force -File -Filter ((Split-Path $ProfilePath -Leaf) + '.dd-backup-*') | Sort-Object Name -Descending | Select-Object -Skip 3)
            foreach ($file in $stale) { Remove-Item -LiteralPath $file.FullName -Force -ErrorAction SilentlyContinue }
        }
        [IO.File]::WriteAllText($ProfilePath, $updated)
    }
    . (Join-Path $destination 'profile.ps1')
}
Write-Host "Installed dd $($manifest.version): $destination"
Write-Host "Without profile integration: pwsh -NoProfile -File `"$(Join-Path $destination 'dd.ps1')`" help"