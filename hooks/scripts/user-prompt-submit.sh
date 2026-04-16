#!/bin/bash
set -euo pipefail

# Read hook input from stdin
input=$(cat)

# Check if linked to a Neovim session
context_file="${NVIM_CLAUDE_CONTEXT_FILE:-}"

if [ -z "$context_file" ]; then
  # Not linked to Neovim, no-op
  exit 0
fi

if [ ! -f "$context_file" ]; then
  # Context file doesn't exist (Neovim may have closed)
  exit 0
fi

# Read context
file=$(jq -r '.file' "$context_file")
filetype=$(jq -r '.filetype' "$context_file")
contents=$(jq -r '.contents' "$context_file")

if [ -z "$file" ] || [ "$file" = "null" ]; then
  exit 0
fi

# Output JSON with additionalContext for UserPromptSubmit hooks
context=$(printf '[Active File: %s]\n```%s\n%s\n```' "$file" "$filetype" "$contents")
jq -n --arg ctx "$context" '{
  "hookSpecificOutput": {
    "hookEventName": "UserPromptSubmit",
    "additionalContext": $ctx
  }
}'
