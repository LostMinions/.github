#!/usr/bin/env bash
# ============================================================
#  Lost Minions --- Label Sync Utility (single repo)
# ------------------------------------------------------------
#  Usage: bash sync-labels.sh <org/repo> [workdir] [--clean]
# ============================================================

set -euo pipefail

if [ $# -lt 1 ]; then
  echo "Usage: bash sync-labels.sh <org/repo> [workdir] [--clean]"
  exit 1
fi

FULL_REPO="$1"
WORKDIR="${2:-}" # ignored; kept for consistent interface
CLEAN_FLAG="${3:-}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LABELS_FILE="$SCRIPT_DIR/labels.json"

# --- Load shared helper functions --------------------------------------------
. "$SCRIPT_DIR/sync-common.sh"

# --- dependency check ---------------------------------------------------------
for tool in gh jq grep; do
  if ! command -v "$tool" &>/dev/null; then
    echo "Missing dependency: $tool"
    exit 1
  fi
done

# --- Clean JSON input ---------------------------------------------------------
if [ ! -f "$LABELS_FILE" ]; then
  echo "Missing file: $LABELS_FILE"
  exit 1
fi

CLEAN_LABELS=$(mktemp)
clean_json_file "$LABELS_FILE" "$CLEAN_LABELS"

# --- verify file --------------------------------------------------------------
[ -f "$CLEAN_LABELS" ] || { echo "Missing file: $CLEAN_LABELS"; exit 1; }

LABEL_COUNT=$(jq '. | length' "$CLEAN_LABELS")
echo "Syncing $LABEL_COUNT labels for $FULL_REPO"
echo ""

# --- ensure repo accessible ----------------------------------------------------
if ! gh repo view "$FULL_REPO" &>/dev/null; then
  echo "Cannot access $FULL_REPO"
  exit 1
fi

# --- preload existing labels --------------------------------------------------
EXISTING_LABELS=$(
  gh label list --repo "$FULL_REPO" --limit 500 --json name -q '.[].name' |
  tr '[:upper:]' '[:lower:]'
)

# --- sync labels --------------------------------------------------------------
jq -c '.[]' "$CLEAN_LABELS" | while read -r label; do
  name=$(echo "$label" | jq -r '.name')
  lower_name=$(echo "$name" | tr '[:upper:]' '[:lower:]')
  color=$(echo "$label" | jq -r '.color')
  desc=$(echo "$label" | jq -r '.description')

  if grep -Fxq "$lower_name" <<< "$EXISTING_LABELS"; then
    echo "- Updating: $name"
    gh label edit "$name" --repo "$FULL_REPO" --color "$color" --description "$desc" >/dev/null
  else
    echo "- Creating: $name"
    gh label create "$name" --repo "$FULL_REPO" --color "$color" --description "$desc" --force >/dev/null
  fi
done

# --- cleanup ------------------------------------------------------------------
EXISTING=$(mktemp)
DEFINED=$(mktemp)

gh label list --repo "$FULL_REPO" --json name -q '.[].name' | tr '[:upper:]' '[:lower:]' > "$EXISTING"
jq -r '.[].name' "$CLEAN_LABELS" | tr '[:upper:]' '[:lower:]' > "$DEFINED"

while IFS= read -r label; do
  if ! grep -Fxq "$label" "$DEFINED"; then
    echo "- Removing: $label"
    gh label delete "$label" --repo "$FULL_REPO" --yes >/dev/null || true
  fi
done < "$EXISTING"

rm -f "$EXISTING" "$DEFINED"

echo ""
echo "Finished syncing labels for $FULL_REPO"
