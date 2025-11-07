#!/usr/bin/env bash
set -euo pipefail

ORG="${ORG_NAME:-LostMinions}"
GH_TOKEN="${GH_TOKEN:?Missing GH_TOKEN}"

LIMIT=2000      # Default free-tier limit (minutes)
MARGIN_PCT=5    # Stop jobs if within 5% of limit

# --- Parse optional CLI args -----------------------------------------------
while [[ $# -gt 0 ]]; do
  case "$1" in
    --limit)
      LIMIT="$2"; shift 2 ;;
    --margin)
      MARGIN_PCT="$2"; shift 2 ;;
    *)
      echo "Usage: $0 [--limit <minutes>] [--margin <percent>]"
      echo "Example: $0 --limit 3000 --margin 10"
      exit 1 ;;
  esac
done

API="https://api.github.com/organizations/${ORG}/settings/billing/usage/summary"

echo "Checking Actions usage for $ORG..."
USED=$(curl -s -L \
  -H "Accept: application/vnd.github+json" \
  -H "Authorization: Bearer ${GH_TOKEN}" \
  "$API" | jq '[.usageItems[] | select(.sku | test("^actions_(linux|windows|macos)$")) | .grossQuantity] | add // 0')

if [[ -z "$USED" || "$USED" == "null" ]]; then
  echo "Could not determine usage; skipping enforcement."
  exit 0
fi

# --- Compute math using awk -------------------------------------------------
PCT=$(awk -v u="$USED" -v l="$LIMIT" 'BEGIN { if (l<=0) print 0; else printf "%.1f", (u/l)*100 }')
THRESHOLD=$(awk -v l="$LIMIT" -v m="$MARGIN_PCT" 'BEGIN { printf "%.0f", l * (1 - m/100) }')

echo "Usage: ${USED} / ${LIMIT} minutes (${PCT}%)"
echo "Threshold for blocking jobs: ${THRESHOLD} minutes (${MARGIN_PCT}% margin)"

# --- Pure-awk enforcement ---------------------------------------------------
over_limit=$(awk -v u="$USED" -v l="$LIMIT" 'BEGIN {print (u>=l) ? 1 : 0}')
near_limit=$(awk -v u="$USED" -v l="$THRESHOLD" 'BEGIN {print (u>=l) ? 1 : 0}')

if [[ "$over_limit" -eq 1 ]]; then
  echo "Usage exceeds free-tier limit ($USED / $LIMIT) --- canceling job."
  exit 1
elif [[ "$near_limit" -eq 1 ]]; then
  echo "Usage within ${MARGIN_PCT}% of limit ($USED / $LIMIT) --- stopping to avoid overage."
  exit 1
else
  echo "Usage within limit --- continuing workflow."
fi
