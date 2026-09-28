#!/usr/bin/env bash
# Runs inside tmux. Restarts Claude whenever it exits so WhatsApp stays connected.
#   CLAUDE_CHANNELS    space-separated channel plugins to load
#   CLAUDE_CONTINUE    1 = resume the previous conversation on restart
#   CLAUDE_CHROME      1 = pass --chrome (phase 2)
#   CLAUDE_REMOTE_CONTROL       1 = enable Remote Control (continue from claude.ai / the app)
#   CLAUDE_REMOTE_CONTROL_NAME  optional Remote Control session name
#   CLAUDE_EXTRA_ARGS  anything else to append
#   CLAUDE_AUTO_CONFIRM_CHANNELS  1 = answer the development-channels warning automatically
#   CLAUDE_DAILY_RESET HH:MM = start a fresh conversation once a day (container TZ)
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

# --- Daily reset ---------------------------------------------------------------
# Once today's reset time has passed, the next launch skips --continue. If Claude
# is running, the watcher ends it once the conversation has been quiet for
# 10 minutes, so a reset never cuts off an exchange in progress.
reset_at=${CLAUDE_DAILY_RESET:-}
reset_stamp="$CLAUDE_CONFIG_DIR/.last-daily-reset"
loop_pid=$$
if [[ -n "$reset_at" && ! "$reset_at" =~ ^([01][0-9]|2[0-3]):[0-5][0-9]$ ]]; then
  echo "!! CLAUDE_DAILY_RESET='$reset_at' is not HH:MM; daily reset disabled"
  reset_at=
fi

reset_due() {
  [[ -n "$reset_at" && ! "$(date +%H:%M)" < "$reset_at" ]] &&
    [[ "$(cat "$reset_stamp" 2>/dev/null)" != "$(date +%F)" ]]
}

session_idle() {
  ! find "$CLAUDE_CONFIG_DIR/projects/-workspace" -name '*.jsonl' -mmin -10 2>/dev/null | grep -q .
}

daily_reset_watcher() {
  while sleep 60; do
    reset_due && session_idle && pkill -TERM -x -P "$loop_pid" claude
  done
}
[[ -n "$reset_at" ]] && daily_reset_watcher &

while true; do
  sync-mcp.sh || echo "!! sync-mcp failed (continuing)"
  fresh=0
  if reset_due; then
    echo "==> daily reset: starting a fresh conversation"
    date +%F > "$reset_stamp"
    fresh=1
  fi
  args=(--dangerously-skip-permissions)
  for c in $channels; do args+=(--dangerously-load-development-channels "$c"); done
  [[ "${CLAUDE_CHROME:-0}" == 1 ]] && args+=(--chrome)
  if [[ "${CLAUDE_REMOTE_CONTROL:-1}" == 1 ]]; then
    args+=(--remote-control ${CLAUDE_REMOTE_CONTROL_NAME:+"$CLAUDE_REMOTE_CONTROL_NAME"})
  fi
  if [[ "${CLAUDE_CONTINUE:-1}" == 1 && $fresh == 0 ]] && compgen -G "$CLAUDE_CONFIG_DIR/projects/-workspace/*.jsonl" >/dev/null; then
    args+=(--continue)
  fi
  [[ "${CLAUDE_AUTO_CONFIRM_CHANNELS:-1}" == 1 ]] && auto_confirm_channels &
  # shellcheck disable=SC2086
  claude "${args[@]}" ${CLAUDE_EXTRA_ARGS:-}
  echo "Claude exited with status $?; restarting in 5s (Ctrl-C to stop the loop)..."
  sleep 5
done
