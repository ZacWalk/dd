#requires -Version 7.4
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot
. (Join-Path $root '.dd/core.ps1')
. (Join-Path $root '.dd/dependencies.ps1')
$fixture = Join-Path ([IO.Path]::GetTempPath()) ('dd-archives-' + [guid]::NewGuid().ToString('N'))
[IO.Directory]::CreateDirectory((Join-Path $fixture 'cmake')) | Out-Null
$path = Join-Path $fixture 'cmake/dd-dependencies.json'
[IO.File]::WriteAllText($path, '{"schema":1,"dependencies":{}}')
$hash = 'a' * 64
$declared = Install-DDDependency $fixture 'archive' 'https://example.com/source.tar.gz' $null $false 'application' $hash
$manifest = Read-DDDependencyManifest $fixture
if ($manifest.dependencies.archive.sha256 -ne $hash -or $manifest.dependencies.archive.method -ne 'application') { throw 'Archive pin was not retained.' }
$null = Update-DDDependency $fixture 'archive' $null $false 'https://example.com/next.tar.gz' ('b' * 64)
$helper = (Join-Path $root '.dd/dependencies.cmake').Replace('\','/')
$json = $path.Replace('\','/')
[IO.File]::WriteAllText((Join-Path $fixture 'CMakeLists.txt'), "cmake_minimum_required(VERSION 3.24)`nproject(archive_recipe NONE)`ninclude(`"$helper`")`ndd_dependency_arguments(`"$json`" archive arguments)`nfile(WRITE `"`${CMAKE_BINARY_DIR}/arguments.txt`" `"`${arguments}`")`ndd_load_dependencies(`"$json`")`n")
& cmake -S $fixture -B (Join-Path $fixture 'out')
if ($LASTEXITCODE) { throw 'Recipe argument export failed.' }
$arguments = [IO.File]::ReadAllText((Join-Path $fixture 'out/arguments.txt'))
if (-not $arguments.Contains('URL_HASH;SHA256=' + ('b' * 64)) -or -not $arguments.Contains('TLS_VERIFY;TRUE')) { throw 'Archive acquisition args omit verification.' }
$content = Join-Path $fixture 'content'
[IO.Directory]::CreateDirectory($content) | Out-Null
[IO.File]::WriteAllText((Join-Path $content 'CMakeLists.txt'), "cmake_minimum_required(VERSION 3.24)`nproject(archive_content NONE)`n")
$archive = Join-Path $fixture 'source.zip'
Compress-Archive -Path (Join-Path $content '*') -DestinationPath $archive
$hash = (Get-FileHash $archive -Algorithm SHA256).Hash.ToLowerInvariant()
$null = Update-DDDependency $fixture 'archive' $null $false 'https://example.com/source.zip' $hash
$cmake = @'
cmake_minimum_required(VERSION 3.24)
project(archive_recipe NONE)
include("@HELPER@")
dd_dependency_arguments("@JSON@" archive arguments)
list(REMOVE_AT arguments 1)
list(INSERT arguments 1 "@ARCHIVE@")
FetchContent_Declare(payload ${arguments})
FetchContent_MakeAvailable(payload)
'@
[IO.File]::WriteAllText((Join-Path $fixture 'CMakeLists.txt'), $cmake.Replace('@HELPER@',$helper).Replace('@JSON@',$json).Replace('@ARCHIVE@',$archive.Replace('\','/')))
$null = Invoke-DDProcess cmake @('-S',$fixture,'-B',(Join-Path $fixture 'verified')) $fixture
[IO.File]::AppendAllText($archive, 'corruption')
$rejected = Invoke-DDProcess cmake @('-S',$fixture,'-B',(Join-Path $fixture 'corrupt')) $fixture -AllowFailure
if (-not $rejected.exitCode -or ($rejected.stdout + $rejected.stderr) -notmatch 'hash|SHA256') { throw 'Corrupt archive passed verification.' }
$null = Invoke-DDProcess cmake @("-DDD_ARCHIVE_SOURCE=$content",'-DDD_ARCHIVE_INITIALIZE=ON','-P',$helper) $fixture
$null = Invoke-DDProcess cmake @("-DDD_ARCHIVE_SOURCE=$content",'-P',$helper) $fixture
[IO.File]::WriteAllText((Join-Path $content 'local-work.txt'), 'keep')
$rejected = Invoke-DDProcess cmake @("-DDD_ARCHIVE_SOURCE=$content",'-P',$helper) $fixture -AllowFailure
if (-not $rejected.exitCode -or $rejected.stderr -notmatch 'Preserving edited archive') { throw 'Edited extracted source was accepted.' }
Write-Host 'PASS: archive pins, recipe arguments, checksum rejection and extracted-source preservation.'
exit 0