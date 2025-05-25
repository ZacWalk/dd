#requires -Version 7.4
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot
. (Join-Path $root '.dd/core.ps1')
. (Join-Path $root '.dd/requirements.ps1')
$fixture = Join-Path ([IO.Path]::GetTempPath()) ('dd-requirements-' + [guid]::NewGuid().ToString('N'))
[IO.Directory]::CreateDirectory($fixture) | Out-Null
$template = [IO.File]::ReadAllText((Join-Path $root '.dd/templates/common/dd.psd1')).Replace('@NAME@','requirements').Replace('@TYPE@','cli')
$path = Join-Path $fixture 'dd.psd1'
[IO.File]::WriteAllText($path, $template.Replace('schema = 1', "schema = 1`nrequirements = @{ tools = @{ cmake = @{ minimum = '999.0' }; python = @{ minimum = '999.0'; optional = `$true } }; msvc = @{ components = @('Microsoft.VisualStudio.Component.VC.ATL') } }"))
$requirements = Get-DDRequirements $fixture
if ($requirements.tools.cmake.minimum -ne '999.0' -or -not $requirements.tools.python.optional -or $requirements.msvc.components -notcontains 'Microsoft.VisualStudio.Component.VC.ATL') { throw 'Requirements were not merged.' }
$report = Get-DDRequirementReport $fixture
if ($report.ready -or -not ($report.issues -match 'cmake') -or -not ($report.warnings -match 'python') -or $report.packages -contains 'Python.Python.3.13' -or $report.packages -contains 'python3') { throw 'Required and optional checks/plans diverged.' }
[IO.File]::WriteAllText($path, [IO.File]::ReadAllText($path).Replace('schema = 1', "schema = 1`ndependencies = @{ owner = 'application' }"))
foreach ($command in @('doctor','build')) {
	$output = & pwsh -NoProfile -File (Join-Path $root 'dd.ps1') --project $fixture --json $command
	if ($LASTEXITCODE -ne 3 -or ($output | ConvertFrom-Json).ok) { throw "$command did not preserve prerequisite exit code 3: $output" }
}
$output = & pwsh -NoProfile -File (Join-Path $root 'dd.ps1') --project $fixture --json toolchain --dry-run
if ($LASTEXITCODE -or -not (($output | ConvertFrom-Json).data.issues -match 'cmake')) { throw 'Toolchain plan used different checks.' }
if (Test-Path (Join-Path $fixture '.dd/state')) { throw 'Failed prerequisites ran configure.' }
Write-Host 'PASS: merged native versions/components and optional prerequisite planning.'
exit 0