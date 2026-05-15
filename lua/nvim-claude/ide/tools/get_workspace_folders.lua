local M = {
  name = "getWorkspaceFolders",
  description = "List workspace root directories.",
  input_schema = { type = "object", properties = vim.empty_dict() },
}

function M.handler(_)
  local cwd = vim.fn.getcwd()
  local payload = {
    success = true,
    folders = {
      {
        name = vim.fn.fnamemodify(cwd, ":t"),
        uri = "file://" .. cwd,
        path = cwd,
      },
    },
    rootPath = cwd,
  }
  return {
    content = { { type = "text", text = vim.json.encode(payload) } },
  }
end

return M
