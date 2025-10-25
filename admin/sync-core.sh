#!/usr/bin/env bash
# ============================================================
#  The Portal Realm --- Unified GitHub Sync Controller (bash)
# ------------------------------------------------------------
#  Runs file, issue type, label, and secret syncs for all enabled repos.
#  Clean Markdown-safe output for GitHub workflow summaries.
# ============================================================

set -euo pipefail

START_DIR="$(pwd)"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPOS_FILE="$SCRIPT_DIR/repos.json"

# --- Verify repos.json --------------------------------------------------------
if [ ! -f "$REPOS_FILE" ]; then
  echo "Missing repos.json"
  exit 1
fi

echo "# The Portal Realm GitHub Sync"
echo ""

# --- Sync labels for the source repo itself ----------------------------------
if [ -n "${GITHUB_REPOSITORY:-}" ]; then
  echo "## Repository: $GITHUB_REPOSITORY (self)"
  echo ""
  echo "### Labels (Self-Sync)"
  bash "$SCRIPT_DIR/sync-labels.sh" "$GITHUB_REPOSITORY" || {
    echo "sync-labels.sh failed for $GITHUB_REPOSITORY"
    exit 1
  }
  echo ""
  echo "---"
  echo ""
fi

# --- Read enabled repos -------------------------------------------------------
# Clean the JSON file (strip comments, fix trailing commas, handle CRLF)
strip_comments() {
  perl -0777 -pe '
    s{/\*.*?\*/}{}gs;          # remove /* ... */ blocks
    s{//[^\r\n]*}{}g;          # remove // comments (CRLF or LF)
    s/,\s*([}\]])/\1/g;        # remove trailing commas
  ' "$1"
}

# Create a temp copy of the cleaned file
CLEAN_REPOS=$(mktemp)
strip_comments "$REPOS_FILE" > "$CLEAN_REPOS"

# Now parse with jq
repos=$(jq -c '.repos[] | select(.enabled == true)' "$CLEAN_REPOS")

while IFS= read -r repo; do
  ORG=$(echo "$repo" | jq -r '.org')
  NAME=$(echo "$repo" | jq -r '.name')
  FULL="$ORG/$NAME"

  echo "## Repository: $FULL"
  echo ""

  # ------------------------------------------------------------
  # [0/3] Secrets
  # ------------------------------------------------------------
  echo "### [0/3] Secrets"
  bash "$SCRIPT_DIR/sync-secrets.sh" "$FULL" || {
    echo "sync-secrets.sh failed for $FULL"
    exit 1
  }
  echo ""
  echo "---"
  echo ""

  # ------------------------------------------------------------
  # [1/3] Templates and Policies
  # ------------------------------------------------------------
  echo "### [1/3] Templates and Policies"
  bash "$SCRIPT_DIR/sync-files.sh" "$FULL" || {
    echo "sync-files.sh failed for $FULL"
    exit 1
  }
  echo ""
  echo "---"
  echo ""

  # ------------------------------------------------------------
  # [2/3] Issue Types
  # ------------------------------------------------------------
  echo "### [2/3] Issue Types"
  bash "$SCRIPT_DIR/sync-issue-types.sh" "$FULL" || {
    echo "sync-issue-types.sh failed for $FULL"
    exit 1
  }
  echo ""
  echo "---"
  echo ""

  # ------------------------------------------------------------
  # [3/3] Labels
  # ------------------------------------------------------------
  echo "### [3/3] Labels"
  bash "$SCRIPT_DIR/sync-labels.sh" "$FULL" || {
    echo "sync-labels.sh failed for $FULL"
    exit 1
  }
  echo ""
  echo "---"
  echo ""

  echo "Done: $FULL"
  echo ""
done <<< "$repos"

cd "$START_DIR"
echo "All enabled repositories processed successfully."
