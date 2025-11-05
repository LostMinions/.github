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

ORG_NAME="${GITHUB_REPOSITORY%%/*}"
echo "============================================================"
echo "$ORG_NAME GitHub Sync Started"
echo "============================================================"
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

REPOS=()
while IFS= read -r line; do
  [[ -z "$line" ]] && continue  # skip empty lines
  REPOS+=("$line")
done < <(jq -c '.repos[] | select(.enabled == true)' "$CLEAN_REPOS")

# --- Pre-check for archived repositories --------------------------------------
echo "Checking for archived repositories..."
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
  echo "Archived repositories detected (must disable in repos.json):"
  for r in "${ARCHIVED_LIST[@]}"; do
    echo "- $r"
  done
  echo ""
  echo "Please set \"enabled\": false for these in repos.json before running the sync."
  exit 1
else
  echo "No archived repositories detected. Proceeding with sync..."
  echo ""
fi

# --- Self-label sync (runs immediately) ---------------------------------------
if [ -n "${GITHUB_REPOSITORY:-}" ]; then
  echo "Self repository: $GITHUB_REPOSITORY"
  echo "Running label sync..."
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
    echo ""
    echo "------------------------------------------------------------"
    echo "Repository: $FULL"
    echo "------------------------------------------------------------"

    declare -A steps=(
      ["0"]="sync-secrets.sh|Secrets"
      ["1"]="sync-files.sh|Templates and Policies"
      ["2"]="sync-issue-types.sh|Issue Types"
      ["3"]="sync-labels.sh|Labels"
      ["4"]="sync-workflows.sh|Workflows"
    )

    for i in {0..4}; do
      IFS='|' read -r script title <<< "${steps[$i]}"
      echo "Step $((i+1))/5: $title"
      if bash "$SCRIPT_DIR/$script" "$FULL"; then
        echo "  Success: $script"
      else
        echo "  Failed:  $script"
      fi
      echo ""
      echo "---"
      echo ""
    done

    echo "Completed repository: $FULL"
    echo ""
  } > "$LOG_PATH" 2>&1
}

export -f run_sync_for_repo
export SCRIPT_DIR LOG_DIR

echo "Launching parallel syncs..."
echo ""
echo "Repos detected: ${#REPOS[@]}"
echo "Max parallel jobs: ${MAX_JOBS:-4}"
printf '  - %s\n' "${REPOS[@]}"
echo ""

MAX_JOBS=${MAX_JOBS:-4}
running_jobs=0
pids=()
repo_names=()

# --- disable -e so a child failure or wait error won't abort main ---
set +e

for repo_json in "${REPOS[@]}"; do
  ORG=$(echo "$repo_json" | jq -r '.org')
  NAME=$(echo "$repo_json" | jq -r '.name')
  FULL="$ORG/$NAME"
  LOG_PATH="$LOG_DIR/${FULL//\//-}.log"

  echo "Starting sync for $FULL (log: $LOG_PATH)"
  (
    set +e
    run_sync_for_repo "$repo_json"
    exit_code=$?
    echo "- Finished $FULL with exit code $exit_code" >> "$LOG_PATH"
    exit $exit_code
  ) &

  pids+=($!)
  repo_names+=("$FULL")
  ((running_jobs++))

  if (( running_jobs >= MAX_JOBS )); then
    echo "Waiting for available job slot..."
    wait -n || true
    ((running_jobs--))
  fi
done

# --- Wait for remaining jobs to finish ---
echo ""
echo "Waiting for remaining sync jobs to finish..."
exit_status=0
for i in "${!pids[@]}"; do
  pid=${pids[$i]}
  repo=${repo_names[$i]}
  if wait "$pid"; then
    echo "$repo completed successfully"
  else
    echo "$repo failed (see logs/${repo//\//-}.log)"
    exit_status=1
  fi
done

# --- re-enable -e after concurrency block ---
set -e
exit $exit_status

echo ""
echo "============================================================"
echo "All enabled repositories processed."
echo "============================================================"

cd "$START_DIR"
