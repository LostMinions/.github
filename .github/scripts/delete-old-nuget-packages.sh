#!/usr/bin/env bash
# delete-old-nuget-packages.sh
# Keeps only the most recent version of a NuGet package in GitHub Packages.

ORG="LostMinions"
PACKAGE_NAME="LostMinions.Discord"   # <-- your package id
TOKEN="${GH_TOKEN:?GH_TOKEN required}"

echo "Fetching package versions for $ORG/$PACKAGE_NAME ..."
VERSIONS=$(curl -s -H "Authorization: Bearer $TOKEN" \
  -H "Accept: application/vnd.github+json" \
  "https://api.github.com/orgs/$ORG/packages/nuget/$PACKAGE_NAME/versions" |
  jq -r '.[].id')

LATEST=$(echo "$VERSIONS" | head -n 1)
echo "Keeping version id $LATEST, deleting the rest..."

for VID in $(echo "$VERSIONS" | tail -n +2); do
  echo "Deleting version id $VID..."
  curl -X DELETE \
    -H "Authorization: Bearer $TOKEN" \
    -H "Accept: application/vnd.github+json" \
    "https://api.github.com/orgs/$ORG/packages/nuget/$PACKAGE_NAME/versions/$VID"
done

echo "Cleanup complete."
