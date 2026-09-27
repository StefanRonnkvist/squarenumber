param(
    [Parameter(Mandatory = $true)]
    [ValidateSet('apk', 'appbundle', 'msix')]
    [string]$Target
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$root = Split-Path -Parent $PSScriptRoot
Set-Location $root
$pubspecPath = Join-Path $root 'pubspec.yaml'

if (-not (Test-Path $pubspecPath)) {
    throw "pubspec.yaml not found at: $pubspecPath"
}

$line = Get-Content -Path $pubspecPath | Where-Object { $_ -match '^version:' } | Select-Object -First 1
if (-not $line) {
    throw 'version not found in pubspec.yaml'
}

if ($line -notmatch '^version:\s*([0-9]+\.[0-9]+\.[0-9]+)\+([0-9]+)\s*$') {
    throw 'Expected version format x.y.z+n in pubspec.yaml'
}

$buildName = $Matches[1]
$buildNumber = $Matches[2]
$msixVersion = "$buildName.$buildNumber"

switch ($Target) {
    'apk' {
        flutter build apk --release --build-name $buildName --build-number $buildNumber
    }
    'appbundle' {
        flutter build appbundle --release --build-name $buildName --build-number $buildNumber
    }
    'msix' {
        dart run msix:create --version $msixVersion
    }
}
