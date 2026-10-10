#!/usr/bin/env bash
# Type a prompt into the running Claude session, as if someone had typed it at
# the terminal, for scheduled jobs in /config/crontab:
#   claude-prompt.sh 'Run the weekly report'
# If Claude is restarting, waits up to 10 minutes for it to come back. If it's
# busy, the prompt is queued and runs when the current turn ends.
# Each prompt sent is logged to ~/.claude/cron.log.
set -euo pipefail

if [[ $# -ne 1 || -z "$1" ]]; then
  echo "usage: claude-prompt.sh '<prompt>'" >&2
  exit 1
fi
log="${CLAUDE_CONFIG_DIR:-$HOME/.claude}/cron.log"
say() { echo "$(date '+%F %T') $*" | tee -a "$log"; }

# Ready = the tmux session exists and Claude has been up for 30s (long enough
# to get past startup and the development-channels warning).
ready() {
  local pid
  tmux has-session -t claude 2>/dev/null || return 1
  pid=$(pgrep -xo claude) || return 1
  (( $(ps -o etimes= -p "$pid") >= 30 ))
}
for _ in $(seq 1 60); do
  ready && break
  sleep 10
done
if ! ready; then
  say "!! Claude isn't running; not sent: $1"
  exit 1
fi

# Send the text literally, then Enter separately: sent together, Claude can
# treat the Enter as part of a paste and add a newline instead of submitting.
tmux send-keys -t claude -l -- "$1"
sleep 1
tmux send-keys -t claude Enter
say "sent: $1"
