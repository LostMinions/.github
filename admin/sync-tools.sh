#!/usr/bin/env bash
# ============================================================
#  Lost Minions --- Tools Folder Sync (single-clone)
# ------------------------------------------------------------
#  Syncs the /tools folder from the template repository into
#  an already-cloned target repo.
#
#  Features:
#    * Reads optional include/exclude lists from manifest.json
#    * Cleans stale tool files when deprecated/removed
#    * Mirrors internal folder structure
#
#  Usage:
#    bash sync-tools.sh <org/repo> <workdir>
# ============================================================

set -euo pipefail

# --- Arguments ---------------------------------------------------------------
if [ $# -lt 2 ]; then
  echo "Usage: bash sync-tools.sh <org/repo> <workdir>"
  exit 1
fi

FULL_REPO="$1"     # e.g. LostMinions/LostMinions.Core
WORKDIR="$2"       # path to the already-cloned repo

# --- Paths -------------------------------------------------------------------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
REPOS_FILE="$SCRIPT_DIR/repos.json"
MANIFEST_FILE="$SCRIPT_DIR/manifest.json"

SOURCE_TOOLS="$ROOT_DIR/tools"
TARGET_TOOLS="$WORKDIR/tools"

# --- Load shared helpers -----------------------------------------------------
. "$SCRIPT_DIR/sync-common.sh"

cd "$WORKDIR"

# --- Dependency check --------------------------------------------------------
for cmd in git jq rsync; do
  if ! command -v "$cmd" >/dev/null 2>&1; then
    echo "Missing dependency: $cmd"
    exit 1
  fi
done

echo "Syncing tools folder for $FULL_REPO"
echo ""

# --- Load manifest rules -----------------------------------------------------
TOOLS_INCLUDES=()
TOOLS_DEPRECATED=()

if [ -f "$MANIFEST_FILE" ]; then
  CLEAN_MANIFEST=$(mktemp)
  clean_json_file "$MANIFEST_FILE" "$CLEAN_MANIFEST"

  # defaults.tools.include
  if jq -e '.defaults.tools.include' "$CLEAN_MANIFEST" >/dev/null 2>&1; then
    mapfile -t TOOLS_INCLUDES < <(
      jq -r '.defaults.tools.include[]?' "$CLEAN_MANIFEST"
    )
  fi

  # deprecated.tools
  if jq -e '.deprecated.tools' "$CLEAN_MANIFEST" >/dev/null 2>&1; then
    mapfile -t TOOLS_DEPRECATED < <(
      jq -r '.deprecated.tools[]?' "$CLEAN_MANIFEST"
    )
  fi

  rm -f "$CLEAN_MANIFEST"
fi

# --- Default: sync entire /tools if manifest has no include list ------------
USE_MANIFEST_FILTERS=true
if ((${#TOOLS_INCLUDES[@]} == 0)); then
  USE_MANIFEST_FILTERS=false
fi

# --- Ensure target folder exists --------------------------------------------
mkdir -p "$TARGET_TOOLS"

# --- Remove deprecated tool files -------------------------------------------
if ((${#TOOLS_DEPRECATED[@]} > 0)); then
  for f in "${TOOLS_DEPRECATED[@]}"; do
    if [ -f "$TARGET_TOOLS/$f" ]; then
      echo "- Removing deprecated: tools/$f"
      rm -f "$TARGET_TOOLS/$f"
    fi
  done
fi

# --- Sync logic --------------------------------------------------------------
echo "- Copying tools..."

if [[ "$USE_MANIFEST_FILTERS" == false ]]; then
  # Full sync
  rsync -av --delete "$SOURCE_TOOLS/" "$TARGET_TOOLS/" >/dev/null 2>&1
else
  # Selective sync
  for pattern in "${TOOLS_INCLUDES[@]}"; do
    src="$SOURCE_TOOLS/$pattern"
    if compgen -G "$src" > /dev/null; then
      rsync -av "$src" "$TARGET_TOOLS/" >/dev/null 2>&1
      echo "  * Synced pattern: $pattern"
    else
      echo "  * Pattern not found: $pattern"
    fi
  done
fi

# --- Stage synced tools ------------------------------------------------------
if git status --porcelain | grep -q "tools/"; then
  git add tools >/dev/null 2>&1
  echo ""
  echo "Tools folder staged for commit in $FULL_REPO"
else
  echo "No changes detected in tools folder."
fi

