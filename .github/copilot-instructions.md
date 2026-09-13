# dd development

- Product: dd build system. `dd toolchain` evaluates and provisions native tools.
- dd has two modes: CLI mode (default, one command per invocation) and MCP mode
  (`dd mcp`, a stdio JSON-RPC server that runs until stdin closes).
- Use the PowerShell CLI as the single behavior owner; MCP adapts typed requests to it.
  MCP mode owns stdout, so it prints no result envelope and rejects `--json`.
- `dd ide --mcp` writes `.vscode/mcp.json`; `--dry-run` previews it. Never register
  MCP servers during tests.
- Use pinned FetchContent/ExternalProject declarations in cmake/dd-dependencies.json,
  or explicit application-owned dependency recipes. Preserve local source work.
  Never automatically commit, push,
  elevate, alter profiles or register MCP servers during tests.
- Run `pwsh tools/prepare.ps1`, `pwsh tests/smoke.ps1 -Build`, and
  `pwsh tests/dependencies.ps1`. Run native Linux tests under WSL or Ubuntu CI.
- MCP is pure PowerShell 7.4+, with no third-party packages or build step.
  Follow https://modelcontextprotocol.io/specification/2025-06-18/basic/transports.
- Run `pwsh tests/mcp.ps1`. Keep stdout exclusively for MCP messages;
  enforce configured workspace boundaries and opt-in before executing project code.
- All dd release downloads come from https://github.com/ZacWalk/dd. Native compiler
  provisioning uses official OS package providers; dynamicdispatch.org is not a download source.