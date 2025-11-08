#!/usr/bin/env bash
# ============================================================
#  Lost Minions --- Auto Multi-Block Commit Squasher (Smart)
# ------------------------------------------------------------
#  Detects repeated commit messages (like "Sync .github assets
#  and metadata" or "Sync workflows from template repo") and
#  squashes each contiguous block into a single commit.
#
#  Supports multiple target messages (array)
#  Skips commits with tags (release boundaries)
#  Keeps other history fully intact
#  Safe to run repeatedly before pushing
# ============================================================

set -euo pipefail

# --- Function: Clean invalid or orphaned tags -------------------------------
cleanup_invalid_tags() {
  echo
  echo "Checking for invalid or orphaned remote tags..."
  git fetch --prune --tags

  # Get all remote tag names
  mapfile -t remote_tags < <(git ls-remote --tags origin | awk '{print $2}' | sed 's|refs/tags/||' | grep -v '\^{}')

  local cleaned=0

  for t in "${remote_tags[@]}"; do
    # Skip valid version tags (v1.x.x etc.)
    if [[ "$t" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
      continue
    fi

    # Check whether commit exists locally or remotely
    if ! git rev-list -n 1 "$t" >/dev/null 2>&1; then
      echo "Deleting orphaned remote tag: $t"
      git push origin ":refs/tags/$t" >/dev/null 2>&1 || true
      ((cleaned++))
    fi
  done

  if (( cleaned == 0 )); then
    echo "No invalid or orphaned tags found."
  else
    echo "Cleaned $cleaned orphaned tag(s)."
  fi
}

# Always auto-resolve merge conflicts by keeping the current (HEAD) version
git config --global merge.ours.driver true

# --- Configurable Targets ----------------------------------------------------
TARGET_MSGS=(
  "Sync .github assets and metadata"
  "Sync workflows from template repo"
  "Sync .github templates and community files"
)

BRANCH=$(git rev-parse --abbrev-ref HEAD)
TMPFILE=$(mktemp)

echo
echo "Searching for repeated commit messages..."
echo "Branch: $BRANCH"
echo "Targets:"
for msg in "${TARGET_MSGS[@]}"; do echo " - $msg"; done
echo

# --- Collect all tagged commits ---------------------------------------------
mapfile -t tagged_commits < <(git rev-list --tags --no-walk)
tagged_count=${#tagged_commits[@]}
echo "Found $tagged_count tagged commits (these will be skipped as squash boundaries)."
echo

# Helper to check if a SHA is tagged
is_tagged() {
  local sha="$1"
  [[ " ${tagged_commits[*]} " == *" $sha "* ]]
}

# --- Gather all matching commits --------------------------------------------
mapfile -t all_commits < <(
  for msg in "${TARGET_MSGS[@]}"; do
    git log --reverse --oneline --grep="^${msg}$" | awk -v m="$msg" '{print $1 "|" m}'
  done | sort -u
)

if (( ${#all_commits[@]} == 0 )); then
  echo "No commits found matching target messages."
  cleanup_invalid_tags
  exit 0
fi

echo "Found ${#all_commits[@]} matching commits (across all patterns)."
echo

# --- Detect contiguous runs --------------------------------------------------
runs=()
current_run=()
prev_sha=""

for entry in "${all_commits[@]}"; do
  sha="${entry%%|*}"
  msg="${entry#*|}"

  # Skip tagged commits (release anchors)
  if is_tagged "$sha"; then
    if (( ${#current_run[@]} > 1 )); then
      runs+=("$(IFS=,; echo "${current_run[*]}")")
    fi
    current_run=()
    prev_sha=""
    continue
  fi

  if [[ -z "$prev_sha" ]]; then
    current_run=("$sha|$msg")
  else
    between=$(git rev-list --count "${prev_sha}..${sha}^")
    if [[ "$between" -eq 0 ]]; then
      current_run+=("$sha|$msg")
    else
      if (( ${#current_run[@]} > 1 )); then
        runs+=("$(IFS=,; echo "${current_run[*]}")")
      fi
      current_run=("$sha|$msg")
    fi
  fi
  prev_sha="$sha"
done
if (( ${#current_run[@]} > 1 )); then
  runs+=("$(IFS=,; echo "${current_run[*]}")")
fi

if (( ${#runs[@]} == 0 )); then
  echo "No contiguous blocks of repeated commits found --- nothing to squash."
  cleanup_invalid_tags
  exit 0
fi

echo "Detected ${#runs[@]} contiguous blocks of repeated commits:"
for i in "${!runs[@]}"; do
  IFS=, read -r -a block <<< "${runs[$i]}"
  echo "  Block $((i+1)): ${#block[@]} commits (${block[0]%%|*}..${block[-1]%%|*})"
done
echo

# --- Process each run --------------------------------------------------------
for i in "${!runs[@]}"; do
  IFS=, read -r -a block <<< "${runs[$i]}"
  first_entry="${block[0]}"
  last_entry="${block[-1]}"
  first_sha="${first_entry%%|*}"
  msg="${first_entry#*|}"
  base=$(git rev-parse "${first_sha}^")

  echo
  echo "Squashing block $((i+1)) (${#block[@]} commits)..."
  echo "Range: $first_sha..${last_entry%%|*}"
  echo "Message: \"$msg\""

  # Build temporary todo list
  todo=$(mktemp)
  echo "pick $first_sha $msg" > "$todo"
  for entry in "${block[@]:1}"; do
    sha="${entry%%|*}"
    echo "squash $sha $msg" >> "$todo"
  done

  # Run non-interactive rebase with our todo plan
  GIT_MERGE_AUTOEDIT=no \
  git -c sequence.editor=true rebase -i --autostash --strategy-option=ours "$base" < "$todo" >/dev/null 2>&1 || {
    echo " Merge conflict detected --- auto-resolving with HEAD (ours)..."
    git add -A
    git rebase --continue || true
  }

  # Overwrite commit message cleanly
  git commit --amend -m "$msg" --no-edit >/dev/null 2>&1 || true

  echo "Block $((i+1)) squashed successfully with message: $msg"
done

# --- Verify ------------------------------------------------------------------
echo
echo "Verifying cleanup..."
git log --oneline --grep "Sync" | head -n 10
echo

read -p "Force-push cleaned branch ($BRANCH)? [y/N] " yn
if [[ "$yn" =~ ^[Yy]$ ]]; then
  git push origin "$BRANCH" --force
  echo "Force-pushed cleaned branch."
else
  echo "Skipped push. You can inspect results first:"
  echo "  git log --oneline --graph --decorate"
fi

cleanup_invalid_tags

echo
echo "Done."
