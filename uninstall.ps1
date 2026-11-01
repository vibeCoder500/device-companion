<#
.SYNOPSIS
    Device Companion stop and uninstall (Windows)
.DESCRIPTION
    Stops the background caricature overlay process, removes the startup registry entry,
    and deletes all downloaded caricature assets from $env:LOCALAPPDATA\CorpFunZoomies.

    One-line uninstall:
      irm https://raw.githubusercontent.com/vibeCoder500/device-companion/main/uninstall.ps1 | iex
#>
param([switch]$StopOnly)
$ErrorActionPreference = 'Stop'
if ($env:OS -ne 'Windows_NT' -or [string]::IsNullOrWhiteSpace($env:LOCALAPPDATA)) {
    throw 'Device Companion requires Windows and a per-user LOCALAPPDATA directory.'
}
$InstallDir = Join-Path $env:LOCALAPPDATA 'CorpFunZoomies'
$PidFile    = Join-Path $InstallDir 'zoomies.pid'
$WorkerFile = Join-Path $InstallDir 'run-zoomies.ps1'
$RegRunPath = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run'
$RegRunName = 'CorpFunZoomies'

Write-Host "[*] Stopping Device Companion..." -ForegroundColor Yellow
$workerPattern = [regex]::Escape($WorkerFile)
Get-CimInstance Win32_Process -Filter "Name = 'powershell.exe' OR Name = 'pwsh.exe'" |
    Where-Object { $_.ProcessId -ne $PID -and $_.CommandLine -match $workerPattern } |
    ForEach-Object { Stop-Process -Id $_.ProcessId -Force }
foreach ($file in @($PidFile, (Join-Path $InstallDir 'zoomies.ready'))) {
    if (Test-Path -LiteralPath $file) {
        Remove-Item -LiteralPath $file -Force
    }
}
if ((Test-Path -LiteralPath $RegRunPath) -and (Get-Item -LiteralPath $RegRunPath).GetValueNames() -contains $RegRunName) {
    Remove-ItemProperty -LiteralPath $RegRunPath -Name $RegRunName -Force
}
if (-not $StopOnly -and (Test-Path -LiteralPath $InstallDir)) {
    if ((Get-Item -LiteralPath $InstallDir).Attributes -band [IO.FileAttributes]::ReparsePoint) {
        throw 'Refusing to delete a linked installation directory.'
    }
    Remove-Item -LiteralPath $InstallDir -Recurse -Force
}
if ($StopOnly) {
    Write-Host '[OK] Device Companion stopped. It will not restart automatically.' -ForegroundColor Green
} else {
    Write-Host '[OK] Device Companion has been completely uninstalled.' -ForegroundColor Green
}
