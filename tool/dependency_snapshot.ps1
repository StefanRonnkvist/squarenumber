Param(
  [string]$OutputDir = "reports/dependency"
)

$ErrorActionPreference = "Stop"

function Get-PubspecProjectIdentity {
  param(
    [string]$PubspecPath
  )

  $projectRoot = Split-Path -Parent $PubspecPath
  $projectName = (Split-Path -Leaf $projectRoot)
  $version = 'unknown'

  if (Test-Path $PubspecPath) {
    $content = Get-Content -Path $PubspecPath
    $nameLine = $content | Where-Object { $_ -match '^\s*name\s*:\s*' } | Select-Object -First 1
    $versionLine = $content | Where-Object { $_ -match '^\s*version\s*:\s*' } | Select-Object -First 1

    if ($nameLine) {
      $projectName = ($nameLine -split ':', 2)[1].Trim().Trim("'\"")
    }

    if ($versionLine) {
      $version = ($versionLine -split ':', 2)[1].Trim()
    }
  }

  if ([string]::IsNullOrWhiteSpace($projectName)) {
    $projectName = 'app'
  }

  return @{
    Name = $projectName
    Version = $version
  }
}

$projectIdentity = Get-PubspecProjectIdentity -PubspecPath (Join-Path (Split-Path -Parent $PSScriptRoot) 'pubspec.yaml')

New-Item -ItemType Directory -Path $OutputDir -Force | Out-Null

$outdatedPath = "$OutputDir/pub-outdated.txt"
$depsPath = "$OutputDir/pub-deps-compact.txt"
$timestampPath = "$OutputDir/snapshot-timestamp.txt"
$reportPath = "$OutputDir/dependency-health.md"

function Get-PreviousContent {
  param(
    [string]$Path
  )

  if (Test-Path $Path) {
    return Get-Content -Raw -Path $Path
  }

  return $null
}

function Get-DeltaSection {
  param(
    [string]$Label,
    [AllowNull()][string]$PreviousContent,
    [string]$CurrentContent,
    [int]$MaxDiffLines = 80
  )

  if ($null -eq $PreviousContent) {
    return @(
      "### $Label",
      "- Status: New artifact (no previous snapshot file found)."
    )
  }

  if ($PreviousContent -eq $CurrentContent) {
    return @(
      "### $Label",
      "- Status: No change since previous snapshot."
    )
  }

  $previousLines = $PreviousContent -split "`r?`n"
  $currentLines = $CurrentContent -split "`r?`n"
  $diffLinesRaw = Compare-Object -ReferenceObject $previousLines -DifferenceObject $currentLines
  $diffRendered = @()

  foreach ($line in $diffLinesRaw) {
    if ($line.SideIndicator -eq "<=") {
      $diffRendered += "- $($line.InputObject)"
    } elseif ($line.SideIndicator -eq "=>") {
      $diffRendered += "+ $($line.InputObject)"
    }
  }

  $isTruncated = $diffRendered.Count -gt $MaxDiffLines
  if ($isTruncated) {
    $diffRendered = $diffRendered | Select-Object -First $MaxDiffLines
  }

  $section = @(
    "### $Label",
    "- Status: Changed.",
    '```diff'
  )

  $section += $diffRendered

  if ($isTruncated) {
    $section += "# Diff truncated to first $MaxDiffLines lines."
  }

  $section += @(
    '```'
  )

  return $section
}

$previousOutdated = Get-PreviousContent -Path $outdatedPath
$previousDeps = Get-PreviousContent -Path $depsPath

$timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss K"

flutter pub outdated | Out-File -Encoding utf8 $outdatedPath
flutter pub deps --style=compact | Out-File -Encoding utf8 $depsPath
Set-Content -Encoding utf8 $timestampPath $timestamp

$currentOutdated = Get-Content -Raw -Path $outdatedPath
$currentDeps = Get-Content -Raw -Path $depsPath

$outdatedDeltaSection = Get-DeltaSection -Label "pub-outdated.txt" -PreviousContent $previousOutdated -CurrentContent $currentOutdated
$depsDeltaSection = Get-DeltaSection -Label "pub-deps-compact.txt" -PreviousContent $previousDeps -CurrentContent $currentDeps

$reportLines = @(
  "# Dependency Health Snapshot",
  "",
  "Generated: $timestamp",
  "Project: $($projectIdentity.Name) $($projectIdentity.Version)",
  "",
  "## Summary",
  "- Full dependency analysis completed.",
  "- See raw artifacts for exact tool output.",
  "",
  "## Delta Since Previous Snapshot"
)

$reportLines += $outdatedDeltaSection
$reportLines += @("")
$reportLines += $depsDeltaSection
$reportLines += @(
  "",
  "## Raw Artifacts",
  "- $OutputDir/pub-outdated.txt",
  "- $OutputDir/pub-deps-compact.txt",
  "- $OutputDir/snapshot-timestamp.txt",
  "",
  "## Commands Used",
  "- flutter pub outdated",
  "- flutter pub deps --style=compact"
)

$reportLines | Out-File -Encoding utf8 $reportPath

Write-Host "Dependency snapshot updated in $OutputDir"
