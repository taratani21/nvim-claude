local M = {}

local function get_context_dir()
  local config = require("nvim-claude").config
  return (config.context and config.context.context_dir) or "/tmp/nvim-claude"
end

local function get_hash()
  local servername = vim.v.servername
  -- simple hash: replace non-alphanumeric chars with dashes
  return servername:gsub("[^%w]", "-"):gsub("^-+", ""):gsub("-+$", "")
end

function M.get_context_path()
  return get_context_dir() .. "/" .. get_hash() .. ".json"
end

function M.get_servername()
  return vim.v.servername
end

local function is_file_buffer()
  if vim.bo.buftype ~= "" then
    return false
  end
  local file = vim.api.nvim_buf_get_name(0)
  if file == "" then
    return false
  end
  if vim.fn.filereadable(file) ~= 1 then
    return false
  end
  return true
end

local function get_diagnostics()
  local buf = vim.api.nvim_get_current_buf()
  local diags = vim.diagnostic.get(buf)
  local result = {}
  local severity_map = { "error", "warning", "info", "hint" }

  for _, d in ipairs(diags) do
    table.insert(result, {
      line = d.lnum + 1,
      severity = severity_map[d.severity] or "unknown",
      message = d.message,
    })
  end
  return result
end

function M.write_context()
  if not is_file_buffer() then
    return
  end

  local file = vim.fn.expand("%:.")
  local ft = vim.bo.filetype
  local cwd = vim.fn.getcwd()

  local context = {
    file = file,
    filetype = ft,
    cwd = cwd,
    diagnostics = get_diagnostics(),
    timestamp = os.time(),
  }

  local dir = get_context_dir()
  vim.fn.mkdir(dir, "p")

  local json = vim.fn.json_encode(context)
  local path = M.get_context_path()
  local f = io.open(path, "w")
  if f then
    f:write(json)
    f:close()
  end
end

function M.delete_context()
  local base_dir = vim.fn.fnamemodify(M.get_context_path(), ":h")
  os.remove(M.get_context_path())
  os.remove(base_dir .. "/manifest.json")
  os.remove(base_dir .. "/turn-baseline.sha")
  os.remove(base_dir .. "/turn-diff.patch")
  vim.fn.delete(base_dir .. "/snapshots", "rf")
end

function M.register_autocmds()
  local group = vim.api.nvim_create_augroup("nvim-claude-context", { clear = true })

  vim.api.nvim_create_autocmd({ "BufEnter", "BufWritePost", "DiagnosticChanged" }, {
    group = group,
    callback = function()
      M.write_context()
    end,
  })

  vim.api.nvim_create_autocmd("VimLeavePre", {
    group = group,
    callback = function()
      M.delete_context()
    end,
  })
end

return M
