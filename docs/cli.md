# The `dd` Command Line

> **Status: design background with an initial implementation.** The authoritative
> executable contract is in [implementation.md](implementation.md). Windows supports
> GUI and CLI; Linux supports CLI only. Project settings use native `dd.psd1` data files.

Bootstrap installs the user-level launcher and templates. Then create a folder and
run `dd init` to scaffold an app in it:

```powershell
mkdir my-app
cd my-app
dd init         # Prompts for GUI or CLI; defaults the name to the folder name
dd toolchain    # Installs missing native build prerequisites when needed
dd build
```

`dd init` is project creation, not machine provisioning. A generated project vendors
`dd.ps1`, so existing clones can run it directly with PowerShell 7 without installing
the launcher. For an existing project, do not run `init` again:

```powershell
git clone https://github.com/.../photo-app
cd photo-app
pwsh -NoProfile -File ./dd.ps1 dep install
pwsh -NoProfile -File ./dd.ps1 toolchain
pwsh -NoProfile -File ./dd.ps1 build
```

---

## Commands

| Command | Purpose |
| --- | --- |
| `dd init [--type gui\|cli] [--name <name>]` | Scaffold an app in the current folder. Prompt for missing choices interactively. |
| `dd toolchain` | Install missing native compiler and build prerequisites. Idempotent; never scaffolds an app. |
| `dd doctor` | Report what is present, what is missing, and how to fix it. Never modifies anything. |
| `dd dep list [--available]` | Inspect CMake dependency declarations, or list catalog entries. |
| `dd dep install [name] [--method fetchcontent\|externalproject]` | Validate declarations or add a catalog dependency. CMake acquires it later. |
| `dd dep install <name> --git <url> --ref <ref> [--method fetchcontent\|externalproject]` | Declare a custom dependency at a full commit; resolve tags/branches once. |
| `dd dep update <name> --ref <ref>` | Change one pin in the dependency JSON; no Git staging or checkout changes. |
| `dd adopt --project <directory> --dry-run` | Inspect an existing app without rewriting it. |
| `dd build [debug\|release\|both]` | Configure if needed, then build. Default `both`. |
| `dd run [target] -- [args...]` | Select an explicit, default or sole target; build Release and launch with exact arguments. |
| `dd launch [target] -- [args...]` | Build Release, detach with file-backed logs, and return a persistent PID. |
| `dd targets` | List target IDs, platform support, paths and default selection without building. |
| `dd targets --vscode [--dry-run] [--yes]` | Add missing per-target launch entries, preserving existing entries; applying requires --yes. |
| `dd commands` | List declared project scripts and typed command metadata without executing them. |
| `dd help <name>` | Inspect one declared project command's parameters and execution contract. |
| `dd test` | Build both configs and run CTest; smoke-test GUI targets on Windows. |
| `dd ide [--yes]` | Generate a Windows solution; `--yes` opens it when a full IDE exists. |
| `dd clean [debug\|release\|both] [--dry-run] [--yes]` | Preview or authorize deletion of recognized generated build trees. |
| `dd env` | Import via the profile function; direct invocation returns environment data. |
| `dd fmt [--dry-run]` | Format application C/C++ under src/ and tests/, never deps/. |
| `dd self-update [--version <tag>] [--dry-run] [--yes]` | Install a verified side-by-side user release from GitHub; preserve project-pinned drivers and profiles. |
| `dd mcp [--register]` | Show project-local MCP configuration, or add it if absent. Templates already include it. |
| `dd help` | Usage. Also the default when invoked with no arguments. |

### Global switches

| Switch | Effect |
| --- | --- |
| `--json` | One versioned JSON result with data, errors and log paths. |
| `--project <directory>` | Explicit working directory, subject to command-specific checks. |
| `--non-interactive` | Never prompt. Also implied by JSON output, CI or redirected input. |
| `--jobs <n>` | Parallelism; defaults to the core count. |
| `--target <platform>` | Proposed native targets: `x64-windows` and `x64-linux`. Default to the host; cross-compilation is out of scope. |

### Exit codes

`0` success · `1` build or test failure · `2` bad usage · `3` missing prerequisite
(such as compiler tools or Git) · `4` environment setup failed · `5` dependency
operation failed or was blocked by local work.

Distinguishing 3 from 1 matters: CI should retry neither, but a contributor seeing 3
needs a completely different message than one seeing 1.

---

## Initialization

The user-facing sequence is **bootstrap, create a folder, enter it, `dd init`**.
Bootstrap installs the launcher, not a compiler or application. On PowerShell it
registers a profile loader with the user's consent. A shell without a profile can
invoke the installed driver directly. See [design.md](design.md#decision-10---bootstrap-and-command-routing)
for launcher routing and the Unix system `dd` name collision.

Without `--type`, interactive `init` presents **GUI** and **CLI** choices. On Linux,
show GUI as unavailable with a note that platform-h's Linux backend is planned, and
offer CLI. Do not silently substitute CLI for a requested GUI app.

| Native host | GUI scaffold | CLI scaffold |
| --- | --- | --- |
| Windows x64 | platform-h FetchContent declaration, app callbacks, GUI smoke-test configuration | Portable C++ `main`, CTest, no platform-h dependency |
| Linux x64 (initially Ubuntu under WSL 2) | Unavailable until platform-h gains a supported Linux backend | Portable C++ `main`, CTest, no platform-h dependency |

The folder name supplies the default project name. Validate it or prompt for a valid
name; record the selected name and `type` (`gui` or `cli`) in the `project` hashtable in
`dd.psd1`. GUI initialization uses the same `dep install` logic to declare platform-h
at the template's tested pin in `cmake/dd-dependencies.json`. CLI initialization adds no library
dependencies by default. Neither path installs a toolchain, changes the shell profile,
commits, pushes, or starts the application.

Both templates provide the vendored driver, manifest, CMake files, native presets,
starter source and tests. CLI CMake must not require Windows resources, MSVC, or a GUI
backend; it selects the native toolchain when configured on Windows or Linux.

For agents and scripts:

```powershell
dd init --type cli --name my-app --non-interactive
dd init --type gui --name photo-app --dry-run
```

`--non-interactive` requires `--type`, uses a valid folder name if `--name` is omitted,
and fails rather than prompting. Redirected input and CI also disable prompting.
`--dry-run` reports the files and dependencies that would be created without writes
or network access; it requires explicit choices like non-interactive mode. Dependency
fetches inherit the non-interactive credential rules in [dependencies.md](dependencies.md).

Validate app type, host support, names, destination and prerequisites before any
writes, Git initialization or fetches. A Linux `--type gui` request fails with exit
`2`, even in dry-run mode. An empty folder, or an empty Git repository rooted there,
is the initial supported destination. An existing project or other nonempty folder
fails without changes and points to `adopt`; rerunning `init` never overwrites files.
Also refuse a destination inside another Git working tree rather than creating a
nested repository or modifying the parent. A successful fresh init creates a Git
repository if needed; initialization and dependency declarations do not stage files.

`dd toolchain` checks the selected native toolchain and installs missing prerequisites
using the host's supported package manager. Without a project it selects the host's
default. On an already provisioned machine it reports success without changes.
Elevation or unavailable package managers require actionable instructions, never a
hidden password prompt in automation. `dd doctor` remains read-only.

These are the new shared-driver semantics. Legacy per-repository scripts may still
use `init` for installation; adoption must report that incompatibility rather than
guess at arguments or silently reroute them.

---

## Dependencies and scaffolding

See [dependencies.md](dependencies.md) for the command semantics, source-cache safety,
platform-h integration and agent workflow. `dd` manages URLs, full commit pins and
methods in `cmake/dd-dependencies.json`; CMake FetchContent/ExternalProject owns
acquisition and build integration. Pins are not duplicated in `dd.psd1`.

`dep install` with no name validates declarations only. It does not download, run
CMake, install the catalog or update branch tips. `dep update` changes one declaration
explicitly. Configure fetches FetchContent sources; build downloads/builds external
projects. Status `declared` does not mean the dependency is already built.

Dependency commands accept `--json` and `--non-interactive`; mutating dependency
commands also accept `--dry-run`. `init` supports `--non-interactive` and `--dry-run`
as specified above; these are not global switches. GUI scaffolds declare platform-h
and use its app helper; CLI scaffolds do not. Existing CMake recipes and project
drivers are not silently rewritten during adoption.

---

## `dd.psd1`

Project settings use a PowerShell data file, loaded with the native
`Import-PowerShellDataFile` cmdlet. No third-party parser is required on Windows or
Linux. Example schema 1 CLI app:

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
      'debug-path' = 'build/{platform}/debug/bin/app{exe}'
      'release-path' = 'build/{platform}/release/bin/app{exe}'
    }
  )
}
```

`cmake-target` is the actual CMake target, not inferred from the user-facing id or
executable name. Use `@(...)` for targets, even with one item. Quote hyphenated keys.
Comments and literal strings are supported; arbitrary PowerShell code is not. The
manifest is never dot-sourced or passed to `Invoke-Expression`.

The driver validates the loaded hashtables before configure. The data-model contract
is in [../schema/dd.schema.json](../schema/dd.schema.json), and more detail is in
[implementation.md](implementation.md#manifest). Dependency registration and exact
commits live in the dependency JSON, not PSD1. CMake owns unit tests and build rules.

Earlier experimental `dd.toml` projects need a reviewed conversion to this hashtable
syntax; simply renaming the file will not work. The new driver reports the old format
without rewriting it. Existing cache variables and executable test-output patterns
remain CMake-owned. Required ATL/MFC components can be declared in `requirements.msvc`.

For existing projects, [adoption.md](adoption.md) specifies `dependencies.owner`,
archive pins, application recipes, separate configure/build/test mappings and native
requirements. `dd build --app ID,ID` selects application build targets. `dd test`
accepts `--app ID,ID`, `--label REGEX`, and `--name REGEX`; application labels and
explicit filters intersect. Tests always build both preset defaults and fail if no
tests match. Failures include test names, durations, excerpts and full log paths.

`run` remains bounded (120 seconds by default). `launch` returns a PID, start timestamp,
executable and stdout/stderr log paths; the application survives driver/MCP exit.
Configure/build/test progress goes to stderr and optional MCP progress notifications;
stdout with `--json` remains one result envelope. Clean uses verified CMake File API
records, never guessed directories; stale and ambiguous cleanup requests fail safely.

### Extensions and multiple apps

Schema 1 additionally accepts optional `commands`, `project.default-target` and
per-target `platforms` fields. The declaration syntax and JSON script protocol are
specified in [extensions.md](extensions.md), with a runnable version-bump example.

`commands`, `targets` and `help NAME` validate metadata without compiler setup or
project script execution. Native build checks are separate. `run` uses an explicit ID,
the configured default, or the only compatible target; ambiguous non-interactive
requests fail before building. Interactive callers are prompted to select an ID.

Custom commands take named string/integer/boolean parameters. Unknown arguments and
built-in name collisions are errors. Write commands require `--yes` in automation;
`--dry-run` is script-backed and must be declared and implemented by the project.
The shared driver never silently overrides built-in commands or installs hooks.

---

## Required behaviours

These are the things the prototype gets right that a reimplementation would get wrong.
Each one cost a debugging session to find.

### Environment

The following compiler-environment rules apply to Windows/MSVC. Linux uses native
compiler discovery and must not run Visual Studio discovery or `vcvars64.bat`.

- **Clear `VSCMD_VER` before running `vcvars64.bat`.** The batch file silently
  short-circuits when it is already set, leaving a shell that has `cl.exe` but not
  `rc.exe`. The failure surfaces much later, in the resource compile step.
- **Verify after importing.** Check `cl.exe`, `link.exe` and `rc.exe` resolve; do not assume the
  batch file succeeded because it exited zero.
- **Import once per process** and cache the result.
- Prefer `vswhere.exe` over a hardcoded path list (see Risk 1 in
  [design.md](design.md)).

### Configure

- **Detect stale configuration without unsafe deletion.** Two cases seen in practice:
  a cache variable the driver now wants to set differently (CMake will keep the old
  value silently), and a `CMAKE_MAKE_PROGRAM` pointing at a Ninja that has since been
  uninstalled. The second produces an error message that names neither Ninja nor the
  cache.
- Search **recursively** for nested `CMakeCache.txt` files; subprojects have their own.

The current implementation always configures and never deletes caches implicitly.
For incompatible cached generators or tools, report the error and use a reviewed
`clean --dry-run` / `clean --yes` on recognized build trees. Broader cache repair is
future work, not permission to delete source or dependency trees.

### Build

- **`ninja -k 0`** so one run reports every error rather than stopping at the first.
  A contributor should not have to build six times to see six errors.
- **Write the raw log to a temp file and print its path.** The summary is lossy by
  design; the detail has to remain reachable without a rebuild.
- **Build debug and release.** A debug-only compiler ICE once went unnoticed for an
  entire release because only release was built.

### Diagnostic summary

Group twice and show both:

- **By file** — tells you *where* to work. A header included by 76 translation units
  can account for hundreds of lines from five lines of source.
- **By code** — tells you *what kind* of problem it is. 412 instances of one code is
  usually a single declaration, not 412 problems.

Always print the ratio implicitly by showing counts, so the reader can divide total by
unique before estimating effort.

### Testing

CLI apps run CTest and command-line checks with exit-code, output and timeout
assertions; they never wait for a window. GUI smoke tests apply only to GUI targets
on supported hosts. The following process/window rules describe Windows GUI testing.

- **Redirect stdout to a file.** A `/SUBSYSTEM:WINDOWS` process is not given the
  parent's console, so a pipe reads empty regardless of what the program printed.
- **Never `-Wait` on a test process.** A faulting case can raise a modal crash dialog
  with nobody present to dismiss it, and the run hangs forever. Always use a timeout
  and kill on expiry.
- **`WaitForInputIdle` is not enough** to conclude a window exists. It returns as soon
  as the process pumps messages, which is well before the frame is created. Poll for
  the window with a deadline instead of sleeping a fixed interval, or the result
  depends on how busy the machine is.
- **Report the settled window title, not the first one observed.** The frame gets its
  own caption before the view has anything to prefix it with, so the first title read
  is a race that looks like a regression.
- **Check for a crash report even when the window opened.** An app can fault and keep
  running; a report file written after the run started downgrades a pass to a fail.
  This check belongs in `finally`, and it must mutate a result variable — `return` has
  already fixed the function's value by then.
- **Always clean up the process**, including on the failure paths.

### Argument validation

Validate every user-supplied value against the known set *before* acting. Two bugs of
identical shape were found in the prototype: `clean both` fell through as a literal and
looked for a directory named `x64-both`, cleaning nothing and reporting success; and an
unknown target id caused every test to report `SKIP` and exit `0`. **A run that does
nothing because the requested target was invalid must never exit zero.** An explicit,
verified no-change result from an idempotent operation such as `dep install` is success.

---

## Repository layout

Example Windows GUI scaffold (CLI scaffolds omit platform-h and use native presets):

```text
<repo>/
├── dd.ps1                  # Vendored driver, identical across repositories
├── dd.psd1                 # Native data-only project configuration
├── cmake/
│   └── dd-dependencies.json # Dependency URLs, exact commits and CMake methods
├── CMakeLists.txt
├── CMakePresets.json       # Preset names referenced by dd.psd1
├── src.../
├── exe/                    # output-dir; finished executables
└── build/
    └── x64-windows/
      ├── debug/
      ├── release/
      └── vs/             # dd ide
```

---

## CI

The point of CI parity is that a failing job can be reproduced with the same command
locally, with no translation step.

```yaml
- shell: pwsh
  run: |
    ./dd.ps1 dep install
    ./dd.ps1 toolchain
    ./dd.ps1 test
```

The job must first check out the application repository and have Git available.
Dependency acquisition uses the committed JSON pins, not the current catalog or branch
tips. `dep install` validates data; CMake fetches into each build tree and checks any
existing source checkout before reusing it.

CI builds existing projects; it does not scaffold them with `init`. Separate template
tests run `init --type cli --non-interactive` on Windows and Ubuntu and
`init --type gui --non-interactive` on Windows, then build and test clean clones.
WSL 2 Ubuntu is the initial local Linux test environment; native Ubuntu CI supplements
it. A CLI workflow must not depend on a desktop session or the platform-h backend.

`dd` should detect CI (via `$env:CI`) and adjust: no colour, no summarising (the log is
the artifact), and never open a window that requires interaction.

Open question: the smoke test needs an interactive desktop session. GitHub's
`windows-latest` runners provide one, but this should be verified early rather than
assumed, since the smoke test is the most valuable check in the suite.
