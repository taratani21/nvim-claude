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
