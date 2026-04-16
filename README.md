# nvim-claude

Neovim integration for Claude Code — active buffer context and terminal management.

## Features

- **Terminal management** — open/close Claude Code in Neovim splits or tmux panes
- **Visual selection sending** — send selected code to Claude with file context
- **Active buffer awareness** — automatically includes the current file as context in every Claude Code query
- **Tmux-aware** — detects tmux and uses tmux panes when available

## Installation

### As a Claude Code plugin (recommended)

Add the marketplace and install:

```
/plugin marketplace add taratani21/agent-plugin-marketplace
/plugin install nvim-claude@agent-plugin-marketplace
```

### As a Neovim plugin (lazy.nvim)

```lua
{
  "taratani21/nvim-claude",
  config = function()
    require("nvim-claude").setup()
  end,
}
```

## Configuration

```lua
require("nvim-claude").setup({
  split_direction = "vertical",  -- "vertical" or "horizontal"
  split_size = 80,               -- width (vertical) or height (horizontal)
  claude_command = "claude",     -- command to launch Claude Code
  prefer_tmux = true,            -- use tmux panes when inside tmux
  context = {
    enabled = true,                    -- enable active buffer context
    context_dir = "/tmp/nvim-claude",  -- where context files are written
  },
})
```

## Commands & Keybindings

| Command | Default binding | Description |
|---|---|---|
| `:ClaudeToggle` | `<leader>ct` | Toggle Claude Code session |
| `:ClaudeVSplit` | `<leader>cv` | Open in vertical split |
| `:ClaudeHSplit` | `<leader>ch` | Open in horizontal split |
| `:ClaudeSend` | `<leader>cp` (visual) | Send selection to Claude Code |

## Status Line

To show a `🟢 nvim connected` indicator in Claude Code's status line when linked to a Neovim session, add this to your `~/.claude/settings.json`:

```json
{
  "statusLine": {
    "type": "command",
    "command": "cat > /dev/null; [ -n \"${NVIM_CLAUDE_SERVER:-}\" ] && echo '🟢 nvim connected'"
  }
}
```

## How It Works

1. Neovim writes the active buffer's contents to a JSON file on every buffer switch and save
2. When Claude Code is launched from the plugin, it receives env vars linking it to the Neovim session
3. A `UserPromptSubmit` hook reads the context file and injects the active file into every query as a system message
4. The status line checks for the env var to show connection status
