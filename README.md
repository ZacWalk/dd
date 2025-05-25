# dd — the Dynamic Dispatch Build System

[![Build and test dd](https://github.com/ZacWalk/dd/actions/workflows/ci.yml/badge.svg)](https://github.com/ZacWalk/dd/actions/workflows/ci.yml)

**Create and build C++ apps: GUI or CLI on Windows, CLI on Linux.**

Workflow after bootstrapping the `dd` launcher:

```powershell
mkdir my-app
cd my-app
dd init         # Choose GUI or CLI; scaffold in this folder
dd toolchain    # Install missing compiler and build tools when needed
dd build
```

GUI initialization declares platform-h for pinned CMake FetchContent acquisition. CLI
initialization adds no library dependencies. Linux GUI support is planned once
platform-h has a Linux backend; it is not available yet.

[Source and releases](https://github.com/ZacWalk/dd)

All dd downloads come from this GitHub repository. Native compiler packages still
come from official OS providers. The owned dynamicdispatch.org domain is not used
for bootstrap, updates, templates or dependency catalogs.

## Bootstrap

In **PowerShell 7.4+** (`pwsh`), with Git installed:

```powershell
irm "https://raw.githubusercontent.com/ZacWalk/dd/main/bootstrap.ps1" | iex
```

This downloads and immediately executes the bootstrap script. Inspect
[bootstrap.ps1](bootstrap.ps1) first, or download and review it before running it.
The installer verifies the latest published release archive and asks before adding
`dd` to your PowerShell profile. Accept that prompt to use `dd` immediately and in
future PowerShell sessions; declining leaves direct script invocation available.
It does not install a compiler. A published GitHub release containing `dd.zip` and
`dd.zip.sha256` is required; otherwise use the source-checkout instructions below.

## Try the source checkout

```powershell
pwsh -NoProfile -File ./tools/prepare.ps1
pwsh -NoProfile -File ./dd.ps1 help --json
```

`prepare` validates the source runtime and native `dd.psd1` template offline; there
is no parser dependency to download or compile. It does not install a compiler or
modify profiles. The CLI and optional MCP server use only PowerShell 7.4+ and its
built-in libraries; no package installation or JavaScript build is needed.
To create an app, make an empty folder outside this Git working tree and run
the source checkout's driver with `init --project <folder>`.

For a packaged release, run `bootstrap.ps1 -RegisterProfile` after inspecting it.
It downloads and verifies `dd.zip` from GitHub Releases and preserves existing profile
content. Existing `dd` functions are reported as conflicts, not overwritten. A fresh
release must be published before the remote bootstrap workflow can succeed; these
working-tree changes have not been published automatically. See
[docs/implementation.md](docs/implementation.md) for exact commands and validation.

---

## Why

DD is a very simple package manager and build system. Really just a PowerShell script. I use it for my C++ projects and it makes my life a lot easier.

## What it does

The implemented command surface is:

- **Bootstrap** installs the user-level launcher and templates, not a compiler or app.
- **`dd init`** scaffolds in the current folder, prompting for GUI or CLI. Agents can
  use `dd init --type cli --name my-app --non-interactive` instead of answering prompts.
- **`dd toolchain`** installs missing native build tools: MSVC, Windows SDK, CMake and
  Ninja on Windows; initially GCC, CMake and Ninja on Ubuntu Linux. Inspect with
  `--dry-run`; installation requires `--yes` and the appropriate privileges.
- **`dd dep install [name]`** validates or adds pinned declarations in
  `cmake/dd-dependencies.json`. Choose FetchContent (default) or `--method externalproject`.
  CMake fetches/builds dependencies; pin changes are explicit and nothing is Git-staged.
- **`dd build`** sets up the compiler environment, configures, builds every
  configuration, and summarises the result.
- **`dd test`** runs unit tests and command-line checks. GUI targets additionally get
  window smoke tests on supported hosts; CLI targets never require a desktop.
- **`dd run`**, **`dd ide`**, **`dd clean`**, **`dd doctor`** do what they look like.

Failures are triaged rather than dumped: diagnostics are grouped by file *and* by
error code, so it is obvious whether you are looking at one systematic mistake or many
separate ones. The full log is always kept.

## How it fits together

Bootstrap makes `dd init` available before a project exists. Each scaffold then vendors
`dd.ps1`, like `gradlew`, with project-specific settings in `dd.psd1`. The manifest is
a native PowerShell data hashtable, loaded without executing project code. Existing clones
can invoke the script directly with PowerShell 7 without the user-level launcher.
The shared driver has the same command surface across projects; no app-specific forks
are needed. Unix bootstrap must not silently shadow the system `dd` utility.

Each scaffold includes `.vscode/mcp.json` pointing at its own `.dd/mcp/server.ps1`, plus
`AGENTS.md` with the automation contract. MCP is optional and runs directly with `pwsh`.
It defaults to inspection, scaffold and dependency tools. For a trusted project, add
`-AllowExecution` to that project's MCP server arguments to enable build/test/run/launch.
Compiler installation, profile changes and arbitrary shell commands are not MCP tools.
See [docs/mcp.md](docs/mcp.md) for the launch command, protocol contract and upgrade steps.

Projects can declare custom commands such as `dd version` in `dd.psd1`, backed by
project-owned PowerShell scripts. `dd commands --json` and `dd help version` discover
their typed interfaces without running code. Write operations require confirmation;
MCP script execution requires explicit trust, even for dry-runs. Multiple applications
use normal target entries, optional `project.default-target`, and `dd run [target]`.
See [docs/extensions.md](docs/extensions.md) for the protocol and working version example.

Scaffolds include VS Code F5 launch/build tasks, C++20 IntelliSense settings and the
C/C++ extension recommendation. The native Debug configuration is listed first;
Linux debugging additionally needs GDB. A generated GitHub Actions workflow builds
and tests both configurations on Windows and Ubuntu for CLI apps, or Windows for GUI
apps. Generated README badges contain an explicit `OWNER` placeholder until published.

New GUI applications use [platform-h](https://github.com/ZacWalk/platform-h). CMake's
FetchContent and ExternalProject modules acquire dependencies at exact commits or archive
SHA-256 hashes in `cmake/dd-dependencies.json`. CMake owns linking and build directories;
application-owned recipes handle special integration. Existing apps can explicitly keep
all dependency ownership in their CMake files. ATL/WTL remain existing-app options,
not new-app defaults. See [docs/adoption.md](docs/adoption.md) for separate phase presets,
native requirements, focused tests, and persistent launch.

Underneath it is ordinary CMake, Ninja and a native compiler. `dd` owns the environment, the
diagnostics and the command surface — not your build graph.

For an existing clone, validate declarations and provision tools without scaffolding:

```powershell
pwsh -NoProfile -File ./dd.ps1 dep install
pwsh -NoProfile -File ./dd.ps1 toolchain
pwsh -NoProfile -File ./dd.ps1 build
```

## Commands

| | |
| --- | --- |
| `dd init [--type gui\|cli] [--name <name>]` | Scaffold in the current folder; prompt for missing choices |
| `dd toolchain` | Install missing native build prerequisites |
| `dd dep install [name] [--method fetchcontent\|externalproject]` | Validate declarations or add a selected library; CMake fetches it later |
| `dd dep list` | Inspect dependency URLs, pins and methods |
| `dd dep update <name> --ref <ref>` | Explicitly change a dependency pin |
| `dd build [debug\|release\|both]` | Build |
| `dd run [target] -- [args...]` | Build Release and wait for the target, with a bounded timeout |
| `dd launch [target] -- [args...]` | Start a persistent Release app; return PID and log paths |
| `dd targets [--vscode --dry-run]` | Discover apps or preview missing F5 launch entries |
| `dd commands` / `dd help <name>` | Discover declared project commands without executing scripts |
| `dd test [--app ID,ID] [--label REGEX] [--name REGEX]` | Both configurations; filtered CTest or the full suite and GUI smoke tests |
| `dd ide [--yes]` | Generate a Visual Studio solution; `--yes` opens it (Windows only) |
| `dd clean [debug\|release\|both] --dry-run` | Preview cleanup; use `--yes` to delete recognized build trees |
| `dd doctor` | Diagnose a broken environment |
| `dd mcp` | Show project-scoped MCP configuration; scaffolds already include it |
| `dd adopt --dry-run --project <folder>` | Inspect an existing application without rewriting it |
| `dd self-update --dry-run` | Plan a side-by-side user-level release update |

## Status

Initial implementation, version 0.1.0. Windows CLI and platform-h GUI scaffolds, native
Linux CLI builds, pinned dependency workflows, local release installation and the MCP
protocol adapter have executable tests. Interfaces are not stable yet. Automatic
legacy-project migration and in-place updates of project-pinned drivers are deliberately
not implemented; existing source and local work are preserved.

## Documentation

| | |
| --- | --- |
| [docs/design.md](docs/design.md) | The problem, the goals, and every decision with its rationale |
| [docs/implementation.md](docs/implementation.md) | Current executable behavior, setup, MCP, tests and limitations |
| [docs/cli.md](docs/cli.md) | Command surface, `dd.psd1` schema, required behaviours |
| [docs/dependencies.md](docs/dependencies.md) | FetchContent/ExternalProject dependencies, migration and agent workflow |
| [docs/extensions.md](docs/extensions.md) | Custom commands, typed script protocol, multi-app targets and MCP trust |
| [docs/toolchain.md](docs/toolchain.md) | How the compiler is acquired and driven |

## Requirements

The shared driver requires PowerShell 7.4+ and Git on Windows x64 or Linux x64. Windows
10/11 use MSVC and `winget`; Ubuntu with GCC is the initial Linux provisioning and
test baseline, exercised locally in WSL 2. Other distributions need verified native
tools or manual installation guidance. macOS and Linux GUI apps are not in v1 scope.

`dd init` does not need a compiler to scaffold. `dd toolchain` reports missing tools
and any required elevation; `dd doctor` diagnoses without modifying the machine.
