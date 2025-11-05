#!/usr/bin/env bash
# ============================================================
#  Lost Minions --- Workflow Sync Utility
# ------------------------------------------------------------
#  Syncs selected workflows to each repo based on repos.json
#  Always includes update-submodules.yml for all enabled repos.
#  Avoids duplicates automatically.
# ============================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPOS_FILE="$SCRIPT_DIR/repos.json"
WORKFLOW_SRC="$SCRIPT_DIR/../.github/workflows"

if [ ! -f "$REPOS_FILE" ]; then
  echo "Missing repos.json"
  exit 1
fi

strip_comments() {
  perl -0777 -pe '
    s{/\*.*?\*/}{}gs;
    s{//[^\r\n]*}{}g;
    s/,\s*([}\]])/\1/g;
  ' "$1"
}

CLEAN_JSON=$(mktemp)
strip_comments "$REPOS_FILE" > "$CLEAN_JSON"

repos=$(jq -c '.repos[] | select(.enabled == true)' "$CLEAN_JSON")

echo "# Syncing workflows to enabled repositories"
echo ""

while IFS= read -r repo; do
  ORG=$(echo "$repo" | jq -r '.org')
  NAME=$(echo "$repo" | jq -r '.name')
  FULL="$ORG/$NAME"

  # --- Base workflows (always include update-submodules.yml) ---
  WORKFLOWS=("update-submodules.yml")

  # --- Merge any defined workflows from JSON ---
  EXTRA_WORKFLOWS=$(echo "$repo" | jq -r '.workflows[]?' 2>/dev/null || true)
  if [ -n "$EXTRA_WORKFLOWS" ]; then
    while IFS= read -r wf; do
      [[ -n "$wf" ]] && WORKFLOWS+=("$wf")
    done <<< "$EXTRA_WORKFLOWS"
  fi

  # --- Deduplicate the list ---
  mapfile -t WORKFLOWS < <(printf "%s\n" "${WORKFLOWS[@]}" | awk '!seen[$0]++')

  echo "## Repository: $FULL"
  TMPDIR=$(mktemp -d)

  if ! gh repo clone "$FULL" "$TMPDIR" -- --depth=1 >/dev/null 2>&1; then
    echo "  - Clone failed for $FULL"
    continue
  fi

  mkdir -p "$TMPDIR/.github/workflows"

  for wf in "${WORKFLOWS[@]}"; do
    SRC="$WORKFLOW_SRC/$wf"
    if [ -f "$SRC" ]; then
      cp "$SRC" "$TMPDIR/.github/workflows/$wf"
      echo "  - Copied $wf"
    else
      echo "  - Missing source file: $wf"
    fi
  done

  cd "$TMPDIR"
  if [ -n "$(git status --porcelain)" ]; then
    git add .github/workflows
    git commit -m "Sync workflows from template repo"
    git push origin HEAD >/dev/null 2>&1 || echo "  - Push failed for $FULL"
    echo "  - Updated workflows for $FULL"
  else
    echo "  - No workflow changes for $FULL"
  fi

  cd "$SCRIPT_DIR"
  rm -rf "$TMPDIR"
  echo ""
done <<< "$repos"

echo "Workflow sync complete."
