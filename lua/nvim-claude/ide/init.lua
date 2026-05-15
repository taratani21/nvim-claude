local server = require("nvim-claude.ide.server")
local lockfile = require("nvim-claude.ide.lockfile")

local M = {}
local state = { lockfile_path = nil, port = nil, auth_token = nil, connected = false }

-- Debug log path; tail with `tail -f /tmp/nvim-claude-ide.log` while testing.
local DEBUG_LOG = "/tmp/nvim-claude-ide.log"
local function dlog(msg)
  local f = io.open(DEBUG_LOG, "a")
  if not f then return end
  f:write(os.date("%H:%M:%S ") .. msg .. "\n")
  f:close()
end

local function random_token()
  local out = {}
  for i = 1, 32 do out[i] = string.format("%02x", math.random(0, 255)) end
  return table.concat(out)
end

local function send_response(client, id, result)
  local payload = vim.json.encode({ jsonrpc = "2.0", id = id, result = result })
  dlog("SEND " .. payload)
  server.send(client, payload)
end

local function handle_message(client, payload)
  dlog("RECV " .. payload)
  local ok, msg = pcall(vim.json.decode, payload)
  if not ok then
    dlog("PARSE_ERR " .. tostring(msg))
    return
  end

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

  if msg.method == "notifications/initialized" or msg.method == "ide_connected" then
    return -- no-op notifications, no response
  end

  if msg.method == "prompts/list" then
    send_response(client, msg.id, { prompts = {} })
    return
  end

  if msg.method == "resources/list" then
    send_response(client, msg.id, { resources = {} })
    return
  end

  if msg.method == "tools/list" then
    -- Phase 0: no tools registered yet. Phase 1 wires the dispatcher.
    send_response(client, msg.id, { tools = {} })
    return
  end

  dlog("UNHANDLED method=" .. tostring(msg.method))
end

function M.start()
  -- Truncate debug log on each start.
  local f = io.open(DEBUG_LOG, "w")
  if f then f:close() end

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
  dlog(string.format("STARTED port=%d pid=%d cwd=%s lockfile=%s",
    port, vim.fn.getpid(), vim.fn.getcwd(), state.lockfile_path))
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
