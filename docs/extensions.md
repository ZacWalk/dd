# Project extensibility

Keep project-specific commands in project-owned scripts, not in a fork of the dd
driver. The native `dd.psd1` manifest declares the command interface as data. The
shared CLI owns parsing, validation, confirmation, timeouts and JSON results; the
script owns application behavior such as which files contain its version number.

These optional fields extend manifest schema 1. Existing projects continue to work
unchanged. Older vendored drivers reject the new fields, so update the complete
vendored runtime through a reviewed change before adding them. No automatic hooks
or override of built-in commands are supported.

## Declaring commands

Add a `commands` hashtable at the manifest's top level:

```powershell
commands = @{
    version = @{
        description = 'Bump the application version'
        script = 'tools/version.ps1'
        effects = 'write'
        'supports-dry-run' = $true
        'timeout-secs' = 30
        platforms = @('x64-windows', 'x64-linux')
        parameters = @{
            part = @{
                type = 'string'
                choices = @('major', 'minor', 'patch')
                default = 'patch'
                description = 'Version component to increment'
            }
        }
    }
}
```

Use [../examples/version.ps1](../examples/version.ps1) as a starting point for the
project's `tools/version.ps1`. It reads a `VERSION` file containing a plain three-part
version such as `1.2.3`, previews or applies the bump, and returns structured results.
Prerelease labels and multiple version-file synchronization are intentionally not
part of the example. Connect CMake/resources to your chosen version source yourself.
The example never stages, commits or publishes a change.

```powershell
dd commands --json
dd help version
dd version --part minor --dry-run
dd version --part minor --yes
```

Command names are lowercase letters, digits and hyphens. Built-in names, including
`run`, `build`, `dep`, `commands` and `targets`, are reserved. An undeclared command is
an error; dd never searches PATH or guesses a script name. Scripts must be `.ps1`
files inside the project; traversal and linked paths are rejected. A missing script
appears as `scriptExists: false` in discovery and fails invocation with exit 3.

Required command fields: `description`, `script` and `effects` (`read` or `write`).
Optional fields: `parameters` (empty by default), `timeout-secs` (60 by default,
1..9999), `supports-dry-run` (false by default), and `platforms` (both native hosts by
default). Platform declarations describe script compatibility, not compiler needs.

## Parameters and confirmation

Each parameter declares `type = 'string'`, `'integer'` or `'boolean'`. Optional
`required`, `default`, `choices` and `description` fields are validated on discovery.
Defaults must match their declared type and choices. Missing optional parameters
without defaults are omitted from the request. `required` is satisfied by an explicit
value or a valid default. Unknown and duplicate parameters fail before execution.

Supply all parameters as named values, including booleans:

```powershell
dd my-command --count -2 --enabled true --label 'text with spaces'
dd my-command --label=--literal-value
dd my-command --label=
```

Custom options must follow the command name; shared `--project`, `--json` and
`--non-interactive` can precede it. `--key=value` preserves an empty string or a value
starting with `--`. Integers are signed 64-bit values; booleans accept `true`/`false`.
String choices are case-sensitive. Positional custom arguments and pass-through
`--` arguments are not supported. The manifest schema lists reserved parameter names.
There are no arbitrary shell-command strings or manifest scriptblocks.

Write commands require `--yes` in automation. Without it, an interactive CLI asks for
confirmation; JSON output, CI and redirected input never prompt. Read commands do
not require confirmation. `--dry-run` executes the script with preview intent only
when the command declares support; otherwise it fails without running the script.
Use `dd help NAME` to inspect unsupported preview commands without execution.

## Script protocol

dd starts a separate instance of its own PowerShell runtime with `-NoProfile` and
`-NonInteractive`, from the project root. It sends one UTF-8 JSON line to stdin and
closes stdin. Scripts should read the request rather than prompting or parsing dd's
CLI. A typical request is:

```json
{
  "schema": 1,
  "command": "version",
  "projectRoot": "C:/code/my-app",
  "parameters": { "part": "minor" },
  "dryRun": true
}
```

On success, stdout must contain one JSON response:

```json
{
  "schema": 1,
  "data": { "previous": "1.2.3", "next": "1.3.0" },
  "files": ["VERSION"]
}
```

`data` is the command-specific result. `files` is an array of project-relative files
affected, or proposed to be affected in a dry-run. Use an empty array for commands
without file effects. dd validates these paths but does not apply file changes on
the script's behalf. The script must implement and test its own preview behavior.

Write progress and errors to stderr, not stdout. Exit nonzero for failure; dd
propagates that code with a log path. A zero exit with invalid/missing response JSON
is still a failure. Request and response JSON are limited to 1 MiB (response size is
checked after capture). Execution timeout terminates the process tree. Environment
changes inside the child do not change the caller's shell.

`dd ... --json` retains the normal dd result envelope, with command, dryRun,
result, files and log fields inside `data`. Shell text is never evaluated as code.

## Multiple applications

Multiple CMake executables remain ordinary `targets` entries, not custom overrides
of `run`. For example, add these entries to the manifest and the corresponding
`add_executable` targets to CMake:

```powershell
targets = @(
    @{
        id = 'desktop'
        kind = 'gui'
        'cmake-target' = 'desktop_app'
        'debug-path' = 'build/{platform}/debug/bin/desktop{exe}'
        'release-path' = 'build/{platform}/release/bin/desktop{exe}'
        platforms = @('x64-windows')
    },
    @{
        id = 'importer'
        kind = 'cli'
        'cmake-target' = 'data_importer'
        'debug-path' = 'build/{platform}/debug/bin/importer{exe}'
        'release-path' = 'build/{platform}/release/bin/importer{exe}'
    }
)
```

Set `'default-target' = 'desktop'` inside the `project` hashtable if desired.
`dd targets --json` lists IDs, binary path templates, supported platforms and the
configured default without compiling or executing anything. CLI targets default to
both native platforms; GUI targets default to Windows and cannot claim Linux support.
The app's CMake must independently omit unsupported targets on each platform.

```powershell
dd run desktop
dd run importer -- --input data.csv
dd run
```

Selection order: explicit ID, configured default, then the sole host-compatible
target. With several targets and no default, an interactive CLI asks for an ID;
automation returns an error listing the choices. An unsupported configured default
is an error, not an implicit fallback. Explicit IDs can override it. `run` builds the
selected CMake target in Release, launches its configured binary and forwards tokens
after `--`. CMake may still configure/fetch other project dependencies.

Metadata validation is independent of native build readiness: command discovery and
version scripts can work on Linux even for a Windows GUI project with no Linux build
preset. `build`, `run`, `test`, `ide` and `doctor` still check host build requirements.
GUI smoke tests run only for host-compatible targets.

## VS Code targets

After adding apps, add missing F5 launch entries explicitly:

```powershell
dd targets --vscode --dry-run
dd targets --vscode --yes
```

This uses each target's Debug path, native debugger type and the existing scaffold
`dd: build debug` task. It does not build or launch anything. That task builds the
project's Debug configuration, not only the selected executable. Existing launch
entries, arguments and compound configurations are preserved; matching program/type
entries are reused. Conflicting generated names require manual review. Changes back
up the old launch file, then rewrite it as JSON (comments/formatting are not retained).
It never silently refreshes settings during `build` or `run`, nor removes stale entries.

## MCP and trust

- `dd_commands`: compiler-independent command discovery, no execution opt-in needed.
- `dd_targets`: read-only target/default/platform discovery.
- `dd_command`: `project`, `name`, typed `parameters`, `dryRun` (default true), and
  `apply` (default false). A non-preview write requires `dryRun: false, apply: true`.
- `dd_run`: target is optional only when default/unique selection is unambiguous.

Custom script execution requires the server's `-AllowExecution` opt-in, including
script-backed dry-runs and commands labeled read-only. The generic tool accepts only
declared project commands, never built-ins such as `toolchain`. Parameter types and
choices are validated by MCP and the shared CLI. All commands stay scoped to the
configured project root; no global MCP registration or per-project driver fork.

**This is not a sandbox.** Scripts inherit the user's permissions and can access
files or the network outside the project. Path checks constrain dd's invocation and
reported file paths, not arbitrary script behavior. Effects and dry-run declarations
are project-author assertions, not security guarantees. Trust the code before opting
in; never use them as justification for running an untrusted repository automatically.

**The CLI has no equivalent opt-in.** `-AllowExecution` gates MCP only. On the
command line, `dd <name>` runs a declared script directly; `effects = 'write'`
prompts or requires `--yes`, but `effects = 'read'` runs unprompted, exactly like a
package-manager lifecycle script. Read `dd.psd1` and the scripts it names before
running `dd` in a repository you did not write.