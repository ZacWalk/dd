# dd build system 0.1.0

This is the current executable contract. The other design documents preserve the
broader design discussion and legacy-project migration considerations.

## Installation and distribution

dd's source, bootstrap, release archives, templates and catalog are hosted in
[ZacWalk/dd](https://github.com/ZacWalk/dd). No runtime download uses dynamicdispatch.org.
Native compiler packages use official winget/Ubuntu repositories. PowerShell 7.4+
and Git must already be available; missing bootstrap prerequisites produce instructions.

Build a release locally:

```powershell
pwsh -NoProfile -File ./tools/prepare.ps1
pwsh -NoProfile -File ./tools/package.ps1
```

The preparation step validates source files and the native `dd.psd1` template offline.
The runtime uses `Import-PowerShellDataFile`; there is no third-party manifest parser,
downloaded parser source, DLL or on-host compilation. Preparation is a developer check,
not a prerequisite for running the CLI. MCP also runs directly with PowerShell 7.4+;
there are no third-party runtime packages or adapter compilation steps.

`dist/dd.zip` contains a file hash manifest, the runtime, templates, optional
MCP PowerShell scripts. `dist/dd.zip.sha256` hashes the archive. Packaging refuses to
overwrite an existing archive; move it aside before creating another one.

After a release is published, an inspected bootstrap can be invoked as:

```powershell
./bootstrap.ps1 -Version v0.1.0 -RegisterProfile
```

The intended convenience URL is
`https://raw.githubusercontent.com/ZacWalk/dd/main/bootstrap.ps1`; a tagged version is
preferable for reproducibility. `irm <url> | iex` trusts and executes the initial
download. The installer then verifies GitHub's release checksum and per-file hashes,
rejects unsafe archive paths and activates a side-by-side release. These checks detect
corruption, not compromise of the GitHub publisher; detached signature/key management
is not implemented. No release is published automatically by local development.

For offline installation or testing, provide `-ArchivePath` and `-Sha256`. Use
`-InstallRoot` and `-ProfilePath` to target isolated locations. `-NoProfile` installs
without changing shell configuration. Registration preserves other profile content,
backs up changed profiles, detects conflicting dd functions and is repeatable.

On Linux, run bootstrap with native `pwsh`. Profile integration applies to PowerShell,
not Bash; opting in shadows the Unix dd utility only in that PowerShell session.
Nothing replaces `/usr/bin/dd`. Bare-shell installation still requires PowerShell
to be installed first. No automatic sudo, UAC or execution-policy changes occur.

## Creating and building apps

After bootstrap, create an empty directory, enter it and run `dd init`. Interactive
mode asks for GUI or CLI; non-interactive mode requires `--type`. GUI is Windows-only
and automatically declares the catalog's pinned platform-h FetchContent dependency. CLI has no default
source dependencies. Linux GUI requests fail before writing files.

```powershell
dd init --type cli --name my-app --dry-run
dd init --type cli --name my-app --non-interactive
dd toolchain --dry-run
dd doctor --json
dd test --json
dd run app -- --help
```

If the launcher is not installed, use `pwsh -NoProfile -File /path/to/dd.ps1` in place
of `dd`. `--project <directory>` explicitly selects an existing directory. `init`
always uses that directory, never an ancestor; nested Git repositories and populated
destinations are refused. It does not install a compiler, commit or push.

The launcher prefers a nearest vendored driver for project commands and the installed
driver for `init`. Executing repository drivers or CMake means trusting project code.
No directory-jump fallback exists. `dd env` imports into the calling PowerShell only
through the installed profile function; direct child-process invocation returns the
selected environment values in JSON instead of claiming to modify its parent.

Scaffolds use native x64 MSVC or GCC, CMake 3.24+, Ninja, C++20 and isolated
`build/<platform>/<configuration>` trees. Existing apps use their declared presets
and binary directories. Configure runs on each build. Both
configurations build by default. Raw configure/build/test/run logs are retained in
the host temp directory; summaries group MSVC diagnostic codes and GCC warning options.
Read-only Git and environment operations do not create logs. Long tool calls have
timeouts and process-tree cleanup. Raw stdout/stderr are captured separately, so their
combined log does not promise exact cross-stream ordering. Configure/build/test output
streams to stderr with five-second heartbeats; MCP supports progress notifications.

`test` runs CTest in both configurations with `--no-tests=error`; GUI targets also
get bounded window smoke tests, settled-title reporting and crash-file checks. The
generated GUI app does not yet install an application crash reporter, so absence of
a crash file alone is not proof of fault-free execution. `run` accepts an explicit
target ID, otherwise uses `project.default-target` or the sole compatible target.
Ambiguous interactive runs prompt; automation fails with available choices. It
forwards arguments after `--`, defaults to a 120-second timeout and returns its exit
code. `--timeout` can explicitly change that bound.

`launch` instead detaches a Release process and returns its PID, timestamp, executable
and file-backed stdout/stderr paths. It survives the driver and MCP server; there is
no implicit launch timeout. `build --app ID,ID` scopes build targets. `test --app`,
`--label`, and `--name` filter CTest while still building both preset defaults, including
test executable prerequisites. Empty selections fail. JSON failures expose
`data.testFailures` with names, durations and bounded excerpts plus retained log paths.

## VS Code and CI

Each generated app includes `.vscode/launch.json`, `tasks.json`, `settings.json`,
`c_cpp_properties.json` and `extensions.json` alongside its MCP configuration.
The Microsoft C/C++ extension is recommended, not silently installed. F5 builds Debug
through `pwsh -NoProfile -File .../dd.ps1 build debug` as a process task and launches
the binary recorded by the Debug target path. GUI projects have only the Windows
debugger configuration; CLI projects include Windows/MSVC and Linux/GDB configurations,
with the native host first. Select the matching one when moving a clone to another OS.
On WSL open the project in a remote WSL window and install GDB and the C/C++ extension
there. Debugger/extension installation is separate from native compiler provisioning.

CMake and both IntelliSense configurations use C++20 and C17. The native Debug build
exports `compile_commands.json` so IntelliSense can use the actual compiler flags and
includes. If output paths change, update both the manifest and launch configuration.

The generated `.github/workflows/ci.yml` validates dependency declarations, checks native
tools, builds both configurations and runs tests on Windows/Ubuntu for CLI or Windows
only for GUI. It uses read-only repository permissions and does not persist checkout
credentials. The generated README includes a workflow badge using `OWNER/<app-name>`;
replace that with the actual repository slug after publishing. `init` cannot know the
owner of a remote repository that does not exist yet and does not create one.

## Manifest

`dd.psd1` contains one PowerShell data hashtable with `schema = 1`. The generated example is in
[../.dd/templates/common/dd.psd1](../.dd/templates/common/dd.psd1), and the model schema
is in [../schema/dd.schema.json](../schema/dd.schema.json).

- `project = @{ ... }`: `name`, `type` (`gui` or `cli`), optional `default-target` ID.
- `build = @{ 'x64-windows' = @{ ... }; 'x64-linux' = @{ ... } }`: native preset tables,
  each containing `debug` and `release` names or `{ configure, build, test }` mappings,
  plus optional `ide` configure preset. Only the current host is required.
- `targets = @( @{ ... } )`: an array of target hashtables, each with a unique `id`,
  `kind`, `cmake-target`, `debug-path`, `release-path`, optional `platforms` and `test-label`.
- `dependencies = @{ owner = 'dd' | 'application' }`: optional explicit acquisition owner.
- `requirements`: optional built-in tool minima, optional tools and Visual Studio components.
  See [adoption.md](adoption.md) for syntax, shared-tree safety and ownership limitations.
- `commands = @{ ... }`: optional project command declarations described in
  [extensions.md](extensions.md). Scripts live in the project, not the driver.
- Paths support `{platform}` and `{exe}` substitutions and must stay inside the project.

Comments are supported. Quote hyphenated keys and use single-quoted strings for
literal paths. The loader is data-only: dd never dot-sources or evaluates the manifest.
Executable expressions, method calls, duplicate keys and unsupported fields fail validation before
CMake runs. JSON Schema describes the loaded data model; the file itself is not JSON.

Earlier experimental projects with `dd.toml` must convert their settings to a
`dd.psd1` hashtable; a filename-only rename is not sufficient. The driver detects a
TOML-only project and reports migration guidance rather than searching past it for
an ancestor project. No automatic rewrite of existing projects is performed. The
catalog, CMake presets, MCP configuration and CLI `--json` results remain JSON.

CMake owns linking, compiler settings and CTest definitions. Source dependency URLs,
methods and pins live in `cmake/dd-dependencies.json`, not PSD1. Existing ImageWalker test patterns,
arbitrary cache variables and output publishing rules are not imported automatically.

## Dependency operations

`dep list`, `dep list --available`, `dep install [name]`, custom
`dep install NAME --git URL --ref REF --method fetchcontent|externalproject`, and
`dep update NAME --ref REF` are implemented. FetchContent is the default method.
Mutations support `--dry-run`. Direct URLs must be HTTPS or ssh://, with no embedded
passwords; no interactive Git credential prompts or executable transports are enabled.

`install` records or verifies declarations; it does not download or run CMake. An
explicit hash is stored directly; tags/branches are resolved once with `git ls-remote`.
The single JSON file is atomically replaced after validating its existing content.
All Git staging, local source checkouts and unrelated entries remain unchanged.
`list` and `doctor` report `declared`, not a claim that sources were built.

The generated CMake includes FetchContent, ExternalProject and `.dd/dependencies.cmake`.
The helper reads the JSON natively and uses full `GIT_TAG` pins. FetchContent exposes
upstream targets or populated sources during configure; ExternalProject creates
`dd-dep-NAME`, builds separately and installs under a private prefix. External outputs
still need an application-owned imported target/byproduct/linking recipe as appropriate.
See [dependencies.md](dependencies.md) for exported source/build/install variables.

Caches live under each build tree's `_deps/`, with revision-specific sources. Changing
a pin selects a new cache, preserving old checkouts. Modified/mismatched source,
linked paths and unsupported overrides are refused. Libraries that modify their own
tracked source require a reviewed custom recipe; safety is not silently relaxed.
Recursive repository fetching is disabled. Application-owned mode neither inspects
nor modifies existing dependency checkouts. Archive URLs use SHA-256 verification;
`method: "application"` exports acquisition arguments without running a generic recipe.

Ref-resolution failures leave declarations unchanged. Download/build failures can
leave partial CMake caches, reported through retained logs; there is no destructive
automatic rollback. Configure and build can fetch and execute upstream code, so MCP's
existing `-AllowExecution` requirement remains essential.

## Agent and MCP interface

Every CLI command accepts `--json`; stdout then contains one versioned result:

```json
{"schema":1,"version":"0.1.0","ok":true,"exitCode":0,"data":{},"errors":[],"logs":[]}
```

Exit codes are `0` success, `1` execution failure, `2` invalid request, `3` missing
prerequisites, `4` environment setup failure, and `5` dependency failure/conflict.
`run` and custom project commands propagate their child process exit codes. JSON, CI and redirected input disable
interactive prompts. Use structured data and log paths rather than parsing display text.

Both templates generate `AGENTS.md` and `.vscode/mcp.json`. The MCP configuration is
independent per app and points to that app's `.dd/mcp/server.ps1`; no global server is
registered. VS Code's own trust/enablement prompt still applies. Ordinary CLI usage
does not require a running MCP server. Both interfaces use the existing PowerShell runtime.

The optional adapter implements MCP stdio using built-in PowerShell and .NET APIs.
Available tools:
`dd_help`, `dd_doctor`, `dd_init`, `dd_dependencies`, `dd_build`, `dd_test`, `dd_run`, `dd_launch`,
`dd_toolchain_plan`, `dd_commands`, `dd_command`, and `dd_targets`. Declaration mutation
tools default to preview and require `apply: true`. `dd_command` defaults to a script-backed
dry-run; writes require `dryRun: false, apply: true`. Build/test/run/launch and all custom
script execution require `-AllowExecution` in the server's launch args.
The server resolves paths inside its configured root, serializes operations and
handles cancellation. It exposes neither arbitrary shell execution nor compiler
installation, profile editing, cleanup or commit/push tools.
Protocol versions, queue/output bounds, lifecycle and migration are documented in
[mcp.md](mcp.md). The maintained adapter has no package-manager or SDK dependency.

Custom commands use an isolated `pwsh -NoProfile -NonInteractive` child process with
JSON requests over stdin and validated JSON responses on stdout. Descriptions and
typed parameter/default/choice metadata are discoverable without requiring native
build support. Unknown commands do not fall through to shell execution. Effects and
dry-run support are declarations, not a sandbox; trusted scripts still have the user's
permissions. See [extensions.md](extensions.md) for the complete contract and examples.

## Other commands

- `toolchain --dry-run` inspects native prerequisites. `--yes` installs via winget or
  Ubuntu apt only in an already suitably privileged terminal; no hidden elevation.
  Minimal verification includes CMake version, GCC version and MSVC/SDK executables.
  Full legacy optional-component reconciliation is not implemented.
- `ide` generates a Visual Studio solution on Windows. `--yes` opens it if a full IDE
  exists; Build Tools alone is reported clearly. GUI launch is never implicit in MCP.
- `fmt --dry-run` lists application C/C++ files under src/ and tests/; actual formatting
  requires clang-format. It never formats deps/ or the driver.
- `clean --dry-run` previews native generated build directories. `--yes` is required
  for deletion; tracked files, linked paths, foreign caches and unrecognized trees are
  refused. Edited dependency source caches are preserved too. `clean all` is not implemented.
- `adopt --dry-run` reports an existing driver, dependencies and suspected duplicate
  acquisition. It is an inspection aid, not a CMake parser or automatic migration.
- `self-update --dry-run` plans a GitHub side-by-side user release. `--yes` installs
  without editing profiles. Project-pinned runtime updates remain reviewed manual
  changes; the command refuses to overwrite a vendored project driver.
- `mcp` prints configuration; `mcp --register` adds a missing VS Code config and refuses
  to overwrite one. Scaffolds already contain the project-local configuration.
- `targets --vscode --dry-run` previews additional F5 configurations from manifest
  targets. `--yes` adds them with a backup; existing entries and arguments are preserved.
  This keeps newly added apps discoverable in VS Code without automatic file rewriting.

## Validation

```powershell
pwsh -NoProfile -File ./tests/contracts.ps1
pwsh -NoProfile -File ./tests/manifest.ps1
pwsh -NoProfile -File ./tests/extensions-manifest.ps1
pwsh -NoProfile -File ./tests/extensions.ps1
pwsh -NoProfile -File ./tests/targets.ps1
pwsh -NoProfile -File ./tests/smoke.ps1 -Build
pwsh -NoProfile -File ./tests/vscode.ps1 -Build
pwsh -NoProfile -File ./tests/cmake-declarations.ps1
pwsh -NoProfile -File ./tests/dependencies.ps1
pwsh -NoProfile -File ./tests/dependency-roundtrip.ps1
pwsh -NoProfile -File ./tests/externalproject.ps1
pwsh -NoProfile -File ./tests/gui.ps1
```

The last command is Windows-only. On Linux run the others with native PowerShell/GCC;
WSL tests create fixtures on the Linux filesystem. Run `pwsh tests/mcp.ps1` for the real
stdio protocol checks, and `tests/ci-exit.ps1` after packaging for GitHub-style exit
handling checks, including bootstrap installation and profile preservation tests.
Expected command failures must not leak their exit code from a successful test script;
the runner-style check also verifies that real command and assertion failures propagate.
Fixtures are retained in temp directories
for inspection, not removed with broad cleanup commands.

CI runs Windows and Ubuntu checks. The manual release workflow creates a draft release
from a tested version tag. Real clean-machine compiler installation, GitHub-hosted
release download and native hosted-runner GUI sessions require validation in CI or an
appropriate disposable machine; local tests do not claim those external gates passed.