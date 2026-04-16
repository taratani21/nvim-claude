#!/bin/bash
set -euo pipefail

input=$(cat)

context_file="${NVIM_CLAUDE_CONTEXT_FILE:-}"
nvim_server="${NVIM_CLAUDE_SERVER:-}"

if [ -z "$context_file" ] || [ -z "$nvim_server" ]; then
  exit 0
fi

manifest="$(dirname "$context_file")/manifest.json"
snapshot_dir="$(dirname "$context_file")/snapshots"

# No files changed this turn
if [ ! -f "$manifest" ]; then
  exit 0
fi

# Check that at least one file actually has a diff
has_changes=false
for file_path in $(jq -r '.[]' "$manifest"); do
  safe_name=$(echo "$file_path" | sed 's|/|__|g')
  snapshot="$snapshot_dir/$safe_name"
  if [ -f "$snapshot" ] && ! diff -q "$snapshot" "$file_path" > /dev/null 2>&1; then
    has_changes=true
    break
  fi
done

if [ "$has_changes" = false ]; then
  exit 0
fi

# Tell Neovim to open the diffs via the nvim-claude diff module
nvim --server "$nvim_server" --remote-expr \
  "luaeval(\"require('nvim-claude.diff').open_turn_diffs('$(echo "$manifest" | sed "s/'/\\\\'/g")', '$(echo "$snapshot_dir" | sed "s/'/\\\\'/g")') or 0\")" \
  2>/dev/null || true

exit 0
