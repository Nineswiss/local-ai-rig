#!/usr/bin/env bash
# setup-client.sh
# Run this on the machine you'll actually work from (Mac or Linux) — the one
# with your project files. Installs Aider and points it at the GPU machine
# running Ollama (set up separately via setup-pc.ps1).
#
# Usage:
#   ./setup-client.sh <pc-host> [model] [big-model]
#   ./setup-client.sh adampc.local
#   ./setup-client.sh adampc.local qwen2.5:14b devstral:24b
#
# Prefer the PC's mDNS hostname (<hostname>.local, e.g. adampc.local - the
# Windows machine's own hostname, no setup needed) over its raw LAN IP. The
# IP is DHCP-assigned and WILL change eventually (router reboot, lease
# expiry), silently breaking everything pointed at it. The hostname keeps
# resolving to wherever the PC actually is. Test one with:
#   ping -c 1 adampc.local

set -euo pipefail

PC_HOST="${1:-}"
MODEL="${2:-qwen2.5:14b}"
BIG_MODEL="${3:-devstral:24b}"

if [ -z "$PC_HOST" ]; then
  echo "Usage: $0 <pc-host> [model] [big-model]"
  echo "  <pc-host> is the PC's mDNS hostname (preferred, e.g. adampc.local)"
  echo "  or its LAN IP (works, but breaks if the IP ever changes)"
  echo "  e.g. $0 adampc.local"
  exit 1
fi

echo "== local-ai-rig: client setup =="

OS="$(uname -s)"

# --- 1. Install Aider ---
if command -v aider >/dev/null 2>&1; then
  echo "Aider already installed, skipping."
elif [ "$OS" = "Darwin" ]; then
  if ! command -v brew >/dev/null 2>&1; then
    echo "Homebrew not found. Install it first: https://brew.sh"
    exit 1
  fi
  echo "Installing Aider via Homebrew..."
  brew install aider
elif [ "$OS" = "Linux" ]; then
  echo "Installing Aider via pip..."
  python3 -m pip install --user aider-install && "$HOME/.local/bin/aider-install"
else
  echo "Unsupported OS: $OS. Install Aider manually: https://aider.chat/docs/install.html"
  exit 1
fi

# --- 2. Verify the PC is reachable ---
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [ -x "$SCRIPT_DIR/check-connection.sh" ]; then
  "$SCRIPT_DIR/check-connection.sh" "$PC_HOST" || echo "Continuing anyway; fix connectivity before use." >&2
else
  echo "Checking Ollama at http://${PC_HOST}:11434 ..."
  if curl -s -m 5 "http://${PC_HOST}:11434/api/version" >/dev/null; then
    echo "Reachable."
  else
    echo "WARNING: could not reach http://${PC_HOST}:11434 — is setup-pc.ps1 done running there," >&2
    echo "and are both machines on the same LAN? Continuing anyway; fix connectivity before use." >&2
  fi
fi

# --- 3. Persist OLLAMA_API_BASE in the shell profile ---
PROFILE=""
case "$SHELL" in
  */zsh) PROFILE="$HOME/.zshrc" ;;
  */bash) PROFILE="$HOME/.bash_profile" ;;
  *) PROFILE="$HOME/.profile" ;;
esac

MARKER="# local-ai-rig"
if [ -f "$PROFILE" ] && grep -q "$MARKER" "$PROFILE" 2>/dev/null; then
  # Remove previous local-ai-rig lines so re-running updates them cleanly
  sed -i.bak "/$MARKER/d" "$PROFILE"
fi
{
  echo "export OLLAMA_API_BASE=http://${PC_HOST}:11434 $MARKER"
  echo "alias aider-big=\"aider --model ollama_chat/${BIG_MODEL}\" $MARKER"
} >> "$PROFILE"
echo "Added OLLAMA_API_BASE and the aider-big alias to $PROFILE"

# --- 4. Aider config ---
CONF="$HOME/.aider.conf.yml"
cat > "$CONF" <<EOF
yes-always: true
pretty: false
model: ollama_chat/${MODEL}
EOF
echo "Wrote $CONF"

echo ""
echo "== Done =="
echo "Open a NEW terminal (so the env var and alias load), cd into a project, and run:"
echo "  aider          # fast model (${MODEL}) - everyday single-file edits"
echo "  aider-big      # bigger model (${BIG_MODEL}) - new projects, multi-file scaffolds"
echo ""
echo "Both talk to ${PC_HOST}'s GPU automatically. See README for which to use when."
