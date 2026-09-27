#!/usr/bin/env bash
# Scaffold the private local/ folder (sibling of repo/) from the templates.
# Usage: claude/scripts/init-local.sh [LOCAL_DIR]   (default ../local)
set -euo pipefail

repo=$(cd "$(dirname "$0")/../.." && pwd)
local_dir=${1:-${LOCAL_DIR:-$repo/../local}}
templates="$repo/defaults/templates"

mkdir -p "$local_dir"/{config/skills,data/claude,data/whatsapp,data/chrome,workspace}
local_dir=$(cd "$local_dir" && pwd)

for f in install.yaml CLAUDE.md settings.json; do
  if [[ -e "$local_dir/config/$f" ]]; then
    echo "keep   $local_dir/config/$f"
  else
    cp "$templates/$f" "$local_dir/config/$f"
    echo "create $local_dir/config/$f"
  fi
done

if [[ ! -e "$local_dir/.env" ]]; then
  cp "$repo/.env.example" "$local_dir/.env"
  echo "create $local_dir/.env"
fi

echo
echo "Now edit $local_dir/config/CLAUDE.md (who you are, allowed contacts)"
echo "and $local_dir/config/install.yaml (extra packages/plugins/skills)."
