# Adopting dd in an existing application

Keep application behavior in CMake, presets and project-owned scripts. Do not fork
the shared driver or run `init` in a populated repository. `adopt --dry-run` inspects
an existing project without rewriting it. Vendor the reviewed runtime and add a
data-only `dd.psd1`; retain the application's target names and output paths.

## Dependency ownership

Choose one of these explicitly:

- Default `dependencies = @{ owner = 'dd' }`: pins live in
  `cmake/dd-dependencies.json`. Missing or invalid declarations remain errors.
- `dependencies = @{ owner = 'application' }`: existing CMake owns pins, fetching
  and recipes. No dd dependency JSON is needed. `dep list` reports unknown inventory
  (`inventoryKnown: false`), not an empty known list. Named mutations are rejected.

With dd-owned pins, `method: "application"` disables automatic integration for that
entry. The recipe consumes only the acquisition arguments:

```cmake
include("${CMAKE_CURRENT_SOURCE_DIR}/.dd/dependencies.cmake")
dd_dependency_arguments("${CMAKE_CURRENT_SOURCE_DIR}/cmake/dd-dependencies.json" codec codec_acquisition)
FetchContent_Declare(codec ${codec_acquisition} SOURCE_SUBDIR build/cmake)
FetchContent_MakeAvailable(codec)
```

The same arguments work with `ExternalProject_Add`. Set options, patch commands,
source subdirectories, imported targets and byproducts in the recipe, not JSON.
The application recipe owns source/cache preservation as well as build integration.
Generic dd recipes remain available for standard CMake projects.

Git entries have a full `commit`. Archive entries instead have an HTTPS `url` and
64-character lowercase `sha256`. Supply a reviewed upstream checksum, not a checksum
learned from an untrusted download. CMake verifies `URL_HASH` before extraction.

```powershell
dd dep install codec --url https://example.org/codec-1.0.tar.gz --sha256 <reviewed-sha256> --method application
dd dep update codec --url https://example.org/codec-1.1.tar.gz --sha256 <reviewed-sha256>
```

## Phase presets and cleanup

Each configuration accepts either one name shared across phases or separate names:

```powershell
build = @{
    'x64-windows' = @{
        debug = @{ configure = 'native-debug'; build = 'compile-debug'; test = 'check-debug' }
        release = @{ configure = 'native-release'; build = 'compile-release'; test = 'check-release' }
        ide = 'visual-studio'
    }
}
```

Build and test presets must reference their mapped configure preset. Included and
inherited presets are resolved, with native CMake validating conditions and behavior.
Supported path macros include source/file directories, preset name, host name and
environment values. Presets and build directories must stay inside the project;
unknown path macros and linked paths fail rather than being guessed.

After configure, CMake File API cache metadata verifies the source and binary paths.
dd records these plus preset and manifest hashes in ignored `.dd/state/`. Clean never
executes CMake to discover a directory. Missing/stale records, changed path expansion,
foreign caches, tracked files, linked paths or edited/unrecognized source caches block
cleanup. Reconfigure intentionally after changing presets. Shared trees require
`clean both`, including Ninja Multi-Config and Visual Studio trees; a single-config
request never silently removes other configurations. `--yes` authorizes deletion only
after these checks. Retain local work outside disposable build trees.

`ide` configures only the declared Windows IDE preset and requires a Visual Studio
generator. It does not invent a build directory or alter the application's generator.
The scaffold IDE preset lets CMake choose the installed default generator; existing
applications should declare the Visual Studio generator they support.

## Native requirements

```powershell
requirements = @{
    tools = @{
        cmake = @{ minimum = '3.28.0' }
        python = @{ minimum = '3.11.0' }
        gdb = @{ minimum = '12.0'; optional = $true; platforms = @('x64-linux') }
    }
    msvc = @{
        minimum = '17.0'
        components = @('Microsoft.VisualStudio.Component.VC.ATL')
    }
}
```

`msvc.minimum` means Visual Studio version, not the `cl` version. Components are
unioned with the required x64 C++ tools. Tool requirements use built-in providers,
not executable project probes. Required defaults cannot be weakened. Optional tools
warn without blocking builds or joining an install plan. Required tools are checked
by build, doctor, toolchain planning and post-install verification. Providers use
official OS packages and can still fail to satisfy a newer minimum; that is an error,
not readiness. No test or MCP tool installs packages, changes profiles or elevates.

## Multiple apps and execution

Give each target an ID, actual `cmake-target`, explicit Debug/Release paths and a
`test-label` if it should support application-scoped tests. Output names need not match
IDs. `project.default-target` handles default run/launch selection.

```powershell
dd build --app viewer,editor
dd test --app viewer --label smoke --name startup
dd run viewer --timeout 30 -- document.jpg
dd launch viewer -- document.jpg
```

Test labels for selected apps are unioned, then intersected with explicit label/name
filters. Tests build each preset's default targets to include separate test binaries.
Both configurations remain the default; zero selected tests is an error. Explicit
CTest filters omit the separate GUI window smoke pass. Failure results include names,
durations, excerpts and log paths. Configure/build/test progress and five-second
heartbeats use stderr; JSON stdout remains one envelope. MCP forwards progress when
the client requests it with a progress token.

`run` waits, captures output, and enforces its timeout. `launch` starts a detached
Release process with null stdin and file-backed stdout/stderr. It returns PID,
timestamp, executable and log paths and survives CLI/MCP exit. This reports process
creation, not application readiness. The user owns its lifetime; dd does not later
terminate it. Linux launch requires `setsid` and `nohup`. MCP launch requires explicit
`-AllowExecution`, as do builds, tests and custom scripts. The MCP adapter is pure
PowerShell; see [mcp.md](mcp.md) for configuration and protocol details.

## Regression coverage

`tests/adoption.ps1` uses an isolated existing-project-shaped fixture with nonstandard
output paths, phase-specific presets, application ownership, filtered/failed CTest
runs and persistent launch. `tests/presets.ps1` covers include/inheritance, environment
invalidation and shared-tree refusal. Archive, prerequisite and MCP tests cover their
respective contracts. These tests do not modify or claim to build a user's ImageWalker
checkout. Real application recipes and native package installation still need their
own integration validation.