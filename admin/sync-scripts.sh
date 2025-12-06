#!/usr/bin/env bash

# ============================================================
#  Lost Minions --- Script Sync
# ------------------------------------------------------------
#  Auto-discovers and syncs .github/scripts/*.sh files from
#  the template repository into an existing cloned repo.
#
#  Current behavior:
#    * Auto-discovers all managed .sh scripts
#    * Uses manifest.deprecated.scripts to remove old ones
#    * Uses manifest.exclude.scripts to skip specific basenames
#
#  Advisory only (read, but NOT applied yet):
#    * manifest.defaults.scripts[]
#    * repos.json -> scripts / extra_scripts / exclude_scripts / sync_scripts
#
#  Stages results; sync-core commits later.
#
#  Usage:
#    bash sync-scripts.sh <owner/repo> <workdir>
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
REPOS_FILE="$SCRIPT_DIR/repos.json"
MANIFEST_FILE="$SCRIPT_DIR/manifest.json"

. "$SCRIPT_DIR/sync-common.sh"

SRC_DIR="$ROOT_DIR/.github/scripts"
DEST_DIR="$WORKDIR/.github/scripts"

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

# --- Load defaults / deprecated / exclude from manifest ----------------------

DEFAULT_SCRIPTS=()
DEPRECATED_SCRIPTS=()
EXCLUDE_SCRIPTS=()

if [ -f "$MANIFEST_FILE" ]; then
  CLEAN_MANIFEST=$(mktemp)
  clean_json_file "$MANIFEST_FILE" "$CLEAN_MANIFEST"

  # defaults.scripts (advisory; we auto-discover everything)
  if jq -e '.defaults.scripts' "$CLEAN_MANIFEST" >/dev/null 2>&1; then
    mapfile -t DEFAULT_SCRIPTS < <(jq -r '.defaults.scripts[]?' "$CLEAN_MANIFEST")
    if ((${#DEFAULT_SCRIPTS[@]} > 0)); then
      echo "! manifest.json defines defaults.scripts, but sync-scripts.sh currently syncs ALL .sh scripts and ignores defaults."
      echo ""
    fi
  fi

  # deprecated.scripts (actual behavior: delete from target)
  if jq -e '.deprecated.scripts' "$CLEAN_MANIFEST" >/dev/null 2>&1; then
    mapfile -t DEPRECATED_SCRIPTS < <(jq -r '.deprecated.scripts[]?' "$CLEAN_MANIFEST")
  fi

  # exclude.scripts (actual behavior: skip these basenames when copying)
  if jq -e '.exclude.scripts' "$CLEAN_MANIFEST" >/dev/null 2>&1; then
    mapfile -t EXCLUDE_SCRIPTS < <(jq -r '.exclude.scripts[]?' "$CLEAN_MANIFEST")
  fi

  rm -f "$CLEAN_MANIFEST"
fi

# --- Read repos.json for per-repo script settings (advisory) -----------------
if [ -f "$REPOS_FILE" ]; then
  CLEAN_JSON=$(mktemp)
  clean_json_file "$REPOS_FILE" "$CLEAN_JSON"

  REPO_CONFIG=$(jq -c --arg full "$FULL_REPO" \
    '.repos[] | select((.owner + "/" + .name) == $full)' "$CLEAN_JSON" || true)

  rm -f "$CLEAN_JSON"

  if [ -n "${REPO_CONFIG:-}" ]; then
    if jq -e '.scripts' <<<"$REPO_CONFIG" >/dev/null 2>&1; then
      echo "! repos.json defines scripts[] for $FULL_REPO, but sync-scripts.sh currently syncs ALL .sh scripts and ignores per-repo lists."
    fi

    if jq -e '.extra_scripts' <<<"$REPO_CONFIG" >/dev/null 2>&1; then
      echo "! repos.json defines extra_scripts for $FULL_REPO, but sync-scripts.sh currently ignores it."
    fi

    if jq -e '.exclude_scripts' <<<"$REPO_CONFIG" >/dev/null 2>&1; then
      echo "! repos.json defines exclude_scripts for $FULL_REPO, but sync-scripts.sh currently relies only on manifest.exclude.scripts."
    fi

    if jq -e '.sync_scripts' <<<"$REPO_CONFIG" >/dev/null 2>&1; then
      echo "! repos.json defines sync_scripts for $FULL_REPO, but sync-scripts.sh currently always syncs scripts/ for repos it is run against."
    fi

    echo ""
  fi
fi

# Helper: check if a basename is in EXCLUDE_SCRIPTS
is_excluded_script() {
  local base="$1"
  for x in "${EXCLUDE_SCRIPTS[@]}"; do
    [[ "$x" == "$base" ]] && return 0
  done
  return 1
}

# --- Discover all template scripts -------------------------------------------

mapfile -t TEMPLATE_SCRIPTS < <(discover_files "$SRC_DIR" "*.sh")
echo "Detected ${#TEMPLATE_SCRIPTS[@]} scripts in template:"
printf -- '- %s\n' "${TEMPLATE_SCRIPTS[@]}"
echo ""

# --- Copy all template scripts (minus manifest excludes) ---------------------

for script in "${TEMPLATE_SCRIPTS[@]}"; do
  base="$(basename "$script")"

  if is_excluded_script "$base"; then
    echo "- Skipping script $script (excluded in manifest)"
    continue
  fi

  cp -f "$SRC_DIR/$script" "$DEST_DIR/"
  chmod +x "$DEST_DIR/$script" 2>/dev/null || true
  echo "- Synced script $script"
done

# --- Remove deprecated scripts ------------------------------------------------

if ((${#DEPRECATED_SCRIPTS[@]})); then
  remove_deprecated "$DEST_DIR" "${DEPRECATED_SCRIPTS[@]}"
fi

# --- Stage changes; commit handled by sync-core ------------------------------

git -C "$WORKDIR" add ".github/scripts" >/dev/null 2>&1 || true
echo ""
echo "Scripts staged for $FULL_REPO"
