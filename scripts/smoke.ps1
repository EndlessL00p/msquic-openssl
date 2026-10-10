#!/usr/bin/env pwsh
# Validate a packaged archive: unpack it and build + run tests/smoke against
# it with no MsQuic/OpenSSL sources present. No release without this passing.
# Cross targets (ios/android) can't run on the build host, so validation is
# the link: the smoke binary must build against the artifact.
param(
    [Parameter(Mandatory)][string]$Archive,
    [ValidateSet('', 'ios', 'android')]
    [string]$Target = '',           # cross target the archive was built for
    [ValidateSet('arm64-v8a', 'armeabi-v7a', 'x86', 'x86_64')]
    [string]$AndroidAbi = 'arm64-v8a'
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'common.ps1')
Set-Location (Join-Path $PSScriptRoot '..')

$work = Join-Path ([IO.Path]::GetTempPath()) ("mq_smoke_" + [IO.Path]::GetRandomFileName())
try {
    $root = Join-Path $work 'artifact'
    Expand-Archive -Path $Archive -DestinationPath $root

    # The smoke program is plain C, so CMake's native cross support is enough
    # here; only MsQuic's own OpenSSL build needs the heavier toolchain files
    $crossArgs = @()
    if ($Target -eq 'ios') {
        $crossArgs = @('-DCMAKE_SYSTEM_NAME=iOS', '-DCMAKE_OSX_ARCHITECTURES=arm64',
                       '-DCMAKE_OSX_SYSROOT=iphoneos', '-DCMAKE_OSX_DEPLOYMENT_TARGET=13.0')
    } elseif ($Target -eq 'android') {
        $ndk = Find-AndroidNdk
        if (-not $ndk) { Write-Error 'Android NDK not found - set ANDROID_NDK_HOME' }
        $crossArgs = @("-DCMAKE_TOOLCHAIN_FILE=$ndk/build/cmake/android.toolchain.cmake",
                       "-DANDROID_ABI=$AndroidAbi", '-DANDROID_PLATFORM=android-29')
    }

    $configs = if ($Target) { @('Release') }
               elseif ($onWindows) { @('Release', 'Debug') } else { @('Release') }
    Invoke-Checked cmake -B (Join-Path $work 'build') -S tests/smoke "-DCMAKE_PREFIX_PATH=$root" @crossArgs
    foreach ($config in $configs) {
        Invoke-Checked cmake --build (Join-Path $work 'build') --config $config
        $exe = @("$work/build/smoke", "$work/build/smoke.exe", "$work/build/$config/smoke.exe",
                 "$work/build/smoke.app/smoke") |    # ios: executables become bundles
            Where-Object { Test-Path $_ } | Select-Object -First 1
        if (-not $exe) {
            Write-Host "FAIL: no smoke binary produced for $config"
            exit 1
        }
        if ($Target) {
            Write-Host "[$config] linked (cross target $Target - not run)"
            continue
        }
        $out = & $exe
        Write-Host "[$config] $out"
        if (($LASTEXITCODE -ne 0) -or ($out -notmatch 'SMOKE_PASS')) {
            Write-Host "FAIL: smoke did not pass for $config"
            exit 1
        }
    }
    if ($Target) { Write-Host "PASS (link only): $Archive" }
    else { Write-Host "PASS: $Archive" }
} finally {
    Remove-Item -Recurse -Force $work -ErrorAction SilentlyContinue
}
