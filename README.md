# msquic-openssl

This is an independent project that packages and redistributes
prebuilt **static** libraries of:
[MsQuic](https://github.com/microsoft/msquic) with the
[quictls](https://github.com/quictls/openssl) TLS stack, published as
hash-verified release archives for use with CMake.

> It is **NOT** affiliated with or endorsed by Microsoft, the MsQuic or OpenSSL projects, or thier maintainers.

This project will switch to OpenSSL as the MsQuic TLS provider once support hits a versioned release.

## Why does this exist?

I needed a prebuilt distribution of **MsQuic+quictls** without the need
to install the full toolchain (Perl/NASM) to compile OpenSSL.

For convenience, you can use this project with CMake in two ways:
- use a prebuilt archive
- include the full source build

Both expose the same targets via FetchContent
[msquic::msquic] and [msquic::crypto]

## AI disclosure

This build tooling was entirely written by Claude Fable 5.

## Archive Contents

Each archive contains the MsQuic public headers, the quictls `openssl/`
headers, one self-contained static library (libssl and libcrypto objects
included), and a CMake package config:

```
include/            msquic.h ... + openssl/*.h
lib/                libmsquic.a          (windows: lib/release + lib/debug msquic.lib)
lib/cmake/msquic-openssl/msquic-openssl-config.cmake
LICENSES/           MsQuic (MIT), OpenSSL (Apache-2.0)
VERSIONS            exact msquic tag, openssl commit, compiler
```

## Using an archive

```cmake
# after unpacking, or via FetchContent URL + URL_HASH:
find_package(msquic-openssl CONFIG REQUIRED
             PATHS ${path_to_unpacked_archive} NO_DEFAULT_PATH)

target_link_libraries(your_app PRIVATE msquic::msquic)   # QUIC + TLS
target_link_libraries(your_app PRIVATE msquic::crypto)   # + openssl headers /
                                                         #   libcrypto, if you do
                                                         #   your own cert work
```

The targets carry everything: include paths, `QUIC_BUILD_STATIC`, and the
platform link requirements (Windows system libraries, Apple frameworks).
Windows archives ship Release **and** Debug libraries; multi-config
generators pick the matching CRT flavor automatically.

Verify downloads against the `SHA256SUMS` attached to each release (CMake:
pass `URL_HASH` to FetchContent).

## Building from source instead

The same targets, defined by building MsQuic+OpenSSL locally:

```cmake
include(FetchContent)
FetchContent_Declare(msquic-openssl
    GIT_REPOSITORY <this repo>
    GIT_TAG v2.5.9-1)
FetchContent_MakeAvailable(msquic-openssl)
# msquic::msquic and msquic::crypto now exist, identical to the artifact's
```

Prerequisites for source builds: CMake, a C/C++ toolchain, Perl; Windows
also NASM (`scripts/setup_toolchain.ps1` installs what's missing —
PowerShell 7 on macOS/Linux: `brew install --cask powershell`).

## Reproducing an artifact

```sh
./scripts/setup_toolchain.ps1     # once
./scripts/build.ps1               # build + stage + zip into dist/
./scripts/smoke.ps1 -Archive dist/msquic-openssl-dev-<platform>.zip
```

`build.ps1` enters the Visual Studio developer environment itself on
Windows, builds both CRT configs there, and produces universal
(arm64 + x86_64) libraries on macOS. CI runs exactly these scripts; release
artifacts are only ever built by CI from a tagged commit.

## Versioning

Tags are `<msquic tag>-<packaging revision>`: `v2.5.9-1` wraps MsQuic
v2.5.9; a `-2` would fix packaging only. The `VERSIONS` file in every
archive records the exact msquic tag and openssl commit inside.

## License

Build scripts and CMake glue in this repo: [MIT](LICENSE). The artifacts
contain MsQuic (MIT) and OpenSSL (Apache-2.0), see (THIRD_PARTY_NOTICES);
Both license texts ship in every archive under `LICENSES/`.
