#!/usr/bin/env bash

# ============================================================
#  Lost Minions --- .github Template Sync
# ------------------------------------------------------------
#  Syncs .github template directories (ISSUE_TEMPLATE,
#  PULL_REQUEST_TEMPLATE, etc.) from the template repository
#  into an already-cloned target repo.
#
#  Current behavior:
#    * Uses manifest.defaults.templates as the canonical list
#      (falls back to ISSUE_TEMPLATE + PULL_REQUEST_TEMPLATE)
#    * Uses manifest.deprecated.templates to remove old dirs
#    * Uses manifest.exclude.templates to skip specific dirs
#    * Cleans stale files inside each managed folder
#
#  Advisory only (read, but NOT applied yet):
#    * repos.json -> templates / extra_templates /
#            exclude_templates / sync_templates
#
#  Usage:
#    bash sync-templates.sh <owner/repo> <workdir>
# ============================================================

set -euo pipefail

# --- Arguments ---------------------------------------------------------------
if [ $# -lt 2 ]; then
  echo "Usage: bash sync-templates.sh <owner/repo> <workdir>"
  exit 1
fi

FULL_REPO="$1"
WORKDIR="$2"

# --- Paths -------------------------------------------------------------------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
MANIFEST_FILE="$SCRIPT_DIR/manifest.json"
REPOS_FILE="$SCRIPT_DIR/repos.json"

# --- Load shared helpers -----------------------------------------------------
. "$SCRIPT_DIR/sync-common.sh"

cd "$WORKDIR"

# --- Dependency check --------------------------------------------------------
for cmd in git jq; do
  if ! command -v "$cmd" >/dev/null 2>&1; then
    echo "Missing dependency: $cmd"
    exit 1
  fi
done

echo "Syncing .github templates for $FULL_REPO"
echo ""

mkdir -p .github

# --- Read repos.json for per-repo template settings (advisory) --------------
if [ -f "$REPOS_FILE" ]; then
  CLEAN_JSON=$(mktemp)
  clean_json_file "$REPOS_FILE" "$CLEAN_JSON"

  REPO_CONFIG=$(jq -c --arg full "$FULL_REPO" \
    '.repos[] | select((.owner + "/" + .name) == $full)' "$CLEAN_JSON" || true)

  rm -f "$CLEAN_JSON"

  if [ -n "${REPO_CONFIG:-}" ]; then
    if jq -e '.templates' <<<"$REPO_CONFIG" >/dev/null 2>&1; then
      echo "! repos.json defines templates[] for $FULL_REPO, but sync-templates.sh currently uses manifest.defaults.templates and ignores per-repo lists."
    fi

    if jq -e '.extra_templates' <<<"$REPO_CONFIG" >/dev/null 2>&1; then
      echo "! repos.json defines extra_templates for $FULL_REPO, but sync-templates.sh currently ignores it."
    fi

    if jq -e '.exclude_templates' <<<"$REPO_CONFIG" >/dev/null 2>&1; then
      echo "! repos.json defines exclude_templates for $FULL_REPO, but sync-templates.sh currently relies only on manifest.exclude.templates."
    fi

    if jq -e '.sync_templates' <<<"$REPO_CONFIG" >/dev/null 2>&1; then
      echo "! repos.json defines sync_templates for $FULL_REPO, but sync-templates.sh currently always syncs templates for repos it is run against."
    fi

    echo ""
  fi
fi

# --- Load defaults / deprecated / excludes from manifest ---------------------

TEMPLATE_DIRS=()
DEPRECATED_DIRS=()
EXCLUDE_TEMPLATES=()

if [ -f "$MANIFEST_FILE" ]; then
  CLEAN_MANIFEST=$(mktemp)
  clean_json_file "$MANIFEST_FILE" "$CLEAN_MANIFEST"

  # defaults
  if jq -e '.defaults.templates' "$CLEAN_MANIFEST" >/dev/null 2>&1; then
    mapfile -t TEMPLATE_DIRS < <(jq -r '.defaults.templates[]?' "$CLEAN_MANIFEST")
    TEMPLATE_DIRS=("${TEMPLATE_DIRS[@]/#/$ROOT_DIR/.github/}")
  fi

  # deprecations (by folder name under .github/)
  if jq -e '.deprecated.templates' "$CLEAN_MANIFEST" >/dev/null 2>&1; then
    mapfile -t DEPRECATED_DIRS < <(jq -r '.deprecated.templates[]?' "$CLEAN_MANIFEST")
  fi

  # excludes (by folder name under .github/)
  if jq -e '.exclude.templates' "$CLEAN_MANIFEST" >/dev/null 2>&1; then
    mapfile -t EXCLUDE_TEMPLATES < <(jq -r '.exclude.templates[]?' "$CLEAN_MANIFEST")
  fi

  rm -f "$CLEAN_MANIFEST"
fi

# --- Normalize CRLF from manifest (Windows-safe) -----------------------------
TEMPLATE_DIRS=("${TEMPLATE_DIRS[@]//$'\r'/}")
DEPRECATED_DIRS=("${DEPRECATED_DIRS[@]//$'\r'/}")
EXCLUDE_TEMPLATES=("${EXCLUDE_TEMPLATES[@]//$'\r'/}")

# --- Fallback defaults if manifest missing -----------------------------------
if ((${#TEMPLATE_DIRS[@]} == 0)); then
  TEMPLATE_DIRS=(
    "$ROOT_DIR/.github/ISSUE_TEMPLATE"
    "$ROOT_DIR/.github/PULL_REQUEST_TEMPLATE"
  )
fi

# Helper: check if a template folder basename is excluded
is_excluded_template() {
  local base="$1"
  for x in "${EXCLUDE_TEMPLATES[@]}"; do
    [[ "$x" == "$base" ]] && return 0
  done
  return 1
}

# --- Remove deprecated template directories ----------------------------------
if ((${#DEPRECATED_DIRS[@]} > 0)); then
  for old in "${DEPRECATED_DIRS[@]}"; do
    TARGET_PATH=".github/$old"
    if [ -d "$TARGET_PATH" ]; then
      echo "- Removing deprecated template folder: $TARGET_PATH"
      rm -rf "$TARGET_PATH"
    fi
  done
fi

# --- Copy template directories into target repo ------------------------------
for d in "${TEMPLATE_DIRS[@]}"; do
  if [ -d "$d" ]; then
    base="$(basename "$d")"

    if is_excluded_template "$base"; then
      echo "- Skipping template folder $base (excluded in manifest)"
      continue
    fi

    cp -r "$d" .github/
    echo "- Synced $base"
  fi
done

# --- Clean stale files inside managed template dirs --------------------------
for src_dir in "${TEMPLATE_DIRS[@]}"; do
  # respect excludes when cleaning too
  base="$(basename "$src_dir")"
  if is_excluded_template "$base"; then
    continue
  fi

  target_dir=".github/$base"
  if [ -d "$target_dir" ]; then
    echo "Checking for stale files in $target_dir ..."
    # normalize CRLF
    src_dir="${src_dir//$'\r'/}"
    target_dir="${target_dir//$'\r'/}"

    SOURCE_FILES=$(cd "$ROOT_DIR" && find "${src_dir#$ROOT_DIR/}" -type f | sort)
    TARGET_FILES=$(find "$target_dir" -type f | sort)
    STALE_FILES=$(comm -23 <(echo "$TARGET_FILES") <(echo "$SOURCE_FILES"))

    if [[ -n "$STALE_FILES" ]]; then
      echo "$STALE_FILES" | while read -r FILE; do
        [[ -z "$FILE" ]] && continue
        echo "- Removing stale file: $FILE"
        rm -f "$FILE"
      done
    fi
  fi
done

# --- Stage template changes (commit handled by sync-core) --------------------
git add .github >/dev/null 2>&1 || true
echo ""
echo "Template directories staged for $FULL_REPO"
