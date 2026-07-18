# Shared helpers for the scripts in this directory. Dot-source, don't run:
#   . (Join-Path $PSScriptRoot 'common.ps1')

# $IsWindows/$IsMacOS don't exist in Windows PowerShell 5.1 (Desktop edition)
$onWindows = ($PSVersionTable.PSEdition -eq 'Desktop') -or $IsWindows
$onMac = (-not $onWindows) -and $IsMacOS

# Run a native command and stop on a failing exit code
# ($ErrorActionPreference = 'Stop' alone doesn't cover those)
function Invoke-Checked {
    & $args[0] @($args[1..($args.Count-1)])
    if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
}

# First Android NDK env var that points at an existing directory, else $null
function Find-AndroidNdk {
    @($env:ANDROID_NDK_HOME, $env:ANDROID_NDK_LATEST_HOME, $env:ANDROID_NDK_ROOT) |
        Where-Object { $_ -and (Test-Path $_) } | Select-Object -First 1
}
