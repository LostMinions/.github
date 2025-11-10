#!/usr/bin/env bash
# ============================================================
#  Lost Minions --- Initialize and Pin Library Submodules
# ------------------------------------------------------------
#  Clones each LostMinions library as a submodule and pins it
#  to the most recent tagged release commit.
# ============================================================

set -euo pipefail

declare -A REPOS=(
  ["LostMinions.Core"]="https://github.com/LostMinions/LostMinions.Core.git"
  ["LostMinions.Discord"]="https://github.com/LostMinions/LostMinions.Discord.git"
  ["LostMinions.GoogleSheets"]="https://github.com/LostMinions/LostMinions.GoogleSheets.git"
  ["LostMinions.Logging"]="https://github.com/LostMinions/LostMinions.Logging.git"
)

echo
echo "Initializing and pinning Lost Minions library submodules..."
echo

for name in $(printf '%s\n' "${!REPOS[@]}" | sort); do
  url="${REPOS[$name]}"
  path="libs/$name"

  echo "------------------------------------------------------------"
  echo "Processing $name"
  echo "  URL  : $url"
  echo "  Path : $path"
  echo "------------------------------------------------------------"

  # Clean any old data and make sure parent dir exists
  rm -rf "$path"
  mkdir -p "$(dirname "$path")"

  # Explicitly clone instead of relying on git submodule add to create the dir
  #git clone --depth=1 -b master "$url" "$path" --quiet

  # Register as submodule (this just writes .gitmodules + index entry)
  git submodule add --force --quiet -b master "$url" "$path"

  pushd "$path" >/dev/null

    # Ensure full history and tags are present
    git fetch --unshallow 2>/dev/null || git fetch --all --tags --force --quiet

    # Get most recent tag by creation date
    latest=$(git for-each-ref --sort=-creatordate --format '%(refname:short)' refs/tags | head -n 1)

    if [[ -z "$latest" ]]; then
      echo "No tags found for $name --- leaving on master."
    else
      commit=$(git rev-list -n 1 "tags/$latest")
      git checkout --detach "tags/$latest" --quiet
      head_hash=$(git rev-parse HEAD)
      echo " Latest tag: $latest"
      echo "Tag commit: $commit"
      echo "HEAD now : $head_hash"

      if [[ "$commit" == "$head_hash" ]]; then
        echo "Success --- pinned $name to $latest ($commit)"
      else
        echo "Mismatch! Tag commit and HEAD differ for $name"
      fi
    fi

  popd >/dev/null
  echo
done

# --- Commit submodule state ---------------------------------------------------
echo "Committing pinned submodule states..."
git add .gitmodules libs
git commit -m "Add and pin all library submodules to latest tagged releases" || true

echo
echo "Done. All libraries added and pinned to their latest tags."
