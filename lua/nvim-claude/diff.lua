local M = {}

function M.open_diff(snapshot_path, current_path, label)
  -- Open a new tab with the current file
  vim.cmd("tabnew " .. vim.fn.fnameescape(current_path))
  vim.cmd("diffthis")

  -- Open the snapshot in a vertical split
  vim.cmd("vsplit " .. vim.fn.fnameescape(snapshot_path))
  vim.api.nvim_buf_set_option(0, "buftype", "nofile")
  vim.api.nvim_buf_set_option(0, "bufhidden", "wipe")
  vim.api.nvim_buf_set_option(0, "modifiable", false)

  -- Set a readable name for the snapshot buffer
  local buf_name = (label or "before") .. " (before claude)"
  pcall(vim.api.nvim_buf_set_name, 0, buf_name)

  vim.cmd("diffthis")

  -- Focus the current file (right side)
  vim.cmd("wincmd l")
end

function M.open_turn_diffs(manifest_path, snapshot_dir)
  if vim.fn.filereadable(manifest_path) ~= 1 then
    vim.notify("nvim-claude: no changes to diff", vim.log.levels.INFO)
    return
  end

  local content = vim.fn.readfile(manifest_path)
  local files = vim.fn.json_decode(table.concat(content, "\n"))

  if not files or #files == 0 then
    vim.notify("nvim-claude: no changes to diff", vim.log.levels.INFO)
    return
  end

  local opened = 0
  for _, file_path in ipairs(files) do
    local safe_name = file_path:gsub("/", "__")
    local snapshot = snapshot_dir .. "/" .. safe_name

    if vim.fn.filereadable(snapshot) == 1 then
      M.open_diff(snapshot, file_path, file_path)
      opened = opened + 1
    end
  end

  if opened > 0 then
    vim.notify(string.format("nvim-claude: opened %d diff tab(s)", opened), vim.log.levels.INFO)
  end
end

return M
