param(
    [int]$Port = 8000,
    [switch]$LocalOnly
)
$ErrorActionPreference = 'Stop'
$pulseWorkspace = Split-Path -Parent $PSScriptRoot
$pulsePython = Join-Path $pulseWorkspace 'backend\.venv\Scripts\python.exe'
if (-not (Test-Path -LiteralPath $pulsePython)) {
    throw 'Сначала выполните scripts\Setup-Backend.ps1'
}
$listenAddress = if ($LocalOnly) { '127.0.0.1' } else { '0.0.0.0' }
Write-Host ''
Write-Host 'Пульс — сервер' -ForegroundColor Cyan
Write-Host ('Проверка: http://127.0.0.1:' + $Port + '/api/health')
Write-Host 'Адреса ноутбука:'
[System.Net.NetworkInformation.NetworkInterface]::GetAllNetworkInterfaces() |
    Where-Object OperationalStatus -eq 'Up' |
    ForEach-Object {
        $_.GetIPProperties().UnicastAddresses |
            Where-Object { $_.Address.AddressFamily -eq 'InterNetwork' -and $_.Address.ToString() -notlike '127.*' -and $_.Address.ToString() -notlike '169.254.*' } |
            ForEach-Object { Write-Host ('  http://' + $_.Address + ':' + $Port) }
    }
Write-Host 'Телефон и ноутбук должны быть в одной сети Wi-Fi. Остановка: Ctrl+C.'
Push-Location $pulseWorkspace
try {
    & $pulsePython -m uvicorn backend.main:app --host $listenAddress --port $Port
} finally {
    Pop-Location
}

