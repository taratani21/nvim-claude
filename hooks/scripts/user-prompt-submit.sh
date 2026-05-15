#!/bin/bash
set -euo pipefail

# Read hook input from stdin
input=$(cat)

# shellcheck source=lib/snapshot.sh
. "$(dirname "$0")/lib/snapshot.sh"

# Clear turn diff tracking and snapshot working tree state for new turn
context_file="${NVIM_CLAUDE_CONTEXT_FILE:-}"
if [ -n "$context_file" ]; then
  base_dir="$(dirname "$context_file")"
  rm -f "$base_dir/turn-baseline.sha" "$base_dir/turn-current.sha"

  baseline_sha=$(build_snapshot_commit "nvim-claude turn baseline")
  if [ -n "$baseline_sha" ]; then
    echo "$baseline_sha" > "$base_dir/turn-baseline.sha"
  fi
fi

# Check if linked to a Neovim session
if [ -z "$context_file" ]; then
  exit 0
fi

if [ ! -f "$context_file" ]; then
  exit 0
fi

# Read metadata from context JSON
file=$(jq -r '.file' "$context_file")
filetype=$(jq -r '.filetype' "$context_file")
cwd=$(jq -r '.cwd' "$context_file")

if [ -z "$file" ] || [ "$file" = "null" ]; then
  exit 0
fi

# Read file contents from disk
full_path="$cwd/$file"
if [ ! -f "$full_path" ]; then
  exit 0
fi
contents=$(cat "$full_path")

# Format diagnostics if any exist
diag_count=$(jq '.diagnostics | length' "$context_file")
diag_section=""
if [ "$diag_count" -gt 0 ]; then
  diag_lines=$(jq -r '.diagnostics[] | "  Line \(.line) [\(.severity)]: \(.message)"' "$context_file")
  diag_section=$(printf '\n\nDiagnostics (%d):\n%s' "$diag_count" "$diag_lines")
fi

# Build context string
context=$(printf '[Active File: %s]%s\n```%s\n%s\n```' "$file" "$diag_section" "$filetype" "$contents")

jq -n --arg ctx "$context" '{
  "hookSpecificOutput": {
    "hookEventName": "UserPromptSubmit",
    "additionalContext": $ctx
  }
}'
