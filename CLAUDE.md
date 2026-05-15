# nvim-claude

Neovim + Claude Code integration plugin. Dual-purpose: Neovim plugin (Lua) and Claude Code plugin (hooks).

## Project Structure

```
lua/nvim-claude/       Neovim plugin modules (Lua)
  init.lua             setup(), config, keybindings
  terminal.lua         terminal lifecycle, tmux detection
  send.lua             visual selection sending
  context.lua          active buffer context writing
  diff.lua             per-turn diff view via diffview.nvim
  ide/                 WebSocket-based IDE protocol server, tools, events
plugin/nvim-claude.lua user commands registration
hooks/                 Claude Code hooks (auto-registered)
  hooks.json           hook config (SessionStart, UserPromptSubmit, Stop)
  scripts/             hook shell scripts
    lib/snapshot.sh    temp-index git snapshots for per-turn diffs
tests/                 headless nvim test suite
.claude-plugin/        Claude Code plugin manifest
```

## Testing

```bash
tests/run.sh
```

Runs all `tests/*_test.lua` files in headless nvim.

## Version Bumping

When releasing changes, bump the version in **both** repos:

1. `.claude-plugin/plugin.json` in this repo
2. `.claude-plugin/marketplace.json` in `agent-plugin-marketplace`

Claude Code caches plugins by version — same version = no update.

## Key Design Decisions

- Context JSON stores only metadata + diagnostics, not file contents. The hook reads file contents from disk on-demand at query time.
- Active file / selection / diagnostics flow over the WebSocket IDE protocol (`lua/nvim-claude/ide/`), not the UserPromptSubmit hook. The hook is now snapshot-only. Hooks remain the right tool for turn-boundary events (no IDE-protocol equivalent for UserPromptSubmit/Stop).
- Per-turn diff snapshots use a temp git index to capture both tracked and untracked files (`hooks/scripts/lib/snapshot.sh`) without disturbing the user's actual git index. Both pre-turn and post-turn snapshots are built so new files Claude creates appear in the diff.
- File navigation guidance is injected via a SessionStart hook (not a skill) so it only appears when connected to a Neovim session. This avoids wasted context and failed tool calls when no session exists.
- Status line is configured inline in user settings (not bundled) to avoid cache path breakage on version updates.
