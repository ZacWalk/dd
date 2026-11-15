# Design

Why dd is built the way it is. What it does is in the documents the
[README](../README.md#documentation) lists.

## The problem

I maintain several open-source C++ Windows applications. The barrier to contributing is
not the code — it is **getting a build to work at all**. Contributors are mostly Linux or
macOS developers who know C++ well and Windows tooling not at all, and a first-time
contributor has to know, without being told:

- which Visual Studio edition and components to install, and that Build Tools is enough;
- that `cl.exe` exists only inside a `vcvars64.bat` environment;
- that CMake and Ninja are separate installs;
- how to get reproducible dependency sources after cloning;
- which preset to configure, and that a stale `CMakeCache.txt` can keep pointing at a
  compiler that no longer exists;
- how to tell a real error from the several hundred warnings printed above it.

Every one of those is a place a contributor gives up. None of them is interesting.

## Goals

1. **Simple project creation.** Bootstrap once, then `dd init` in an empty folder; machine
   setup is the separate `dd toolchain`.
2. **User-level bootstrap, project-pinned driver.** Installing dd changes nothing
   machine-wide, and each project vendors its own driver.
3. **One surface everywhere.** Projects differ in `dd.psd1`, never in the script.
4. **Readable failure.** Errors are triaged and summarized, and the full log is kept.
5. **CI parity.** CI runs the command a contributor runs.
6. **Reproducible dependencies.** Pins are reviewed data, and CMake acquires sources.
7. **Native portability.** CLI apps and libraries build natively on Windows and Linux.

## Non-goals

- Replacing CMake: dd owns the environment, the diagnostics and the command surface, not
  the build graph.
- A package registry, binary cache or version solver: a small catalog of names and URLs
  and pinned CMake declarations are enough.
- Cross-compilation or a bundled compiler: dd drives the host's native toolchain.
- A plugin framework or lifecycle hooks: projects declare commands instead.

## Decisions

1. **Native toolchains.** MSVC on Windows and GCC on Linux, located and driven by dd rather
   than shipped: the Microsoft toolchain is not redistributable, and the GUI template and
   applications that use ATL or MFC need it ([toolchain.md](toolchain.md)).
2. **A vendored driver, like `gradlew`.** Each project commits `dd.ps1` and `.dd/`, so a
   clone needs no dd installation, and the copy records the driver the project was
   verified with. The cost is one copy per repository, updated by a reviewed change.
3. **Settings in a PowerShell data file.** `Import-PowerShellDataFile` is native on every
   host, allows comments and runs no code, so there is no parser to ship. Machine data -
   pins, presets, results - stays JSON ([cli.md](cli.md#the-project-file)).
4. **CMake keeps the build.** Projects own `CMakeLists.txt` and `CMakePresets.json`, and dd
   contributes what surrounds them: replacing working builds buys nothing and risks
   everything.
5. **Diagnostic triage is a feature.** A build that prints 800 warnings says nothing;
   grouped by file they show where the work is - a header included everywhere can account
   for hundreds of lines - and grouped by code what kind it is - hundreds of one code are
   usually one declaration. dd summarizes by default and keeps the log
   ([implementation.md](implementation.md#configure-and-build)).
6. **Tests follow the application type.** CLI checks never need a desktop. A GUI app often
   has no meaningful command line, so starting, opening a window, staying up and leaving
   no crash report is its real regression signal ([cli.md](cli.md#building-and-testing)).
7. **Platform-named build trees.** `build/<platform>/<configuration>` keeps Windows and WSL
   from sharing incompatible CMake caches.
8. **CMake acquires dependencies.** dd edits pins in one JSON file, which PowerShell and
   CMake both read natively and which is both list and lock; FetchContent and
   ExternalProject fetch and build ([dependencies.md](dependencies.md)).
9. **Scaffolding is not provisioning.** `init` writes a project and installs nothing;
   `toolchain` installs tools and writes no source, and either can run first. A library
   scaffold includes an example CLI, so the repository is runnable and testable from its
   first build ([cli.md](cli.md#initialization)).
10. **A user-level launcher.** Bootstrap installs verified releases side by side and edits
    the profile only with consent, without elevation; the launcher defers to a project's
    own driver. On Unix `dd` is already a system utility, so the function is opt-in and
    never replaces it ([implementation.md](implementation.md#releases-and-bootstrap)).
11. **AI integration is local to each project.** Every command has a JSON result and a
    non-interactive mode, and each project's own driver serves MCP, scoped to its
    workspace, with project code execution opt-in ([mcp.md](mcp.md)).
12. **Project commands are declared, not forked.** A project adds scripts through
    `commands` metadata; dd validates, confirms and runs them in a separate process, and
    built-in names are reserved ([extensions.md](extensions.md)).
