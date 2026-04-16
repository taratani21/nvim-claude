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
  state.direction = direction
end

local function close_tmux()
  if state.tmux_pane then
    vim.fn.system("tmux kill-pane -t " .. state.tmux_pane)
    state.tmux_pane = nil
  end
end

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

return M
