#!/bin/bash
set -euo pipefail

input=$(cat)

# shellcheck source=lib/snapshot.sh
. "$(dirname "$0")/lib/snapshot.sh"

# Snapshot working tree state for new turn (used by Stop hook to compute diff).
context_file="${NVIM_CLAUDE_CONTEXT_FILE:-}"
if [ -n "$context_file" ]; then
  base_dir="$(dirname "$context_file")"
  rm -f "$base_dir/turn-baseline.sha" "$base_dir/turn-current.sha"

  baseline_sha=$(build_snapshot_commit "nvim-claude turn baseline")
  if [ -n "$baseline_sha" ]; then
    echo "$baseline_sha" > "$base_dir/turn-baseline.sha"
  fi
fi

# Active-file context now flows over the IDE WS protocol (lua/nvim-claude/ide/).
# This hook no longer injects [Active File: ...] into prompts.
exit 0
