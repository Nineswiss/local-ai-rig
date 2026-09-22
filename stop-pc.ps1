# stop-pc.ps1
# Stops the Ollama and/or Open WebUI processes started by setup-pc.ps1.
# Frees GPU VRAM and the LAN ports (11434, 8080). Safe to run any time,
# whether or not either is actually running. Re-run setup-pc.ps1 to start
# them again.
#
# Usage:
#   .\stop-pc.ps1              # stop both, show status before/after
#   .\stop-pc.ps1 -OllamaOnly  # leave Open WebUI running
#   .\stop-pc.ps1 -WebUIOnly   # leave Ollama running (Aider still works)

param(
    [switch]$OllamaOnly,
    [switch]$WebUIOnly
)

function Get-ServiceStatus {
    param([string]$Name)
    $procs = Get-Process -Name $Name -ErrorAction SilentlyContinue
    if ($procs) {
        return "RUNNING (PID $($procs.Id -join ', '))"
    }
    return "not running"
}

Write-Host "== Before ==" -ForegroundColor Cyan
Write-Host "Ollama:      $(Get-ServiceStatus 'ollama')"
Write-Host "Open WebUI:  $(Get-ServiceStatus 'open-webui')"
Write-Host ""

if (-not $WebUIOnly) {
    $procs = Get-Process -Name "ollama" -ErrorAction SilentlyContinue
    if ($procs) {
        $procs | Stop-Process -Force
        Write-Host "Stopped Ollama." -ForegroundColor Green
    }
}
if (-not $OllamaOnly) {
    $procs = Get-Process -Name "open-webui" -ErrorAction SilentlyContinue
    if ($procs) {
        $procs | Stop-Process -Force
        Write-Host "Stopped Open WebUI." -ForegroundColor Green
    }

    $watcherPidFile = Join-Path $PSScriptRoot ".gpu-banner-watcher.pid"
    if (Test-Path $watcherPidFile) {
        $watcherPid = Get-Content $watcherPidFile -ErrorAction SilentlyContinue
        Remove-Item $watcherPidFile -ErrorAction SilentlyContinue
        if ($watcherPid -and (Get-Process -Id $watcherPid -ErrorAction SilentlyContinue)) {
            Stop-Process -Id $watcherPid -Force
            Write-Host "Stopped GPU-banner watcher." -ForegroundColor Green
        }
    }
}

Start-Sleep -Seconds 1
Write-Host ""
Write-Host "== After ==" -ForegroundColor Cyan
Write-Host "Ollama:      $(Get-ServiceStatus 'ollama')"
Write-Host "Open WebUI:  $(Get-ServiceStatus 'open-webui')"
Write-Host ""
Write-Host "Re-run setup-pc.ps1 any time to start them again." -ForegroundColor Yellow
