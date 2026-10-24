# Dot-source from PowerShell before invoking Flutter, Dart, adb, or Gradle:
# . ./scripts/toolchain.ps1
chcp.com 65001 | Out-Null
$OutputEncoding = [System.Text.UTF8Encoding]::new($false)
[Console]::OutputEncoding = [System.Text.UTF8Encoding]::new($false)
$toolchainWorkspace = if ($env:PULS_WORKSPACE_ROOT) { $env:PULS_WORKSPACE_ROOT } else { Split-Path -Parent $PSScriptRoot }
$toolchainRoot = Join-Path $toolchainWorkspace '.tools'
$env:FLUTTER_ROOT = Join-Path $toolchainRoot 'flutter'
$env:ANDROID_HOME = Join-Path $toolchainRoot 'android-sdk'
$env:ANDROID_SDK_ROOT = $env:ANDROID_HOME
$env:JAVA_HOME = Join-Path $toolchainRoot 'jdk'
$env:PUB_CACHE = Join-Path $toolchainRoot 'pub-cache'
$env:GRADLE_USER_HOME = Join-Path $toolchainRoot 'gradle-cache'
$env:ANDROID_USER_HOME = Join-Path $toolchainRoot 'android-user'
$env:ANDROID_AVD_HOME = Join-Path $toolchainRoot 'android-avd'
$env:APPDATA = Join-Path $toolchainRoot 'appdata'
$env:TEMP = Join-Path $toolchainRoot 'tmp'
$env:TMP = $env:TEMP
$env:FLUTTER_SUPPRESS_ANALYTICS = 'true'
$env:DART_SUPPRESS_ANALYTICS = 'true'
$env:CI = 'true'
$env:PATH = @(
    (Join-Path $env:FLUTTER_ROOT 'bin')
    (Join-Path $env:JAVA_HOME 'bin')
    (Join-Path $env:ANDROID_HOME 'cmdline-tools/latest/bin')
    (Join-Path $env:ANDROID_HOME 'platform-tools')
    $env:PATH
) -join ';'
New-Item -ItemType Directory -Force -Path $env:PUB_CACHE,$env:GRADLE_USER_HOME,$env:ANDROID_USER_HOME,$env:ANDROID_AVD_HOME,$env:APPDATA,$env:TEMP | Out-Null
