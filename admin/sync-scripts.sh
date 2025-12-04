#!/usr/bin/env bash
# ============================================================
#  Lost Minions --- Script Sync
# ------------------------------------------------------------
#  Auto-discovers and syncs .github/scripts/*.sh files from
#  the template repository into an existing cloned repo.
#
#  Features:
#    * Auto-discovers managed scripts
#    * Reads defaults and deprecated entries from manifest.json
#    * Stages results; core commits later
# ============================================================

set -euo pipefail

# --- Arguments ---------------------------------------------------------------
if [ $# -lt 2 ]; then
  echo "Usage: bash sync-scripts.sh <owner/repo> <workdir>"
  exit 1
fi

FULL_REPO="$1"
WORKDIR="$2"

# --- Paths -------------------------------------------------------------------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
. "$SCRIPT_DIR/sync-common.sh"

SRC_DIR="$ROOT_DIR/.github/scripts"
DEST_DIR="$WORKDIR/.github/scripts"
MANIFEST_FILE="$SCRIPT_DIR/manifest.json"

mkdir -p "$DEST_DIR"
echo "Syncing scripts for $FULL_REPO"
echo ""

# --- Dependency check --------------------------------------------------------
for cmd in jq; do
  if ! command -v "$cmd" >/dev/null 2>&1; then
    echo "Missing dependency: $cmd"
    exit 1
  fi
done

# --- Load defaults + deprecated from manifest --------------------------------
DEFAULT_SCRIPTS=()
DEPRECATED_SCRIPTS=()

if [ -f "$MANIFEST_FILE" ]; then
  CLEAN_MANIFEST=$(mktemp)
  clean_json_file "$MANIFEST_FILE" "$CLEAN_MANIFEST"

  if jq -e '.defaults.scripts' "$CLEAN_MANIFEST" >/dev/null 2>&1; then
    mapfile -t DEFAULT_SCRIPTS < <(jq -r '.defaults.scripts[]?' "$CLEAN_MANIFEST")
  fi

  if jq -e '.deprecated.scripts' "$CLEAN_MANIFEST" >/dev/null 2>&1; then
    mapfile -t DEPRECATED_SCRIPTS < <(jq -r '.deprecated.scripts[]?' "$CLEAN_MANIFEST")
  fi

  rm -f "$CLEAN_MANIFEST"
fi

# --- Discover all template scripts -------------------------------------------
mapfile -t TEMPLATE_SCRIPTS < <(discover_files "$SRC_DIR" "*.sh")
echo "Detected ${#TEMPLATE_SCRIPTS[@]} scripts in template:"
printf -- '- %s\n' "${TEMPLATE_SCRIPTS[@]}"
echo ""

# --- Copy all template scripts ------------------------------------------------
for script in "${TEMPLATE_SCRIPTS[@]}"; do
  cp -f "$SRC_DIR/$script" "$DEST_DIR/"
  chmod +x "$DEST_DIR/$script" 2>/dev/null || true
  echo "- Synced script $script"
done

# --- Remove deprecated scripts ------------------------------------------------
if ((${#DEPRECATED_SCRIPTS[@]})); then
  remove_deprecated "$DEST_DIR" "${DEPRECATED_SCRIPTS[@]}"
fi

# --- Stage changes; commit handled by sync-core -------------------------------
git -C "$WORKDIR" add ".github/scripts" >/dev/null 2>&1 || true
echo ""
echo "Scripts staged for $FULL_REPO"
