#!/bin/bash
set -euo pipefail

input=$(cat)

context_file="${NVIM_CLAUDE_CONTEXT_FILE:-}"
if [ -z "$context_file" ]; then
  exit 0
fi

file_path=$(echo "$input" | jq -r '.tool_input.file_path // empty')
if [ -z "$file_path" ]; then
  exit 0
fi

# Append file path to manifest (deduplicated at read time)
manifest="$(dirname "$context_file")/manifest.json"

if [ -f "$manifest" ]; then
  # Add to existing array if not already present
  jq --arg fp "$file_path" 'if index($fp) then . else . + [$fp] end' "$manifest" > "$manifest.tmp"
  mv "$manifest.tmp" "$manifest"
else
  jq -n --arg fp "$file_path" '[$fp]' > "$manifest"
fi

exit 0
