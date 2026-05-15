local M = {}

local function read_sha(path)
  if vim.fn.filereadable(path) ~= 1 then
    return ""
  end
  return vim.fn.trim(vim.fn.readfile(path)[1] or "")
end

function M.open_turn_diff()
  local context = require("nvim-claude.context")
  local base_dir = vim.fn.fnamemodify(context.get_context_path(), ":h")

  local baseline = read_sha(base_dir .. "/turn-baseline.sha")
  if baseline == "" then
    vim.notify("nvim-claude: no turn baseline found", vim.log.levels.INFO)
    return
  end

  local current = read_sha(base_dir .. "/turn-current.sha")

  -- Ensure diffview is loaded (may be lazy-loaded)
  require("diffview")

  -- Close existing diffview if open, then open fresh.
  -- When a current snapshot exists, diff baseline..current so new untracked
  -- files Claude created show up (diffview hardcodes hiding untracked when
  -- comparing a commit against the working tree). Otherwise fall back to
  -- baseline vs working tree.
  pcall(vim.cmd, "DiffviewClose")
  if current ~= "" then
    vim.cmd("DiffviewOpen " .. baseline .. ".." .. current)
  else
    vim.cmd("DiffviewOpen " .. baseline)
  end
end

return M
