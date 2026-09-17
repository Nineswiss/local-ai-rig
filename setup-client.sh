#!/usr/bin/env bash
# setup-client.sh
# Run this on the machine you'll actually work from (Mac or Linux) — the one
# with your project files. Installs Aider and points it at the GPU machine
# running Ollama (set up separately via setup-pc.ps1).
#
# Usage:
#   ./setup-client.sh <pc-ip> [model]
#   ./setup-client.sh 192.168.1.3
#   ./setup-client.sh 192.168.1.3 qwen2.5:32b

set -euo pipefail

PC_IP="${1:-}"
MODEL="${2:-qwen2.5:14b}"

if [ -z "$PC_IP" ]; then
  echo "Usage: $0 <pc-ip> [model]"
  echo "  <pc-ip> is the LAN IP of the machine running setup-pc.ps1"
  echo "  e.g. $0 192.168.1.3"
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
echo "Checking Ollama at http://${PC_IP}:11434 ..."
if curl -s -m 5 "http://${PC_IP}:11434/api/version" >/dev/null; then
  echo "Reachable."
else
  echo "WARNING: could not reach http://${PC_IP}:11434 — is setup-pc.ps1 done running there," >&2
  echo "and are both machines on the same LAN? Continuing anyway; fix connectivity before use." >&2
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
  # Replace the existing line so re-running with a different IP updates it
  sed -i.bak "/$MARKER/d" "$PROFILE"
fi
echo "export OLLAMA_API_BASE=http://${PC_IP}:11434 $MARKER" >> "$PROFILE"
echo "Added OLLAMA_API_BASE to $PROFILE"

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
echo "Open a NEW terminal (so the env var loads), cd into a project, and run:"
echo "  aider"
echo ""
echo "It'll talk to ${MODEL} on ${PC_IP}'s GPU automatically."
