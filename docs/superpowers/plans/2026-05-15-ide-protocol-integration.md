# IDE Protocol Integration Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add WebSocket-based IDE protocol support to nvim-claude so Claude Code's TUI shows live nvim state (current file, selection) in its status line and can drive `openFile`/`openDiff` through standard tools, while preserving the existing tmux spawn UX and snapshot hooks.

**Architecture:** New `lua/nvim-claude/ide/` module owns: a `vim.uv` TCP server with WebSocket upgrade, a JSON-RPC 2.0 dispatcher, IDE-protocol MCP tool implementations, lockfile management at `~/.claude/ide/<pid>.lock`, and an autocmd-driven event publisher. Coexists with existing hooks (snapshot at turn boundary remains hook-based).

**Tech Stack:** Lua, `vim.uv` (libuv), nvim API, RFC 6455 (WebSocket), JSON-RPC 2.0. Borrows WS framing from `coder/claudecode.nvim` (Apache-2.0).

**Spec:** `docs/superpowers/specs/2026-05-15-ide-protocol-integration-design.md`

**Primary protocol reference:** [`coder/claudecode.nvim/PROTOCOL.md`](https://github.com/coder/claudecode.nvim/blob/main/PROTOCOL.md) — the maintained, community-documented spec of Claude Code's IDE protocol (lockfile schema, handshake, MCP tool surface, event method names). All "what does Claude Code expect here?" questions in this plan should consult that document first; only fall back to reading source code if the doc is silent.

---

## File Structure

### New files

| Path | Purpose |
|---|---|
| `lua/nvim-claude/ide/init.lua` | Public API: `start()`, `stop()`, `is_connected()`, `state()` |
| `lua/nvim-claude/ide/server.lua` | TCP listener, accepts WS upgrades, routes frames to RPC |
| `lua/nvim-claude/ide/websocket.lua` | RFC 6455 frame encode/decode, masking, ping/pong |
| `lua/nvim-claude/ide/rpc.lua` | JSON-RPC 2.0 envelope handling, tool registry, dispatch |
| `lua/nvim-claude/ide/lockfile.lua` | Write/read/cleanup `~/.claude/ide/<pid>.lock`, stale reaper |
| `lua/nvim-claude/ide/events.lua` | Autocmd subscriptions, throttled push notifications |
| `lua/nvim-claude/ide/tools/get_current_selection.lua` | Visual selection or cursor position |
| `lua/nvim-claude/ide/tools/get_open_editors.lua` | List file buffers, mark active |
| `lua/nvim-claude/ide/tools/get_workspace_folders.lua` | Wraps `vim.fn.getcwd()` |
| `lua/nvim-claude/ide/tools/get_diagnostics.lua` | Wraps `vim.diagnostic.get()` |
| `lua/nvim-claude/ide/tools/open_file.lua` | `:edit` + optional jump-to-line |
| `lua/nvim-claude/ide/tools/open_diff.lua` | Diff view between paths/content blobs |
| `tests/run.sh` | Test runner: invokes each `tests/*.lua` via `nvim --headless -l` |
| `tests/websocket_test.lua` | Frame encode/decode roundtrips |
| `tests/rpc_test.lua` | JSON-RPC envelope parsing |
| `tests/lockfile_test.lua` | Lockfile write/read/stale-reap |
| `NOTICE` | Apache-2.0 attribution for borrowed claudecode.nvim code |

### Modified files

| Path | Change |
|---|---|
| `lua/nvim-claude/init.lua` | Add `ide` config block, call `ide.start()` in `setup()` |
| `hooks/scripts/user-prompt-submit.sh` | Remove `[Active File: ...]` injection (Phase 3) |
| `hooks/scripts/session-start.sh` | Update guidance to describe IDE-protocol tools (Phase 3) |
| `.mcp.json` | Remove `open-in-nvim` entry (Phase 4) |
| `.claude-plugin/plugin.json` | Bump `version` to `0.8.0` (Phase 4) |
| `README.md` | Document IDE-protocol features and config (Phase 4) |
| `CLAUDE.md` | Note new architecture and which features go through which path (Phase 4) |

### Deleted files

- `servers/open-in-nvim.js` (Phase 4)
- `dist/open-in-nvim.cjs` (Phase 4)
- `package.json`, `package-lock.json`, `node_modules/` (Phase 4 — no longer building anything)

---

## Conventions used in this plan

- All file paths are absolute from repo root: `/root/projects/nvim-claude.feat.enhancements/`
- Tests live in `tests/` and run via `bash tests/run.sh` (created in Phase 0).
- Each task ends with a commit. Commit messages follow conventional-commits style (`feat:`, `fix:`, `chore:`, `docs:`, `test:`).
- "Borrow from claudecode.nvim" tasks include a step to clone or browse their repo at `https://github.com/coder/claudecode.nvim` for reference. Adaptation MUST preserve their copyright header and add the file path to `NOTICE`.
- The `--headless -l` test runner returns non-zero exit code if any `assert(...)` fails. No external test framework needed.

---

## Phase 0 — Spike: Verify Protocol Compatibility

**Goal of this phase:** prove Claude Code recognizes our nvim instance as an IDE before investing in tools. If it doesn't, abort the whole plan and re-evaluate.

### Task 0.1: Set up minimal test runner

**Files:**
- Create: `tests/run.sh`
- Create: `tests/sanity_test.lua`

- [ ] **Step 1: Write the test runner**

`tests/run.sh`:
```bash
#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

failed=0
for f in tests/*_test.lua; do
  echo "--- $f ---"
  if ! nvim --headless -u NONE \
       --cmd "set rtp+=$(pwd)" \
       -l "$f"; then
    failed=$((failed + 1))
  fi
done

if [ "$failed" -gt 0 ]; then
  echo "FAILED: $failed test file(s)"
  exit 1
fi
echo "ALL TESTS PASSED"
```

`tests/sanity_test.lua`:
```lua
assert(1 + 1 == 2, "basic math broken")
print("sanity_test: PASS")
```

- [ ] **Step 2: Run it**

```bash
chmod +x tests/run.sh && tests/run.sh
```

Expected: `sanity_test: PASS` then `ALL TESTS PASSED`.

- [ ] **Step 3: Commit**

```bash
git add tests/run.sh tests/sanity_test.lua
git commit -m "chore: add minimal headless-nvim test runner"
```

### Task 0.2: Extract protocol details from PROTOCOL.md

**Files:**
- Read-only: [`coder/claudecode.nvim/PROTOCOL.md`](https://github.com/coder/claudecode.nvim/blob/main/PROTOCOL.md) — primary source
- Read-only: `https://github.com/coder/claudecode.nvim` source (only as fallback for anything PROTOCOL.md leaves out)
- Create: `tests/protocol_notes.md` (extracted summary used by later tasks)

- [ ] **Step 1: Fetch PROTOCOL.md**

```bash
curl -fsSL https://raw.githubusercontent.com/coder/claudecode.nvim/main/PROTOCOL.md -o /tmp/PROTOCOL.md
```

If the file moved or the curl fails, browse to the URL in the spec link and save the document manually.

- [ ] **Step 2: Extract the lockfile contract**

From PROTOCOL.md, copy into `tests/protocol_notes.md` exactly:
- Lockfile path pattern (`~/.claude/ide/<???>.lock`)
- Every required and optional field, with type
- File permissions / ownership requirements

- [ ] **Step 3: Extract the handshake contract**

Append to `tests/protocol_notes.md`:
- HTTP request headers Claude Code sends on upgrade (Sec-WebSocket-Key, Authorization, subprotocol, etc.)
- Subprotocol value (e.g., `mcp` or version-suffixed)
- First JSON-RPC message after upgrade, with example
- Required shape of the `initialize` response

- [ ] **Step 4: Extract the tool and event surface**

Append to `tests/protocol_notes.md`:
- The complete list of tool names Claude Code expects to be able to call (`getCurrentSelection`, `getOpenEditors`, `openFile`, `openDiff`, `getDiagnostics`, `getWorkspaceFolders`, plus anything else PROTOCOL.md mentions)
- The exact JSON-RPC method names for push notifications from IDE → Claude (e.g., `selection_changed` vs an MCP-style `notifications/...` namespace). This is the single most important detail for Phase 1 to work.
- Any tool input/output shapes that differ from what this plan assumes

- [ ] **Step 5: Cross-check against claudecode.nvim source for gaps**

If PROTOCOL.md leaves any of the above blank, only then clone the source as a secondary reference:

```bash
git clone --depth 1 https://github.com/coder/claudecode.nvim /tmp/claudecode-ref
```

Find the corresponding implementation: `find /tmp/claudecode-ref/lua -type f -name "*.lua" | xargs grep -l "lockfile\|WebSocket\|tools/list" -i | sort -u`

Note in `tests/protocol_notes.md` which details came from PROTOCOL.md (authoritative) vs source (inferred).

- [ ] **Step 6: No commit yet**

`tests/protocol_notes.md` gets committed in Task 0.4 along with the lockfile implementation it informs.

### Task 0.3: Write WS frame encode/decode with tests

**Files:**
- Create: `lua/nvim-claude/ide/websocket.lua`
- Create: `tests/websocket_test.lua`
- Modify: `NOTICE` (create)

- [ ] **Step 1: Create NOTICE file**

`/root/projects/nvim-claude.feat.enhancements/NOTICE`:
```
nvim-claude includes WebSocket protocol code derived from claudecode.nvim
(https://github.com/coder/claudecode.nvim), which is licensed under the
Apache License, Version 2.0.

Original copyright: Copyright (c) coder.com and contributors.

The full Apache 2.0 license text is available at:
http://www.apache.org/licenses/LICENSE-2.0

Files derived from claudecode.nvim are noted in their headers.
```

- [ ] **Step 2: Write the failing test**

`tests/websocket_test.lua`:
```lua
package.path = package.path .. ";./lua/?.lua;./lua/?/init.lua"
local ws = require("nvim-claude.ide.websocket")

-- Round-trip: encode then decode a small text frame.
local payload = '{"jsonrpc":"2.0","method":"ping"}'
local frame = ws.encode_frame({ opcode = 0x1, payload = payload, fin = true })
local decoded, rest = ws.decode_frame(frame)
assert(decoded ~= nil, "decode_frame returned nil")
assert(decoded.opcode == 0x1, "opcode mismatch: got " .. tostring(decoded.opcode))
assert(decoded.fin == true, "fin should be true")
assert(decoded.payload == payload, "payload mismatch")
assert(rest == "", "no remaining bytes expected, got " .. #rest)

-- Masked client→server frame should also decode.
local masked = ws.encode_frame({ opcode = 0x1, payload = payload, fin = true, mask = true })
local decoded_masked = ws.decode_frame(masked)
assert(decoded_masked.payload == payload, "masked payload mismatch")

-- Larger payload (>125 bytes triggers extended-length encoding).
local big = string.rep("x", 200)
local big_frame = ws.encode_frame({ opcode = 0x1, payload = big, fin = true })
local big_decoded = ws.decode_frame(big_frame)
assert(big_decoded.payload == big, "extended-length payload mismatch")

-- Partial frame: returns nil + leftover.
local partial, rest_partial = ws.decode_frame(string.sub(frame, 1, 3))
assert(partial == nil, "partial frame should return nil")
assert(rest_partial == string.sub(frame, 1, 3), "leftover should be untouched input")

print("websocket_test: PASS")
```

- [ ] **Step 3: Run test to verify it fails**

```bash
tests/run.sh
```

Expected: error like `module 'nvim-claude.ide.websocket' not found` and overall FAILED.

- [ ] **Step 4: Implement websocket.lua**

Adapt from `/tmp/claudecode-ref/lua/claudecode/server/...` (whatever file contains their WS framing). Preserve their copyright header at the top of `lua/nvim-claude/ide/websocket.lua`. Public API:

```lua
local M = {}

--- Encode a WebSocket frame.
--- opts: { opcode = 0x1|0x2|0x8|0x9|0xA, payload = string, fin = boolean, mask = boolean }
--- Returns: string (binary frame).
function M.encode_frame(opts) ... end

--- Decode one WebSocket frame from a buffer.
--- Returns: (frame_table, remaining_bytes) on success
---          (nil, original_buf) if buffer is incomplete
--- frame_table: { opcode, payload, fin }
function M.decode_frame(buf) ... end

return M
```

Borrow the actual byte-level encoding/decoding logic from claudecode.nvim. Add a header comment:

```lua
-- Derived from claudecode.nvim (Apache-2.0).
-- See NOTICE in repo root.
```

- [ ] **Step 5: Run test to verify it passes**

```bash
tests/run.sh
```

Expected: `websocket_test: PASS` and `ALL TESTS PASSED`.

- [ ] **Step 6: Commit**

```bash
git add NOTICE lua/nvim-claude/ide/websocket.lua tests/websocket_test.lua
git commit -m "feat(ide): add WebSocket frame codec (derived from claudecode.nvim)"
```

### Task 0.4: Write lockfile module with tests

**Files:**
- Create: `lua/nvim-claude/ide/lockfile.lua`
- Create: `tests/lockfile_test.lua`
- Create: `tests/protocol_notes.md` (notes from Task 0.2)

- [ ] **Step 1: Write the failing test**

`tests/lockfile_test.lua`:
```lua
package.path = package.path .. ";./lua/?.lua;./lua/?/init.lua"
local lockfile = require("nvim-claude.ide.lockfile")

-- Use a tmp dir, not the real ~/.claude/ide
local tmp = vim.fn.tempname()
vim.fn.mkdir(tmp, "p")
lockfile._set_dir_for_test(tmp)

local info = {
  port = 53917,
  authToken = "deadbeef" .. string.rep("0", 56),
  ideName = "Neovim",
  pid = vim.fn.getpid(),
  workspaceFolders = { vim.fn.getcwd() },
}

local path = lockfile.write(info)
assert(path:find(tmp, 1, true), "lockfile path should be under tmp dir")
assert(vim.fn.filereadable(path) == 1, "lockfile should be readable")

local read_back = lockfile.read(path)
assert(read_back.port == info.port, "port mismatch")
assert(read_back.authToken == info.authToken, "authToken mismatch")
assert(read_back.ideName == "Neovim", "ideName mismatch")

-- Stale reaper: a lock for pid=1 (init, never matches our nvim) should be reaped
-- only if we explicitly write a stale one.
local stale_path = tmp .. "/99999.lock"
local f = io.open(stale_path, "w")
f:write(vim.fn.json_encode({ pid = 99999, port = 1 }))
f:close()
lockfile.reap_stale()
assert(vim.fn.filereadable(stale_path) == 0, "stale lockfile should be removed")
assert(vim.fn.filereadable(path) == 1, "our live lockfile should remain")

lockfile.remove(path)
assert(vim.fn.filereadable(path) == 0, "remove should delete the file")

print("lockfile_test: PASS")
```

- [ ] **Step 2: Run test to verify it fails**

```bash
tests/run.sh
```

Expected: module not found.

- [ ] **Step 3: Write the lockfile notes file**

Write `tests/protocol_notes.md` with the schema and handshake findings from Task 0.2. This is the canonical record of "what protocol Claude Code expects" for the rest of the plan to build against.

- [ ] **Step 4: Implement lockfile.lua**

```lua
local M = {}

local DIR = vim.fn.expand("~/.claude/ide")

function M._set_dir_for_test(d) DIR = d end

local function ensure_dir()
  if vim.fn.isdirectory(DIR) == 0 then
    vim.fn.mkdir(DIR, "p", 0700)
  end
end

function M.path_for(pid)
  return DIR .. "/" .. pid .. ".lock"
end

function M.write(info)
  ensure_dir()
  local path = M.path_for(info.pid)
  local f = assert(io.open(path, "w"))
  f:write(vim.fn.json_encode(info))
  f:close()
  return path
end

function M.read(path)
  local f = io.open(path, "r")
  if not f then return nil end
  local content = f:read("*a")
  f:close()
  local ok, parsed = pcall(vim.fn.json_decode, content)
  if not ok then return nil end
  return parsed
end

function M.remove(path)
  os.remove(path)
end

local function pid_alive(pid)
  -- /proc check works on linux. On other platforms fall back to os.execute.
  if vim.fn.has("linux") == 1 then
    return vim.fn.isdirectory("/proc/" .. pid) == 1
  end
  return os.execute("kill -0 " .. pid .. " 2>/dev/null") == 0
end

function M.reap_stale()
  if vim.fn.isdirectory(DIR) == 0 then return end
  local entries = vim.fn.readdir(DIR)
  for _, name in ipairs(entries) do
    local pid = tonumber(name:match("^(%d+)%.lock$"))
    if pid and not pid_alive(pid) then
      M.remove(DIR .. "/" .. name)
    end
  end
end

return M
```

- [ ] **Step 5: Run test to verify it passes**

```bash
tests/run.sh
```

Expected: both `websocket_test: PASS` and `lockfile_test: PASS`, `ALL TESTS PASSED`.

- [ ] **Step 6: Commit**

```bash
git add lua/nvim-claude/ide/lockfile.lua tests/lockfile_test.lua tests/protocol_notes.md
git commit -m "feat(ide): add lockfile manager with stale-pid reaper"
```

### Task 0.5: Minimal TCP server with WS upgrade

**Files:**
- Create: `lua/nvim-claude/ide/server.lua`

This task is wiring + integration; no unit tests (real test is the manual verification in Task 0.7).

- [ ] **Step 1: Implement server.lua**

```lua
local uv = vim.uv or vim.loop
local ws = require("nvim-claude.ide.websocket")

local M = {}
local state = { server = nil, port = nil, clients = {}, on_message = nil, auth_token = nil }

local function http_response(status, body)
  return ("HTTP/1.1 %s\r\nContent-Length: %d\r\n\r\n%s"):format(status, #body, body)
end

local function ws_accept_key(client_key)
  local guid = "258EAFA5-E914-47DA-95CA-C5AB0DC85B11"
  -- SHA1+Base64; vim has neither built-in. Use system tools.
  local cmd = ("printf %%s '%s%s' | openssl dgst -binary -sha1 | openssl base64"):format(client_key, guid)
  local f = io.popen(cmd)
  local out = f:read("*a"):gsub("%s", "")
  f:close()
  return out
end

local function handle_handshake(client, request)
  local key = request:match("Sec%-WebSocket%-Key:%s*([^\r\n]+)")
  local auth = request:match("Authorization:%s*Bearer%s+([^\r\n]+)")
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
  client:write(
    "HTTP/1.1 101 Switching Protocols\r\n"
    .. "Upgrade: websocket\r\n"
    .. "Connection: Upgrade\r\n"
    .. "Sec-WebSocket-Accept: " .. accept .. "\r\n\r\n"
  )
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
  -- After upgrade: parse WS frames.
  while true do
    local frame, rest = ws.decode_frame(buf)
    if not frame then return buf end
    buf = rest
    if frame.opcode == 0x1 and state.on_message then
      pcall(state.on_message, client, frame.payload)
    elseif frame.opcode == 0x8 then
      client:close()
      return ""
    end
  end
end

function M.start(opts)
  state.on_message = opts.on_message
  state.auth_token = opts.auth_token
  state.server = uv.new_tcp()
  state.server:bind("127.0.0.1", 0)
  state.server:listen(8, function(err)
    assert(not err, err)
    local client = uv.new_tcp()
    state.server:accept(client)
    local read_buf = ""
    client:read_start(function(read_err, chunk)
      if read_err or not chunk then
        client:close()
        return
      end
      read_buf = on_client_data(client, read_buf, chunk)
    end)
    table.insert(state.clients, client)
  end)
  state.port = state.server:getsockname().port
  return state.port
end

function M.stop()
  for _, c in ipairs(state.clients) do pcall(function() c:close() end) end
  state.clients = {}
  if state.server then state.server:close() end
  state.server = nil
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
```

- [ ] **Step 2: No automated test**

This is wired up and verified in Task 0.7's manual integration check. Building it without tests is acceptable here because the WS framing it depends on IS tested, and the integration test is decisive.

- [ ] **Step 3: Commit**

```bash
git add lua/nvim-claude/ide/server.lua
git commit -m "feat(ide): add WS server with upgrade handshake and bearer auth"
```

### Task 0.6: Wire spike together — minimal `ide.start()` that responds to `initialize`

**Files:**
- Create: `lua/nvim-claude/ide/init.lua`
- Modify: `lua/nvim-claude/init.lua`

- [ ] **Step 1: Write ide/init.lua**

```lua
local server = require("nvim-claude.ide.server")
local lockfile = require("nvim-claude.ide.lockfile")

local M = {}
local state = { lockfile_path = nil, port = nil, connected = false }

local function random_token()
  local out = {}
  for i = 1, 32 do out[i] = string.format("%02x", math.random(0, 255)) end
  return table.concat(out)
end

local function handle_message(client, payload)
  local ok, msg = pcall(vim.fn.json_decode, payload)
  if not ok then return end

  if msg.method == "initialize" then
    state.connected = true
    -- Response shape MUST match what's documented in tests/protocol_notes.md
    -- (filled during Task 0.2). Adjust here based on actual findings.
    local response = {
      jsonrpc = "2.0",
      id = msg.id,
      result = {
        protocolVersion = "2024-11-05",
        capabilities = { tools = {} },
        serverInfo = { name = "nvim-claude", version = "0.8.0" },
      },
    }
    server.send(client, vim.fn.json_encode(response))
  end
end

function M.start()
  math.randomseed(os.time())
  lockfile.reap_stale()
  local token = random_token()
  local port = server.start({ on_message = handle_message, auth_token = token })
  state.port = port
  state.lockfile_path = lockfile.write({
    pid = vim.fn.getpid(),
    port = port,
    authToken = token,
    ideName = "Neovim",
    workspaceFolders = { vim.fn.getcwd() },
    transport = "ws",
  })
  vim.api.nvim_create_autocmd("VimLeavePre", {
    callback = function() M.stop() end,
  })
end

function M.stop()
  if state.lockfile_path then lockfile.remove(state.lockfile_path) end
  server.stop()
  state.connected = false
end

function M.is_connected() return state.connected end
function M.state() return state end

return M
```

- [ ] **Step 2: Modify lua/nvim-claude/init.lua**

After the `context` block in `M.config`, add:

```lua
  ide = {
    enabled = true,
    auto_start = true,
  },
```

In `M.setup(opts)`, after the existing context registration, add:

```lua
  if M.config.ide.enabled and M.config.ide.auto_start then
    require("nvim-claude.ide").start()
  end
```

- [ ] **Step 3: Commit**

```bash
git add lua/nvim-claude/ide/init.lua lua/nvim-claude/init.lua
git commit -m "feat(ide): minimal start/stop with lockfile and initialize handler"
```

### Task 0.7: Decision-gate manual verification

This is the decision gate. **If this fails, stop the plan and re-evaluate.**

- [ ] **Step 1: Restart nvim**

Open a fresh nvim. Verify the lockfile is created:

```bash
ls -la ~/.claude/ide/
cat ~/.claude/ide/$(pgrep -n nvim).lock
```

Expected: a `<pid>.lock` file containing valid JSON with `port`, `authToken`, etc.

- [ ] **Step 2: Verify the port is listening**

```bash
ss -tln | grep $(jq -r .port ~/.claude/ide/$(pgrep -n nvim).lock)
```

Expected: a `LISTEN` entry on `127.0.0.1`.

- [ ] **Step 3: Launch Claude Code**

In nvim: `<leader>cv` (or `:ClaudeVSplit`).

- [ ] **Step 4: Look for the IDE indicator in Claude's TUI**

Inspect the bottom status row of the Claude Code TUI. Look for a "Connected to Neovim" indicator or similar.

**If the indicator appears:** spike succeeded. Proceed to Phase 1.

**If the indicator does NOT appear:** the protocol details we have are wrong. Possible causes:
- Lockfile schema mismatch (filename pattern, missing fields)
- Handshake response missing required fields
- Auth token format wrong
- Subprotocol header missing
- Claude Code expects a different transport (stdio vs ws)

Diagnostic steps:
1. Check Claude Code's debug logs (`~/.claude/logs/` or `claude --debug`)
2. Compare lockfile contents with what claudecode.nvim writes (run claudecode.nvim in a separate nvim, diff the lockfiles)
3. Add `vim.notify` debug prints in `server.lua`'s `on_client_data` to see if Claude even attempted a connection

If after one round of fixes Claude still doesn't connect: STOP. Document what was tried in `tests/protocol_notes.md`, post findings, and re-evaluate the plan with the user.

- [ ] **Step 5: Commit (only if successful)**

```bash
git commit --allow-empty -m "chore: phase 0 spike — IDE protocol connection verified"
```

---

## Phase 1 — Status Line MVP

**Goal:** Claude's TUI status line shows the active nvim file and updates as the user moves around. Cursor/selection events flow live.

### Task 1.1: JSON-RPC dispatcher

**Files:**
- Create: `lua/nvim-claude/ide/rpc.lua`
- Create: `tests/rpc_test.lua`

- [ ] **Step 1: Write the failing test**

`tests/rpc_test.lua`:
```lua
package.path = package.path .. ";./lua/?.lua;./lua/?/init.lua"
local rpc = require("nvim-claude.ide.rpc")

local d = rpc.new()

d:register_tool({
  name = "echo",
  description = "Echo back",
  input_schema = { type = "object", properties = { msg = { type = "string" } } },
  handler = function(args) return { content = { { type = "text", text = args.msg } } } end,
})

-- tools/list response shape
local list_resp = d:dispatch('{"jsonrpc":"2.0","id":1,"method":"tools/list"}')
local list_decoded = vim.fn.json_decode(list_resp)
assert(list_decoded.id == 1)
assert(#list_decoded.result.tools == 1)
assert(list_decoded.result.tools[1].name == "echo")

-- tools/call invokes handler
local call_resp = d:dispatch(vim.fn.json_encode({
  jsonrpc = "2.0", id = 2, method = "tools/call",
  params = { name = "echo", arguments = { msg = "hi" } },
}))
local call_decoded = vim.fn.json_decode(call_resp)
assert(call_decoded.id == 2)
assert(call_decoded.result.content[1].text == "hi")

-- Unknown method returns JSON-RPC error
local err_resp = d:dispatch('{"jsonrpc":"2.0","id":3,"method":"bogus"}')
local err_decoded = vim.fn.json_decode(err_resp)
assert(err_decoded.error ~= nil, "should return error envelope")
assert(err_decoded.error.code == -32601, "method not found = -32601")

print("rpc_test: PASS")
```

- [ ] **Step 2: Run test to verify it fails**

```bash
tests/run.sh
```

Expected: module not found.

- [ ] **Step 3: Implement rpc.lua**

```lua
local M = {}

function M.new()
  local self = { tools = {} }

  function self:register_tool(spec)
    self.tools[spec.name] = spec
  end

  local function err_response(id, code, message)
    return vim.fn.json_encode({
      jsonrpc = "2.0", id = id,
      error = { code = code, message = message },
    })
  end

  function self:dispatch(payload)
    local ok, msg = pcall(vim.fn.json_decode, payload)
    if not ok then
      return err_response(vim.NIL, -32700, "parse error")
    end

    if msg.method == "tools/list" then
      local list = {}
      for _, t in pairs(self.tools) do
        table.insert(list, {
          name = t.name,
          description = t.description,
          inputSchema = t.input_schema,
        })
      end
      return vim.fn.json_encode({
        jsonrpc = "2.0", id = msg.id, result = { tools = list },
      })
    end

    if msg.method == "tools/call" then
      local tool = self.tools[msg.params and msg.params.name]
      if not tool then
        return err_response(msg.id, -32602, "unknown tool: " .. tostring(msg.params and msg.params.name))
      end
      local handler_ok, result = pcall(tool.handler, msg.params.arguments or {})
      if not handler_ok then
        return err_response(msg.id, -32603, tostring(result))
      end
      return vim.fn.json_encode({
        jsonrpc = "2.0", id = msg.id, result = result,
      })
    end

    return err_response(msg.id, -32601, "method not found: " .. tostring(msg.method))
  end

  return self
end

return M
```

- [ ] **Step 4: Run test to verify it passes**

```bash
tests/run.sh
```

Expected: all tests pass.

- [ ] **Step 5: Commit**

```bash
git add lua/nvim-claude/ide/rpc.lua tests/rpc_test.lua
git commit -m "feat(ide): add JSON-RPC dispatcher with tool registry"
```

### Task 1.2: Wire dispatcher into ide/init.lua

**Files:**
- Modify: `lua/nvim-claude/ide/init.lua`

- [ ] **Step 1: Replace the inline `initialize` handler with the dispatcher**

In `lua/nvim-claude/ide/init.lua`, replace `handle_message` with:

```lua
local rpc = require("nvim-claude.ide.rpc")
local dispatcher = rpc.new()

local function handle_message(client, payload)
  local ok, msg = pcall(vim.fn.json_decode, payload)
  if not ok then return end

  if msg.method == "initialize" then
    state.connected = true
    local response = {
      jsonrpc = "2.0", id = msg.id,
      result = {
        protocolVersion = "2024-11-05",
        capabilities = { tools = {} },
        serverInfo = { name = "nvim-claude", version = "0.8.0" },
      },
    }
    server.send(client, vim.fn.json_encode(response))
    return
  end

  -- All other methods go through the dispatcher.
  vim.schedule(function()
    server.send(client, dispatcher:dispatch(payload))
  end)
end

-- Expose for tool registration during start().
M._dispatcher = dispatcher
```

- [ ] **Step 2: Restart nvim, verify Claude TUI still shows connection**

Manual check — same as Task 0.7 step 4. Connection should still work.

- [ ] **Step 3: Commit**

```bash
git add lua/nvim-claude/ide/init.lua
git commit -m "refactor(ide): route messages through JSON-RPC dispatcher"
```

### Task 1.3: Implement `getCurrentSelection` tool

**Files:**
- Create: `lua/nvim-claude/ide/tools/get_current_selection.lua`
- Modify: `lua/nvim-claude/ide/init.lua`

- [ ] **Step 1: Implement the tool**

```lua
local M = {
  name = "getCurrentSelection",
  description = "Return the current visual selection or cursor position in the active nvim buffer.",
  input_schema = { type = "object", properties = {} },
}

local function visual_range()
  local mode = vim.fn.mode()
  if mode ~= "v" and mode ~= "V" and mode ~= "\22" then
    return nil
  end
  local s = vim.fn.getpos("v")
  local e = vim.fn.getpos(".")
  if s[2] > e[2] or (s[2] == e[2] and s[3] > e[3]) then s, e = e, s end
  return s, e
end

function M.handler(_)
  local buf = vim.api.nvim_get_current_buf()
  local file = vim.api.nvim_buf_get_name(buf)
  local s_pos, e_pos = visual_range()
  local text = ""
  local start_line, start_col, end_line, end_col

  if s_pos then
    start_line, start_col = s_pos[2], s_pos[3]
    end_line, end_col = e_pos[2], e_pos[3]
    local lines = vim.api.nvim_buf_get_lines(buf, start_line - 1, end_line, false)
    text = table.concat(lines, "\n")
  else
    local cur = vim.api.nvim_win_get_cursor(0)
    start_line, start_col = cur[1], cur[2] + 1
    end_line, end_col = start_line, start_col
  end

  return {
    content = {
      { type = "text", text = vim.fn.json_encode({
        text = text,
        filePath = file,
        startLine = start_line, startColumn = start_col,
        endLine = end_line,     endColumn = end_col,
      }) },
    },
  }
end

return M
```

- [ ] **Step 2: Register in ide/init.lua**

In `M.start()`, after creating the dispatcher (move dispatcher creation into `start` if it isn't already), add:

```lua
M._dispatcher:register_tool(require("nvim-claude.ide.tools.get_current_selection"))
```

- [ ] **Step 3: Commit**

```bash
git add lua/nvim-claude/ide/tools/get_current_selection.lua lua/nvim-claude/ide/init.lua
git commit -m "feat(ide): add getCurrentSelection tool"
```

### Task 1.4: Implement `getOpenEditors` tool

**Files:**
- Create: `lua/nvim-claude/ide/tools/get_open_editors.lua`
- Modify: `lua/nvim-claude/ide/init.lua`

- [ ] **Step 1: Implement**

```lua
local M = {
  name = "getOpenEditors",
  description = "List open file buffers; mark the active one.",
  input_schema = { type = "object", properties = {} },
}

function M.handler(_)
  local active = vim.api.nvim_get_current_buf()
  local editors = {}
  for _, b in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_loaded(b) and vim.bo[b].buftype == "" then
      local file = vim.api.nvim_buf_get_name(b)
      if file ~= "" then
        table.insert(editors, {
          filePath = file,
          isActive = b == active,
          languageId = vim.bo[b].filetype,
          isDirty = vim.bo[b].modified,
        })
      end
    end
  end
  return {
    content = { { type = "text", text = vim.fn.json_encode({ editors = editors }) } },
  }
end

return M
```

- [ ] **Step 2: Register in ide/init.lua**

Add a line in `M.start()` parallel to the get_current_selection registration.

- [ ] **Step 3: Commit**

```bash
git add lua/nvim-claude/ide/tools/get_open_editors.lua lua/nvim-claude/ide/init.lua
git commit -m "feat(ide): add getOpenEditors tool"
```

### Task 1.5: Implement `getWorkspaceFolders` tool

**Files:**
- Create: `lua/nvim-claude/ide/tools/get_workspace_folders.lua`
- Modify: `lua/nvim-claude/ide/init.lua`

- [ ] **Step 1: Implement**

```lua
local M = {
  name = "getWorkspaceFolders",
  description = "List workspace root directories.",
  input_schema = { type = "object", properties = {} },
}

function M.handler(_)
  local cwd = vim.fn.getcwd()
  return {
    content = { { type = "text", text = vim.fn.json_encode({
      folders = { { uri = "file://" .. cwd, name = vim.fn.fnamemodify(cwd, ":t") } },
    }) } },
  }
end

return M
```

- [ ] **Step 2: Register, commit**

```bash
git add lua/nvim-claude/ide/tools/get_workspace_folders.lua lua/nvim-claude/ide/init.lua
git commit -m "feat(ide): add getWorkspaceFolders tool"
```

### Task 1.6: Live event push on selection/buffer change

**Files:**
- Create: `lua/nvim-claude/ide/events.lua`
- Modify: `lua/nvim-claude/ide/init.lua`

- [ ] **Step 1: Implement events.lua**

```lua
local server = require("nvim-claude.ide.server")

local M = {}
local state = { last_push_at = 0, throttle_ms = 100 }

function M.set_throttle(ms) state.throttle_ms = ms end

local function now_ms()
  return math.floor(vim.uv.hrtime() / 1e6)
end

local function throttled(fn)
  local t = now_ms()
  if t - state.last_push_at < state.throttle_ms then return end
  state.last_push_at = t
  fn()
end

local function push_selection()
  local buf = vim.api.nvim_get_current_buf()
  if vim.bo[buf].buftype ~= "" then return end
  local file = vim.api.nvim_buf_get_name(buf)
  if file == "" then return end
  local cur = vim.api.nvim_win_get_cursor(0)
  local notif = vim.fn.json_encode({
    jsonrpc = "2.0",
    method = "selection_changed",
    params = {
      filePath = file,
      line = cur[1],
      column = cur[2] + 1,
    },
  })
  server.broadcast(notif)
end

function M.register()
  local group = vim.api.nvim_create_augroup("nvim-claude-ide-events", { clear = true })
  vim.api.nvim_create_autocmd({ "BufEnter", "CursorMoved", "CursorMovedI", "ModeChanged" }, {
    group = group,
    callback = function() throttled(push_selection) end,
  })
end

return M
```

- [ ] **Step 2: Register in ide/init.lua**

Inside `M.start()`, after tool registration:

```lua
require("nvim-claude.ide.events").register()
require("nvim-claude.ide.events").set_throttle(
  (require("nvim-claude").config.ide or {}).selection_throttle_ms or 100
)
```

- [ ] **Step 3: Manual verification**

Restart nvim with Claude attached. Move the cursor in a file buffer. Confirm Claude TUI status line updates with the file and line number.

**Note:** the exact notification method name (`selection_changed` vs `at_mentioned_files_changed` vs other) MUST be confirmed against `tests/protocol_notes.md` from Task 0.2. If the status line doesn't update, the method name is the most likely culprit; check claudecode.nvim's events emission code for the right name.

- [ ] **Step 4: Commit**

```bash
git add lua/nvim-claude/ide/events.lua lua/nvim-claude/ide/init.lua
git commit -m "feat(ide): push selection_changed events on cursor/buffer changes"
```

### Task 1.7: Phase 1 verification checkpoint

- [ ] **Step 1: Run all tests**

```bash
tests/run.sh
```

Expected: all PASS.

- [ ] **Step 2: Manual matrix**

Restart nvim, attach Claude:
- Open a file → status line shows that file ✓
- Move cursor → line number updates ✓
- Open another file → switches ✓
- Visual select → selection range shown ✓ (if Claude TUI displays it)

- [ ] **Step 3: No commit**

If issues found, fix in dedicated commits before proceeding.

---

## Phase 2 — File and Diff Opening

**Goal:** Claude can open files and diffs in nvim through standard IDE tools.

### Task 2.1: Implement `openFile` tool

**Files:**
- Create: `lua/nvim-claude/ide/tools/open_file.lua`
- Modify: `lua/nvim-claude/ide/init.lua`

- [ ] **Step 1: Implement**

```lua
local M = {
  name = "openFile",
  description = "Open a file in nvim, optionally jumping to a line and column.",
  input_schema = {
    type = "object",
    properties = {
      filePath = { type = "string" },
      line = { type = "number" },
      column = { type = "number" },
    },
    required = { "filePath" },
  },
}

function M.handler(args)
  local path = args.filePath
  vim.schedule(function()
    vim.cmd("edit " .. vim.fn.fnameescape(path))
    if args.line then
      vim.api.nvim_win_set_cursor(0, { args.line, (args.column or 1) - 1 })
    end
  end)
  return { content = { { type = "text", text = "opened: " .. path } } }
end

return M
```

- [ ] **Step 2: Register in ide/init.lua, commit**

```bash
git add lua/nvim-claude/ide/tools/open_file.lua lua/nvim-claude/ide/init.lua
git commit -m "feat(ide): add openFile tool"
```

### Task 2.2: Implement `openDiff` tool

**Files:**
- Create: `lua/nvim-claude/ide/tools/open_diff.lua`
- Modify: `lua/nvim-claude/ide/init.lua`

- [ ] **Step 1: Decide implementation strategy**

Two paths, pick based on what's already familiar in this codebase:
- **A:** Use `diffview.nvim` — `:DiffviewOpen` with the two paths. Pro: matches existing per-turn diff UX. Con: requires diffview installed.
- **B:** Native nvim `:diffsplit` — opens two windows in diff mode. Pro: no dependency. Con: less polished UX.

Recommended: A (diffview), with graceful fallback to B if diffview isn't installed.

- [ ] **Step 2: Implement**

```lua
local M = {
  name = "openDiff",
  description = "Open a diff view between two files.",
  input_schema = {
    type = "object",
    properties = {
      oldFilePath = { type = "string" },
      newFilePath = { type = "string" },
      oldFileContents = { type = "string" },
      newFileContents = { type = "string" },
    },
  },
}

local function write_temp(content, hint)
  local path = vim.fn.tempname() .. "-" .. (hint or "diff")
  local f = assert(io.open(path, "w"))
  f:write(content or "")
  f:close()
  return path
end

function M.handler(args)
  local old_path = args.oldFilePath
  local new_path = args.newFilePath
  if args.oldFileContents and not old_path then
    old_path = write_temp(args.oldFileContents, "old")
  end
  if args.newFileContents and not new_path then
    new_path = write_temp(args.newFileContents, "new")
  end
  vim.schedule(function()
    local has_diffview = pcall(require, "diffview")
    if has_diffview then
      pcall(vim.cmd, "DiffviewClose")
      vim.cmd(("DiffviewOpen --selected-file=%s -- %s %s"):format(
        vim.fn.fnameescape(new_path), vim.fn.fnameescape(old_path), vim.fn.fnameescape(new_path)
      ))
    else
      vim.cmd("edit " .. vim.fn.fnameescape(old_path))
      vim.cmd("diffthis")
      vim.cmd("vsplit " .. vim.fn.fnameescape(new_path))
      vim.cmd("diffthis")
    end
  end)
  return { content = { { type = "text", text = "opened diff" } } }
end

return M
```

**Note:** the exact `DiffviewOpen` command line for "compare two arbitrary files" may need adjustment. Test interactively before committing.

- [ ] **Step 3: Register in ide/init.lua, commit**

```bash
git add lua/nvim-claude/ide/tools/open_diff.lua lua/nvim-claude/ide/init.lua
git commit -m "feat(ide): add openDiff tool with diffview/native fallback"
```

### Task 2.3: Unregister legacy MCP server `open-in-nvim`

**Files:**
- Modify: `.mcp.json`

- [ ] **Step 1: Read current `.mcp.json`**

```bash
cat /root/projects/nvim-claude.feat.enhancements/.mcp.json
```

- [ ] **Step 2: Remove the `open-in-nvim` entry**

Edit the file to delete the `mcpServers.open-in-nvim` block. If it's the only entry, leave an empty `mcpServers: {}` rather than removing the file (keeps the manifest valid).

- [ ] **Step 3: Bump version**

In `.claude-plugin/plugin.json`, bump `version` from `0.7.0` to `0.7.1` (small interim bump to mark the MCP server retirement).

- [ ] **Step 4: Commit**

```bash
git add .mcp.json .claude-plugin/plugin.json
git commit -m "feat(ide): retire legacy open-in-nvim MCP server"
```

---

## Phase 3 — Diagnostics + Retire Active-File Injection

**Goal:** Diagnostics flow over IDE protocol; the `[Active File: ...]` block disappears from prompts because Claude now has it live.

### Task 3.1: Implement `getDiagnostics` tool

**Files:**
- Create: `lua/nvim-claude/ide/tools/get_diagnostics.lua`
- Modify: `lua/nvim-claude/ide/init.lua`

- [ ] **Step 1: Implement**

```lua
local M = {
  name = "getDiagnostics",
  description = "Get LSP diagnostics for a file (or all open files if filePath omitted).",
  input_schema = {
    type = "object",
    properties = {
      filePath = { type = "string" },
    },
  },
}

local SEVERITY = { "error", "warning", "info", "hint" }

local function buf_for_file(path)
  for _, b in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_loaded(b) and vim.api.nvim_buf_get_name(b) == path then
      return b
    end
  end
end

function M.handler(args)
  local diagnostics = {}
  local function collect(buf)
    local file = vim.api.nvim_buf_get_name(buf)
    for _, d in ipairs(vim.diagnostic.get(buf)) do
      table.insert(diagnostics, {
        filePath = file,
        line = d.lnum + 1,
        column = d.col + 1,
        severity = SEVERITY[d.severity] or "unknown",
        message = d.message,
        source = d.source,
      })
    end
  end

  if args.filePath then
    local b = buf_for_file(args.filePath)
    if b then collect(b) end
  else
    for _, b in ipairs(vim.api.nvim_list_bufs()) do
      if vim.api.nvim_buf_is_loaded(b) and vim.bo[b].buftype == "" then
        collect(b)
      end
    end
  end

  return { content = { { type = "text", text = vim.fn.json_encode({ diagnostics = diagnostics }) } } }
end

return M
```

- [ ] **Step 2: Register in ide/init.lua, commit**

```bash
git add lua/nvim-claude/ide/tools/get_diagnostics.lua lua/nvim-claude/ide/init.lua
git commit -m "feat(ide): add getDiagnostics tool"
```

### Task 3.2: Remove `[Active File: ...]` injection from UserPromptSubmit hook

**Files:**
- Modify: `hooks/scripts/user-prompt-submit.sh`

- [ ] **Step 1: Edit the hook**

Strip the entire block from the line `# Read metadata from context JSON` down through the `jq -n --arg ctx "$context" ...` invocation. After the snapshot block, the script should just exit 0 (no stdout output, so no context injection happens).

After edit, the script should be roughly:

```bash
#!/bin/bash
set -euo pipefail

input=$(cat)

# shellcheck source=lib/snapshot.sh
. "$(dirname "$0")/lib/snapshot.sh"

# Snapshot working tree state for new turn (used by Stop hook to compute diff).
context_file="${NVIM_CLAUDE_CONTEXT_FILE:-}"
if [ -n "$context_file" ]; then
  base_dir="$(dirname "$context_file")"
  rm -f "$base_dir/turn-baseline.sha" "$base_dir/turn-current.sha"

  baseline_sha=$(build_snapshot_commit "nvim-claude turn baseline")
  if [ -n "$baseline_sha" ]; then
    echo "$baseline_sha" > "$base_dir/turn-baseline.sha"
  fi
fi

# Active-file context now flows over the IDE WS protocol (lua/nvim-claude/ide/).
# This hook no longer injects [Active File: ...] into prompts.
exit 0
```

- [ ] **Step 2: Manual verification**

Trigger a turn. Confirm there's no `[Active File: ...]` block in the prompt anymore (it's now in Claude's status line live).

- [ ] **Step 3: Commit**

```bash
git add hooks/scripts/user-prompt-submit.sh
git commit -m "refactor(hooks): retire active-file injection (now via IDE protocol)"
```

### Task 3.3: Update SessionStart guidance

**Files:**
- Modify: `hooks/scripts/session-start.sh`

- [ ] **Step 1: Replace the inline guidance**

Replace the `[Neovim Session Connected]` text block with one that describes the new IDE-protocol tools instead of the bygone `open_in_nvim` MCP. Specifically:

- Mention that `openFile`, `openDiff`, `getCurrentSelection`, `getOpenEditors`, `getDiagnostics` are available
- Keep the "when to open files in nvim" guidance — it still applies, just the tool name is now `openFile`
- Drop any reference to `mcp__plugin_nvim-claude_nvim-claude__open_in_nvim`

- [ ] **Step 2: Commit**

```bash
git add hooks/scripts/session-start.sh
git commit -m "docs(hooks): update SessionStart guidance for IDE-protocol tools"
```

---

## Phase 4 — Cleanup and Release

### Task 4.1: Delete legacy MCP server bundle

**Files:**
- Delete: `servers/open-in-nvim.js`
- Delete: `dist/open-in-nvim.cjs`
- Delete: `package.json`, `package-lock.json`
- Delete: `node_modules/` (if present)

- [ ] **Step 1: Verify no other code references these**

```bash
grep -rn "open-in-nvim\|servers/open\|dist/open" \
  /root/projects/nvim-claude.feat.enhancements/ \
  --exclude-dir=node_modules --exclude-dir=.git
```

Expected: only matches in files we're about to delete (or none).

- [ ] **Step 2: Delete files**

```bash
cd /root/projects/nvim-claude.feat.enhancements
rm -rf servers/ dist/ package.json package-lock.json node_modules/
```

- [ ] **Step 3: Verify plugin still loads**

Restart nvim. No errors. Connection still works.

- [ ] **Step 4: Commit**

```bash
git add -A
git commit -m "chore: remove legacy open-in-nvim MCP server (superseded by IDE protocol)"
```

### Task 4.2: Bump plugin version and update marketplace

**Files:**
- Modify: `.claude-plugin/plugin.json`
- (External) marketplace.json in `agent-plugin-marketplace` repo

- [ ] **Step 1: Bump version**

In `.claude-plugin/plugin.json`, set `version` to `0.8.0`.

- [ ] **Step 2: Commit**

```bash
git add .claude-plugin/plugin.json
git commit -m "chore: bump version to 0.8.0"
```

- [ ] **Step 3: Manual reminder for marketplace**

Per `CLAUDE.md`, the marketplace.json in the `agent-plugin-marketplace` repo also needs a version bump for users to receive the update. This is done outside this repo. Do not consider the release "shipped" until that's pushed.

### Task 4.3: Update README

**Files:**
- Modify: `README.md`

- [ ] **Step 1: Edit README**

Add a new section under the existing feature list describing IDE-protocol integration. Include:
- That nvim-claude now appears as a connected IDE in Claude Code's TUI
- Live selection / current file flowing to Claude
- `openFile` / `openDiff` tools available
- New config keys: `ide.enabled`, `ide.auto_start`, `ide.selection_throttle_ms`
- Note: existing `open_in_nvim` MCP tool is removed; replaced by IDE-protocol `openFile`

Update the "Commands & Keybindings" table if any commands were added (none in this plan).

- [ ] **Step 2: Commit**

```bash
git add README.md
git commit -m "docs: document IDE protocol integration"
```

### Task 4.4: Update CLAUDE.md

**Files:**
- Modify: `CLAUDE.md`

- [ ] **Step 1: Edit project structure section**

Add `lua/nvim-claude/ide/` to the project structure tree with a one-line description.

Add a "Key Design Decisions" entry:

> - Active file / selection / diagnostics flow over the WebSocket IDE protocol (`lua/nvim-claude/ide/`), not the UserPromptSubmit hook. The hook is now snapshot-only. Hooks remain the right tool for turn-boundary events (no IDE-protocol equivalent for UserPromptSubmit/Stop).

Remove the bullet about the bundled MCP server (no longer accurate).

- [ ] **Step 2: Commit**

```bash
git add CLAUDE.md
git commit -m "docs: update CLAUDE.md for IDE-protocol architecture"
```

### Task 4.5: Final verification

- [ ] **Step 1: All tests pass**

```bash
tests/run.sh
```

- [ ] **Step 2: Full manual matrix**

- Fresh nvim → IDE indicator appears in Claude TUI
- Move cursor across files → status line updates
- Claude calls `openFile` (ask it to open a file) → file opens in nvim
- Claude calls `openDiff` (ask it to compare two files) → diff opens
- Claude calls `getDiagnostics` → returns current LSP diags
- Type a prompt → no `[Active File: ...]` text in the prompt
- Per-turn diff still opens at end of turn
- `<leader>ct` toggle still hides/shows preserving session
- tmux mode and nvim-split mode both work

- [ ] **Step 3: Tag the release**

```bash
git tag v0.8.0
```

- [ ] **Step 4: Final commit (if anything fixed during verification)**

Otherwise this phase is done.

---

## Risk-Triggered Bailout

If any of these conditions trigger, **stop and re-plan**:

1. **Phase 0 spike fails after one round of fixes** — protocol details are off; need to spend more time reading claudecode.nvim or Claude Code's source. Don't push forward into Phase 1.
2. **Status line doesn't update in Phase 1.6** despite events being sent — method name is wrong; need to dig into Claude Code's actual subscription mechanism. Don't proceed to Phase 2 until live updates work.
3. **Three or more consecutive tasks fail with "this depends on protocol detail X that we don't actually know"** — protocol notes from Task 0.2 are insufficient. Schedule a deeper read of claudecode.nvim before continuing.

In all bailout cases: do NOT delete the legacy MCP server (Phase 4) until the new path is fully working. Users should never be left with neither path functional.
