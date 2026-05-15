local M = {
  name = "getCurrentSelection",
  description = "Return the current visual selection or cursor position in the active nvim buffer.",
  input_schema = { type = "object", properties = vim.empty_dict() },
}

local function active_file_buffer()
  local buf = vim.api.nvim_get_current_buf()
  if vim.bo[buf].buftype ~= "" then return nil end
  local file = vim.api.nvim_buf_get_name(buf)
  if file == "" then return nil end
  return buf, file
end

local function visual_range()
  local mode = vim.fn.mode()
  if mode ~= "v" and mode ~= "V" and mode ~= "\22" then
    return nil
  end
  local s = vim.fn.getpos("v")
  local e = vim.fn.getpos(".")
  -- Normalize so s <= e.
  if s[2] > e[2] or (s[2] == e[2] and s[3] > e[3]) then
    s, e = e, s
  end
  return s, e
end

local function as_text(payload)
  return { content = { { type = "text", text = vim.json.encode(payload) } } }
end

function M.handler(_)
  local buf, file = active_file_buffer()
  if not buf then
    return as_text({ success = false, message = "No active file buffer" })
  end

  local s_pos, e_pos = visual_range()
  local text = ""
  -- 0-indexed line/character, LSP-style
  local start_line, start_char, end_line, end_char
  local is_empty

  if s_pos then
    start_line = s_pos[2] - 1
    start_char = s_pos[3] - 1
    end_line   = e_pos[2] - 1
    end_char   = e_pos[3] - 1
    is_empty = (start_line == end_line and start_char == end_char)
    local lines = vim.api.nvim_buf_get_lines(buf, start_line, end_line + 1, false)
    text = table.concat(lines, "\n")
  else
    local cur = vim.api.nvim_win_get_cursor(0)  -- {1-indexed line, 0-indexed col}
    start_line = cur[1] - 1
    start_char = cur[2]
    end_line = start_line
    end_char = start_char
    is_empty = true
  end

  return as_text({
    success = true,
    text = text,
    filePath = file,
    selection = {
      start = { line = start_line, character = start_char },
      ["end"] = { line = end_line, character = end_char },
      isEmpty = is_empty,
    },
  })
end

return M
