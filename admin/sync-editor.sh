#!/usr/bin/env bash

# ============================================================
#  Lost Minions --- Editor / IDE Settings Sync
# ------------------------------------------------------------
#  Syncs root-level editor/IDE config files from the template
#  repository into an already-cloned target repo.
#
#  Features:
#    * Manifest defaults / deprecated / global exclude
#    * Per-repo include/extra/exclude via repos.json
#
#  Usage:
#    bash sync-editor.sh <owner/repo> <workdir>
# ============================================================

set -euo pipefail

# --- Arguments ---------------------------------------------------------------
if [ $# -lt 2 ]; then
  echo "Usage: bash sync-editor.sh <owner/repo> <workdir>"
  exit 1
fi

FULL_REPO="$1"      # e.g. LostMinions/LostMinions.Core
WORKDIR="$2"        # path to already-cloned repo

# --- Paths -------------------------------------------------------------------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
REPOS_FILE="$SCRIPT_DIR/repos.json"
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

# --- Parse repo configuration from repos.json --------------------------------
CLEAN_JSON=$(mktemp)
clean_json_file "$REPOS_FILE" "$CLEAN_JSON"

REPO_CONFIG=$(jq -c --arg full "$FULL_REPO" \
  '.repos[] | select((.owner + "/" + .name) == $full)' "$CLEAN_JSON")

rm -f "$CLEAN_JSON"

if [ -z "$REPO_CONFIG" ]; then
  echo "Repo not found or not enabled in repos.json: $FULL_REPO"
  exit 1
fi

if [ "$(echo "$REPO_CONFIG" | jq -r '.enabled')" != "true" ]; then
  echo "Repo disabled in repos.json: $FULL_REPO"
  exit 0
fi

SYNC_EDITOR=$(echo "$REPO_CONFIG" | jq -r '.sync_editor // "false"')

# Per-repo excludes and extras for editor files
EXCLUDE_EDITOR_FILE=()
if jq -e '.exclude_editor_file' <<<"$REPO_CONFIG" >/dev/null 2>&1; then
  mapfile -t EXCLUDE_EDITOR_FILE < <(echo "$REPO_CONFIG" | jq -r '.exclude_editor_file[]?' 2>/dev/null || true)
fi

EXTRA_EDITOR_FILES=()
if jq -e '.extra_editor_file' <<<"$REPO_CONFIG" >/dev/null 2>&1; then
  mapfile -t EXTRA_EDITOR_FILES < <(echo "$REPO_CONFIG" | jq -r '.extra_editor_file[]?' 2>/dev/null || true)
  EXTRA_EDITOR_FILES=("${EXTRA_EDITOR_FILES[@]/#/$ROOT_DIR/}")
fi

# Explicit per-repo include list (overrides manifest defaults if present)
EXPLICIT_EDITOR_FILES=()
if jq -e '.editor_files' <<<"$REPO_CONFIG" >/dev/null 2>&1; then
  mapfile -t EXPLICIT_EDITOR_FILES < <(echo "$REPO_CONFIG" | jq -r '.editor_files[]?' 2>/dev/null || true)
  EXPLICIT_EDITOR_FILES=("${EXPLICIT_EDITOR_FILES[@]/#/$ROOT_DIR/}")
fi

# --- Load defaults / deprecated / manifest-level excludes --------------------

EDITOR_FILES=()
DEPRECATED_EDITOR_FILES=()
MANIFEST_EXCLUDE_EDITOR=()

if [ -f "$MANIFEST_FILE" ]; then
  CLEAN_MANIFEST=$(mktemp)
  clean_json_file "$MANIFEST_FILE" "$CLEAN_MANIFEST"

  # Load default editor files
  if jq -e '.defaults.editor' "$CLEAN_MANIFEST" >/dev/null 2>&1; then
    mapfile -t EDITOR_FILES < <(jq -r '.defaults.editor[]?' "$CLEAN_MANIFEST")
    EDITOR_FILES=("${EDITOR_FILES[@]/#/$ROOT_DIR/}")
  fi

  # Load deprecated editor files
  if jq -e '.deprecated.editor' "$CLEAN_MANIFEST" >/dev/null 2>&1; then
    mapfile -t DEPRECATED_EDITOR_FILES < <(jq -r '.deprecated.editor[]?' "$CLEAN_MANIFEST")
  fi

  # Load manifest-level excludes (by basename)
  if jq -e '.exclude.editor' "$CLEAN_MANIFEST" >/dev/null 2>&1; then
    mapfile -t MANIFEST_EXCLUDE_EDITOR < <(jq -r '.exclude.editor[]?' "$CLEAN_MANIFEST")
  fi

  rm -f "$CLEAN_MANIFEST"
fi

# --- Build final editor list -------------------------------------------------

if ((${#EXPLICIT_EDITOR_FILES[@]} > 0)); then
  # Repo explicitly controls full list
  EDITOR_FILES=("${EXPLICIT_EDITOR_FILES[@]}")
else
  # No explicit list; only use manifest defaults if repo opted in
  if [[ "$SYNC_EDITOR" != "true" ]]; then
    echo "No editor_files and sync_editor != true for $FULL_REPO; skipping editor sync."
    exit 0
  fi
  # EDITOR_FILES already populated from manifest.defaults.editor (may be empty)
fi

# Merge in any per-repo extra editor files
EDITOR_FILES+=("${EXTRA_EDITOR_FILES[@]}")

if ((${#EDITOR_FILES[@]} == 0)); then
  echo "Warning: No editor files resolved for $FULL_REPO; skipping editor sync."
  exit 0
fi

echo "Syncing editor/IDE settings for $FULL_REPO"
echo ""

# --- Remove deprecated editor files ------------------------------------------
if ((${#DEPRECATED_EDITOR_FILES[@]} > 0)); then
  for f in "${DEPRECATED_EDITOR_FILES[@]}"; do
    TARGET_FILE="$(basename "$f")"
    if [ -f "$TARGET_FILE" ]; then
      echo "- Removing deprecated editor file: $TARGET_FILE"
      rm -f "$TARGET_FILE"
    fi
  done
fi

# Helper: check if a basename is in a list
in_list() {
  local needle="$1"; shift
  for x in "$@"; do
    [[ "$x" == "$needle" ]] && return 0
  done
  return 1
}

# --- Copy editor files (with manifest + per-repo excludes) -------------------
for f in "${EDITOR_FILES[@]}"; do
  if [ -f "$f" ]; then
    base="$(basename "$f")"

    # Skip manifest-level excludes
    if in_list "$base" "${MANIFEST_EXCLUDE_EDITOR[@]}"; then
      echo "- Skipping $base (excluded in manifest)"
      continue
    fi

    # Skip excluded editor files for this repo
    if in_list "$base" "${EXCLUDE_EDITOR_FILE[@]}"; then
      echo "- Skipping $base (excluded for $FULL_REPO)"
      continue
    fi

    cp "$f" ./ || true
    echo "- Copied $base"
  else
    echo "- Warning: configured editor file not found in template: $f"
  fi
done

# --- Stage all managed editor files ------------------------------------------
for f in "${EDITOR_FILES[@]}"; do
  target="$(basename "$f")"
  [ -e "$target" ] && git add "$target" >/dev/null 2>&1
done

echo ""
echo "Editor/IDE settings files staged for $FULL_REPO"
