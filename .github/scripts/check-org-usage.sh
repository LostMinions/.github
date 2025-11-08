#!/usr/bin/env bash
# ------------------------------------------------------------
# LostMinions --- GitHub Org Usage Check
# ------------------------------------------------------------

set -euo pipefail

ORG="${ORG_NAME:-LostMinions}"
TOKEN="${GH_TOKEN:?Missing GH_TOKEN}"

CHECK_ACTIONS=false
CHECK_BANDWIDTH=false

ACTIONS_LIMIT=2000        # minutes
BANDWIDTH_LIMIT=1.0       # GB
MARGIN=5                  # %

API="https://api.github.com/organizations/${ORG}/settings/billing/usage/summary"
FAIL=0

# --- Parse CLI args ---------------------------------------------------------
while [[ $# -gt 0 ]]; do
  case "$1" in
    --org) ORG="$2"; shift 2 ;;
    --token) TOKEN="$2"; shift 2 ;;
    --actions) CHECK_ACTIONS=true; shift ;;
    --packages-bandwidth) CHECK_BANDWIDTH=true; shift ;;
    --actions-limit) ACTIONS_LIMIT="$2"; shift 2 ;;
    --packages-bandwidth-limit) BANDWIDTH_LIMIT="$2"; shift 2 ;;
    --margin) MARGIN="$2"; shift 2 ;;
    *) echo "Usage: $0 [--actions] [--packages-bandwidth]" ; exit 0 ;;
  esac
done

safe_cmp() { # usage: safe_cmp "1 > 0"
  awk "BEGIN {print ($1) ? 1 : 0}" 2>/dev/null || echo 0
}

# --- Function: Check Actions minutes ---------------------------------------
check_actions() {
  local mode_tag
  if $CHECK_ACTIONS; then mode_tag="(enforced)"; else mode_tag="(info-only)"; fi

  echo "Checking Actions usage for $ORG $mode_tag"
  resp=$(curl -s -L -H "Accept: application/vnd.github+json" -H "Authorization: Bearer ${TOKEN}" "$API" || true)
  USED=$(echo "$resp" | jq '[.usageItems[] | select(.sku | test("^actions_(linux|windows|macos)$")) | .grossQuantity] | add // 0')

  if [[ -z "$USED" || "$USED" == "null" ]]; then
    echo "Could not determine Actions usage (missing data)."
    $CHECK_ACTIONS && FAIL=1
    return
  fi

  PCT=$(awk -v u="$USED" -v l="$ACTIONS_LIMIT" 'BEGIN { if (l<=0) print 0; else printf "%.1f", (u/l)*100 }')
  THRESHOLD=$(awk -v l="$ACTIONS_LIMIT" -v m="$MARGIN" 'BEGIN { printf "%.0f", l * (1 - m/100) }')

  echo "* Actions: ${USED} / ${ACTIONS_LIMIT} minutes (${PCT}%)"
  echo "* Threshold for stop: ${THRESHOLD} minutes (${MARGIN}% margin)"

  if [[ "$(safe_cmp "$USED >= $THRESHOLD")" == "1" ]]; then
    echo "Actions usage near or over limit."
    $CHECK_ACTIONS && FAIL=1
  else
    echo "Actions usage OK."
  fi
}

# --- Function: Check Packages bandwidth ------------------------------------
check_packages_bandwidth() {
  local mode_tag
  if $CHECK_BANDWIDTH; then mode_tag="(enforced)"; else mode_tag="(info-only)"; fi

  echo "Checking Packages bandwidth for $ORG $mode_tag"
  resp=$(curl -s -L -H "Accept: application/vnd.github+json" -H "Authorization: Bearer ${TOKEN}" -H "X-GitHub-Api-Version: 2022-11-28" "$API" || true)
  bandwidth_used=$(echo "$resp" | jq -r '.usageItems[] | select(.sku=="packages_bandwidth") | .grossQuantity')
  [[ -z "$bandwidth_used" || "$bandwidth_used" == "null" ]] && bandwidth_used=0

  limit_adj=$(awk "BEGIN {print $BANDWIDTH_LIMIT * (1 - $MARGIN / 100)}")

  printf "* Bandwidth: %.3f GB / Limit: %.2f GB\n" "$bandwidth_used" "$BANDWIDTH_LIMIT"
  printf "* Threshold for stop: %.3f GB (%s%% margin)\n" "$limit_adj" "$MARGIN"

  if [[ "$(safe_cmp "$bandwidth_used > $limit_adj")" == "1" ]]; then
    echo "Packages bandwidth near or over limit."
    $CHECK_BANDWIDTH && FAIL=1
  else
    echo "Packages bandwidth OK."
  fi
}

# --- Always run both checks ------------------------------------------------
check_actions
echo ""
check_packages_bandwidth

# --- Final status ----------------------------------------------------------
if [[ "$FAIL" -eq 1 ]]; then
  echo "One or more usage checks exceeded safe limits."
  echo "result=failure" >> "${GITHUB_OUTPUT:-/dev/null}" || true
else
  echo "All usage within safe limits."
  echo "result=success" >> "${GITHUB_OUTPUT:-/dev/null}" || true
fi

exit 0  # always exit 0
