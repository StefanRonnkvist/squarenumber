$ErrorActionPreference = "SilentlyContinue"

$projectRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$projectName = Split-Path -Leaf $projectRoot
$safeProjectName = ($projectName -replace '[^A-Za-z0-9._-]', '_')
if ([string]::IsNullOrWhiteSpace($safeProjectName)) {
    $safeProjectName = 'app'
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
            # Try cmd fallback because it can sometimes remove paths PowerShell cannot.
            cmd /c "rmdir /s /q \"$Path\"" | Out-Null
        }

        if (-not (Test-Path $Path)) {
            return
        }

        Start-Sleep -Milliseconds (250 * $attempt)
    }

    Write-Warning "Failed to fully remove path after retries: $Path"
}

Get-Process aapt2, dart, flutter, java, javaw, gradle, kotlin -ErrorAction SilentlyContinue |
    Stop-Process -Force -ErrorAction SilentlyContinue

Remove-PathRobust "build\app\outputs\bundle\release"
Remove-PathRobust "build\app\outputs\flutter-apk"
Remove-PathRobust "build\app\outputs\apk\release"
Remove-PathRobust "build\app\intermediates"
Remove-PathRobust "windows\flutter\ephemeral\.plugin_symlinks"

Remove-PathRobust ".android_build\app\outputs\bundle\release"
Remove-PathRobust ".android_build\app\outputs\flutter-apk"
Remove-PathRobust ".android_build\app\outputs\apk\release"
Remove-PathRobust ".android_build\app\intermediates"

$androidBuildRoot = Join-Path $env:LOCALAPPDATA "Temp\$safeProjectName`_android_build"
Remove-PathRobust (Join-Path $androidBuildRoot "app\outputs\bundle\release")
Remove-PathRobust (Join-Path $androidBuildRoot "app\outputs\flutter-apk")
Remove-PathRobust (Join-Path $androidBuildRoot "app\outputs\apk\release")
Remove-PathRobust (Join-Path $androidBuildRoot "app\intermediates")