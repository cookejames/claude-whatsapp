#!/usr/bin/env bash
# Log the Google Workspace CLI (gws) in from inside the container:
#   docker compose exec -it claude gws-login.sh
# gws waits for Google's redirect on http://localhost:<port> inside the container,
# which the Mac's browser can't reach, so the redirect URL is pasted back here and
# replayed with curl.
#   GWS_SCOPES  comma-separated OAuth scope URLs (default: Gmail read-only)
set -uo pipefail

scopes=${GWS_SCOPES:-https://www.googleapis.com/auth/gmail.readonly}
cfg=${GOOGLE_WORKSPACE_CLI_CONFIG_DIR:-$HOME/.config/gws}
if [[ ! -s "$cfg/client_secret.json" ]]; then
  echo "!! Missing $cfg/client_secret.json (local/data/gws/client_secret.json on the Mac)."
  echo "   See README \"Google Workspace\" for creating the OAuth client."
  exit 1
fi

log=$(mktemp)
trap 'rm -f "$log"' EXIT
gws auth login --scopes "$scopes" >"$log" 2>&1 </dev/null &
pid=$!

url=
for _ in $(seq 1 30); do
  url=$(grep -oE 'https://accounts\.google\.com/[^[:space:]]+' "$log" | head -1)
  [[ -n "$url" ]] && break
  kill -0 "$pid" 2>/dev/null || break
  sleep 1
done
if [[ -z "$url" ]]; then
  echo "!! gws didn't print a login URL:"
  cat "$log"
  kill "$pid" 2>/dev/null
  exit 1
fi

cat <<MSG
Scopes: ${scopes//,/ }

1. Open this URL in your browser, sign in and approve:

$url

2. The browser then fails to load a http://localhost:... page. That's expected.
   Copy the whole address from the address bar and paste it below.

MSG
read -r -p "Redirect URL: " redirect
if [[ "$redirect" != http://localhost:* && "$redirect" != http://127.0.0.1:* ]]; then
  echo "!! Expected a http://localhost:... URL"
  kill "$pid" 2>/dev/null
  exit 1
fi

curl -s -o /dev/null "$redirect"
if ! wait "$pid"; then
  echo "!! Login failed:"
  cat "$log"
  exit 1
fi
echo "==> Logged in."
gws auth status
