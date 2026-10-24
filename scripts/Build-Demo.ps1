param([switch]$Arm64)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'toolchain-ascii.ps1')
$demoWorkspace = $env:PULS_WORKSPACE_ROOT
Push-Location (Join-Path $demoWorkspace 'mobile')
try {
    flutter.bat pub get --offline
    if ($LASTEXITCODE -ne 0) { throw 'Flutter dependency resolution failed.' }
    $demoArguments = @('build','apk','--release','--no-pub','--dart-define=DEMO_MODE=true')
    if ($Arm64) { $demoArguments += @('--target-platform','android-arm64') }
    flutter.bat @demoArguments
    if ($LASTEXITCODE -ne 0) { throw 'Demo APK build failed.' }
    $demoBuildOutput = Join-Path $demoWorkspace 'mobile\build\app\outputs\flutter-apk\app-release.apk'
    $demoAapt = Join-Path $env:ANDROID_HOME 'build-tools\36.0.0\aapt.exe'
    $demoPermissions = & $demoAapt dump permissions $demoBuildOutput
    if ($LASTEXITCODE -ne 0 -or $demoPermissions -match 'android.permission.INTERNET') { throw 'Offline APK must not request INTERNET.' }
    $demoMetadata = & $demoAapt dump badging $demoBuildOutput
    if ($LASTEXITCODE -ne 0 -or -not ($demoMetadata -match "name='ru.uunit.pulse.demo'")) { throw 'Offline APK has an incorrect package ID.' }
    $demoName = if ($Arm64) { 'pulse-demo-arm64.apk' } else { 'pulse-demo.apk' }
    $demoDestination = Join-Path $demoWorkspace ('artifacts\' + $demoName)
    Copy-Item -LiteralPath 'build\app\outputs\flutter-apk\app-release.apk' -Destination $demoDestination -Force
    & (Join-Path $env:ANDROID_HOME 'build-tools\36.0.0\apksigner.bat') verify $demoDestination
    if ($LASTEXITCODE -ne 0) { throw 'APK verification failed.' }
    Write-Output ('APK: ' + $demoDestination)
    Get-FileHash -LiteralPath $demoDestination -Algorithm SHA256
} finally {
    Pop-Location
}
