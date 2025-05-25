#requires -Version 7.4
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot
$fixture = Join-Path ([IO.Path]::GetTempPath()) ('dd-bootstrap-' + [guid]::NewGuid().ToString('N'))
[IO.Directory]::CreateDirectory($fixture) | Out-Null
$profilePath = Join-Path $fixture 'profile.ps1'
[IO.File]::WriteAllText($profilePath, '$env:DD_PROFILE_TEST = "preserved"' + "`n")
$archive = Join-Path $root 'dist/dd.zip'
$zip = [IO.Compression.ZipFile]::OpenRead($archive)
try {
	$entries = @($zip.Entries | Select-Object -ExpandProperty FullName)
	if ($entries -match '(?i)Tomlyn|^\.dd/lib/|dd\.toml$') { throw 'Release contains obsolete parser or manifest files.' }
	if ($entries -notcontains '.dd/templates/common/dd.psd1') { throw 'Release is missing the PSD1 template.' }
	if ($entries -notcontains '.dd/project-commands.ps1' -or $entries -notcontains 'examples/version.ps1') { throw 'Release is missing project command support or its example.' }
	if ($entries -notcontains '.dd/dependencies.cmake' -or $entries -notcontains '.dd/templates/common/cmake/dd-dependencies.json') { throw 'Release is missing the CMake dependency integration.' }
	if ($entries -match '(?i)node_modules|package(-lock)?\.json$|\.m?js$|\.ts$') { throw 'Release contains JavaScript dependencies or build artifacts.' }
	if ($entries -notcontains '.dd/mcp/server.ps1' -or $entries -notcontains '.dd/mcp/tools.ps1' -or $entries -notcontains '.dd/mcp/invoke.ps1') { throw 'Release is missing PowerShell MCP.' }
}
finally { $zip.Dispose() }
$hash = (Get-FileHash $archive -Algorithm SHA256).Hash
$arguments = @('-NoProfile', '-File', (Join-Path $root 'bootstrap.ps1'), '-ArchivePath', $archive, '-Sha256', $hash, '-InstallRoot', (Join-Path $fixture 'install'), '-RegisterProfile', '-ProfilePath', $profilePath)
& pwsh @arguments
if ($LASTEXITCODE) { throw 'Bootstrap failed.' }
$first = [IO.File]::ReadAllText($profilePath)
& pwsh @arguments
if ($LASTEXITCODE -or [IO.File]::ReadAllText($profilePath) -ne $first) { throw 'Bootstrap is not idempotent.' }
if (-not $first.Contains('DD_PROFILE_TEST')) { throw 'Profile content lost.' }
. $profilePath
$application = Join-Path $fixture 'packaged-app'
[IO.Directory]::CreateDirectory($application) | Out-Null
Push-Location $application
try {
	$created = dd init --type cli --name packaged-app --json
	if ($LASTEXITCODE -or -not ($created | ConvertFrom-Json).ok) { throw "Installed launcher failed: $created" }
	if (-not (Test-Path 'dd.psd1') -or (Test-Path '.dd/lib')) { throw 'Packaged scaffold did not use dependency-free PSD1.' }
	if (-not (Test-Path '.dd/mcp/server.ps1') -or -not (Test-Path '.vscode/mcp.json')) { throw 'Packaged scaffold is missing project-local MCP.' }
	$declared = dd dep install spike-db --json
	if ($LASTEXITCODE -or ($declared | ConvertFrom-Json).data.method -ne 'fetchcontent') { throw 'Packaged dependency declaration failed.' }
	$tested = dd test --json
	if ($LASTEXITCODE -or -not ($tested | ConvertFrom-Json).ok) { throw "Packaged application build/test failed: $tested" }
	[IO.Directory]::CreateDirectory((Join-Path $application 'tools')) | Out-Null
	Copy-Item (Join-Path $root 'examples/version.ps1') (Join-Path $application 'tools/version.ps1')
	$manifestPath = Join-Path $application 'dd.psd1'
	$command = "commands = @{ version = @{ description = 'Bump version'; script = 'tools/version.ps1'; effects = 'write'; 'supports-dry-run' = `$true; parameters = @{ part = @{ type = 'string'; default = 'patch'; choices = @('major','minor','patch') } } } }"
	[IO.File]::WriteAllText($manifestPath, [IO.File]::ReadAllText($manifestPath).Replace('schema = 1', "schema = 1`n$command"))
	[IO.File]::WriteAllText((Join-Path $application 'VERSION'), "1.2.3`n")
	$preview = dd version --part minor --dry-run --json | ConvertFrom-Json
	if ($LASTEXITCODE -or $preview.data.result.next -ne '1.3.0' -or [IO.File]::ReadAllText((Join-Path $application 'VERSION')).Trim() -ne '1.2.3') { throw 'Packaged command preview failed.' }
	$applied = dd version --part minor --yes --json | ConvertFrom-Json
	if ($LASTEXITCODE -or $applied.data.result.next -ne '1.3.0' -or [IO.File]::ReadAllText((Join-Path $application 'VERSION')).Trim() -ne '1.3.0') { throw 'Packaged command apply failed.' }
}
finally { Pop-Location }
& pwsh -NoProfile -File (Join-Path $PSScriptRoot 'mcp.ps1') -Server (Join-Path $application '.dd/mcp/server.ps1') -ProtocolOnly
if ($LASTEXITCODE) { throw 'Packaged PowerShell MCP protocol failed.' }
$bad = & pwsh -NoProfile -File (Join-Path $root 'bootstrap.ps1') -ArchivePath $archive -Sha256 ('0' * 64) -InstallRoot (Join-Path $fixture 'bad') -NoProfile 2>&1
if ($LASTEXITCODE -eq 0 -or (Test-Path (Join-Path $fixture 'bad'))) { throw 'Corrupt release was accepted.' }
Write-Host "PASS: parser-free release, packaged PSD1/MCP scaffold, build/tests, profile preservation/idempotence and checksum rejection. Fixture: $fixture"
exit 0