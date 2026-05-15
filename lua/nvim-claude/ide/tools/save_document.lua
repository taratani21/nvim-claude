local M = {
  name = "saveDocument",
  description = "Save the buffer for the given file path if it has unsaved changes.",
  input_schema = {
    type = "object",
    properties = {
      filePath = { type = "string", description = "Absolute path of the file to save." },
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

  if not vim.bo[buf].modified then
    return as_text({ success = true, filePath = path, saved = false, message = "not dirty" })
  end

  local ok, err = pcall(vim.api.nvim_buf_call, buf, function()
    vim.cmd("write")
  end)
  if not ok then
    return as_text({ success = false, message = tostring(err) })
  end

  return as_text({ success = true, filePath = path, saved = true, message = "saved" })
end

return M
