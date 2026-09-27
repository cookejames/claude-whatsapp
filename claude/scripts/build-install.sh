#!/usr/bin/env bash
# Install the `build:` section of one or more install.yaml files.
# Lists from every file are unioned, so local/config/install.yaml only adds.
set -euo pipefail

files=()
for f in "$@"; do [[ -s "$f" ]] && files+=("$f"); done
[[ ${#files[@]} -eq 0 ]] && { echo "build-install: no install.yaml found"; exit 0; }

# Print the unique entries of .build.<key> across all files, one per line.
list() {
  yq eval-all ".build.$1 // [] | .[]" "${files[@]}" | grep -v '^---$' | awk 'NF && !seen[$0]++'
}

mapfile -t apt  < <(list apt)
mapfile -t brew < <(list brew)
mapfile -t npm  < <(list npm)
mapfile -t pip  < <(list pip)

if (( ${#apt[@]} )); then
  echo "==> apt: ${apt[*]}"
  sudo apt-get update
  sudo apt-get install -y --no-install-recommends "${apt[@]}"
  sudo rm -rf /var/lib/apt/lists/*
fi

if (( ${#brew[@]} )); then
  echo "==> brew: ${brew[*]}"
  brew install "${brew[@]}"
  brew cleanup --prune=all || true
fi

if (( ${#npm[@]} )); then
  echo "==> npm: ${npm[*]}"
  npm install -g "${npm[@]}"
fi

if (( ${#pip[@]} )); then
  echo "==> pip (uv tool): ${pip[*]}"
  for p in "${pip[@]}"; do uv tool install "$p"; done
fi

echo "==> build-install done"
