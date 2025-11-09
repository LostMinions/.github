#!/usr/bin/env bash
set -euo pipefail

git fetch --tags --quiet || true

echo "Tags in repo:"
git tag --sort=-creatordate || echo "(none)"
echo

# Fetch all tags quietly
git fetch --tags --quiet || true

# Find the latest tag numerically (vX.Y.Z format)
LATEST=$(git tag | grep -E '^v[0-9]+\.[0-9]+\.[0-9]+$' | sort -V | tail -n1 || echo "")

echo "LATEST detected tag: '${LATEST}'"

if [[ -z "$LATEST" ]]; then
  echo "No existing tags found. Starting at v1.0.0"
  VERSION="1.0.0"
else
  BASE=${LATEST#v}
  BASE=${BASE:-$LATEST}
  echo "Normalized base version: '${BASE}'"

  { IFS='.' read -r MAJOR MINOR PATCH <<< "$BASE"; } || true
  MAJOR=${MAJOR:-0}
  MINOR=${MINOR:-0}
  PATCH=${PATCH:-0}

  bump="${INPUT_BUMP:-patch}"
  echo "Bump type: '${bump}'"

  case "$bump" in
    major) MAJOR=$((MAJOR + 1)); MINOR=0; PATCH=0 ;;
    minor) MINOR=$((MINOR + 1)); PATCH=0 ;;
    patch|*) PATCH=$((PATCH + 1)) ;;
  esac

  VERSION="$MAJOR.$MINOR.$PATCH"
fi

echo
echo "Final computed version: $VERSION"
echo "version=$VERSION" >> "$GITHUB_OUTPUT"
