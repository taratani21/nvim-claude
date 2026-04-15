# nvim-claude Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a Neovim plugin that manages Claude Code terminal sessions in splits or tmux panes, with visual selection sending.

**Architecture:** Lua-only plugin with three modules — `init.lua` (config/setup), `terminal.lua` (session lifecycle, tmux detection), `send.lua` (visual selection piping). A thin `plugin/nvim-claude.lua` file registers commands and keybindings. Tmux vs Neovim terminal is decided at open time via `$TMUX` env check.

**Tech Stack:** Lua, Neovim API (0.5+), tmux CLI

---

## File Map

| File | Responsibility |
|---|---|
| `lua/nvim-claude/init.lua` | Config defaults, `setup()`, public API surface |
| `lua/nvim-claude/terminal.lua` | Open/close/toggle terminal, tmux detection, pane/buffer tracking |
| `lua/nvim-claude/send.lua` | Get visual selection, write to terminal channel or tmux pane |
| `plugin/nvim-claude.lua` | Register `:Claude*` commands and default keybindings |

---

### Task 1: Config module (`init.lua`)

**Files:**
- Create: `lua/nvim-claude/init.lua`

- [ ] **Step 1: Create init.lua with config defaults and setup()**

```lua
local M = {}

M.config = {
  split_direction = "vertical",
  split_size = 80,
  claude_command = "claude",
  prefer_tmux = true,
}

function M.setup(opts)
  M.config = vim.tbl_deep_extend("force", M.config, opts or {})
end

return M
```

- [ ] **Step 2: Verify module loads**

Open Neovim and run:
```
:lua print(vim.inspect(require('nvim-claude').config))
```
Expected: table with the four default config values.

- [ ] **Step 3: Commit**

```bash
git add lua/nvim-claude/init.lua
git commit -m "feat: add config module with setup() and defaults"
```

---

### Task 2: Terminal module — Neovim backend (`terminal.lua`)

**Files:**
- Create: `lua/nvim-claude/terminal.lua`

- [ ] **Step 1: Create terminal.lua with state tracking and tmux detection**

```lua
local M = {}

local state = {
  buf = nil,
  win = nil,
  chan = nil,
  tmux_pane = nil,
  direction = nil,
}

function M.is_tmux()
  return vim.env.TMUX ~= nil
end

function M.use_tmux()
  local config = require("nvim-claude").config
  return config.prefer_tmux and M.is_tmux()
end

function M.is_open()
  if M.use_tmux() then
    return state.tmux_pane ~= nil
  end
  return state.win ~= nil and vim.api.nvim_win_is_valid(state.win)
end

return M
```

- [ ] **Step 2: Add Neovim terminal open function**

Add to `terminal.lua` before the `return M`:

```lua
local function get_size(direction)
  local config = require("nvim-claude").config
  if direction == "vertical" then
    return config.split_size or 80
  else
    return config.split_size or 15
  end
end

local function open_nvim(direction)
  local config = require("nvim-claude").config
  local size = get_size(direction)

  if direction == "vertical" then
    vim.cmd(size .. "vsplit")
  else
    vim.cmd("botright " .. size .. "split")
  end

  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_win_set_buf(0, buf)

  local chan = vim.fn.termopen(config.claude_command, {
    on_exit = function()
      state.buf = nil
      state.win = nil
      state.chan = nil
    end,
  })

  state.buf = buf
  state.win = vim.api.nvim_get_current_win()
  state.chan = chan
  state.direction = direction
end
```

- [ ] **Step 3: Add Neovim terminal close function**

Add to `terminal.lua` before the `return M`:

```lua
local function close_nvim()
  if state.win and vim.api.nvim_win_is_valid(state.win) then
    vim.api.nvim_win_close(state.win, true)
  end
  if state.buf and vim.api.nvim_buf_is_valid(state.buf) then
    vim.api.nvim_buf_delete(state.buf, { force = true })
  end
  state.win = nil
  state.buf = nil
  state.chan = nil
end
```

- [ ] **Step 4: Commit**

```bash
git add lua/nvim-claude/terminal.lua
git commit -m "feat: add terminal module with nvim backend open/close"
```

---

### Task 3: Terminal module — tmux backend

**Files:**
- Modify: `lua/nvim-claude/terminal.lua`

- [ ] **Step 1: Add tmux open function**

Add to `terminal.lua` before the `return M`:

```lua
local function open_tmux(direction)
  local config = require("nvim-claude").config
  local size = get_size(direction)
  local flag = direction == "vertical" and "-h" or "-v"

  local cmd = string.format(
    "tmux split-window %s -l %d %s",
    flag, size, config.claude_command
  )
  local result = vim.fn.system(cmd)

  -- capture the new pane ID
  local pane_id = vim.fn.trim(vim.fn.system("tmux display-message -p '#{pane_id}'"))
  -- the new pane is now active, so we need the *last* pane's ID
  -- actually, split-window makes the new pane active, so get it before switching back
  pane_id = vim.fn.trim(vim.fn.system("tmux list-panes -F '#{pane_id}' | tail -1"))

  state.tmux_pane = pane_id
  state.direction = direction
end
```

- [ ] **Step 2: Add tmux close function**

Add to `terminal.lua` before the `return M`:

```lua
local function close_tmux()
  if state.tmux_pane then
    vim.fn.system("tmux kill-pane -t " .. state.tmux_pane)
    state.tmux_pane = nil
  end
end
```

- [ ] **Step 3: Commit**

```bash
git add lua/nvim-claude/terminal.lua
git commit -m "feat: add tmux backend for terminal module"
```

---

### Task 4: Terminal module — public API (toggle, open, close)

**Files:**
- Modify: `lua/nvim-claude/terminal.lua`

- [ ] **Step 1: Add public open/close/toggle functions**

Add to `terminal.lua` before the `return M`:

```lua
function M.open(direction)
  local config = require("nvim-claude").config
  direction = direction or config.split_direction

  if M.is_open() then
    M.close()
  end

  if M.use_tmux() then
    open_tmux(direction)
  else
    open_nvim(direction)
  end
end

function M.close()
  if M.use_tmux() then
    close_tmux()
  else
    close_nvim()
  end
end

function M.toggle()
  if M.is_open() then
    M.close()
  else
    local config = require("nvim-claude").config
    M.open(state.direction or config.split_direction)
  end
end

function M.get_state()
  return state
end
```

- [ ] **Step 2: Verify toggle works**

Open Neovim and run:
```
:lua require('nvim-claude').setup()
:lua require('nvim-claude.terminal').toggle()
```
Expected: A vertical split opens running `claude`. Running toggle again closes it.

- [ ] **Step 3: Commit**

```bash
git add lua/nvim-claude/terminal.lua
git commit -m "feat: add public toggle/open/close API to terminal module"
```

---

### Task 5: Send module (`send.lua`)

**Files:**
- Create: `lua/nvim-claude/send.lua`

- [ ] **Step 1: Create send.lua with visual selection sending**

```lua
local M = {}

local function get_visual_selection()
  local start_pos = vim.fn.getpos("'<")
  local end_pos = vim.fn.getpos("'>")
  local start_line = start_pos[2]
  local end_line = end_pos[2]

  local lines = vim.api.nvim_buf_get_lines(0, start_line - 1, end_line, false)
  return table.concat(lines, "\n")
end

function M.send_selection()
  local terminal = require("nvim-claude.terminal")

  if not terminal.is_open() then
    vim.notify("nvim-claude: no Claude session is open", vim.log.levels.WARN)
    return
  end

  local text = get_visual_selection()
  if text == "" then
    return
  end

  local state = terminal.get_state()

  if terminal.use_tmux() then
    -- escape special characters for tmux send-keys
    local escaped = text:gsub("'", "'\\''")
    vim.fn.system(string.format("tmux send-keys -t %s '%s' Enter", state.tmux_pane, escaped))
  else
    if state.chan then
      vim.api.nvim_chan_send(state.chan, text .. "\n")
    end
  end
end

return M
```

- [ ] **Step 2: Commit**

```bash
git add lua/nvim-claude/send.lua
git commit -m "feat: add send module for visual selection piping"
```

---

### Task 6: Commands and keybindings (`plugin/nvim-claude.lua`)

**Files:**
- Create: `plugin/nvim-claude.lua`

- [ ] **Step 1: Create plugin file with commands**

```lua
if vim.g.loaded_nvim_claude then
  return
end
vim.g.loaded_nvim_claude = true

vim.api.nvim_create_user_command("ClaudeToggle", function()
  require("nvim-claude.terminal").toggle()
end, { desc = "Toggle Claude Code session" })

vim.api.nvim_create_user_command("ClaudeVSplit", function()
  require("nvim-claude.terminal").open("vertical")
end, { desc = "Open Claude Code in vertical split" })

vim.api.nvim_create_user_command("ClaudeHSplit", function()
  require("nvim-claude.terminal").open("horizontal")
end, { desc = "Open Claude Code in horizontal split" })

vim.api.nvim_create_user_command("ClaudeSend", function()
  require("nvim-claude.send").send_selection()
end, { range = true, desc = "Send visual selection to Claude Code" })
```

- [ ] **Step 2: Add default keybindings in init.lua setup()**

Modify `lua/nvim-claude/init.lua` — replace the existing `setup()` function:

```lua
function M.setup(opts)
  M.config = vim.tbl_deep_extend("force", M.config, opts or {})

  -- Default keybindings
  vim.keymap.set("n", "<leader>ct", "<cmd>ClaudeToggle<cr>", { desc = "Toggle Claude Code" })
  vim.keymap.set("n", "<leader>cv", "<cmd>ClaudeVSplit<cr>", { desc = "Claude Code vertical split" })
  vim.keymap.set("n", "<leader>ch", "<cmd>ClaudeHSplit<cr>", { desc = "Claude Code horizontal split" })
  vim.keymap.set("v", "<leader>cs", "<cmd>ClaudeSend<cr>", { desc = "Send selection to Claude Code" })
end
```

- [ ] **Step 3: Verify commands register**

Open Neovim and run:
```
:lua require('nvim-claude').setup()
:ClaudeToggle
```
Expected: Claude Code opens in a vertical split.

- [ ] **Step 4: Commit**

```bash
git add plugin/nvim-claude.lua lua/nvim-claude/init.lua
git commit -m "feat: add user commands and default keybindings"
```

---

### Task 7: Smoke test the full plugin

**Files:**
- No new files

- [ ] **Step 1: Test full flow — Neovim terminal**

Ensure `$TMUX` is not set (or `prefer_tmux = false`). Open Neovim:
```
:lua require('nvim-claude').setup({ prefer_tmux = false })
:ClaudeToggle          -- should open vertical split with claude
:ClaudeToggle          -- should close it
:ClaudeHSplit          -- should open horizontal split
:ClaudeToggle          -- should close it
```

- [ ] **Step 2: Test full flow — tmux backend**

Inside a tmux session, open Neovim:
```
:lua require('nvim-claude').setup({ prefer_tmux = true })
:ClaudeToggle          -- should open tmux pane with claude
:ClaudeToggle          -- should close the tmux pane
:ClaudeVSplit          -- should open vertical tmux pane
```

- [ ] **Step 3: Test send selection**

Open a file, visually select some lines, then:
```
:'<,'>ClaudeSend       -- should send the selected text to the claude session
```

- [ ] **Step 4: Commit any fixes**

If any fixes were needed, commit them:
```bash
git add -A
git commit -m "fix: address issues found during smoke testing"
```
