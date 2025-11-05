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

# --- Pre-check for archived repositories --------------------------------------
echo "### Checking for archived repositories..."
echo ""

ARCHIVED_LIST=()

while IFS= read -r repo; do
  ORG=$(echo "$repo" | jq -r '.org')
  NAME=$(echo "$repo" | jq -r '.name')
  FULL="$ORG/$NAME"

  # Query GitHub to see if the repo is archived
  IS_ARCHIVED=$(gh repo view "$FULL" --json isArchived -q '.isArchived' 2>/dev/null || echo "false")

  if [[ "$IS_ARCHIVED" == "true" ]]; then
    ARCHIVED_LIST+=("$FULL")
  fi
done <<< "$repos"

if (( ${#ARCHIVED_LIST[@]} > 0 )); then
  echo "The following repositories are archived but marked as enabled:"
  for r in "${ARCHIVED_LIST[@]}"; do
    echo "- $r"
  done
  echo ""
  echo "Please set \"enabled\": false for these in repos.json before running the sync."
  exit 1
else
  echo "No archived repositories detected — proceeding with sync."
  echo ""
fi

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

# --- Main sync loop -----------------------------------------------------------
while IFS= read -r repo; do
  ORG=$(echo "$repo" | jq -r '.org')
  NAME=$(echo "$repo" | jq -r '.name')
  FULL="$ORG/$NAME"

  echo "## Repository: $FULL"
  echo ""

  # ------------------------------------------------------------
  # [0/4] Secrets
  # ------------------------------------------------------------
  echo "### [0/4] Secrets"
  bash "$SCRIPT_DIR/sync-secrets.sh" "$FULL" || {
    echo "sync-secrets.sh failed for $FULL"
    exit 1
  }
  echo ""
  echo "---"
  echo ""

  # ------------------------------------------------------------
  # [1/4] Templates and Policies
  # ------------------------------------------------------------
  echo "### [1/4] Templates and Policies"
  bash "$SCRIPT_DIR/sync-files.sh" "$FULL" || {
    echo "sync-files.sh failed for $FULL"
    exit 1
  }
  echo ""
  echo "---"
  echo ""

  # ------------------------------------------------------------
  # [2/4] Issue Types
  # ------------------------------------------------------------
  echo "### [2/4] Issue Types"
  bash "$SCRIPT_DIR/sync-issue-types.sh" "$FULL" || {
    echo "sync-issue-types.sh failed for $FULL"
    exit 1
  }
  echo ""
  echo "---"
  echo ""

  # ------------------------------------------------------------
  # [3/4] Labels
  # ------------------------------------------------------------
  echo "### [3/4] Labels"
  bash "$SCRIPT_DIR/sync-labels.sh" "$FULL" || {
    echo "sync-labels.sh failed for $FULL"
    exit 1
  }
  echo ""
  echo "---"
  echo ""

  # ------------------------------------------------------------
  # [4/4] Workflows
  # ------------------------------------------------------------
  echo "### [4/4] Workflows"
  bash "$SCRIPT_DIR/sync-workflows.sh" || {
    echo "sync-workflows.sh failed"
    exit 1
  }
  echo ""
  echo "---"

  echo "Done: $FULL"
  echo ""
done <<< "$repos"

cd "$START_DIR"
echo "All enabled repositories processed successfully."
