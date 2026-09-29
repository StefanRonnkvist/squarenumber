param(
    [switch]$Quiet
)

<#
.SYNOPSIS
    Checks that README.md, store_listing/, and the Help tab describe the app
    that is actually being shipped.

.DESCRIPTION
    Version numbers live in three places (pubspec.yaml, android/local.properties,
    and lib/app/app_metadata.dart) and are echoed in README.md and a test. They
    drift silently: the app keeps building while the Information tab and the
    feedback diagnostics report the wrong build.

    This script fails when those sources disagree, when the store listing breaks
    the Google Play length limits, or when README links point at files that do
    not exist.

.EXAMPLE
    pwsh -NoProfile -ExecutionPolicy Bypass -File scripts/audit-docs.ps1
#>

$ErrorActionPreference = 'Stop'

$root = Split-Path -Parent $PSScriptRoot
$failures = [System.Collections.Generic.List[string]]::new()
$checks = 0

function Add-Failure {
    param([string]$Message)
    $failures.Add($Message) | Out-Null
}

function Get-FileText {
    param([string]$RelativePath)

    $path = Join-Path $root $RelativePath
    if (-not (Test-Path $path)) {
        Add-Failure "Missing file: $RelativePath"
        return $null
    }
    return (Get-Content -Path $path -Raw)
}

function Assert-Match {
    param(
        [string]$Content,
        [string]$Pattern,
        [string]$Label,
        [string]$File
    )

    $script:checks++
    if ($Content -notmatch $Pattern) {
        Add-Failure "$Label : expected /$Pattern/ in $File"
    }
}

function Assert-Equal {
    param(
        [string]$Actual,
        [string]$Expected,
        [string]$Label
    )

    $script:checks++
    if ($Actual -ne $Expected) {
        Add-Failure "$Label : expected '$Expected' but found '$Actual'"
    }
}

# --- Read the sources -------------------------------------------------------

$pubspec = Get-FileText 'pubspec.yaml'
$metadata = Get-FileText 'lib/app/app_metadata.dart'
$readme = Get-FileText 'README.md'
$shortSynopsis = Get-FileText 'store_listing/google_play_short_synopsis.txt'
$longSynopsis = Get-FileText 'store_listing/google_play_long_synopsis.txt'
$helpSource = Get-FileText 'lib/features/settings/widgets/settings_tab.dart'
$versionTest = Get-FileText 'test/information_versions_test.dart'

if ($failures.Count -gt 0) {
    foreach ($failure in $failures) { Write-Host $failure -ForegroundColor Red }
    exit 1
}

# --- Version agreement ------------------------------------------------------

$pubspecVersion = $null
$msixVersion = $null
$packageName = $null

if ($pubspec -match '(?m)^version:\s*([0-9]+\.[0-9]+\.[0-9]+)\+([0-9]+)\s*$') {
    $pubspecVersion = $Matches[1]
    $pubspecBuild = $Matches[2]
} else {
    Add-Failure 'pubspec.yaml : could not parse a "version: x.y.z+n" line'
}

if ($pubspec -match '(?m)^\s+msix_version:\s*([0-9]+\.[0-9]+\.[0-9]+\.[0-9]+)\s*$') {
    $msixVersion = $Matches[1]
} else {
    Add-Failure 'pubspec.yaml : could not parse an msix_version line'
}

if ($metadata -match "appVersion\s*=\s*'([^']+)'") {
    $metadataVersion = $Matches[1]
} else {
    Add-Failure 'app_metadata.dart : could not parse appVersion'
}

if ($metadata -match "appBuildNumber\s*=\s*'([^']+)'") {
    $metadataBuild = $Matches[1]
} else {
    Add-Failure 'app_metadata.dart : could not parse appBuildNumber'
}

if ($metadata -match "appMsixVersion\s*=\s*'([^']+)'") {
    $metadataMsix = $Matches[1]
} else {
    Add-Failure 'app_metadata.dart : could not parse appMsixVersion'
}

if ($metadata -match "appPackageName\s*=\s*'([^']+)'") {
    $metadataPackage = $Matches[1]
} else {
    Add-Failure 'app_metadata.dart : could not parse appPackageName'
}

if ($pubspecVersion -and $metadataVersion) {
    Assert-Equal $metadataVersion $pubspecVersion 'Version mismatch (app_metadata vs pubspec)'
}
if ($pubspecBuild -and $metadataBuild) {
    Assert-Equal $metadataBuild $pubspecBuild 'Build number mismatch (app_metadata vs pubspec)'
}
if ($msixVersion -and $metadataMsix) {
    Assert-Equal $metadataMsix $msixVersion 'MSIX mismatch (app_metadata vs pubspec)'
}

# app_metadata must be the four-part form of the Flutter version.
if ($pubspecVersion -and $pubspecBuild -and $msixVersion) {
    $expectedMsix = "$pubspecVersion.$pubspecBuild"
    Assert-Equal $msixVersion $expectedMsix 'MSIX version is not <flutter version>.<build number>'
}

# --- README echoes the current version --------------------------------------

if ($pubspecVersion -and $pubspecBuild) {
    $aabVersion = "$pubspecVersion+$pubspecBuild"
    Assert-Match $readme ([regex]::Escape($aabVersion)) 'Version table' 'README.md'
    Assert-Match $readme ([regex]::Escape($msixVersion)) 'Version table' 'README.md'
}
if ($metadataPackage) {
    Assert-Match $readme ([regex]::Escape($metadataPackage)) 'Version table' 'README.md'
}

# --- The version test must assert the same values the app ships --------------

if ($pubspecVersion -and $pubspecBuild) {
    Assert-Match $versionTest ([regex]::Escape("$pubspecVersion+$pubspecBuild")) 'Version assertion' 'test/information_versions_test.dart'
}

# --- Store listing limits ---------------------------------------------------

# Google Play: short description max 80 characters, full description max 4000.
$shortLength = $shortSynopsis.Trim().Length
$longLength = $longSynopsis.Trim().Length

$checks++
if ($shortLength -gt 80) {
    Add-Failure "Short synopsis is $shortLength characters; Google Play allows 80"
}

$checks++
if ($longLength -gt 4000) {
    Add-Failure "Long synopsis is $longLength characters; Google Play allows 4000"
}

# --- Help tab documents the rules the code enforces -------------------------

Assert-Match $helpSource 'Move the active square' 'Help tab is missing an entry' 'settings_tab.dart'
Assert-Match $helpSource 'Make a clear' 'Help tab is missing an entry' 'settings_tab.dart'
Assert-Match $helpSource 'Tune the game' 'Help tab is missing an entry' 'settings_tab.dart'
Assert-Match $helpSource 'five-column' 'Help tab should name the board size' 'settings_tab.dart'
Assert-Match $helpSource '1\.50x' 'Help tab should state the speed cap' 'settings_tab.dart'
Assert-Match $helpSource '500 points' 'Help tab should state the speed step' 'settings_tab.dart'

# --- README links resolve ---------------------------------------------------

$checks++
foreach ($match in [regex]::Matches($readme, '\]\((?!https?:)([^)#]+)\)')) {
    $link = $match.Groups[1].Value
    $linkPath = Join-Path $root $link
    if (-not (Test-Path $linkPath)) {
        Add-Failure "README.md links to '$link' but that path does not exist"
    }
}

# --- Report -----------------------------------------------------------------

if (-not $Quiet) {
    Write-Host "Version:    $pubspecVersion+$pubspecBuild (MSIX $msixVersion)"
    Write-Host "Short:      $shortLength/80 characters"
    Write-Host "Long:       $longLength/4000 characters"
    Write-Host "Checks:     $checks"
}

if ($failures.Count -gt 0) {
    Write-Host ''
    foreach ($failure in $failures) { Write-Host "FAIL $failure" -ForegroundColor Red }
    Write-Host ''
    Write-Host "$($failures.Count) documentation problem(s) found." -ForegroundColor Red
    exit 1
}

if (-not $Quiet) {
    Write-Host 'Documentation is consistent.' -ForegroundColor Green
}
exit 0
