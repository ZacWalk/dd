# How dd works

This document maps the driver for whoever changes it. What each command does for its
user is in [cli.md](cli.md); why dd is built this way is in [design.md](design.md).

## Runtime

`dd.ps1` dot-sources `.dd/core.ps1` and calls `Invoke-DD`, which loads the other modules,
parses the options, dispatches the command and writes the result.

| File | Owns |
| --- | --- |
| `.dd/core.ps1` | The version and file inventory, options, manifest validation, project discovery, processes, the MSVC environment, `init`, `build`, dispatch and the result envelope |
| `.dd/commands.ps1` | `toolchain`, `clean`, the GUI smoke test, `ide`, `fmt`, `self-update`, `adopt`, `env` and `mcp` |
| `.dd/execution.ps1` | Streaming tool output, `launch` and CTest |
| `.dd/presets.ps1` | CMake preset resolution, configure and its state records |
| `.dd/requirements.ps1` | Tool and Visual Studio requirements, and the doctor report |
| `.dd/dependencies.ps1`, `.dd/dependencies.cmake` | `dd dep`, and the CMake side of the pins |
| `.dd/project-commands.ps1` | Project commands, target metadata and selection, and VS Code launch entries |
| `.dd/mcp/` | The MCP server (`server.ps1`), its tools (`tools.ps1`) and the CLI bridge (`invoke.ps1`) |
| `.dd/catalog.json`, `.dd/templates/` | Dependency names and URLs; the scaffolds |
| `.dd/LICENSE` | dd's MIT licence, so every vendored copy carries it |
| `profile.ps1`, `bootstrap.ps1` | The installed `dd` function; installation |

`Get-DDRuntimeFiles` and `Get-DDReleaseFiles` in `core.ps1` are the file inventory that
`init`, packaging and `tools/prepare.ps1` use. `bootstrap.ps1` cannot load the runtime it
is verifying, so it carries its own copy of the release list; `prepare.ps1` fails when
the two differ, and when the schema's reserved command names differ from the built-ins.
The CLI and library templates must build with GCC on Linux, so they require no Windows
resources, MSVC or GUI backend; CI builds both on Windows and Ubuntu.

## Finding the project

The `dd` profile function runs the nearest `dd.ps1` at or above the current directory, or
the installed driver for `init` and when there is none. The driver starts from the current
directory or `--project`, where `init` stays. Commands that act on a project walk up to
the nearest folder with a `dd.psd1` and fail with exit 3 when there is none; `help`,
`doctor`, `toolchain`, `dep`, `env`, `adopt`, `self-update` and `mcp` also work outside a
project. Nothing changes the shell's directory, and in MCP mode the walk stops at the
workspace boundary. Running a repository's driver, or its CMake, runs that repository's
code.

## Processes

External tools run through `Invoke-DDProcess`: without a shell - `cmd.exe` only for
`vcvars64.bat` - over UTF-8 pipes, and with a timeout, ten minutes unless the caller sets
another, after which the whole process tree is killed. Git runs with terminal and
credential prompts off, the `ext` and `file` protocols disabled and hooks ignored.

Configure, build and test stream each output line to stderr, unprefixed so VS Code's
`$msCompile` and `$gcc` problem matchers still anchor at column 1, with a heartbeat every
five seconds. stdout and stderr are captured separately, so a combined log does not keep
their exact interleaving.

## Configure and build

Every build configures first, with `cmake --preset`. dd writes a CMake File API query
beforehand, checks afterwards that CMake's reply names this source tree and the preset's
binary directory, then records the directory, the generator and the hashes of the presets
and `dd.psd1` in `.dd/state/<platform>-<configuration>.json`. `clean` trusts nothing else
and never runs CMake to find a directory. dd never deletes a cache on its own, and does
not detect a stale one: a cache variable CMake silently keeps, or a `CMAKE_MAKE_PROGRAM`
naming a Ninja since uninstalled, whose error names neither. `dd clean` and a rebuild fix
both.

The build passes `-k 0` to Ninja, so a contributor sees every error from one run.
Diagnostics are parsed from MSVC's `file(line): error C1234:` and GCC's
`file:line:col: warning: ... [-Wflag]` forms and counted by file and by code
([why](design.md#decisions)). Both configurations build by default because a compiler
fault can appear in only one.

## Logs

Each logged run writes `<guid>.log` in the temp directory's `dd-logs`; `test` also leaves
its JUnit report as `dd-ctest-<guid>.xml`, and `launch` its output in `dd-launch`. The
first log a dd process writes removes those older than two weeks. Read-only Git commands
and version probes keep no log. Summaries are lossy by design; the log keeps the detail.

## Tests

`dd test` asks CTest for its selection as JSON first and refuses an empty one, then runs
it with `--no-tests=error` and reads failures from the JUnit report. The GUI smoke test,
`Invoke-DDGuiSmoke`, keeps rules that each cost a debugging session:

- Never wait on a test process without a timeout: a faulting app can raise a modal crash
  dialog that nobody dismisses.
- `WaitForInputIdle` returns before the frame exists. Poll for the window against a
  deadline; a fixed sleep makes the result depend on the machine's load.
- Report the settled title, not the first one read: the frame has its caption before the
  view prefixes it.
- Look for crash reports in `finally`, even after a pass: an app can fault and keep
  running.
- End the process on every path, failures included.

## Arguments

Validate every user-supplied value against the known set before acting. A run that does
nothing because a request was invalid must never exit 0; an explicit, verified no-change
result, such as `dep install` finding the declaration already there, is success.

## Releases and bootstrap

`tools/package.ps1` stages `dd.ps1`, `profile.ps1`, `bootstrap.ps1`, `README.md`, the
runtime and templates, `schema/`, `docs/` and `examples/`; writes `release.json` with every
file's SHA-256; and produces `dist/dd.zip` and `dist/dd.zip.sha256`. It refuses to
overwrite an existing archive. The *Publish dd release* workflow creates a draft GitHub
release from an existing tag that matches the runtime version, after `prepare.ps1`,
`verify.ps1`, packaging and `tests/ci-exit.ps1`; bootstrap sees it only once it is
published. Local packaging publishes nothing.

`bootstrap.ps1` needs PowerShell 7.4 and Git. It downloads `dd.zip` and its checksum from
the latest GitHub release, or the one `-Version` names, accepting only URLs under this
repository's releases. It checks the archive's SHA-256; refuses absolute, parent and
duplicate entries, symlinks, and archives that unpack to over 256 MB or 10,000 entries;
unpacks into a staging folder and checks every file against `release.json` and the
required list; and only then moves the release into place, beside any others, as
`<version>-<hash prefix>` under `%LOCALAPPDATA%\dd` or `~/.local/share/dd`. It never
overwrites an installed release that was modified, nor installs through a linked path.

| Option | Effect |
| --- | --- |
| `-Version vX.Y.Z` | That tagged release instead of the latest, for a reproducible install |
| `-ArchivePath <zip>`, `-Sha256 <hash>` | Install a local archive; the checksum is always required |
| `-InstallRoot <directory>` | Install somewhere else |
| `-RegisterProfile`, `-NoProfile` | Add the `dd` function to the profile without asking, or leave the profile alone |
| `-ProfilePath <file>` | Edit that profile instead of the current user's |

Profile registration adds one marked block that loads `profile.ps1`. It backs the profile
up first, keeps the rest of it, refuses when another `dd` function or alias exists, and
changes nothing when rerun. On Linux the function shadows the system `dd` only inside
PowerShell, and the prompt says so; `/usr/bin/dd` is never replaced. Bootstrap never
elevates, uses sudo or changes the execution policy. Its checksums detect corruption, not
a compromised publisher: releases are not signed.
