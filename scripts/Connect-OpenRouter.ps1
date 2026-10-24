$ErrorActionPreference = 'Stop'
$pulseAiRoot = Split-Path -Parent $PSScriptRoot
$pulseAiDirectory = Join-Path $pulseAiRoot 'runtime/server'
New-Item -ItemType Directory -Force -Path $pulseAiDirectory | Out-Null
Write-Host 'Paste the OpenRouter API key. Input is hidden; the key stays on this PC.'
$pulseAiSecure = Read-Host 'OpenRouter API key' -AsSecureString
$pulseAiPointer = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($pulseAiSecure)
try {
    $pulseAiKey = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($pulseAiPointer).Trim()
    if ($pulseAiKey -notmatch '^sk-or-[A-Za-z0-9_-]{20,}$') { throw 'This does not look like an OpenRouter API key.' }
    [IO.File]::WriteAllText((Join-Path $pulseAiDirectory 'openrouter.key'), $pulseAiKey, [Text.UTF8Encoding]::new($false))
    Write-Host 'Key saved locally. Return to Codex and say it is ready.'
} finally {
    [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($pulseAiPointer)
    $pulseAiKey = $null
    $pulseAiSecure.Dispose()
}
