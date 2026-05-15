# IDE Protocol Reference

Source: https://github.com/coder/claudecode.nvim/blob/main/PROTOCOL.md
Cross-referenced against:
- `/tmp/claudecode-ref/lua/claudecode/lockfile.lua`
- `/tmp/claudecode-ref/lua/claudecode/server/handshake.lua`
- `/tmp/claudecode-ref/lua/claudecode/server/init.lua`
- `/tmp/claudecode-ref/lua/claudecode/server/client.lua`
- `/tmp/claudecode-ref/lua/claudecode/tools/init.lua`
Captured: 2026-05-15

---

## Lockfile

**Source: PROTOCOL.md (authoritative)**

Path: `~/.claude/ide/<port>.lock`

The filename key is the **WebSocket port number** (an integer in range 10000–65535), not a UUID or name.
Example: `~/.claude/ide/12345.lock`

Override: if env var `CLAUDE_CONFIG_DIR` is set, use `$CLAUDE_CONFIG_DIR/ide/<port>.lock` instead of `~/.claude/ide/<port>.lock`.
(Source: lockfile.lua — inferred from source)

Permissions: not explicitly stated in PROTOCOL.md. The claudecode.nvim reference implementation writes with default `io.open("w")` permissions (no explicit chmod). No special ownership requirements mentioned.

Schema:

| Field | Type | Required | Description |
|---|---|---|---|
| `pid` | number | yes | IDE process ID (from `vim.fn.getpid()`) |
| `workspaceFolders` | string[] | yes | Array of absolute folder paths currently open. Starts with `cwd`, adds LSP workspace folders. |
| `ideName` | string | yes | Human-readable editor name, e.g. `"Neovim"`, `"VS Code"` |
| `transport` | string | yes | Must be `"ws"` (WebSocket) |
| `authToken` | string | yes | Random UUID v4, e.g. `"550e8400-e29b-41d4-a716-446655440000"`. Min 10 chars, max 500 chars. |

Example lockfile content:
```json
{
  "pid": 12345,
  "workspaceFolders": ["/path/to/project"],
  "ideName": "Neovim",
  "transport": "ws",
  "authToken": "550e8400-e29b-41d4-a716-446655440000"
}
```

---

## Environment Variables

**Source: PROTOCOL.md (authoritative)**

The IDE must set these when launching Claude:

| Variable | Value | Notes |
|---|---|---|
| `CLAUDE_CODE_SSE_PORT` | Port number as string, e.g. `"12345"` | Claude reads this to find the matching lock file |
| `ENABLE_IDE_INTEGRATION` | `"true"` | Signals IDE integration is active |

---

## Handshake

**Source: PROTOCOL.md (authoritative) + handshake.lua (inferred)**

Claude connects to the WebSocket server and performs a standard RFC 6455 HTTP upgrade handshake.

### HTTP headers Claude sends on upgrade

| Header | Value | Notes |
|---|---|---|
| `Upgrade` | `websocket` | Standard WS upgrade |
| `Connection` | `Upgrade` | Standard WS |
| `Sec-WebSocket-Key` | Base64-encoded 16 bytes (24 chars) | Standard WS, used to compute Accept |
| `Sec-WebSocket-Version` | `13` | Required, must be exactly `"13"` |
| `x-claude-code-ide-authorization` | The `authToken` value from lockfile | **Custom auth header** — this is how Claude authenticates |
| `Sec-WebSocket-Protocol` | Unknown (echoed back by server if present) | Optional; server echoes whatever client sends |

The critical authentication header name is exactly:
```
x-claude-code-ide-authorization: <authToken>
```

### Server handshake response

```
HTTP/1.1 101 Switching Protocols
Upgrade: websocket
Connection: Upgrade
Sec-WebSocket-Accept: <computed_accept_key>
Sec-WebSocket-Protocol: <echoed_from_client>   (only if client sent one)
```

Accept key is computed via standard RFC 6455: SHA-1 of `<client_key> + "258EAFA5-E914-47DA-95CA-C5AB0DC85B11"`, then base64-encoded.

### After upgrade: MCP initialize exchange

**Source: server/init.lua (inferred) — PROTOCOL.md does not show the exact initialize request**

Claude sends an MCP `initialize` request immediately after upgrade:

```json
{
  "jsonrpc": "2.0",
  "id": 1,
  "method": "initialize",
  "params": {
    "protocolVersion": "2024-11-05",
    "capabilities": {},
    "clientInfo": {
      "name": "claude-code",
      "version": "<version>"
    }
  }
}
```

Note: The exact params Claude sends are **inferred from MCP spec 2025-03-26**. PROTOCOL.md does not show the request shape verbatim. The server only uses the `id` field from the request to form its response.

### Required `initialize` response shape

**Source: server/init.lua (authoritative from reference implementation)**

MCP protocol version used by claudecode.nvim: `"2024-11-05"` (set as `MCP_PROTOCOL_VERSION` constant).

```json
{
  "jsonrpc": "2.0",
  "id": 1,
  "result": {
    "protocolVersion": "2024-11-05",
    "capabilities": {
      "logging": {},
      "prompts": { "listChanged": true },
      "resources": { "subscribe": true, "listChanged": true },
      "tools": { "listChanged": true }
    },
    "serverInfo": {
      "name": "claudecode-neovim",
      "version": "<plugin_version>"
    }
  }
}
```

### After initialize: notifications/initialized

**Source: server/init.lua (inferred)**

Claude sends a notification (no `id`, no response expected):
```json
{
  "jsonrpc": "2.0",
  "method": "notifications/initialized",
  "params": {}
}
```

The server handles this as a no-op.

### After initialized: tools/list and prompts/list

Claude then queries the tool list:
```json
{
  "jsonrpc": "2.0",
  "id": 2,
  "method": "tools/list",
  "params": {}
}
```

Response:
```json
{
  "jsonrpc": "2.0",
  "id": 2,
  "result": {
    "tools": [ /* array of tool definitions */ ]
  }
}
```

Claude also queries:
```json
{ "jsonrpc": "2.0", "id": 3, "method": "prompts/list", "params": {} }
```
Response: `{ "jsonrpc": "2.0", "id": 3, "result": { "prompts": [] } }`

---

## Tools (IDE side, called by Claude via `tools/call`)

**Source: PROTOCOL.md (authoritative) + tools/init.lua (inferred for registration)**

Tool invocations use method `tools/call`:
```json
{
  "jsonrpc": "2.0",
  "id": "<request-id>",
  "method": "tools/call",
  "params": {
    "name": "<toolName>",
    "arguments": { /* tool-specific */ }
  }
}
```

All tool responses have shape:
```json
{
  "jsonrpc": "2.0",
  "id": "<request-id>",
  "result": {
    "content": [{ "type": "text", "text": "<json-stringified or plain string>" }]
  }
}
```

### Complete tool list (10 MCP-exposed + 1 internal)

**Source: tools/init.lua register_all() — authoritative tool name list**

| Tool | Exposed via MCP | Input | Output | Notes |
|---|---|---|---|---|
| `openFile` | yes | `filePath` (req), `preview`, `startText`, `endText`, `selectToEndOfLine`, `makeFrontmost` | Text message or JSON with `success`, `filePath`, `languageId`, `lineCount` | See details below |
| `openDiff` | yes | `old_file_path`, `new_file_path`, `new_file_contents`, `tab_name` | `"FILE_SAVED"` or `"DIFF_REJECTED"` | **Blocking** — waits for user interaction |
| `getCurrentSelection` | yes | none | JSON: `{success, text, filePath, selection}` or `{success: false, message}` | Current editor selection |
| `getLatestSelection` | yes | none | JSON: `{success, text, filePath, selection}` or `{success: false, message}` | Most recent selection, even if editor unfocused |
| `getOpenEditors` | yes | none | JSON: `{tabs: [{uri, isActive, label, languageId, isDirty}]}` | All open tabs |
| `getWorkspaceFolders` | yes | none | JSON: `{success, folders: [{name, uri, path}], rootPath}` | All workspace folders |
| `getDiagnostics` | yes | `uri` (optional file URI) | JSON array: `[{uri, diagnostics: [{message, severity, range, source}]}]` | LSP diagnostics; no uri = all files |
| `checkDocumentDirty` | yes | `filePath` (req) | JSON: `{success, filePath, isDirty, isUntitled}` or `{success: false, message}` | Checks unsaved changes |
| `saveDocument` | yes | `filePath` (req) | JSON: `{success, filePath, saved, message}` or `{success: false, message}` | Saves a document |
| `closeAllDiffTabs` | yes | none | Text: `"CLOSED_<count>_DIFF_TABS"` | Closes all diff editor tabs |
| `close_tab` | **internal only** (no MCP schema) | `tab_name` (req) | Text: `"TAB_CLOSED"` | Snake_case — not exposed in tools/list |

Note: `executeCode` (Jupyter kernel tool) appears in PROTOCOL.md as tool #12 from the VS Code extension but is **not registered** in the claudecode.nvim reference implementation. It is VS Code–specific.

### Naming convention note (from PROTOCOL.md)

Most tools are camelCase (`openFile`, `getCurrentSelection`, etc.). The exception is `close_tab` which uses snake_case — and it's not MCP-exposed anyway.

### openFile detailed input

```json
{
  "filePath": "/path/to/file.js",
  "preview": false,
  "startText": "function hello",
  "endText": "}",
  "selectToEndOfLine": false,
  "makeFrontmost": true
}
```

Fields: `filePath` (string, required), `preview` (bool, default false), `startText` (string, optional), `endText` (string, optional), `selectToEndOfLine` (bool, default false), `makeFrontmost` (bool, default true).

When `makeFrontmost=true`: returns `{"content": [{"type": "text", "text": "Opened file: /path/to/file.js"}]}`
When `makeFrontmost=false`: returns detailed JSON string with `success`, `filePath`, `languageId`, `lineCount`.

### getDiagnostics severity values

Severity is a string: `"Error"`, `"Warning"`, `"Information"`, `"Hint"` (matching VS Code DiagnosticSeverity enum names).

---

## Push Notifications (IDE → Claude)

**Source: PROTOCOL.md (authoritative)**

These are JSON-RPC notifications (no `id`, no response expected from Claude).

### `selection_changed`

Sent whenever the user's selection changes in the editor:

```json
{
  "jsonrpc": "2.0",
  "method": "selection_changed",
  "params": {
    "text": "selected text content",
    "filePath": "/absolute/path/to/file.js",
    "fileUrl": "file:///absolute/path/to/file.js",
    "selection": {
      "start": { "line": 10, "character": 5 },
      "end": { "line": 15, "character": 20 },
      "isEmpty": false
    }
  }
}
```

**This is the exact method name: `selection_changed`** (snake_case, not `selectionChanged`, not `notifications/selection_changed`).

### `at_mentioned`

Sent when the user explicitly sends a selection as context (e.g., via a keybinding):

```json
{
  "jsonrpc": "2.0",
  "method": "at_mentioned",
  "params": {
    "filePath": "/path/to/file",
    "lineStart": 10,
    "lineEnd": 20
  }
}
```

**Exact method name: `at_mentioned`** (snake_case).

---

## WebSocket Transport Details

**Source: PROTOCOL.md + client.lua (inferred)**

- Bind to `127.0.0.1` only (localhost), never `0.0.0.0`
- Port range: 10000–65535 (random selection)
- Protocol: RFC 6455 WebSocket over TCP
- Frame types: TEXT (opcode 0x1) used for JSON-RPC messages; BINARY also accepted and treated as text
- Fragmented messages are NOT supported (close with code 1003 if received)
- PING/PONG keepalive: server sends PING every 30 seconds; client timeout after 30 seconds without PONG
- Messages are standard JSON-RPC 2.0:
  - Requests: have `id` field → require response
  - Notifications: no `id` field → no response

---

## Server-side JSON-RPC Method Handlers

**Source: server/init.lua (inferred)**

The IDE WebSocket server must handle these inbound methods from Claude:

| Method | Type | Notes |
|---|---|---|
| `initialize` | Request | Returns capabilities and server info |
| `notifications/initialized` | Notification | No-op, just acknowledge |
| `prompts/list` | Request | Return `{ "prompts": [] }` |
| `tools/list` | Request | Return `{ "tools": [...] }` |
| `tools/call` | Request | Invoke tool handler by `params.name` |

---

## Open Questions / Gaps in PROTOCOL.md

1. **Exact `initialize` request params from Claude**: PROTOCOL.md does not show what params Claude includes in its `initialize` request. We know the method name and that the server must respond with `protocolVersion`, `capabilities`, `serverInfo`. The MCP spec 2025-03-26 shape is used as a guide.

2. **`Sec-WebSocket-Protocol` subprotocol value**: PROTOCOL.md does not state what subprotocol string (if any) Claude sends. The claudecode.nvim server simply echoes it back — our implementation should do the same (don't require a specific value, just echo).

3. **Lock file permissions**: PROTOCOL.md says nothing about file mode bits. The reference implementation uses default `io.open("w")` permissions. This is probably fine; Claude just needs to read the file.

4. **`executeCode` tool**: Present in PROTOCOL.md's VS Code tool list (tool #12) but not in claudecode.nvim's Neovim implementation. We will not implement it — it's Jupyter-specific.

5. **`resources/list`, `resources/read`**: Not mentioned in PROTOCOL.md for this protocol. Likely not needed; `capabilities.resources` is declared but no handlers are required for basic IDE recognition.

6. **Exact `id` types in JSON-RPC**: The `id` field may be a string or number. The reference implementation uses `tostring(id)` when routing, so both are acceptable.
