local server = require("nvim-claude.ide.server")
local lockfile = require("nvim-claude.ide.lockfile")

local M = {}
local state = { lockfile_path = nil, port = nil, auth_token = nil, connected = false }

local function random_token()
  local out = {}
  for i = 1, 32 do out[i] = string.format("%02x", math.random(0, 255)) end
  return table.concat(out)
end

local function send_response(client, id, result)
  server.send(client, vim.fn.json_encode({ jsonrpc = "2.0", id = id, result = result }))
end

local function handle_message(client, payload)
  local ok, msg = pcall(vim.fn.json_decode, payload)
  if not ok then return end

  if msg.method == "initialize" then
    state.connected = true
    send_response(client, msg.id, {
      protocolVersion = "2024-11-05",
      capabilities = {
        logging = vim.empty_dict(),
        prompts = { listChanged = true },
        resources = { subscribe = true, listChanged = true },
        tools = { listChanged = true },
      },
      serverInfo = { name = "nvim-claude", version = "0.8.0" },
    })
    return
  end

  if msg.method == "notifications/initialized" then
    return -- no-op, no response
  end

  if msg.method == "prompts/list" then
    send_response(client, msg.id, { prompts = {} })
    return
  end

  if msg.method == "tools/list" then
    -- Phase 0: no tools registered yet. Phase 1 wires the dispatcher.
    send_response(client, msg.id, { tools = {} })
    return
  end
end

function M.start()
  math.randomseed((vim.uv or vim.loop).hrtime() % 2^31)
  lockfile.reap_stale()
  local token = random_token()
  local port = server.start({ on_message = handle_message, auth_token = token })
  state.port = port
  state.auth_token = token
  state.lockfile_path = lockfile.write({
    port = port,
    pid = vim.fn.getpid(),
    workspaceFolders = { vim.fn.getcwd() },
    ideName = "Neovim",
    transport = "ws",
    authToken = token,
  })
  vim.api.nvim_create_autocmd("VimLeavePre", {
    once = true,
    callback = function() M.stop() end,
  })
end

function M.stop()
  if state.lockfile_path then lockfile.remove(state.lockfile_path) end
  server.stop()
  state.connected = false
  state.port = nil
  state.auth_token = nil
end

function M.is_connected() return state.connected end
function M.port() return state.port end
function M.state() return state end

return M
