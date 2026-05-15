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
  ide = {
    enabled = true,
    auto_start = true,
  },
}

function M.setup(opts)
  M.config = vim.tbl_deep_extend("force", M.config, opts or {})

  -- Register context autocmds
  if M.config.context.enabled then
    require("nvim-claude.context").register_autocmds()
  end

  -- Start IDE WebSocket server
  if M.config.ide.enabled and M.config.ide.auto_start then
    local ok, err = pcall(require("nvim-claude.ide").start)
    if not ok then
      vim.notify("nvim-claude: IDE server failed to start: " .. tostring(err), vim.log.levels.WARN)
    end
  end

  -- Default keybindings
  vim.keymap.set("n", "<leader>ct", "<cmd>ClaudeToggle<cr>", { desc = "Toggle Claude Code visibility" })
  vim.keymap.set("n", "<leader>cv", "<cmd>ClaudeVSplit<cr>", { desc = "Claude Code vertical split" })
  vim.keymap.set("n", "<leader>ch", "<cmd>ClaudeHSplit<cr>", { desc = "Claude Code horizontal split" })
  vim.keymap.set("v", "<leader>cp", ":'<,'>ClaudeSend<cr>", { desc = "Send selection to Claude Code" })
  vim.keymap.set("n", "<leader>cd", "<cmd>ClaudeDiff<cr>", { desc = "Show diffs from last Claude turn" })
end

return M
