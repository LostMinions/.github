#!/usr/bin/env bash
# ============================================================
#  Lost Minions --- Update Submodules to Latest Tagged Release
# ------------------------------------------------------------
#  Iterates through all submodules, fetches tags, and checks
#  out the latest version tag for each. Designed for CI or
#  local sync before building the unified package bundle.
#
#  Usage:
#    bash .github/scripts/update-submodules.sh
# ============================================================

set -euo pipefail

echo
echo "Updating submodules to latest tags..."
echo

# Ensure submodules are initialized and up to date
git submodule sync --recursive --quiet
git submodule update --init --recursive --quiet

# Collect submodule paths from .gitmodules (sorted alphabetically)
mapfile -t SUBMODULES < <(git config --file .gitmodules --get-regexp path | awk '{ print $2 }' | sort)

if [[ ${#SUBMODULES[@]} -eq 0 ]]; then
  echo "No submodules found in .gitmodules"
  exit 0
fi

# --- Iterate through all submodules ------------------------------------------
for module_path in "${SUBMODULES[@]}"; do
  echo "------------------------------------------------------------"
  echo "Processing $module_path"
  echo "------------------------------------------------------------"

  if [ ! -e "$module_path/.git" ]; then
    echo "Skipping: $module_path is not a valid Git submodule directory."
    echo
    continue
  fi

  pushd "$module_path" >/dev/null

    # Ensure we have complete history and all tags
    git fetch --unshallow 2>/dev/null || git fetch --all --tags --force --quiet

    # Find the latest tag by creation date
    latest_tag=$(git for-each-ref --sort=-creatordate --format '%(refname:short)' refs/tags | head -n 1)

    if [[ -z "$latest_tag" ]]; then
      echo "No tags found for $module_path --- leaving on current commit."
    else
      commit=$(git rev-list -n 1 "tags/$latest_tag")
      echo "Latest tag: $latest_tag"
      echo "Tag commit: $commit"
      echo "Checking out tag: $latest_tag"
      git checkout --detach "tags/$latest_tag" --quiet
      head_hash=$(git rev-parse HEAD)
      echo "HEAD now : $head_hash"

      if [[ "$commit" == "$head_hash" ]]; then
        echo "Success --- pinned $module_path to $latest_tag ($commit)"
      else
        echo "Mismatch! Tag commit and HEAD differ for $module_path"
      fi
    fi

  popd >/dev/null
  echo
done

# --- Commit submodule pointer updates ----------------------------------------
if ! git diff --quiet --submodule; then
  echo "Committing updated submodule references..."
  git add .gitmodules $(git config --file .gitmodules --get-regexp path | awk '{ print $2 }')
  git commit -m "Update submodules to latest tagged releases" || true
  echo "Submodule references updated and committed."
else
  echo "All submodules already up to date."
fi

echo
echo "Done. Submodules synced to latest tags."
