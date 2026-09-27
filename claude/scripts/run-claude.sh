#!/usr/bin/env bash
# Runs inside tmux. Restarts Claude whenever it exits so WhatsApp stays connected.
#   CLAUDE_CHANNELS    space-separated channel plugins to load
#   CLAUDE_CONTINUE    1 = resume the previous conversation on restart
#   CLAUDE_CHROME      1 = pass --chrome (phase 2)
#   CLAUDE_REMOTE_CONTROL       1 = enable Remote Control (continue from claude.ai / the app)
#   CLAUDE_REMOTE_CONTROL_NAME  optional Remote Control session name
#   CLAUDE_EXTRA_ARGS  anything else to append
#   CLAUDE_AUTO_CONFIRM_CHANNELS  1 = answer the development-channels warning automatically
set -uo pipefail
cd /workspace || exit 1

channels=${CLAUDE_CHANNELS:-plugin:whatsapp-channel@whatsapp-claude-plugin}

# Nobody is at the terminal after a restart, so accept the development-channels
# warning ("I am using this for local development" is option 1, pre-selected).
auto_confirm_channels() {
  local pane=${TMUX_PANE:-claude}
  for _ in $(seq 1 60); do
    sleep 2
    if tmux capture-pane -p -t "$pane" 2>/dev/null | grep -q 'I am using this for local development'; then
      tmux send-keys -t "$pane" Enter
      return
    fi
  done
}

while true; do
  args=(--dangerously-skip-permissions)
  for c in $channels; do args+=(--dangerously-load-development-channels "$c"); done
  [[ "${CLAUDE_CHROME:-0}" == 1 ]] && args+=(--chrome)
  if [[ "${CLAUDE_REMOTE_CONTROL:-1}" == 1 ]]; then
    args+=(--remote-control ${CLAUDE_REMOTE_CONTROL_NAME:+"$CLAUDE_REMOTE_CONTROL_NAME"})
  fi
  if [[ "${CLAUDE_CONTINUE:-1}" == 1 ]] && compgen -G "$CLAUDE_CONFIG_DIR/projects/-workspace/*.jsonl" >/dev/null; then
    args+=(--continue)
  fi
  [[ "${CLAUDE_AUTO_CONFIRM_CHANNELS:-1}" == 1 ]] && auto_confirm_channels &
  # shellcheck disable=SC2086
  claude "${args[@]}" ${CLAUDE_EXTRA_ARGS:-}
  echo "Claude exited with status $?; restarting in 5s (Ctrl-C to stop the loop)..."
  sleep 5
done
