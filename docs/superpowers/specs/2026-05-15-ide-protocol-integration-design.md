# IDE Protocol Integration

## Overview

Connect nvim-claude to Claude Code via the same WebSocket-based IDE protocol the official VS Code and JetBrains plugins use. Unlocks the "connected IDE" status line in the Claude TUI (current file, line range, IDE name), live selection/file events, and Claude-initiated `openFile`/`openDiff` against nvim — capabilities that hooks alone cannot provide.

Existing nvim-claude features (tmux-pane spawn, visibility toggle, per-turn diff via diffview, snapshot-at-turn-boundary hooks) are preserved unchanged.

## Goals

- Claude Code's TUI status line shows the active nvim file and selection.
- Cursor/selection/buffer changes pushed to Claude in real time, replacing the current per-turn `[Active File: ...]` text injection.
- Claude can open files and diffs in nvim through the standard IDE-protocol tools, not a custom MCP wrapper.
- Plugin keeps working when Claude Code is launched without IDE protocol awareness (graceful degradation).

## Non-goals

- Per-turn diff picker / shadow-repo storage (deferred — separate spec).
- Replacing the snapshot-at-turn-boundary hooks. UserPromptSubmit and Stop have no IDE-protocol equivalent.
- Forking claudecode.nvim. We borrow its protocol implementation (Apache-2.0) as permitted derivative work, with attribution.
- Supporting more than one connected Claude Code session per nvim instance. Documented limitation; multi-client comes later if needed.

## Architecture

### What stays from current plugin

| Module | Role |
|---|---|
| `lua/nvim-claude/terminal.lua` | tmux + nvim spawn, visibility toggle |
| `hooks/scripts/user-prompt-submit.sh` | turn-baseline snapshot |
| `hooks/scripts/stop.sh` | turn-current snapshot, diff trigger |
| `hooks/scripts/lib/snapshot.sh` | git tree commit helper |
| `lua/nvim-claude/diff.lua` | diffview integration |
| `lua/nvim-claude/context.lua` | will keep for snapshot-related state, see below |

### What's added

```
lua/nvim-claude/
  ide/
    init.lua          -- public API: start(), stop(), is_connected()
    server.lua        -- vim.uv TCP server, WebSocket upgrade handshake
    websocket.lua     -- WS frame encode/decode (borrowed from claudecode.nvim)
    rpc.lua           -- JSON-RPC 2.0 dispatcher
    lockfile.lua      -- write/cleanup ~/.claude/ide/<port>.lock
    tools/
      get_current_selection.lua
      get_open_editors.lua
      get_workspace_folders.lua
      get_diagnostics.lua
      open_file.lua
      open_diff.lua
    events.lua        -- autocmd → push notifications to client
NOTICE                 -- attribution for borrowed claudecode.nvim code
```

### What's removed

| Component | Replacement |
|---|---|
| `servers/open-in-nvim.js` (MCP server) | IDE protocol's `openFile` tool |
| `dist/open-in-nvim.cjs` (bundled artifact) | (no replacement needed) |
| `.mcp.json` registration of `open-in-nvim` | removed entry |
| Active-file context written to `/tmp/nvim-claude/<hash>.json` | live event push over WS |
| `[Active File: ...]` injection in `user-prompt-submit.sh` | live event push over WS |
| `nvim-navigation` skill (or its bundled-tool equivalent) | unchanged on disk; the SessionStart guidance now describes the IDE-protocol tools |

The `context.lua` module is repurposed: instead of writing buffer JSON for hook consumption, it owns the snapshot-related state files (turn-baseline.sha, turn-current.sha) that hooks still produce.

## Data Flow

### Connection lifecycle

```
nvim startup
  └─ nvim-claude.setup() → ide.start()
       ├─ server.lua binds 127.0.0.1:<random_port>
       ├─ lockfile.lua writes ~/.claude/ide/<pid>.lock with {port, authToken, ideName, workspaceFolders}
       └─ events.lua registers autocmds (BufEnter, CursorMoved, ModeChanged, DiagnosticChanged, VimLeavePre)

terminal.lua spawn (tmux pane or nvim split)
  └─ env: NVIM_CLAUDE_SERVER, NVIM_CLAUDE_CONTEXT_FILE (unchanged)

Claude Code starts
  └─ scans ~/.claude/ide/*.lock
  └─ connects to ws://127.0.0.1:<port> with Authorization: Bearer <authToken>
  └─ JSON-RPC initialize handshake
  └─ Claude TUI status line shows connected IDE + active file

User edits in nvim
  └─ autocmd fires
  └─ events.lua sends notification: { method: "selection_changed", params: {...} }
  └─ Claude TUI updates status line

Claude calls openFile
  └─ rpc.lua dispatches to tools/open_file.lua
  └─ open_file.lua does vim.cmd("edit "..path) etc., returns success

VimLeavePre
  └─ ide.stop() closes server, removes lockfile
```

### Coexistence with hooks

```
UserPromptSubmit hook
  └─ snapshot.sh → turn-baseline.sha
  └─ NO LONGER injects [Active File: ...] (Claude already knows via WS)

Stop hook
  └─ snapshot.sh → turn-current.sha
  └─ Triggers diffview via existing nvim --remote-expr path
     (could be migrated to a new RPC method later, out of scope)
```

## Components

### `ide/server.lua` and `ide/websocket.lua`

`vim.uv` TCP server bound to `127.0.0.1`. Per-connection HTTP→WS upgrade handshake (RFC 6455), then framed JSON-RPC. Bearer-token auth required on the upgrade request — must match the token written to the lockfile, otherwise reject.

WebSocket frame plumbing is the most error-prone part to reimplement; borrow `claudecode.nvim`'s implementation (their `websocket.lua` is mature, Apache-2.0, well-tested against Claude Code's specific framing quirks). Attribute in `NOTICE`.

### `ide/lockfile.lua`

Writes `~/.claude/ide/<pid>.lock` containing JSON:

```json
{
  "pid": 12345,
  "port": 53917,
  "authToken": "<random 32-byte hex>",
  "ideName": "Neovim",
  "workspaceFolders": ["/abs/path/to/cwd"],
  "transport": "ws"
}
```

Removed on `VimLeavePre`. Stale lockfiles from crashed nvim instances are reaped at `start()` time by checking each `pid` file under `~/.claude/ide/` against `/proc/<pid>` — remove if process is gone.

### `ide/rpc.lua`

JSON-RPC 2.0 dispatcher. Registers tool handlers and translates between MCP-flavored request/response envelopes and the underlying tool functions. Handles `initialize`, `tools/list`, `tools/call`. Each tool returns `{ content: [...], isError?: bool }` per MCP convention.

### Tool implementations (`ide/tools/*.lua`)

Each tool is a Lua module exposing `name`, `description`, `input_schema`, and `handler(args)`. Handlers run on the main nvim event loop via `vim.schedule()` so they can call vim API safely.

| Tool | Behavior |
|---|---|
| `getCurrentSelection` | Return `{text, filePath, startLine, startColumn, endLine, endColumn}` for the current visual selection or cursor position |
| `getOpenEditors` | Return list of buffers with `buftype==""` and a real file path; mark the active one |
| `getWorkspaceFolders` | Return `[{uri, name}]` — currently just `vim.fn.getcwd()`. Single entry in v1 |
| `getDiagnostics` | Return diagnostics from `vim.diagnostic.get()` for a given file or all files |
| `openFile` | `vim.cmd("edit "..path)`, optionally jump to line/column. Same surface as today's custom `open_in_nvim` |
| `openDiff` | Open a diff view comparing two file paths or in-memory content. Implementation choice (built-in `:diffsplit` vs `diffview.nvim`) deferred to phase 2 |

### `ide/events.lua`

Subscribes to nvim autocmds and pushes WS notifications:

| Event | nvim autocmd | Notification |
|---|---|---|
| Active buffer changed | `BufEnter` | `selection_changed` (file + cursor) |
| Selection changed | `CursorMoved`, `ModeChanged` | `selection_changed` |
| Diagnostics updated | `DiagnosticChanged` | `at_mentioned_files_changed` (or similar; protocol-specific) |
| Workspace changed | `DirChanged` | reconnect-on-next via lockfile rewrite |

Throttled to ~10Hz to avoid flooding Claude Code on rapid cursor movement.

## Implementation Phases

### Phase 0 — Spike (decision gate)

Stand up a minimal WS server + lockfile. Goal: launch nvim, launch Claude Code, observe the connected-IDE indicator in Claude's TUI. No tools needed beyond `initialize`.

If Claude Code does **not** recognize the connection, abort and reconsider — protocol may have changed since claudecode.nvim's last update, or have undiscovered handshake requirements. Do not invest in phases 1–4 until this is green.

Estimated: 0.5–1 day.

### Phase 1 — Status line MVP

Implement `getCurrentSelection`, `getOpenEditors`, `getWorkspaceFolders`. Push `selection_changed` events. Verify Claude's status line shows current nvim file and updates as the user moves around.

Estimated: 1 day.

### Phase 2 — File and diff opening

Implement `openFile` and `openDiff`. Begin parallel removal of the custom `open-in-nvim` MCP server (keep in tree but unregister from `.mcp.json`).

Estimated: 0.5 day.

### Phase 3 — Diagnostics + active-file injection retirement

Implement `getDiagnostics`. Remove `[Active File: ...]` block from `user-prompt-submit.sh` since Claude now has it live. Update SessionStart guidance to describe new tools.

Estimated: 0.5 day.

### Phase 4 — Cleanup and release

Delete `servers/`, `dist/`, related npm files. Update README, plugin.json (`v0.8.0`), marketplace.json. Write migration note for users who manually configured `open-in-nvim`.

Estimated: 0.5 day.

Total: ~3 days of focused work.

## Configuration

New options under `setup()`:

```lua
require("nvim-claude").setup({
  ide = {
    enabled = true,                  -- master switch
    host = "127.0.0.1",              -- never bind public
    auto_start = true,               -- start server in setup() vs. manual ide.start()
    selection_throttle_ms = 100,     -- min ms between push events
  },
})
```

## Testing

- **Phase-0 manual:** lockfile present, port listening, Claude TUI shows connection.
- **Unit:** WS frame encode/decode roundtrip; JSON-RPC envelope validation; lockfile write/parse.
- **Integration:** headless nvim starts server → throwaway luv-based WS client connects, exchanges `initialize`, calls each tool, asserts shape of response.
- **Manual matrix:** tmux mode + nvim-split mode × Claude Code launched fresh + Claude already running × multiple buffers open.
- **Regression:** existing per-turn diff still opens after Stop; `<leader>ct` toggle still preserves session; visual selection still flows via `:ClaudeSend` (separate path, unaffected).

## Risks and Mitigations

| Risk | Mitigation |
|---|---|
| Claude Code changes IDE protocol | Track claudecode.nvim's commit log as a canary; their fixes telegraph our needed patches |
| WebSocket framing edge cases | Borrow battle-tested impl from claudecode.nvim rather than re-deriving |
| Auth token leak via lockfile readable by others | `~/.claude/ide/` is user-owned 0700 by default; verify and chmod if not |
| Multiple Claude clients connect simultaneously | v1 accepts only one connection at a time; second connection refused |
| nvim crashes leaving stale lockfile | Reap stale lockfiles by `/proc/<pid>` check at start |
| Server bind fails (port exhaustion, firewall) | Log warning, set `is_connected()=false`, plugin continues working without IDE features |
| Borrowed Apache-2.0 code requires NOTICE | Add `NOTICE` file with attribution at repo root |

## Prior Art

- [`coder/claudecode.nvim/PROTOCOL.md`](https://github.com/coder/claudecode.nvim/blob/main/PROTOCOL.md) — **the** community-maintained spec of Claude Code's IDE protocol: lockfile schema, handshake, tool surface, event method names. Primary reference for everything in this design — consult it before reading source code or guessing.
- [`coder/claudecode.nvim`](https://github.com/coder/claudecode.nvim) — Apache-2.0; reference implementation of the protocol for Neovim, source of borrowed WS framing code. Forces Claude into an nvim terminal split (no tmux), which is why this spec exists rather than a switch to that plugin.
- [Anthropic's VS Code extension](https://code.claude.com/docs/en/vs-code) — closed source. Behavioral reference only.
- [GitHub issue #6686](https://github.com/anthropics/claude-code/issues/6686) — Anthropic declined to standardize the IDE protocol on Zed's open ACP spec. Confirms protocol stability is on us, not Anthropic.

## What's Not Included

- Multi-client connection support.
- Migration of the per-turn diff trigger (Stop hook → diff.lua) to an RPC path. Stays as `nvim --remote-expr` for now.
- Diff picker (separate deferred spec).
- Shadow-repo storage for diff history (separate deferred spec).
- Replacing UserPromptSubmit/Stop hooks. They remain the snapshot trigger.
- Per-server scoping of state files in `/tmp/nvim-claude/`. Tracked separately as a small cleanup; doesn't block this work.
