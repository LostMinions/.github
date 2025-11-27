#!/usr/bin/env bash
# ============================================================
#  Lost Minions --- Tools Folder Sync
# ------------------------------------------------------------
#  Syncs ALL files + folders from the /tools directory in the
#  template repository into an already-cloned target repo.
#
#  Features:
#    * Auto-discovers everything inside /tools
#    * Reads deprecated items from manifest.json
#    * Removes deprecated tool files/folders
#    * Stages changes (sync-core handles commit)
# ============================================================

set -euo pipefail

# --- Arguments ---------------------------------------------------------------
if [ $# -lt 2 ]; then
  echo "Usage: bash sync-tools.sh <owner/repo> <workdir>"
  exit 1
fi

FULL_REPO="$1"
WORKDIR="$2"

# --- Paths -------------------------------------------------------------------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
. "$SCRIPT_DIR/sync-common.sh"

SRC_DIR="$ROOT_DIR/tools"
DEST_DIR="$WORKDIR/tools"
MANIFEST_FILE="$SCRIPT_DIR/manifest.json"

mkdir -p "$DEST_DIR"
echo "Syncing tools for $FULL_REPO"
echo ""

# --- Dependency check --------------------------------------------------------
for cmd in jq; do
  if ! command -v "$cmd" >/dev/null 2>&1; then
    echo "Missing dependency: $cmd"
    exit 1
  fi
done

# --- Load deprecated tools list ----------------------------------------------
DEFAULT_TOOLS=()
DEPRECATED_TOOLS=()

if [ -f "$MANIFEST_FILE" ]; then
  CLEAN_MANIFEST=$(mktemp)
  clean_json_file "$MANIFEST_FILE" "$CLEAN_MANIFEST"

  if jq -e '.default.tools' "$CLEAN_MANIFEST" >/dev/null 2>&1; then
    mapfile -t DEFAULT_TOOLS < <(jq -r '.default.tools[]?' "$CLEAN_MANIFEST")
  fi

  if jq -e '.deprecated.tools' "$CLEAN_MANIFEST" >/dev/null 2>&1; then
    mapfile -t DEPRECATED_TOOLS < <(jq -r '.deprecated.tools[]?' "$CLEAN_MANIFEST")
  fi

  rm -f "$CLEAN_MANIFEST"
fi

# --- Discover everything in /tools/ (files + folders) ------------------------
mapfile -t TEMPLATE_TOOLS < <(discover_all "$SRC_DIR")
echo "Detected ${#TEMPLATE_TOOLS[@]} items in template tools/:"
printf -- '- %s\n' "${TEMPLATE_TOOLS[@]}"
echo ""

# --- Copy all template tool items --------------------------------------------
for item in "${TEMPLATE_TOOLS[@]}"; do
  rm -rf "$DEST_DIR/$item"
  cp -r "$SRC_DIR/$item" "$DEST_DIR/"
  echo "- Synced tool: $item"
done

# --- Remove deprecated tools --------------------------------------------------
if ((${#DEPRECATED_TOOLS[@]})); then
  remove_deprecated "$DEST_DIR" "${DEPRECATED_TOOLS[@]}"
fi

# --- Stage tools folder -------------------------------------------------------
git -C "$WORKDIR" add "tools" >/dev/null 2>&1 || true
echo ""
echo "Tools staged for $FULL_REPO"
