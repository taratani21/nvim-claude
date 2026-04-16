#!/bin/bash
set -euo pipefail

input=$(cat)

context_file="${NVIM_CLAUDE_CONTEXT_FILE:-}"
if [ -z "$context_file" ]; then
  exit 0
fi

# Get the file being edited/written
file_path=$(echo "$input" | jq -r '.tool_input.file_path // empty')
if [ -z "$file_path" ]; then
  exit 0
fi

# Snapshot dir for this turn
snapshot_dir="$(dirname "$context_file")/snapshots"
mkdir -p "$snapshot_dir"

# Create a safe filename from the path
safe_name=$(echo "$file_path" | sed 's|/|__|g')
snapshot="$snapshot_dir/$safe_name"

# Only snapshot once per file per turn (first edit wins)
if [ -f "$snapshot" ]; then
  exit 0
fi

# Save the current file content (before Claude changes it)
if [ -f "$file_path" ]; then
  cp "$file_path" "$snapshot"
else
  # File doesn't exist yet (new file) — create empty snapshot
  touch "$snapshot"
fi

exit 0
