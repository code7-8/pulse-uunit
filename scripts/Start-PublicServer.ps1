$ErrorActionPreference = 'Stop'
$pulsePublicWorkspace = Split-Path -Parent $PSScriptRoot
$pulsePublicPython = Join-Path $pulsePublicWorkspace 'backend\.venv\Scripts\python.exe'
$pulsePublicScript = Join-Path $PSScriptRoot 'public_server.py'
$pulsePublicRuntime = Join-Path $pulsePublicWorkspace 'runtime\server'
New-Item -ItemType Directory -Force -Path $pulsePublicRuntime | Out-Null
$env:PYTHONUTF8 = '1'
$pulsePublicStatus = Join-Path $pulsePublicRuntime 'status.json'
if (Test-Path -LiteralPath $pulsePublicStatus) {
    $pulseExistingState = Get-Content -LiteralPath $pulsePublicStatus -Raw -Encoding UTF8 | ConvertFrom-Json
    if ($pulseExistingState.running -and $pulseExistingState.heartbeat -and
        ([DateTimeOffset]::Now - [DateTimeOffset]$pulseExistingState.heartbeat).TotalSeconds -lt 10) {
        Write-Host 'Public server is already running.'
        Write-Host $pulseExistingState.url
        return
    }
}
& $pulsePublicPython -X utf8 $pulsePublicScript prepare
if ($LASTEXITCODE -ne 0) { throw 'Public server preparation failed' }
$pulsePublicArguments = '-X utf8 "' + $pulsePublicScript + '" run'
$pulsePublicLaunchTime = [DateTimeOffset]::Now.AddSeconds(-1)
$pulseDetachedScript = Join-Path $PSScriptRoot 'Detached-PublicServer.py'
$pulseStartupInfo = New-CimInstance -ClassName Win32_ProcessStartup -ClientOnly -Property @{ ShowWindow = [uint16]0 }
$pulseCreateResult = Invoke-CimMethod -ClassName Win32_Process -MethodName Create -Arguments @{
    CommandLine = ('"' + $pulsePublicPython + '" -X utf8 "' + $pulseDetachedScript + '"')
    CurrentDirectory = $pulsePublicWorkspace
    ProcessStartupInformation = $pulseStartupInfo
}
if ($pulseCreateResult.ReturnValue -ne 0) { throw ('Windows could not start the server: ' + $pulseCreateResult.ReturnValue) }
$pulsePublicProcess = Get-Process -Id $pulseCreateResult.ProcessId
Write-Host 'Public server started in the background.'
Write-Host ('Status and address: ' + $pulsePublicRuntime)
$pulsePublicDeadline = [DateTime]::UtcNow.AddSeconds(25)
while ([DateTime]::UtcNow -lt $pulsePublicDeadline -and -not $pulsePublicProcess.HasExited) {
    if (Test-Path -LiteralPath $pulsePublicStatus) {
        $pulseNewState = Get-Content -LiteralPath $pulsePublicStatus -Raw -Encoding UTF8 | ConvertFrom-Json
        if ($pulseNewState.running -and $pulseNewState.url -and ([DateTimeOffset]$pulseNewState.started_at) -ge $pulsePublicLaunchTime) {
            Write-Host $pulseNewState.url
            break
        }
    }
    Start-Sleep -Milliseconds 500
}
if ($pulsePublicProcess.HasExited) { throw ('Server stopped. See ' + $pulsePublicRuntime + '/logs') }
