# msquic-openssl — prebuilt static MsQuic + quictls bundles

**Goal:** relocatable, hash-pinned static builds of MsQuic with the quictls
TLS stack, published as CI release artifacts, so that consumers can link a
WebTransport-capable MsQuic without Perl, NASM, an OpenSSL build, or a
10-minute first configure. This repo owns the slow, toolchain-heavy part;
consumers download and link — or FetchContent this repo to build from source.

**Consumer-agnostic by policy:** this project stands alone. No downstream
project (raynet included) is mentioned in the README, code, comments, or
release notes — only in this plan, and these references get removed when the
plan is retired.

## Consumption modes

Both modes export the **same imported targets** (`msquic::msquic`,
`msquic::crypto`, carrying include dirs and the Windows system-lib list), so
consumers write one code path:

1. **Artifact** — download a release archive, `find_package` via the bundled
   cmake config. Seconds, no toolchain beyond a C compiler.
2. **Source** — FetchContent/add_subdirectory this repo; it builds MsQuic +
   quictls exactly as CI does and defines the same targets. This is the
   escape hatch and the recipe that produces mode 1, so they cannot drift.
3. **Standalone** — `scripts/build.ps1` configures, builds, and packages an
   artifact locally; what CI runs, reproducible by a human.

## What it builds

Exactly what raynet's in-tree superbuild produces today, no drift:

- MsQuic pinned to a release tag (start: **v2.5.9**), `QUIC_TLS_LIB=quictls`,
  `QUIC_BUILD_SHARED=OFF`, tools/tests/perf off.
- quictls with MsQuic's trimmed config (the `no-*` flag list lives in MsQuic's
  `submodules/CMakeLists.txt` — we don't restate it, we just run it).
- Static only. Shared libs are explicitly out of scope: static is the raylib
  idiom, and raynet's dev-cert path links quictls `libcrypto` directly.

## Artifact layout

One archive per platform/config, versioned `msquic-openssl-<msquic tag>-<rev>`
(e.g. `v2.5.9-1` — the `-1` is our packaging revision, bumped for
packaging-only fixes):

```
include/
    msquic.h, msquic_posix.h / msquic_winuser.h...  (MsQuic src/inc)
    openssl/*.h                                     (quictls headers, for
                                                     consumers doing cert work)
lib/
    windows: release/msquic.lib + debug/msquic.lib  (both CRT flavors, one zip)
    unix:    libmsquic.a
    - one self-contained library: MsQuic's combined archive already bundles
      every libssl/libcrypto object, so no separate TLS libs ship
lib/cmake/msquic-openssl/
    msquic-openssl-config.cmake     (imported targets: msquic::msquic,
                                     msquic::crypto - include dirs, the Windows
                                     system-lib list, per-config locations;
                                     standard path so plain find_package works)
LICENSES/  (MsQuic MIT, quictls Apache-2.0)
VERSIONS   (msquic tag, quictls commit, compiler)
```

Plus a `SHA256SUMS` file on every release. Consumers pin URL + hash.

## Platform matrix

| Archive | Notes |
|---|---|
| `windows-x64` | One zip, both configs (`lib/release` + `lib/debug`): static libs bake in the MSVC CRT flavor (`/MD` vs `/MDd`), and the cmake config maps them per build config so a Release-only bundle can't break Debug users with LNK2038. |
| `macos-universal` | arm64 + x86_64 via `lipo`; `CMAKE_OSX_DEPLOYMENT_TARGET` pinned (11.0) so it runs on anything current. Release only — mixing configs is fine on unix. |
| `linux-x64` | Built on the **oldest** supported LTS runner (glibc floor). Release only. |
| `linux-arm64` | Later, when someone asks. |

No wasm artifact: the browser backend is JS WebTransport, no MsQuic.

## Repo contents

Small on purpose:

- `CMakeLists.txt` — FetchContent MsQuic at the pinned tag with the config
  above, wrap the results in the exported targets. Must work both standalone
  (CI package build) and consumed via add_subdirectory/FetchContent
  (source mode) — same targets either way.
- `scripts/build.ps1` — cross-platform PowerShell: configure, build, package
  one platform/config; used identically by CI and by a human reproducing an
  artifact locally.
- `scripts/setup_toolchain.ps1` — installs the build prerequisites (Windows:
  Perl, NASM; checks the VS toolset). The toolchain burden lives here, not
  with consumers.
- Workflows in `.github/workflows/` **only** — Gitea Actions falls back to
  reading `.github/` when no `.gitea/` exists, so one copy serves both; keep
  the YAML to features both support (checkout, upload-artifact, matrix, thin
  steps calling `build.ps1`). A matrix build on push, a release job on tag
  that uploads the archives + SHA256SUMS.

## Validation before release

An artifact nobody has linked is not an artifact. The release job must:

1. Unpack the archive into a scratch dir.
2. Build and run a minimal smoke program against it — `MsQuicOpen2` +
   `SHA256()` (proves msquic, libcrypto, headers, and the system-lib list in
   the cmake config all resolve) — with **no** checkout of MsQuic sources.
3. On Windows, do this once per config against a matching `/MD`/`/MDd` build.

## Versioning & update flow

- Tag `v2.5.9-1` → artifacts. Bumping MsQuic = change one pin, tag `v2.6.0-1`.
- quictls security updates arrive via MsQuic's submodule pin, so the update
  path is: bump MsQuic tag (or cherry-pick a submodule bump), tag, release —
  one CI run instead of every user rebuilding OpenSSL.
- raynet consumes by URL + SHA256 (its Stage 8 plan); nothing here knows
  raynet exists.

## Trust posture

- Release artifacts are built only by CI from a tagged commit — never
  uploaded from a workstation. The workflow run is the provenance.
- Consumers verify SHA256; a tampered download fails the build loudly.
- Building from source remains a first-class path (this repo *is* the recipe),
  and raynet keeps its FetchContent fallback.

## Done criteria

- Tagged release with all four archives + SHA256SUMS, produced by CI.
- Smoke validation green on all three OSes, both Windows configs.
- raynet builds against the artifact on all platforms with its source
  fallback untouched (that integration is raynet Stage 8, not this repo).
