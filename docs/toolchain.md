# Toolchains

dd builds with the host's native compiler and never ships one. Three operations stay
separate: bootstrap installs dd, `dd init` writes a project, and `dd toolchain` installs
build tools. Neither of the first two installs a compiler, `dd toolchain` never writes
source, and `dd doctor` only reports.

| Host | Toolchain | Projects |
| --- | --- | --- |
| Windows x64 | Visual Studio 17 or later, or its Build Tools, with the x64 C++ tools and the Windows SDK; CMake; Ninja | GUI, CLI, library |
| Linux x64: Ubuntu, including WSL 2 | GCC, CMake, Ninja | CLI, library |

PowerShell 7.4+ and Git are needed everywhere. On Linux, dd never looks for Visual
Studio; Windows tools run from WSL do not make a Linux build. ATL and MFC are components a
project can require, not defaults, and source libraries such as libdesktop or WTL are
[dependencies](dependencies.md), never system packages.

## Requirements

| Tool | Default minimum |
| --- | --- |
| CMake, CTest | 3.24 |
| Ninja | 1.10 |
| Git | 2.20 |
| GCC, on Linux | 10 |
| Visual Studio, on Windows | 17, with `Microsoft.VisualStudio.Component.VC.Tools.x86.x64` |

On Windows, `cl`, `link` and `rc` must also resolve in the [compiler
environment](#the-msvc-environment). A project raises these minima, or adds tools and
Visual Studio components, in `dd.psd1`:

```powershell
requirements = @{
    tools = @{
        cmake = @{ minimum = '3.28.0' }
        python = @{ minimum = '3.11.0' }
        gdb = @{ minimum = '12.0'; optional = $true; platforms = @('x64-linux') }
    }
    msvc = @{
        minimum = '17.0'
        components = @('Microsoft.VisualStudio.Component.VC.ATL')
    }
}
```

A project can name `cmake`, `ctest`, `ninja`, `git`, `gcc`, `python` and `gdb`, each
probed by dd for its version; no project script runs. A default cannot be lowered or made
optional.
A missing optional tool is a warning, and is never installed. `msvc.minimum` is the
Visual Studio version, not `cl`'s, and `components` add to the x64 C++ tools. ATL is not
among the C++ workload's recommended components, so an application that needs it lists
`Microsoft.VisualStudio.Component.VC.ATL`; a libdesktop app does not. `build`, `test`,
`run`, `launch`, `ide`, `doctor` and `toolchain` all check the same merged requirements.

## `dd toolchain`

`dd toolchain --dry-run` reports what is missing and the packages that would supply it,
and with no project it checks the host's defaults. On a ready machine `dd toolchain`
succeeds without changes. Otherwise it fails with exit 3 unless given `--yes`, which
installs, then checks again and fails if the requirements are still unmet: a package
manager's success is not readiness. dd never opens an elevation or password prompt, and
changes no dependency pins or profiles.

### Windows

`--yes` needs an elevated PowerShell and installs with `winget`:

| Package | When |
| --- | --- |
| `Microsoft.VisualStudio.BuildTools` | No Visual Studio meets the requirements: installed with the `VCTools` workload, its recommended components and every required component. An existing Visual Studio is instead modified, through its installer, to add the components |
| `Kitware.CMake` | CMake or CTest is missing or too old |
| `Ninja-build.Ninja`, `Git.Git`, `Python.Python.3.13` | Ninja, Git or a required Python is missing or too old |

winget's results for an already installed package or no applicable upgrade are accepted,
but prove nothing; the check afterwards decides. Without winget, which some Windows
images lack and some policies block, install the reported tools by hand. The Microsoft
toolchain is not redistributable, so dd cannot ship it: each user installs it under their
own acceptance of its licence, and the first install is large.

### Linux

Automatic installation supports Ubuntu, identified by `/etc/os-release`, through apt:
`build-essential`, `cmake`, `ninja-build`, `git`, `python3` and `gdb`, as needed. Run as
root, `dd toolchain --yes` installs them; otherwise it prints the `sudo apt-get` commands
to run. On other distributions, install GCC, CMake 3.24+ and Ninja yourself.

## The MSVC environment

`cl.exe` exists only inside the environment `vcvars64.bat` sets up, so dd imports that
environment into its own process, once per set of requirements; nobody needs a Developer
Command Prompt.

1. `vswhere.exe`, at its fixed path under `%ProgramFiles(x86)%\Microsoft Visual
   Studio\Installer`, finds the latest installation that meets the minimum version and
   components. Without it, or without a match, dd stops with exit 3.
2. dd clears `VSCMD_VER`, `VSCMD_ARG_TGT_ARCH` and `VSCMD_ARG_HOST_ARCH`, and restores the
   `PATH` an earlier `vcvars` session saved: `vcvars64.bat` silently does nothing when
   `VSCMD_VER` is set, leaving `cl.exe` without `rc.exe`, which fails much later, in the
   resource compile.
3. It runs `cmd /d /s /c "vcvars64.bat >nul && set"` and copies the variables into the
   process.
4. It checks that `cl.exe`, `link.exe` and `rc.exe` resolve, since a zero exit from the
   batch file proves nothing, and fails with exit 4 when they do not.

`dd env` returns the result ([cli.md](cli.md#other-commands)).
