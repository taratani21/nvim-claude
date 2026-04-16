#!/bin/bash
set -euo pipefail

# Read hook input from stdin
input=$(cat)

# Only inject nvim navigation context when connected to a Neovim session
nvim_server="${NVIM_CLAUDE_SERVER:-}"
if [ -z "$nvim_server" ]; then
  exit 0
fi

context=$(cat <<'GUIDANCE'
[Neovim Session Connected]

You have an active Neovim session. Use the `open_in_nvim` MCP tool to open files in the user's editor instead of printing file contents in chat.

When to open files in Neovim:
- User asks "show me", "open", "go to", "navigate to", or "where is" a file or location
- You've found a bug, definition, or relevant code the user should look at
- After writing or updating a plan, spec, design doc, or any document the user should review — open it so they can read it in the editor with proper rendering instead of scrolling terminal output
- After creating any document intended for the user to read (README, ADR, migration guide, etc.)

When NOT to open files:
- When you're reading files to do your own work (use Read tool instead)
- When the user just wants you to explain code inline

The tool takes `file` (path) and optional `line` (number). Always include line when you know the specific location.

After writing a plan or spec, don't dump the full contents into chat — give a brief summary and open the file so the user reads it in their editor.

Pacing: open one file per response unless the user asks for multiple. After opening, explain what they're looking at. For additional locations, describe them in chat and offer to open.
GUIDANCE
)

jq -n --arg ctx "$context" '{
  "hookSpecificOutput": {
    "hookEventName": "SessionStart",
    "additionalContext": $ctx
  }
}'
