# Optional process environment for Windows tools that cannot handle Cyrillic paths.
# Dot-source this helper, then use P:\mobile as the project directory.
# Files remain in the existing workspace. The mapping is removed with -Remove.
param(
    [ValidatePattern('^[D-Z]$')][string]$DriveLetter = 'P',
    [switch]$Remove
)
$toolchainActualWorkspace = Split-Path -Parent $PSScriptRoot
$toolchainDrive = $DriveLetter + ':'
$toolchainDriveRoot = $toolchainDrive + '\'
$toolchainMarkerName = '.tools\toolchain-workspace.txt'
$toolchainMarkerPath = Join-Path $toolchainActualWorkspace $toolchainMarkerName
if ($Remove) {
    if ($env:PULS_WORKSPACE_ROOT -ne $toolchainDriveRoot) {
        throw 'Only the mapping selected by this shell can be removed.'
    }
    $toolchainMappedMarker = Join-Path $toolchainDriveRoot $toolchainMarkerName
    if (-not (Test-Path $toolchainMappedMarker) -or (Get-Content $toolchainMappedMarker -Raw).Trim() -ne $toolchainActualWorkspace) {
        throw 'Workspace alias verification failed; nothing was changed.'
    }
    Set-Location -LiteralPath $toolchainActualWorkspace
    subst.exe $toolchainDrive /D
    if ($LASTEXITCODE -ne 0) { throw 'Could not remove the workspace drive alias.' }
    Remove-Item Env:PULS_WORKSPACE_ROOT
    . (Join-Path $PSScriptRoot 'toolchain.ps1')
    return
}
if (Test-Path $toolchainDriveRoot) {
    $toolchainMappedMarker = Join-Path $toolchainDriveRoot $toolchainMarkerName
    if (-not (Test-Path $toolchainMappedMarker) -or (Get-Content $toolchainMappedMarker -Raw).Trim() -ne $toolchainActualWorkspace) {
        throw "Drive $toolchainDrive is already in use. Choose another DriveLetter."
    }
} else {
    $toolchainActualWorkspace | Set-Content -Encoding utf8 $toolchainMarkerPath
    subst.exe $toolchainDrive $toolchainActualWorkspace
    if ($LASTEXITCODE -ne 0) { throw 'Could not create the workspace drive alias.' }
}
$env:PULS_WORKSPACE_ROOT = $toolchainDriveRoot
. (Join-Path $PSScriptRoot 'toolchain.ps1')
Write-Output "Workspace alias: $toolchainDriveRoot"
