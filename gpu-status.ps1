# Reports whether Forge or Ollama (local-ai-rig) has an active compute
# context on this PC's one shared GPU. Deliberately doesn't try to flag
# "anything else" - the only useful thing to tell a user is "the other app
# you might be about to compete with is busy right now," not "Notepad has
# a GPU handle open," which is true almost constantly and isn't actionable.
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

$forgeActive = $false
$ollamaActive = $false

$raw = & nvidia-smi --query-compute-apps=pid,process_name --format=csv,noheader

foreach ($line in $raw) {
    if (-not $line) { continue }
    $parts = $line -split ',\s*', 2
    if ($parts.Count -lt 2) { continue }
    $procId = $parts[0].Trim()

    $proc = Get-CimInstance Win32_Process -Filter "ProcessId=$procId" -ErrorAction SilentlyContinue
    $cmdLine = if ($proc) { $proc.CommandLine } else { '' }

    if ($cmdLine -match 'webui_forge_neo') {
        $forgeActive = $true
    } elseif ($cmdLine -match 'ollama') {
        $ollamaActive = $true
    }
}

[PSCustomObject]@{
    utilizationPct = $utilizationPct
    usedMB         = $usedMB
    totalMB        = $totalMB
    forgeActive    = $forgeActive
    ollamaActive   = $ollamaActive
} | ConvertTo-Json -Compress
