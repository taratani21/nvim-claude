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
