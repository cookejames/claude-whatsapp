#!/usr/bin/env bash
# Sign Claude back in over WhatsApp. One pass; entrypoint.sh runs it every
# minute when LOGIN_ALERT_CHAT (a WhatsApp chat id) is set.
#
# Claude's sign-in stops renewing after about four weeks, and Claude then wipes
# the stored tokens and answers every prompt with "Login expired". When that
# happens this script:
#   1. starts /login in the tmux session and sends the sign-in link to
#      LOGIN_ALERT_CHAT through the WhatsApp plugin (which keeps running);
#   2. waits up to 10 minutes for a reply from that chat with the code the
#      sign-in page shows (a long string with a "#" in it), then types it into
#      the session. When the link carries its OAuth state (older Claude Code
#      versions), the part after "#" must match it;
#   3. reports the result. After a link expires it waits for "login" from the
#      same chat before sending another, so an outage overnight is one message.
# `claude-login-watch.sh --test` runs the same flow while Claude is signed in;
# it succeeds when the new sign-in replaces the stored one, and if it fails the
# current sign-in is untouched.
# The code is never logged or stored. Events go to ~/.claude/login-watch.log.
set -uo pipefail

chat=${LOGIN_ALERT_CHAT:-}
[[ -n "$chat" ]] || exit 0
test_mode=0
[[ "${1:-}" == "--test" ]] && test_mode=1

cfg=${CLAUDE_CONFIG_DIR:-$HOME/.claude}
creds="$cfg/.credentials.json"
dir="$cfg/login-watch"
pending="$dir/pending"     # "<state> <epoch> <iso> <test 0|1>" while a link is out
expired="$dir/expired"     # "<iso>" once a link timed out, until "login"
outage="$dir/outage"       # exists while signed out and the owner was told
log="$cfg/login-watch.log"
messages="$HOME/.whatsapp-channel/messages.jsonl"
link_ttl=600
mkdir -p "$dir"

exec 9>"$dir/lock"
flock -n 9 || exit 0

say() { echo "$(date '+%F %T') $*" >>"$log"; }
send() { whatsapp-send.mjs "$chat" "$1" || say "!! WhatsApp send failed"; }
signed_in() { jq -e '(.claudeAiOauth.accessToken // "") | length > 0' "$creds" >/dev/null 2>&1; }
creds_stamp() { stat -c %Y "$creds" 2>/dev/null || echo 0; }
pane() { tmux capture-pane -p -J -t claude 2>/dev/null; }
now_iso() { date -u +%FT%T.000Z; }

# Texts from the owner's chat received since $1, newest last.
owner_texts_since() {
  [[ -f "$messages" ]] || return 0
  jq -r --arg c "$chat" --arg t "$1" \
    'select(.direction == "in" and .chat_id == $c and .ts >= $t) | .text // empty' \
    "$messages" 2>/dev/null
}

# Open /login and print the sign-in URL. Returns 1 if it can't get one.
start_login() {
  tmux has-session -t claude 2>/dev/null && pgrep -x claude >/dev/null || return 1
  tmux send-keys -t claude Escape
  sleep 1
  tmux send-keys -t claude -l "/login"
  sleep 1
  tmux send-keys -t claude Enter
  local url="" menu_done=0
  for _ in $(seq 1 20); do
    sleep 1
    if ((!menu_done)) && pane | grep -q "Select login method"; then
      # Option 1 (Claude subscription) is pre-selected.
      pane | grep -q "❯ 1. Claude account with subscription" || return 1
      tmux send-keys -t claude Enter
      menu_done=1
      continue
    fi
    url=$(pane | awk '/^https:\/\/claude\.(ai|com)\/(cai\/)?oauth\/authorize/ {f = 1}
                      f && /Hold Shift|Paste code/ {exit}
                      f {gsub(/[[:space:]]/, ""); printf "%s", $0}')
    [[ "$url" == *"?"?* ]] && { echo "$url"; return 0; }
  done
  return 1
}

# --- A link is out: wait for the code ------------------------------------------
if [[ -f "$pending" ]]; then
  read -r state since since_iso pending_test <"$pending"
  # Signed in some other way (e.g. /login at the terminal) during a real outage.
  if ((!pending_test)) && signed_in; then
    send "✅ Claude is signed in again."
    say "signed in again (not via WhatsApp)"
    rm -f "$pending" "$expired" "$outage"
    exit 0
  fi
  # "-" = the link didn't show its state, so accept any code-shaped reply.
  [[ "$state" == "-" ]] && want='[A-Za-z0-9_-]{16,}' || want=$state
  code=$(owner_texts_since "$since_iso" | sed 's/^[[:space:]]*//; s/[[:space:]]*$//' |
    grep -E "^[A-Za-z0-9_-]{20,}#${want}\$" | tail -1)
  if [[ -n "$code" ]]; then
    rm -f "$pending"
    before=$(creds_stamp)
    if pane | grep -q "Paste code here"; then
      tmux send-keys -t claude -l -- "$code"
      sleep 1
      tmux send-keys -t claude Enter
      unset code
      for _ in $(seq 1 30); do
        sleep 1
        signed_in && [[ "$(creds_stamp)" != "$before" ]] && break
      done
    fi
    if signed_in && [[ "$(creds_stamp)" != "$before" ]]; then
      sleep 2
      pane | grep -q "Login successful" && tmux send-keys -t claude Enter
      send "✅ Claude is signed in again. You can delete your code message (Delete for everyone)."
      say "signed in with a code from WhatsApp (test=$pending_test)"
      rm -f "$expired" "$outage"
    elif ((pending_test)); then
      tmux send-keys -t claude Escape
      send "❌ Test: that didn't complete the sign-in. Claude is still signed in on its previous login."
      say "!! test: code from WhatsApp did not sign in"
    else
      now_iso >"$expired"
      send "❌ That didn't sign Claude in. Reply *login* for a new link."
      say "!! code from WhatsApp did not sign in"
    fi
    exit 0
  fi
  if (($(date +%s) - since >= link_ttl)); then
    rm -f "$pending"
    if ((pending_test)); then
      tmux send-keys -t claude Escape
      send "Test: the sign-in link expired, so I've cancelled the test. Claude is still signed in."
      say "test link expired"
    else
      now_iso >"$expired"
      send "The sign-in link has expired. Reply *login* whenever you're ready and I'll send a new one."
      say "link expired"
    fi
  fi
  exit 0
fi

if signed_in && ((!test_mode)); then
  if [[ -e "$outage" ]]; then
    send "✅ Claude is signed in again."
    say "signed in again"
  fi
  rm -f "$expired" "$outage"
  exit 0
fi

# --- Signed out (or --test): send a sign-in link -------------------------------
if ((!test_mode)) && [[ -f "$expired" ]]; then
  owner_texts_since "$(cat "$expired")" | grep -qixE '[[:space:]]*login[[:space:]]*' || exit 0
fi

since_iso=$(now_iso)
if ! url=$(start_login); then
  if ((test_mode)); then
    say "!! test: could not get a sign-in link"
    echo "could not get a sign-in link" >&2
  elif [[ ! -e "$outage" ]]; then
    send "⚠️ Claude in the WhatsApp container is signed out, so I can't reply or run scheduled jobs, and I couldn't open the sign-in screen. Please run /login in the session."
    touch "$outage"
  fi
  say "!! could not get a sign-in link"
  exit 1
fi
state=-
if [[ "$url" == *"&state="* ]]; then
  state=${url##*&state=}
  state=${state%%&*}
  if [[ ! "$state" =~ ^[A-Za-z0-9_-]{16,}$ ]]; then
    say "!! unexpected sign-in link format; not sent"
    exit 1
  fi
fi
echo "$state $(date +%s) $since_iso $test_mode" >"$pending"
rm -f "$expired"
if ((test_mode)); then
  intro="🧪 Test of signing Claude in over WhatsApp (Claude is still signed in; nothing breaks if you ignore this)."
else
  intro="⚠️ Claude in the WhatsApp container is signed out, so I can't reply or run scheduled jobs."
  touch "$outage"
fi
send "$intro

1. Open this link and sign in with your Claude account:
$url

2. Reply here with the code it shows you.

The link works for 10 minutes. I'll type the code into Claude and tell you when it's done."
say "sign-in link sent (test=$test_mode)"
