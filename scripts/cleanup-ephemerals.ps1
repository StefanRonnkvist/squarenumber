param(
  [switch]$RunPubGet
)

$ErrorActionPreference = 'Stop'

$root = Split-Path -Parent $PSScriptRoot
Set-Location $root

$targets = @(
  'ios\Flutter\ephemeral\Packages',
  'macos\Flutter\ephemeral\Packages'
)

foreach ($target in $targets) {
  if (Test-Path $target) {
    attrib -R $target /S /D | Out-Null
    Remove-Item $target -Recurse -Force
    Write-Host "Removed: $target"
  } else {
    Write-Host "Not found: $target"
  }
}

if ($RunPubGet) {
  Write-Host 'Running: flutter pub get'
  flutter pub get
}
