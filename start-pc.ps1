# start-pc.ps1
# Starts Ollama and Open WebUI if they're not already running. Does NOT
# reinstall anything, pull models, or touch the firewall - that's
# setup-pc.ps1's job, and unlike this script it needs internet (for the
# model pulls), which defeats the point of a quick "turn it back on"
# button when you're offline. Use this for the common case: PC just
# rebooted, or you ran stop-pc.ps1 earlier and want the services back.
# Safe to re-run - anything already running is left alone.
#
# Usage: .\start-pc.ps1

function Get-ServiceStatus {
    param([string]$Name)
    $procs = Get-Process -Name $Name -ErrorAction SilentlyContinue
    if ($procs) { return "RUNNING (PID $($procs.Id -join ', '))" }
    return "not running"
}

function Start-DetachedProcess {
    # See setup-pc.ps1 for why this uses WMI instead of Start-Process: a
    # Start-Process child dies the instant the session that launched it
    # closes (e.g. an SSH connection), even with -WindowStyle Hidden.
    param([string]$FilePath, [string]$ArgumentList = "")
    $cmdLine = "`"$FilePath`" $ArgumentList".TrimEnd()
    $result = Invoke-CimMethod -ClassName Win32_Process -MethodName Create -Arguments @{ CommandLine = $cmdLine }
    if ($result.ReturnValue -ne 0) {
        throw "Failed to start '$FilePath' (WMI Win32_Process.Create returned $($result.ReturnValue))"
    }
    return $result.ProcessId
}

Write-Host "== local-ai-rig: start ==" -ForegroundColor Cyan

if (Get-Process -Name "ollama" -ErrorAction SilentlyContinue) {
    Write-Host "Ollama already running." -ForegroundColor Yellow
} else {
    $ollamaCmd = Get-Command ollama -ErrorAction SilentlyContinue
    if (-not $ollamaCmd) {
        Write-Host "Ollama isn't installed - run setup-pc.ps1 first." -ForegroundColor Red
    } else {
        $env:OLLAMA_HOST = "0.0.0.0:11434"
        $env:OLLAMA_CONTEXT_LENGTH = "16384"
        Start-DetachedProcess -FilePath $ollamaCmd.Source -ArgumentList "serve" | Out-Null
        Write-Host "Started Ollama." -ForegroundColor Green
    }
}

$webuiExe = Join-Path $PSScriptRoot ".openwebui-venv\Scripts\open-webui.exe"
$webuiInstalled = Test-Path $webuiExe
if (Get-Process -Name "open-webui" -ErrorAction SilentlyContinue) {
    Write-Host "Open WebUI already running." -ForegroundColor Yellow
} elseif (-not $webuiInstalled) {
    Write-Host "Open WebUI isn't installed - run setup-pc.ps1 first." -ForegroundColor Red
} else {
    $env:OLLAMA_BASE_URL = "http://127.0.0.1:11434"
    Start-DetachedProcess -FilePath $webuiExe -ArgumentList "serve --host 0.0.0.0 --port 8080" | Out-Null
    Write-Host "Started Open WebUI." -ForegroundColor Green
}

# GPU-busy banner watcher - purely a UI nicety on top of Open WebUI, so
# only bother if Open WebUI is actually installed. Uses its own PID file
# (unlike Ollama/Open WebUI above) since it's a bare powershell.exe
# process - Get-Process -Name wouldn't reliably tell it apart from any
# other PowerShell window.
$watcherPidFile = Join-Path $PSScriptRoot ".gpu-banner-watcher.pid"
$watcherRunning = $false
if (Test-Path $watcherPidFile) {
    $watcherPid = Get-Content $watcherPidFile -ErrorAction SilentlyContinue
    $watcherRunning = $watcherPid -and (Get-Process -Id $watcherPid -ErrorAction SilentlyContinue)
}
if (-not $webuiInstalled) {
    # already explained above, don't repeat it
} elseif ($watcherRunning) {
    Write-Host "GPU-banner watcher already running." -ForegroundColor Yellow
} else {
    # Routed through cmd.exe to redirect output to a log file (proved its
    # worth debugging this very feature - Set-Banner failures would
    # otherwise be invisible, same as any other detached process here).
    # That means the PID captured below is cmd.exe's, not the actual
    # watcher - stop-pc.ps1 has to taskkill /T it for the same reason
    # start.ps1/stop.ps1 do in forge-ui: Stop-Process on just this PID
    # would kill cmd.exe and orphan the powershell.exe child underneath it.
    $watcherScript = Join-Path $PSScriptRoot "gpu-banner-watcher.ps1"
    $watcherLog = Join-Path $PSScriptRoot "gpu-banner-watcher.log"
    $cmdLine = "cmd.exe /c powershell.exe -NoProfile -ExecutionPolicy Bypass -File `"$watcherScript`" > `"$watcherLog`" 2>&1"
    $result = Invoke-CimMethod -ClassName Win32_Process -MethodName Create -Arguments @{ CommandLine = $cmdLine; CurrentDirectory = $PSScriptRoot }
    if ($result.ReturnValue -ne 0) {
        Write-Host "Failed to start GPU-banner watcher (WMI returned $($result.ReturnValue))" -ForegroundColor Red
    } else {
        Set-Content -Path $watcherPidFile -Value $result.ProcessId
        Write-Host "Started GPU-banner watcher (log: gpu-banner-watcher.log)." -ForegroundColor Green
    }
}

Start-Sleep -Seconds 2
Write-Host ""
Write-Host "Ollama:      $(Get-ServiceStatus 'ollama')"
Write-Host "Open WebUI:  $(Get-ServiceStatus 'open-webui')"

$hostname = $env:COMPUTERNAME.ToLower()
Write-Host ""
Write-Host "Browser chat:  http://${hostname}.local:8080" -ForegroundColor Cyan
Write-Host "Aider/Ollama:  http://${hostname}.local:11434" -ForegroundColor Cyan
