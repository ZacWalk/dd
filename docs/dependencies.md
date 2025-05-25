# CMake dependencies and app scaffolding

dd uses CMake **FetchContent** and **ExternalProject**. New GUI
apps declare [platform-h](https://github.com/ZacWalk/platform-h); CLI apps have no
default library dependencies. Linux currently supports CLI apps only.

## Ownership

| Data or operation | Owner |
| --- | --- |
| Dependency URL, exact commit or archive hash and method | `cmake/dd-dependencies.json` in dd-owned mode |
| Source acquisition and dependency builds | CMake FetchContent or ExternalProject |
| Application targets, linking and package adapters | Application CMake files |
| App type, presets and executable paths | `dd.psd1` |
| Friendly names and initial tested pins | Versioned dd catalog |

Commit the JSON declarations with the app. It is both the dependency list and the
pin record: no second lockfile. PowerShell and CMake read JSON natively,
so this does not add a manifest parser dependency. Project settings remain PSD1.
Catalog updates do not change already declared pins.

```json
{
  "schema": 1,
  "dependencies": {
    "platform-h": {
      "url": "https://github.com/ZacWalk/platform-h.git",
      "commit": "8e9be5de233d1797ce7a2b50fe663042469611a9",
      "method": "fetchcontent"
    }
  }
}
```

The schema is in [../schema/dependencies.schema.json](../schema/dependencies.schema.json).
Names are lowercase letters, digits and hyphens. Commits are full 40-character hashes.
URLs use HTTPS or ssh://, without passwords or CMake list/control characters.
Archives use HTTPS and a full lowercase 64-character `sha256` instead of `commit`.
`method` is `fetchcontent`, `externalproject`, or `application` for a custom recipe.

## Commands

| Command | Behaviour |
| --- | --- |
| `dd dep list` | Inspect declarations, URLs, pins and methods. No network or writes. |
| `dd dep list --available` | List entries in the installed catalog. |
| `dd dep install` | Validate existing declarations. Does not download or run CMake. |
| `dd dep install <name>` | Add a catalog pin using FetchContent; an existing declaration is verified unchanged. |
| `dd dep install <name> --git <url> --ref <ref> [--method fetchcontent\|externalproject]` | Add a custom dependency with a pinned revision and selected method. |
| `dd dep update <name> --ref <ref>` | Change only that dependency's recorded commit. No checkout or index changes. |
| `dd dep install <name> --url <https-url> --sha256 <hash> [--method application]` | Pin an archive; CMake verifies its bytes before extraction. |
| `dd dep update <name> --url <https-url> --sha256 <hash>` | Update an archive URL and checksum together. |

`--method` also works with a catalog name. Neither add nor update stages files,
commits, pushes, configures, builds or checks out source. Full commit IDs are recorded
without a network request; availability is checked when CMake fetches. Branches and
tags are resolved once through `git ls-remote`, including peeled annotated tags.
Ambiguous branch/tag names require a fully qualified ref. No floating branch is
stored. Review the declaration change and commit it normally.

```powershell
dd dep install platform-h
dd dep install spike-db --dry-run
dd dep install tinyxml2 --git https://github.com/leethomason/tinyxml2.git --ref 10.0.0 --method externalproject
dd dep list
dd build
```

These commands require the scaffold's dependency JSON, not a Git repository. Git is
needed for tag/branch resolution and CMake's Git downloads. Supplying a different URL,
ref or method to an already declared name is an error; use `update` for a pin change
or review edits to the JSON for an integration-method change.

## CMake integration

Templates include both standard modules and the shared JSON adapter before app targets:

```cmake
include(FetchContent)
include(ExternalProject)
include("${CMAKE_CURRENT_SOURCE_DIR}/.dd/dependencies.cmake")
dd_load_dependencies("${CMAKE_CURRENT_SOURCE_DIR}/cmake/dd-dependencies.json")
```

**FetchContent** is the default for libraries incorporated into the application's
build. The helper declares the URL and exact GIT_TAG and calls
`FetchContent_MakeAvailable`. A library with a CMake project exposes its targets at
configure time; a source-only library is populated for an application-owned wrapper.
Hyphens become underscores in content names: `platform-h` becomes `platform_h`.
The helper exports `<content_name>_SOURCE_DIR`, `_BINARY_DIR` and `_INSTALL_DIR`.

For a GUI template, platform-h provides `platform::platform` and `platform_add_app()`;
the app calls the latter after loading dependencies. No `add_subdirectory(deps/...)`
or second FetchContent declaration is needed. For the source-only spike-db catalog pin:

```cmake
add_library(spikedb STATIC "${spike_db_SOURCE_DIR}/src/spike_db.c")
target_include_directories(spikedb PUBLIC "${spike_db_SOURCE_DIR}/src")
target_link_libraries(app PRIVATE spikedb)
```

**ExternalProject** is for separate CMake builds. It creates `dd-dep-<name>`, fetches
at build time, configures with the parent's compiler/build type, and installs under
an isolated prefix. It does **not** expose the library's targets inside the parent.
The app must provide an imported target or other integration and an
`add_dependencies(app dd-dep-<name>)` ordering edge when it consumes the output.
Imported libraries can also require explicit byproduct declarations in a custom
ExternalProject recipe. There is no automatic generic linker configuration.

The built-in ExternalProject mode supports standard CMake build/install projects.
Non-CMake build systems, custom configure arguments and special byproduct recipes
remain app-owned CMake work; do not use executable install hooks in JSON.

For `method: "application"`, `dd_load_dependencies` validates the declaration but
does not acquire or build it. A reviewed application recipe obtains acquisition
arguments with `dd_dependency_arguments(manifest name output)` and supplies them to
FetchContent or ExternalProject. Arguments contain `GIT_TAG` or `URL_HASH`, and TLS
verification for archives. The recipe owns cache layout, `SOURCE_SUBDIR`, patches,
options, dependencies, imported targets and byproducts. See [adoption.md](adoption.md).

## Caches and safety

Generic sources live under the configured binary directory's `_deps/<name>-<full-pin>-src`.
Build, install and stamp directories use shorter commit prefixes to reduce Windows
path lengths, with full-commit markers that reject prefix collisions. Updates select
new paths rather than modifying prior source checkouts. Windows, Linux, Debug and
Release do not share compiler caches.

- `dd dep` changes only the declaration file with an atomic replacement, retaining
  unrelated entries. It refuses invalid data and concurrent edits detected during
  ref resolution. Existing Git staging is not changed.
- `--dry-run` never writes or accesses the network; unresolved refs remain unresolved.
  `--json` and `--non-interactive` remain available to agents.
- `doctor` validates declarations; status `declared` does not claim a download or
  build completed. CMake checks source integrity when configuring, not `doctor`.
- CMake downloads only when needed. No automatic sibling-source overrides or installed
  package substitution are used. Recursive repository fetching is disabled.
  Dependencies needing nested repositories need a separate reviewed integration.
- CMake refuses modified/mismatched existing source checkouts and linked cache paths.
  It does not discard local work. The same rule can reject libraries whose own build
  edits tracked source, such as older zlib CMake builds; use a suitable upstream fix
  or a separate application-owned recipe rather than disabling safety implicitly.
- `dd clean` refuses edited or unrecognized cached source repositories, even with
  `--yes`. Preserve any source work before explicitly cleaning a recognized build tree.
- Archive contents are fingerprinted after acquisition; repeated use and cleanup refuse
  edited or unverified contents. Application recipes own their own source validation.
- Ref-resolution failures leave declarations unchanged. Build download failures retain
  their logs and partial caches for inspection; no destructive automatic rollback.
- Configure/build executes upstream code and can access the network. MCP requires
  the existing project-execution opt-in for those commands. Dependency declaration
  tools alone never configure or run dependency code.

A clean clone can run `dd dep install` to validate the
declarations, then `dd build` or `dd test`; CMake fetches the pinned revisions.
An offline first build cannot fetch missing sources; populated, unchanged caches
avoid update requests. CMake dependency providers or hand-written recipes are trusted
project code and remain the application's responsibility.

## Existing projects

Set `dependencies = @{ owner = 'application' }` in `dd.psd1` when existing CMake already
owns dependency pins and recipes. No dd dependency JSON is then required. `dep list`
and `doctor` report `inventoryKnown: false`, not an empty known inventory; named pin
mutations are rejected. Omission defaults to dd ownership, where missing or invalid
JSON remains an error. No existing checkout or build recipe is rewritten automatically.

Alternatively keep dd-owned pins with `method: "application"` for selected recipes.
Choose one acquisition owner per library to avoid duplicate copies. See the
[adoption guide](adoption.md) for the full contract.

## Validation

Tests cover declaration-only installs, unchanged Git indexes, both native build
platforms, FetchContent fresh-clone/update behavior, preservation of old cached work,
ExternalProject build/install, annotated tags and GUI platform-h integration. CI
also exercises dry-runs, MCP method selection and the packaged scaffold. Tests retain
temporary fixtures for inspection and never migrate a user's existing repositories.