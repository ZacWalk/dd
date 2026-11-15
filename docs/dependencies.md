# CMake dependencies

dd records each dependency's URL, exact pin and method in `cmake/dd-dependencies.json`;
CMake's FetchContent or ExternalProject fetches and builds it. GUI scaffolds declare
[libdesktop](https://github.com/ZacWalk/libdesktop); CLI and library scaffolds declare
nothing.

## Ownership

| Data or operation | Owner |
| --- | --- |
| URL, exact commit or archive hash, and method | `cmake/dd-dependencies.json` |
| Fetching and building sources | CMake FetchContent or ExternalProject |
| Application targets, linking and package adapters | The application's CMake |
| Names and repository URLs for `dd dep install <name>` | The catalog, `.dd/catalog.json` |

The JSON is both the dependency list and the lock: commit it with the project.
PowerShell and CMake read it natively, and its model is
[schema/dependencies.schema.json](../schema/dependencies.schema.json). Names are lowercase
letters, digits and hyphens. A Git entry has an HTTPS or `ssh://` `url`, without
passwords, queries, fragments or CMake list characters, and a full lowercase 40-character
`commit`; an archive has an HTTPS `url` and a lowercase 64-character `sha256` instead.
`method` is `fetchcontent`, `externalproject` or `application`. Write entries with
`dd dep` rather than copying a pin from documentation. The catalog holds URLs, not pins,
so changing it never moves a declared pin.

A project whose CMake already owns its pins and recipes sets
`dependencies = @{ owner = 'application' }` in `dd.psd1` and needs no JSON. `dep list` and
`doctor` then report `inventoryKnown: false` rather than an empty list, and named changes
fail with exit 2. Under the default, `owner = 'dd'`, a missing or invalid JSON is an
error. Give each library one acquisition owner, or it is fetched twice.

## Commands

| Command | Behaviour |
| --- | --- |
| `dd dep list` | Show the declarations; no network, no writes |
| `dd dep list --available` | Show the catalog |
| `dd dep install` | Validate the declarations; downloads nothing and runs no CMake |
| `dd dep install <name> [--method <method>]` | Declare a catalog entry at its default branch's current head; an existing declaration is verified unchanged |
| `dd dep install <name> --git <url> --ref <ref> [--method <method>]` | Declare a Git dependency at a commit, branch or tag |
| `dd dep install <name> --url <https-url> --sha256 <hash> [--method <method>]` | Declare an archive |
| `dd dep update <name> --ref <ref>` | Re-pin a Git dependency |
| `dd dep update <name> --url <https-url> --sha256 <hash>` | Change an archive's URL and checksum together |

`--method` defaults to `fetchcontent`. A full commit is recorded without a network
request; a branch or tag is resolved once with `git ls-remote`, peeling annotated tags,
and a name that is both needs `refs/heads/...` or `refs/tags/...`. No floating ref is
stored. Another URL, ref or method for a declared name is an error: re-pin with `update`,
and change a method by editing the JSON. `--dry-run` writes nothing and uses no network.

`dd dep` changes only the JSON, replacing it atomically and keeping unrelated entries, and
refuses if the file changed while a ref was resolving; a failed resolution leaves it
unchanged. It never stages, commits, pushes, configures, builds or checks anything out:
review and commit the change as usual. An invalid request exits 2 and a failed operation
5. The commands need the JSON, not a Git repository; Git itself resolves refs and fetches
Git sources.

```powershell
dd dep install libdesktop --dry-run
dd dep install tinyxml2 --git https://github.com/leethomason/tinyxml2.git --ref 10.0.0 --method externalproject
dd dep list
dd build
```

## CMake integration

Scaffolds load the declarations before the application's targets:

```cmake
include(FetchContent)
include(ExternalProject)
include("${CMAKE_CURRENT_SOURCE_DIR}/.dd/dependencies.cmake")
dd_load_dependencies("${CMAKE_CURRENT_SOURCE_DIR}/cmake/dd-dependencies.json")
```

**`fetchcontent`** brings a library into the application's build at configure time. A
library with a CMake project exposes its targets - libdesktop provides
`libdesktop_add_app()` and `libdesktop::ui`, tinyxml2 the target `tinyxml2` - and a
source-only one is populated for an application-owned wrapper. Hyphens in a name become
underscores in its content name, and `<content_name>_SOURCE_DIR`, `_BINARY_DIR` and
`_INSTALL_DIR` are set.

```cmake
target_link_libraries(app PRIVATE tinyxml2)
```

**`externalproject`** builds a standard CMake project separately as `dd-dep-<name>`:
fetched at build time, configured with the parent's compilers, build type, C++20 and MSVC
runtime, and installed under a private prefix. Its targets are not visible to the parent,
so the application supplies an imported target, any byproducts, and
`add_dependencies(app dd-dep-<name>)`. Other build systems, custom configure arguments and
install steps belong in application recipes, never in the JSON.

**`application`** is validated but not fetched. A reviewed recipe takes the acquisition
arguments - `GIT_TAG` with dd's Git safety settings, or `URL_HASH` with TLS verification -
and owns the rest: cache layout, `SOURCE_SUBDIR`, patches, options, imported targets and
byproducts. The arguments work with `ExternalProject_Add` too.

```cmake
dd_dependency_arguments("${CMAKE_CURRENT_SOURCE_DIR}/cmake/dd-dependencies.json" codec codec_acquisition)
FetchContent_Declare(codec ${codec_acquisition} SOURCE_SUBDIR build/cmake)
FetchContent_MakeAvailable(codec)
```

Archives extract with the current time, not their own, so a recipe that keeps one source
directory across pins rebuilds what it compiled from the old archive. A
`FETCHCONTENT_SOURCE_DIR_<NAME>` override of a `fetchcontent` or `externalproject` entry
is refused, because it would bypass the pin: a recipe that builds from a local checkout
declares `application`.

## Caches and safety

Each build tree keeps its own cache. Sources live in `_deps/<name>-<pin>-src`; build,
install and ExternalProject directories use the pin's first 16 characters, with a
full-pin marker that rejects a collision. A new pin gets new directories, so earlier
checkouts, and any edits in them, survive.

- CMake refuses a cached Git source that is modified or at another commit, an occupied
  source directory and a linked cache path. It discards no local work, which can also
  reject a library whose own build edits its tracked files; use an upstream fix or an
  application recipe rather than weakening the check.
- Archive sources are fingerprinted after extraction, and edited or unverified contents
  are refused.
- Submodules are not fetched, installed packages never stand in for a declaration, and
  Git runs without prompts, hooks or the `ext` and `file` transports.
- `dd clean` refuses a tree holding edited or unrecognized cached sources, even with
  `--yes`. A recipe's ordinary `_deps/<name>-src` archive cache is recognised when
  the configured project's dependency manifests declare its SHA-256 and its retained
  download matches that hash. Cleanup compares the source with a fresh temporary
  extraction, including when a recipe uses another FetchContent name. Missing
  downloads, changed pins and local source edits are refused.
- A failed download keeps its partial cache and log for inspection; nothing rolls back.
- An offline first build cannot fetch; populated, unchanged caches need no network.
- Configure and build run upstream code and reach the network, so MCP runs them only with
  `--allow-execution`; declaring a dependency runs none of it.

`dd dep list` and `dd doctor` report each dependency as `declared`, which does not mean
it was fetched or built.
