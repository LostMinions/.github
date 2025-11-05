#!/usr/bin/env bash
# ============================================================
#  The Portal Realm --- .github Template Sync (bash)
# ------------------------------------------------------------
#  Syncs .github templates and community files for one repo.
#  Usage: bash sync-files.sh <org/repo>
#  Markdown-safe output (no colors, emojis, or special chars)
# ============================================================

set -euo pipefail

if [ $# -lt 1 ]; then
  echo "Usage: bash sync-files.sh <org/repo>"
  exit 1
fi

FULL_REPO="$1"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
SOURCE_DIR="$ROOT_DIR"
REPOS_FILE="$SCRIPT_DIR/repos.json"

TMPDIR=$(mktemp -d)
cleanup() {
  cd "$SCRIPT_DIR" || true
  rm -rf "$TMPDIR" || true
}
trap cleanup EXIT

# --- Dependency check --------------------------------------------------------
for cmd in gh git jq; do
  if ! command -v "$cmd" >/dev/null 2>&1; then
    echo "Missing dependency: $cmd"
    exit 1
  fi
done

# --- Verify source folders ---------------------------------------------------
if [ ! -d "$SOURCE_DIR/.github/ISSUE_TEMPLATE" ]; then
  echo "Missing .github/ISSUE_TEMPLATE folder"
  exit 1
fi

echo "Syncing .github templates and policies for $FULL_REPO"
echo ""

# --- Clone repo --------------------------------------------------------------
if ! gh repo clone "$FULL_REPO" "$TMPDIR" -- --depth=1 >/dev/null 2>&1; then
  echo "Failed to clone $FULL_REPO"
  exit 1
fi
cd "$TMPDIR"

# Disable CRLF warnings on Windows
git config core.autocrlf false
git config core.safecrlf false

mkdir -p .github

# --- Copy source files into place -------------------------------------------
# Directories that live under .github
TEMPLATE_DIRS=(
  "$SOURCE_DIR/.github/ISSUE_TEMPLATE"
  "$SOURCE_DIR/.github/PULL_REQUEST_TEMPLATE"
)

# --- Community files that belong in the repo root ----------------------------
ROOT_FILES=(
  "$SOURCE_DIR/CONTRIBUTING.md"
  "$SOURCE_DIR/SECURITY.md"
  "$SOURCE_DIR/CODE_OF_CONDUCT.md"
)

strip_comments() {
  perl -0777 -pe '
    s{/\*.*?\*/}{}gs;
    s{//[^\r\n]*}{}g;
    s/,\s*([}\]])/\1/g;
  ' "$1"
}

CLEAN_JSON=$(mktemp)
strip_comments "$REPOS_FILE" > "$CLEAN_JSON"

# Determine which license to copy (default = private)
LICENSE_TYPE=$(jq -r --arg repo "$FULL_REPO" '
  .repos[] | select((.org + "/" + .name) == $repo) | .license // "private"
' "$CLEAN_JSON")

if [[ "$LICENSE_TYPE" == "mit" ]]; then
  ROOT_FILES+=("$SOURCE_DIR/LICENSE")
else
  ROOT_FILES+=("$SOURCE_DIR/NOTICE_PRIVATE.md")
fi

# Copy template directories into .github
for d in "${TEMPLATE_DIRS[@]}"; do
  if [ -d "$d" ]; then
    cp -r "$d" .github/
  fi
done

# --- Remove stale license file (swap protection) -----------------------------
if [[ "$LICENSE_TYPE" == "mit" ]]; then
  [ -f "NOTICE_PRIVATE.md" ] && rm -f "NOTICE_PRIVATE.md"
else
  [ -f "LICENSE" ] && rm -f "LICENSE"
fi

# --- Copy community files into repo root ------------------------------------
for f in "${ROOT_FILES[@]}"; do
  if [ -f "$f" ]; then
    cp "$f" ./
  fi
done

# --- Cleanup: remove stale files only from managed directories ---------------
#echo "- Checking for stale files in ISSUE_TEMPLATE and PULL_REQUEST_TEMPLATE"

MANAGED_DIRS=(
  ".github/ISSUE_TEMPLATE"
  ".github/PULL_REQUEST_TEMPLATE"
)

for dir in "${MANAGED_DIRS[@]}"; do
  if [ -d "$dir" ]; then
    echo "  Checking $dir ..."
    SRC_PATH="$SOURCE_DIR/$dir"

    # Build relative file lists
    SOURCE_FILES=$(cd "$SOURCE_DIR" && find "$dir" -type f | sort)
    TARGET_FILES=$(find "$dir" -type f | sort)

    # Find files that exist in target but not in source
    STALE_FILES=$(comm -23 <(echo "$TARGET_FILES") <(echo "$SOURCE_FILES"))

    if [[ -z "$STALE_FILES" ]]; then
      : # no stale files
      #echo "  - No stale files in $dir"
    else
      echo "$STALE_FILES" | while read -r FILE; do
        [[ -z "$FILE" ]] && continue
        echo "- Removing stale file: $FILE"
        rm -f "$FILE"
      done
    fi
  fi
done

# --- Commit and push if needed -----------------------------------------------
# Stage both .github and the root-level community files
FILES_TO_COMMIT=(
  ".github"
  "CONTRIBUTING.md"
  "SECURITY.md"
  "CODE_OF_CONDUCT.md"
)

# Add whichever license/notice was used above
if [[ "$LICENSE_TYPE" == "mit" ]]; then
  FILES_TO_COMMIT+=("LICENSE")
else
  FILES_TO_COMMIT+=("NOTICE_PRIVATE.md")
fi

# Filter only those that exist
TO_STAGE=()
for f in "${FILES_TO_COMMIT[@]}"; do
  [ -e "$f" ] && TO_STAGE+=("$f")
done

if [ -n "$(git status --porcelain)" ]; then
  echo "- Committing changes"
  git add "${TO_STAGE[@]}"
  git commit -m "Sync .github templates and community files" >/dev/null || true
  echo "- Pushing changes"
  if git push origin HEAD >/dev/null 2>&1; then
    echo "- Updated $FULL_REPO"
  else
    echo "! Push failed for $FULL_REPO"
  fi
else
  : # no stale files
  #echo "No changes detected in $FULL_REPO"
fi

echo ""
echo "Finished syncing .github templates and policies for $FULL_REPO"
