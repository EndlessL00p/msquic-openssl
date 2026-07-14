#!/usr/bin/env pwsh
# Validate a packaged archive: unpack it and build + run tests/smoke against
# it with no MsQuic/quictls sources present. No release without this passing.
param(
    [Parameter(Mandatory)][string]$Archive
)

$ErrorActionPreference = 'Stop'
Set-Location (Join-Path $PSScriptRoot '..')
$onWindows = ($PSVersionTable.PSEdition -eq 'Desktop') -or $IsWindows

$work = Join-Path ([IO.Path]::GetTempPath()) ("mq_smoke_" + [IO.Path]::GetRandomFileName())
try {
    $root = Join-Path $work 'artifact'
    Expand-Archive -Path $Archive -DestinationPath $root

    $configs = if ($onWindows) { @('Release', 'Debug') } else { @('Release') }
    cmake -B (Join-Path $work 'build') -S tests/smoke "-DCMAKE_PREFIX_PATH=$root"
    if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
    foreach ($config in $configs) {
        cmake --build (Join-Path $work 'build') --config $config
        if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
        $exe = @("$work/build/smoke", "$work/build/smoke.exe", "$work/build/$config/smoke.exe") |
            Where-Object { Test-Path $_ } | Select-Object -First 1
        $out = & $exe
        Write-Host "[$config] $out"
        if (($LASTEXITCODE -ne 0) -or ($out -notmatch 'SMOKE_PASS')) {
            Write-Host "FAIL: smoke did not pass for $config"
            exit 1
        }
    }
    Write-Host "PASS: $Archive"
} finally {
    Remove-Item -Recurse -Force $work -ErrorAction SilentlyContinue
}
