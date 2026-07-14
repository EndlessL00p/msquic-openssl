#!/usr/bin/env pwsh
# Build, stage, and package one platform's artifact into dist/.
#
#   windows: one multi-config build tree, Debug + Release both installed (CRT flavors)
#   macos:   one build per architecture, libraries merged with lipo
#   linux:   single Release build
#
# What CI runs, reproducible by a human: scripts/build.ps1 -Version v2.5.9-1
param(
    [string]$Version = 'dev',       # artifact version label, e.g. v2.5.9-1
    [switch]$SingleArch             # macos: current arch only, skip lipo
)

$ErrorActionPreference = 'Stop'
Set-Location (Join-Path $PSScriptRoot '..')

$onWindows = ($PSVersionTable.PSEdition -eq 'Desktop') -or $IsWindows
$onMac = (-not $onWindows) -and $IsMacOS

function Invoke-Checked {
    & $args[0] @($args[1..($args.Count-1)])
    if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
}

function Get-CacheValue([string]$Build, [string]$Key) {
    $hit = Select-String -Path (Join-Path $Build 'CMakeCache.txt') -Pattern "^${Key}:\w+=(.+)$" |
        Select-Object -First 1
    if (-not $hit) { Write-Error "$Key not found in $Build/CMakeCache.txt" }
    $hit.Matches[0].Groups[1].Value
}

$dist = 'dist'
$stage = Join-Path $dist 'stage'
Remove-Item -Recurse -Force $stage -ErrorAction SilentlyContinue
New-Item -ItemType Directory -Force -Path $stage | Out-Null

if ($onWindows) {
    $platform = 'windows-x64'
    if ($env:PROCESSOR_ARCHITECTURE -eq 'ARM64') { $platform = 'windows-arm64' }

    # The OpenSSL build step runs nmake/cl; enter a VS developer environment
    # if we aren't in one (works from any shell, including CI runners)
    if (-not (Get-Command nmake -ErrorAction SilentlyContinue)) {
        $vswhere = "${env:ProgramFiles(x86)}\Microsoft Visual Studio\Installer\vswhere.exe"
        $vsPath = & $vswhere -latest -products * -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath
        if (-not $vsPath) { Write-Error 'no Visual Studio C++ toolset found (run scripts/setup_toolchain.ps1)' }
        Import-Module (Join-Path $vsPath 'Common7\Tools\Microsoft.VisualStudio.DevShell.dll')
        Enter-VsDevShell -VsInstallPath $vsPath -DevCmdArguments '-arch=x64' -SkipAutomaticLocation
    }

    # Debug + Release from one tree needs a multi-config generator; the
    # default is environment-dependent (plain Ninja would silently ignore
    # --config and ship a Debug-only artifact). A cache from another
    # generator cannot be reconfigured, so start that case fresh.
    if ((Test-Path 'build/CMakeCache.txt') -and -not (Select-String -Path 'build/CMakeCache.txt' `
            -Pattern '^CMAKE_GENERATOR:\w+=Ninja Multi-Config$' -Quiet)) {
        Remove-Item -Recurse -Force build
    }
    Invoke-Checked cmake -B build -G 'Ninja Multi-Config'
    Invoke-Checked cmake --build build --config Release --parallel
    Invoke-Checked cmake --build build --config Debug --parallel
    Invoke-Checked cmake --install build --config Release --prefix $stage
    Invoke-Checked cmake --install build --config Debug --prefix $stage
    $versionsBuild = 'build'
} elseif ($onMac) {
    $archs = @(if ($SingleArch) { uname -m } else { 'arm64'; 'x86_64' })
    foreach ($arch in $archs) {
        Invoke-Checked cmake -B "build-$arch" `
            '-DCMAKE_BUILD_TYPE=Release' `
            "-DCMAKE_OSX_ARCHITECTURES=$arch" `
            '-DCMAKE_OSX_DEPLOYMENT_TARGET=11.0'
        Invoke-Checked cmake --build "build-$arch" --parallel
        Invoke-Checked cmake --install "build-$arch" --prefix "$stage-$arch"
    }
    Copy-Item -Recurse "$stage-$($archs[0])/*" $stage
    if ($archs.Count -gt 1) {
        $platform = 'macos-universal'
        # Headers come from the first arch; warn if the arch-specific OpenSSL
        # configuration header differs between the two
        $confs = $archs | ForEach-Object { Get-FileHash "$stage-$_/include/openssl/configuration.h" }
        if (($confs | Select-Object -Unique -ExpandProperty Hash).Count -gt 1) {
            Write-Warning 'openssl/configuration.h differs between architectures'
        }
        $libs = $archs | ForEach-Object { "$stage-$_/lib/libmsquic.a" }
        Invoke-Checked lipo -create @libs -output "$stage/lib/libmsquic.a"
    } else {
        $platform = "macos-$($archs[0])"
    }
    $versionsBuild = "build-$($archs[0])"
} else {
    $arch = switch (uname -m) { 'x86_64' { 'x64' } 'aarch64' { 'arm64' } default { uname -m } }
    $platform = "linux-$arch"
    Invoke-Checked cmake -B build '-DCMAKE_BUILD_TYPE=Release'
    Invoke-Checked cmake --build build --parallel
    Invoke-Checked cmake --install build --prefix $stage
    $versionsBuild = 'build'
}

# Provenance: what exactly is in this artifact. Visual Studio generators
# never cache CMAKE_C_COMPILER, so on Windows take cl from the dev shell.
$msquicTag = Get-CacheValue $versionsBuild 'MSQUIC_TAG'
$quictlsCommit = git -C "$versionsBuild/_deps/msquic-src/submodules/quictls" rev-parse HEAD
$compiler = if ($onWindows) { (Get-Command cl).Source }
            else { Get-CacheValue $versionsBuild 'CMAKE_C_COMPILER' }
@(
    "msquic:   $msquicTag"
    "quictls:  $quictlsCommit"
    "compiler: $compiler"
    "platform: $platform"
    "built:    $((Get-Date).ToUniversalTime().ToString('yyyy-MM-dd HH:mm')) UTC"
) | Set-Content (Join-Path $stage 'VERSIONS')

# Archive + checksum
$name = "msquic-openssl-$Version-$platform"
$zip = Join-Path $dist "$name.zip"
Remove-Item $zip -ErrorAction SilentlyContinue
Compress-Archive -Path "$stage/*" -DestinationPath $zip
$hash = (Get-FileHash -Algorithm SHA256 $zip).Hash.ToLower()
"$hash  $name.zip" | Set-Content (Join-Path $dist "$name.zip.sha256")

Write-Host ''
Write-Host "packaged $zip"
Write-Host "sha256   $hash"
