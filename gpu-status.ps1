# Reports whether Forge, Ollama (local-ai-rig), or anything else has an
# active compute context on this PC's one shared GPU.
#
# Per-process VRAM isn't usable here: nvidia-smi's own used_memory field
# comes back "[N/A]" for every process on this card (confirmed live, incl.
# for Ollama's llama-server.exe while it was genuinely using 11.9/12GB - a
# known limitation on some consumer GeForce cards/drivers, not a bug in
# this script). So this reports presence in --query-compute-apps (which
# process_name resolves to the underlying interpreter, not what launched
# it - matched via each PID's actual command line instead) plus the GPU's
# aggregate utilization/memory for context, rather than a per-app MB split
# it can't actually get.
$ErrorActionPreference = 'Stop'

$gpuLine = & nvidia-smi --query-gpu=utilization.gpu,memory.used,memory.total --format=csv,noheader,nounits
$gpuParts = $gpuLine -split ',\s*'
$utilizationPct = [int]$gpuParts[0].Trim()
$usedMB = [int]$gpuParts[1].Trim()
$totalMB = [int]$gpuParts[2].Trim()

# Idle desktop/system processes that hold a GPU compute context just for
# normal compositing - always present, never meaningfully "using" the GPU
# for this purpose. Best-effort, not exhaustive: an unrecognized app here
# just means an occasional over-cautious warning, not a dangerous miss.
$harmless = @(
    'dwm.exe', 'explorer.exe', 'LogonUI.exe', 'ShellExperienceHost.exe',
    'StartMenuExperienceHost.exe', 'SearchHost.exe', 'TextInputHost.exe',
    'ShellHost.exe', 'CrossDeviceResume.exe', 'WUDFHost.exe',
    'msedgewebview2.exe', 'logioptionsplus_agent.exe',
    'Creative Cloud UI Helper.exe', 'EpicGamesLauncher.exe',
    'EpicWebHelper.exe', 'EOSOverlayRenderer-Win64-Shipping.exe',
    'WindowsTerminal.exe', 'Avid Link.exe', 'svchost.exe', 'csrss.exe',
    'winlogon.exe', 'SystemSettings.exe', 'ApplicationFrameHost.exe',
    'RuntimeBroker.exe'
)

$forgeActive = $false
$ollamaActive = $false
$otherProcesses = @()

$raw = & nvidia-smi --query-compute-apps=pid,process_name --format=csv,noheader

foreach ($line in $raw) {
    if (-not $line) { continue }
    $parts = $line -split ',\s*', 2
    if ($parts.Count -lt 2) { continue }
    $procId = $parts[0].Trim()

    $proc = Get-CimInstance Win32_Process -Filter "ProcessId=$procId" -ErrorAction SilentlyContinue
    $cmdLine = if ($proc) { $proc.CommandLine } else { '' }
    $name = if ($proc) { $proc.Name } else { $parts[1].Trim() }

    if ($cmdLine -match 'webui_forge_neo') {
        $forgeActive = $true
    } elseif ($cmdLine -match 'ollama') {
        $ollamaActive = $true
    } elseif ($harmless -notcontains $name) {
        if ($otherProcesses -notcontains $name) { $otherProcesses += $name }
    }
}

[PSCustomObject]@{
    utilizationPct = $utilizationPct
    usedMB         = $usedMB
    totalMB        = $totalMB
    forgeActive    = $forgeActive
    ollamaActive   = $ollamaActive
    otherActive    = $otherProcesses.Count -gt 0
    otherProcesses = $otherProcesses
} | ConvertTo-Json -Compress
