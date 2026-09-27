#!/usr/bin/env bash
# Runs inside tmux. Restarts Claude whenever it exits so WhatsApp stays connected.
#   CLAUDE_CHANNELS    space-separated channel plugins to load
#   CLAUDE_CONTINUE    1 = resume the previous conversation on restart
#   CLAUDE_CHROME      1 = pass --chrome (phase 2)
#   CLAUDE_EXTRA_ARGS  anything else to append
set -uo pipefail
cd /workspace || exit 1

channels=${CLAUDE_CHANNELS:-plugin:whatsapp-channel@whatsapp-claude-plugin}

while true; do
  args=(--dangerously-skip-permissions)
  for c in $channels; do args+=(--dangerously-load-development-channels "$c"); done
  [[ "${CLAUDE_CHROME:-0}" == 1 ]] && args+=(--chrome)
  if [[ "${CLAUDE_CONTINUE:-1}" == 1 ]] && compgen -G "$CLAUDE_CONFIG_DIR/projects/-workspace/*.jsonl" >/dev/null; then
    args+=(--continue)
  fi
  # shellcheck disable=SC2086
  claude "${args[@]}" ${CLAUDE_EXTRA_ARGS:-}
  echo "Claude exited with status $?; restarting in 5s (Ctrl-C to stop the loop)..."
  sleep 5
done
