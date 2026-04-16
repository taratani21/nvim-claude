# Active Buffer Context Design

## Overview

Give Claude Code awareness of the active Neovim file buffer. When a user submits a query to Claude Code, the current file's contents are automatically included as context. A status line indicator shows that the Claude session is linked to a Neovim instance.

## Plugin Structure

nvim-claude serves as both a Neovim plugin and a Claude Code plugin:

```
nvim-claude/
├── .claude-plugin/
│   └── plugin.json                -- Claude Code plugin manifest
├── hooks/
│   ├── hooks.json                 -- auto-registered hook config
│   └── scripts/
│       └── user-prompt-submit.sh  -- injects active file into queries
├── scripts/
│   └── statusline.sh              -- shows "[nvim connected]" (manual setup)
├── lua/nvim-claude/
│   ├── init.lua                   -- setup(), config, autocmd registration
│   ├── terminal.lua               -- terminal lifecycle
│   ├── send.lua                   -- visual selection sending
│   └── context.lua                -- writes buffer context to JSON
├── plugin/nvim-claude.lua         -- vim commands and keybindings
└── docs/
```

## Data Flow

```
Neovim                                    Claude Code
  |                                           |
  |-- BufEnter / BufWritePost ---------->     |
  |   context.lua writes JSON to              |
  |   /tmp/nvim-claude/<hash>.json            |
  |                                           |
  |-- terminal.lua launches claude with       |
  |   NVIM_CLAUDE_SERVER env var ---------->  |
  |                                           |
  |                              statusline.sh checks env var
  |                              shows "[nvim connected]"
  |                                           |
  |                              user types a query and submits
  |                                           |
  |                              UserPromptSubmit hook reads
  |                              /tmp/nvim-claude/<hash>.json
  |                              prepends file context to query
```

## Context Module (`lua/nvim-claude/context.lua`)

### Autocmds

Registers `BufEnter` and `BufWritePost` autocmds in a `nvim-claude` augroup.

### Buffer Filtering

Only writes context for real file buffers:
- `vim.bo.buftype == ""` (excludes terminals, help, quickfix, tree views, etc.)
- File must exist on disk (`vim.fn.filereadable(file) == 1`)

### Context File

Path: `/tmp/nvim-claude/<hash>.json` where `<hash>` is a deterministic hash of `vim.v.servername`.

Contents:

```json
{
  "file": "lua/nvim-claude/init.lua",
  "filetype": "lua",
  "cwd": "/root/projects/nvim-claude",
  "contents": "local M = {}\n...",
  "timestamp": 1713200000
}
```

### Lifecycle

- Autocmds are registered during `setup()` in `init.lua`
- Context file is created on first qualifying `BufEnter`
- Context file is deleted on `VimLeavePre`

## Terminal Launch Change (`lua/nvim-claude/terminal.lua`)

When opening Claude, pass the Neovim server address:

- **Neovim terminal backend**: Pass `NVIM_CLAUDE_SERVER` via `termopen()`'s `env` option
- **tmux backend**: Prefix the command: `NVIM_CLAUDE_SERVER=<servername> tmux split-window ...`

The env var value is `vim.v.servername`.

## Status Line Script (`scripts/statusline.sh`)

Simple script that checks if the session is linked to Neovim:

```bash
#!/bin/bash
if [ -n "$NVIM_CLAUDE_SERVER" ]; then
  echo "[nvim connected]"
fi
```

This is NOT auto-registered. Users must manually add to their Claude Code settings:

```json
{
  "statusLine": {
    "type": "command",
    "command": "<path-to-plugin>/scripts/statusline.sh"
  }
}
```

Runs on default Claude Code events (after assistant messages, etc.). No polling needed.

## Claude Code Plugin Manifest (`.claude-plugin/plugin.json`)

```json
{
  "name": "nvim-claude",
  "version": "0.1.0",
  "description": "Neovim integration for Claude Code — active buffer context and terminal management"
}
```

## Hook Configuration (`hooks/hooks.json`)

```json
{
  "UserPromptSubmit": [
    {
      "matcher": "",
      "hooks": [
        {
          "type": "command",
          "command": "bash ${CLAUDE_PLUGIN_ROOT}/hooks/scripts/user-prompt-submit.sh"
        }
      ]
    }
  ]
}
```

Auto-registered when the plugin is installed in Claude Code.

## UserPromptSubmit Hook (`hooks/scripts/user-prompt-submit.sh`)

### Behavior

1. Check if `NVIM_CLAUDE_SERVER` env var is set. If not, exit (no-op for non-Neovim sessions).
2. Derive the context file path from the env var (same hash as Neovim uses).
3. Read the JSON context file.
4. Prepend the file context to the user's query in this format:

```
[Active File: lua/nvim-claude/init.lua]
```lua
... full file contents ...
```

<user's original query>
```

### Edge Cases

- If `NVIM_CLAUDE_SERVER` is not set: no-op, pass query through unchanged
- If context file doesn't exist: no-op (Neovim may have closed)
- If context file is stale (timestamp older than a threshold): still include it but could warn

## Session Linking

### Plugin-launched sessions

The plugin sets `NVIM_CLAUDE_SERVER` automatically when launching Claude via `terminal.lua`. No user action needed.

### Standalone Claude sessions (future)

A user can manually link by launching Claude with the env var:

```bash
NVIM_CLAUDE_SERVER=/tmp/nvimABC123 claude
```

The server address is discoverable via `:echo v:servername` in Neovim. A future command could make this easier (e.g., `:ClaudeConnect` that prints the connection string).

## Multiple Session Support

Each Neovim instance has a unique `v:servername`, so:
- Multiple Neovim instances = multiple context files (different hashes)
- Multiple Claude sessions can link to different Neovim instances
- Multiple Claude sessions linking to the same Neovim instance share the same context file (they see the same active buffer, which is correct)

## Configuration

New config options in `setup()`:

```lua
require("nvim-claude").setup({
  -- existing options...
  context = {
    enabled = true,              -- enable/disable context writing
    context_dir = "/tmp/nvim-claude",  -- base directory for context files
  },
})
```

## What's NOT Included

- No cursor position tracking (just file-level context)
- No multi-file context (just the active buffer)
- No unsaved buffer content for now (writes on BufEnter/BufWritePost, so content reflects last save or file switch)
- No auto-configuration of the status line (manual user setup)
