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
