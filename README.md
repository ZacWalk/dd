# dd — the Dynamic Dispatch Build System

[![Build and test dd](https://github.com/ZacWalk/dd/actions/workflows/ci.yml/badge.svg)](https://github.com/ZacWalk/dd/actions/workflows/ci.yml)

**Create and build C and C++ projects: GUI or CLI apps on Windows, CLI apps and static libraries on Windows and Linux.**

DD is a very simple package manager and build system. Really just a PowerShell script. I
use it for my C++ projects and it makes my life a lot easier.

Underneath is ordinary CMake, Ninja and the native compiler. dd sets up the compiler
environment, configures and builds both configurations, triages diagnostics by file and
by code while keeping the full log, and runs the tests, behind the same commands in every
project. Each project vendors the driver as `dd.ps1` and `.dd/`, like `gradlew`, with its
settings in `dd.psd1` and its dependency pins in `cmake/dd-dependencies.json`. CMake keeps
the build graph.

```powershell
mkdir my-app
cd my-app
dd init         # Choose GUI, CLI or library; scaffold in this folder
dd toolchain    # Install missing compiler and build tools when needed
dd build
```

A clone needs no launcher; its vendored driver runs directly:

```powershell
pwsh -NoProfile -File ./dd.ps1 dep install
pwsh -NoProfile -File ./dd.ps1 toolchain
pwsh -NoProfile -File ./dd.ps1 build
```

## Bootstrap

In **PowerShell 7.4+** (`pwsh`), with Git installed:

```powershell
irm "https://raw.githubusercontent.com/ZacWalk/dd/main/bootstrap.ps1" | iex
```

This downloads and immediately runs the bootstrap script: inspect
[bootstrap.ps1](bootstrap.ps1) first, or download and review it before running it. It
installs the latest published release - the launcher and templates, not a compiler or an
app - after verifying its checksums, and asks before adding `dd` to your PowerShell
profile. Accept to use `dd` now and in future sessions; decline and the installed driver
still runs directly. [implementation.md](docs/implementation.md#releases-and-bootstrap)
describes its options and checks.

dd's own downloads come only from [github.com/ZacWalk/dd](https://github.com/ZacWalk/dd);
compilers and tools come from the OS package providers, and dynamicdispatch.org is not a
download source.

## Try the source checkout

```powershell
pwsh -NoProfile -File ./tools/prepare.ps1
pwsh -NoProfile -File ./dd.ps1 help --json
```

`prepare` validates the runtime and the `dd.psd1` template offline; it installs no
compiler and modifies no profile. To create an app, make an empty folder outside this Git
working tree and run `pwsh -NoProfile -File ./dd.ps1 init --project <folder>`.

## Requirements

PowerShell 7.4+ and Git, on x64 Windows or Linux:

| Host | Toolchain | Projects |
| --- | --- | --- |
| Windows 10 or 11 | MSVC and the Windows SDK, CMake and Ninja, through `winget` | GUI, CLI, library |
| Ubuntu, including WSL 2 | GCC, CMake and Ninja, through apt | CLI, library |

`dd init` needs no compiler; `dd toolchain` installs what is missing, and `dd doctor`
reports it without changing anything ([toolchain.md](docs/toolchain.md)). On other Linux
distributions, install the tools by hand. macOS, Linux GUI apps and ARM64 or 32-bit x86
targets are not supported, and dd's commands and file formats can still change between
releases.

## Documentation

| Document | Subject |
| --- | --- |
| [docs/cli.md](docs/cli.md) | Commands, options and results; `dd init` and its scaffolds; the `dd.psd1` project file |
| [docs/toolchain.md](docs/toolchain.md) | Native toolchains: requirements, `dd toolchain` and the MSVC environment |
| [docs/dependencies.md](docs/dependencies.md) | Pinned CMake dependencies and `dd dep` |
| [docs/extensions.md](docs/extensions.md) | Project commands declared in `dd.psd1` |
| [docs/adoption.md](docs/adoption.md) | Adopting dd in an existing application |
| [docs/mcp.md](docs/mcp.md) | The MCP server |
| [docs/implementation.md](docs/implementation.md) | How the driver works, and how releases are made |
| [docs/design.md](docs/design.md) | The problem, goals and decisions behind dd |

## Developing dd

```powershell
pwsh -NoProfile -File ./tools/prepare.ps1
pwsh -NoProfile -File ./tests/verify.ps1
```

`verify.ps1` runs the regression scripts in `tests/` in order - on Windows also the
compiler-environment check and the GUI check, which opens windows - inside a temp
directory of its own, kept when a script fails. It fails on a script it does not list.
Each script also runs alone; `tests/mcp.ps1 -ProtocolOnly` checks the MCP protocol without
building. Run the Linux tests natively, on Ubuntu or in WSL from the Linux filesystem
rather than a mounted Windows drive. The suite never runs `dd toolchain --yes` or
downloads a real release, so check those on a disposable machine. CI runs both commands on
Windows and Ubuntu, then `tools/package.ps1` and `tests/ci-exit.ps1`, which checks runner
exit codes, the packaged release and bootstrap.

## Licence

[MIT](LICENSE). Every project that vendors dd carries the same licence in `.dd/LICENSE`.
