# Design Notes

> **Status: design rationale.** An initial shared driver now exists. Current executable
> behavior and limitations are in [implementation.md](implementation.md); this document
> preserves the decisions and migration context behind it.

## The problem

I maintain several open-source C++ Windows applications. The dominant barrier to
contribution is not the code — it is **getting a build to work at all**. Contributors
are mostly Linux or macOS developers who know C++ well and Windows tooling not at all.

A first-time contributor currently has to know, without being told:

- which Visual Studio edition to install, and that Build Tools is enough;
- that the C++ workload and Windows SDK must be selected, with additional components
  such as ATL required only by legacy applications;
- how to acquire reproducible dependency sources after cloning;
- that `cl.exe` only exists inside a `vcvars64.bat` shell, and which of seven possible
  paths that batch file lives at this year;
- that CMake and Ninja are separate installs, and that the CMake bundled inside Visual
  Studio is not on `PATH`;
- which preset to configure, and that a stale `CMakeCache.txt` will keep pointing at a
  compiler that no longer exists;
- how to tell a real error from the several hundred warnings printed above it.

Every one of those is a place a contributor gives up. None of them is interesting.

## The goal

Bootstrap once, then create a new application in its own folder:

```powershell
mkdir my-app
cd my-app
dd init       # Scaffold here; prompt for GUI or CLI
dd toolchain  # Install missing native build tools when needed
dd build
```

Windows supports GUI and CLI scaffolds. Linux supports CLI only until platform-h
gains a supported Linux backend. GUI initialization declares platform-h for FetchContent;
CLI initialization does not. Existing clones use `dep install` to validate pins and
`toolchain` for machine setup, not `init` to recreate the project.

…and the same command surface — `build`, `run`, `test`, `ide`, `clean` — across every
repository I maintain, so that knowledge transfers between them.

## What already works

`imagewalker/dd.ps1` is the working prototype. It is per-repo and hardcoded, but it
already solves the problem for one project. The parts worth generalising:

| Behaviour | Why it matters |
| --- | --- |
| Legacy prerequisite installer (now `dd toolchain`) | Installs CMake, Ninja and VC Build Tools via `winget`. Turns a 20-minute wiki page into one command. |
| `vcvars64.bat` discovery and import | Contributor never learns the words "developer command prompt". |
| Clearing `VSCMD_VER` first | `vcvars64` silently short-circuits if it is already set, leaving a shell with `cl` but no `rc`. |
| Stale-cache detection | A `CMakeCache.txt` pointing at a deleted Ninja is a baffling failure; detect and discard it. |
| `ninja -k 0` | One run reports every error instead of only the first. |
| Grouping diagnostics **by file and by code** | 380 warnings in one header is five lines of work; 412 of one code is one struct field. The raw list hides both. |
| Full log kept in temp | Summaries are lossy on purpose; the detail must still be reachable. |
| GUI smoke test | These apps have no meaningful CLI. "Starts, opens a window, stays up, leaves no crash report" is the real regression signal. |
| Redirecting stdout to a file for tests | `/SUBSYSTEM:WINDOWS` apps get no inherited stdout, so piped output is always empty. |
| Building debug **and** release | A debug-only compiler ICE went unnoticed for a release because only release was built. |

Generalising this — same script, per-repo configuration — is the whole product.

New GUI applications use [platform-h](https://github.com/ZacWalk/platform-h), not WTL or
ATL. app-galactica provides useful app-owned CMake integration. Each library has one
acquisition owner; CMake FetchContent/ExternalProject acquires sources from declared pins.
The proposed ownership contract is in [dependencies.md](dependencies.md).

## Goals

1. **Simple project creation.** Bootstrap, create a folder, run `dd init`, choose GUI
  or CLI. Machine setup is a separate `dd toolchain` command.
2. **User-level bootstrap, project-pinned driver.** The launcher and templates install
  without machine-wide changes; each app vendors its driver, like `gradlew`. Toolchain
  installation may require elevation; scaffolding and dependency restores do not.
3. **Identical surface across repositories.** Differences live in `dd.psd1`, never in
   the script.
4. **Readable failure.** Errors are triaged and summarised, not dumped.
5. **CI parity.** The command a contributor runs locally is the command CI runs.
6. **Reproducible source dependencies.** `dd dep` manages pinned CMake declarations;
  CMake acquires sources and updates are deliberate, reviewable data changes.
7. **Native CLI portability.** Windows and Linux CLI apps share the scaffold contract.
  WSL 2 Ubuntu provides the initial local Linux test environment.

## Non-goals

- Replacing CMake. `dd` owns the *environment* and the *diagnostics*, not the build graph.
- A hosted package registry, binary package cache or version-range solver. A small
  name-to-repository catalog and CMake dependency declarations are in scope.
- Cross-compilation or a bundled MinGW toolchain in v1. Use MSVC on Windows and
  initially GCC on Ubuntu Linux. See Decision 1.
- Linux GUI apps before platform-h has a Linux backend; macOS apps in v1. See Risk 3.

---

## Decisions

### Decision 1 - Use native toolchains on Windows and Linux

platform-h currently has a Win32/MSVC backend, and app-galactica's CMake build requires
Windows x64 and MSVC. This is the GUI baseline. Choosing platform-h replaces
the legacy app framework, not the compiler or Windows SDK.

`dd toolchain` acquires MSVC with `winget`; `dd` locates `vcvars64.bat` and imports the
environment itself. ATL and MFC remain opt-in project requirements for legacy apps,
not dependencies of the GUI scaffold. WTL is a separate source library.

Linux CLI apps use the native compiler and CMake/Ninja, initially GCC on Ubuntu.
They do not need platform-h, MSVC or a Windows SDK. `dd toolchain` selects the native
host provider; neither `init` nor `build` installs system packages implicitly.

An earlier bundled LLVM + MinGW-w64 proposal is deferred, not a requirement for the
new scaffolder. Additional platform-h backends or compiler support would need their
own validation. See [toolchain.md](toolchain.md).

### Decision 2 — `dd.ps1` is vendored per repository, like `gradlew`

The script is committed to each repo. A contributor clones and runs it. There is
no global launcher requirement for an existing clone: PowerShell 7 can run the
vendored script directly. Bootstrap supplies the user-level launcher and templates
for new-project creation. It does not override an existing project's pinned driver.

The cost is N copies to keep in sync. Each carries a version stamp. User-level
`dd self-update` installs a verified side-by-side release from GitHub, but does not
overwrite a project's pinned runtime. Updating a vendored runtime is a reviewed
project change. No downloads depend on dynamicdispatch.org.

### Decision 3 — Project-specific driver settings live in `dd.psd1`

In the ImageWalker prototype the version list `10 20 22 23 30`, the `imagewalker$ver.exe`
naming rule, `IW_OUTPUT_DIR`, the `/test` argument and the crash-report glob are all
hardcoded. Those become manifest data so the script itself is byte-identical across
repositories. Schema in [cli.md](cli.md).

Use a native PowerShell data file and `Import-PowerShellDataFile`. This replaces the
earlier TOML proposal without a parser dependency or loss of comments. Load data, not
executable scripts. Schema 1 defines native presets and target paths; legacy fields
remain migration context, not automatically supported settings. The JSON schema
describes the loaded model; CLI and MCP results remain JSON. See
[implementation.md](implementation.md#manifest).

### Decision 4 — CMake and Ninja stay; `dd` owns the environment and the output

`dd init` generates starter CMake files, but the runtime driver does not maintain a
parallel build graph. Projects keep ownership of their `CMakeLists.txt` and
`CMakePresets.json`. What `dd` contributes is everything around that: prerequisite
installation, environment setup, cache hygiene, diagnostic triage, test orchestration,
and one uniform CLI.

These are existing projects with working CMake builds. Replacing that buys nothing and
risks everything.

### Decision 5 — Diagnostic triage is a feature, not output formatting

A build that emits 800 warnings communicates nothing. The same build grouped by file
and by code communicates *where the work is*: 380 warnings concentrated in one header
are five lines to fix, and 412 instances of one code are usually one declaration. Both
facts are invisible in a linear log and neither is discoverable by a newcomer.

`dd` therefore summarises by default and keeps the full log on disk for follow-up.

### Decision 6 - Tests follow the application type

CLI templates use CTest and command-line checks with bounded execution and asserted
exit codes and output. They never require a desktop session. GUI targets additionally
get window smoke tests: starts, opens a window, stays up, and leaves no crash report.
These currently run on Windows only. Required behaviours are in [cli.md](cli.md).

### Decision 7 — Name the platform from the start

Native platform IDs are `x64-windows` and `x64-linux`. New scaffold build trees use
`build/<platform>/<config>/` so Windows and WSL never share incompatible CMake caches.
`--target` defaults to the host and rejects unsupported cross-target requests. Existing
apps retain the build paths in their own presets during adoption.

### Decision 8 - CMake owns dependency acquisition

Use `include(FetchContent)` and `include(ExternalProject)`.
`dd dep install [name]` validates or adds entries in `cmake/dd-dependencies.json`.
That file records URLs, full commit IDs and methods without duplicating them in
PSD1. PowerShell and CMake both parse it natively. Pin updates change
only declarations; no staging, checkouts, automatic commits or source resets.

FetchContent integrates libraries at configure time; ExternalProject builds and
installs standard CMake projects separately. App-specific linking remains CMake's
responsibility. Sources and outputs are cached by revision under each build tree;
updates do not overwrite old source edits. Existing legacy checkouts are preserved
for explicit migration. See [dependencies.md](dependencies.md).

### Decision 9 - Init scaffolds GUI or CLI in the current folder

After bootstrap, users create and enter a folder and run `dd init`. It prompts for
GUI or CLI and defaults the name to the folder name. `--type`, `--name`, `--dry-run`
and `--non-interactive` provide the same deterministic workflow for agents. Validate
all choices and destination conflicts before writes; Linux GUI requests fail before
scaffolding or fetching. Never scaffold in an ancestor discovered by the launcher.

Both versioned templates generate a driver, manifest, CMake, presets, source and tests.
GUI declares platform-h at a tested pin via the dependency commands and generates its
callbacks and `platform_add_app()` integration. CLI generates a portable `main` with
CTest and no default source dependencies. Linux GUI remains unavailable until the
planned platform-h backend is implemented and validated.

`dd toolchain` installs missing native build prerequisites. It is intentionally
separate from scaffolding, is idempotent, and can run before or after `init`.
Legacy scripts that call installation `init` must be identified during adoption.

An AI agent selects and invokes the same deterministic template and dependency
commands a human uses, then builds and tests the result. Adopting an existing app is
a preview-and-review workflow that preserves its CMake and reports conflicting
dependency acquisition rather than silently replacing it.

### Decision 10 - Bootstrap and command routing

Bootstrap installs a versioned launcher and templates in user-owned storage. It
does not create an app or install a compiler. Downloads must be verified before
activation, with no partial release exposed to users. The shared runtime requires
PowerShell 7; bootstrap must detect it or provide installation guidance rather than
assuming it exists on Windows PowerShell 5.1 or Linux.

PowerShell integration adds an idempotent, marked loader block to the selected user's
profile with consent, preserving unrelated content and reporting an existing `dd`
function conflict. No global execution-policy change, automatic elevation or profile
replacement is permitted. Shell integration and machine toolchains are separate.

The launcher handles `init` in the current folder before project discovery, including
the populated-folder refusal. Other project commands may resolve the nearest trusted
vendored driver by walking upward; when none exists, the installed driver can serve
help, `init`, `adopt` and `toolchain`. Project-only commands report a missing project
without changing directory. Do not silently translate legacy driver commands.

On Unix, `dd` is already a system utility. Bootstrap must disclose that collision and
require explicit opt-in before adding a shell function with that name; it never
replaces the system executable. Direct `pwsh -NoProfile -File /path/to/dd.ps1 ...`
invocation remains available without shell changes. This naming concern does not
change the `init`/`toolchain` semantics.

### Decision 11 - AI integration is local to each generated project

All CLI commands provide versioned JSON results and non-interactive behavior. The
optional MCP adapter is pure PowerShell 7.4+ and calls the same runtime. It implements
the stdio protocol with built-in JSON and process APIs, without third-party packages.
Both templates include `.vscode/mcp.json` and `AGENTS.md`; each app uses its own
vendored adapter, not a globally registered MCP server. It is scoped to its workspace
and requires explicit execution enablement for build/test/run/launch. Protocol framing,
cancellation and tool parity are checked by the PowerShell test harness. Compiler
installation and arbitrary shell commands are not MCP tools.

### Decision 12 - Declare project commands without overriding the driver

Use optional `commands` metadata in the PSD1 manifest for project-owned scripts.
dd validates parameters, confirms write operations, invokes an isolated PowerShell
process with JSON input/output, and propagates errors/timeouts. Built-in command names
are reserved. Discovery and script execution do not depend on CMake or a compiler;
native build commands perform their own host checks.

Multiple apps remain target entries, with an optional default target and explicit
selection in automation when otherwise ambiguous. `targets` exposes metadata and can
add missing F5 launch entries with explicit consent. CMake owns target build logic.
Automatic lifecycle hooks and a general plugin framework are deliberately deferred.
MCP exposes discovery and a generic declared-command tool, with project-code execution
opt-in even for previews. See [extensions.md](extensions.md) for details.

---

## Risks and open questions

### Risk 1 — Visual Studio version drift

The prototype hardcodes seven candidate `vcvars64.bat` paths, one of which is a
specific VS 18 Enterprise install. This list rots with every VS release. Use
`vswhere.exe` — it ships at a fixed location under `%ProgramFiles(x86)%` and is the
supported discovery mechanism — with the hardcoded list only as a fallback.

Related: the prototype prefers the CMake bundled inside Visual Studio, whose path also
embeds the edition and version. Same fix.

### Risk 2 — `winget` is not always available or permitted

Absent on older Windows 10, on some LTSC images, and frequently blocked by corporate
policy. Windows `dd toolchain` must fail with instructions rather than a stack trace, and
`dd doctor` should report exactly what is missing and how to install it by hand.

### Risk 3 - Linux GUI support is not yet available

Linux CLI support does not imply Linux GUI support. platform-h's Linux backend is
planned; `init --type gui` must fail on Linux until a tested backend and template
exist. WSLg is not a replacement for that backend. Test native CLI scaffolds locally
on WSL 2 Ubuntu's Linux filesystem, including case sensitivity, executable permissions,
spaces in paths, clean-clone dependency pins and operation without profiles. Add native
Ubuntu CI rather than claiming WSL proves every Linux distribution is supported.

### Risk 4 — PowerShell version and execution policy

The shared driver targets PowerShell 7 on both Windows and Linux. Bootstrap must
handle the initial absence of that runtime with clear guidance. Windows execution
policy may block downloaded scripts; document trust and signing requirements without
silently weakening policy. Runtime and shell setup need separate clean-machine tests
from the native compiler setup handled by `dd toolchain`.

### Risk 5 — Naming collisions

*Dynamic dispatch* is an established C++ term for virtual calls, and `dd` shadows the
long-standing Unix utility that anyone using Git Bash, MSYS2 or WSL will have. Neither
is fatal; both are cheaper to reconsider now than after the domain content is written.

### Open question — how much should `dd` know about CMake?

The initial driver always reconfigures and leaves CMake to diagnose incompatible
caches. Explicit cleanup is limited to recognized generated build trees, with path
and tracked-file checks and user authorization. More elaborate repair can come later.

---

## Document map

| Document | Contents |
| --- | --- |
| design.md (this file) | Problem, goals, decisions, risks |
| [cli.md](cli.md) | Command surface, `dd.psd1` schema, required behaviours |
| [dependencies.md](dependencies.md) | CMake dependency ownership, pinning, migration and agent workflow |
| [extensions.md](extensions.md) | Project-owned commands, multi-app targets, script protocol and trust model |
| [toolchain.md](toolchain.md) | Toolchain acquisition, MSVC discovery, the bundled-LLVM alternative |