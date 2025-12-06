#!/usr/bin/env bash

# ============================================================
#  Lost Minions --- Actions Sync
# ------------------------------------------------------------
#  Auto-discovers and syncs composite actions from the
#  template repository into an existing cloned repo.
#
#  Current behavior:
#    * Syncs ALL actions from .github/actions
#    * Removes deprecated actions listed in manifest.json
#
#  Advisory only (read, but NOT applied yet):
#    * defaults.actions / exclude.actions in manifest.json
#    * actions / extra_actions / exclude_actions / sync_actions in repos.json
#
#  Usage:
#    bash sync-actions.sh <owner/repo> <workdir>
# ============================================================

set -euo pipefail

# --- Arguments ---------------------------------------------------------------
if [ $# -lt 2 ]; then
    echo "Usage: bash sync-actions.sh <owner/repo> <workdir>"
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
REPOS_FILE="$SCRIPT_DIR/repos.json"

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

# --- Load defaults / deprecated / exclude from manifest (advisory) ----------
DEFAULT_ACTIONS=()
DEPRECATED_ACTIONS=()
MANIFEST_EXCLUDE_ACTIONS=()

if [ -f "$MANIFEST_FILE" ]; then
    CLEAN_MANIFEST=$(mktemp)
    clean_json_file "$MANIFEST_FILE" "$CLEAN_MANIFEST"

    if jq -e '.defaults.actions' "$CLEAN_MANIFEST" >/dev/null 2>&1; then
        mapfile -t DEFAULT_ACTIONS < <(jq -r '.defaults.actions[]?' "$CLEAN_MANIFEST")
    fi

    if jq -e '.deprecated.actions' "$CLEAN_MANIFEST" >/dev/null 2>&1; then
        mapfile -t DEPRECATED_ACTIONS < <(jq -r '.deprecated.actions[]?' "$CLEAN_MANIFEST")
    fi

    if jq -e '.exclude.actions' "$CLEAN_MANIFEST" >/dev/null 2>&1; then
        mapfile -t MANIFEST_EXCLUDE_ACTIONS < <(jq -r '.exclude.actions[]?' "$CLEAN_MANIFEST")
    fi

    rm -f "$CLEAN_MANIFEST"

    # Warnings: these are currently NOT applied by this script
    if ((${#DEFAULT_ACTIONS[@]} > 0)); then
        echo "! manifest.json defines defaults.actions, but sync-actions.sh currently syncs ALL actions and ignores defaults."
    fi

    if ((${#MANIFEST_EXCLUDE_ACTIONS[@]} > 0)); then
        echo "! manifest.json defines exclude.actions, but sync-actions.sh currently ignores manifest-level excludes."
    fi

    echo ""
fi

# --- Read repos.json for per-repo action settings (advisory) -----------------
if [ -f "$REPOS_FILE" ]; then
    CLEAN_JSON=$(mktemp)
    clean_json_file "$REPOS_FILE" "$CLEAN_JSON"

    REPO_CONFIG=$(jq -c --arg full "$FULL_REPO" \
        '.repos[] | select((.owner + "/" + .name) == $full)' "$CLEAN_JSON" || true)

    rm -f "$CLEAN_JSON"

    if [ -n "${REPO_CONFIG:-}" ]; then
        if jq -e '.actions' <<<"$REPO_CONFIG" >/dev/null 2>&1; then
            echo "! repos.json defines actions[] for $FULL_REPO, but sync-actions.sh currently syncs ALL actions and ignores per-repo lists."
        fi

        if jq -e '.extra_actions' <<<"$REPO_CONFIG" >/dev/null 2>&1; then
            echo "! repos.json defines extra_actions for $FULL_REPO, but sync-actions.sh currently ignores them."
        fi

        if jq -e '.exclude_actions' <<<"$REPO_CONFIG" >/dev/null 2>&1; then
            echo "! repos.json defines exclude_actions for $FULL_REPO, but sync-actions.sh currently ignores them."
        fi

        if jq -e '.sync_actions' <<<"$REPO_CONFIG" >/dev/null 2>&1; then
            echo "! repos.json defines sync_actions for $FULL_REPO, but sync-actions.sh currently ignores it (actions are always synced)."
        fi

        echo ""
    fi
fi

# --- Discover all template actions -------------------------------------------
mapfile -t TEMPLATE_ACTIONS < <(discover_dirs "$SRC_DIR")
echo "Detected ${#TEMPLATE_ACTIONS[@]} actions in template:"
printf -- '- %s\n' "${TEMPLATE_ACTIONS[@]}"
echo ""

# --- Copy all template actions -----------------------------------------------
for act in "${TEMPLATE_ACTIONS[@]}"; do
    rm -rf "$DEST_DIR/$act"
    cp -r "$SRC_DIR/$act" "$DEST_DIR/"
    echo "- Synced action $act"
done

# --- Remove deprecated actions -----------------------------------------------
if ((${#DEPRECATED_ACTIONS[@]})); then
    remove_deprecated "$DEST_DIR" "${DEPRECATED_ACTIONS[@]}"
fi

# --- Stage changes; commit handled by sync-core ------------------------------
git -C "$WORKDIR" add ".github/actions" >/dev/null 2>&1 || true

echo ""
echo "Actions staged for $FULL_REPO"
