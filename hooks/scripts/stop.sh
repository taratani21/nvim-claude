#!/bin/bash
set -euo pipefail

# shellcheck source=lib/snapshot.sh
. "$(dirname "$0")/lib/snapshot.sh"

input=$(cat)

context_file="${NVIM_CLAUDE_CONTEXT_FILE:-}"
nvim_server="${NVIM_CLAUDE_SERVER:-}"

if [ -z "$context_file" ] || [ -z "$nvim_server" ]; then
  exit 0
fi

base_dir="$(dirname "$context_file")"
baseline_file="$base_dir/turn-baseline.sha"

# No baseline recorded (not in a git repo, or no turn started)
if [ ! -f "$baseline_file" ]; then
  exit 0
fi

baseline_sha=$(cat "$baseline_file")
if [ -z "$baseline_sha" ]; then
  exit 0
fi

# Snapshot the current working tree (tracked + untracked) so the diff captures
# new files Claude created during this turn.
current_sha=$(build_snapshot_commit "nvim-claude turn current")
if [ -z "$current_sha" ]; then
  exit 0
fi

# Skip if nothing actually changed between baseline and current
if git diff --quiet "$baseline_sha" "$current_sha" 2>/dev/null; then
  exit 0
fi

echo "$current_sha" > "$base_dir/turn-current.sha"

# Open diffview via our Lua module (handles lazy-loading)
nvim --server "$nvim_server" --remote-expr \
  "luaeval(\"require('nvim-claude.diff').open_turn_diff() or 0\")" \
  2>/dev/null || true

exit 0
