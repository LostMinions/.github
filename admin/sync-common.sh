#!/usr/bin/env bash
# ============================================================
#  Lost Minions --- Common discovery + cleanup utilities for sync scripts
# ============================================================
set -euo pipefail

# Force UTF-8 locale (prevents emoji loss when cleaning JSON)
export LANG="en_US.UTF-8"
export LC_ALL="en_US.UTF-8"

# --- discover_dirs ------------------------------------------------------------
# Lists top-level subdirectories (sorted)
discover_dirs() {
  local base="$1"
  [ -d "$base" ] || return
  find "$base" -mindepth 1 -maxdepth 1 -type d -printf "%f\n" | sort
}

# --- discover_files -----------------------------------------------------------
# Lists files matching pattern (sorted)
discover_files() {
  local base="$1" pattern="${2:-*}"
  [ -d "$base" ] || return
  find "$base" -type f -name "$pattern" -printf "%f\n" | sort
}

# --- discover_all ------------------------------------------------------------
# Lists all files under base (recursive), as paths relative to base, sorted
discover_all() {
  local base="$1"
  [ -d "$base" ] || return
  find "$base" -type f -printf "%P\n" | sort
}

# --- remove_deprecated --------------------------------------------------------
# Deletes deprecated files or directories by name
remove_deprecated() {
  local folder="$1"; shift
  for name in "$@"; do
    if [ -e "$folder/$name" ]; then
      rm -rf "$folder/$name"
      echo "- Removed deprecated: $folder/$name"
    fi
  done
}

# --- clean_json_file ----------------------------------------------------------
# Removes // comments, /* ... */ blocks, and trailing commas from a JSON file.
# Writes to a destination path if provided, or prints to stdout.
# Usage:
#   clean_json_file source.json dest.json
#   clean_json_file source.json > clean.json
clean_json_file() {
  local src="$1"
  local dest="${2:-}"
  local cleaned
  cleaned=$(perl -CSD -Mutf8 -0777 -pe '
    s{/\*.*?\*/}{}gs;          # remove /* ... */ blocks
    s{//[^\r\n]*}{}g;          # remove // comments
    s/,\s*([}\]])/\1/g;        # remove trailing commas
  ' "$src")

  if [[ -n "$dest" ]]; then
    printf "%s" "$cleaned" > "$dest"
  else
    printf "%s" "$cleaned"
  fi
}
