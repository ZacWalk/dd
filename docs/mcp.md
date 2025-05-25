# PowerShell MCP server

dd's optional MCP adapter runs directly with PowerShell 7.4+ on Windows and Linux.
It requires no Node.js, npm, SDK, downloaded modules or build step. Native application
builds still need the compiler, Git and CMake tools reported by `dd doctor`.

## Start and trust

```powershell
pwsh -NoProfile -NonInteractive -File ./.dd/mcp/server.ps1 -Root C:/code/my-app
```

This command starts a stdio protocol process, not an interactive shell. MCP clients
launch it and send JSON messages on stdin. Scaffolds already include this configuration:

```json
{
  "servers": {
    "dd": {
      "type": "stdio",
      "command": "pwsh",
      "args": ["-NoProfile", "-NonInteractive", "-File", "${workspaceFolder}/.dd/mcp/server.ps1", "-Root", "${workspaceFolder}"]
    }
  }
}
```

Add `-AllowExecution` only for trusted code. Without it, build/test/run/launch and
all custom project scripts are disabled, including script-backed previews. Discovery,
doctor, toolchain planning, scaffold creation and pin editing retain their existing
interfaces. Mutations default to preview. There are no tools for arbitrary shell
execution, compiler installation, cleanup, profile edits or Git commits/pushes.

Project directories must remain inside `-Root` and cannot traverse linked paths.
Each project command requires a manifest in the selected project itself, so ancestor
discovery cannot escape the configured workspace. These checks constrain invocation,
not the behavior of trusted project code; the server is not an OS sandbox.

## Protocol contract

The server implements the tools subset of MCP over newline-delimited UTF-8 JSON-RPC:

- `initialize`, `notifications/initialized`, `ping`, `tools/list`, and `tools/call`.
- Protocol versions `2025-06-18`, `2025-03-26`, and `2024-11-05`. Unsupported client
  versions negotiate `2025-06-18`; the client decides whether it can continue.
- All 12 existing dd tools, with JSON Schema input validation. Modern clients receive
  both structured results and text JSON; older clients receive text JSON only.
- Progress notifications when the request supplies a progress token. CLI logs never
  enter protocol stdout directly.
- One active CLI child, up to 32 queued calls, and a 30-minute maximum per active call.
  Ping and cancellation remain responsive while project code runs.
- `notifications/cancelled` removes queued calls or terminates the active CLI process
  tree, without responding to the cancelled call. Unknown cancellations are ignored.
- Closing stdin discards queued calls, terminates active work and exits. Applications
  already returned by `dd_launch` remain user-owned and survive server shutdown.
- Input frames are limited to 1,048,576 decoded characters, CLI stdout to 8,388,608
  decoded characters, and retained CLI stderr to 65,536 characters. Oversized protocol
  frames close the connection; oversized CLI output fails only that tool call.

No HTTP transport, resources, prompts, sampling or task APIs are advertised. The
adapter owns protocol handling; the shared CLI owns command behavior. A fixed
PowerShell wrapper receives the CLI argument vector as JSON on stdin, avoiding shell
parsing of URLs, quotes, empty strings and forwarded arguments.

Reference: [MCP stdio specification](https://modelcontextprotocol.io/specification/2025-06-18/basic/transports).

## Existing projects

Update the vendored runtime through a reviewed project change. Replace the old MCP
client command and arguments with the configuration above, and use `-AllowExecution`
instead of the previous adapter's execution flag when trust is intentional. Restart
the client server after changing its configuration. `dd mcp` prints the correct local
configuration; `dd mcp --register` never overwrites an existing one.

Old JavaScript bundles and package files are no longer used or copied into scaffolds
or releases. No external project configuration is rewritten automatically.

## Validate

```powershell
pwsh -NoProfile -File ./tests/mcp.ps1 -ProtocolOnly
pwsh -NoProfile -File ./tests/mcp.ps1
```

The first command checks framing, lifecycle, schema validation, all tool definitions,
pin mutations, exact custom arguments, workspace boundaries, active/queued cancellation
and EOF cleanup. The full test also builds both configurations, checks filtered CTest
results and progress, and verifies launch survival after server exit. Both tests use
PowerShell as the real stdio client; no test package installation is needed. Release
bootstrap tests also exercise the packaged server and reject JavaScript artifacts.