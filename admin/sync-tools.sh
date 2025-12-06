#!/usr/bin/env bash

# ============================================================
#  Lost Minions --- Tools Folder Sync
# ------------------------------------------------------------
#  Syncs tool files/folders from the /tools directory in the
#  template repository into an already-cloned target repo.
#
#  Behavior:
#    * If repos.json defines tools[], that list is used.
#    * Otherwise, if manifest.defaults.tools exists, that list is used.
#    * Otherwise, falls back to syncing ALL items under tools/.
#
#    * manifest.deprecated.tools => removed from target
#    * manifest.exclude.tools    => globally skipped
#    * repos[].extra_tools       => added on top of base list
#    * repos[].exclude_tools     => per-repo skip
#
#  Stages changes; sync-core handles the commit.
#
#  Usage:
#    bash sync-tools.sh <owner/repo> <workdir>
# ============================================================

set -euo pipefail

# --- Arguments ---------------------------------------------------------------
if [ $# -lt 2 ]; then
  echo "Usage: bash sync-tools.sh <owner/repo> <workdir>"
  exit 1
fi

FULL_REPO="$1"
WORKDIR="$2"

# Derive short repo name (everything after owner/)
REPO_NAME="${FULL_REPO#*/}"

# Flag: are we syncing a .github repo?
IS_DOT_GITHUB_REPO=0
if [[ "$REPO_NAME" == ".github" ]]; then
  IS_DOT_GITHUB_REPO=1
fi

# --- Paths -------------------------------------------------------------------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
. "$SCRIPT_DIR/sync-common.sh"

SRC_DIR="$ROOT_DIR/tools"
DEST_DIR="$WORKDIR/tools"
MANIFEST_FILE="$SCRIPT_DIR/manifest.json"
REPOS_FILE="$SCRIPT_DIR/repos.json"

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

# --- Load repo config (tools / extra_tools / exclude_tools) ------------------
REPO_TOOLS=()
REPO_EXTRA_TOOLS=()
REPO_EXCLUDE_TOOLS=()

if [ -f "$REPOS_FILE" ]; then
  CLEAN_JSON=$(mktemp)
  clean_json_file "$REPOS_FILE" "$CLEAN_JSON"

  REPO_CONFIG=$(jq -c --arg full "$FULL_REPO" \
    '.repos[] | select((.owner + "/" + .name) == $full)' "$CLEAN_JSON" || true)

  rm -f "$CLEAN_JSON"

  if [ -n "${REPO_CONFIG:-}" ]; then
    if jq -e '.tools' <<<"$REPO_CONFIG" >/dev/null 2>&1; then
      mapfile -t REPO_TOOLS < <(echo "$REPO_CONFIG" | jq -r '.tools[]?' 2>/dev/null || true)
    fi

    if jq -e '.extra_tools' <<<"$REPO_CONFIG" >/dev/null 2>&1; then
      mapfile -t REPO_EXTRA_TOOLS < <(echo "$REPO_CONFIG" | jq -r '.extra_tools[]?' 2>/dev/null || true)
    fi

    if jq -e '.exclude_tools' <<<"$REPO_CONFIG" >/dev/null 2>&1; then
      mapfile -t REPO_EXCLUDE_TOOLS < <(echo "$REPO_CONFIG" | jq -r '.exclude_tools[]?' 2>/dev/null || true)
    fi
  fi
fi

# --- Load defaults / deprecated / global excludes from manifest --------------

DEFAULT_TOOLS=()
DEPRECATED_TOOLS=()
GLOBAL_EXCLUDE_TOOLS=()

if [ -f "$MANIFEST_FILE" ]; then
  CLEAN_MANIFEST=$(mktemp)
  clean_json_file "$MANIFEST_FILE" "$CLEAN_MANIFEST"

  # defaults.tools (relative to tools/)
  if jq -e '.defaults.tools' "$CLEAN_MANIFEST" >/dev/null 2>&1; then
    mapfile -t DEFAULT_TOOLS < <(jq -r '.defaults.tools[]?' "$CLEAN_MANIFEST")
  fi

  # deprecated.tools (relative to tools/)
  if jq -e '.deprecated.tools' "$CLEAN_MANIFEST" >/dev/null 2>&1; then
    mapfile -t DEPRECATED_TOOLS < <(jq -r '.deprecated.tools[]?' "$CLEAN_MANIFEST")
  fi

  # exclude.tools (relative to tools/, acts as prefix match)
  if jq -e '.exclude.tools' "$CLEAN_MANIFEST" >/dev/null 2>&1; then
    mapfile -t GLOBAL_EXCLUDE_TOOLS < <(jq -r '.exclude.tools[]?' "$CLEAN_MANIFEST")
  fi

  rm -f "$CLEAN_MANIFEST"
fi

# Helper: prefix/relative path exclude
is_excluded_tool() {
  local rel="$1"
  shift
  local arr=("$@")
  for p in "${arr[@]}"; do
    # Exact match or prefix match (so "legacy" skips "legacy/..." too)
    if [[ "$rel" == "$p" || "$rel" == "$p/"* ]]; then
      return 0
    fi
  done
  return 1
}

# --- Discover everything in /tools/ (for fallback + validation) --------------

mapfile -t TEMPLATE_TOOLS < <(discover_all "$SRC_DIR")
echo "Detected ${#TEMPLATE_TOOLS[@]} items in template tools/:"
printf -- '- %s\n' "${TEMPLATE_TOOLS[@]}"
echo ""

# --- Build final list of tools to sync ---------------------------------------

TOOLS_TO_SYNC=()

if (( IS_DOT_GITHUB_REPO == 1 )); then
  # Special case: .github repos always mirror the full tools/ tree
  TOOLS_TO_SYNC=("${TEMPLATE_TOOLS[@]}")
else
  if ((${#REPO_TOOLS[@]} > 0)); then
    # Repo explicitly controls which tools it wants
    TOOLS_TO_SYNC=("${REPO_TOOLS[@]}")
  elif ((${#DEFAULT_TOOLS[@]} > 0)); then
    # Fall back to manifest defaults
    TOOLS_TO_SYNC=("${DEFAULT_TOOLS[@]}")
  else
    # Final fallback: all discovered items under /tools
    TOOLS_TO_SYNC=("${TEMPLATE_TOOLS[@]}")
  fi

  # Merge per-repo extras (for non-.github repos)
  TOOLS_TO_SYNC+=("${REPO_EXTRA_TOOLS[@]}")
fi

if ((${#TOOLS_TO_SYNC[@]} == 0)); then
  echo "Warning: No tools resolved for $FULL_REPO; skipping tools sync."
  exit 0
fi

echo "Resolved ${#TOOLS_TO_SYNC[@]} tools to sync for $FULL_REPO:"
printf -- '- %s\n' "${TOOLS_TO_SYNC[@]}"
echo ""

# --- Copy selected tool items (minus excludes) -------------------------------

for rel in "${TOOLS_TO_SYNC[@]}"; do
  # Normalize any accidental CR
  rel="${rel//$'\r'/}"

  # For non-.github repos, apply global + per-repo excludes
  if (( IS_DOT_GITHUB_REPO == 0 )); then
    if is_excluded_tool "$rel" "${GLOBAL_EXCLUDE_TOOLS[@]}"; then
      echo "- Skipping tools/$rel (excluded in manifest)"
      continue
    fi
    if is_excluded_tool "$rel" "${REPO_EXCLUDE_TOOLS[@]}"; then
      echo "- Skipping tools/$rel (excluded for $FULL_REPO)"
      continue
    fi
  fi

  src="$SRC_DIR/$rel"
  dest="$DEST_DIR/$rel"

  if [ ! -e "$src" ]; then
    echo "tools/$rel requested for $FULL_REPO but does not exist in template; skipping."
    continue
  fi

  rm -rf "$dest"
  mkdir -p "$(dirname "$dest")"
  cp -r "$src" "$dest"
  echo "- Synced tool: $rel"
done

# --- Remove deprecated tools -------------------------------------------------

if (( ${#DEPRECATED_TOOLS[@]} )); then
  remove_deprecated "$DEST_DIR" "${DEPRECATED_TOOLS[@]}"
fi

# --- Stage tools folder ------------------------------------------------------

git -C "$WORKDIR" add "tools" >/dev/null 2>&1 || true
echo ""
echo "Tools staged for $FULL_REPO"
