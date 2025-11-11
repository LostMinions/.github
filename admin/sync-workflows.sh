#!/usr/bin/env bash
# ============================================================
#  Lost Minions --- Workflow Sync (single-clone version)
# ------------------------------------------------------------
#  Automatically syncs and maintains workflows inside an
#  existing cloned repository, using:
#    * auto-discovery from template .github/workflows
#    * manifest.json for defaults & deprecations
#    * repos.json for per-repo workflow activation
#
#  Usage:
#    bash sync-workflows.sh <org/repo> <workdir>
# ============================================================

set -euo pipefail

# --- Arguments ---------------------------------------------------------------
if [ $# -lt 2 ]; then
  echo "Usage: bash sync-workflows.sh <org/repo> <workdir>"
  exit 1
fi

FULL_REPO="$1"      # e.g. LostMinions/LostMinions.Core
WORKDIR="$2"        # already-cloned repo folder

# --- Paths -------------------------------------------------------------------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
SOURCE_DIR="$ROOT_DIR/.github/workflows"
REPOS_FILE="$SCRIPT_DIR/repos.json"
MANIFEST_FILE="$SCRIPT_DIR/manifest.json"

# --- Load shared helper functions --------------------------------------------
. "$SCRIPT_DIR/sync-common.sh"

cd "$WORKDIR"

# --- Dependency check ---------------------------------------------------------
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
  '.repos[] | select((.org + "/" + .name) == $full)' "$CLEAN_JSON")

if [ -z "$REPO_CONFIG" ]; then
  echo "Repo not found or not enabled in repos.json: $FULL_REPO"
  exit 1
fi

if [ "$(echo "$REPO_CONFIG" | jq -r '.enabled')" != "true" ]; then
  echo "Repo disabled in repos.json: $FULL_REPO"
  exit 0
fi

# --- Read defaults & deprecations from manifest.json --------------------------
DEFAULT_WORKFLOWS=()
DEPRECATED_WORKFLOWS=()
if [ -f "$MANIFEST_FILE" ]; then
  CLEAN_MANIFEST=$(mktemp)
  clean_json_file "$MANIFEST_FILE" "$CLEAN_MANIFEST"

  # Defaults
  DUMMY_PREFIX="Dummy - "
  if jq -e '.defaults.dummy_prefix' "$CLEAN_MANIFEST" >/dev/null 2>&1; then
    DUMMY_PREFIX=$(jq -r '.defaults.dummy_prefix' "$CLEAN_MANIFEST")
  fi

  if jq -e '.defaults.workflows' "$CLEAN_MANIFEST" >/dev/null 2>&1; then
    mapfile -t DEFAULT_WORKFLOWS < <(jq -r '.defaults.workflows[]?' "$CLEAN_MANIFEST")
  fi

  # Deprecations
  if jq -e '.deprecated.workflows' "$CLEAN_MANIFEST" >/dev/null 2>&1; then
    mapfile -t DEPRECATED_WORKFLOWS < <(jq -r '.deprecated.workflows[]?' "$CLEAN_MANIFEST")
  fi

  rm -f "$CLEAN_MANIFEST"
fi

# --- Combine defaults with per-repo workflows --------------------------------
WORKFLOWS=("${DEFAULT_WORKFLOWS[@]}")

EXTRA_WORKFLOWS=$(echo "$REPO_CONFIG" | jq -r '.workflows[]?' 2>/dev/null || true)
if [ -n "$EXTRA_WORKFLOWS" ]; then
  while IFS= read -r wf; do
    [[ -n "$wf" ]] && WORKFLOWS+=("$wf")
  done <<< "$EXTRA_WORKFLOWS"
fi

# --- Handle per-repo workflow exclusions -------------------------------------
EXCLUDE_WORKFLOWS=()
if jq -e '.exclude_workflows' <<<"$REPO_CONFIG" >/dev/null 2>&1; then
  mapfile -t EXCLUDE_WORKFLOWS < <(echo "$REPO_CONFIG" | jq -r '.exclude_workflows[]?' 2>/dev/null || true)
fi

# Deduplicate first
mapfile -t WORKFLOWS < <(printf "%s\n" "${WORKFLOWS[@]}" | awk '!seen[$0]++')

# Remove any excluded workflows
if ((${#EXCLUDE_WORKFLOWS[@]})); then
  for ex in "${EXCLUDE_WORKFLOWS[@]}"; do
    WORKFLOWS=("${WORKFLOWS[@]/$ex}")
  done
fi

echo "Syncing workflows for $FULL_REPO"
mkdir -p .github/workflows

# --- Remove deprecated workflows ---------------------------------------------
if ((${#DEPRECATED_WORKFLOWS[@]})); then
  remove_deprecated ".github/workflows" "${DEPRECATED_WORKFLOWS[@]}"
fi

# --- Discover all template workflows -----------------------------------------
mapfile -t ALL_WORKFLOWS < <(find "$SOURCE_DIR" -maxdepth 1 -type f -name "*.yml" -printf "%f\n" | sort)

echo "Detected ${#ALL_WORKFLOWS[@]} workflows in template:"
printf -- '- %s\n' "${ALL_WORKFLOWS[@]}"
echo ""

# --- Copy or dummy depending on repo config ----------------------------------
for wf in "${ALL_WORKFLOWS[@]}"; do
  SRC="$SOURCE_DIR/$wf"
  DEST=".github/workflows/$wf"
  mkdir -p "$(dirname "$DEST")"

  if printf '%s\n' "${WORKFLOWS[@]}" | grep -qx "$wf"; then
    cp -f "$SRC" "$DEST"
    echo "- Copied $wf"
  else
    echo "- Creating dummy $wf"
    {
      echo "name: ${DUMMY_PREFIX}${wf}"
      echo "on:"
      echo "  workflow_call:"
      echo "jobs:"
      echo "  none:"
      echo "    runs-on: ubuntu-latest"
      echo "    steps:"
      echo "      - run: echo \"Placeholder for $wf - not used by this repo.\""
    } > "$DEST"
  fi
done

# --- Stage changes only (commit handled by sync-core) ------------------------
git add .github/workflows >/dev/null 2>&1 || true
echo ""
echo "Workflows staged for $FULL_REPO"
