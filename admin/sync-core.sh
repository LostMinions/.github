#!/usr/bin/env bash
# ============================================================
#  The Portal Realm --- Unified GitHub Sync Controller
# ------------------------------------------------------------
#  Runs all sync scripts for each enabled repo concurrently,
#  captures logs separately, and merges them in order.
# ============================================================

set -euo pipefail

START_DIR="$(pwd)"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPOS_FILE="$SCRIPT_DIR/repos.json"
LOG_DIR="$SCRIPT_DIR/logs"
mkdir -p "$LOG_DIR"

# --- Verify repos.json --------------------------------------------------------
if [ ! -f "$REPOS_FILE" ]; then
  echo "Missing repos.json"
  exit 1
fi

echo "# The Portal Realm GitHub Sync"
echo ""

# --- Read enabled repos -------------------------------------------------------
strip_comments() {
  perl -0777 -pe '
    s{/\*.*?\*/}{}gs;
    s{//[^\r\n]*}{}g;
    s/,\s*([}\]])/\1/g;
  ' "$1"
}

CLEAN_REPOS=$(mktemp)
strip_comments "$REPOS_FILE" > "$CLEAN_REPOS"

mapfile -t REPOS < <(jq -c '.repos[] | select(.enabled == true)' "$CLEAN_REPOS")

# --- Pre-check for archived repositories --------------------------------------
echo "### Checking for archived repositories..."
echo ""

ARCHIVED_LIST=()
for repo in "${REPOS[@]}"; do
  ORG=$(echo "$repo" | jq -r '.org')
  NAME=$(echo "$repo" | jq -r '.name')
  FULL="$ORG/$NAME"
  IS_ARCHIVED=$(gh repo view "$FULL" --json isArchived -q '.isArchived' 2>/dev/null || echo "false")
  if [[ "$IS_ARCHIVED" == "true" ]]; then
    ARCHIVED_LIST+=("$FULL")
  fi
done

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

# --- Self-label sync (runs immediately) ---------------------------------------
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

# --- Helper: per-repo sync sequence ------------------------------------------
run_sync_for_repo() {
  local repo_json="$1"
  local ORG NAME FULL LOG_PATH
  ORG=$(echo "$repo_json" | jq -r '.org')
  NAME=$(echo "$repo_json" | jq -r '.name')
  FULL="$ORG/$NAME"
  LOG_PATH="$LOG_DIR/${FULL//\//-}.log"

  {
    echo "## Repository: $FULL"
    echo ""

    declare -A steps=(
      ["0"]="sync-secrets.sh|Secrets"
      ["1"]="sync-files.sh|Templates and Policies"
      ["2"]="sync-issue-types.sh|Issue Types"
      ["3"]="sync-labels.sh|Labels"
      ["4"]="sync-workflows.sh|Workflows"
    )

    for i in {0..4}; do
      IFS='|' read -r script title <<< "${steps[$i]}"
      echo "### [$i/4] $title"
      if bash "$SCRIPT_DIR/$script" "$FULL"; then
        echo "  $script succeeded"
      else
        echo "  $script failed for $FULL"
      fi
      echo ""
      echo "---"
      echo ""
    done

    echo "Done: $FULL"
    echo ""
  } > "$LOG_PATH" 2>&1
}

export -f run_sync_for_repo
export SCRIPT_DIR LOG_DIR

echo "### Launching parallel syncs..."
echo ""

MAX_JOBS=4  # parallel limit
running_jobs=0
pids=()

for repo_json in "${REPOS[@]}"; do
  # run in subshell, suppress errors bubbling to main
  (
    run_sync_for_repo "$repo_json" || echo "Sync failed for repo JSON: $repo_json"
  ) &
  pids+=($!)
  ((running_jobs++))

  # throttle parallelism
  if (( running_jobs >= MAX_JOBS )); then
    wait -n || true
    ((running_jobs--))
  fi
done

# Wait for all jobs to finish safely
for pid in "${pids[@]}"; do
  wait "$pid" || true
done

# --- Merge logs in order ------------------------------------------------------
SYNC_LOG="$SCRIPT_DIR/sync-log.md"
{
  echo "# Sync Summary ($(date -u))"
  echo ""
  for repo_json in "${REPOS[@]}"; do
    ORG=$(echo "$repo_json" | jq -r '.org')
    NAME=$(echo "$repo_json" | jq -r '.name')
    FULL="$ORG/$NAME"
    LOG_PATH="$LOG_DIR/${FULL//\//-}.log"

    if [ -f "$LOG_PATH" ]; then
      echo -e "\n## $FULL\n"
      cat "$LOG_PATH"
      echo ""
    else
      echo -e "\n## $FULL\nNo log found.\n"
    fi
  done
} > "$SYNC_LOG"

echo ""
echo "All enabled repositories processed."
echo "Combined log written to: $SYNC_LOG"

cd "$START_DIR"
