#!/bin/bash
set -euo pipefail

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

# Check if there are actual changes since the baseline
if git diff --quiet "$baseline_sha" 2>/dev/null; then
  exit 0
fi

# Open diffview via our Lua module (handles lazy-loading)
nvim --server "$nvim_server" --remote-expr \
  "luaeval(\"require('nvim-claude.diff').open_turn_diff() or 0\")" \
  2>/dev/null || true

exit 0
