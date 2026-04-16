#!/bin/bash
# Reads Claude Code session JSON from stdin (unused here).
# Checks if session is linked to a Neovim instance via env var.
cat > /dev/null

if [ -n "${NVIM_CLAUDE_SERVER:-}" ]; then
  echo "[nvim connected]"
fi
