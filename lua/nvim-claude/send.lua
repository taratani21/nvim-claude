local M = {}

local function get_visual_selection()
  local start_pos = vim.fn.getpos("'<")
  local end_pos = vim.fn.getpos("'>")
  local start_line = start_pos[2]
  local end_line = end_pos[2]

  local lines = vim.api.nvim_buf_get_lines(0, start_line - 1, end_line, false)
  return {
    text = table.concat(lines, "\n"),
    start_line = start_line,
    end_line = end_line,
  }
end

local function format_selection(selection)
  local file = vim.fn.expand("%:.")  -- relative path
  local ft = vim.bo.filetype

  local header = string.format("File: %s, Lines %d-%d", file, selection.start_line, selection.end_line)
  return "[Code Context]\n" .. header .. "\n```" .. ft .. "\n" .. selection.text .. "\n```\n\n[Query]\n"
end

function M.send_selection()
  local terminal = require("nvim-claude.terminal")

  if not terminal.is_open() then
    terminal.open("vertical")
  end

  local selection = get_visual_selection()
  if selection.text == "" then
    return
  end

  local text = format_selection(selection)

  local state = terminal.get_state()

  if terminal.use_tmux() then
    -- escape special characters for tmux send-keys
    local escaped = text:gsub("'", "'\\''")
    vim.fn.system(string.format("tmux send-keys -t %s '%s'", state.tmux_pane, escaped))
    vim.fn.system(string.format("tmux select-pane -t %s", state.tmux_pane))
  else
    if state.chan then
      vim.api.nvim_chan_send(state.chan, text)
    end
    if state.win and vim.api.nvim_win_is_valid(state.win) then
      vim.api.nvim_set_current_win(state.win)
    end
  end
end

return M
