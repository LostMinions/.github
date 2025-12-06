#!/usr/bin/env bash

# ============================================================
#  Lost Minions --- Admin Folder Sync
# ------------------------------------------------------------
#  Syncs ALL files + folders from the /admin directory in the
#  template repo into an already-cloned target repo.
#
#  Current behavior:
#    * Auto-discovers everything inside /admin
#    * Always skips:
#      - admin/repos.json
#      - admin/labels.json
#      - admin/issue-types.json
#    * Uses:
#      - manifest.json -> .exclude.admin[] (extra excludes)
#      - manifest.json -> .deprecated.admin[] (items to remove)
#
#  Advisory only (read, but NOT applied yet):
#    * manifest.json -> .defaults.admin[]
#    * repos.json -> admin / extra_admin / exclude_admin / sync_admin
#
#  Stages changes; sync-core handles the commit.
#
#  Usage:
#    bash sync-admin.sh <owner/repo> <workdir>
# ============================================================

set -euo pipefail

# --- Arguments ---------------------------------------------------------------
if [ $# -lt 2 ]; then
  echo "Usage: bash sync-admin.sh <owner/repo> <workdir>"
  exit 1
fi

FULL_REPO="$1"
WORKDIR="$2"

# --- Paths / setup -----------------------------------------------------------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

. "$SCRIPT_DIR/sync-common.sh"

TEMPLATE_ADMIN="$ROOT_DIR/admin"
TARGET_ADMIN="$WORKDIR/admin"
MANIFEST_FILE="$SCRIPT_DIR/manifest.json"
REPOS_FILE="$SCRIPT_DIR/repos.json"

mkdir -p "$TARGET_ADMIN"

echo "Syncing admin for $FULL_REPO"
echo "  Template: $TEMPLATE_ADMIN"
echo "  Target:   $TARGET_ADMIN"
echo ""

# --- Dependencies ------------------------------------------------------------
for cmd in jq; do
  if ! command -v "$cmd" >/dev/null 2>&1; then
    echo "Missing dependency: $cmd"
    exit 1
  fi
done

# --- Base excluded + deprecated lists ----------------------------------------

# Always-excluded admin files (per-org config)
EXCLUDED_ADMIN=(
  "repos.json"
  "labels.json"
  "issue-types.json"
)

DEPRECATED_ADMIN=()

# --- Read manifest.json (defaults/exclude/deprecated) ------------------------
if [ -f "$MANIFEST_FILE" ]; then
  CLEAN_MANIFEST=$(mktemp)
  clean_json_file "$MANIFEST_FILE" "$CLEAN_MANIFEST"

  # Advisory: defaults.admin (NOT used; we auto-discover everything)
  DEFAULT_ADMIN_ITEMS=()
  if jq -e '.defaults.admin' "$CLEAN_MANIFEST" >/dev/null 2>&1; then
    mapfile -t DEFAULT_ADMIN_ITEMS < <(jq -r '.defaults.admin[]?' "$CLEAN_MANIFEST")
    if ((${#DEFAULT_ADMIN_ITEMS[@]} > 0)); then
      echo "! manifest.json defines defaults.admin, but sync-admin.sh currently syncs ALL admin items and ignores defaults."
      echo ""
    fi
  fi

  # Optional: extra excludes (relative to admin/)
  if jq -e '.exclude.admin' "$CLEAN_MANIFEST" >/dev/null 2>&1; then
    while IFS= read -r path; do
      [[ -n "$path" ]] && EXCLUDED_ADMIN+=("$path")
    done < <(jq -r '.exclude.admin[]?' "$CLEAN_MANIFEST")
  fi

  # Optional: deprecated admin items to remove from targets
  if jq -e '.deprecated.admin' "$CLEAN_MANIFEST" >/dev/null 2>&1; then
    mapfile -t DEPRECATED_ADMIN < <(jq -r '.deprecated.admin[]?' "$CLEAN_MANIFEST")
  fi

  rm -f "$CLEAN_MANIFEST"
fi

# --- Read repos.json for per-repo admin settings (advisory) ------------------
if [ -f "$REPOS_FILE" ]; then
  CLEAN_JSON=$(mktemp)
  clean_json_file "$REPOS_FILE" "$CLEAN_JSON"

  REPO_CONFIG=$(jq -c --arg full "$FULL_REPO" \
    '.repos[] | select((.owner + "/" + .name) == $full)' "$CLEAN_JSON" || true)

  rm -f "$CLEAN_JSON"

  if [ -n "${REPO_CONFIG:-}" ]; then
    if jq -e '.admin' <<<"$REPO_CONFIG" >/dev/null 2>&1; then
      echo "! repos.json defines admin[] for $FULL_REPO, but sync-admin.sh currently syncs ALL admin items and ignores per-repo lists."
    fi

    if jq -e '.extra_admin' <<<"$REPO_CONFIG" >/dev/null 2>&1; then
      echo "! repos.json defines extra_admin for $FULL_REPO, but sync-admin.sh currently ignores it."
    fi

    if jq -e '.exclude_admin' <<<"$REPO_CONFIG" >/dev/null 2>&1; then
      echo "! repos.json defines exclude_admin for $FULL_REPO, but sync-admin.sh currently relies only on manifest.exclude.admin + built-in excludes."
    fi

    if jq -e '.sync_admin' <<<"$REPO_CONFIG" >/dev/null 2>&1; then
      echo "! repos.json defines sync_admin for $FULL_REPO, but sync-admin.sh currently always syncs admin/ for enabled repos."
    fi

    echo ""
  fi
fi

is_excluded_admin() {
  local rel="$1"
  for p in "${EXCLUDED_ADMIN[@]}"; do
    # Exact match or prefix match (so "logs" skips "logs/..." too)
    if [[ "$rel" == "$p" || "$rel" == "$p/"* ]]; then
      return 0
    fi
  done
  return 1
}

# --- Discover everything in /admin/ ------------------------------------------

mapfile -t ADMIN_ITEMS < <(discover_all "$TEMPLATE_ADMIN")

echo "Detected ${#ADMIN_ITEMS[@]} items in template admin/:"
printf -- '- %s\n' "${ADMIN_ITEMS[@]}"
echo ""

# --- Copy all template admin items (minus exclusions) ------------------------

for item in "${ADMIN_ITEMS[@]}"; do
  # item is relative to TEMPLATE_ADMIN
  if is_excluded_admin "$item"; then
    echo "- Skipping admin/$item (excluded)"
    continue
  fi

  src="$TEMPLATE_ADMIN/$item"
  dest="$TARGET_ADMIN/$item"

  rm -rf "$dest"
  mkdir -p "$(dirname "$dest")"
  cp -r "$src" "$dest"
  echo "- Synced admin: $item"
done

# --- Remove deprecated admin items -------------------------------------------

if ((${#DEPRECATED_ADMIN[@]})); then
  remove_deprecated "$TARGET_ADMIN" "${DEPRECATED_ADMIN[@]}"
fi

# --- Stage admin folder ------------------------------------------------------

git -C "$WORKDIR" add "admin" >/dev/null 2>&1 || true

echo ""
echo "Admin staged for $FULL_REPO"
