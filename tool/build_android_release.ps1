param(
    [string]$ProjectRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path,
    [string]$AndroidSdkRoot = "",
    [string]$JavaHome = "C:\Program Files\Android\openjdk\jdk-21.0.8",
    [switch]$SkipAab,
    [switch]$SkipApk
)

$ErrorActionPreference = "Stop"

function Get-PubspecVersionMetadata {
    param(
        [Parameter(Mandatory = $true)]
        [string]$PubspecPath
    )

    $versionLine = Select-String -Path $PubspecPath -Pattern '^version\s*:\s*([^\s]+)' | Select-Object -First 1
    if (-not $versionLine) {
        return @{ BuildNumber = $null; Name = $null }
    }

    $versionValue = $versionLine.Matches[0].Groups[1].Value
    $parts = $versionValue.Split('+', 2)
    $versionName = $parts[0]
    $buildNumber = if ($parts.Count -gt 1) { $parts[1] } else { $null }

    return @{ BuildNumber = $buildNumber; Name = $versionName }
}

function Get-ProjectBuildName {
    param(
        [Parameter(Mandatory = $true)]
        [string]$ProjectRoot
    )

    $projectName = Split-Path -Leaf $ProjectRoot
    if ([string]::IsNullOrWhiteSpace($projectName)) {
        return 'app'
    }

    $safeName = $projectName -replace '[^A-Za-z0-9._-]', '_'
    if ([string]::IsNullOrWhiteSpace($safeName)) {
        return 'app'
    }

    return $safeName
}

function Resolve-AndroidBuildRoot {
    param(
        [Parameter(Mandatory = $true)]
        [string]$ProjectRoot
    )

    $projectBuildRoot = Join-Path $ProjectRoot ".android_build"
    if (Test-Path $projectBuildRoot) {
        return $projectBuildRoot
    }

    $localAppData = [Environment]::GetEnvironmentVariable('LOCALAPPDATA')
    if (-not [string]::IsNullOrWhiteSpace($localAppData)) {
        $projectBuildName = Get-ProjectBuildName -ProjectRoot $ProjectRoot
        return Join-Path $localAppData "Temp\$projectBuildName`_android_build"
    }

    return $projectBuildRoot
}

function Resolve-ExistingPath {
    param(
        [Parameter(Mandatory = $true)]
        [string[]]$Candidates
    )

    foreach ($candidate in $Candidates) {
        if (Test-Path $candidate) {
            return $candidate
        }
    }

    return $null
}

function Resolve-AndroidSdkRoot {
    param(
        [Parameter(Mandatory = $true)]
        [string]$ProjectRoot,
        [string]$PreferredPath
    )

    if (-not [string]::IsNullOrWhiteSpace($PreferredPath) -and (Test-Path $PreferredPath)) {
        return $PreferredPath
    }

    $localPropertiesPath = Join-Path $ProjectRoot "android\local.properties"
    if (Test-Path $localPropertiesPath) {
        $sdkLine = Select-String -Path $localPropertiesPath -Pattern '^\s*sdk\.dir\s*=\s*(.+?)\s*$' | Select-Object -First 1
        if ($sdkLine) {
            $rawPath = $sdkLine.Matches[0].Groups[1].Value.Trim()
            $decodedPath = ($rawPath -replace '\\\\', '\')
            if (Test-Path $decodedPath) {
                return $decodedPath
            }
        }
    }

    $envCandidates = @(
        [Environment]::GetEnvironmentVariable('ANDROID_SDK_ROOT'),
        [Environment]::GetEnvironmentVariable('ANDROID_HOME')
    )
    foreach ($candidate in $envCandidates) {
        if (-not [string]::IsNullOrWhiteSpace($candidate) -and (Test-Path $candidate)) {
            return $candidate
        }
    }

    $localAppData = [Environment]::GetEnvironmentVariable('LOCALAPPDATA')
    if (-not [string]::IsNullOrWhiteSpace($localAppData)) {
        $commonDefault = Join-Path $localAppData 'Android\sdk'
        if (Test-Path $commonDefault) {
            return $commonDefault
        }
    }

    return $PreferredPath
}

function Resolve-JavaHome {
    param(
        [string]$PreferredPath
    )

    if (-not [string]::IsNullOrWhiteSpace($PreferredPath) -and (Test-Path $PreferredPath)) {
        return $PreferredPath
    }

    $envJavaHome = [Environment]::GetEnvironmentVariable('JAVA_HOME')
    if (-not [string]::IsNullOrWhiteSpace($envJavaHome) -and (Test-Path $envJavaHome)) {
        return $envJavaHome
    }

    $programFiles = [Environment]::GetEnvironmentVariable('ProgramFiles')
    if (-not [string]::IsNullOrWhiteSpace($programFiles)) {
        $candidates = @(
            (Join-Path $programFiles 'Android\Android Studio\jbr'),
            (Join-Path $programFiles 'Android\Android Studio\jre'),
            (Join-Path $programFiles 'Android\openjdk\jdk-21.0.8'),
            (Join-Path $programFiles 'Android\openjdk\jdk-17.0.8')
        )

        foreach ($candidate in $candidates) {
            if (Test-Path $candidate) {
                return $candidate
            }
        }

        $openJdkBase = Join-Path $programFiles 'Android\openjdk'
        if (Test-Path $openJdkBase) {
            $jdkDirectory = Get-ChildItem -Path $openJdkBase -Directory -ErrorAction SilentlyContinue |
                Sort-Object Name -Descending |
                Select-Object -First 1
            if ($jdkDirectory -and (Test-Path $jdkDirectory.FullName)) {
                return $jdkDirectory.FullName
            }
        }
    }

    return $PreferredPath
}

function Copy-ArtifactWithAliases {
    param(
        [Parameter(Mandatory = $true)]
        [string]$SourcePath,
        [Parameter(Mandatory = $true)]
        [string]$TargetDirectory,
        [Parameter(Mandatory = $true)]
        [string]$CanonicalName,
        [string]$VersionedName
    )

    New-Item -ItemType Directory -Path $TargetDirectory -Force | Out-Null

    $canonicalPath = Join-Path $TargetDirectory $CanonicalName

    Copy-Item -Path $SourcePath -Destination $canonicalPath -Force

    $versionedItem = $null
    if (-not [string]::IsNullOrWhiteSpace($VersionedName)) {
        $versionedPath = Join-Path $TargetDirectory $VersionedName
        Copy-Item -Path $SourcePath -Destination $versionedPath -Force
        $versionedItem = (Get-Item $versionedPath)
    }

    return @{
        Canonical = (Get-Item $canonicalPath)
        Versioned = $versionedItem
    }
}

function Assert-PathExists {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path,
        [Parameter(Mandatory = $true)]
        [string]$Description
    )

    if (-not (Test-Path $Path)) {
        throw "$Description not found: $Path"
    }
}

function Remove-PathRobust {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path,
        [int]$MaxAttempts = 5
    )

    if (-not (Test-Path $Path)) {
        return
    }

    for ($attempt = 1; $attempt -le $MaxAttempts; $attempt++) {
        if (Test-Path $Path) {
            attrib -R "$Path\*" /S /D 2>$null
        }

        try {
            Remove-Item -Recurse -Force $Path -ErrorAction Stop
        }
        catch {
            cmd /c "rmdir /s /q \"$Path\"" | Out-Null
        }

        if (-not (Test-Path $Path)) {
            return
        }

        Start-Sleep -Milliseconds (250 * $attempt)
    }

    Write-Warning "Failed to fully remove path after retries: $Path"
}

function Invoke-PrebuildCleanup {
    param(
        [Parameter(Mandatory = $true)]
        [string]$ProjectRoot,
        [Parameter(Mandatory = $true)]
        [string]$AndroidBuildRoot
    )

    $cleanupPaths = @(
        (Join-Path $ProjectRoot "build\app\intermediates"),
        (Join-Path $AndroidBuildRoot "app\intermediates"),
        (Join-Path $ProjectRoot "build\app\outputs\apk\release"),
        (Join-Path $AndroidBuildRoot "app\outputs\apk\release")
    )

    foreach ($path in $cleanupPaths) {
        Remove-PathRobust -Path $path
    }
}

function Invoke-ApkOutputCleanup {
    param(
        [Parameter(Mandatory = $true)]
        [string]$ProjectRoot,
        [Parameter(Mandatory = $true)]
        [string]$AndroidBuildRoot
    )

    $cleanupPaths = @(
        (Join-Path $ProjectRoot "build\app\outputs\apk\release"),
        (Join-Path $ProjectRoot "build\app\outputs\flutter-apk"),
        (Join-Path $AndroidBuildRoot "app\outputs\apk\release"),
        (Join-Path $AndroidBuildRoot "app\outputs\flutter-apk")
    )

    $localAppData = [Environment]::GetEnvironmentVariable('LOCALAPPDATA')
    if (-not [string]::IsNullOrWhiteSpace($localAppData)) {
        $projectBuildName = Get-ProjectBuildName -ProjectRoot $ProjectRoot
        $tempAndroidBuildRoot = Join-Path $localAppData "Temp\$projectBuildName`_android_build"
        $cleanupPaths += @(
            (Join-Path $tempAndroidBuildRoot "app\outputs\apk\release"),
            (Join-Path $tempAndroidBuildRoot "app\outputs\flutter-apk")
        )
    }

    foreach ($path in $cleanupPaths) {
        Remove-PathRobust -Path $path -MaxAttempts 8
    }
}

Write-Host "Project root: $ProjectRoot"

$AndroidSdkRoot = Resolve-AndroidSdkRoot -ProjectRoot $ProjectRoot -PreferredPath $AndroidSdkRoot
$JavaHome = Resolve-JavaHome -PreferredPath $JavaHome

Write-Host "Android SDK: $AndroidSdkRoot"
Write-Host "JAVA_HOME: $JavaHome"

Assert-PathExists -Path $ProjectRoot -Description "Project root"
Assert-PathExists -Path $AndroidSdkRoot -Description "Android SDK root"
Assert-PathExists -Path $JavaHome -Description "Java home"

$flutter = Get-Command flutter -ErrorAction SilentlyContinue
if (-not $flutter) {
    throw "Flutter CLI not found in PATH."
}

$env:ANDROID_HOME = $AndroidSdkRoot
$env:ANDROID_SDK_ROOT = $AndroidSdkRoot
$env:JAVA_HOME = $JavaHome
$env:Path = "$JavaHome\bin;$AndroidSdkRoot\cmdline-tools\latest\bin;$AndroidSdkRoot\platform-tools;" + $env:Path

Set-Location $ProjectRoot

$pubspecPath = Join-Path $ProjectRoot "pubspec.yaml"
Assert-PathExists -Path $pubspecPath -Description "pubspec.yaml"
$versionInfo = Get-PubspecVersionMetadata -PubspecPath $pubspecPath
$buildNumber = $versionInfo.BuildNumber
$versionName = $versionInfo.Name
if ([string]::IsNullOrWhiteSpace($buildNumber)) {
    $buildNumber = "unknown"
}
if ([string]::IsNullOrWhiteSpace($versionName)) {
    $versionName = "unknown"
}

$androidBuildRoot = Resolve-AndroidBuildRoot -ProjectRoot $ProjectRoot
Write-Host "Resolved Android build root: $androidBuildRoot"

Write-Host "Running Android prebuild cleanup..."
Invoke-PrebuildCleanup -ProjectRoot $ProjectRoot -AndroidBuildRoot $androidBuildRoot

Write-Host "Running flutter pub get..."
flutter pub get
if ($LASTEXITCODE -ne 0) {
    throw "flutter pub get failed with exit code $LASTEXITCODE"
}

if (-not $SkipAab) {
    Write-Host "Building release AAB..."
    flutter build appbundle --release
    $aabBuildExitCode = $LASTEXITCODE
    if ($aabBuildExitCode -ne 0) {
        $aabFromRedirectedBuild = Resolve-ExistingPath -Candidates @(
            (Join-Path $androidBuildRoot "app\outputs\bundle\release\app-release.aab"),
            (Join-Path $ProjectRoot "build\app\outputs\bundle\release\app-release.aab")
        )
        if ($aabFromRedirectedBuild) {
            Write-Warning "flutter build appbundle returned exit code $aabBuildExitCode, but a release AAB exists at: $aabFromRedirectedBuild"
        }
        else {
            throw "flutter build appbundle --release failed with exit code $aabBuildExitCode"
        }
    }
}

if (-not $SkipApk) {
    Write-Host "Preparing APK output folders..."
    Invoke-ApkOutputCleanup -ProjectRoot $ProjectRoot -AndroidBuildRoot $androidBuildRoot

    Write-Host "Building release APK..."
    flutter build apk --release
    $apkBuildExitCode = $LASTEXITCODE
    if ($apkBuildExitCode -ne 0) {
        $apkFromRedirectedBuild = Resolve-ExistingPath -Candidates @(
            (Join-Path $androidBuildRoot "app\outputs\flutter-apk\app-release.apk"),
            (Join-Path $androidBuildRoot "app\outputs\apk\release\app-release.apk"),
            (Join-Path $ProjectRoot "build\app\outputs\flutter-apk\app-release.apk")
        )
        if ($apkFromRedirectedBuild) {
            Write-Warning "flutter build apk returned exit code $apkBuildExitCode, but a release APK exists at: $apkFromRedirectedBuild"
        }
        else {
            throw "flutter build apk --release failed with exit code $apkBuildExitCode"
        }
    }
}

if (-not $SkipAab) {
    $aabSource = Resolve-ExistingPath -Candidates @(
        (Join-Path $androidBuildRoot "app\outputs\bundle\release\app-release.aab"),
        (Join-Path $ProjectRoot "build\app\outputs\bundle\release\app-release.aab")
    )
    if (-not $aabSource) {
        throw "Release AAB was not found in expected output folders."
    }

    $aabCopyResult = Copy-ArtifactWithAliases -SourcePath $aabSource -TargetDirectory (Join-Path $ProjectRoot "build\app\outputs\bundle\release") -CanonicalName "app-release.aab"

    Write-Host "AAB source: $aabSource"
    Write-Host "AAB canonical copy: $($aabCopyResult.Canonical.FullName) ($([math]::Round($aabCopyResult.Canonical.Length / 1MB, 2)) MB)"
}

if (-not $SkipApk) {
    $apkSource = Resolve-ExistingPath -Candidates @(
        (Join-Path $androidBuildRoot "app\outputs\flutter-apk\app-release.apk"),
        (Join-Path $androidBuildRoot "app\outputs\apk\release\app-release.apk"),
        (Join-Path $ProjectRoot "build\app\outputs\flutter-apk\app-release.apk")
    )
    if (-not $apkSource) {
        throw "Release APK was not found in expected output folders."
    }

    $apkCopyResult = Copy-ArtifactWithAliases -SourcePath $apkSource -TargetDirectory (Join-Path $ProjectRoot "build\app\outputs\flutter-apk") -CanonicalName "app-release.apk"

    Write-Host "APK source: $apkSource"
    Write-Host "APK canonical copy: $($apkCopyResult.Canonical.FullName) ($([math]::Round($apkCopyResult.Canonical.Length / 1MB, 2)) MB)"
}

Write-Host "Android release build finished successfully."
