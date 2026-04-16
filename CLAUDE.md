# nvim-claude

Neovim + Claude Code integration plugin. Dual-purpose: Neovim plugin (Lua) and Claude Code plugin (hooks, MCP).

## Project Structure

```
lua/nvim-claude/       Neovim plugin modules (Lua)
  init.lua             setup(), config, keybindings
  terminal.lua         terminal lifecycle, tmux detection
  send.lua             visual selection sending
  context.lua          active buffer context writing
  diff.lua             per-turn diff view via diffview.nvim
plugin/nvim-claude.lua user commands registration
hooks/                 Claude Code hooks (auto-registered)
  hooks.json           hook config (SessionStart, UserPromptSubmit, Stop)
  scripts/             hook shell scripts
servers/               MCP server source (ESM)
dist/                  bundled MCP server (committed, no npm install needed)
.claude-plugin/        Claude Code plugin manifest
.mcp.json              MCP server config
```

## Building

After modifying `servers/open-in-nvim.js`, rebuild the bundle:

```bash
npm install        # first time only, installs esbuild + MCP SDK
npm run build      # bundles to dist/open-in-nvim.cjs
```

The `dist/` directory is committed to git so consumers don't need npm. Always rebuild and commit `dist/` after changing server source.

## Version Bumping

When releasing changes, bump the version in **both** repos:

1. `.claude-plugin/plugin.json` in this repo
2. `.claude-plugin/marketplace.json` in `agent-plugin-marketplace`

Claude Code caches plugins by version — same version = no update.

## Key Design Decisions

- Context JSON stores only metadata + diagnostics, not file contents. The hook reads file contents from disk on-demand at query time.
- Per-turn diffs use `git stash create` for non-destructive working tree snapshots. Requires a git repo.
- MCP server uses `execFileSync` (no shell) to avoid escaping issues with `nvim --remote-send`.
- File navigation guidance is injected via a SessionStart hook (not a skill) so it only appears when connected to a Neovim session. This avoids wasted context and failed tool calls when no session exists.
- Status line is configured inline in user settings (not bundled) to avoid cache path breakage on version updates.
