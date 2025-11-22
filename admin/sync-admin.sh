#!/usr/bin/env bash
# ============================================================
#  Lost Minions --- Admin Folder Sync (single-clone)
# ------------------------------------------------------------
#  Syncs ALL files + folders from the /admin directory in the
#  template .github repo into an already-cloned target repo.
#
#  Features:
#    * Auto-discovers everything inside /admin
#    * Always skips:
#        - admin/repos.json
#        - admin/labels.json
#        - admin/issue-types.json
#    * Optional extra excludes via manifest.json (.exclude.admin[])
#    * Optional deprecated items via manifest.json (.deprecated.admin[])
#    * Stages changes (sync-core handles commit)
# ============================================================

set -euo pipefail

# --- Arguments ---------------------------------------------------------------
if [ $# -lt 2 ]; then
  echo "Usage: bash sync-admin.sh <org/repo> <workdir>"
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

mkdir -p "$TARGET_ADMIN"

echo "Syncing admin for $FULL_REPO"
echo "  Template: $TEMPLATE_ADMIN"
echo "  Target:   $TARGET_ADMIN"
echo ""

# --- Dependencies ------------------------------------------------------------
# Only needed if we read manifest.json; safe to require since other scripts do.
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

# --- Read extra excludes / deprecated from manifest.json ---------------------
if [ -f "$MANIFEST_FILE" ]; then
  CLEAN_MANIFEST=$(mktemp)
  clean_json_file "$MANIFEST_FILE" "$CLEAN_MANIFEST"

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

# --- Discover everything in /admin/ -----------------------------------------

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
