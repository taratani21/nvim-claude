#!/bin/bash
set -euo pipefail

# Read hook input from stdin
input=$(cat)

# Clear turn diff tracking and snapshot working tree state for new turn
context_file="${NVIM_CLAUDE_CONTEXT_FILE:-}"
if [ -n "$context_file" ]; then
  base_dir="$(dirname "$context_file")"
  rm -rf "$base_dir/snapshots"
  rm -f "$base_dir/manifest.json"

  # Create a git stash object of current state (doesn't modify working tree or stash list)
  if git rev-parse --is-inside-work-tree > /dev/null 2>&1; then
    # Stage everything temporarily to capture untracked files too
    stash_sha=$(git stash create 2>/dev/null || true)
    if [ -z "$stash_sha" ]; then
      # No changes to stash — use HEAD as the baseline
      stash_sha=$(git rev-parse HEAD 2>/dev/null || true)
    fi
    if [ -n "$stash_sha" ]; then
      echo "$stash_sha" > "$base_dir/turn-baseline.sha"
    fi
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
