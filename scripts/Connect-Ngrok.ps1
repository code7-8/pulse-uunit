$ErrorActionPreference = 'Stop'
$pulseConnectRoot = Split-Path -Parent $PSScriptRoot
$pulseConnectRuntime = Join-Path $pulseConnectRoot 'runtime/server'
$pulseConnectNgrok = Join-Path $pulseConnectRoot '.tools/ngrok/ngrok.exe'
$pulseConnectConfig = Join-Path $pulseConnectRuntime 'ngrok.yml'
if (-not (Test-Path -LiteralPath $pulseConnectRuntime)) { throw 'Prepare the public server first.' }
Write-Host 'Free ngrok account: https://dashboard.ngrok.com/get-started/your-authtoken'
Write-Host 'Paste ONLY the authtoken below. Input is hidden. Do not paste the full command.'
$pulseConnectSecret = Read-Host 'Authtoken' -AsSecureString
$pulseConnectPointer = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($pulseConnectSecret)
try {
    $pulseConnectToken = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($pulseConnectPointer).Trim()
    if ($pulseConnectToken -notmatch '^[A-Za-z0-9_-]{20,200}$') { throw 'Invalid token format. Paste only the token from your dashboard.' }
    $pulseConnectSettings = @{version='3'; agent=@{authtoken=$pulseConnectToken; update_check=$false; remote_management=$false; web_addr='false'}}
    [IO.File]::WriteAllText($pulseConnectConfig, ($pulseConnectSettings | ConvertTo-Json -Depth 4), [Text.UTF8Encoding]::new($false))
} finally {
    [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($pulseConnectPointer)
    $pulseConnectToken = $null
    $pulseConnectSettings = $null
}
& $pulseConnectNgrok config check --config $pulseConnectConfig
if ($LASTEXITCODE -ne 0) { throw 'ngrok configuration check failed' }
$pulseConnectSettingsFile = Join-Path $pulseConnectRuntime 'settings.json'
$pulseConnectServerSettings = Get-Content -LiteralPath $pulseConnectSettingsFile -Raw -Encoding UTF8 | ConvertFrom-Json
$pulseConnectServerSettings | Add-Member -NotePropertyName provider -NotePropertyValue 'ngrok' -Force
[IO.File]::WriteAllText($pulseConnectSettingsFile, ($pulseConnectServerSettings | ConvertTo-Json), [Text.UTF8Encoding]::new($false))
Write-Host 'Configured. The token was saved only inside runtime/server/ngrok.yml.'
Write-Host 'Return to Codex. We will switch the running tunnel and build the APK.'
