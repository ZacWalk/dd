$installedDriver = Join-Path $PSScriptRoot 'dd.ps1'
$dispatcher = {
    $selectedDriver = $installedDriver
    $command = if ($args.Count) { [string]$args[0] } else { 'help' }
    if ($command -ne 'init') {
        $directory = (Get-Location).Path
        while ($directory) {
            $candidate = Join-Path $directory 'dd.ps1'
            if (Test-Path -LiteralPath $candidate -PathType Leaf) { $selectedDriver = $candidate; break }
            $parent = Split-Path $directory
            if ($parent -eq $directory) { break }
            $directory = $parent
        }
    }
    if ($command -eq 'env') {
        $result = & pwsh -NoProfile -File $selectedDriver @args --json | ConvertFrom-Json
        $global:LASTEXITCODE = $result.exitCode
        if (-not $result.ok) { Write-Error ($result.errors -join '; '); return }
        foreach ($property in $result.data.environment.PSObject.Properties) {
            [Environment]::SetEnvironmentVariable($property.Name, [string]$property.Value, 'Process')
        }
        return
    }
    & pwsh -NoProfile -File $selectedDriver @args
    $global:LASTEXITCODE = $LASTEXITCODE
}.GetNewClosure()
Set-Item -Path Function:global:dd -Value $dispatcher