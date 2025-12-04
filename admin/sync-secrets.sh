#!/usr/bin/env bash
# ============================================================
#  Lost Minions --- Repo Secret Sync
# ------------------------------------------------------------
#  Usage: bash sync-secrets.sh <owner/repo>
#  Pushes selected secrets into the given repository so that
#  every private repo gets the same GH_TOKEN (and others later).
# ============================================================

set -euo pipefail

if [ $# -lt 1 ]; then
  echo "Usage: bash sync-secrets.sh <owner/repo>"
  exit 1
fi

FULL_REPO="$1"
OWNER="${FULL_REPO%%/*}"
REPO="${FULL_REPO##*/}"

# --- secrets to replicate (add more as needed)
SECRETS=("GH_TOKEN")

echo "Syncing secrets for $FULL_REPO"
echo ""

# --- dependency + auth check -----------------------------------------------
for tool in gh jq; do
  if ! command -v "$tool" &>/dev/null; then
    echo "Missing dependency: $tool"
    exit 1
  fi
done

if ! gh auth status &>/dev/null; then
  echo "Not authenticated with gh CLI"
  exit 1
fi

# --- replicate + verify secrets --------------------------------------------
for SECRET_NAME in "${SECRETS[@]}"; do
  VALUE_VAR="${SECRET_NAME}"
  VALUE="${!VALUE_VAR:-}"

  if [[ -z "$VALUE" ]]; then
    echo "- Environment variable $VALUE_VAR not set --- skipping"
    continue
  fi

  echo "- Setting $SECRET_NAME for $FULL_REPO"
  if gh secret set "$SECRET_NAME" --body "$VALUE" --repo "$FULL_REPO" >/dev/null 2>&1; then
    # --- verify by listing it back
    if gh secret list --repo "$FULL_REPO" --json name -q '.[].name' | grep -Fxq "$SECRET_NAME"; then
      echo "- Verified: $SECRET_NAME successfully written"
    else
      echo "! Warning: $SECRET_NAME not visible after write (possible scope issue)"
    fi
  else
    echo "! Failed to set $SECRET_NAME --- permission or API error"
  fi
done

echo ""
echo "Finished syncing secrets for $FULL_REPO"
