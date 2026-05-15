local M = {
  name = "closeAllDiffTabs",
  description = "Close all editor tabs that contain a diff view.",
  input_schema = { type = "object", properties = vim.empty_dict() },
}

function M.handler(_)
  local closed = 0
  -- Iterate in reverse so closing earlier tabs doesn't invalidate later refs.
  local tabs = vim.api.nvim_list_tabpages()
  for i = #tabs, 1, -1 do
    local tab = tabs[i]
    local has_diff = false
    for _, win in ipairs(vim.api.nvim_tabpage_list_wins(tab)) do
      if vim.wo[win].diff then has_diff = true; break end
    end
    if has_diff then
      pcall(vim.cmd, "tabclose " .. vim.api.nvim_tabpage_get_number(tab))
      closed = closed + 1
    end
  end
  return { content = { { type = "text", text = "CLOSED_" .. closed .. "_DIFF_TABS" } } }
end

return M
