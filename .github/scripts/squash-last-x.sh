#!/usr/bin/env bash
# ============================================================
#  Lost Minions --- Simple Commit Squasher
# ------------------------------------------------------------
#  Squashes the last N commits into one, keeping only a single
#  message. Designed for cleaning up repeated CI/Sync commits.
#
#  Usage:
#    bash squash-last-x.sh [count] [message]
#  Example:
#    bash squash-last-x.sh 8 "Sync workflows from template repo"
# ============================================================

set -euo pipefail

COUNT="${1:-0}"
MSG="${2:-"Squashed recent commits"}"

if [[ "$COUNT" -lt 2 ]]; then
  echo "Usage: bash $0 <commit_count> [commit_message]"
  echo "Example: bash $0 10 'Sync workflows from template repo'"
  exit 1
fi

echo "Squashing last $COUNT commits into one..."
echo "Message: \"$MSG\""

# Find the commit before the oldest one in the range
BASE=$(git rev-parse "HEAD~${COUNT}")

# Create temporary backup branch in case user wants to undo
BACKUP="backup-before-squash-$(date +%Y%m%d-%H%M%S)"
git branch "$BACKUP" >/dev/null 2>&1
echo "Created safety branch: $BACKUP"

# Perform non-interactive squash
git reset --soft "$BASE"
git commit -m "$MSG"

echo
echo "Squash complete!"
echo "You can inspect the result with:"
echo "  git log --oneline -n 5"
echo
echo "When ready, force-push the changes:"
echo "  git push origin HEAD --force"
echo
