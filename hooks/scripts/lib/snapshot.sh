#!/bin/bash
# Build a commit object capturing the full working tree (tracked + untracked,
# respecting .gitignore) without disturbing the user's index. Echoes the SHA
# on success, or nothing if not in a git repo. Args: $1 = commit message.
build_snapshot_commit() {
  local message="$1"
  git rev-parse --is-inside-work-tree > /dev/null 2>&1 || return 0

  local git_dir
  git_dir=$(git rev-parse --git-dir 2>/dev/null) || return 0

  local temp_index
  temp_index=$(mktemp) || return 0

  if [ -f "$git_dir/index" ]; then
    cp "$git_dir/index" "$temp_index"
  else
    # No real index yet (fresh repo); the empty file mktemp left would be
    # read as a corrupt index, so remove it and let git create one.
    rm -f "$temp_index"
  fi

  GIT_INDEX_FILE="$temp_index" git add -A 2>/dev/null

  local tree
  tree=$(GIT_INDEX_FILE="$temp_index" git write-tree 2>/dev/null)
  rm -f "$temp_index"
  [ -z "$tree" ] && return 0

  local head_sha
  head_sha=$(git rev-parse --verify HEAD 2>/dev/null || true)

  if [ -n "$head_sha" ]; then
    git commit-tree "$tree" -p "$head_sha" -m "$message" 2>/dev/null
  else
    git commit-tree "$tree" -m "$message" 2>/dev/null
  fi
}
