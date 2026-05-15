# nvim-claude

Neovim integration for Claude Code — live editor state via the IDE protocol, per-turn diffs, and terminal management.

## Features

- **IDE protocol integration** — Neovim registers as a connected IDE in Claude Code (`/ide`), giving Claude live editor state and tool-driven control of the editor
- **Active buffer awareness** — automatically includes the current file and LSP diagnostics as context in every Claude Code query
- **Per-turn diff view** — after each Claude response, see exactly what changed in diffview.nvim with file panel navigation
- **Terminal management** — open/close Claude Code in Neovim splits or tmux panes
- **Visual selection sending** — send selected code lines to Claude with a reference to the active file
- **Tmux-aware** — detects tmux and uses tmux panes when available
- **Multi-session support** — multiple Neovim instances and Claude sessions work independently

## Installation

### As a Claude Code plugin (recommended)

This installs both the Neovim plugin and the Claude Code hooks:

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
  ide = {
    enabled = true,               -- expose nvim as a connected IDE to Claude Code
    auto_start = true,            -- start the WebSocket server on setup()
    selection_throttle_ms = 100,  -- min ms between selection_changed events
  },
})
```

## Commands & Keybindings

| Command | Default binding | Description |
|---|---|---|
| `:ClaudeToggle` | `<leader>ct` | Toggle Claude Code visibility (keeps session alive) |
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

### IDE Protocol Integration

The plugin starts a WebSocket server in Neovim that implements the Claude Code IDE protocol. Once connected, Neovim appears in Claude's `/ide` command as a registered editor, and Claude gains access to six tools:

| Tool | Description |
|---|---|
| `getCurrentSelection` | Returns the text currently selected in the editor |
| `getOpenEditors` | Lists all open buffers with their file paths |
| `getWorkspaceFolders` | Returns the project root directories |
| `getDiagnostics` | Returns LSP diagnostics for open files |
| `openFile` | Opens a file in Neovim and jumps to a specific line |
| `openDiff` | Opens a diff view between two versions of a file |

Live `selection_changed` events are pushed to Claude as the cursor moves, so Claude always knows what you are looking at without you needing to describe it.

The IDE integration works in both Neovim split and tmux pane spawn modes.

### Active Buffer Context

1. Neovim writes the active file's metadata and LSP diagnostics to a lightweight JSON file on `BufEnter`, `BufWritePost`, and `DiagnosticChanged` (no file contents stored — just the path and diagnostics)
2. When Claude Code is launched from the plugin, it receives `NVIM_CLAUDE_SERVER` and `NVIM_CLAUDE_CONTEXT_FILE` env vars linking it to the Neovim session
3. A `SessionStart` hook detects the Neovim connection and injects file navigation guidance

### Per-Turn Diffs

1. When you submit a prompt, the hook creates a lightweight git snapshot using a temp git index to capture both tracked and untracked files (`hooks/scripts/lib/snapshot.sh`) without disturbing your actual git index
2. Claude edits files during its turn
3. When Claude finishes responding, the `Stop` hook diffs the snapshot against the current working tree and opens diffview.nvim
4. Each new turn closes the previous diffview and opens a fresh one — no tab accumulation
5. You can also manually view the last turn's diffs with `<leader>cd` or `:ClaudeDiff`

### Session Linking

Each Neovim instance has a unique server address (`v:servername`). The plugin passes this to Claude as an env var, creating a 1:1 link. Multiple Neovim instances and Claude sessions work independently.

Standalone Claude sessions can also be linked manually:

```bash
NVIM_CLAUDE_SERVER=/tmp/nvimXYZ123 NVIM_CLAUDE_CONTEXT_FILE=/tmp/nvim-claude/hash.json claude
```

The server address is discoverable via `:echo v:servername` in Neovim.

## Migrating from <0.8.0

Earlier versions included a custom `open_in_nvim` MCP tool (with an associated `servers/` directory and `npm run build` step) for opening files in Neovim. That tool has been replaced by the standard IDE-protocol `openFile` tool. No user action is required — Claude will use the new tool automatically. The `npm install` and build steps are no longer needed.

## Requirements

- Neovim 0.5+
- [diffview.nvim](https://github.com/sindrets/diffview.nvim) (for per-turn diffs)
- `jq` (for hook scripts)
- tmux (optional, for tmux pane support)

## Limitations

- Per-turn diffs require a git repository (uses a temp git index for snapshots)
- Concurrent Claude sessions in the same git repo will see each other's changes in diffs (use separate worktrees for true isolation)
- Active buffer context reflects the last saved state (not unsaved changes)
