#!/usr/bin/env bash
# ============================================================
#  Lost Minions --- Actions Sync (single-clone version)
# ------------------------------------------------------------
#  Auto-discovers and syncs composite actions from the
#  template repository into an existing cloned repo.
#
#  Features:
#    * Auto-discovers .github/actions/*
#    * Reads defaults and deprecated actions from manifest.json
#    * Stages changes; core handles commit
# ============================================================

set -euo pipefail

# --- Arguments ---------------------------------------------------------------
if [ $# -lt 2 ]; then
  echo "Usage: bash sync-actions.sh <org/repo> <workdir>"
  exit 1
fi

FULL_REPO="$1"
WORKDIR="$2"

# --- Paths -------------------------------------------------------------------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
. "$SCRIPT_DIR/sync-common.sh"

SRC_DIR="$ROOT_DIR/.github/actions"
DEST_DIR="$WORKDIR/.github/actions"
MANIFEST_FILE="$SCRIPT_DIR/manifest.json"

mkdir -p "$DEST_DIR"
echo "Syncing actions for $FULL_REPO"
echo ""

# --- Dependency check --------------------------------------------------------
for cmd in jq; do
  if ! command -v "$cmd" >/dev/null 2>&1; then
    echo "Missing dependency: $cmd"
    exit 1
  fi
done

# --- Load defaults + deprecated from manifest --------------------------------
DEFAULT_ACTIONS=()
DEPRECATED_ACTIONS=()

if [ -f "$MANIFEST_FILE" ]; then
  CLEAN_MANIFEST=$(mktemp)
  clean_json_file "$MANIFEST_FILE" "$CLEAN_MANIFEST"

  if jq -e '.defaults.actions' "$CLEAN_MANIFEST" >/dev/null 2>&1; then
    mapfile -t DEFAULT_ACTIONS < <(jq -r '.defaults.actions[]?' "$CLEAN_MANIFEST")
  fi

  if jq -e '.deprecated.actions' "$CLEAN_MANIFEST" >/dev/null 2>&1; then
    mapfile -t DEPRECATED_ACTIONS < <(jq -r '.deprecated.actions[]?' "$CLEAN_MANIFEST")
  fi

  rm -f "$CLEAN_MANIFEST"
fi

# --- Discover all template actions -------------------------------------------
mapfile -t TEMPLATE_ACTIONS < <(discover_dirs "$SRC_DIR")
echo "Detected ${#TEMPLATE_ACTIONS[@]} actions in template:"
printf -- '- %s\n' "${TEMPLATE_ACTIONS[@]}"
echo ""

# --- Copy all template actions ------------------------------------------------
for act in "${TEMPLATE_ACTIONS[@]}"; do
  rm -rf "$DEST_DIR/$act"
  cp -r "$SRC_DIR/$act" "$DEST_DIR/"
  echo "- Synced action $act"
done

# --- Remove deprecated actions ------------------------------------------------
if ((${#DEPRECATED_ACTIONS[@]})); then
  remove_deprecated "$DEST_DIR" "${DEPRECATED_ACTIONS[@]}"
fi

# --- Stage changes; commit handled by sync-core -------------------------------
git -C "$WORKDIR" add ".github/actions" >/dev/null 2>&1 || true
echo ""
echo "Actions staged for $FULL_REPO"
