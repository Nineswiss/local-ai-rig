# gpu-banner-watcher.ps1
# Background loop: watches this PC's shared GPU (see gpu-status.ps1, a
# copy of the one in forge-ui - they're independent repos, so this is a
# deliberate small duplication rather than a cross-repo dependency) and
# keeps an Open WebUI banner in sync - visible at the top of the chat UI
# whenever Forge (forge-ui) has an active GPU context, so a slow/failed
# Ollama response doesn't come as a surprise. Deliberately only Forge, not
# "anything else with a GPU handle open" - that's noise nobody can act on.
# Direct motivation: forge-ui's git history, 2026-09-22 - GPU-accelerated
# Ollama silently pushed VRAM to 98% during a real Forge generation. The
# same contention risk runs the other way too; this is that same warning,
# from Ollama's side.
#
# Needs an Open WebUI API key (log into the web UI, Settings > Account >
# API Keys, generate one) saved to .openwebui-api-key next to this script
# (gitignored - it's a credential, never commit it). Without it, this
# logs a warning and keeps retrying every 30s in case the file appears
# later, rather than failing start-pc.ps1 outright - the rest of
# local-ai-rig works fine without this running at all.
#
# Started by start-pc.ps1, stopped by stop-pc.ps1 - not meant to be run
# directly, but safe to (Ctrl+C to stop).
#
# Usage: .\gpu-banner-watcher.ps1

$ErrorActionPreference = 'Stop'
$ScriptDir = $PSScriptRoot
$KeyFile = Join-Path $ScriptDir '.openwebui-api-key'
$GpuStatusScript = Join-Path $ScriptDir 'gpu-status.ps1'
$WebUIUrl = 'http://127.0.0.1:8080'
$BannerId = 'gpu-status'
$PollSeconds = 10

function Get-ApiKey {
    if (Test-Path $KeyFile) {
        $key = (Get-Content $KeyFile -Raw).Trim()
        if ($key) { return $key }
    }
    return $null
}

function Set-Banner {
    param([string]$ApiKey, [bool]$Busy, [string]$Message)

    $headers = @{ Authorization = "Bearer $ApiKey" }
    $current = Invoke-RestMethod -Uri "$WebUIUrl/api/v1/configs/banners" -Headers $headers -Method Get
    # Preserve any banner an admin set manually - only ever touch our own.
    $others = @($current | Where-Object { $_.id -ne $BannerId })

    $banners = $others
    if ($Busy) {
        $banners = $others + [PSCustomObject]@{
            id          = $BannerId
            type        = 'warning'
            title       = $null
            content     = $Message
            dismissible = $true
            timestamp   = [int][double]::Parse((Get-Date -UFormat %s))
        }
    }

    $body = @{ banners = $banners } | ConvertTo-Json -Depth 5
    Invoke-RestMethod -Uri "$WebUIUrl/api/v1/configs/banners" -Headers $headers -Method Post -ContentType 'application/json' -Body $body | Out-Null
}

Write-Host "== gpu-banner-watcher: starting ==" -ForegroundColor Cyan

# $null, not $false, so the very first successful check always pushes a
# state instead of assuming "not busy" and staying silent if it's wrong.
$lastBusy = $null

while ($true) {
    $apiKey = Get-ApiKey
    if (-not $apiKey) {
        Write-Host "No API key at $KeyFile yet - see README. Retrying in ${PollSeconds}s..." -ForegroundColor Yellow
        Start-Sleep -Seconds $PollSeconds
        continue
    }

    try {
        $status = & powershell -NoProfile -ExecutionPolicy Bypass -File $GpuStatusScript | ConvertFrom-Json
        # Only Forge, deliberately - not "anything else with a GPU handle
        # open" (that's noise a user can't act on, and undermines the one
        # warning that's actually useful: don't be surprised if chat is
        # slow right now).
        $busy = $status.forgeActive

        if ($busy -ne $lastBusy) {
            $message = 'Forge is generating an image or video right now - chat responses may be slower or fail'
            Set-Banner -ApiKey $apiKey -Busy $busy -Message $message
            Write-Host "GPU busy: $busy ($message)" -ForegroundColor Cyan
            $lastBusy = $busy
        }
    } catch {
        Write-Host "gpu-banner-watcher: check failed - $($_.Exception.Message)" -ForegroundColor Yellow
    }

    Start-Sleep -Seconds $PollSeconds
}
