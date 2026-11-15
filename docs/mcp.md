# PowerShell MCP server

dd's optional MCP server runs directly with PowerShell 7.4+ on Windows and Linux. It
needs no Node.js, npm, SDK, downloaded modules or build step; the builds it runs still
need the tools `dd doctor` reports.

## Two modes

`dd` has exactly two modes, and the command line selects between them:

- **CLI mode** — the default. Every verb (`build`, `test`, `run`, `doctor`, `dep`, …)
  executes once, prints a result envelope and exits. This is the single behaviour owner.
- **MCP mode** — `dd mcp`. The process becomes a stdio JSON-RPC server and stays alive
  until stdin closes. It adapts typed MCP requests onto CLI mode, running each tool call
  as a child `dd` invocation and returning that command's envelope.

Because MCP mode owns stdout for protocol messages, it never prints a result envelope and
`--json` is rejected. Diagnostics go to stderr.

## Start and trust

```powershell
dd mcp
```

This starts a stdio protocol process for an MCP client, not an interactive shell. Every
scaffold configures it in `.vscode/mcp.json`:

```json
{
  "servers": {
    "dd": {
      "type": "stdio",
      "command": "pwsh",
      "args": ["-NoProfile", "-NonInteractive", "-File", "${workspaceFolder}/dd.ps1", "mcp"]
    }
  }
}
```

`dd ide --mcp` writes the same entry, with the driver's absolute path, into a project
without a `.vscode/mcp.json`, and `dd ide --mcp --dry-run` prints it; an existing file is
never overwritten. Each project runs its own vendored server; none is registered
globally, and the client's own trust prompt still applies.

The workspace boundary is the project root when `dd mcp` starts inside a project, and the
current directory otherwise, so machine-level inspection works anywhere. A tool's
`project` must be an existing directory inside the boundary, reached through no linked
path, and a tool that acts on a project needs a `dd.psd1` in that directory itself, so
discovery never climbs past the boundary. These checks constrain invocation, not trusted
project code: the server is not a sandbox.

| Tool | Runs | Needs `--allow-execution` |
| --- | --- | --- |
| `dd_help` | `dd help` | |
| `dd_commands`, `dd_targets` | `dd commands`, `dd targets` | |
| `dd_doctor` | `dd doctor` | |
| `dd_toolchain_plan` | `dd toolchain --dry-run`; it never installs | |
| `dd_init` | `dd init`, as a preview unless `apply` is true | |
| `dd_dependencies` | `dd dep`; `install` and `update` preview unless `apply` is true | |
| `dd_build`, `dd_test` | `dd build`, `dd test` | Yes |
| `dd_run`, `dd_launch` | `dd run`, `dd launch`; `target` may be omitted only when the selection is unambiguous | Yes |
| `dd_command` | A declared [project command](extensions.md), never a built-in; `dryRun` defaults to true, and a write needs `dryRun: false` with `apply: true` | Yes, even for a preview |

Add `--allow-execution` to the server's arguments only for a trusted workspace: builds,
tests and project scripts run project and dependency code. No tool runs arbitrary shell
commands, installs compilers, cleans, edits profiles, or commits or pushes.

## Protocol contract

The server implements the tools subset of MCP over newline-delimited UTF-8 JSON-RPC,
following the [stdio transport](https://modelcontextprotocol.io/specification/2025-06-18/basic/transports):

- `initialize`, `notifications/initialized`, `ping`, `tools/list` and `tools/call`.
- Protocol versions `2025-06-18`, `2025-03-26` and `2024-11-05`. Other client versions
  negotiate `2025-06-18`; the client decides whether it can continue.
- JSON Schema validation of every tool's input. `2025-06-18` clients receive structured
  results and text JSON; older clients receive text JSON only.
- Progress notifications from the CLI's stderr when a call supplies a progress token. CLI
  output never reaches protocol stdout directly.
- One active CLI child, up to 32 queued calls, and 30 minutes per active call. Ping and
  cancellation stay responsive while project code runs.
- `notifications/cancelled` removes a queued call or ends the active CLI process tree,
  without answering the cancelled call. Unknown cancellations are ignored.
- Closing stdin discards queued calls, ends active work and exits. Applications started by
  `dd_launch` belong to the user and survive the server.
- Input frames are limited to 1,048,576 decoded characters, CLI stdout to 8,388,608 and
  retained CLI stderr to 65,536. An oversized frame closes the connection; oversized CLI
  output fails only that call.

No HTTP transport, resources, prompts, sampling or task APIs are advertised. A fixed
PowerShell wrapper receives each CLI argument vector as JSON on stdin, so URLs, quotes,
empty strings and forwarded arguments are never parsed by a shell.
