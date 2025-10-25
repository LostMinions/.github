#!/usr/bin/env bash
# ============================================================
#  The Portal Realm --- Org Issue Type Sync Utility (bash)
# ------------------------------------------------------------
#  Creates or updates organization-level issue types via GraphQL API.
#  Requires: gh CLI authenticated with full repo/org scope.
#  Usage: bash sync-issue-types.sh <org/repo>
#  Markdown-safe output (no colors, emojis, or special chars)
# ============================================================

set -euo pipefail

if [ $# -lt 1 ]; then
  echo "Usage: bash sync-issue-types.sh <org/repo>"
  exit 1
fi

FULL_REPO="$1"
ORG="${FULL_REPO%%/*}"   # Extract org before first slash
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TYPES_FILE="$SCRIPT_DIR/issue-types.json"

# --- Dependency check --------------------------------------------------------
for tool in gh jq perl; do
  if ! command -v "$tool" &>/dev/null; then
    echo "Missing dependency: $tool"
    exit 1
  fi
done

# --- strip_comments() --------------------------------------------------------
strip_comments() {
  perl -0777 -pe '
    s{/\*.*?\*/}{}gs;          # remove /* ... */ blocks
    s{//[^\n]*}{}g;            # remove // line comments
    s/,\s*([}\]])/\1/g;        # remove trailing commas
  ' "$1"
}

# --- Prepare cleaned JSON copy ----------------------------------------------
if [ ! -f "$TYPES_FILE" ]; then
  echo "Missing file: $TYPES_FILE"
  exit 1
fi

CLEAN_TYPES=$(mktemp)
strip_comments "$TYPES_FILE" > "$CLEAN_TYPES"

# --- Retrieve organization ID -----------------------------------------------
ORG_ID=$(gh api graphql -f query="
{
  organization(login: \"$ORG\") { id }
}
" --jq '.data.organization.id')

if [[ -z "$ORG_ID" ]]; then
  echo "Could not retrieve organization ID for $ORG"
  exit 1
fi

TYPE_COUNT=$(jq '. | length' "$CLEAN_TYPES")
echo "Syncing $TYPE_COUNT issue types for $FULL_REPO"
echo ""

# --- Fetch existing types ----------------------------------------------------
EXISTING_JSON=$(gh api graphql -f query="
{
  organization(login: \"$ORG\") {
    issueTypes(first: 100) {
      nodes { id name color description }
    }
  }
}
" --jq '.data.organization.issueTypes.nodes')

# --- Iterate through new definitions ----------------------------------------
jq -c '.[]' "$CLEAN_TYPES" | while read -r t; do
  NAME=$(echo "$t" | jq -r '.name')
  COLOR_HEX=$(echo "$t" | jq -r '.color')
  DESC=$(echo "$t" | jq -r '.description')

  # Convert hex color to GitHub enum
  case "$COLOR_HEX" in
    000000|1B1F23) COLOR="BLACK" ;;
    0366D6|1F6FEB) COLOR="BLUE" ;;
    2E8B57|22863A|0E8A16) COLOR="GREEN" ;;
    D73A4A|CB2431) COLOR="RED" ;;
    EAC54F|FBCA04) COLOR="YELLOW" ;;
    9370DB|6F42C1) COLOR="PURPLE" ;;
    708090|586069) COLOR="GRAY" ;;
    FFA500|D18616) COLOR="ORANGE" ;;
    *) COLOR="GRAY" ;;
  esac

  EXISTING_ID=$(echo "$EXISTING_JSON" | jq -r --arg NAME "$NAME" '.[] | select(.name==$NAME) | .id')

  if [[ -n "$EXISTING_ID" && "$EXISTING_ID" != "null" ]]; then
    echo "- Updating: $NAME ($COLOR)"
    gh api graphql -f query="
    mutation {
      updateIssueType(input: {
        issueTypeId: \"$EXISTING_ID\",
        color: $COLOR,
        description: \"$DESC\"
      }) {
        issueType { id name color description }
      }
    }" >/dev/null
  else
    echo "- Creating: $NAME ($COLOR)"
    gh api graphql -f query="
    mutation {
      createIssueType(input: {
        ownerId: \"$ORG_ID\",
        name: \"$NAME\",
        description: \"$DESC\",
        color: $COLOR,
        isEnabled: true
      }) {
        issueType { id name color description isEnabled }
      }
    }" >/dev/null
  fi
done

# --- Cleanup: remove stale issue types --------------------------------------
#echo "Checking for stale issue types to remove..."

# Build list of valid names from source
VALID_NAMES=$(jq -r '.[].name' "$CLEAN_TYPES" | tr -d '\r' | sort)

# Extract all existing type names from org
EXISTING_NAMES=$(echo "$EXISTING_JSON" | jq -r '.[].name' | tr -d '\r' | sort)

# Find names that exist in org but not in source
STALE_NAMES=$(comm -23 <(echo "$EXISTING_NAMES") <(echo "$VALID_NAMES"))

if [[ -z "$STALE_NAMES" ]]; then
  : # no stale issue types
  #echo "- No stale issue types to remove."
else
  echo "$STALE_NAMES" | while read -r STALE; do
    [[ -z "$STALE" ]] && continue
    STALE_ID=$(echo "$EXISTING_JSON" | jq -r --arg STALE "$STALE" '.[] | select(.name==$STALE) | .id')
    if [[ -n "$STALE_ID" && "$STALE_ID" != "null" ]]; then
      echo "- Removing: $STALE"
     gh api graphql -f query="
     mutation {
       deleteIssueType(input: {issueTypeId: \"$STALE_ID\"}) {
         clientMutationId
       }
     }" >/dev/null
    fi
  done
fi

echo ""
echo "Finished syncing issue types for $FULL_REPO"
