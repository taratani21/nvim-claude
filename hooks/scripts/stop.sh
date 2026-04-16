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

# Generate unified diff for all changed files
diff_file="$(dirname "$context_file")/turn-diff.patch"
> "$diff_file"

files=$(jq -r '.[]' "$manifest")
has_changes=false

for file_path in $files; do
  safe_name=$(echo "$file_path" | sed 's|/|__|g')
  snapshot="$snapshot_dir/$safe_name"

  if [ ! -f "$snapshot" ]; then
    continue
  fi

  # Generate diff (diff exits 1 if files differ, which is expected)
  file_diff=$(diff -u "$snapshot" "$file_path" \
    --label "a/$file_path" \
    --label "b/$file_path" 2>/dev/null || true)

  if [ -n "$file_diff" ]; then
    echo "$file_diff" >> "$diff_file"
    echo "" >> "$diff_file"
    has_changes=true
  fi
done

if [ "$has_changes" = false ]; then
  rm -f "$diff_file"
  exit 0
fi

# Open the diff in Neovim in a new tab
nvim --server "$nvim_server" --remote-send \
  ":tabnew $diff_file | setlocal filetype=diff buftype=nofile readonly nomodified
" 2>/dev/null || true

exit 0
