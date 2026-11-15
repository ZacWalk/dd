# Project commands

A project adds its own commands - bumping a version, say - as PowerShell scripts declared
in `dd.psd1`, not by forking the driver. dd owns parsing, validation, confirmation,
timeouts and the JSON result; the script owns what the command does. Built-in commands
cannot be overridden, and there are no lifecycle hooks.

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

Start the script from [examples/version.ps1](../examples/version.ps1). It reads a
`VERSION` file holding `MAJOR.MINOR.PATCH`, previews or applies the bump, and returns
structured results. It handles no prerelease labels, updates no other file, and never
stages, commits or publishes; connect CMake and resources to `VERSION` yourself.

```powershell
dd commands --json
dd help version
dd version --part minor --dry-run
dd version --part minor --yes
```

| Field | Meaning |
| --- | --- |
| `description` | Required |
| `script` | Required: a `.ps1` file inside the project; traversal and linked paths are refused |
| `effects` | Required: `read` or `write` |
| `parameters` | Named parameters; none by default |
| `timeout-secs` | 1 to 9999; 60 by default |
| `supports-dry-run` | Whether the script implements previews; `$false` by default |
| `platforms` | The hosts the script supports, both by default; this is about the script, not compilers |

Command names are lowercase letters, digits and hyphens; built-in names are reserved. An
undeclared command is an error: dd never searches `PATH` or guesses a script. A missing
script shows as `scriptExists: false` in `dd commands` and fails with exit 3 when run.
Discovery needs no compiler, CMake or build preset, so it works on any host.

## Parameters

Each parameter has a `type` - `string`, `integer` (signed 64-bit) or `boolean` - and
optionally `required`, `default`, `choices` and `description`. Defaults must match the
type and choices; string choices are case-sensitive. An omitted parameter takes its
default; without one it fails if `required` and is otherwise left out of the request.
Unknown, duplicate and reserved parameter names fail before any script runs.

```powershell
dd my-command --count -2 --enabled true --label 'text with spaces'
dd my-command --label=--literal-value
dd my-command --label=
```

Every value is named, booleans as `true` or `false`; `--key=value` keeps an empty string
or a value that starts with `--`. Custom options follow the command name, while
`--project`, `--json` and `--non-interactive` may precede it. Positional arguments and
`--` are refused, and nothing is ever evaluated as shell text.

## Confirmation and previews

A `write` command needs `--yes` in automation; interactively dd asks first, and JSON
output, CI and redirected input never prompt. A `read` command runs unprompted.
`--dry-run` runs the script with `dryRun` set only if it declares `supports-dry-run`;
otherwise it fails without running anything. `dd help <name>` inspects a command without
executing it.

## Script protocol

dd starts a separate `pwsh -NoProfile -NonInteractive` in the project root, writes one
UTF-8 JSON request line to its stdin and closes it. The script reads that request rather
than prompting or parsing dd's command line:

```json
{
  "schema": 1,
  "command": "version",
  "projectRoot": "C:/code/my-app",
  "parameters": { "part": "minor" },
  "dryRun": true
}
```

On success it prints one JSON response on stdout:

```json
{
  "schema": 1,
  "data": { "previous": "1.2.3", "next": "1.3.0" },
  "files": ["VERSION"]
}
```

`data` is the command's result. `files` lists the project-relative files it changed, or
that a preview would change; use an empty array for none. dd checks those paths but
changes nothing itself: the script implements, and tests, its own preview.

Progress and errors go to stderr. A nonzero exit fails the command with that code and a
log path; a zero exit without a valid response fails too. Requests and responses are
limited to 1 MiB, a timeout ends the process tree, and environment changes stay in the
child. With `--json`, the envelope's `data` holds `command`, `dryRun`, `result`, `files`
and `log`.

## Trust

Scripts are not sandboxed. They run with the user's permissions and can reach files and
the network outside the project. Path checks constrain what dd invokes and reports, not
what a script does, and `effects` and `supports-dry-run` are the author's claims, not
guarantees.

On the command line `dd <name>` runs a declared script directly: a `write` command asks
or needs `--yes`, but a `read` command runs unprompted, like a package manager's lifecycle
script. Read `dd.psd1` and the scripts it names before running dd in a repository you did
not write. MCP mode runs no project script, not even a preview, without
`--allow-execution` ([mcp.md](mcp.md#start-and-trust)).
