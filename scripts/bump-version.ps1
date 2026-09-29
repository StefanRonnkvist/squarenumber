param(
    [int]$PatchIncrement = 1,
    [switch]$NoGit
)

$ErrorActionPreference = 'Stop'

$root = Split-Path -Parent $PSScriptRoot
$pubspecPath = Join-Path $root 'pubspec.yaml'

if (-not (Test-Path $pubspecPath)) {
    throw "pubspec.yaml was not found at $pubspecPath"
}

$lines = Get-Content -Path $pubspecPath
$versionUpdated = $false
$msixUpdated = $false
$major = 0
$minor = 0
$patch = 0
$build = 0
$newPatch = 0

for ($i = 0; $i -lt $lines.Count; $i++) {
    $line = $lines[$i]

    if ($line -match '^version:\s*([0-9]+)\.([0-9]+)\.([0-9]+)\+([0-9]+)\s*$') {
        $major = [int]$Matches[1]
        $minor = [int]$Matches[2]
        $patch = [int]$Matches[3]
        $build = [int]$Matches[4] + 1
        $newPatch = $patch + $PatchIncrement
        $newVersion = "$major.$minor.$newPatch+$build"
        $lines[$i] = "version: $newVersion"
        $versionUpdated = $true
    }
    elseif ($line -match '^  msix_version:\s*([0-9]+)\.([0-9]+)\.([0-9]+)\.([0-9]+)\s*$') {
        $newMsixVersion = "$major.$minor.$newPatch.$build"
        if (-not $versionUpdated) {
            $newMsixVersion = "$major.$minor.$($patch + $PatchIncrement).$build"
        }
        $lines[$i] = "  msix_version: $newMsixVersion"
        $msixUpdated = $true
    }
}

if (-not $versionUpdated) {
    throw "Could not find a Flutter version line in pubspec.yaml"
}

if (-not $msixUpdated) {
    $newMsixVersion = "$major.$minor.$newPatch.$build"
    $lines += "msix_config:"
    $lines += "  msix_version: $newMsixVersion"
}

Set-Content -Path $pubspecPath -Value ($lines -join [Environment]::NewLine)

$androidPropsPath = Join-Path $root 'android/local.properties'
if (Test-Path $androidPropsPath) {
    $androidLines = Get-Content -Path $androidPropsPath
    $versionNameUpdated = $false
    $versionCodeUpdated = $false

    for ($i = 0; $i -lt $androidLines.Count; $i++) {
        if ($androidLines[$i] -match '^flutter.versionName=') {
            $androidLines[$i] = "flutter.versionName=$major.$minor.$newPatch"
            $versionNameUpdated = $true
        }
        elseif ($androidLines[$i] -match '^flutter.versionCode=') {
            $androidLines[$i] = "flutter.versionCode=$build"
            $versionCodeUpdated = $true
        }
    }

    if (-not $versionNameUpdated) {
        $androidLines += "flutter.versionName=$major.$minor.$newPatch"
    }

    if (-not $versionCodeUpdated) {
        $androidLines += "flutter.versionCode=$build"
    }

    Set-Content -Path $androidPropsPath -Value ($androidLines -join [Environment]::NewLine)
}

$androidVersionName = "$major.$minor.$newPatch"
$androidVersionCode = $build
$msixVersion = "$major.$minor.$newPatch.$build"

# lib/app/app_metadata.dart is the source shown in the Information tab and the
# support diagnostics. Leaving it untouched is what caused it to drift behind
# pubspec.yaml, so it is regenerated from the same computed values here.
$metadataPath = Join-Path $root 'lib/app/app_metadata.dart'
if (Test-Path $metadataPath) {
    $metadata = Get-Content -Path $metadataPath -Raw

    $replacements = @(
        @{
            Pattern = "const\s+String\s+appVersion\s*=\s*'[^']*'"
            Value   = "const String appVersion = '$androidVersionName'"
        },
        @{
            Pattern = "const\s+String\s+appBuildNumber\s*=\s*'[^']*'"
            Value   = "const String appBuildNumber = '$androidVersionCode'"
        },
        @{
            Pattern = "const\s+String\s+appMsixVersion\s*=\s*'[^']*'"
            Value   = "const String appMsixVersion = '$msixVersion'"
        }
    )

    foreach ($replacement in $replacements) {
        $pattern = $replacement.Pattern
        $value = $replacement.Value
        $updated = [regex]::Replace($metadata, $pattern, $value)
        if ($updated -eq $metadata) {
            Write-Warning "Could not find $value assignment in lib/app/app_metadata.dart; update it manually."
        }
        $metadata = $updated
    }

    Set-Content -Path $metadataPath -Value $metadata -NoNewline
}

Write-Host "Flutter version: $androidVersionName+$androidVersionCode"
Write-Host "Android versionName: $androidVersionName"
Write-Host "Android versionCode: $androidVersionCode"
Write-Host "MSIX version: $msixVersion"

if (-not $NoGit) {
    $gitRoot = git -C $root rev-parse --show-toplevel 2>$null
    if ($LASTEXITCODE -eq 0 -and $gitRoot) {
        $gitStatus = git -C $root status --short
        if ($gitStatus) {
            git -C $root add pubspec.yaml android/local.properties lib/app/app_metadata.dart
            if ($LASTEXITCODE -eq 0) {
                git -C $root commit -m "Bump app version to $major.$minor.$newPatch+$build" --no-verify
            }
        }
    }
}
