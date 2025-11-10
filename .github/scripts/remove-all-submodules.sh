#!/usr/bin/env bash
# ============================================================
#  Lost Minions --- Remove All Submodules (Full Cleanup)
# ------------------------------------------------------------
#  Cleans all submodules, cached metadata, and folders so the
#  repo can be reinitialized or retested from scratch.
# ============================================================

set -euo pipefail

echo "Removing all submodules..."
echo

# Get a list of all current submodule paths (if any)
submodules=$(git config --file .gitmodules --get-regexp path | awk '{ print $2 }' || true)

if [[ -z "$submodules" ]]; then
  echo "No submodules found."
else
  for path in $submodules; do
    echo " Removing submodule: $path"
    git submodule deinit -f -- "$path" || true
    git rm -f "$path" || true
    rm -rf ".git/modules/$path"
    rm -rf "$path"
  done
fi

# Clean up .gitmodules if it still exists
if [[ -f ".gitmodules" ]]; then
  echo "Cleaning .gitmodules..."
  rm -f .gitmodules
fi

# Stage and commit cleanup
echo
echo "Committing cleanup..."
git add -A || true
git commit -m "Remove all submodules (full cleanup)" || echo "No changes to commit."

echo
echo "All submodules removed and metadata cleaned."
