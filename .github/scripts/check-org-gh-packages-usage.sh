#!/usr/bin/env bash
# ------------------------------------------------------------
# LostMinions --- GitHub Packages Bandwidth/Storage Usage Check
# ------------------------------------------------------------
set -e

ORG="${ORG_NAME:?ORG_NAME required}"
TOKEN="${GH_TOKEN:?GH_TOKEN required}"
BANDWIDTH_LIMIT="${BANDWIDTH_LIMIT:-1.5}"  # GB
STORAGE_LIMIT="${STORAGE_LIMIT:-1.8}"      # GB
MARGIN="${MARGIN:-5}"                      # %

API_URL="https://api.github.com/organizations/$ORG/settings/billing/usage/summary"

echo "Checking GitHub Packages usage for org: $ORG"
echo "> $API_URL"

resp=$(curl -s -L \
  -H "Accept: application/vnd.github+json" \
  -H "Authorization: Bearer $TOKEN" \
  -H "X-GitHub-Api-Version: 2022-11-28" \
  "$API_URL")

if ! echo "$resp" | grep -q '"usageItems"'; then
  echo "Unable to retrieve usage data. Response:"
  echo "$resp"
  exit 1
fi

bandwidth_used=$(echo "$resp" | jq -r '.usageItems[] | select(.sku=="packages_bandwidth") | .grossQuantity')
storage_used=$(echo "$resp" | jq -r '.usageItems[] | select(.sku=="packages_storage") | .grossQuantity')

# Apply margin
bw_limit_adj=$(awk "BEGIN {print $BANDWIDTH_LIMIT * (1 - $MARGIN / 100)}")
st_limit_adj=$(awk "BEGIN {print $STORAGE_LIMIT * (1 - $MARGIN / 100)}")

printf "Bandwidth Used: %.3f GB / Limit: %.2f GB\n" "$bandwidth_used" "$BANDWIDTH_LIMIT"
printf "Storage Used: %.3f GB / Limit: %.2f GB\n" "$storage_used" "$STORAGE_LIMIT"

# Compare values
if (( $(echo "$bandwidth_used > $bw_limit_adj" | bc -l) )); then
  echo "Bandwidth near or over limit ($bandwidth_used GB)"
  exit 1
fi

if (( $(echo "$storage_used > $st_limit_adj" | bc -l) )); then
  echo "Storage near or over limit ($storage_used GB)"
  exit 1
fi

echo "GitHub Packages usage OK"
