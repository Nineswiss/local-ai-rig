#!/usr/bin/env bash
# check-connection.sh
# Quick health check for the PC running Ollama/Open WebUI. Run this whenever
# something seems broken before digging further - it turns a cryptic
# "connection refused" deep in Aider's stack into a clear, specific answer.
#
# Usage:
#   ./check-connection.sh [pc-host]
#   ./check-connection.sh                # uses $OLLAMA_API_BASE's host if set
#   ./check-connection.sh adampc.local

set -uo pipefail

if [ -n "${1:-}" ]; then
  PC_HOST="$1"
elif [ -n "${OLLAMA_API_BASE:-}" ]; then
  # strip protocol and port from something like http://adampc.local:11434
  PC_HOST="$(echo "$OLLAMA_API_BASE" | sed -E 's#^[a-z]+://##; s#:[0-9]+$##')"
else
  echo "No host given and \$OLLAMA_API_BASE is not set."
  echo "Usage: $0 [pc-host]"
  exit 1
fi

FAIL=0

echo "== Checking $PC_HOST =="

# 1. Ollama API - a single curl call proves both DNS/mDNS resolution AND
# that Ollama itself is up, with one clear, fast, non-hanging check. (An
# earlier version of this script used ping first; dropped it - redundant
# with what curl already proves, and macOS ping's timeout mechanism prints
# a spurious "Alarm clock" job-control message to the terminal on failure.)
if curl -s -m 5 "http://${PC_HOST}:11434/api/version" >/dev/null 2>&1; then
  echo "[OK]   Ollama API reachable on port 11434"
else
  echo "[FAIL] Ollama API not reachable on port 11434"
  echo "       - Is the PC powered on and awake?"
  echo "       - Same LAN/Wi-Fi network as this machine?"
  echo "       - If this is a raw IP, it may have changed - use the .local"
  echo "         hostname instead (see README's Known Issues)."
  echo "       - If the host itself is reachable (try: ping $PC_HOST) but this"
  echo "         still fails, Ollama has likely crashed - on the PC, re-run"
  echo "         setup-pc.ps1 (safe to run again) or manually: ollama serve"
  FAIL=1
fi

# 2. Open WebUI (informational only - not required for Aider)
if curl -s -m 5 -o /dev/null "http://${PC_HOST}:8080/" 2>&1; then
  echo "[OK]   Open WebUI reachable on port 8080"
else
  echo "[--]   Open WebUI not reachable on port 8080 (fine if you only use Aider)"
fi

echo ""
if [ "$FAIL" -eq 0 ]; then
  echo "All required services reachable."
  exit 0
else
  echo "Something's not reachable - see above."
  exit 1
fi
