#requires -Version 7.4
param([string]$Server = (Join-Path (Split-Path $PSScriptRoot) '.dd/mcp/server.ps1'), [switch]$ProtocolOnly)
$ErrorActionPreference = 'Stop'
$fixture = Join-Path ([IO.Path]::GetTempPath()) ('dd-mcp-' + [guid]::NewGuid().ToString('N'))
[IO.Directory]::CreateDirectory($fixture) | Out-Null
function Start-Client([switch]$Execution, [string]$Workspace = $fixture) {
    $process = [Diagnostics.Process]::new()
    $process.StartInfo = [Diagnostics.ProcessStartInfo]::new((Join-Path $PSHOME $(if ($IsWindows) { 'pwsh.exe' } else { 'pwsh' })))
    $process.StartInfo.UseShellExecute = $false
    $process.StartInfo.RedirectStandardInput = $true
    $process.StartInfo.RedirectStandardOutput = $true
    $process.StartInfo.RedirectStandardError = $true
    $process.StartInfo.StandardInputEncoding = [Text.UTF8Encoding]::new($false)
    $process.StartInfo.StandardOutputEncoding = [Text.UTF8Encoding]::new($false)
    foreach ($argument in @('-NoProfile','-NonInteractive','-File',$Server,'-Root',$Workspace)) { $process.StartInfo.ArgumentList.Add($argument) }
    if ($Execution) { $process.StartInfo.ArgumentList.Add('-AllowExecution') }
    $null = $process.Start()
    return @{ process = $process; errors = $process.StandardError.ReadToEndAsync(); sequence = 0; progress = 0; read = $process.StandardOutput.ReadLineAsync() }
}
function Send-Message($Client, $Message) { $Client.process.StandardInput.WriteLine(($Message | ConvertTo-Json -Depth 30 -Compress)); $Client.process.StandardInput.Flush() }
function Read-Message($Client, [int]$Timeout = 30) {
    if (-not $Client.read.Wait($Timeout * 1000)) { throw 'MCP response timed out.' }
    $line = $Client.read.GetAwaiter().GetResult()
    if ($null -eq $line) { throw "MCP closed stdout: $($Client.errors.GetAwaiter().GetResult())" }
    $Client.read = $Client.process.StandardOutput.ReadLineAsync()
    $message = $line | ConvertFrom-Json -AsHashtable
    if ($message.jsonrpc -cne '2.0') { throw "Non-protocol stdout: $line" }
    return $message
}
function Request($Client, [string]$Method, $Parameters = @{}, [int]$Timeout = 30) {
    $Client.sequence++
    Send-Message $Client @{ jsonrpc = '2.0'; id = $Client.sequence; method = $Method; params = $Parameters }
    do {
        $message = Read-Message $Client $Timeout
        if ($message.method -eq 'notifications/progress') { $Client.progress++; continue }
        if ($message.id -ne $Client.sequence) { throw 'Unexpected response ID.' }
    } while ($message.method)
    return $message
}
function Initialize-Client($Client, [string]$Version = '2025-06-18') {
    $result = Request $Client initialize @{ protocolVersion = $Version; capabilities = @{}; clientInfo = @{ name = 'dd-test'; version = '1' } }
    $expected = if ($Version -in @('2024-11-05','2025-03-26')) { $Version } else { '2025-06-18' }
    if ($result.result.protocolVersion -ne $expected -or -not $result.result.capabilities.tools) { throw 'MCP initialization failed.' }
    Send-Message $Client @{ jsonrpc = '2.0'; method = 'notifications/initialized' }
}
function Call-Tool($Client, [string]$Name, $Arguments = @{}, [bool]$ErrorExpected = $false, [int]$Timeout = 30) {
    $response = Request $Client 'tools/call' @{ name = $Name; arguments = $Arguments; _meta = @{ progressToken = 'native-progress' } } $Timeout
    if ($response.error -or [bool]$response.result.isError -ne $ErrorExpected) { throw "Unexpected $Name result: $($response | ConvertTo-Json -Depth 40 -Compress)" }
    return $response.result
}
function Wait-File($Client, [string]$Path) {
    $timer = [Diagnostics.Stopwatch]::StartNew()
    while (-not (Test-Path -LiteralPath $Path) -and $timer.Elapsed.TotalSeconds -lt 15) { $null = $Client.process.WaitForExit(50) }
    if (-not (Test-Path -LiteralPath $Path)) { throw "Timed out waiting for $Path" }
}
function Close-Client($Client) {
    $Client.process.StandardInput.Close()
    try {
        if (-not $Client.process.WaitForExit(10000)) { $Client.process.Kill($true); throw 'MCP did not exit after EOF.' }
        if ($Client.process.ExitCode) { throw "MCP failed: $($Client.errors.GetAwaiter().GetResult())" }
    } finally { $Client.process.Dispose() }
}
$client = Start-Client
try {
    if ((Request $client 'tools/list').error.code -ne -32600) { throw 'Uninitialized tool requests were accepted.' }
    Initialize-Client $client
    $listed = Request $client 'tools/list'
    if ($listed.result.tools.name -notcontains 'dd_help') { throw 'Missing dd_help.' }
    if ($listed.result.tools.Count -ne 12) { throw 'Tool catalog parity failed.' }
    $help = Request $client 'tools/call' @{ name = 'dd_help' }
    if (-not $help.result.structuredContent.ok) { throw "CLI help failed: $($help | ConvertTo-Json -Depth 20)" }
    $client.process.StandardInput.WriteLine('{broken')
    if ((Read-Message $client).error.code -ne -32700) { throw 'Malformed JSON did not return a parse error.' }
    if ((Request $client ping).error) { throw 'Malformed input corrupted the session.' }
    if ((Request $client unknown).error.code -ne -32601) { throw 'Unknown methods must return method-not-found.' }
    foreach ($name in @('dd_build','dd_test','dd_run','dd_launch','dd_command')) {
        $values = if ($name -eq 'dd_command') { @{ name = 'version' } } else { @{} }
        $blocked = Request $client 'tools/call' @{ name = $name; arguments = $values }
        if (-not $blocked.result.isError -or $blocked.result.content[0].text -notmatch 'execution is disabled') { throw "Missing execution gate for $name" }
    }
    $invalid = Request $client 'tools/call' @{ name = 'dd_build'; arguments = @{ jobs = '2' } }
    if ($invalid.error.code -ne -32602) { throw 'Typed input validation failed.' }
    $outside = Request $client 'tools/call' @{ name = 'dd_doctor'; arguments = @{ project = '..' } }
    if (-not $outside.result.isError -or $outside.result.content[0].text -notmatch 'outside') { throw 'Workspace traversal accepted.' }
    $unknown = Request $client 'tools/call' @{ name = 'dd_shell' }
    if ($unknown.error.code -ne -32602) { throw 'Unknown tool was accepted.' }
    $invalid = Request $client 'tools/call' @{ name = 'dd_init'; arguments = @{ type = 'cli'; name = 'app'; apply = 'true' } }
    if ($invalid.error.code -ne -32602) { throw 'A string authorized a write.' }
    $client.process.StandardInput.WriteLine('[]')
    if ((Read-Message $client).error.code -ne -32600) { throw 'A batch was accepted.' }
    Send-Message $client @{ jsonrpc = '2.0'; method = 'notifications/cancelled' }
    $client.process.StandardInput.Write('{"jsonrpc":"2.0","id":"fragmented","method":')
    $client.process.StandardInput.Flush()
    $client.process.StandardInput.WriteLine('"ping"}')
    if ((Read-Message $client).id -cne 'fragmented') { throw 'Fragmented message handling failed.' }
    $app = Join-Path $fixture 'app'
    [IO.Directory]::CreateDirectory($app) | Out-Null
    $null = Call-Tool $client dd_init @{ project = 'app'; type = 'cli'; name = 'mcp-app' }
    if (Test-Path (Join-Path $app 'dd.psd1')) { throw 'Default preview wrote a project.' }
    $null = Call-Tool $client dd_init @{ project = 'app'; type = 'cli'; name = 'mcp-app'; apply = $true }
    $catalog = Call-Tool $client dd_dependencies @{ project = 'app'; operation = 'available' }
    if (-not $catalog.structuredContent.data.dependencies.'spike-db') { throw 'Dependency catalog was not available.' }
    $null = Call-Tool $client dd_dependencies @{ project = 'app'; operation = 'install'; name = 'archive'; url = 'https://example.com/source.zip'; sha256 = 'a' * 64; method = 'application'; apply = $true }
    $null = Call-Tool $client dd_dependencies @{ project = 'app'; operation = 'update'; name = 'archive'; url = 'https://example.com/next.zip'; sha256 = 'b' * 64; apply = $true }
    $list = Call-Tool $client dd_dependencies @{ project = 'app'; operation = 'list' }
    if ($list.structuredContent.data.dependencies[0].sha256 -ne ('b' * 64)) { throw 'Archive mutation parity failed.' }
    $commands = Call-Tool $client dd_commands @{ project = 'app' }
    if ($commands.structuredContent.data.commands.Count) { throw 'Fresh app has unexpected commands.' }
    $targets = Call-Tool $client dd_targets @{ project = 'app' }
    if ($targets.structuredContent.data.targets[0].id -ne 'app') { throw 'Target discovery parity failed.' }
    $outsideFolder = Join-Path ([IO.Path]::GetTempPath()) ('dd-mcp-outside-' + [guid]::NewGuid().ToString('N'))
    [IO.Directory]::CreateDirectory($outsideFolder) | Out-Null
    $link = Join-Path $fixture 'linked'
    $null = New-Item -ItemType $(if ($IsWindows) { 'Junction' } else { 'SymbolicLink' }) -Path $link -Target $outsideFolder
    $blocked = Call-Tool $client dd_doctor @{ project = 'linked' } $true
    if ($blocked.content[0].text -notmatch 'linked|outside') { throw 'Linked workspace escape was accepted.' }
    if ($IsLinux) {
        $caseSibling = Join-Path (Split-Path $fixture) (Split-Path $fixture -Leaf).ToUpperInvariant()
        [IO.Directory]::CreateDirectory($caseSibling) | Out-Null
        $blocked = Call-Tool $client dd_doctor @{ project = $caseSibling } $true
        if ($blocked.content[0].text -notmatch 'outside') { throw 'Case-sensitive workspace boundary was bypassed.' }
    }
} finally { Close-Client $client }
$manifestPath = Join-Path $app 'dd.psd1'
$parentProject = Join-Path $fixture 'parent-project'
$boundedRoot = Join-Path $parentProject 'workspace'
$subdirectory = Join-Path $boundedRoot 'child'
[IO.Directory]::CreateDirectory($subdirectory) | Out-Null
$parentManifest = [IO.File]::ReadAllText($manifestPath).Replace('schema = 1', "schema = 1`nrequirements = @{ tools = @{ cmake = @{ minimum = '999.0' } } }")
[IO.File]::WriteAllText((Join-Path $parentProject 'dd.psd1'), $parentManifest)
$client = Start-Client -Workspace $boundedRoot
try {
    Initialize-Client $client
    foreach ($project in @('.', 'child')) {
        $plan = Call-Tool $client dd_toolchain_plan @{ project = $project }
        if ($plan.structuredContent.data.requirements.tools.cmake.minimum -eq '999.0') { throw 'MCP discovered a manifest outside its root.' }
        $doctor = Request $client 'tools/call' @{ name = 'dd_doctor'; arguments = @{ project = $project } }
        if (-not $doctor.result.structuredContent.data.requirements -or $doctor.result.structuredContent.data.requirements.tools.cmake.minimum -eq '999.0') { throw 'MCP doctor inspected a parent outside its root.' }
        $null = Call-Tool $client dd_dependencies @{ project = $project; operation = 'available' }
    }
} finally { Close-Client $client }
$client = Start-Client -Workspace $parentProject
try {
    Initialize-Client $client
    $plan = Call-Tool $client dd_toolchain_plan @{ project = 'workspace/child' }
    if ($plan.structuredContent.data.requirements.tools.cmake.minimum -ne '999.0') { throw 'MCP stopped discovering ancestors inside its allowed root.' }
} finally { Close-Client $client }
$declaration = @'
commands = @{
    echo = @{ description = 'Typed fixture'; script = 'tools/echo.ps1'; effects = 'write'; 'supports-dry-run' = $true; parameters = @{ text = @{ type = 'string'; required = $true }; count = @{ type = 'integer'; default = 1 } } }
    hold = @{ description = 'Cancellation fixture'; script = 'tools/hold.ps1'; effects = 'read' }
}
'@
[IO.Directory]::CreateDirectory((Join-Path $app 'tools')) | Out-Null
Copy-Item (Join-Path $PSScriptRoot 'fixtures/project-command.ps1') (Join-Path $app 'tools/echo.ps1')
Copy-Item (Join-Path $PSScriptRoot 'fixtures/mcp-hold.ps1') (Join-Path $app 'tools/hold.ps1')
[IO.File]::WriteAllText($manifestPath, [IO.File]::ReadAllText($manifestPath).Replace('schema = 1', "schema = 1`n$declaration"))
$client = Start-Client -Execution
try {
    Initialize-Client $client
    $preview = Call-Tool $client dd_command @{ project = 'app'; name = 'echo'; parameters = @{ text = '--quoted "text"; $var https://example.com'; count = -2 } }
    if ($preview.structuredContent.data.result.parameters.text -cne '--quoted "text"; $var https://example.com' -or $preview.structuredContent.data.result.parameters.count -ne -2) { throw 'Custom parameter tokens changed.' }
    if (Test-Path (Join-Path $app 'request.json')) { throw 'Preview applied the custom command.' }
    $unicode = 'https://example.com/' + [char]0x00e9 + [char]0x4e2d + "`nline two"
    $preview = Call-Tool $client dd_command @{ project = 'app'; name = 'echo'; parameters = @{ text = $unicode } }
    if ($preview.structuredContent.data.result.parameters.text -cne $unicode) { throw 'UTF-8 or embedded newlines changed.' }
    $null = Call-Tool $client dd_command @{ project = 'app'; name = 'echo'; dryRun = $false; parameters = @{ text = 'unconfirmed' } } $true
    $null = Call-Tool $client dd_command @{ project = 'app'; name = 'echo'; parameters = @{ text = 'bad type'; count = '2' } } $true
    $null = Call-Tool $client dd_command @{ project = 'app'; name = 'toolchain'; dryRun = $false; apply = $true } $true
    $applied = Call-Tool $client dd_command @{ project = 'app'; name = 'echo'; dryRun = $false; apply = $true; parameters = @{ text = '' } }
    if ($applied.structuredContent.data.result.parameters.text -cne '') { throw 'Empty string argument changed.' }
    $ready = Join-Path $app 'hold.json'
    Send-Message $client @{ jsonrpc = '2.0'; id = 'hold'; method = 'tools/call'; params = @{ name = 'dd_command'; arguments = @{ project = 'app'; name = 'hold'; dryRun = $false } } }
    Wait-File $client $ready
    $held = Get-Content $ready -Raw | ConvertFrom-Json
    Send-Message $client @{ jsonrpc = '2.0'; id = 'queued'; method = 'tools/call'; params = @{ name = 'dd_command'; arguments = @{ project = 'app'; name = 'echo'; dryRun = $false; apply = $true; parameters = @{ text = 'must not run' } } } }
    Send-Message $client @{ jsonrpc = '2.0'; method = 'notifications/cancelled'; params = @{ requestId = 'queued' } }
    if ((Request $client ping).error) { throw 'Ping blocked behind execution.' }
    Send-Message $client @{ jsonrpc = '2.0'; method = 'notifications/cancelled'; params = @{ requestId = 'hold' } }
    $null = Call-Tool $client dd_help
    foreach ($processId in @($held.parent, $held.child)) {
        $process = Get-Process -Id $processId -ErrorAction SilentlyContinue
        if ($process -and -not $process.HasExited) {
            $zombie = $IsLinux -and (Get-Content "/proc/$processId/status" -Raw -ErrorAction SilentlyContinue) -match '(?m)^State:\s+Z'
            if (-not $zombie) { $process.Kill($true); throw 'Cancellation left project code running.' }
        }
    }
    if ((Get-Content (Join-Path $app 'request.json') -Raw | ConvertFrom-Json).parameters.text -cne '') { throw 'Queued cancellation still executed a mutation.' }
    if (-not $ProtocolOnly) {
        $doctor = Call-Tool $client dd_doctor @{ project = 'app' }
        $plan = Call-Tool $client dd_toolchain_plan @{ project = 'app' }
        if (-not $doctor.structuredContent.data.ready -or -not $plan.structuredContent.data.ready) { throw 'Native prerequisite inspection did not report readiness.' }
        $null = Call-Tool $client dd_build @{ project = 'app'; configuration = 'debug'; apps = @('app'); jobs = 2 } $false 180
        $tested = Call-Tool $client dd_test @{ project = 'app'; apps = @('app'); name = '^app_unit$' } $false 180
        if (@($tested.structuredContent.data.results | Where-Object status -eq 'tested').Count -ne 2 -or $client.progress -eq 0) { throw 'Native filtering or progress failed.' }
        $run = Call-Tool $client dd_run @{ project = 'app'; target = 'app'; args = @('--help'); timeout = 10 } $false 120
        if ($run.structuredContent.data.stdout -notmatch 'Usage: mcp-app') { throw 'Run argument forwarding failed.' }
        $run = Call-Tool $client dd_run @{ project = 'app'; target = 'app'; args = @('unknown'); timeout = 10 } $true 120
        if ($run.structuredContent.exitCode -ne 2) { throw 'Run lost the child exit code.' }
        [IO.File]::WriteAllText((Join-Path $app 'src/main.cpp'), "#include <chrono>`n#include <thread>`nint main() { std::this_thread::sleep_for(std::chrono::minutes(2)); }`n")
        $launched = Call-Tool $client dd_launch @{ project = 'app'; target = 'app' } $false 120
        $applicationId = $launched.structuredContent.data.pid
        if ($launched.structuredContent.data.status -ne 'started') { throw 'Launch did not report started.' }
    }
} finally {
    Close-Client $client
    if ($applicationId) {
        $application = Get-Process -Id $applicationId -ErrorAction Stop
        try { if ($application.HasExited) { throw 'Application did not survive server exit.' }; $application.Kill($true); $application.WaitForExit() } finally { $application.Dispose() }
    }
}
foreach ($version in @('2024-11-05','2099-01-01')) {
    $client = Start-Client
    try {
        Initialize-Client $client $version
        $result = Call-Tool $client dd_help
        if ($version -eq '2024-11-05' -and $result.Contains('structuredContent')) { throw 'Older protocol received an unnegotiated structured result.' }
    } finally { Close-Client $client }
}
[IO.File]::Move($ready, "$ready.previous")
$client = Start-Client -Execution
try {
    Initialize-Client $client
    Send-Message $client @{ jsonrpc = '2.0'; id = 'eof-hold'; method = 'tools/call'; params = @{ name = 'dd_command'; arguments = @{ project = 'app'; name = 'hold'; dryRun = $false } } }
    Wait-File $client $ready
    $held = Get-Content $ready -Raw | ConvertFrom-Json
} finally { Close-Client $client }
foreach ($processId in @($held.parent, $held.child)) {
    $process = Get-Process -Id $processId -ErrorAction SilentlyContinue
    if ($process -and -not $process.HasExited) {
        $zombie = $IsLinux -and (Get-Content "/proc/$processId/status" -Raw -ErrorAction SilentlyContinue) -match '(?m)^State:\s+Z'
        if (-not $zombie) { $process.Kill($true); throw 'EOF left project code running.' }
    }
}
$switchableRoot = Join-Path $fixture 'switchable-root'
[IO.Directory]::CreateDirectory($switchableRoot) | Out-Null
$client = Start-Client -Workspace $switchableRoot
try {
    Initialize-Client $client
    Move-Item -LiteralPath $switchableRoot -Destination "$switchableRoot.original"
    $null = New-Item -ItemType $(if ($IsWindows) { 'Junction' } else { 'SymbolicLink' }) -Path $switchableRoot -Target $outsideFolder
    $blocked = Call-Tool $client dd_help @{} $true
    if ($blocked.content[0].text -notmatch 'linked') { throw 'Root replacement bypassed workspace checks.' }
} finally { Close-Client $client }
Write-Host 'PASS: PowerShell-only MCP protocol, all tools, typed commands, workspace boundaries, cancellation and requested native progress/launch checks.'
exit 0