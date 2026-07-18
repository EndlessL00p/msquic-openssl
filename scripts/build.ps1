#!/usr/bin/env pwsh
# Build, stage, and package one platform's artifact into dist/.
#
#   windows: one multi-config build tree, Debug + Release both installed (CRT flavors)
#   macos:   one build per architecture, libraries merged with lipo
#   linux:   single Release build
#   ios:     cross-compile on a macOS host (device arm64, MsQuic's ios toolchain)
#   android: cross-compile with the Android NDK (default ABI arm64-v8a)
#
# Per-platform configure flags live in CMakePresets.json (usable standalone via
# cmake --preset <name>); this script adds what presets can't express: host
# prerequisites, staging, lipo, provenance, and the archive.
#
# What CI runs, reproducible by a human: scripts/build.ps1 -Version v2.5.9-1
param(
    [string]$Version = 'dev',       # artifact version label, e.g. v2.5.9-1
    [ValidateSet('', 'ios', 'android')]
    [string]$Target = '',           # cross-compile target; default is the host platform
    [ValidateSet('arm64-v8a', 'armeabi-v7a', 'x86', 'x86_64')]
    [string]$AndroidAbi = 'arm64-v8a',
    [switch]$SingleArch             # macos: current arch only, skip lipo
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'common.ps1')
Set-Location (Join-Path $PSScriptRoot '..')

function Get-CacheValue([string]$Build, [string]$Key) {
    $hit = Select-String -Path (Join-Path $Build 'CMakeCache.txt') -Pattern "^${Key}:\w+=(.+)$" |
        Select-Object -First 1
    if (-not $hit) { Write-Error "$Key not found in $Build/CMakeCache.txt" }
    $hit.Matches[0].Groups[1].Value
}

# Configure, build, and install one tree from its CMakePresets.json preset.
# Single-config generators ignore --config, so one code path serves both.
function Invoke-BuildTree {
    param([string]$Preset, [string]$BuildDir, [string]$Prefix,
          [string[]]$Configs = @('Release'), [string[]]$ExtraArgs = @())
    Invoke-Checked cmake --preset $Preset -B $BuildDir @ExtraArgs
    foreach ($config in $Configs) {
        Invoke-Checked cmake --build $BuildDir --config $config --parallel
        Invoke-Checked cmake --install $BuildDir --config $config --prefix $Prefix
    }
}

$dist = 'dist'
$stage = Join-Path $dist 'stage'
Remove-Item -Recurse -Force $stage -ErrorAction SilentlyContinue
New-Item -ItemType Directory -Force -Path $stage | Out-Null

if ($Target -eq 'ios') {
    if (-not $onMac) { Write-Error 'ios builds need a macOS host with Xcode (iOS SDK)' }
    $platform = 'ios-arm64'

    # MsQuic's OpenSSL step needs its vendored ios toolchain (it reads the
    # SDK_NAME/DEPLOYMENT_TARGET variables that file sets). The toolchain must
    # exist before configure - FetchContent can't supply it - so fetch the
    # copy matching the pinned MsQuic tag; the ios preset points at this path.
    # A marker records the tag the cached copy came from; on a tag bump start
    # the tree fresh (its cache pins the old toolchain's results too).
    $tagHit = Select-String -Path CMakeLists.txt -Pattern 'set\(MSQUIC_TAG "([^"]+)"' |
        Select-Object -First 1
    if (-not $tagHit) { Write-Error 'MSQUIC_TAG not found in CMakeLists.txt' }
    $tag = $tagHit.Matches[0].Groups[1].Value
    $marker = 'build-ios/ios-toolchain.tag'
    if (-not ((Test-Path $marker) -and ((Get-Content $marker) -eq $tag))) {
        Remove-Item -Recurse -Force build-ios -ErrorAction SilentlyContinue
        New-Item -ItemType Directory -Force -Path build-ios | Out-Null
        Invoke-WebRequest "https://raw.githubusercontent.com/microsoft/msquic/$tag/cmake/toolchains/ios.cmake" `
            -OutFile 'build-ios/ios-toolchain.cmake'
        Set-Content $marker $tag
    }

    Invoke-BuildTree -Preset ios -BuildDir build-ios -Prefix $stage
    $versionsBuild = 'build-ios'
} elseif ($Target -eq 'android') {
    if ($onWindows) { Write-Error 'android builds need a macOS or Linux host' }
    $ndk = Find-AndroidNdk
    if (-not $ndk) { Write-Error 'Android NDK not found - set ANDROID_NDK_HOME (https://developer.android.com/ndk)' }
    $platform = 'android-' + @{ 'arm64-v8a' = 'arm64'; 'armeabi-v7a' = 'arm'
                                'x86' = 'x86'; 'x86_64' = 'x64' }[$AndroidAbi]

    # MsQuic's OpenSSL configure needs the NDK env vars (the android preset
    # reads ANDROID_NDK_HOME) and its llvm bin dir on PATH (the prebuilt dir
    # is named for the host; darwin's is universal)
    $hostDir = if ($onMac) { 'darwin-x86_64' } else { 'linux-x86_64' }
    $env:ANDROID_NDK_HOME = $ndk
    $env:ANDROID_NDK_ROOT = $ndk
    $env:PATH = "$ndk/toolchains/llvm/prebuilt/$hostDir/bin" + [IO.Path]::PathSeparator + $env:PATH

    $build = "build-android-$AndroidAbi"
    Invoke-BuildTree -Preset android -BuildDir $build -Prefix $stage `
        -ExtraArgs @("-DANDROID_ABI=$AndroidAbi")
    $versionsBuild = $build
} elseif ($onWindows) {
    # Build natively for the host, so the artifact label matches what cl targets
    $arch = if ($env:PROCESSOR_ARCHITECTURE -eq 'ARM64') { 'arm64' } else { 'x64' }
    $platform = "windows-$arch"

    # The OpenSSL build step runs nmake/cl; enter a VS developer environment
    # if we aren't in one (works from any shell, including CI runners)
    if (-not (Get-Command nmake -ErrorAction SilentlyContinue)) {
        $vswhere = "${env:ProgramFiles(x86)}\Microsoft Visual Studio\Installer\vswhere.exe"
        $vcTools = if ($arch -eq 'arm64') { 'Microsoft.VisualStudio.Component.VC.Tools.ARM64' }
                   else { 'Microsoft.VisualStudio.Component.VC.Tools.x86.x64' }
        $vsPath = & $vswhere -latest -products * -requires $vcTools -property installationPath
        if (-not $vsPath) { Write-Error "no Visual Studio C++ toolset for $arch found (run scripts/setup_toolchain.ps1)" }
        Import-Module (Join-Path $vsPath 'Common7\Tools\Microsoft.VisualStudio.DevShell.dll')
        Enter-VsDevShell -VsInstallPath $vsPath -DevCmdArguments "-arch=$arch" -SkipAutomaticLocation
    }

    # The windows preset pins Ninja Multi-Config; a cache from another
    # generator cannot be reconfigured, so start that case fresh
    if ((Test-Path 'build/CMakeCache.txt') -and -not (Select-String -Path 'build/CMakeCache.txt' `
            -Pattern '^CMAKE_GENERATOR:\w+=Ninja Multi-Config$' -Quiet)) {
        Remove-Item -Recurse -Force build
    }
    Invoke-BuildTree -Preset windows -BuildDir build -Prefix $stage -Configs @('Release', 'Debug')
    $versionsBuild = 'build'
} elseif ($onMac) {
    $archs = @(if ($SingleArch) { uname -m } else { 'arm64'; 'x86_64' })
    foreach ($arch in $archs) {
        Invoke-BuildTree -Preset "macos-$arch" -BuildDir "build-$arch" -Prefix "$stage-$arch"
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
    Invoke-BuildTree -Preset linux -BuildDir build -Prefix $stage
    $versionsBuild = 'build'
}

# Provenance: what exactly is in this artifact. CMAKE_C_COMPILER isn't
# reliably in the cache (VS generators never write it; toolchain files set it
# as a plain variable), so take cl from the dev shell on Windows and CMake's
# generated CMakeCCompiler.cmake - which always records the real path -
# everywhere else.
$msquicTag = Get-CacheValue $versionsBuild 'MSQUIC_TAG'
$quictlsCommit = git -C "$versionsBuild/_deps/msquic-src/submodules/quictls" rev-parse HEAD
$compiler = if ($onWindows) { (Get-Command cl).Source } else {
    $ccFile = Get-ChildItem "$versionsBuild/CMakeFiles/*/CMakeCCompiler.cmake" | Select-Object -First 1
    $hit = if ($ccFile) { Select-String -Path $ccFile -Pattern 'set\(CMAKE_C_COMPILER "(.+)"\)' |
        Select-Object -First 1 }
    if (-not $hit) { Write-Error "CMAKE_C_COMPILER not found under $versionsBuild/CMakeFiles" }
    $hit.Matches[0].Groups[1].Value
}
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
