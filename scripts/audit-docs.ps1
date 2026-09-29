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

    Gameplay constants (board width, speed range, speed step, history size) live
    in lib/app/main_app.dart and are documented in README.md and the Help tab.
    Those are read from the source rather than repeated here, so retuning the
    game flags stale documentation instead of silently diverging.

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
$helpTest = Get-FileText 'test/help_tab_test.dart'
$appSource = Get-FileText 'lib/app/main_app.dart'
$tasksSource = Get-FileText '.vscode/tasks.json'

if ($failures.Count -gt 0) {
    foreach ($failure in $failures) { Write-Host $failure -ForegroundColor Red }
    exit 1
}

# --- Version agreement ------------------------------------------------------

$pubspecVersion = $null
$msixVersion = $null

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

# --- The version test must not hardcode values that go stale ----------------

# The test should assert against the shared constants. If someone reverts it to
# a literal, the test would pass while reporting the wrong build, which is the
# failure this whole script exists to prevent.
if ($pubspecVersion -and $pubspecBuild) {
    $literalAab = [regex]::Escape("$pubspecVersion+$pubspecBuild")
    if ($versionTest -match $literalAab) {
        Add-Failure "test/information_versions_test.dart hardcodes '$pubspecVersion+$pubspecBuild'; assert against appAabVersion instead so a version bump cannot leave it stale"
        $checks++
    }
    $checks++
    Assert-Match $versionTest 'appAabVersion' 'Version test should assert against appAabVersion' 'test/information_versions_test.dart'
    Assert-Match $versionTest 'appMsixVersion' 'Version test should assert against appMsixVersion' 'test/information_versions_test.dart'
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

# --- Gameplay constants are read from the source, not repeated here ---------

# Every Help tab entry that a player relies on, plus the facts the docs state
# in prose. Retuning the game in main_app.dart must not leave stale copy.
$helpEntries = @(
    'Move the active square',
    'Make a clear',
    'Score and build cascades',
    'Survive the rising pace',
    'Pause, restore, and restart',
    'Track your scores',
    'Tune the game',
    'Play anywhere',
    'Get help and send feedback'
)
foreach ($entry in $helpEntries) {
    Assert-Match $helpSource ([regex]::Escape("title: Text('$entry')")) "Help tab entry '$entry' is missing" 'settings_tab.dart'
}

# The Help tab is the in-app source of truth, so its test should still assert
# the full set of entries rather than a hand-picked few.
foreach ($entry in $helpEntries) {
    Assert-Match $helpTest ([regex]::Escape($entry)) "Help tab test does not cover '$entry'" 'test/help_tab_test.dart'
}

function Get-NumericConstant {
    param(
        [string]$Name,
        [string]$Source
    )

    $script:checks++
    $pattern = "static\s+const\s+(?:int|double)\s+$Name\s*=\s*([0-9.]+)"
    if ($Source -match $pattern) {
        return $Matches[1]
    }
    Add-Failure "main_app.dart : could not read constant $Name"
    return $null
}

$columns = Get-NumericConstant '_fixedColumnsAcross' $appSource
$minSpeed = Get-NumericConstant '_minSpeed' $appSource
$maxSpeed = Get-NumericConstant '_maxSpeed' $appSource
$speedStep = Get-NumericConstant '_speedStep' $appSource
$pointsPerStep = Get-NumericConstant '_pointsPerSpeedStep' $appSource
$maxHistory = Get-NumericConstant '_maxScoreHistoryEntries' $appSource

if ($columns) {
    # Accept the digit or the spelled-out width, and either hyphenated or spaced.
    $columnWords = @{ 5 = 'five|5'; 6 = 'six|6'; 7 = 'seven|7'; 8 = 'eight|8' }
    $columnAlt = if ($columnWords.ContainsKey([int]$columns)) { $columnWords[[int]$columns] } else { [regex]::Escape("$columns") }
    Assert-Match $readme "($columnAlt)[- ]column" "README should state the board width ($columns)" 'README.md'
    Assert-Match $readme 'top 10' 'README should state the top 10 history' 'README.md'
    Assert-Match $helpSource "($columnAlt)[- ]column" "Help tab should name the board width ($columns)" 'settings_tab.dart'
}
if ($maxSpeed -and $minSpeed -and $speedStep -and $pointsPerStep) {
    $speedCap = '{0:0.00}' -f [double]$maxSpeed
    $speedFloor = '{0:0.00}' -f [double]$minSpeed
    $stepLabel = '{0:0.00}' -f [double]$speedStep
    Assert-Match $readme ([regex]::Escape("$speedFloor")) "README should state the minimum speed ($speedFloor)" 'README.md'
    Assert-Match $readme ([regex]::Escape("$speedCap")) "README should state the speed cap ($speedCap)" 'README.md'
    Assert-Match $readme ([regex]::Escape("$pointsPerStep points")) "README should state the speed step ($pointsPerStep points)" 'README.md'
    Assert-Match $helpSource ([regex]::Escape("$speedCap")) "Help tab should state the speed cap ($speedCap)" 'settings_tab.dart'
    Assert-Match $helpSource ([regex]::Escape("$pointsPerStep points")) "Help tab should state the speed step ($pointsPerStep points)" 'settings_tab.dart'
}
if ($maxHistory) {
    Assert-Match $longSynopsis ([regex]::Escape("$maxHistory best completed runs")) "Long synopsis should state the $maxHistory best runs" 'google_play_long_synopsis.txt'
}

# The audit must not be wired to a script that does not exist.
$script:checks++
if ($tasksSource -notmatch [regex]::Escape('scripts/audit-docs.ps1')) {
    Add-Failure 'tasks.json should run scripts/audit-docs.ps1 as part of the release task'
}

# --- README links resolve ---------------------------------------------------

# README is written from the repository root, so links are root-relative.
foreach ($match in [regex]::Matches($readme, '\]\((?!https?:|mailto:)([^)#]+)\)')) {
    $link = $match.Groups[1].Value
    $script:checks++
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
    Write-Host "Rules:      $columns columns, $speedFloor-$speedCap speed, +$stepLabel per $pointsPerStep points, top $maxHistory"
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
