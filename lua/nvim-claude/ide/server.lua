local uv = vim.uv or vim.loop
local ws = require("nvim-claude.ide.websocket")

local M = {}
local state = { server = nil, port = nil, clients = {}, on_message = nil, auth_token = nil }

local function http_response(status, body)
  return ("HTTP/1.1 %s\r\nContent-Length: %d\r\n\r\n%s"):format(status, #body, body)
end

local function ws_accept_key(client_key)
  -- Validate: key is supposed to be base64 (RFC 6455). Refuse anything that
  -- could break out of the shell-quoted printf below.
  if not client_key:match("^[A-Za-z0-9+/=]+$") then
    return nil
  end
  local guid = "258EAFA5-E914-47DA-95CA-C5AB0DC85B11"
  -- SHA1 + Base64; nvim has neither built-in. Shell out to openssl.
  local cmd = ("printf %%s '%s%s' | openssl dgst -binary -sha1 | openssl base64"):format(client_key, guid)
  local f = assert(io.popen(cmd))
  local out = f:read("*a"):gsub("%s", "")
  f:close()
  return out
end

--- Header lookup is case-insensitive per RFC 7230.
local function header(request, name)
  for line in request:gmatch("[^\r\n]+") do
    local k, v = line:match("^([^:]+):%s*(.+)$")
    if k and k:lower() == name:lower() then
      return v
    end
  end
  return nil
end

local function handle_handshake(client, request)
  local key = header(request, "Sec-WebSocket-Key")
  -- PROTOCOL.md: custom auth header, NOT standard Authorization.
  local auth = header(request, "x-claude-code-ide-authorization")
  local subprotocol = header(request, "Sec-WebSocket-Protocol")

  if not key then
    client:write(http_response("400 Bad Request", "missing Sec-WebSocket-Key"))
    client:close()
    return false
  end
  if state.auth_token and auth ~= state.auth_token then
    client:write(http_response("401 Unauthorized", "bad token"))
    client:close()
    return false
  end

  local accept = ws_accept_key(key)
  if not accept then
    client:write(http_response("400 Bad Request", "invalid Sec-WebSocket-Key"))
    client:close()
    return false
  end
  local response = "HTTP/1.1 101 Switching Protocols\r\n"
    .. "Upgrade: websocket\r\n"
    .. "Connection: Upgrade\r\n"
    .. "Sec-WebSocket-Accept: " .. accept .. "\r\n"
  if subprotocol then
    response = response .. "Sec-WebSocket-Protocol: " .. subprotocol .. "\r\n"
  end
  response = response .. "\r\n"
  client:write(response)
  return true
end

local function on_client_data(client, buf, chunk)
  buf = buf .. chunk
  if not client._upgraded then
    if buf:find("\r\n\r\n", 1, true) then
      if handle_handshake(client, buf) then
        client._upgraded = true
        return ""
      end
    end
    return buf
  end
  while true do
    local frame, rest = ws.decode_frame(buf)
    if not frame then return buf end
    buf = rest
    -- Both TEXT (0x1) and BINARY (0x2) treated as text payloads per PROTOCOL.md.
    if (frame.opcode == 0x1 or frame.opcode == 0x2) and state.on_message then
      pcall(state.on_message, client, frame.payload)
    elseif frame.opcode == 0x8 then
      client:close()
      return ""
    elseif frame.opcode == 0x9 then
      -- PING → respond with PONG echoing payload
      pcall(function()
        client:write(ws.encode_frame({ opcode = 0xA, payload = frame.payload or "", fin = true }))
      end)
    end
  end
end

local function pick_port()
  -- PROTOCOL.md restricts port range to 10000–65535. Try a few candidates.
  for _ = 1, 50 do
    local candidate = math.random(10000, 65535)
    local probe = uv.new_tcp()
    local ok = pcall(function() probe:bind("127.0.0.1", candidate) end)
    probe:close()
    if ok then return candidate end
  end
  error("could not find a free port in 10000-65535")
end

function M.start(opts)
  state.on_message = opts.on_message
  state.auth_token = opts.auth_token
  local port = pick_port()
  state.server = uv.new_tcp()
  state.server:bind("127.0.0.1", port)
  state.server:listen(8, function(err)
    assert(not err, err)
    local client = uv.new_tcp()
    state.server:accept(client)
    if #state.clients > 0 then
      -- v1 limitation: only one Claude Code session per nvim. Refuse extra.
      pcall(function()
        client:write(http_response("503 Service Unavailable", "another client is already connected"))
        client:close()
      end)
      return
    end
    local read_buf = ""
    client:read_start(function(read_err, chunk)
      if read_err or not chunk then
        -- Remove from clients list before closing so broadcast doesn't fire on dead handles.
        for i, c in ipairs(state.clients) do
          if c == client then table.remove(state.clients, i); break end
        end
        pcall(function() client:close() end)
        return
      end
      read_buf = on_client_data(client, read_buf, chunk)
    end)
    table.insert(state.clients, client)
  end)
  state.port = port
  return port
end

function M.stop()
  for _, c in ipairs(state.clients) do pcall(function() c:close() end) end
  state.clients = {}
  if state.server then state.server:close() end
  state.server = nil
  state.port = nil
end

function M.send(client, text)
  local frame = ws.encode_frame({ opcode = 0x1, payload = text, fin = true })
  client:write(frame)
end

function M.broadcast(text)
  for _, c in ipairs(state.clients) do
    pcall(M.send, c, text)
  end
end

function M.port() return state.port end

return M
