#!/usr/bin/env bash
# Prepare ~/.claude from defaults + /config, install runtime plugins/skills,
# then keep an interactive Claude session alive in tmux session "claude".
set -euo pipefail

CFG="$CLAUDE_CONFIG_DIR"
mkdir -p "$CFG/skills" /config/skills

# --- Seed /config with templates if the local dir is empty -------------------
for f in install.yaml CLAUDE.md settings.json; do
  [[ -e "/config/$f" ]] || cp "/opt/defaults/templates/$f" "/config/$f"
done

# --- First run: skip onboarding and trust /workspace ------------------------
state="$CFG/.claude.json"
[[ -s "$state" ]] || echo '{}' > "$state"
tmp=$(mktemp)
jq '.hasCompletedOnboarding = true
    | .projects["/workspace"].hasTrustDialogAccepted = true
    | .projects["/workspace"].hasCompletedProjectOnboarding = true' "$state" > "$tmp" && mv "$tmp" "$state"

# --- settings.json: keep what Claude wrote, then apply defaults, then local ---
settings="$CFG/settings.json"
[[ -s "$settings" ]] || echo '{}' > "$settings"
local_settings=/config/settings.json
[[ -s "$local_settings" ]] || local_settings=<(echo '{}')
tmp=$(mktemp)
jq -s '.[0] * .[1] * .[2]' "$settings" /opt/defaults/settings.json "$local_settings" > "$tmp" && mv "$tmp" "$settings"

# --- Memory: generic defaults as user memory, private notes as project memory -
ln -sfn /opt/defaults/CLAUDE.md "$CFG/CLAUDE.md"
ln -sfn /config/CLAUDE.md /workspace/CLAUDE.md

# --- Local skills (defaults baked into the image, private ones from /config) --
for s in /opt/defaults/skills/*/ /config/skills/*/; do
  [[ -f "$s/SKILL.md" ]] && ln -sfn "${s%/}" "$CFG/skills/$(basename "$s")"
done
# Drop links whose target has gone away.
find "$CFG/skills" -maxdepth 1 -xtype l -delete

runtime-install.sh || echo "!! runtime-install reported errors (continuing)"

# --- Fetch the voice transcription model in the background (slow only once) ---
{ whisper-transcribe.sh --download >/dev/null 2>&1 \
    && echo "==> whisper model ready (${WHISPER_MODEL:-large-v3-turbo})" \
    || echo "!! whisper model download failed; the first voice note will retry it"; } &

# --- Start Claude in tmux and stay in the foreground while it runs -----------
tmux new-session -d -s claude -x 200 -y 50 -c /workspace run-claude.sh
echo "==> Claude is running. Attach with: docker compose exec claude tmux attach -t claude"

trap 'tmux kill-server 2>/dev/null; exit 0' TERM INT
while tmux has-session -t claude 2>/dev/null; do sleep 5 & wait $!; done
