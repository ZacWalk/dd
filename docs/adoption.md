# Adopting dd in an existing application

dd fits around a working CMake build without rewriting it. Keep application behaviour in
CMake, presets and project-owned scripts; never fork the driver, and never run `init` in
a populated repository. dd migrates nothing automatically.

1. Run `dd adopt --dry-run --project <folder>` from outside the application, so the
   installed driver answers rather than a `dd.ps1` the application may already have. It
   changes nothing, and reports the root's files, any declared dependencies, an existing
   `dd.ps1` whose commands need review before it is replaced, and any declared URL that
   `CMakeLists.txt` also fetches.
2. Vendor dd's `dd.ps1` and `.dd/` unchanged.
3. Write a data-only [`dd.psd1`](cli.md#the-project-file) that names the application's own
   presets, CMake targets and output paths; target IDs need not match executable names.
   Give a target a `test-label` if `--app` should select its tests, declare a library as
   `kind = 'library'` with `{libprefix}` and `{lib}` paths, and point
   `project.default-target` at an executable ([targets](cli.md#targets)).
4. Choose who owns the dependency pins: dd, in `cmake/dd-dependencies.json`, or the
   application's CMake ([ownership](dependencies.md#ownership)). Archive pins and
   `application` recipes let dd own pins while the application keeps special integration.
5. Declare the tools and Visual Studio components the build needs - ATL, say - in
   `requirements` ([toolchain.md](toolchain.md#requirements)).

## Optional Clang Static Analyzer pass

The source checkout's `tools/analyze.ps1` scans sibling repositories that opt in with
`.csa.psd1`, independently of `dd build` and the normal `.clang-tidy` checks. Run from
an x64 Visual Studio developer shell with a full LLVM installation on `PATH`.
The Visual Studio formatting-only LLVM component can omit the builtin `cpuid.h`
needed by DirectXMath; install matching Clang resource headers if using that component.

```powershell
.\dd\tools\analyze.ps1 -List
.\dd\tools\analyze.ps1
.\dd\tools\analyze.ps1 -Project libfiles -FilePattern '*decode_psd.cpp'
```

`Build` in the manifest names a configured Ninja build with
`CMAKE_EXPORT_COMPILE_COMMANDS=ON`; `Paths` lists Git pathspecs such as
`@('src','tests',':!src/imported')`. Allow only owned sources and headers.
The pass intersects those tracked files with the build database, never scans a
dependency tree, and does not modify sources. Included SDK and dependency headers
must still parse. Use `-BuildDir` with one project to analyze a different build.
The printed output directory contains inputs, owned files absent from the build,
per-file traces, deduplicated findings and exit codes. Parse failures fail the run;
analyzer warnings are reported for review, not treated as build failures.

## Phase presets

Each configuration names one preset for every phase, or one for each:

```powershell
build = @{
    'x64-windows' = @{
        debug = @{ configure = 'native-debug'; build = 'compile-debug'; test = 'check-debug' }
        release = @{ configure = 'native-release'; build = 'compile-release'; test = 'check-release' }
        ide = 'visual-studio'
    }
}
```

Build and test presets must reference their mapped configure preset. dd resolves
`include`s, inheritance and conditions to find each preset's build directory, and rejects
a hidden preset or one whose condition excludes the host; CMake still does the work. Path
macros cover the source and file directories, the preset name, the host system name and
environment values. Presets and build directories must stay inside the project, and an
unknown macro or a linked path fails rather than being guessed.

`clean` trusts only the build directory dd recorded at the last configure
([how](implementation.md#configure-and-build)), so reconfigure after changing presets or
the manifest. A tree that configurations share - Ninja Multi-Config, a Visual Studio
generator, or two mappings naming one directory - needs `clean both`: a
single-configuration request never removes another configuration's files.

`dd ide` configures only the declared `ide` preset, which must use a Visual Studio
generator; dd invents no build directory and changes no generator. The scaffold's
`windows-ide` preset leaves the generator to CMake's default, so an existing application
should name the Visual Studio generator it supports.
