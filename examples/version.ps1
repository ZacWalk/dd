#requires -Version 7.4
$ErrorActionPreference = 'Stop'
try {
    $request = [Console]::In.ReadLine() | ConvertFrom-Json -AsHashtable -ErrorAction Stop
    if ($request.schema -ne 1 -or $request.parameters.part -notin @('major', 'minor', 'patch')) { throw 'Expected a schema 1 version request with a valid part.' }
    $path = Join-Path $request.projectRoot 'VERSION'
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw 'Create a VERSION file containing MAJOR.MINOR.PATCH first.' }
    if ((Get-Item -LiteralPath $path).Attributes -band [IO.FileAttributes]::ReparsePoint) { throw 'VERSION must not be a linked file.' }
    $original = [IO.File]::ReadAllText($path)
    $current = $original.Trim()
    if ($current -notmatch '^(0|[1-9][0-9]{0,8})\.(0|[1-9][0-9]{0,8})\.(0|[1-9][0-9]{0,8})$') { throw 'VERSION must contain three nonnegative integers (at most nine digits each).' }
    $major = [long]$Matches[1]
    $minor = [long]$Matches[2]
    $patch = [long]$Matches[3]
    switch ($request.parameters.part) {
        'major' { $major++; $minor = 0; $patch = 0 }
        'minor' { $minor++; $patch = 0 }
        'patch' { $patch++ }
    }
    if ($major -gt 999999999 -or $minor -gt 999999999 -or $patch -gt 999999999) { throw 'Version component exceeds nine digits.' }
    $next = "$major.$minor.$patch"
    if (-not $request.dryRun) {
        if ([IO.File]::ReadAllText($path) -cne $original) { throw 'VERSION changed concurrently; retry.' }
        [IO.File]::WriteAllText($path, $next + "`n")
    }
    $response = @{ schema = 1; data = @{ previous = $current; next = $next }; files = @('VERSION') }
    [Console]::Out.WriteLine(($response | ConvertTo-Json -Compress))
}
catch {
    [Console]::Error.WriteLine($_.Exception.Message)
    exit 1
}