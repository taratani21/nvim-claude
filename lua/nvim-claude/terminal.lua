local M = {}

local STASH_SESSION = "nvim-claude-stash"

local state = {
  -- nvim mode
  buf = nil,
  win = nil,
  chan = nil,
  -- tmux mode
  tmux_pane = nil,
  tmux_hidden = false,
  -- shared
  direction = nil,
}

function M.is_tmux()
  return vim.env.TMUX ~= nil
end

function M.use_tmux()
  local config = require("nvim-claude").config
  return config.prefer_tmux and M.is_tmux()
end

local function tmux_pane_exists(pane_id)
  if not pane_id then
    return false
  end
  local out = vim.fn.system({ "tmux", "list-panes", "-a", "-F", "#{pane_id}" })
  for line in (out or ""):gmatch("[^\n]+") do
    if line == pane_id then
      return true
    end
  end
  return false
end

-- Alive anywhere — visible or hidden.
function M.is_alive()
  if M.use_tmux() then
    if not state.tmux_pane then
      return false
    end
    if tmux_pane_exists(state.tmux_pane) then
      return true
    end
    state.tmux_pane = nil
    state.tmux_hidden = false
    return false
  end
  return state.buf ~= nil and vim.api.nvim_buf_is_valid(state.buf)
end

-- Currently visible (a window/pane the user can see).
function M.is_open()
  if M.use_tmux() then
    return M.is_alive() and not state.tmux_hidden
  end
  return state.win ~= nil and vim.api.nvim_win_is_valid(state.win)
end

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
  local context = require("nvim-claude.context")
  local size = get_size(direction)

  if direction == "vertical" then
    vim.cmd(size .. "vsplit")
  else
    vim.cmd("botright " .. size .. "split")
  end

  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_win_set_buf(0, buf)
  -- Keep the buffer alive across hide/show cycles.
  vim.bo[buf].bufhidden = "hide"

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

local function hide_nvim()
  if state.win and vim.api.nvim_win_is_valid(state.win) then
    vim.api.nvim_win_close(state.win, false)
  end
  state.win = nil
end

local function show_nvim()
  if not (state.buf and vim.api.nvim_buf_is_valid(state.buf)) then
    return false
  end
  local size = get_size(state.direction)
  if state.direction == "vertical" then
    vim.cmd(size .. "vsplit")
  else
    vim.cmd("botright " .. size .. "split")
  end
  vim.api.nvim_win_set_buf(0, state.buf)
  state.win = vim.api.nvim_get_current_win()
  return true
end

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
  state.tmux_hidden = false
  state.direction = direction
end

local function ensure_stash_session()
  vim.fn.system({ "tmux", "has-session", "-t", STASH_SESSION })
  if vim.v.shell_error ~= 0 then
    vim.fn.system({ "tmux", "new-session", "-d", "-s", STASH_SESSION })
  end
end

local function hide_tmux()
  if not state.tmux_pane or state.tmux_hidden then
    return
  end
  ensure_stash_session()
  vim.fn.system({
    "tmux", "break-pane", "-d",
    "-s", state.tmux_pane,
    "-t", STASH_SESSION .. ":",
  })
  state.tmux_hidden = true
end

local function show_tmux()
  if not state.tmux_pane or not state.tmux_hidden then
    return
  end
  -- Place the pane next to the nvim pane in the same window.
  local nvim_pane = vim.env.TMUX_PANE
  if not nvim_pane or nvim_pane == "" then
    nvim_pane = vim.fn.trim(vim.fn.system({ "tmux", "display-message", "-p", "#{pane_id}" }))
  end
  local size = get_size(state.direction)
  local flag = state.direction == "vertical" and "-h" or "-v"
  vim.fn.system({
    "tmux", "join-pane",
    "-s", state.tmux_pane,
    "-t", nvim_pane,
    flag, "-l", tostring(size),
  })
  state.tmux_hidden = false
end

local function close_tmux()
  if state.tmux_pane then
    vim.fn.system({ "tmux", "kill-pane", "-t", state.tmux_pane })
    state.tmux_pane = nil
    state.tmux_hidden = false
  end
end

function M.open(direction)
  local config = require("nvim-claude").config
  direction = direction or config.split_direction

  if M.is_alive() then
    M.close()
  end

  if M.use_tmux() then
    open_tmux(direction)
  else
    open_nvim(direction)
  end
end

function M.hide()
  if not M.is_open() then
    return
  end
  if M.use_tmux() then
    hide_tmux()
  else
    hide_nvim()
  end
end

function M.show()
  if M.is_open() then
    return
  end
  if not M.is_alive() then
    M.open(state.direction)
    return
  end
  if M.use_tmux() then
    show_tmux()
  else
    show_nvim()
  end
end

function M.close()
  if M.use_tmux() then
    close_tmux()
  else
    close_nvim()
  end
end

-- Toggle visibility — keeps the session alive across hide/show.
-- If no session exists, opens a fresh one.
function M.toggle()
  if M.is_open() then
    M.hide()
  elseif M.is_alive() then
    M.show()
  else
    local config = require("nvim-claude").config
    M.open(state.direction or config.split_direction)
  end
end

function M.get_state()
  return state
end

return M
