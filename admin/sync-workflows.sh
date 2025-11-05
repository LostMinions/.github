#!/usr/bin/env bash
# ============================================================
#  Lost Minions --- Workflow Sync (per repo)
# ------------------------------------------------------------
#  Syncs selected workflows for one repo.
#  Always includes update-submodules.yml.
#  Usage: bash sync-workflows.sh <org/repo>
# ============================================================

set -euo pipefail

if [ $# -lt 1 ]; then
  echo "Usage: bash sync-workflows.sh <org/repo>"
  exit 1
fi

FULL_REPO="$1"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
SOURCE_DIR="$ROOT_DIR/.github/workflows"
REPOS_FILE="$SCRIPT_DIR/repos.json"

TMPDIR=$(mktemp -d)
cleanup() {
  cd "$SCRIPT_DIR" || true
  rm -rf "$TMPDIR" || true
}
trap cleanup EXIT

for cmd in gh git jq; do
  if ! command -v "$cmd" >/dev/null 2>&1; then
    echo "Missing dependency: $cmd"
    exit 1
  fi
done

# --- Find repo config from repos.json ---
strip_comments() {
  perl -0777 -pe '
    s{/\*.*?\*/}{}gs;
    s{//[^\r\n]*}{}g;
    s/,\s*([}\]])/\1/g;
  ' "$1"
}

CLEAN_JSON=$(mktemp)
strip_comments "$REPOS_FILE" > "$CLEAN_JSON"

REPO_CONFIG=$(jq -c --arg full "$FULL_REPO" '.repos[] | select((.org + "/" + .name) == $full)' "$CLEAN_JSON")

if [ -z "$REPO_CONFIG" ]; then
  echo "Repo not found or not enabled in repos.json: $FULL_REPO"
  exit 1
fi

if [ "$(echo "$REPO_CONFIG" | jq -r '.enabled')" != "true" ]; then
  echo "Repo disabled in repos.json: $FULL_REPO"
  exit 0
fi

# --- Deprecated workflow list ---
DEPRECATED_WORKFLOWS=(
  "weekly-submodule-update.yml"
)

# --- Build workflow list ---
WORKFLOWS=(
  "update-submodules.yml"
)

EXTRA_WORKFLOWS=$(echo "$REPO_CONFIG" | jq -r '.workflows[]?' 2>/dev/null || true)
if [ -n "$EXTRA_WORKFLOWS" ]; then
  while IFS= read -r wf; do
    [[ -n "$wf" ]] && WORKFLOWS+=("$wf")
  done <<< "$EXTRA_WORKFLOWS"
fi

# Deduplicate
mapfile -t WORKFLOWS < <(printf "%s\n" "${WORKFLOWS[@]}" | awk '!seen[$0]++')

echo "Syncing workflows for $FULL_REPO"
echo ""

if ! gh repo clone "$FULL_REPO" "$TMPDIR" -- --depth=1 >/dev/null 2>&1; then
  echo "Failed to clone $FULL_REPO"
  exit 1
fi
cd "$TMPDIR"

mkdir -p .github/workflows

# --- Remove deprecated workflows (clean up old names) ---
for old in "${DEPRECATED_WORKFLOWS[@]}"; do
  if [ -f "$TMPDIR/.github/workflows/$old" ]; then
    echo "  - Removing deprecated $old"
    rm -f "$TMPDIR/.github/workflows/$old"
  fi
done

for wf in "${WORKFLOWS[@]}"; do
  SRC="$SOURCE_DIR/$wf"
  if [ -f "$SRC" ]; then
    cp "$SRC" ".github/workflows/$wf"
    echo "  - Copied $wf"
  else
    echo "  - Missing source file: $wf"
  fi
done

if [ -n "$(git status --porcelain)" ]; then
  git add .github/workflows
  git commit -m "Sync workflows from template repo" >/dev/null || true
  if git push origin HEAD >/dev/null 2>&1; then
    echo "  - Updated $FULL_REPO"
  else
    echo "! Push failed for $FULL_REPO"
  fi
else
  echo "  - No workflow changes for $FULL_REPO"
fi

echo ""
echo "Finished syncing workflows for $FULL_REPO"
