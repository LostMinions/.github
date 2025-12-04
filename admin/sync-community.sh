#!/usr/bin/env bash
# ============================================================
#  Lost Minions --- Community File Sync
# ------------------------------------------------------------
#  Syncs root-level community and license files from the
#  template repository into an already-cloned target repo.
#
#  Features:
#    * Reads default community files from manifest.json
#    * Handles LICENSE vs NOTICE_PRIVATE logic
#    * Cleans stale or swapped-out files
#
#  Usage:
#    bash sync-community.sh <owner/repo> <workdir>
# ============================================================

set -euo pipefail

# --- Arguments ---------------------------------------------------------------
if [ $# -lt 2 ]; then
  echo "Usage: bash sync-community.sh <owner/repo> <workdir>"
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

LICENSE_TYPE=$(echo "$REPO_CONFIG" | jq -r '.license // "private"')
REPO_NAME=$(echo "$REPO_CONFIG" | jq -r '.name')

IS_DOTGITHUB=false
if [[ "$REPO_NAME" == ".github" ]]; then
  IS_DOTGITHUB=true
fi

# --- Load defaults and deprecations from manifest ----------------------------
COMMUNITY_FILES=()
DEPRECATED_FILES=()

if [ -f "$MANIFEST_FILE" ]; then
  CLEAN_MANIFEST=$(mktemp)
  clean_json_file "$MANIFEST_FILE" "$CLEAN_MANIFEST"

  # Load default community files
  if jq -e '.defaults.community' "$CLEAN_MANIFEST" >/dev/null 2>&1; then
    mapfile -t COMMUNITY_FILES < <(jq -r '.defaults.community[]?' "$CLEAN_MANIFEST")
    COMMUNITY_FILES=("${COMMUNITY_FILES[@]/#/$ROOT_DIR/}")
  fi

  # Load deprecated community files
  if jq -e '.deprecated.community' "$CLEAN_MANIFEST" >/dev/null 2>&1; then
    mapfile -t DEPRECATED_FILES < <(jq -r '.deprecated.community[]?' "$CLEAN_MANIFEST")
  fi

  rm -f "$CLEAN_MANIFEST"
fi

EXCLUDE_COMMUNITY_FILE=()
if jq -e '.exclude_community_file' <<<"$REPO_CONFIG" >/dev/null 2>&1; then
  mapfile -t EXCLUDE_COMMUNITY_FILE < <(echo "$REPO_CONFIG" | jq -r '.exclude_community_file[]?' 2>/dev/null || true)
fi

# --- Fallback if no manifest defaults ----------------------------------------
if ((${#COMMUNITY_FILES[@]} == 0)); then
  echo "Warning: No default community files found in manifest; skipping community file sync."
fi

echo "Syncing community and license files for $FULL_REPO"
echo ""

# --- Add license/notice files -------------------------------------------------
if [[ "$IS_DOTGITHUB" == true ]]; then
  # For org-level .github repos, keep both around.
  COMMUNITY_FILES+=("$ROOT_DIR/LICENSE")
  COMMUNITY_FILES+=("$ROOT_DIR/NOTICE_PRIVATE.md")
else
  if [[ "$LICENSE_TYPE" == "mit" ]]; then
    COMMUNITY_FILES+=("$ROOT_DIR/LICENSE")
  else
    COMMUNITY_FILES+=("$ROOT_DIR/NOTICE_PRIVATE.md")
  fi
fi

# --- Remove deprecated community files ---------------------------------------
if ((${#DEPRECATED_FILES[@]} > 0)); then
  for f in "${DEPRECATED_FILES[@]}"; do
    TARGET_FILE="$(basename "$f")"
    if [ -f "$TARGET_FILE" ]; then
      echo "- Removing deprecated file: $TARGET_FILE"
      rm -f "$TARGET_FILE"
    fi
  done
fi

# --- Copy community and license files (with per-repo excludes) ---------------
for f in "${COMMUNITY_FILES[@]}"; do
  if [ -f "$f" ]; then
    base="$(basename "$f")"

    # Skip excluded community files for this repo
    skip=false
    for ex in "${EXCLUDE_COMMUNITY_FILE[@]}"; do
      if [[ "$base" == "$ex" ]]; then
        skip=true
        break
      fi
    done

    if [[ "$skip" == true ]]; then
      echo "- Skipping $base (excluded for $FULL_REPO)"
      continue
    fi

    cp "$f" ./ || true
    echo "- Copied $base"
  fi
done

# --- Prevent dual-license duplication (non-.github only) ----------------------
if [[ "$IS_DOTGITHUB" != true ]]; then
  if [[ "$LICENSE_TYPE" == "mit" ]]; then
    [ -f "NOTICE_PRIVATE.md" ] && rm -f "NOTICE_PRIVATE.md"
  else
    [ -f "LICENSE" ] && rm -f "LICENSE"
  fi
fi

# --- Stage all managed community files ---------------------------------------
for f in "${COMMUNITY_FILES[@]}"; do
  target="$(basename "$f")"
  [ -e "$target" ] && git add "$target" >/dev/null 2>&1
done

echo ""
echo "Community and license files staged for $FULL_REPO"
