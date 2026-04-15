# nvim-claude Plugin Design

## Overview

A Neovim plugin that provides terminal session management for Claude Code. Opens and manages Claude Code sessions in Neovim splits or tmux panes, with the ability to send code selections to the session.

## Plugin Structure

```
nvim-claude/
├── lua/nvim-claude/
│   ├── init.lua        -- setup(), config defaults, public API
│   ├── terminal.lua    -- terminal lifecycle (open/close/toggle, layout, tmux detection)
│   └── send.lua        -- send visual selection to active Claude session
├── plugin/nvim-claude.lua  -- vim commands and default keybindings
└── README.md
```

## Configuration

Users configure via `require('nvim-claude').setup()` with these options:

- **`split_direction`** — `"vertical"` or `"horizontal"` (default: `"vertical"`)
- **`split_size`** — width (vertical) or height (horizontal) in columns/rows (default: `80` vertical, `15` horizontal)
- **`claude_command`** — the shell command to launch (default: `"claude"`)
- **`prefer_tmux`** — when `true` and inside tmux, open Claude in a tmux pane instead of a Neovim split (default: `true`)

Plugin manager setup (lazy.nvim):

```lua
{
  "user/nvim-claude",
  config = function()
    require("nvim-claude").setup({
      split_direction = "vertical",
      split_size = 80,
      claude_command = "claude",
      prefer_tmux = true,
    })
  end,
}
```

## Commands & Keybindings

| Command | Default binding | Description |
|---|---|---|
| `:ClaudeToggle` | `<leader>ct` | Toggle Claude Code session open/closed |
| `:ClaudeVSplit` | `<leader>cv` | Open in vertical split |
| `:ClaudeHSplit` | `<leader>ch` | Open in horizontal split |
| `:ClaudeSend` | `<leader>cs` (visual mode) | Send visual selection to the Claude session |

## Terminal Behavior

- **Tmux detection:** Check `$TMUX` env var. If set and `prefer_tmux` is true, use `tmux split-window` to open Claude. Otherwise, use Neovim's `vim.fn.termopen()`.
- **Toggle:** If a Claude session is already open, close it. If closed, reopen with the last-used layout.
- **Single session:** Only one Claude terminal at a time. Toggling layout closes the current one and reopens in the new direction.
- **Tmux pane management:** When using tmux, track the pane ID so we can close/toggle it. Use `tmux split-window -h` (vertical) or `tmux split-window -v` (horizontal) to match Neovim's split semantics.

## Send Selection

- In visual mode, `:ClaudeSend` grabs the selected text and writes it to the terminal channel (Neovim) or pipes it via `tmux send-keys` (tmux).
- The selection is sent as-is, preserving newlines.

## Technical Decisions

- **Lua-only:** Requires Neovim 0.5+. No VimScript.
- **lazy.nvim:** Recommended plugin manager, but any Lua-compatible manager works.
- **Flat module structure:** terminal.lua handles both tmux and Neovim terminal backends. The tmux-vs-Neovim decision is a single conditional at open time — no need for a backend abstraction layer yet.
- **No external dependencies:** Only requires Neovim APIs and optionally tmux.
