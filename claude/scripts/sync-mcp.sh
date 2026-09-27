#!/usr/bin/env bash
# Apply runtime.mcp from install.yaml (defaults + /config) to Claude's user scope.
# Run at container start and before every Claude (re)launch, so editing
# install.yaml and typing /exit is enough to pick up changes.
set -uo pipefail

files=()
for f in /opt/defaults/install.yaml /config/install.yaml; do [[ -s "$f" ]] && files+=("$f"); done
[[ ${#files[@]} -eq 0 ]] && exit 0

# Refuse to act on a file that doesn't parse, rather than treating it as empty.
for f in "${files[@]}"; do
  if ! err=$(yq eval '.' "$f" 2>&1 >/dev/null); then
    echo "!! $f is not valid YAML, skipping MCP sync (servers left as they were): $err" >&2
    exit 1
  fi
done

# runtime.mcp is a map of name -> server config (same shape as .mcp.json), merged
# with local winning. ${VAR} in any string is filled from the container env
# (local/.env), so secrets stay out of install.yaml. Servers are written at user
# scope; ones we added before but are no longer declared are removed, and servers
# added by hand with `claude mcp add` are left alone.
state="$CLAUDE_CONFIG_DIR/.claude.json"
managed="$CLAUDE_CONFIG_DIR/.managed-mcp.json"
[[ -s "$state" ]] || echo '{}' > "$state"
[[ -s "$managed" ]] || echo '[]' > "$managed"

declared=$(yq eval-all -o=json -I=0 '. as $f ireduce ({}; . * ($f.runtime.mcp // {}))' "${files[@]}" |
  jq -c 'walk(if type == "string"
              then gsub("\\$\\{(?<v>[A-Za-z_][A-Za-z0-9_]*)\\}"; env[.v] // "")
              else . end)')

tmp=$(mktemp)
jq --argjson declared "$declared" --slurpfile managed "$managed" '
  .mcpServers = ((.mcpServers // {}) | with_entries(select(.key as $k | $managed[0] | index($k) | not)))
                + $declared
' "$state" > "$tmp" && mv "$tmp" "$state"
jq -n --argjson declared "$declared" '$declared | keys' > "$managed"

if [[ "$declared" != "{}" ]]; then
  echo "==> mcp servers: $(jq -r 'keys | join(" ")' <<<"$declared")"
fi
