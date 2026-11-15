# dd development

dd is the PowerShell 7.4 build driver the [README](../README.md) introduces. Each subject
has one document in [docs/](../docs), listed in the README;
[implementation.md](../docs/implementation.md) maps the runtime.

- Keep the CLI the single behaviour owner: MCP mode only adapts typed requests onto it
  ([two modes](../docs/mcp.md#two-modes)). Keep MCP stdout for protocol messages only, and
  keep the workspace boundary and the opt-in before executing project code.
- The runtime and MCP are pure PowerShell 7.4+: no third-party packages, parsers or build
  step. Follow the [MCP stdio transport](https://modelcontextprotocol.io/specification/2025-06-18/basic/transports).
- Projects vendor `dd.ps1` and `.dd/` unchanged, so a runtime change reaches them only
  through a release. A new runtime file joins the inventory in `.dd/core.ps1` and the list
  in `bootstrap.ps1`; `tools/prepare.ps1` checks that the two agree.
- Dependencies use pinned FetchContent or ExternalProject declarations in
  `cmake/dd-dependencies.json`, or explicit application-owned recipes. Preserve local
  source work.
- Never automatically commit, push, elevate, alter profiles or register MCP servers during
  tests.
- Download dd releases only from https://github.com/ZacWalk/dd, and provision native
  compilers only through official OS package providers; dynamicdispatch.org is not a
  download source.
- Verify with `tools/prepare.ps1`, then `tests/verify.ps1`
  ([Developing dd](../README.md#developing-dd)). An expected command failure must not leak
  its exit code from a passing test script; `tests/ci-exit.ps1` runs scripts the way
  GitHub Actions does to catch that.
- Keep these headings: `docs/cli.md`'s *Commands* and `docs/mcp.md`'s *Two modes*, which
  other repositories link to, and the README's *Try the source checkout*, which
  `bootstrap.ps1` links to. Scaffolded READMEs link to `docs/extensions.md` and
  `docs/adoption.md`.
