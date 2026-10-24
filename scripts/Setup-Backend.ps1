$ErrorActionPreference = 'Stop'
$pulseWorkspace = Split-Path -Parent $PSScriptRoot
$pulseVenv = Join-Path $pulseWorkspace 'backend\.venv'
if (-not (Test-Path -LiteralPath (Join-Path $pulseVenv 'Scripts\python.exe'))) {
    python -m venv $pulseVenv
    if ($LASTEXITCODE -ne 0) { throw 'Не удалось создать окружение Python.' }
}
& (Join-Path $pulseVenv 'Scripts\python.exe') -m pip install -r (Join-Path $pulseWorkspace 'backend\requirements.txt')
if ($LASTEXITCODE -ne 0) { throw 'Не удалось установить зависимости сервера.' }
Write-Host 'Готово. Запуск: .\scripts\Start-Server.ps1' -ForegroundColor Green

