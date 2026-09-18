# setup-pc.ps1
# Run this on the Windows machine that has the GPU. Sets up Ollama (for
# Aider) and Open WebUI (browser-based chat) as LAN-reachable services that
# survive reboots. Safe to re-run any time - every step is idempotent.
#
# Usage (PowerShell, does not need to be Administrator):
#   .\setup-pc.ps1
#   .\setup-pc.ps1 -Model qwen2.5:14b -BigModel devstral:24b -VisionModel qwen2.5vl:7b
#   .\setup-pc.ps1 -SkipWebUI          # Ollama/Aider only, no browser chat UI
#
# What it does:
#   1. Installs Ollama via winget (skips if already installed)
#   2. Sets OLLAMA_HOST and OLLAMA_CONTEXT_LENGTH as persistent user env
#      vars, so Ollama binds to your LAN (0.0.0.0:11434) with a real context
#      window instead of localhost-only + a tiny auto-sized default
#   3. Opens a Windows Firewall rule for port 11434
#   4. Pulls a fast model, a bigger one for complex requests, and a
#      vision-capable one for images (see README's "Choosing a model")
#   5. Unless -SkipWebUI: installs Open WebUI (its own Python 3.12 venv,
#      since it needs <3.13), opens the firewall for port 8080, walks you
#      through first-run admin signup, then applies known-good per-model
#      settings (fixes a real "does not support tools" error the vision
#      model hits under Open WebUI's default config) via seed-model-config.py
#   6. Prints the URLs your other machines should use to connect

param(
    [string]$Model = "qwen2.5:14b",
    [string]$BigModel = "devstral:24b",
    [string]$VisionModel = "qwen2.5vl:7b",
    [switch]$SkipWebUI
)

$ErrorActionPreference = "Stop"
$ScriptDir = $PSScriptRoot

function Wait-ForHttp {
    param([string]$Url, [int]$TimeoutSeconds = 60)
    $elapsed = 0
    while ($elapsed -lt $TimeoutSeconds) {
        try {
            Invoke-WebRequest -Uri $Url -UseBasicParsing -TimeoutSec 3 | Out-Null
            return $true
        } catch {
            Start-Sleep -Seconds 2
            $elapsed += 2
        }
    }
    return $false
}

function Start-DetachedProcess {
    # Start-Process launches a child inside the CALLING session's Job Object.
    # That's invisible when you run this script at a real console - but over
    # SSH (which the workmate/README doesn't rule out, and which we use for
    # remote setup), Windows OpenSSH tears down that job the moment the SSH
    # session closes, silently killing every "detached" child in it -
    # -WindowStyle Hidden only hides the window, it doesn't change job
    # membership. Confirmed by testing: Ollama and Open WebUI both died the
    # instant the launching SSH connection ended. Creating the process via
    # WMI instead makes it a child of the WMI provider host, not our job, so
    # it survives the session that started it closing.
    param([string]$FilePath, [string]$ArgumentList = "")
    $cmdLine = "`"$FilePath`" $ArgumentList".TrimEnd()
    $result = Invoke-CimMethod -ClassName Win32_Process -MethodName Create -Arguments @{ CommandLine = $cmdLine }
    if ($result.ReturnValue -ne 0) {
        throw "Failed to start '$FilePath' (WMI Win32_Process.Create returned $($result.ReturnValue))"
    }
    return $result.ProcessId
}

Write-Host "== local-ai-rig: PC setup ==" -ForegroundColor Cyan

# --- 1. Install Ollama ---
if (Get-Command ollama -ErrorAction SilentlyContinue) {
    Write-Host "Ollama already installed, skipping." -ForegroundColor Yellow
} else {
    Write-Host "Installing Ollama..."
    winget install --id Ollama.Ollama --source winget --accept-source-agreements --accept-package-agreements --silent
}

# --- 2. Persistent LAN binding + real context window ---
# The default context window is auto-sized from free VRAM and ends up far
# too small (often 4096 tokens) for anything beyond trivial single-file
# edits - large multi-file responses get silently cut off mid-generation.
Write-Host "Setting OLLAMA_HOST=0.0.0.0:11434 and OLLAMA_CONTEXT_LENGTH=16384 (persistent, user-level)..."
[Environment]::SetEnvironmentVariable("OLLAMA_HOST", "0.0.0.0:11434", "User")
[Environment]::SetEnvironmentVariable("OLLAMA_CONTEXT_LENGTH", "16384", "User")
$env:OLLAMA_HOST = "0.0.0.0:11434"
$env:OLLAMA_CONTEXT_LENGTH = "16384"

# --- 3. Firewall rule ---
$ruleName = "Ollama LAN (local-ai-rig)"
if (Get-NetFirewallRule -DisplayName $ruleName -ErrorAction SilentlyContinue) {
    Write-Host "Firewall rule already exists, skipping." -ForegroundColor Yellow
} else {
    Write-Host "Opening firewall for port 11434..."
    New-NetFirewallRule -DisplayName $ruleName -Direction Inbound -Protocol TCP -LocalPort 11434 -Action Allow | Out-Null
}

# --- 4. Restart Ollama so it picks up the new env var, then pull models ---
Write-Host "Restarting Ollama so it picks up the LAN binding..."
Get-Process ollama -ErrorAction SilentlyContinue | Stop-Process -Force
Start-Sleep -Seconds 2
$ollamaPath = (Get-Command ollama).Source
Start-DetachedProcess -FilePath $ollamaPath -ArgumentList "serve" | Out-Null

if (-not (Wait-ForHttp "http://127.0.0.1:11434/api/version" 30)) {
    Write-Host "WARNING: Ollama didn't respond within 30s. Continuing anyway -" -ForegroundColor Yellow
    Write-Host "the model pulls below will fail if it's genuinely not up." -ForegroundColor Yellow
}

Write-Host "Pulling models: $Model (fast), $BigModel (complex requests), $VisionModel (images)..."
Write-Host "This can take a while on first run - together they're roughly 26GB."
ollama pull $Model
ollama pull $BigModel
ollama pull $VisionModel

# --- 5. Open WebUI (browser chat UI) ---
if (-not $SkipWebUI) {
    Write-Host ""
    Write-Host "== Setting up Open WebUI ==" -ForegroundColor Cyan

    # Open WebUI needs Python <3.13; the system default is often newer.
    $py312 = $null
    try {
        $pyList = & py -0p 2>&1
        $py312Line = $pyList | Where-Object { $_ -match "3\.12" } | Select-Object -First 1
        if ($py312Line) {
            $py312 = ($py312Line -split '\s+')[-1]
        }
    } catch {}

    if (-not $py312) {
        Write-Host "Installing Python 3.12 (Open WebUI needs <3.13)..."
        winget install --id Python.Python.3.12 --source winget --accept-source-agreements --accept-package-agreements --silent
        $py312 = "py -3.12"
    }

    $venvDir = Join-Path $ScriptDir ".openwebui-venv"
    $webuiExe = Join-Path $venvDir "Scripts\open-webui.exe"

    if (-not (Test-Path $webuiExe)) {
        Write-Host "Creating a Python 3.12 venv and installing Open WebUI (this takes a few minutes)..."
        if ($py312 -eq "py -3.12") {
            py -3.12 -m venv $venvDir
        } else {
            & $py312 -m venv $venvDir
        }
        & "$venvDir\Scripts\pip.exe" install open-webui
    } else {
        Write-Host "Open WebUI already installed, skipping." -ForegroundColor Yellow
    }

    # Firewall rule
    $webuiRuleName = "Open WebUI LAN (local-ai-rig)"
    if (-not (Get-NetFirewallRule -DisplayName $webuiRuleName -ErrorAction SilentlyContinue)) {
        Write-Host "Opening firewall for port 8080..."
        New-NetFirewallRule -DisplayName $webuiRuleName -Direction Inbound -Protocol TCP -LocalPort 8080 -Action Allow | Out-Null
    }

    # The actual webui.db location, relative to the venv's site-packages
    $dbPath = Get-ChildItem -Path $venvDir -Recurse -Filter "webui.db" -ErrorAction SilentlyContinue | Select-Object -First 1 -ExpandProperty FullName
    $seedScript = Join-Path $ScriptDir "seed-model-config.py"
    $adminCheckScript = Join-Path $ScriptDir "check-admin-exists.py"

    [Environment]::SetEnvironmentVariable("OLLAMA_BASE_URL", "http://127.0.0.1:11434", "User")
    $env:OLLAMA_BASE_URL = "http://127.0.0.1:11434"

    Get-Process open-webui -ErrorAction SilentlyContinue | Stop-Process -Force
    Start-Sleep -Seconds 1
    Start-DetachedProcess -FilePath $webuiExe -ArgumentList "serve --host 0.0.0.0 --port 8080" | Out-Null

    Write-Host "Waiting for Open WebUI to start (can take ~1-2 min on first run, it downloads a small embedding model)..."
    if (-not (Wait-ForHttp "http://127.0.0.1:8080/" 180)) {
        Write-Host "WARNING: Open WebUI didn't respond within 3 minutes. Check it manually" -ForegroundColor Yellow
        Write-Host "at http://localhost:8080 before continuing." -ForegroundColor Yellow
    }

    $dbPath = Get-ChildItem -Path $venvDir -Recurse -Filter "webui.db" -ErrorAction SilentlyContinue | Select-Object -First 1 -ExpandProperty FullName
    $hasAdmin = $false
    if ($dbPath) {
        $checkResult = & "$venvDir\Scripts\python.exe" $adminCheckScript $dbPath
        $hasAdmin = ($checkResult -match "YES")
    }

    if (-not $hasAdmin) {
        Write-Host ""
        Write-Host ">>> Open http://localhost:8080 now and create your admin account. <<<" -ForegroundColor Cyan
        Write-Host "(Name/email/password are yours to choose - this is a fully local account," -ForegroundColor Cyan
        Write-Host "nothing leaves this machine.)" -ForegroundColor Cyan
        Read-Host "Press Enter here once you've created the account"
    } else {
        Write-Host "Admin account already exists, skipping signup step." -ForegroundColor Yellow
    }

    Write-Host "Applying known-good per-model settings..."
    Get-Process open-webui -ErrorAction SilentlyContinue | Stop-Process -Force
    Start-Sleep -Seconds 1

    $dbPath = Get-ChildItem -Path $venvDir -Recurse -Filter "webui.db" -ErrorAction SilentlyContinue | Select-Object -First 1 -ExpandProperty FullName
    & "$venvDir\Scripts\python.exe" $seedScript $dbPath

    Write-Host "Restarting Open WebUI..."
    Start-DetachedProcess -FilePath $webuiExe -ArgumentList "serve --host 0.0.0.0 --port 8080" | Out-Null
    Wait-ForHttp "http://127.0.0.1:8080/" 60 | Out-Null
}

# --- 6. Done ---
$ip = (Get-NetIPAddress -AddressFamily IPv4 | Where-Object { $_.InterfaceAlias -notmatch 'Loopback' -and $_.IPAddress -notmatch '^169\.254\.' } | Select-Object -First 1).IPAddress
$hostname = $env:COMPUTERNAME.ToLower()

Write-Host ""
Write-Host "== Done ==" -ForegroundColor Green
Write-Host "Ollama (for Aider):  http://${hostname}.local:11434" -ForegroundColor Cyan
if (-not $SkipWebUI) {
    Write-Host "Open WebUI (browser): http://${hostname}.local:8080" -ForegroundColor Cyan
    Write-Host "  -> reachable from ANY device on your LAN, zero setup needed there."
}
Write-Host "  (current IP, works today but can change: ${ip})"
Write-Host ""
Write-Host "IMPORTANT: use the .local hostname above, not the raw IP, anywhere you"
Write-Host "point at this machine. The IP is DHCP-assigned and WILL change eventually"
Write-Host "(router reboot, lease expiry) - anything hardcoded to it breaks silently"
Write-Host "when that happens. The .local hostname (mDNS, already built into Windows)"
Write-Host "keeps resolving correctly no matter what IP this machine gets. Verify it"
Write-Host "works from your other machine with: ping ${hostname}.local"
Write-Host ""
Write-Host "Note: OLLAMA_HOST/Open WebUI env vars are set persistently, but if either"
Write-Host "process isn't running after a reboot, just re-run this script - every"
Write-Host "step is safe to repeat."
Write-Host ""
Write-Host "For real file editing (not just chat), run setup-client.sh on the machine"
Write-Host "with your project files, using the .local hostname above."
