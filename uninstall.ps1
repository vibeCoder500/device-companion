<#
.SYNOPSIS
    Device Companion stop and uninstall (Windows)
.DESCRIPTION
    Stops the background caricature overlay process, removes the startup registry entry,
    and deletes all downloaded caricature assets from $env:LOCALAPPDATA\CorpFunZoomies.

    One-line uninstall:
      irm https://raw.githubusercontent.com/vibeCoder500/device-companion/main/uninstall.ps1 | iex
#>
param(
    [switch]$StopOnly,
    [switch]$ScheduledCleanup,
    [Nullable[DateTime]]$CleanupAtUtc
)
$ErrorActionPreference = 'Stop'
if ($env:OS -ne 'Windows_NT' -or [string]::IsNullOrWhiteSpace($env:LOCALAPPDATA)) {
    throw 'Device Companion requires Windows and a per-user LOCALAPPDATA directory.'
}
$InstallDir = Join-Path $env:LOCALAPPDATA 'CorpFunZoomies'
if ($ScheduledCleanup) {
    if ([string]::IsNullOrWhiteSpace($PSCommandPath)) {
        throw 'Scheduled cleanup must run from the installed uninstall script.'
    }
    $InstallDir = [IO.Path]::GetDirectoryName([IO.Path]::GetFullPath($PSCommandPath))
    if ([IO.Path]::GetFileName($PSCommandPath) -ne 'uninstall.ps1' -or [IO.Path]::GetFileName($InstallDir) -ne 'CorpFunZoomies') {
        throw 'Refusing scheduled cleanup outside its own companion installation.'
    }
}
$PidFile    = Join-Path $InstallDir 'zoomies.pid'
$WorkerFile = Join-Path $InstallDir 'run-zoomies.ps1'
$RegRunPath = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run'
$RegRunName = 'CorpFunZoomies'
$sha = [Security.Cryptography.SHA256]::Create()
try {
    $pathBytes = [Text.Encoding]::UTF8.GetBytes([IO.Path]::GetFullPath($InstallDir).ToLowerInvariant())
    $taskId = ([BitConverter]::ToString($sha.ComputeHash($pathBytes))).Replace('-', '').Substring(0, 16)
} finally {
    $sha.Dispose()
}
$CleanupTaskName = "DeviceCompanionCleanup-$taskId"

if ($ScheduledCleanup) {
    if ($null -eq $CleanupAtUtc) {
        throw 'Scheduled cleanup requires its original uninstall deadline.'
    }
    if ([DateTime]::UtcNow -lt $CleanupAtUtc.ToUniversalTime()) {
        return
    }
}

Write-Host "[*] Stopping Device Companion..." -ForegroundColor Yellow
$workerPattern = [regex]::Escape($WorkerFile)
Get-CimInstance Win32_Process -Filter "Name = 'powershell.exe' OR Name = 'pwsh.exe'" |
    Where-Object { $_.ProcessId -ne $PID -and $_.CommandLine -match $workerPattern } |
    ForEach-Object {
        $process = Get-Process -Id $_.ProcessId -ErrorAction SilentlyContinue
        if ($process -and -not $process.HasExited) {
            try {
                Stop-Process -Id $process.Id -Force -ErrorAction Stop
            } catch {
                if ($_.CategoryInfo.Category -ne [Management.Automation.ErrorCategory]::ObjectNotFound) { throw }
            }
            if (-not $process.WaitForExit(5000)) { throw 'The companion worker did not stop.' }
        }
    }
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
if (-not $StopOnly) {
    $tasks = Get-ScheduledTask -TaskPath '\' -ErrorAction Stop |
        Where-Object { $_.TaskName -eq $CleanupTaskName }
    foreach ($task in $tasks) {
        if ($task.Actions.Count -ne 1 -or $task.Actions[0].Arguments -notmatch [regex]::Escape((Join-Path $InstallDir 'uninstall.ps1'))) {
            throw 'Refusing to remove a cleanup task with an unexpected action.'
        }
        Unregister-ScheduledTask -TaskName $CleanupTaskName -TaskPath '\' -Confirm:$false -ErrorAction Stop
    }
}
if ($StopOnly) {
    Write-Host '[OK] Device Companion stopped. Its automatic cleanup job is still scheduled.' -ForegroundColor Green
} else {
    Write-Host '[OK] Device Companion has been completely uninstalled.' -ForegroundColor Green
}
