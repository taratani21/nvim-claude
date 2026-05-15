local M = {
  name = "getDiagnostics",
  description = "Get LSP diagnostics for a single file (by URI) or all open files.",
  input_schema = {
    type = "object",
    properties = {
      uri = { type = "string", description = "Optional file URI (file://...). Omit for all files." },
    },
  },
}

local SEVERITY = { "Error", "Warning", "Information", "Hint" }

local function uri_to_path(uri)
  if not uri then return nil end
  -- strip file:// prefix
  return (uri:gsub("^file://", ""))
end

local function path_to_uri(path)
  return "file://" .. path
end

local function buf_for_path(path)
  for _, b in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_loaded(b) and vim.api.nvim_buf_get_name(b) == path then
      return b
    end
  end
end

local function diags_for_buf(buf)
  local file = vim.api.nvim_buf_get_name(buf)
  if file == "" then return nil end
  local out = {}
  for _, d in ipairs(vim.diagnostic.get(buf)) do
    table.insert(out, {
      message = d.message,
      severity = SEVERITY[d.severity] or "Information",
      range = {
        start = { line = d.lnum, character = d.col },
        ["end"] = { line = d.end_lnum or d.lnum, character = d.end_col or d.col },
      },
      source = d.source,
    })
  end
  return { uri = path_to_uri(file), diagnostics = out }
end

function M.handler(args)
  local results = {}

  if args and args.uri and args.uri ~= "" then
    local path = uri_to_path(args.uri)
    local b = buf_for_path(path)
    if b then
      local entry = diags_for_buf(b)
      if entry then table.insert(results, entry) end
    end
  else
    for _, b in ipairs(vim.api.nvim_list_bufs()) do
      if vim.api.nvim_buf_is_loaded(b) and vim.bo[b].buftype == "" then
        local entry = diags_for_buf(b)
        if entry then table.insert(results, entry) end
      end
    end
  end

  return { content = { { type = "text", text = vim.json.encode(results) } } }
end

return M
