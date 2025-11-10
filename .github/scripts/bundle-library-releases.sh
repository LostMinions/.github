#!/usr/bin/env bash
# ============================================================
#  Lost Minions --- Bundle Existing Library Releases (Clean)
# ------------------------------------------------------------
#  Fetches latest release .nupkg files from each library
#  submodule and collects them into ./artifacts
#
#  Usage:
#    GH_TOKEN=xxxx bash .github/scripts/bundle-library-releases.sh
# ============================================================

set -euo pipefail

echo
echo "Bundling latest release packages from all submodules..."
echo

: "${GH_TOKEN:?GH_TOKEN environment variable must be set.}"
ORG="LostMinions"
OUTPUT_DIR="artifacts"
mkdir -p "$OUTPUT_DIR"

mapfile -t SUBMODULES < <(git config --file .gitmodules --get-regexp path | awk '{ print $2 }' | sort)

if [[ ${#SUBMODULES[@]} -eq 0 ]]; then
  echo "No submodules found in .gitmodules"
  exit 0
fi

for module_path in "${SUBMODULES[@]}"; do
  name=$(basename "$module_path")
  repo="$ORG/$name"

  echo "------------------------------------------------------------"
  echo " $repo"
  echo "------------------------------------------------------------"

  # Get latest release metadata
  release_json=$(curl -s -H "Authorization: Bearer $GH_TOKEN" \
                      -H "Accept: application/vnd.github+json" \
                      "https://api.github.com/repos/$repo/releases/latest")

  if [[ $(echo "$release_json" | jq -r '.message // empty') == "Not Found" ]]; then
    echo "No releases found for $repo"
    continue
  fi

  tag=$(echo "$release_json" | jq -r '.tag_name // empty')
  echo "Latest tag: $tag"

  asset_data=$(echo "$release_json" | jq -c '.assets[]? | select(.name | endswith(".nupkg"))')
  if [[ -z "$asset_data" ]]; then
    echo "No .nupkg assets for $repo@$tag"
    continue
  fi

  echo "Downloading assets..."
  echo

  echo "$asset_data" | while read -r asset; do
    asset_name=$(echo "$asset" | jq -r '.name')
    asset_url=$(echo "$asset" | jq -r '.url')
    outfile="$OUTPUT_DIR/$asset_name"

    printf -- "- * %-45s" "$asset_name"

    curl -sSL --fail \
      -H "Authorization: Bearer $GH_TOKEN" \
      -H "Accept: application/octet-stream" \
      -o "$outfile" \
      "$asset_url" && {
        size=$(du -h "$outfile" | cut -f1)
        printf -- "- (%s)\n" "$size"
      } || {
        printf -- "- (failed)\n"
      }
  done

  echo
done

echo "------------------------------------------------------------"
echo "Final bundled packages:"
ls -lh "$OUTPUT_DIR" | awk 'NR>1 {print "   "$0}'
echo "------------------------------------------------------------"
echo "Done. Packages ready in '$OUTPUT_DIR'"
