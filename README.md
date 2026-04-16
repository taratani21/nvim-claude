# nvim-claude

Neovim integration for Claude Code — active buffer context, per-turn diffs, file navigation, and terminal management.

## Features

- **Active buffer awareness** — automatically includes the current file and LSP diagnostics as context in every Claude Code query
- **Per-turn diff view** — after each Claude response, see exactly what changed in diffview.nvim with file panel navigation
- **Open files in Neovim** — Claude can open files in your editor via an MCP tool (e.g., "show me where auth is handled")
- **Terminal management** — open/close Claude Code in Neovim splits or tmux panes
- **Visual selection sending** — send selected code lines to Claude with a reference to the active file
- **Tmux-aware** — detects tmux and uses tmux panes when available
- **Multi-session support** — multiple Neovim instances and Claude sessions work independently

## Installation

### As a Claude Code plugin (recommended)

This installs both the Neovim plugin and the Claude Code hooks/MCP server:

```
/plugin marketplace add taratani21/agent-plugin-marketplace
/plugin install nvim-claude@agent-plugin-marketplace
```

Then add to your Neovim config (lazy.nvim):

```lua
{
  dir = '~/.claude/plugins/cache/agent-plugin-marketplace/nvim-claude/<version>',
  name = 'nvim-claude',
  lazy = false,
  config = function()
    require('nvim-claude').setup()
  end,
}
```

Or point directly at the repo:

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
| `:ClaudeDiff` | `<leader>cd` | Show diffs from last Claude turn |

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

### Active Buffer Context

1. Neovim writes the active file's metadata and LSP diagnostics to a lightweight JSON file on `BufEnter`, `BufWritePost`, and `DiagnosticChanged` (no file contents stored — just the path and diagnostics)
2. When Claude Code is launched from the plugin, it receives `NVIM_CLAUDE_SERVER` and `NVIM_CLAUDE_CONTEXT_FILE` env vars linking it to the Neovim session
3. A `UserPromptSubmit` hook reads the context file, loads the file contents from disk on-demand, and injects the active file + diagnostics into every query

### Per-Turn Diffs

1. When you submit a prompt, the hook creates a lightweight git snapshot of the working tree using `git stash create` (non-destructive — doesn't modify your working tree or stash list)
2. Claude edits files during its turn
3. When Claude finishes responding, the `Stop` hook diffs the snapshot against the current working tree and opens diffview.nvim
4. Each new turn closes the previous diffview and opens a fresh one — no tab accumulation
5. You can also manually view the last turn's diffs with `<leader>cd` or `:ClaudeDiff`

### File Navigation (MCP)

The plugin includes an MCP server that exposes an `open_in_nvim` tool. Claude can use it to open files in your editor when you ask things like "show me where X is defined." The companion skill teaches Claude when to use the tool and to pace file openings (one per response, explain before opening another).

### Session Linking

Each Neovim instance has a unique server address (`v:servername`). The plugin passes this to Claude as an env var, creating a 1:1 link. Multiple Neovim instances and Claude sessions work independently.

Standalone Claude sessions can also be linked manually:

```bash
NVIM_CLAUDE_SERVER=/tmp/nvimXYZ123 NVIM_CLAUDE_CONTEXT_FILE=/tmp/nvim-claude/hash.json claude
```

The server address is discoverable via `:echo v:servername` in Neovim.

## Requirements

- Neovim 0.5+
- [diffview.nvim](https://github.com/sindrets/diffview.nvim) (for per-turn diffs)
- `jq` (for hook scripts)
- tmux (optional, for tmux pane support)

## Limitations

- Per-turn diffs require a git repository (uses `git stash create` for snapshots)
- Concurrent Claude sessions in the same git repo will see each other's changes in diffs (use separate worktrees for true isolation)
- The `open_in_nvim` MCP tool requires `nvim` to be on the PATH
- Active buffer context reflects the last saved state (not unsaved changes)
