local M = {}

function M.open_turn_diff()
  local context = require("nvim-claude.context")
  local base_dir = vim.fn.fnamemodify(context.get_context_path(), ":h")
  local baseline_file = base_dir .. "/turn-baseline.sha"

  if vim.fn.filereadable(baseline_file) ~= 1 then
    vim.notify("nvim-claude: no turn baseline found", vim.log.levels.INFO)
    return
  end

  local sha = vim.fn.trim(vim.fn.readfile(baseline_file)[1] or "")
  if sha == "" then
    vim.notify("nvim-claude: empty baseline", vim.log.levels.INFO)
    return
  end

  vim.cmd("DiffviewOpen " .. sha)
end

return M
