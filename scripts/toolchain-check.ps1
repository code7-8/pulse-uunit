param([switch]$AndroidLicenses)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'toolchain.ps1')
if (-not (Test-Path (Join-Path $env:FLUTTER_ROOT 'bin/flutter.bat'))) {
    throw 'Flutter SDK is not installed in .tools/flutter yet.'
}
& flutter.bat doctor -v
& adb.exe devices -l
if ($AndroidLicenses) {
    & flutter.bat doctor --android-licenses
}
