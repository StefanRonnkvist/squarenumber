param(
  [switch]$KillFlutterProcesses
)

$ErrorActionPreference = 'Stop'

$root = Split-Path -Parent $PSScriptRoot
Set-Location $root

if ($KillFlutterProcesses) {
  $names = @('java', 'dart', 'flutter', 'gradle', 'adb')
  foreach ($name in $names) {
    Get-Process -Name $name -ErrorAction SilentlyContinue |
      Stop-Process -Force -ErrorAction SilentlyContinue
  }
}

$pathsToReset = @(
  'ios/Flutter/ephemeral/Packages',
  'macos/Flutter/ephemeral/Packages',
  'linux/flutter/ephemeral/.plugin_symlinks',
  'windows/flutter/ephemeral/.plugin_symlinks',
  'macos/Flutter/ephemeral/.plugin_symlinks',
  'build/app/intermediates/merged_native_libs',
  'build/app/intermediates/assets/release/mergeReleaseAssets',
  'build/app/intermediates/incremental/packageRelease',
  'build/app/outputs/apk/release'
)

foreach ($path in $pathsToReset) {
  if (Test-Path $path) {
    attrib -R $path /S /D | Out-Null
    Remove-Item $path -Recurse -Force -ErrorAction SilentlyContinue
    Write-Host "Reset: $path"
  }
}

Write-Host 'Running: flutter pub get'
flutter pub get
if ($LASTEXITCODE -ne 0) {
  exit $LASTEXITCODE
}

Write-Host 'Running: flutter build apk --release'
flutter build apk --release
if ($LASTEXITCODE -ne 0) {
  exit $LASTEXITCODE
}
