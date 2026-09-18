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
if (Get-Process -Name "open-webui" -ErrorAction SilentlyContinue) {
    Write-Host "Open WebUI already running." -ForegroundColor Yellow
} elseif (-not (Test-Path $webuiExe)) {
    Write-Host "Open WebUI isn't installed - run setup-pc.ps1 first." -ForegroundColor Red
} else {
    $env:OLLAMA_BASE_URL = "http://127.0.0.1:11434"
    Start-DetachedProcess -FilePath $webuiExe -ArgumentList "serve --host 0.0.0.0 --port 8080" | Out-Null
    Write-Host "Started Open WebUI." -ForegroundColor Green
}

Start-Sleep -Seconds 2
Write-Host ""
Write-Host "Ollama:      $(Get-ServiceStatus 'ollama')"
Write-Host "Open WebUI:  $(Get-ServiceStatus 'open-webui')"
