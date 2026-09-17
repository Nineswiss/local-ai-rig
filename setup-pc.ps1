# setup-pc.ps1
# Run this on the Windows machine that has the GPU. Sets up Ollama as a
# LAN-reachable, GPU-accelerated model server that survives reboots.
#
# Usage (PowerShell, does not need to be Administrator):
#   .\setup-pc.ps1
#   .\setup-pc.ps1 -Model qwen2.5:32b
#
# What it does:
#   1. Installs Ollama via winget (skips if already installed)
#   2. Sets OLLAMA_HOST as a persistent user env var, so Ollama binds to your
#      LAN (0.0.0.0:11434) instead of localhost-only on every future start
#   3. Opens a Windows Firewall rule for port 11434, so other machines on
#      your LAN can actually reach it
#   4. Pulls the model
#   5. Prints the URL your other machines should use to connect

param(
    [string]$Model = "qwen2.5:14b"
)

$ErrorActionPreference = "Stop"

Write-Host "== local-ai-rig: PC setup ==" -ForegroundColor Cyan

# --- 1. Install Ollama ---
if (Get-Command ollama -ErrorAction SilentlyContinue) {
    Write-Host "Ollama already installed, skipping." -ForegroundColor Yellow
} else {
    Write-Host "Installing Ollama..."
    winget install --id Ollama.Ollama --source winget --accept-source-agreements --accept-package-agreements --silent
}

# --- 2. Persistent LAN binding ---
Write-Host "Setting OLLAMA_HOST=0.0.0.0:11434 (persistent, user-level)..."
[Environment]::SetEnvironmentVariable("OLLAMA_HOST", "0.0.0.0:11434", "User")
$env:OLLAMA_HOST = "0.0.0.0:11434"

# --- 3. Firewall rule ---
$ruleName = "Ollama LAN (local-ai-rig)"
if (Get-NetFirewallRule -DisplayName $ruleName -ErrorAction SilentlyContinue) {
    Write-Host "Firewall rule already exists, skipping." -ForegroundColor Yellow
} else {
    Write-Host "Opening firewall for port 11434..."
    New-NetFirewallRule -DisplayName $ruleName -Direction Inbound -Protocol TCP -LocalPort 11434 -Action Allow | Out-Null
}

# --- 4. Restart Ollama so it picks up the new env var, then pull the model ---
Write-Host "Restarting Ollama so it picks up the LAN binding..."
Get-Process ollama -ErrorAction SilentlyContinue | Stop-Process -Force
Start-Sleep -Seconds 2
Start-Process -FilePath "ollama" -ArgumentList "serve" -WindowStyle Hidden
Start-Sleep -Seconds 3

Write-Host "Pulling model: $Model (this can take a while on first run)..."
ollama pull $Model

# --- 5. Done ---
$ip = (Get-NetIPAddress -AddressFamily IPv4 | Where-Object { $_.InterfaceAlias -notmatch 'Loopback' -and $_.IPAddress -notmatch '^169\.254\.' } | Select-Object -First 1).IPAddress

Write-Host ""
Write-Host "== Done ==" -ForegroundColor Green
Write-Host "Ollama is running and reachable on your LAN at:"
Write-Host "  http://${ip}:11434" -ForegroundColor Cyan
Write-Host ""
Write-Host "Note: OLLAMA_HOST is now set persistently, but GUI apps (like Ollama's"
Write-Host "tray icon, if it auto-starts on login) only pick up env var changes on"
Write-Host "their next launch. If Ollama doesn't come back up LAN-bound after a"
Write-Host "reboot, just re-run this script."
Write-Host ""
Write-Host "On your client machine (Mac/Linux), run setup-client.sh with this IP."
