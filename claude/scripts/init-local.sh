#!/usr/bin/env bash
# Scaffold the private local/ folder (sibling of repo/) from the templates.
# Usage: claude/scripts/init-local.sh [LOCAL_DIR]   (default ../local)
set -euo pipefail

repo=$(cd "$(dirname "$0")/../.." && pwd)
local_dir=${1:-${LOCAL_DIR:-$repo/../local}}
templates="$repo/defaults/templates"

mkdir -p "$local_dir"/{config/skills,data/claude,data/whatsapp,data/camoufox,data/gws,workspace}
local_dir=$(cd "$local_dir" && pwd)

for f in install.yaml CLAUDE.md settings.json; do
  if [[ -e "$local_dir/config/$f" ]]; then
    echo "keep   $local_dir/config/$f"
  else
    cp "$templates/$f" "$local_dir/config/$f"
    echo "create $local_dir/config/$f"
  fi
done

for pair in ".env.example:.env" "camoufox.env.example:camoufox.env"; do
  src=${pair%%:*} dst=${pair#*:}
  if [[ ! -e "$local_dir/$dst" ]]; then
    cp "$repo/$src" "$local_dir/$dst"
    echo "create $local_dir/$dst"
  fi
done

echo
echo "Now edit $local_dir/config/CLAUDE.md (who you are, allowed contacts)"
echo "and $local_dir/config/install.yaml (extra packages/plugins/skills)."
