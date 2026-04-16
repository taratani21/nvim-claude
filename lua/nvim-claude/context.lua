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

function M.write_context()
  if not is_file_buffer() then
    return
  end

  local file = vim.fn.expand("%:.")
  local abs_file = vim.api.nvim_buf_get_name(0)
  local ft = vim.bo.filetype
  local cwd = vim.fn.getcwd()
  local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
  local contents = table.concat(lines, "\n")

  local context = {
    file = file,
    filetype = ft,
    cwd = cwd,
    contents = contents,
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
  local path = M.get_context_path()
  os.remove(path)
end

function M.register_autocmds()
  local group = vim.api.nvim_create_augroup("nvim-claude-context", { clear = true })

  vim.api.nvim_create_autocmd({ "BufEnter", "BufWritePost" }, {
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
