param(
  [string]$SandboxPath
)

$ErrorActionPreference = 'Stop'

$root = Split-Path -Parent $PSScriptRoot
if ([string]::IsNullOrWhiteSpace($SandboxPath)) {
  $projectName = (Split-Path -Leaf $root)
  $SandboxPath = Join-Path ([System.IO.Path]::GetTempPath()) ("{0}_file_picker_migration_probe" -f $projectName)
}

Set-Location $root

Write-Host "Source: $root"
Write-Host "Sandbox: $SandboxPath"

if (Test-Path $SandboxPath) {
  Remove-Item $SandboxPath -Recurse -Force
}

New-Item -ItemType Directory -Path $SandboxPath | Out-Null

$excludeDirs = @(
  'build',
  '.dart_tool',
  '.idea',
  'ios/Flutter/ephemeral',
  'macos/Flutter/ephemeral',
  'linux/flutter/ephemeral',
  'windows/flutter/ephemeral'
)

$robocopyArgs = @($root, $SandboxPath, '/E', '/XF', '*.log')
foreach ($dir in $excludeDirs) {
  $robocopyArgs += '/XD'
  $robocopyArgs += $dir
}

$null = & robocopy @robocopyArgs
if ($LASTEXITCODE -gt 7) {
  throw "robocopy failed with exit code $LASTEXITCODE"
}

Push-Location $SandboxPath

$summary = [ordered]@{
  upgradedConstraint = $false
  apiPatched = $false
  buildSucceeded = $false
  buildErrorSnippet = ''
}

try {
  $upgradeOutput = (& flutter pub upgrade --major-versions 2>&1 | Out-String)
  if ($upgradeOutput -match 'file_picker: .*-> \^11\.0\.2') {
    $summary.upgradedConstraint = $true
  }

  $mainPath = Join-Path $SandboxPath 'lib/main.dart'
  $mainText = Get-Content $mainPath -Raw
  if ($mainText.Contains('FilePicker.platform.pickFiles')) {
    $mainText = $mainText.Replace('FilePicker.platform.pickFiles', 'FilePicker.pickFiles')
    Set-Content $mainPath $mainText
    $summary.apiPatched = $true
  } elseif ($mainText.Contains('FilePicker.pickFiles')) {
    $summary.apiPatched = $true
  }

  $buildOutput = (& flutter build apk --release 2>&1 | Out-String)
  if ($LASTEXITCODE -eq 0 -or $buildOutput -match 'Built build\\app\\outputs\\flutter-apk\\app-release.apk') {
    $summary.buildSucceeded = $true
  } else {
    if ($buildOutput -match 'GeneratedPluginRegistrant\.java:[\s\S]{0,400}') {
      $summary.buildErrorSnippet = $matches[0]
    } else {
      $summary.buildErrorSnippet = $buildOutput.Substring(0, [Math]::Min(500, $buildOutput.Length))
    }
  }
}
finally {
  Pop-Location
}

Write-Host ''
Write-Host 'Migration Probe Summary'
Write-Host "- upgradedConstraint: $($summary.upgradedConstraint)"
Write-Host "- apiPatched: $($summary.apiPatched)"
Write-Host "- buildSucceeded: $($summary.buildSucceeded)"
if ($summary.buildErrorSnippet) {
  Write-Host '- buildErrorSnippet:'
  Write-Host $summary.buildErrorSnippet
}

if (-not $summary.buildSucceeded) {
  exit 1
}
