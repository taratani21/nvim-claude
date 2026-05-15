local M = {
  name = "checkDocumentDirty",
  description = "Check if the buffer for the given file path has unsaved changes.",
  input_schema = {
    type = "object",
    properties = {
      filePath = { type = "string", description = "Absolute path of the file to check." },
    },
    required = { "filePath" },
  },
}

local function as_text(payload)
  return { content = { { type = "text", text = vim.json.encode(payload) } } }
end

local function find_buf_for_path(path)
  for _, buf in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_get_name(buf) == path then
      return buf
    end
  end
  return nil
end

function M.handler(args)
  local path = args and args.filePath
  if not path or path == "" then
    return as_text({ success = false, message = "filePath is required" })
  end

  local buf = find_buf_for_path(path)
  if not buf then
    return as_text({ success = false, message = "No buffer found for: " .. path })
  end

  return as_text({
    success = true,
    filePath = path,
    isDirty = vim.bo[buf].modified,
    isUntitled = (vim.api.nvim_buf_get_name(buf) == ""),
  })
end

return M
