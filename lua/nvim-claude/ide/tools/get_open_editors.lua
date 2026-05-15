local M = {
  name = "getOpenEditors",
  description = "List open file buffers; mark the active one.",
  input_schema = { type = "object", properties = vim.empty_dict() },
}

function M.handler(_)
  local active = vim.api.nvim_get_current_buf()
  local tabs = {}
  for _, b in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_loaded(b) and vim.bo[b].buftype == "" then
      local file = vim.api.nvim_buf_get_name(b)
      if file ~= "" then
        table.insert(tabs, {
          uri = "file://" .. file,
          isActive = (b == active),
          label = vim.fn.fnamemodify(file, ":t"),
          languageId = vim.bo[b].filetype,
          isDirty = vim.bo[b].modified,
        })
      end
    end
  end
  return {
    content = { { type = "text", text = vim.json.encode({ tabs = tabs }) } },
  }
end

return M
