local M = {}

M.config = {
  split_direction = "vertical",
  split_size = 80,
  claude_command = "claude",
  prefer_tmux = true,
}

function M.setup(opts)
  M.config = vim.tbl_deep_extend("force", M.config, opts or {})

  -- Default keybindings
  vim.keymap.set("n", "<leader>ct", "<cmd>ClaudeToggle<cr>", { desc = "Toggle Claude Code" })
  vim.keymap.set("n", "<leader>cv", "<cmd>ClaudeVSplit<cr>", { desc = "Claude Code vertical split" })
  vim.keymap.set("n", "<leader>ch", "<cmd>ClaudeHSplit<cr>", { desc = "Claude Code horizontal split" })
  vim.keymap.set("v", "<leader>cs", "<cmd>ClaudeSend<cr>", { desc = "Send selection to Claude Code" })
end

return M
