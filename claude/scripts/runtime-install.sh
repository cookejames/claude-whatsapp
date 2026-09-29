#!/usr/bin/env bash
# Apply the `runtime:` section of install.yaml (defaults + /config) on every start:
# plugin marketplaces, plugins and git-hosted skills. Safe to re-run.
set -uo pipefail

files=()
for f in /opt/defaults/install.yaml /config/install.yaml; do [[ -s "$f" ]] && files+=("$f"); done
[[ ${#files[@]} -eq 0 ]] && exit 0

# Refuse to act on a file that doesn't parse, rather than treating it as empty.
for f in "${files[@]}"; do
  if ! err=$(yq eval '.' "$f" 2>&1 >/dev/null); then
    echo "!! $f is not valid YAML, skipping runtime installs: $err" >&2
    exit 1
  fi
done

list() {
  yq eval-all ".runtime.$1 // [] | .[]" "${files[@]}" | grep -v '^---$' | awk 'NF && !seen[$0]++'
}

# --- Marketplaces ------------------------------------------------------------
known_markets=$(claude plugin marketplace list --json 2>/dev/null || echo '[]')
while read -r src; do
  [[ -z "$src" ]] && continue
  if grep -qF "$src" <<<"$known_markets"; then
    claude plugin marketplace update >/dev/null 2>&1 || true
  else
    echo "==> marketplace add $src"
    claude plugin marketplace add "$src" || echo "!! failed to add marketplace $src"
  fi
done < <(list marketplaces)

# --- Plugins -----------------------------------------------------------------
installed=$(claude plugin list --json 2>/dev/null || echo '[]')
while read -r plugin; do
  [[ -z "$plugin" ]] && continue
  if grep -qF "\"${plugin}\"" <<<"$installed" || grep -qF "${plugin%@*}" <<<"$installed"; then
    echo "==> plugin $plugin already installed"
  else
    echo "==> plugin install $plugin"
    claude plugin install "$plugin" || echo "!! failed to install plugin $plugin"
  fi
done < <(list plugins)

# --- Skills from git -----------------------------------------------------------
# Entries: { git: <url>, path: <dir inside repo, optional>, name: <optional>, ref: <optional> }
repos_dir="$CLAUDE_CONFIG_DIR/skill-repos"
skills_dir="$CLAUDE_CONFIG_DIR/skills"
mkdir -p "$repos_dir" "$skills_dir"

# Several entries may share one repo (one per skill); clone or pull it once per run.
declare -A synced=()
while read -r entry; do
  url=$(jq -r '.git // empty' <<<"$entry")
  [[ -z "$url" ]] && continue
  path=$(jq -r '.path // empty' <<<"$entry")
  ref=$(jq -r '.ref // empty' <<<"$entry")
  repo_name=$(basename "${url%.git}")
  dest="$repos_dir/$repo_name"

  if [[ -z "${synced[$dest]:-}" ]]; then
    if [[ -d "$dest/.git" ]]; then
      git -C "$dest" pull --ff-only -q || echo "!! could not update $url"
    else
      echo "==> clone skills $url"
      git clone -q ${ref:+--branch "$ref"} --depth 1 "$url" "$dest" || { echo "!! clone failed $url"; continue; }
    fi
    synced[$dest]=1
  fi

  src="$dest${path:+/$path}"
  name=$(jq -r --arg d "$(basename "$src")" '.name // $d' <<<"$entry")
  if [[ -f "$src/SKILL.md" ]]; then
    ln -sfn "$src" "$skills_dir/$name"
  else
    # A directory of skills: link each child that has a SKILL.md.
    for s in "$src"/*/; do
      [[ -f "$s/SKILL.md" ]] && ln -sfn "${s%/}" "$skills_dir/$(basename "$s")"
    done
  fi
done < <(yq eval-all -o=json -I=0 '.runtime.skills // [] | .[]' "${files[@]}" | grep -v '^---$' | awk 'NF && !seen[$0]++')

sync-mcp.sh

echo "==> runtime-install done"
