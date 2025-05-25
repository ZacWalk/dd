#requires -Version 7.4
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot
. (Join-Path $root '.dd/core.ps1')
foreach ($required in @('dd.ps1', 'profile.ps1', 'bootstrap.ps1', '.dd/templates/common/dd.psd1', '.dd/templates/common/cmake/dd-dependencies.json') + ((Get-DDRuntimeFiles) | ForEach-Object { ".dd/$_" })) {
	if (-not (Test-Path -LiteralPath (Join-Path $root $required) -PathType Leaf)) { throw "Missing source file: $required" }
}
# bootstrap.ps1 cannot dot-source the runtime it is about to verify, so its copy of the
# required file list is checked here rather than trusted.
$declared = [regex]::Match([IO.File]::ReadAllText((Join-Path $root 'bootstrap.ps1')), '(?s)foreach \(\$required in @\((?<list>.*?)\)\) \{\s*\r?\n\s*if \(-not \$expected')
if (-not $declared.Success) { throw 'Could not locate the bootstrap release file list.' }
$bootstrapFiles = @([regex]::Matches($declared.Groups['list'].Value, "'([^']+)'") | ForEach-Object { $_.Groups[1].Value })
$missing = @((Get-DDReleaseFiles) | Where-Object { $_ -notin $bootstrapFiles })
if ($missing.Count) { throw "bootstrap.ps1 does not require: $($missing -join ', ')" }
$unknown = @($bootstrapFiles | Where-Object { $_ -notin (Get-DDReleaseFiles) })
if ($unknown.Count) { throw "bootstrap.ps1 requires files the runtime does not declare: $($unknown -join ', ')" }
$schema = Get-Content (Join-Path $root 'schema/dd.schema.json') -Raw | ConvertFrom-Json -AsHashtable
$reserved = @($schema.properties.commands.propertyNames.not.enum)
$builtins = @(Get-DDBuiltinCommands)
if (@($builtins | Where-Object { $_ -notin $reserved }).Count -or @($reserved | Where-Object { $_ -notin $builtins }).Count) {
	throw 'schema/dd.schema.json reserved command names do not match Get-DDBuiltinCommands.'
}
$template = Import-PowerShellDataFile -LiteralPath (Join-Path $root '.dd/templates/common/dd.psd1')
if ($template.schema -ne 1) { throw 'Unsupported template schema.' }
$template.project.name = 'validation'
$template.project.type = 'cli'
$template.targets[0].kind = 'cli'
$json = $template | ConvertTo-Json -Depth 20
if (-not (Test-Json -Json $json -SchemaFile (Join-Path $root 'schema/dd.schema.json'))) { throw 'Scaffold does not match the published schema.' }
foreach ($file in Get-ChildItem (Join-Path $root '.dd') -Recurse -Filter '*.ps1') {
	$tokens = $null; $errors = $null
	$null = [Management.Automation.Language.Parser]::ParseFile($file.FullName, [ref]$tokens, [ref]$errors)
	if ($errors.Count) { throw "PowerShell syntax errors in $($file.FullName): $errors" }
}
Write-Host "Validated dd $($script:DDVersion) runtime inventory, bootstrap/schema parity and the native dd.psd1 template."