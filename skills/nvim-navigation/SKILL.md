---
name: nvim-navigation
description: >
  Open files in the user's Neovim editor via the open_in_nvim MCP tool.
  Use this skill whenever the user asks to "show me", "open", "go to",
  "navigate to", or "where is" a file or code location. Also use it
  proactively when you find something the user should look at — after
  locating a bug, finding a definition, or answering "where does X happen".
  Only works when connected to a Neovim session (NVIM_CLAUDE_SERVER is set).
---

When the user asks you to show them something in the codebase, or when you've
found code they should look at, open it in their Neovim editor using the
`open_in_nvim` MCP tool rather than just printing file contents in the chat.

This gives the user the code in their editor where they can read it with
syntax highlighting, scroll around, and start editing — much better than
reading a code block in a terminal.

## When to open files in Neovim

- User asks "show me where X is defined/used/called"
- User asks "open that file" or "go to that function"
- You've found a bug or issue and want to point the user to it
- You're explaining code and referencing a specific location
- After a search, when showing the user the relevant result

## When NOT to open files

- When you're reading files to do your own work (use Read tool instead)
- When the user just wants you to explain code inline
- When NVIM_CLAUDE_SERVER is not set (not connected to Neovim)

## How to use the tool

The tool takes a file path and an optional line number:

- `file`: path to the file (relative to cwd or absolute)
- `line`: line number to jump to (optional, but use it when you know the specific location)

When you know the exact line, always include it — jumping to line 42 of a
500-line file is much more helpful than just opening the file.

## Pacing

Opening a file switches the user's editor focus — doing it rapidly is
disorienting. Follow these rules:

- **One file per response** unless the user explicitly asks for multiple
  (e.g., "open both the test and the implementation")
- **After opening a file, pause and explain** what they're looking at and why,
  rather than immediately opening another
- **If you need to reference multiple locations**, describe the others in chat
  and offer to open them: "The other relevant spot is in auth.lua:45 — want
  me to open that too?"
- **Never open files in a loop** (e.g., iterating through search results)
