#!/usr/bin/env pwsh
# One-time build prerequisites - all platforms, one script.
#
# The OpenSSL build needs Perl, and on Windows NASM and the VS C++
# toolset (scripts/build.ps1 enters the VS developer environment itself).
# Installs what's missing via winget (Windows) or brew (macOS); prints what
# to install elsewhere. Idempotent; CI runs it too.

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'common.ps1')

function Test-Command($name) {
    return $null -ne (Get-Command $name -ErrorAction SilentlyContinue)
}

function Update-SessionPath {
    if ($onWindows) {
        $env:Path = [Environment]::GetEnvironmentVariable('Path', 'Machine') + ';' +
                    [Environment]::GetEnvironmentVariable('Path', 'User')
    }
}

function Install-IfMissing($command, $wingetId, $brewName, $hint) {
    if (Test-Command $command) {
        Write-Host "found $command"
        return
    }
    if ($onWindows -and (Test-Command winget)) {
        Write-Host "installing $wingetId..."
        winget install --id $wingetId -e --accept-source-agreements --accept-package-agreements
        Update-SessionPath
    } elseif ($onMac -and (Test-Command brew)) {
        Write-Host "installing $brewName..."
        brew install $brewName
    } else {
        Write-Warning "missing $command - install it manually ($hint)"
    }
}

Install-IfMissing git   Git.Git       git   'https://git-scm.com or your package manager'
Install-IfMissing cmake Kitware.CMake cmake 'https://cmake.org or your package manager'
Install-IfMissing perl  StrawberryPerl.StrawberryPerl perl 'usually preinstalled on unix'

if ($onWindows) {
    Install-IfMissing nasm NASM.NASM $null $null

    # The NASM installer doesn't add itself to PATH
    if (-not (Test-Command nasm)) {
        $nasmDir = @("$env:ProgramFiles\NASM", "$env:LocalAppData\bin\NASM") |
            Where-Object { Test-Path (Join-Path $_ 'nasm.exe') } | Select-Object -First 1
        if ($nasmDir) {
            $userPath = [Environment]::GetEnvironmentVariable('Path', 'User')
            [Environment]::SetEnvironmentVariable('Path', "$userPath;$nasmDir", 'User')
            $env:Path += ";$nasmDir"
            Write-Host "added $nasmDir to user PATH"
        } else {
            Write-Warning 'nasm still not on PATH - add its install directory to PATH before building'
        }
    }

    $vswhere = "${env:ProgramFiles(x86)}\Microsoft Visual Studio\Installer\vswhere.exe"
    $vsPath = $null
    if (Test-Path $vswhere) {
        $vsPath = & $vswhere -latest -products * -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath
    }
    if ($vsPath) {
        Write-Host 'found Visual Studio C++ toolset'
    } else {
        Write-Warning ("no Visual Studio C++ toolset found. Install it with:`n" +
            '  winget install Microsoft.VisualStudio.2022.BuildTools --override "--add Microsoft.VisualStudio.Workload.VCTools --includeRecommended --passive"')
    }
} elseif ($onMac) {
    if (-not (Test-Command clang)) {
        Write-Warning 'no C compiler found - run: xcode-select --install'
    }
}

# Cross targets (scripts/build.ps1 -Target ios|android) are opt-in; report
# what's available rather than installing multi-GB SDKs
if ($onMac) {
    $iosSdk = if (Test-Command xcrun) { & xcrun --sdk iphoneos --show-sdk-path 2>$null } else { $null }
    if ($iosSdk) { Write-Host 'found iOS SDK (for -Target ios)' }
    else { Write-Host 'no iOS SDK - -Target ios needs full Xcode' }
}
if (-not $onWindows) {
    $ndk = Find-AndroidNdk
    if ($ndk) { Write-Host "found Android NDK: $ndk" }
    else { Write-Host 'no Android NDK - -Target android needs ANDROID_NDK_HOME set' }
}

Write-Host ''
Write-Host 'Toolchain ready. Build + package with: ./scripts/build.ps1'
