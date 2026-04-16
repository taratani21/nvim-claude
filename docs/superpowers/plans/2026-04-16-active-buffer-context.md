# Active Buffer Context Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Give Claude Code automatic awareness of the active Neovim file buffer by writing context to a JSON file and injecting it into queries via a UserPromptSubmit hook.

**Architecture:** Neovim writes buffer context to `/tmp/nvim-claude/<hash>.json` on autocmd events. A Claude Code plugin hook reads this file on every prompt submission and injects the file contents as a system message. The terminal module passes `NVIM_CLAUDE_SERVER` env var to link sessions. A status line script shows connection status.

**Tech Stack:** Lua (Neovim API), Bash (hooks/scripts), jq (JSON processing), Claude Code plugin system

---

## File Map

| File | Action | Responsibility |
|---|---|---|
| `lua/nvim-claude/context.lua` | Create | Write active buffer context to JSON on autocmd events |
| `lua/nvim-claude/init.lua` | Modify | Add context config options, register autocmds via context module |
| `lua/nvim-claude/terminal.lua` | Modify | Pass `NVIM_CLAUDE_SERVER` env var when launching Claude |
| `.claude-plugin/plugin.json` | Create | Claude Code plugin manifest |
| `hooks/hooks.json` | Create | Hook configuration for UserPromptSubmit |
| `hooks/scripts/user-prompt-submit.sh` | Create | Read context JSON, output systemMessage |
| `scripts/statusline.sh` | Create | Check env var, show "[nvim connected]" |

---

### Task 1: Context module (`context.lua`)

**Files:**
- Create: `lua/nvim-claude/context.lua`

- [ ] **Step 1: Create context.lua with hash function and context writing**

```lua
local M = {}

local function get_context_dir()
  local config = require("nvim-claude").config
  return (config.context and config.context.context_dir) or "/tmp/nvim-claude"
end

local function get_hash()
  local servername = vim.v.servername
  -- simple hash: replace non-alphanumeric chars with dashes
  return servername:gsub("[^%w]", "-"):gsub("^-+", ""):gsub("-+$", "")
end

function M.get_context_path()
  return get_context_dir() .. "/" .. get_hash() .. ".json"
end

function M.get_servername()
  return vim.v.servername
end

local function is_file_buffer()
  if vim.bo.buftype ~= "" then
    return false
  end
  local file = vim.api.nvim_buf_get_name(0)
  if file == "" then
    return false
  end
  if vim.fn.filereadable(file) ~= 1 then
    return false
  end
  return true
end

function M.write_context()
  if not is_file_buffer() then
    return
  end

  local file = vim.fn.expand("%:.")
  local abs_file = vim.api.nvim_buf_get_name(0)
  local ft = vim.bo.filetype
  local cwd = vim.fn.getcwd()
  local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
  local contents = table.concat(lines, "\n")

  local context = {
    file = file,
    filetype = ft,
    cwd = cwd,
    contents = contents,
    timestamp = os.time(),
  }

  local dir = get_context_dir()
  vim.fn.mkdir(dir, "p")

  local json = vim.fn.json_encode(context)
  local path = M.get_context_path()
  local f = io.open(path, "w")
  if f then
    f:write(json)
    f:close()
  end
end

function M.delete_context()
  local path = M.get_context_path()
  os.remove(path)
end

function M.register_autocmds()
  local group = vim.api.nvim_create_augroup("nvim-claude-context", { clear = true })

  vim.api.nvim_create_autocmd({ "BufEnter", "BufWritePost" }, {
    group = group,
    callback = function()
      M.write_context()
    end,
  })

  vim.api.nvim_create_autocmd("VimLeavePre", {
    group = group,
    callback = function()
      M.delete_context()
    end,
  })
end

return M
```

- [ ] **Step 2: Commit**

```bash
git add lua/nvim-claude/context.lua
git commit -m "feat: add context module for active buffer tracking"
```

---

### Task 2: Update init.lua with context config and autocmd registration

**Files:**
- Modify: `lua/nvim-claude/init.lua`

- [ ] **Step 1: Add context config defaults and register autocmds in setup()**

Replace the full contents of `lua/nvim-claude/init.lua` with:

```lua
local M = {}

M.config = {
  split_direction = "vertical",
  split_size = 80,
  claude_command = "claude",
  prefer_tmux = true,
  context = {
    enabled = true,
    context_dir = "/tmp/nvim-claude",
  },
}

function M.setup(opts)
  M.config = vim.tbl_deep_extend("force", M.config, opts or {})

  -- Register context autocmds
  if M.config.context.enabled then
    require("nvim-claude.context").register_autocmds()
  end

  -- Default keybindings
  vim.keymap.set("n", "<leader>ct", "<cmd>ClaudeToggle<cr>", { desc = "Toggle Claude Code" })
  vim.keymap.set("n", "<leader>cv", "<cmd>ClaudeVSplit<cr>", { desc = "Claude Code vertical split" })
  vim.keymap.set("n", "<leader>ch", "<cmd>ClaudeHSplit<cr>", { desc = "Claude Code horizontal split" })
  vim.keymap.set("v", "<leader>cp", ":'<,'>ClaudeSend<cr>", { desc = "Send selection to Claude Code" })
end

return M
```

- [ ] **Step 2: Verify autocmds register**

Open Neovim and run:
```
:lua require('nvim-claude').setup()
:autocmd nvim-claude-context
```
Expected: Shows BufEnter, BufWritePost, and VimLeavePre autocmds.

- [ ] **Step 3: Verify context file is written**

Open a file in Neovim, then check:
```bash
ls /tmp/nvim-claude/
cat /tmp/nvim-claude/*.json | jq .
```
Expected: JSON file with file, filetype, cwd, contents, and timestamp fields.

- [ ] **Step 4: Commit**

```bash
git add lua/nvim-claude/init.lua
git commit -m "feat: add context config and autocmd registration to setup()"
```

---

### Task 3: Update terminal.lua to pass NVIM_CLAUDE_SERVER env var

**Files:**
- Modify: `lua/nvim-claude/terminal.lua`

- [ ] **Step 1: Modify open_nvim to pass env var**

In `lua/nvim-claude/terminal.lua`, replace the `open_nvim` function with:

```lua
local function open_nvim(direction)
  local config = require("nvim-claude").config
  local context = require("nvim-claude.context")
  local size = get_size(direction)

  if direction == "vertical" then
    vim.cmd(size .. "vsplit")
  else
    vim.cmd("botright " .. size .. "split")
  end

  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_win_set_buf(0, buf)

  local chan = vim.fn.termopen(config.claude_command, {
    env = {
      NVIM_CLAUDE_SERVER = context.get_servername(),
      NVIM_CLAUDE_CONTEXT_FILE = context.get_context_path(),
    },
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

- [ ] **Step 2: Modify open_tmux to pass env var**

In `lua/nvim-claude/terminal.lua`, replace the `open_tmux` function with:

```lua
local function open_tmux(direction)
  local config = require("nvim-claude").config
  local context = require("nvim-claude.context")
  local size = get_size(direction)
  local flag = direction == "vertical" and "-h" or "-v"

  local cmd = string.format(
    "tmux split-window %s -l %d -e NVIM_CLAUDE_SERVER=%s -e NVIM_CLAUDE_CONTEXT_FILE=%s %s",
    flag,
    size,
    vim.fn.shellescape(context.get_servername()),
    vim.fn.shellescape(context.get_context_path()),
    config.claude_command
  )
  vim.fn.system(cmd)

  local pane_id = vim.fn.trim(vim.fn.system("tmux list-panes -F '#{pane_id}' | tail -1"))

  state.tmux_pane = pane_id
  state.direction = direction
end
```

- [ ] **Step 3: Commit**

```bash
git add lua/nvim-claude/terminal.lua
git commit -m "feat: pass NVIM_CLAUDE_SERVER env var when launching Claude"
```

---

### Task 4: Claude Code plugin manifest

**Files:**
- Create: `.claude-plugin/plugin.json`

- [ ] **Step 1: Create plugin manifest**

```json
{
  "name": "nvim-claude",
  "version": "0.1.0",
  "description": "Neovim integration for Claude Code — active buffer context and terminal management"
}
```

- [ ] **Step 2: Commit**

```bash
git add .claude-plugin/plugin.json
git commit -m "feat: add Claude Code plugin manifest"
```

---

### Task 5: UserPromptSubmit hook

**Files:**
- Create: `hooks/hooks.json`
- Create: `hooks/scripts/user-prompt-submit.sh`

- [ ] **Step 1: Create hooks.json**

Create `hooks/hooks.json`:

```json
{
  "description": "nvim-claude hooks for active buffer context injection",
  "hooks": {
    "UserPromptSubmit": [
      {
        "matcher": "",
        "hooks": [
          {
            "type": "command",
            "command": "bash ${CLAUDE_PLUGIN_ROOT}/hooks/scripts/user-prompt-submit.sh",
            "timeout": 10
          }
        ]
      }
    ]
  }
}
```

- [ ] **Step 2: Create the hook script**

Create `hooks/scripts/user-prompt-submit.sh`:

```bash
#!/bin/bash
set -euo pipefail

# Read hook input from stdin
input=$(cat)

# Check if linked to a Neovim session
context_file="${NVIM_CLAUDE_CONTEXT_FILE:-}"

if [ -z "$context_file" ]; then
  # Not linked to Neovim, no-op
  exit 0
fi

if [ ! -f "$context_file" ]; then
  # Context file doesn't exist (Neovim may have closed)
  exit 0
fi

# Read context
file=$(jq -r '.file' "$context_file")
filetype=$(jq -r '.filetype' "$context_file")
contents=$(jq -r '.contents' "$context_file")

if [ -z "$file" ] || [ "$file" = "null" ]; then
  exit 0
fi

# Build system message with active file context
system_message=$(printf '[Active File: %s]\n```%s\n%s\n```' "$file" "$filetype" "$contents")

# Output JSON with systemMessage
jq -n --arg msg "$system_message" '{
  "systemMessage": $msg
}'
```

- [ ] **Step 3: Make the hook script executable**

```bash
chmod +x hooks/scripts/user-prompt-submit.sh
```

- [ ] **Step 4: Test the hook script manually**

```bash
# Create a test context file
mkdir -p /tmp/nvim-claude
echo '{"file":"test.lua","filetype":"lua","contents":"print(\"hello\")","cwd":"/tmp","timestamp":1713200000}' > /tmp/nvim-claude/test-context.json

# Test the hook
NVIM_CLAUDE_CONTEXT_FILE=/tmp/nvim-claude/test-context.json \
  echo '{"user_prompt":"explain this code"}' | \
  bash hooks/scripts/user-prompt-submit.sh | jq .

# Expected output:
# {
#   "systemMessage": "[Active File: test.lua]\n```lua\nprint(\"hello\")\n```"
# }

# Clean up
rm /tmp/nvim-claude/test-context.json
```

- [ ] **Step 5: Commit**

```bash
git add hooks/hooks.json hooks/scripts/user-prompt-submit.sh
git commit -m "feat: add UserPromptSubmit hook for active buffer context injection"
```

---

### Task 6: Status line script

**Files:**
- Create: `scripts/statusline.sh`

- [ ] **Step 1: Create the status line script**

Create `scripts/statusline.sh`:

```bash
#!/bin/bash
# Reads Claude Code session JSON from stdin (unused here).
# Checks if session is linked to a Neovim instance via env var.
cat > /dev/null

if [ -n "${NVIM_CLAUDE_SERVER:-}" ]; then
  echo "[nvim connected]"
fi
```

- [ ] **Step 2: Make it executable**

```bash
chmod +x scripts/statusline.sh
```

- [ ] **Step 3: Commit**

```bash
git add scripts/statusline.sh
git commit -m "feat: add status line script showing nvim connection status"
```

---

### Task 7: End-to-end verification

**Files:**
- No new files

- [ ] **Step 1: Verify plugin structure**

```bash
find . -type f -not -path './.git/*' -not -path './docs/*' | sort
```

Expected:
```
./.claude-plugin/plugin.json
./hooks/hooks.json
./hooks/scripts/user-prompt-submit.sh
./lua/nvim-claude/context.lua
./lua/nvim-claude/init.lua
./lua/nvim-claude/send.lua
./lua/nvim-claude/terminal.lua
./plugin/nvim-claude.lua
./scripts/statusline.sh
```

- [ ] **Step 2: Verify context writing in Neovim**

Open Neovim, open a Lua file, and check:
```
:lua require('nvim-claude').setup()
:e lua/nvim-claude/init.lua
:lua print(require('nvim-claude.context').get_context_path())
```
Then verify the JSON file exists and has correct content:
```bash
cat /tmp/nvim-claude/*.json | jq .
```

- [ ] **Step 3: Verify hook script works with real context**

```bash
# After step 2 created a context file:
NVIM_CLAUDE_CONTEXT_FILE=$(ls /tmp/nvim-claude/*.json | head -1) \
  echo '{"user_prompt":"what does this do?"}' | \
  bash hooks/scripts/user-prompt-submit.sh | jq .
```
Expected: JSON with systemMessage containing the file contents.

- [ ] **Step 4: Verify env var is passed on terminal launch**

In Neovim:
```
:lua require('nvim-claude').setup({ claude_command = 'env | grep NVIM_CLAUDE', prefer_tmux = false })
:ClaudeToggle
```
Expected: Terminal shows `NVIM_CLAUDE_SERVER=...` and `NVIM_CLAUDE_CONTEXT_FILE=...`.

- [ ] **Step 5: Commit any fixes**

```bash
git add -A
git commit -m "fix: address issues found during end-to-end testing"
```
