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

vim.api.nvim_create_user_command("ClaudeDiff", function()
  local context = require("nvim-claude.context")
  local context_dir = require("nvim-claude").config.context.context_dir or "/tmp/nvim-claude"
  local context_path = context.get_context_path()
  local base_dir = vim.fn.fnamemodify(context_path, ":h")
  local manifest = base_dir .. "/manifest.json"
  local snapshot_dir = base_dir .. "/snapshots"
  require("nvim-claude.diff").open_turn_diffs(manifest, snapshot_dir)
end, { desc = "Show diffs from last Claude turn" })
