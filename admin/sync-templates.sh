#!/usr/bin/env bash
# ============================================================
#  Lost Minions --- .github Template Sync (single-clone)
# ------------------------------------------------------------
#  Syncs .github template directories (ISSUE_TEMPLATE,
#  PULL_REQUEST_TEMPLATE, etc.) from the template repository
#  into an already-cloned target repo.
#
#  Features:
#    * Reads default template dirs from manifest.json
#    * Removes deprecated template dirs from manifest.json
#    * Cleans stale files inside each managed folder
#    * Falls back to ISSUE_TEMPLATE + PULL_REQUEST_TEMPLATE
#
#  Usage:
#    bash sync-templates.sh <org/repo> <workdir>
# ============================================================

set -euo pipefail

# --- Arguments ---------------------------------------------------------------
if [ $# -lt 2 ]; then
  echo "Usage: bash sync-templates.sh <org/repo> <workdir>"
  exit 1
fi

FULL_REPO="$1"      # e.g. LostMinions/LostMinions.Core
WORKDIR="$2"        # already-cloned repository path

# --- Paths -------------------------------------------------------------------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
MANIFEST_FILE="$SCRIPT_DIR/manifest.json"

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

# --- Load defaults and deprecated templates from manifest --------------------
TEMPLATE_DIRS=()
DEPRECATED_DIRS=()

if [ -f "$MANIFEST_FILE" ]; then
  CLEAN_MANIFEST=$(mktemp)
  clean_json_file "$MANIFEST_FILE" "$CLEAN_MANIFEST"

  # defaults
  if jq -e '.defaults.templates' "$CLEAN_MANIFEST" >/dev/null 2>&1; then
    mapfile -t TEMPLATE_DIRS < <(jq -r '.defaults.templates[]?' "$CLEAN_MANIFEST")
    TEMPLATE_DIRS=("${TEMPLATE_DIRS[@]/#/$ROOT_DIR/.github/}")
  fi

  # deprecations
  if jq -e '.deprecated.templates' "$CLEAN_MANIFEST" >/dev/null 2>&1; then
    mapfile -t DEPRECATED_DIRS < <(jq -r '.deprecated.templates[]?' "$CLEAN_MANIFEST")
  fi

  rm -f "$CLEAN_MANIFEST"
fi

# --- Normalize CRLF from manifest (Windows-safe) -----------------------------
TEMPLATE_DIRS=("${TEMPLATE_DIRS[@]//$'\r'/}")
DEPRECATED_DIRS=("${DEPRECATED_DIRS[@]//$'\r'/}")

# --- Fallback defaults if manifest missing -----------------------------------
if ((${#TEMPLATE_DIRS[@]} == 0)); then
  TEMPLATE_DIRS=(
    "$ROOT_DIR/.github/ISSUE_TEMPLATE"
    "$ROOT_DIR/.github/PULL_REQUEST_TEMPLATE"
  )
fi

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
    cp -r "$d" .github/
    echo "- Synced $(basename "$d")"
  fi
done

# --- Clean stale files inside managed template dirs --------------------------
for src_dir in "${TEMPLATE_DIRS[@]}"; do
  target_dir=".github/$(basename "$src_dir")"
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
