local M = {
  name = "openFile",
  description = "Open a file in the editor.",
  input_schema = {
    type = "object",
    properties = {
      filePath          = { type = "string" },
      preview           = { type = "boolean" },
      -- v1: startText, endText, selectToEndOfLine are accepted but not yet
      -- implemented (text-based cursor positioning is deferred to a later
      -- iteration; positional navigation via line numbers comes first).
      startText         = { type = "string" },
      endText           = { type = "string" },
      selectToEndOfLine = { type = "boolean" },
      makeFrontmost     = { type = "boolean" },
    },
    required = { "filePath" },
  },
}

local function as_text(text)
  return { content = { { type = "text", text = text } } }
end

function M.handler(args)
  local path = args.filePath
  if not path or path == "" then
    return as_text(vim.json.encode({ success = false, message = "filePath required" }))
  end

  local make_frontmost = args.makeFrontmost
  if make_frontmost == nil then make_frontmost = true end

  -- Open the file. :edit handles it cleanly even if the buffer already exists.
  local ok, err = pcall(vim.cmd, "edit " .. vim.fn.fnameescape(path))
  if not ok then
    return as_text(vim.json.encode({ success = false, message = tostring(err) }))
  end

  if make_frontmost then
    return as_text("Opened file: " .. path)
  end

  local buf = vim.api.nvim_get_current_buf()
  local payload = {
    success    = true,
    filePath   = path,
    languageId = vim.bo[buf].filetype,
    lineCount  = vim.api.nvim_buf_line_count(buf),
  }
  return as_text(vim.json.encode(payload))
end

return M
