#!/usr/bin/env bash
# aider-retry.sh
# Runs an Aider request, and if it fails to actually write any files (the
# model narrated instead of committing to the edit format - a real,
# observed failure mode with local models on complex requests), retries
# with a completely FRESH attempt rather than Aider's own in-place
# reflection. In-place reflection just feeds the model a growing,
# increasingly confused conversation history; a clean retry has a real
# chance of just working, since these failures aren't deterministic.
#
# Usage (run from the directory you want the files created in):
#   ./aider-retry.sh "<your request>" [max_attempts] [model]
#   ./aider-retry.sh "create a react + vite app ... call it ReactTest"
#   ./aider-retry.sh "..." 5 devstral:24b

set -uo pipefail

MESSAGE="${1:-}"
MAX_ATTEMPTS="${2:-3}"
MODEL="${3:-devstral:24b}"

if [ -z "$MESSAGE" ]; then
  echo "Usage: $0 \"<request>\" [max_attempts] [model]"
  exit 1
fi

export OLLAMA_API_BASE="${OLLAMA_API_BASE:-http://adampc.local:11434}"

# Fail fast with a clear reason instead of burning through $MAX_ATTEMPTS
# retries (each potentially several minutes) against a PC that was never
# reachable to begin with.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [ -x "$SCRIPT_DIR/check-connection.sh" ]; then
  if ! "$SCRIPT_DIR/check-connection.sh" >/tmp/aider-retry-preflight.log 2>&1; then
    echo "Preflight check failed - can't reach the PC/Ollama. Details:"
    cat /tmp/aider-retry-preflight.log
    exit 1
  fi
fi

# Force a git repo scoped to THIS directory before Aider ever runs. Without
# this, if any ANCESTOR directory happens to be a git repo (e.g. because an
# earlier Aider session was accidentally launched from there and
# auto-created one), Aider treats that ancestor as the project root and
# writes files relative to it instead of here - files land in the wrong
# place entirely, silently, while looking successful. Learned this the
# hard way. `git init` on an already-git-tracked directory is a no-op, so
# this is always safe to run.
if [ ! -d .git ]; then
  git init -q
fi

LOGDIR="$(pwd)/.aider-retry-logs"
mkdir -p "$LOGDIR"

# Counts real project file changes, ignoring Aider's own bookkeeping files
# (.gitignore gets touched on first-ever run regardless of task success).
count_real_changes() {
  git status --porcelain 2>/dev/null | cut -c4- | grep -v -E '^\.aider|^\.gitignore$' | grep -c .
}

for attempt in $(seq 1 "$MAX_ATTEMPTS"); do
  echo "=== Attempt $attempt/$MAX_ATTEMPTS (model: $MODEL) ==="
  LOGFILE="$LOGDIR/attempt-${attempt}.log"

  BEFORE=$(count_real_changes)

  aider --model "ollama_chat/${MODEL}" \
    --message "$MESSAGE" \
    --yes-always --no-auto-commits \
    > "$LOGFILE" 2>&1

  AFTER=$(count_real_changes)

  if [ "$AFTER" -gt "$BEFORE" ]; then
    echo "Success on attempt $attempt - files were created/modified."
    echo "Full log: $LOGFILE"
    echo ""
    git status --porcelain | cut -c4- | grep -v -E '^\.aider|^\.gitignore$'
    exit 0
  else
    echo "Attempt $attempt produced no file changes. Last lines:"
    tail -6 "$LOGFILE"
    echo "(full log: $LOGFILE)"
    echo ""
  fi
done

echo "All $MAX_ATTEMPTS attempts failed to write any files."
echo "Logs saved in $LOGDIR for review. Consider breaking the request into smaller pieces."
exit 1
