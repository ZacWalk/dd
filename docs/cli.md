# The `dd` command line

`dd` is one PowerShell script with the same commands in every project. Run it as `dd`
once [bootstrap](../README.md#bootstrap) has added the profile function, or as
`pwsh -NoProfile -File ./dd.ps1` through a project's vendored copy. This document owns
the built-in commands, their options and results, what `dd init` creates and the
`dd.psd1` project file. `dd help --json` lists the commands a driver knows.

## Commands

| Command | Behaviour |
| --- | --- |
| `dd init [--type gui\|cli\|library] [--name <name>] [--dry-run]` | Scaffold a project in the current, empty folder; prompt for missing choices ([Initialization](#initialization)) |
| `dd toolchain [--dry-run] [--yes]` | Check the native build tools; `--yes` installs the missing ones ([toolchain.md](toolchain.md)) |
| `dd doctor` | Report missing tools and invalid project files; change nothing |
| `dd dep list\|install\|update ...` | Inspect, add or re-pin dependency declarations ([dependencies.md](dependencies.md#commands)) |
| `dd build [debug\|release\|both] [--app <id,id>]` | Configure and build; both configurations by default |
| `dd test [--app <id,id>] [--label <regex>] [--name <regex>]` | Build both configurations, run CTest and smoke-test GUI targets |
| `dd run [<target>] [--timeout <seconds>] -- [args...]` | Build a target in Release, run it and wait for it |
| `dd launch [<target>] -- [args...]` | Build a target in Release and start it detached; return its PID and log paths |
| `dd targets [--vscode --dry-run\|--yes]` | List the targets, or add missing VS Code launch entries ([Targets](#targets)) |
| `dd commands`, `dd help <name>` | Describe the project's own commands without running them ([extensions.md](extensions.md)) |
| `dd <name> [--<parameter> <value>...]` | Run a project command declared in `dd.psd1` |
| `dd clean [debug\|release\|both] [--dry-run\|--yes]` | Preview, or delete, verified build trees; both by default |
| `dd ide [--yes]` | Generate a Visual Studio solution on Windows; `--yes` opens it |
| `dd ide --mcp [--dry-run]` | Write a missing `.vscode/mcp.json` ([mcp.md](mcp.md#start-and-trust)) |
| `dd fmt [--dry-run]` | Run clang-format on the C and C++ files under `include/`, `src/` and `tests/` |
| `dd env` | Return the compiler environment; the profile function imports it into the shell |
| `dd self-update [--version <vX.Y.Z>] [--dry-run] [--yes]` | Install another release beside the installed one |
| `dd adopt --dry-run` | Inspect an existing application without changing it ([adoption.md](adoption.md)) |
| `dd mcp [--allow-execution]` | Serve MCP over stdio until stdin closes ([mcp.md](mcp.md)) |
| `dd help` | Usage; also the default with no arguments |

## Options

| Option | Effect |
| --- | --- |
| `--json` | Print one result envelope on stdout ([Results](#results-and-exit-codes)) |
| `--project <directory>` | Act on that directory instead of the current one |
| `--non-interactive` | Never prompt; implied by `--json`, a set `CI` variable and redirected input |
| `--jobs <n>` | `build`, `test`, `run` and `launch`: parallel jobs, 1 to 1024; the core count by default |
| `--target <platform>` | `build`, `test`, `run` and `launch`: must name the host, `x64-windows` or `x64-linux`; dd does not cross-compile |

`--dry-run` previews and `--yes` authorizes where a command lists them. An unknown,
repeated or inapplicable option is an error, and every value is checked against the known
set before anything runs, so a mistyped configuration, target or app fails with exit 2
instead of doing nothing.

## Results and exit codes

With `--json`, stdout carries exactly one object: `schema` (1), dd's `version`, `ok`,
`exitCode`, the command's `data`, its `errors` and the `logs` it kept
([Logs](implementation.md#logs)). Without it, dd prints a summary on stdout and errors on
stderr. Configure, build and test output streams to stderr either way, with a heartbeat
every five seconds. Read structured data and log paths, not display text.

| Code | Meaning |
| --- | --- |
| 0 | Success, including a verified no-change result |
| 1 | A build, test or other execution failed |
| 2 | Invalid request |
| 3 | Missing prerequisite: build tools, Git, a manifest, a script or an executable |
| 4 | Compiler environment setup failed |
| 5 | A dependency operation failed or was blocked by local work |

`run` and project commands exit with their child's code. A missing prerequisite (3)
needs a different fix from a failed build (1), which is why they differ.

## Initialization

`dd init` creates a project in the current folder, or in `--project <directory>`, never
in an ancestor. Without `--type` it asks for GUI, CLI or library; `--non-interactive`
and `--dry-run` require `--type`. The name defaults to the folder's: up to 64 letters,
digits, hyphens and underscores, starting with a letter, and not a device name such as
`con`. `--dry-run` lists the files and dependencies without writing or using the network.

| Type | Hosts | Scaffold |
| --- | --- | --- |
| `gui` | Windows | A C++20 app on [libdesktop](https://github.com/ZacWalk/libdesktop)'s `ui` library: a `ui::app` and a `ui::frame_host` in `src/main.cpp`, built with `libdesktop_add_app()` |
| `cli` | Windows, Linux | A C++20 `main` that answers `--help`, with CTest checks |
| `library` | Windows, Linux | A C static library, its header, a unit test, and an example CLI that links it |

The destination must be empty, or an empty Git repository rooted there; any other folder
is refused with a pointer to [`adopt`](adoption.md), and so is a folder inside another Git
working tree. The type, host, name and destination are checked before the first write. A
GUI request on Linux fails with exit 2, even with `--dry-run`: the GUI template needs
Windows and MSVC.

`init` runs `git init` if needed and stages nothing. A GUI scaffold declares libdesktop
with `dd dep install`, pinning the catalog's current default-branch head, and its README
gains a note on libdesktop's MPL-2.0 licence. `init` installs no tools, edits no profile,
and never commits, pushes or starts the app. Every scaffold contains:

| Path | Contents |
| --- | --- |
| `dd.ps1`, `.dd/` | The vendored driver, its runtime and templates, identical in every project |
| `dd.psd1` | [The project file](#the-project-file) |
| `cmake/dd-dependencies.json` | [Dependency pins](dependencies.md) |
| `CMakeLists.txt`, `CMakePresets.json` | C++20 and C17, the static MSVC runtime and `compile_commands.json`; Ninja presets `windows-debug`, `windows-release`, `linux-debug` and `linux-release`, building in `build/<platform>/<configuration>`, and `windows-ide` |
| `src/`, `include/`, `tests/` | Starter source and CTest tests |
| `README.md`, `AGENTS.md` | Build instructions, with a CI badge whose `OWNER` placeholder needs the repository's owner; the automation contract for agents |
| `.vscode/` | F5 debugging, C++20 IntelliSense, the C/C++ extension recommendation and the [MCP server](mcp.md) |
| `.github/workflows/ci.yml` | [CI](#ci) on Windows, and on Ubuntu for CLI and library projects |
| `.gitignore` | `build/`, `.vs/`, `tmp/`, `.dd/state/` and dd's backups |

F5 runs the `dd: build debug` task, then debugs the target's Debug binary. GUI projects
get the Windows debugger only; CLI and library projects get Windows (MSVC) and Linux (GDB)
entries, the host's first. dd installs neither GDB nor editor extensions. A launch entry's
`program` repeats the target's `debug-path`: change both together.

## The project file

`dd.psd1` is one PowerShell data hashtable, loaded with `Import-PowerShellDataFile`. dd
never dot-sources or evaluates it, so it holds comments and literals but no code. Its
model is [schema/dd.schema.json](../schema/dd.schema.json). The CLI scaffold's:

```powershell
@{
    schema = 1
    project = @{
        name = 'my-app'
        type = 'cli'
    }
    build = @{
        'x64-windows' = @{
            debug = 'windows-debug'
            release = 'windows-release'
            ide = 'windows-ide'
        }
        'x64-linux' = @{
            debug = 'linux-debug'
            release = 'linux-release'
        }
    }
    targets = @(
        @{
            id = 'app'
            kind = 'cli'
            'cmake-target' = 'app'
            'test-label' = 'app'
            'debug-path' = 'build/{platform}/debug/bin/app{exe}'
            'release-path' = 'build/{platform}/release/bin/app{exe}'
        }
    )
}
```

| Field | Meaning |
| --- | --- |
| `schema` | `1` |
| `project` | `name`, `type` (`gui`, `cli` or `library`) and an optional `default-target` |
| `build` | Per host, the CMake presets for `debug` and `release`, or a [configure, build and test preset each](adoption.md#phase-presets), and optionally a Visual Studio configure preset as `ide`. Building needs the current host's table |
| `targets` | An array of [targets](#targets): `id`, `kind`, the real `cmake-target`, `debug-path` and `release-path`, and optionally `platforms`, `test-label` and `smoke` |
| `dependencies` | Optional `owner`, `'dd'` by default or `'application'` ([dependencies.md](dependencies.md#ownership)) |
| `requirements` | Optional tool minima and Visual Studio components ([toolchain.md](toolchain.md#requirements)) |
| `commands` | Optional project commands ([extensions.md](extensions.md)) |

Quote hyphenated keys, single-quote literal paths, and write `targets` as `@(...)` even
with one entry. Unknown fields, duplicate keys and expressions fail before CMake runs.
Target paths stay inside the project and take `{platform}`, `{exe}` (`.exe` on Windows),
and `{libprefix}` and `{lib}`, which give a static library its toolchain's name:
`applib.lib` with MSVC, `libapplib.a` with GCC. Dependency pins live in
`cmake/dd-dependencies.json`, never here. dd refuses a project that has a `dd.toml`:
convert its settings to a `dd.psd1` hashtable; renaming the file is not enough.

## Targets

Each executable or static library the project builds is one target, so several apps are
several entries. `cmake-target` and the paths name the real CMake target and outputs,
whatever the `id`. The `kind` decides what dd does with it:

| Kind | Hosts by default | `run`, `launch`, F5 | `dd test` |
| --- | --- | --- | --- |
| `gui` | Windows only; it cannot declare Linux | Yes | CTest and the window smoke test |
| `cli` | Windows and Linux | Yes | CTest |
| `library` | Windows and Linux | No: an archive has no entry point | CTest |

`platforms` narrows a target to some hosts; the application's CMake must itself leave
out what a host does not build. `test-label` is the CTest label that `--app` selects.
`dd targets` lists each target's ID, kind, paths, platforms, whether it is the default
and whether it is runnable, without building anything.

`run` and `launch` take a target ID, else `project.default-target`, else the only
runnable target for the host. With several and no default, an interactive run asks and
automation fails, listing the choices. A default the host cannot run is an error, not a
fallback. Keep the default on an executable: a library scaffold's is its example CLI.

`dd targets --vscode --dry-run` lists the F5 entries the executable targets lack, and
`--yes` adds them, backing up `launch.json` first. Existing entries, arguments and
compound configurations stay; an existing entry with a generated name but another program
stops the command for manual review. The file is rewritten as plain JSON, without its
comments. dd never touches VS Code files during a build or run, and never removes entries.

## Building and testing

`dd build` configures each selected configuration with its preset, every time, then
builds it - with Ninja, past the first error, so one run reports them all. `--app` builds
just those targets. The summary counts diagnostics by file and by code - MSVC codes, GCC
warning options - and the full log is kept ([how](implementation.md#configure-and-build)).
Each configure, build and CTest run is stopped after ten minutes.

`dd test` builds both configurations' preset defaults, so separate test executables are
built too, then runs CTest in each. `--app` selects the union of those targets'
`test-label`s, which `--label` and `--name`, CTest regexes, narrow further. A selection
with no tests fails with exit 2, and a test without its own timeout gets 120 seconds.
Failed tests appear in `data.testFailures` with names, durations, excerpts and logs.

On Windows each host-compatible `gui` target then gets a window smoke test in both
configurations, unless `--label` or `--name` was given:

- the process must create its window within 20 seconds and still be running once its
  title settles; the result reports that title;
- WM_CLOSE must end it with exit code 0 within four seconds - except a target that asks
  before it closes, a tray app say, which declares `smoke = 'start'` and is ended once
  its window has settled;
- a file whose name contains `crash`, written during the test in the project root or
  beside the executable, fails it.

The GUI scaffold installs no crash reporter, so the absence of such a file does not prove
that nothing faulted.

## Running

`dd run` builds the [selected target](#targets) in Release, runs it from the project root
with the arguments after `--`, and returns its output and exit code. It waits at most 120
seconds, or `--timeout` seconds (1 to 9999), then ends the process tree. CMake still
configures the whole project.

`dd launch` builds the same way, then starts the target detached, with empty stdin and
stdout and stderr in files under the temp directory's `dd-launch`. It returns the PID,
start time, executable and log paths: process creation, not readiness. The process
outlives dd and the MCP server, and dd never stops it. On Linux it needs `setsid` and
`nohup`.

### Forwarding arguments from PowerShell

PowerShell removes a bare `--` from the arguments of a script or function it runs, so
`.\dd.ps1 run app -- --help` reaches dd as `run app --help`, and dd rejects `--help` as
one of its own options. Quote it: `.\dd.ps1 run app '--' --help`. The `dd` profile
function is no different.

## Other commands

- `dd doctor` checks the tools and versions the project needs, its manifest and its
  dependency declarations, and exits 3 when something is missing.
- `dd clean` deletes only build trees that dd configured and recorded, after checking that
  each belongs to this project and holds no tracked files, linked paths or edited
  dependency sources. `--dry-run` lists them and `--yes` deletes them. A tree that several
  configurations share needs `clean both` ([adoption.md](adoption.md#phase-presets)).
- `dd ide` configures the `ide` preset, which must use a Visual Studio generator, and
  returns the solution; `--yes` opens it, which needs Visual Studio, not just Build Tools.
- `dd fmt` needs clang-format and touches nothing outside `include/`, `src/` and `tests/`.
- `dd env` sets up the compiler environment and returns `PATH`, `INCLUDE`, `LIB` and
  `LIBPATH`; through the profile function it imports them into the calling PowerShell.
- `dd self-update` runs the installed release's `bootstrap.ps1` to install another release
  beside it, leaving profiles alone. A project's vendored driver refuses it: updating that
  is a reviewed change to the project.

## CI

CI runs the commands a contributor runs. The scaffold's workflow has read-only
permissions and does not persist checkout credentials; on Ubuntu it first installs `g++`,
`cmake` and `ninja-build` with apt. Then, as separate steps:

```powershell
./dd.ps1 dep install --non-interactive
./dd.ps1 doctor --non-interactive
./dd.ps1 test --non-interactive
```

CMake fetches the committed pins, never the catalog's or a branch's current head. GitHub's
Windows runners have the desktop session the GUI smoke test needs.
