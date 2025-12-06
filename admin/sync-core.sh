#!/usr/bin/env bash
# ============================================================
#  Lost Minions --- Unified GitHub Sync Controller
# ------------------------------------------------------------
#  Runs all sync scripts for each enabled repo concurrently,
#  captures logs separately, and merges them in order.
# ============================================================

set -euo pipefail

DEBUG_MODE=false
if [[ "${1:-}" == "--debug" ]]; then
  DEBUG_MODE=true
  shift
  echo "[Debug mode active] --- only the first enabled repo will be processed."
  echo ""
fi

START_DIR="$(pwd)"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPOS_FILE="$SCRIPT_DIR/repos.json"
LOG_DIR="$SCRIPT_DIR/logs"
mkdir -p "$LOG_DIR"

# --- Load shared helpers ------------------------------------------------------
. "$SCRIPT_DIR/sync-common.sh"

# Root of the .github repo this script lives in
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# --- Collect source commits that touched watched paths ------------------------
# This file holds the "root-of-chain" summary that we will embed into
# downstream commits. For a top-level .github, we compute it from its
# own history; for child .github repos, we *reuse* the block from the
# latest sync commit body.
SOURCE_COMMITS_FILE="$(mktemp)"
: > "$SOURCE_COMMITS_FILE"

# Paths/prefixes that match the workflow triggers
WATCH_PREFIXES=(
  ".github/ISSUE_TEMPLATE/"
  ".github/PULL_REQUEST_TEMPLATE/"
  ".github/actions/"
  ".github/scripts/"
  ".github/workflows/"
  "admin/"
  "tools/"
)
WATCH_FILES=(
  ".editorconfig",
  ".github/workflows/github-org-sync.yml"
  "CODE_OF_CONDUCT.md",
  "CodeMaid.config",
  "CONTRIBUTING.md"
  "LICENSE"
  "NOTICE_PRIVATE",
  "SECURITY.md",
)

is_watched_path() {
  local p="$1"
  for f in "${WATCH_FILES[@]}"; do
    [[ "$p" == "$f" ]] && return 0
  done
  for d in "${WATCH_PREFIXES[@]}"; do
    [[ "$p" == "$d"* ]] && return 0
  done
  return 1
}

# We keep this around in case we ever want to filter them,
# but we no longer *use* it when propagating the root summary.
is_sync_commit() {
  local subject="$1"
  [[ "$subject" =~ ^Sync\ [0-9]+[[:space:]]file ]] && return 0
  return 1
}

# Append a single commit as:
# - <subject>
#   <body line 1>
#   <body line 2>
append_commit_summary() {
  local sha="$1"

  local raw
  raw=$(git -C "$REPO_ROOT" show -s --format='%s%n%b' "$sha" 2>/dev/null || echo "")
  [[ -z "$raw" ]] && return 0

  local first=true
  while IFS='' read -r line; do
    if $first; then
      # subject line
      echo "- $line" >> "$SOURCE_COMMITS_FILE"
      first=false
    else
      # indent non-empty body lines
      [[ -z "$line" ]] && continue
      echo "  $line" >> "$SOURCE_COMMITS_FILE"
    fi
  done <<< "$raw"

  echo "" >> "$SOURCE_COMMITS_FILE"
}

collect_watched_commits_in_range() {
  local before="$1"
  local after="$2"

  while read -r sha; do
    local paths touched=false
    paths=$(git -C "$REPO_ROOT" diff-tree --no-commit-id --name-only -r "$sha" || true)

    while read -r path; do
      [[ -z "$path" ]] && continue
      if is_watched_path "$path"; then
        touched=true
        break
      fi
    done <<< "$paths"

    if [[ "$touched" == true ]]; then
      append_commit_summary "$sha"
    fi
  done < <(git -C "$REPO_ROOT" log --format='%H' "$before..$after")
}

# Try to reuse an existing "Source commits from ... (watched paths):"
# block from the latest commit in this .github repo. This is what makes
# the *root* of the chain authoritative: child .github repos read the
# block from their latest sync commit and just pass it downstream.
populate_source_from_last_commit_block() {
  local msg
  msg=$(git -C "$REPO_ROOT" log -1 --pretty=%B 2>/dev/null || echo "")
  [[ -z "$msg" ]] && return 1

  local in_block=false
  local any=false

  while IFS='' read -r line; do
    if ! $in_block; then
      if [[ "$line" == "Source commits from "*"(watched paths):" ]]; then
        in_block=true
      fi
      continue
    fi

    # Once inside the block, keep bullet lines and their indented
    # continuations; stop if we hit something that clearly isn't part
    # of the propagated summary.
    if [[ "$line" == "- "* || "$line" == "  "* || -z "$line" ]]; then
      echo "$line" >> "$SOURCE_COMMITS_FILE"
      any=true
      continue
    else
      # likely a hint / extra paragraph we don't need to duplicate
      break
    fi
  done <<< "$msg"

  [[ "$any" == true && -s "$SOURCE_COMMITS_FILE" ]] || return 1
  return 0
}

# 1) First try: if this .github repo was updated by a parent .github,
#    its latest commit already has the "Source commits from ..." block.
#    In that case, we just reuse it and DO NOT recompute anything.
if populate_source_from_last_commit_block; then
  echo "Reusing upstream source commit summary from latest commit in $REPO_ROOT."
else
  # 2) Otherwise, this repo is the root of the chain for this sync.
  #    Compute the summary from its own commits that touched watched paths.

  if [[ -n "${GITHUB_EVENT_PATH:-}" && -f "$GITHUB_EVENT_PATH" ]]; then
    EVENT_NAME="${GITHUB_EVENT_NAME:-}"
    BEFORE=$(jq -r '.before // ""' "$GITHUB_EVENT_PATH" 2>/dev/null || echo "")
    AFTER=$(jq -r '.after // ""' "$GITHUB_EVENT_PATH" 2>/dev/null || echo "")

    if [[ "$EVENT_NAME" == "push" && -n "$BEFORE" && -n "$AFTER" && "$BEFORE" != "0000000000000000000000000000000000000000" ]]; then
      echo "Source commit range (root-of-chain): $BEFORE..$AFTER"
      collect_watched_commits_in_range "$BEFORE" "$AFTER"
    fi
  fi

  # Fallback for local runs / non-push events / empty ranges:
  # pick the last few commits that touched watched paths.
  if ! [[ -s "$SOURCE_COMMITS_FILE" ]]; then
    echo "No watched commits found in push range; scanning recent history for watched paths..."
    local_count=0
    while read -r sha; do
      local paths touched=false
      paths=$(git -C "$REPO_ROOT" diff-tree --no-commit-id --name-only -r "$sha" || true)

      while read -r path; do
        [[ -z "$path" ]] && continue
        if is_watched_path "$path"; then
          touched=true
          break
        fi
      done <<< "$paths"

      if [[ "$touched" == true ]]; then
        append_commit_summary "$sha"
        ((local_count++))
      fi

      (( local_count >= 3 )) && break
    done < <(git -C "$REPO_ROOT" log --format='%H' -n 50)
  fi
fi

# --- Verify repos.json --------------------------------------------------------
if [ ! -f "$REPOS_FILE" ]; then
  echo "Missing repos.json"
  exit 1
fi

# Determine owner name (local fallback for GH Actions variable)
if [[ -z "${GITHUB_REPOSITORY:-}" ]]; then
  ORG_NAME="LostMinions"   # fallback when run locally
else
  ORG_NAME="${GITHUB_REPOSITORY%%/*}"
fi

echo "============================================================"
echo "$ORG_NAME GitHub Sync Started"
echo "============================================================"
echo ""

# --- Read enabled repos -------------------------------------------------------
CLEAN_REPOS=$(mktemp)
clean_json_file "$REPOS_FILE" "$CLEAN_REPOS"

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
  OWNER=$(echo "$repo" | jq -r '.owner')
  NAME=$(echo "$repo" | jq -r '.name')
  FULL="$OWNER/$NAME"
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
  local OWNER NAME FULL LOG_PATH TMPDIR IS_DOTGITHUB IS_USERREPO OWNER_TYPE

  OWNER=$(echo "$repo_json" | jq -r '.owner')
  NAME=$(echo "$repo_json" | jq -r '.name')
  FULL="$OWNER/$NAME"
  LOG_PATH="$LOG_DIR/${FULL//\//-}.log"
  TMPDIR=$(mktemp -d)

  # Detect if this is a user-owned repo via GitHub API
  OWNER_TYPE=$(gh api "repos/$FULL" --jq '.owner.type' 2>/dev/null || echo "User")
  if [[ "$OWNER_TYPE" == "User" ]]; then
    IS_USERREPO=true
  else
    IS_USERREPO=false
  fi

  # Special handling for org-level .github repos only
  IS_DOTGITHUB=false
  if [[ "$NAME" == ".github" ]]; then
    IS_DOTGITHUB=true
  fi

  {
    echo "------------------------------------------------------------"
    echo "Repository: $FULL"
    echo "------------------------------------------------------------"

    echo "Cloning repository once..."
    if ! gh repo clone "$FULL" "$TMPDIR" -- --depth=1 >/dev/null 2>&1; then
      echo "Failed to clone $FULL"
      exit 1
    fi
    echo ""

    cd "$TMPDIR"

    # ----------------------------------------------------------
    # Step map: different for .github vs normal repos
    # ----------------------------------------------------------
    declare -A steps

    if [[ "$IS_DOTGITHUB" == true ]]; then
      # Org-level .github repos:
      # - no templates / issue-types / labels
      # - add admin sync
      steps=(
        ["0"]="sync-secrets.sh|Secrets"
        ["1"]="sync-community.sh|Community and License Files"
        ["2"]="sync-actions.sh|Actions"
        ["3"]="sync-scripts.sh|Scripts"
        ["4"]="sync-workflows.sh|Workflows"
        ["5"]="sync-tools.sh|Tools"
        ["6"]="sync-editor.sh|Editor"
        ["7"]="sync-admin.sh|Admin"
      )
    elif [[ "$IS_USERREPO" == true ]]; then
      # User-owned repos:
      # - same as .github, but NO admin
      steps=(
        ["0"]="sync-secrets.sh|Secrets"
        ["1"]="sync-community.sh|Community and License Files"
        ["2"]="sync-actions.sh|Actions"
        ["3"]="sync-scripts.sh|Scripts"
        ["4"]="sync-workflows.sh|Workflows"
        ["5"]="sync-tools.sh|Tools"
        ["6"]="sync-editor.sh|Editor"
      )
    else
      # Normal org repos:
      # - full behavior including templates / issue-types / labels
      steps=(
        ["0"]="sync-secrets.sh|Secrets"
        ["1"]="sync-community.sh|Community and License Files"
        ["2"]="sync-templates.sh|Templates"
        ["3"]="sync-issue-types.sh|Issue Types"
        ["4"]="sync-labels.sh|Labels"
        ["5"]="sync-actions.sh|Actions"
        ["6"]="sync-scripts.sh|Scripts"
        ["7"]="sync-workflows.sh|Workflows"
        ["8"]="sync-tools.sh|Tools"
        ["9"]="sync-editor.sh|Editor"
      )
    fi

    # --- Run steps in numeric order --------------------------------------
    for i in $(printf "%s\n" "${!steps[@]}" | sort -n); do
      IFS='|' read -r script title <<< "${steps[$i]}"
      echo "-> Step $((i+1)): $title"
      if bash "$SCRIPT_DIR/$script" "$FULL" "$TMPDIR"; then
        echo ""
        echo "$title complete"
      else
        echo ""
        echo "$title failed"
      fi
      echo ""
    done

    echo "Committing and pushing all updates..."
    if [ -n "$(git status --porcelain)" ]; then
      git add -A
      git reset .DS_Store Thumbs.db 2>/dev/null || true

      # Collect changed paths and filter out internal marker file(s)
      mapfile -t changed_paths < <(git status --porcelain | awk '{print $NF}')
      filtered_paths=()
      for p in "${changed_paths[@]}"; do
        # Don't let our source summary file skew categories or file counts
        [[ "$p" == "admin/.source-commits" ]] && continue
        filtered_paths+=("$p")
      done

      if ((${#filtered_paths[@]} == 0)); then
        echo "Only internal marker files changed; no external sync needed."
        cd "$SCRIPT_DIR"
        rm -rf "$TMPDIR"
        echo ""
        exit 0
      fi

      file_count=${#filtered_paths[@]}
      changed_summary=$(printf '%s ' "${filtered_paths[@]}")

      # Compose an intelligent commit message
      commit_msg="Sync $file_count file"
      [[ "$file_count" -ne 1 ]] && commit_msg+="s"
      commit_msg+=":"

      [[ "$changed_summary" == *".github/actions/"* ]]               && commit_msg+=" actions"
      [[ "$changed_summary" == *"admin/"* ]]                         && commit_msg+=" admin"
      [[ "$changed_summary" == *"CONTRIBUTING.md"* ||
         "$changed_summary" == *"SECURITY.md"*     ||
         "$changed_summary" == *"CODE_OF_CONDUCT.md"* ]]             && commit_msg+=" community"
      [[ "$changed_summary" == *".editorconfig"*    ||
         "$changed_summary" == *"CodeMaid.config"*  ||
         "$changed_summary" == *".DotSettings"* ]]                   && commit_msg+=" editor"
      [[ "$changed_summary" == *".github/scripts/"* ]]               && commit_msg+=" scripts"
      [[ "$changed_summary" == *".github/ISSUE_TEMPLATE/"* ||
         "$changed_summary" == *".github/PULL_REQUEST_TEMPLATE/"* ]] && commit_msg+=" templates"
      [[ "$changed_summary" == *"tools/"* ]]                         && commit_msg+=" tools"
      [[ "$changed_summary" == *".github/workflows/"* ]]             && commit_msg+=" workflows"
      # You can add labels / secrets / issue-types here if you ever map them to concrete paths.

      # Fallback if no category matched (very rare)
      if [[ "$commit_msg" == "Sync $file_count file:" || "$commit_msg" == "Sync $file_count files:" ]]; then
        commit_msg="Sync $file_count file"
        [[ "$file_count" -ne 1 ]] && commit_msg+="s"
        commit_msg+=" (.github assets and metadata)"
      fi

      # commit_msg+=" [skip ci]"

      # Include source commits from origin .github repo, if available
      if [[ -f "${SOURCE_COMMITS_FILE:-}" && -s "$SOURCE_COMMITS_FILE" ]]; then
        echo "Including source commit summary from origin repo (watched paths only):"
        cat "$SOURCE_COMMITS_FILE"

        git commit \
          -m "$commit_msg" \
          -m "Source commits from ${GITHUB_REPOSITORY:-LostMinions/.github} (watched paths):" \
          -m "$(cat "$SOURCE_COMMITS_FILE")" \
          >/dev/null || true
      else
        git commit -m "$commit_msg" >/dev/null || true
      fi

      git push origin HEAD >/dev/null 2>&1 && echo "Pushed updates: $commit_msg" || echo "Push failed"
    else
      echo "No changes to commit"
    fi

    cd "$SCRIPT_DIR"
    rm -rf "$TMPDIR"
    echo ""
  } > "$LOG_PATH" 2>&1
}

export -f run_sync_for_repo
export SCRIPT_DIR LOG_DIR SOURCE_COMMITS_FILE

# --- Launch jobs --------------------------------------------------------------
if [[ "$DEBUG_MODE" == true ]]; then
  echo "Running in debug mode..."
  if ((${#REPOS[@]})); then
    run_sync_for_repo "${REPOS[0]}"
  else
    echo "No enabled repositories found."
    exit 1
  fi
  echo ""
  echo "[Debug complete --- exiting early]"
  exit 0
fi

# Normal parallel mode ---------------------------------------------------------
echo "Launching parallel syncs..."
echo ""
echo "Repos detected: ${#REPOS[@]}"
echo "Max parallel jobs: ${MAX_JOBS:-4}"
printf -- '- %s\n' "${REPOS[@]}"
echo ""

MAX_JOBS=${MAX_JOBS:-4}
running_jobs=0
pids=()
repo_names=()

set +e

for repo_json in "${REPOS[@]}"; do
  OWNER=$(echo "$repo_json" | jq -r '.owner')
  NAME=$(echo "$repo_json" | jq -r '.name')
  FULL="$OWNER/$NAME"
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

# --- Ordered log merge after all jobs finish ----------------------------------
echo ""
echo "Merging logs in launch order..."
for i in "${!repo_names[@]}"; do
  repo=${repo_names[$i]}
  LOG_PATH="$LOG_DIR/${repo//\//-}.log"
  if [ -f "$LOG_PATH" ]; then
    cat "$LOG_PATH"
    echo ""
  fi
done

set -e
exit $exit_status

echo ""
echo "============================================================"
echo "All enabled repositories processed."
echo "============================================================"

cd "$START_DIR"
