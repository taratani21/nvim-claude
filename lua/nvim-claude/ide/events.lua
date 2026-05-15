local server = require("nvim-claude.ide.server")

local M = {}
local state = { last_push_at = 0, throttle_ms = 100 }

function M.set_throttle(ms) state.throttle_ms = ms end

local function now_ms()
  return math.floor((vim.uv or vim.loop).hrtime() / 1e6)
end

local function active_file_buffer()
  local buf = vim.api.nvim_get_current_buf()
  if vim.bo[buf].buftype ~= "" then return nil end
  local file = vim.api.nvim_buf_get_name(buf)
  if file == "" then return nil end
  return buf, file
end

local function visual_range()
  local mode = vim.fn.mode()
  if mode ~= "v" and mode ~= "V" and mode ~= "\22" then
    return nil
  end
  local s = vim.fn.getpos("v")
  local e = vim.fn.getpos(".")
  if s[2] > e[2] or (s[2] == e[2] and s[3] > e[3]) then s, e = e, s end
  return s, e
end

local function build_selection_payload()
  local buf, file = active_file_buffer()
  if not buf then return nil end

  local s_pos, e_pos = visual_range()
  local text = ""
  local start_line, start_char, end_line, end_char, is_empty

  if s_pos then
    start_line = s_pos[2] - 1
    start_char = s_pos[3] - 1
    end_line   = e_pos[2] - 1
    end_char   = e_pos[3] - 1
    is_empty = (start_line == end_line and start_char == end_char)
    local lines = vim.api.nvim_buf_get_lines(buf, start_line, end_line + 1, false)
    text = table.concat(lines, "\n")
  else
    local cur = vim.api.nvim_win_get_cursor(0)
    start_line = cur[1] - 1
    start_char = cur[2]
    end_line = start_line
    end_char = start_char
    is_empty = true
  end

  return {
    text = text,
    filePath = file,
    fileUrl = "file://" .. file,
    selection = {
      start = { line = start_line, character = start_char },
      ["end"] = { line = end_line, character = end_char },
      isEmpty = is_empty,
    },
  }
end

local function push_selection()
  local params = build_selection_payload()
  if not params then return end
  local notif = vim.json.encode({
    jsonrpc = "2.0",
    method = "selection_changed",
    params = params,
  })
  server.broadcast(notif)
end

local function throttled_push()
  local t = now_ms()
  if t - state.last_push_at < state.throttle_ms then return end
  state.last_push_at = t
  push_selection()
end

function M.register()
  local group = vim.api.nvim_create_augroup("nvim-claude-ide-events", { clear = true })
  vim.api.nvim_create_autocmd({ "BufEnter", "CursorMoved", "CursorMovedI", "ModeChanged" }, {
    group = group,
    callback = function() throttled_push() end,
  })
end

--- Send one selection event immediately, ignoring throttle.
--- Useful right after a client connects so Claude's TUI gets initial state.
function M.push_now() push_selection() end

return M
