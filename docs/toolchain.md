# The Toolchain

> **Status: design background.** Native provisioning and checks are implemented; see
> [implementation.md](implementation.md) for verified behavior and limitations.
> Native MSVC on Windows and GCC on Ubuntu
> Linux are the initial targets (see
> [design.md](design.md#decision-1---use-native-toolchains-on-windows-and-linux)).
> The bundled LLVM/MinGW profile below is historical and deferred, not Linux CLI support.

"Toolchain" here means the compiler, linker, standard library, platform SDK, and build
engine — everything `dd` needs and a contributor should never have to think about.

## Command contract

`dd toolchain` installs missing native build prerequisites; `dd init` scaffolds the
project. Bootstrap installs the launcher and templates. These are three separate
operations: neither bootstrap nor init installs a compiler, and toolchain never
creates or rewrites app source. `dd doctor` is the read-only environment check.

With a project, verify its native toolchain requirements; without one, use the host
default. Detect already usable tools and report no changes when requirements are met.
Before installation, report what is missing and any privilege or package-manager
requirements. Never hide an elevation/password prompt in automation or collect secrets
through an agent. Where installation is unavailable, provide commands for the user to
run themselves and stop. Do not change dependency pins or profile files.

| Host / app | Initial toolchain | App support |
| --- | --- | --- |
| Windows x64 | MSVC, Windows SDK, CMake, Ninja | GUI via platform-h; native CLI without it |
| Ubuntu Linux x64 (including WSL 2) | GCC with C++20 support, CMake, Ninja | Native CLI only; no Windows SDK or platform-h required |

The driver requires PowerShell 7 and Git, checked independently of the compiler.
Toolchain selection is native; invoking Windows tools from WSL is not Linux CLI
validation. GUI Linux support is planned after the platform-h backend exists.

Schema 1 supports `requirements.tools` with minimum versions, optional checks and
platform filters, plus `requirements.msvc.minimum` (Visual Studio version) and
component IDs. Build, doctor, installation planning and post-install verification use
the same merged requirements. Required defaults cannot be lowered or made optional.
Optional failures are warnings and do not trigger package installation. Supported
tool providers are CMake, CTest, Ninja, Git, GCC, Python and GDB; no project-defined
probe script is executed. See [adoption.md](adoption.md) for examples.

Default minima are CMake/CTest 3.24, Ninja 1.10, Git 2.20, GCC 10 on Linux, and Visual
Studio 17 with x64 C++ tools on Windows. The compiler environment must also expose
`cl`, `link` and `rc`. Existing Visual Studio installations can be modified to add
required components; a successful package-manager result never skips verification.
Providers cannot guarantee arbitrary minimum versions are available in OS repositories.

---

## Profile 1 — System MSVC (Windows)

`dd` does not ship a compiler. `dd toolchain` installs the Microsoft toolchain and then
build commands drive it. platform-h currently targets Win32/MSVC, and app-galactica
requires Windows x64 and MSVC. New GUI scaffolds use platform-h; ATL and MFC are
optional components for legacy applications, not default prerequisites.

Source libraries such as platform-h are declared through `dd dep` and acquired by
CMake FetchContent/ExternalProject, not installed with `winget`. WTL, when needed by a legacy
application, is also a separate source library. See [dependencies.md](dependencies.md).

### Acquisition (`dd toolchain` on Windows)

Via `winget`, with prerequisite installation requiring elevation when needed:

| Package | Notes |
| --- | --- |
| `Microsoft.VisualStudio.BuildTools` | With `--override "--passive --wait --add Microsoft.VisualStudio.Workload.VCTools --includeRecommended"`. Build Tools is sufficient; the full IDE is not required. |
| `Kitware.CMake` | The CMake bundled inside VS is not on `PATH`, and its location embeds the edition and version. |
| `Ninja-build.Ninja` | |

Two details that are easy to get wrong:

- **Legacy ATL projects need an explicit component.**
  `Microsoft.VisualStudio.Component.VC.ATL` is not covered by `--includeRecommended`.
  Request it only when the project's manifest needs it; a platform-h app does not.
- **winget's "no applicable upgrade" result (`0x8A15002B`) is not fatal**, but does not
  prove the required components exist. Verify the compiler, SDK and requested optional
  components afterwards; an up-to-date installation may still need modification.

### Discovery and environment

The compiler only exists inside the environment that `vcvars64.bat` sets up. `dd`
imports that environment into its own process so the contributor never has to open a
"Developer Command Prompt".

- Locate the installation with `vswhere.exe`, which lives at a fixed path under
  `%ProgramFiles(x86)%\Microsoft Visual Studio\Installer`. A hardcoded list of
  `vcvars64.bat` candidates is a fallback only — it rots with every VS release.
- **Clear `VSCMD_VER`, `VSCMD_ARG_TGT_ARCH` and `VSCMD_ARG_HOST_ARCH` first.**
  `vcvars64.bat` silently short-circuits when `VSCMD_VER` is already set, producing a
  half-configured shell with `cl.exe` present and `rc.exe` absent. The failure appears
  much later, in the resource compile, and looks nothing like its cause.
- Import by running `cmd /c "vcvars64.bat >nul && set"` and copying the result into the
  process environment.
- **Verify afterwards** that `cl.exe`, `link.exe` and SDK tools such as `rc.exe` resolve.
  A zero exit code from the batch file is not evidence that it worked.
- Do this once per process and cache it.

### What this profile costs

- A large first-run install (~2–7 GB depending on components) that `dd` cannot avoid.
- A dependency on `winget`, which is absent on older Windows 10 and frequently blocked
  by corporate policy. `dd doctor` must degrade to printing manual instructions.
- Nothing is redistributable, so there is no "download one archive" story. Given
  Decision 1, that story was never available anyway.

---

## Native Linux CLI toolchain

The initial provisioning provider targets Ubuntu, including Ubuntu under WSL 2. Use
the distribution's native GCC and C++ standard library, CMake, CTest and Ninja. Detect
the distribution and versions before selecting package-manager actions; initial
package candidates are `build-essential`, `cmake` and `ninja-build`. Check that the
installed versions satisfy the generated project's requirements rather than treating
package installation alone as readiness. Unsupported distributions get actionable
manual instructions, not a guessed `apt` invocation.

Linux provisioning uses the normal package manager with the user's authorization.
When root privileges are required and unavailable, report the exact elevated commands
for the user to run; do not launch an unattended password prompt. If tools are already
usable, `dd toolchain` succeeds without installing anything.

CLI scaffolds use ordinary C++ `main`, native binaries and CTest. They do not run
`vcvars64.bat`, enable Windows resource compilation, use `.exe` naming on Linux, or
require a GUI backend. Keep generated build trees separate by native platform and
configuration. Additional libraries must themselves support the selected platform.

Validate locally in WSL 2 Ubuntu under the Linux home directory, not only a mounted
Windows drive. Cover a fresh CLI scaffold, Debug and Release builds, CTest, dependency
restore and argument forwarding from paths with spaces. Native Ubuntu CI supplements
WSL coverage. No Linux GUI build is claimed until platform-h's Linux backend is ready.

---

## Profile 2 — Bundled LLVM + MinGW-w64 (deferred)

Fully self-contained and fully redistributable: one archive, extract and go, no
Microsoft install, no licence acceptance, and it cross-compiles from Linux and macOS.
Essentially a repackaging of [llvm-mingw](https://github.com/mstorsjo/llvm-mingw) plus
Ninja and CMake.

**It cannot replace MSVC for the legacy ATL/MFC applications.** New platform-h GUI apps
currently have a supported Win32/MSVC backend; a MinGW profile would need separate
validation rather than assuming framework replacement makes the compiler interchangeable.

Where it could still earn its place:

- New, portable, non-ATL code — libraries, console tools, test harnesses.
- A Linux/macOS "does it still compile" pre-PR check for the portable subset of a
  codebase, giving non-Windows contributors a fast local signal.

If pursued, it would be selected per project with `toolchain.kind = "llvm"` in
`dd.psd1`, and would live in a versioned cache:

```
%LOCALAPPDATA%\dd\
├── toolchains\
│   └── 1.0.0-x86_64-windows-gnu\   # Immutable once written
└── downloads\                      # Verified archives, kept for offline re-extract
```

A toolchain directory must be written to a temp path, verified, then atomically
renamed. A half-extracted toolchain that is observable produces failures nobody can
diagnose.

### Comparison

| | Profile 1 (system MSVC) | Profile 2 (bundled LLVM) |
| --- | --- | --- |
| **ATL / WTL / MFC / COM** | **Yes** | **No** |
| Redistributable as one archive | No | Yes |
| First-run download | ~2–7 GB | ~150 MB |
| Prebuilt vendor `.lib` files | Compatible | Incompatible |
| Debug info | Native PDB | DWARF; PDB support needs verification |
| Existing `.sln` / MSBuild projects | Compatible | Cannot consume |
| Cross-compile from Linux/macOS | No | Yes |
| Licence acceptance required | Yes | No |

---

## Profile 2 package contents

Recorded for completeness should Profile 2 be revisited. Corrections from the original
draft are called out below the tree.

```text
1.0.0-x86_64-windows-gnu/
├── VERSION                             # Toolchain version, target triple, build date
├── MANIFEST.sha256                     # Hash of every file, for integrity checks
├── LICENSE-TOOLCHAIN.txt               # Aggregated upstream licences
├── toolchain.cmake                     # For CMake delegation only
│
├── bin/
│   ├── dd.exe                          # The driver
│   ├── clang.exe                       # Compiler driver
│   ├── clang++.exe                     # Alias to clang.exe
│   ├── ld.lld.exe                      # Linker (MinGW driver)
│   ├── lld-link.exe                    # Linker (PE/COFF driver)
│   ├── llvm-ar.exe                     # Static archiver
│   ├── llvm-ranlib.exe                 # Archive index generator
│   ├── llvm-dlltool.exe                # Import library generation - required for DLLs
│   ├── llvm-rc.exe                     # Resource compiler (.rc -> .res)
│   ├── llvm-windres.exe                # GNU-compatible resource driver
│   ├── llvm-objcopy.exe                # Binary/symbol utility
│   ├── llvm-strip.exe                  # Symbol stripping for release builds
│   ├── llvm-nm.exe                     # Symbol listing
│   ├── llvm-objdump.exe                # Disassembly and PE inspection
│   ├── llvm-symbolizer.exe             # Crash-dump and sanitizer symbolication
│   ├── clang-format.exe                # Backs `dd fmt`
│   ├── clang-tidy.exe                  # Backs `dd check --lint`
│   ├── ninja.exe                       # Build engine
│   ├── cmake.exe                       # Only used for CMake delegation
│   ├── ctest.exe
│   ├── libc++.dll                      # Shared-runtime builds only
│   ├── libunwind.dll                   # Shared-runtime builds only
│   └── libwinpthread-1.dll             # Shared-runtime builds only
│
├── include/
│   ├── c++/v1/                         # libc++ headers
│   └── x86_64-w64-windows-gnu/         # MinGW-w64 Win32 + UCRT headers
│
├── lib/
│   ├── clang/<version>/
│   │   ├── include/                    # Compiler intrinsics (immintrin.h, ...)
│   │   └── lib/windows/
│   │       ├── libclang_rt.builtins-x86_64.a
│   │       ├── libclang_rt.asan-x86_64.a       # `dd build --sanitize=address`
│   │       └── libclang_rt.profile-x86_64.a    # `dd test --coverage`
│   │
│   └── x86_64-w64-windows-gnu/
│       ├── crt2.o                      # Executable entry point
│       ├── dllcrt2.o                   # DLL entry point
│       ├── libkernel32.a               # Win32 import libraries
│       ├── libucrt.a                   # UCRT import library (see note below)
│       ├── libucrtapp.a
│       ├── libc++.a                    # Static C++ standard library
│       ├── libc++abi.a                 # Static C++ ABI / RTTI
│       ├── libunwind.a                 # Static unwinder (SEH)
│       ├── libwinpthread.a             # Threading - required by libc++
│       ├── libc++.dll.a                # Import libraries for the shared runtime
│       ├── libunwind.dll.a
│       └── libwinpthread.dll.a
│
└── share/cmake-<version>/              # CMake platform modules
```

### Notes on contents

- **`clang-cl.exe` is deliberately absent.** It targets the MSVC ABI
  and cannot function against a MinGW sysroot. Shipping it invites confusing failures.
- **`llvm-dlltool` and `libwinpthread` are not optional.** The former is required for
  any DLL producing an import library; the latter is a hard dependency of libc++'s
  threading support and is easy to omit until `std::thread` fails to link.
- **LLDB and the sanitizer runtimes are candidates for a separate optional component**
  fetched by `dd toolchain install --with lldb`, to keep the base download small.

---

## Runtime linking modes (Profile 2)

The two modes are named **`static`** and **`shared`**. The word *dynamic* is avoided
throughout: it collides with the product name and with C++'s meaning of the term.

| Attribute | `static` (default) | `shared` |
| --- | --- | --- |
| C++ standard library | Embedded from `libc++.a` | `libc++.dll` |
| Exception unwinding | Embedded from `libunwind.a` | `libunwind.dll` |
| Threading | Embedded from `libwinpthread.a` | `libwinpthread-1.dll` |
| C runtime | `ucrtbase.dll` (OS-provided) | `ucrtbase.dll` (OS-provided) |
| Hello-world `.exe` size | ~600 KB – 1.8 MB | ~20 KB – 50 KB |
| Ship alongside the `.exe` | Nothing | `libc++.dll`, `libunwind.dll`, `libwinpthread-1.dll` |
| Passing `std::string`/`vector` across DLL boundaries | Unsafe | Safe, if all modules use the same toolchain build |

> **There is no such thing as a statically linked UCRT under MinGW.** `libucrt.a` is an
> *import library* for `ucrtbase.dll`. Every binary this toolchain produces depends on
> `ucrtbase.dll`, `kernel32.dll`, and the `api-ms-win-crt-*` set. The correct claim is
> **"no redistributable DLLs beyond OS-provided components"**, not "zero DLL
> dependencies". Windows 10 1703+ and Windows 11 ship UCRT in the box.

Static linking has a second, subtler cost: with `libc++abi` statically linked into
multiple modules, RTTI type identity is per-module. Exceptions and `dynamic_cast`
across a DLL boundary may not behave as expected. Projects that throw across module
boundaries should use `shared`.

### Driver invocations

Static:

```powershell
clang++ --target=x86_64-w64-windows-gnu `
    -stdlib=libc++ -rtlib=compiler-rt -unwindlib=libunwind `
    -fuse-ld=lld -static `
    main.cpp -o app.exe
```

Shared:

```powershell
clang++ --target=x86_64-w64-windows-gnu `
    -stdlib=libc++ -rtlib=compiler-rt -unwindlib=libunwind `
    -fuse-ld=lld `
    main.cpp -o app.exe
```

`-static-libgcc` is a GCC compatibility flag and is not the right spelling here;
`-rtlib=compiler-rt -unwindlib=libunwind` is.

---

## `toolchain.cmake` (Profile 2)

Profile 1 needs no toolchain file: once the MSVC environment is imported, CMake finds
`cl.exe` on its own. Profile 2 would need one, passed as `CMAKE_TOOLCHAIN_FILE` during
configure. Recorded here with the corrections that the original draft needed.

```cmake
cmake_minimum_required(VERSION 3.20)

# Deliberately NOT setting CMAKE_SYSTEM_NAME when host and target are both Windows.
# Doing so sets CMAKE_CROSSCOMPILING=TRUE, which disables try_run() and breaks the
# configure step of many third-party projects.

get_filename_component(DD_ROOT "${CMAKE_CURRENT_LIST_DIR}" ABSOLUTE)
set(DD_BIN "${DD_ROOT}/bin")

set(CMAKE_C_COMPILER   "${DD_BIN}/clang.exe")
set(CMAKE_CXX_COMPILER "${DD_BIN}/clang++.exe")
set(CMAKE_AR           "${DD_BIN}/llvm-ar.exe")
set(CMAKE_RANLIB       "${DD_BIN}/llvm-ranlib.exe")
set(CMAKE_RC_COMPILER  "${DD_BIN}/llvm-rc.exe")

# Structured variables rather than embedding --target/--sysroot in a flags string,
# which breaks on paths containing spaces.
set(CMAKE_C_COMPILER_TARGET   "x86_64-w64-windows-gnu")
set(CMAKE_CXX_COMPILER_TARGET "x86_64-w64-windows-gnu")
set(CMAKE_SYSROOT             "${DD_ROOT}")

set(DD_RUNTIME "static" CACHE STRING "static | shared")

if(DD_RUNTIME STREQUAL "static")
    set(DD_RUNTIME_FLAGS "-static")
else()
    set(DD_RUNTIME_FLAGS "")
endif()

# *_INIT applies only on the first configure of a build directory; that is intended.
set(CMAKE_C_FLAGS_INIT   "-fuse-ld=lld -rtlib=compiler-rt ${DD_RUNTIME_FLAGS}")
set(CMAKE_CXX_FLAGS_INIT "-fuse-ld=lld -rtlib=compiler-rt -unwindlib=libunwind -stdlib=libc++ ${DD_RUNTIME_FLAGS}")

set(CMAKE_FIND_ROOT_PATH "${DD_ROOT}")
set(CMAKE_FIND_ROOT_PATH_MODE_LIBRARY ONLY)
set(CMAKE_FIND_ROOT_PATH_MODE_INCLUDE ONLY)
set(CMAKE_FIND_ROOT_PATH_MODE_PACKAGE ONLY)
# PROGRAM is left at the default: projects legitimately need to find git, python, etc.
```

---

## Versioning and integrity (Profile 2)

- Toolchain versions are `MAJOR.MINOR.PATCH` and independent of the `dd` CLI version.
  A project would pin one in `dd.psd1`; the shim would install it on demand.
- Every release publishes `MANIFEST.sha256` and a detached signature. The bootstrap
  script verifies the archive hash **before** extraction, and refuses to proceed on a
  mismatch. This is a security-critical path, like driver bootstrap and updates — a compromised
  toolchain download is arbitrary code execution on every contributor's machine.
- Any future archives would be served over HTTPS from GitHub Releases with an immutable,
  content-addressed path so mirrors and corporate proxies can cache them safely.
- `dd toolchain verify` re-checks an installed toolchain against its manifest.

---

## Licensing and compliance

Ship a single `LICENSE-TOOLCHAIN.txt` containing these blocks verbatim.

| Component | Upstream | Licence | Redistribution terms |
| --- | --- | --- | --- |
| Clang, LLD, LLVM utilities | LLVM Project | Apache 2.0 with LLVM Exception | Retain licence text; binary redistribution permitted without source disclosure |
| libc++, libc++abi, libunwind, compiler-rt | LLVM Project | Apache 2.0 with LLVM Exception | The LLVM Exception removes any attribution requirement on binaries that merely link the runtime |
| MinGW-w64 headers and CRT stubs | MinGW-w64 | Public Domain / ZPL 2.1 | Permissive, non-copyleft |
| winpthreads | MinGW-w64 | MIT / BSD | Retain notice; **applies to shipped binaries** when linked statically |
| CMake | Kitware | BSD 3-Clause | Include copyright notice |
| Ninja | Ninja Authors | Apache 2.0 | Include copyright notice |
| MSVC CRT, Windows SDK (Profile 1) | Microsoft | Visual Studio licence terms | **Not redistributable.** Acquired by the end user under their own acceptance of the terms — which is why `dd toolchain` runs `winget` rather than shipping anything. |

`dd licenses` should emit the aggregate attribution text for a built binary, so that
downstream projects can satisfy their own obligations without research.

---

## Technical considerations

- **ABI stability across modules.** With `shared`, every DLL and plugin must be built
  against the same `libc++.dll` release. libc++ makes no cross-version ABI guarantee.
  `dd` should record the toolchain version in a build-id section so mismatches can be
  diagnosed rather than crashing.
- **SEH.** On x86-64, `libunwind` uses native Windows SEH, so C++ exceptions propagate
  correctly through Win32 stack frames (window procedures, callbacks, COM stubs).
- **UCRT, not msvcrt.** All import libraries target `ucrtbase.dll`, avoiding the
  legacy `msvcrt.dll` behaviours: non-conforming `printf` specifiers, 32-bit `time_t`,
  and locale differences.
- **Kernel callbacks swallow access violations.** Faults inside a window procedure
  invoked via `KiUserCallbackDispatcher` can be silently discarded on some Windows
  versions. This is not a toolchain defect, but it means "the app kept running" is not
  evidence of correctness, and it affects how crash reporting should be configured.
- **Package size.** ~320 MB uncompressed is the starting estimate. Strip all binaries,
  drop unused LLVM tools, and consider making LLDB and the sanitizer runtimes an
  optional component.
