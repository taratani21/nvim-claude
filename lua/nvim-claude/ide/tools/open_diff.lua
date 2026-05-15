local M = {
  name = "openDiff",
  description = "Open a diff view between the original file and proposed new content; blocks until the user saves or rejects the change.",
  input_schema = {
    type = "object",
    properties = {
      old_file_path    = { type = "string", description = "Path of the original file." },
      new_file_path    = { type = "string", description = "Destination path for the proposed file (often same as old_file_path)." },
      new_file_contents = { type = "string", description = "Proposed new content." },
      tab_name         = { type = "string", description = "Label shown in the diff tab title." },
    },
    required = { "old_file_path", "new_file_path", "new_file_contents" },
  },
}

local TIMEOUT_MS  = 5 * 60 * 1000   -- 5 minutes
local POLL_MS     = 100               -- event-loop poll interval for vim.wait

local function as_text(text)
  return { content = { { type = "text", text = text } } }
end

--- Write `content` to a temp file whose name includes `label` for readability.
--- Returns the absolute path.
local function write_temp(content, label)
  local safe_label = (label or "diff"):gsub("[^%w_%-.]", "_")
  local path = vim.fn.tempname() .. "-" .. safe_label
  local f = assert(io.open(path, "w"), "could not create temp file: " .. path)
  f:write(content or "")
  f:close()
  return path
end

--- Try to detect the filetype for `path`, consulting existing buffers first.
local function detect_filetype(path)
  -- 1. Check if a buffer for this path already has a filetype set.
  local bufnr = vim.fn.bufnr(path)
  if bufnr ~= -1 then
    local ft = vim.api.nvim_get_option_value("filetype", { buf = bufnr })
    if ft and ft ~= "" then return ft end
  end

  -- 2. Use Neovim's builtin matcher (nvim >= 0.9).
  if vim.filetype and type(vim.filetype.match) == "function" then
    local ok, ft = pcall(vim.filetype.match, { filename = path })
    if ok and ft and ft ~= "" then return ft end
  end

  -- 3. Simple extension fallback.
  local ext = path:match("%.([%w_%-]+)$") or ""
  local map = {
    lua = "lua", ts = "typescript", js = "javascript",
    jsx = "javascriptreact", tsx = "typescriptreact",
    py = "python", go = "go", rs = "rust",
    c = "c", h = "c", cpp = "cpp", hpp = "cpp",
    md = "markdown", sh = "sh", bash = "bash",
    json = "json", yaml = "yaml", yml = "yaml", toml = "toml",
    vim = "vim",
  }
  return map[ext]
end

--- Find the best non-terminal, non-floating editor window to split into.
local function find_editor_win()
  for _, win in ipairs(vim.api.nvim_list_wins()) do
    local cfg = vim.api.nvim_win_get_config(win)
    if not (cfg.relative and cfg.relative ~= "") then   -- not floating
      local buf = vim.api.nvim_win_get_buf(win)
      local bt  = vim.api.nvim_get_option_value("buftype", { buf = buf })
      local ft  = vim.api.nvim_get_option_value("filetype", { buf = buf })
      local sidebar = ft == "neo-tree" or ft == "NvimTree" or ft == "oil"
                   or ft == "netrw"   or ft == "aerial"   or ft == "tagbar"
      if bt ~= "terminal" and bt ~= "prompt" and not sidebar then
        return win
      end
    end
  end
  return nil
end

function M.handler(args)
  local old_path    = args.old_file_path
  local new_path    = args.new_file_path
  local new_contents = args.new_file_contents
  local tab_name    = args.tab_name or vim.fn.fnamemodify(new_path or old_path or "diff", ":t")

  if not old_path or not new_path or not new_contents then
    return as_text("DIFF_REJECTED")
  end

  -- ── Write proposed content to a temp file ──────────────────────────────────
  local temp_path = write_temp(new_contents, vim.fn.fnamemodify(new_path, ":t"))

  -- ── Outcome is set by autocmds; vim.wait() polls until non-nil ─────────────
  local outcome = nil

  -- ── Open the diff layout ───────────────────────────────────────────────────
  -- Strategy:
  --   • Find (or create) a suitable editor window.
  --   • Load old_file_path (left / original side).
  --   • Split right and load temp_path (right / proposed side).
  --   • Run :diffthis on both.
  --   • Focus proposed buffer so the user can edit it.

  local target_win = find_editor_win()
  if target_win then
    vim.api.nvim_set_current_win(target_win)
  end

  -- Left side: original file (or empty scratch buffer for new files).
  local is_new_file = vim.fn.filereadable(old_path) == 0
  local orig_buf

  if is_new_file then
    orig_buf = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_name(orig_buf, old_path .. " (new file)")
    vim.api.nvim_set_option_value("buftype",    "nofile",  { buf = orig_buf })
    vim.api.nvim_set_option_value("modifiable", false,     { buf = orig_buf })
    vim.api.nvim_win_set_buf(vim.api.nvim_get_current_win(), orig_buf)
  else
    vim.cmd("edit " .. vim.fn.fnameescape(old_path))
    orig_buf = vim.api.nvim_get_current_buf()
  end
  vim.cmd("diffthis")

  -- Right side: proposed content in temp file.
  vim.cmd("rightbelow vsplit " .. vim.fn.fnameescape(temp_path))
  local proposed_buf = vim.api.nvim_get_current_buf()
  local proposed_win = vim.api.nvim_get_current_win()

  -- Give the proposed buffer a friendly name.
  pcall(vim.api.nvim_buf_set_name, proposed_buf, tab_name .. " (proposed)")

  -- Propagate filetype for syntax highlighting.
  local ft = detect_filetype(old_path) or detect_filetype(new_path)
  if ft and ft ~= "" then
    vim.api.nvim_set_option_value("filetype", ft, { buf = proposed_buf })
  end

  -- Make proposed buffer a write-interceptable scratch buffer.
  vim.api.nvim_set_option_value("buftype",   "acwrite", { buf = proposed_buf })
  vim.api.nvim_set_option_value("bufhidden", "wipe",    { buf = proposed_buf })
  vim.api.nvim_set_option_value("swapfile",  false,     { buf = proposed_buf })
  vim.cmd("diffthis")
  vim.cmd("wincmd =")

  -- ── Autocmds ───────────────────────────────────────────────────────────────
  local group = vim.api.nvim_create_augroup(
    "NvimClaudeOpenDiff_" .. proposed_buf, { clear = true })

  -- :w on the proposed buffer → accept.
  -- BufWriteCmd fires instead of the actual file write when buftype == "acwrite".
  vim.api.nvim_create_autocmd("BufWriteCmd", {
    group  = group,
    buffer = proposed_buf,
    callback = function()
      if outcome ~= nil then return end   -- already decided
      -- Copy current buffer contents to new_path (the real destination).
      local lines = vim.api.nvim_buf_get_lines(proposed_buf, 0, -1, false)
      local f = io.open(new_path, "w")
      if f then
        f:write(table.concat(lines, "\n"))
        -- Honour the buffer's end-of-line setting.
        if vim.api.nvim_get_option_value("eol", { buf = proposed_buf }) then
          f:write("\n")
        end
        f:close()
      end
      -- Mark the buffer as unmodified so Neovim doesn't complain.
      vim.api.nvim_set_option_value("modified", false, { buf = proposed_buf })
      outcome = "FILE_SAVED"
    end,
  })

  -- Buffer hidden / wiped → reject (if not already saved).
  -- BufUnload fires before BufHidden/BufWipeout and covers all close paths.
  vim.api.nvim_create_autocmd({ "BufUnload", "BufWipeout" }, {
    group  = group,
    buffer = proposed_buf,
    callback = function()
      if outcome == nil then
        outcome = "DIFF_REJECTED"
      end
    end,
  })

  -- ── Block until the user acts or timeout ───────────────────────────────────
  -- vim.wait() pumps the event loop (timers, I/O, autocmds) at POLL_MS intervals
  -- while our condition is false. This must be called from the main Neovim thread,
  -- which is guaranteed because tool handlers run inside vim.schedule().
  local timed_out = not vim.wait(TIMEOUT_MS, function()
    return outcome ~= nil
  end, POLL_MS)

  -- ── Cleanup ────────────────────────────────────────────────────────────────
  -- Remove our autocmd group (idempotent — already fired autocmds are gone).
  pcall(vim.api.nvim_del_augroup_by_id, group)

  -- Remove temp file from disk.
  pcall(os.remove, temp_path)

  -- If the proposed buffer is still alive, close its diff window quietly.
  if vim.api.nvim_buf_is_valid(proposed_buf) then
    -- Close the window; if it's the last window, nvim will open a new empty one.
    if vim.api.nvim_win_is_valid(proposed_win) then
      pcall(vim.api.nvim_win_close, proposed_win, true)
    end
    pcall(vim.api.nvim_buf_delete, proposed_buf, { force = true })
  end

  -- Turn off diff mode on the original side if still open.
  if vim.api.nvim_buf_is_valid(orig_buf) then
    for _, win in ipairs(vim.api.nvim_list_wins()) do
      if vim.api.nvim_win_get_buf(win) == orig_buf then
        pcall(function()
          vim.api.nvim_win_call(win, function() vim.cmd("diffoff") end)
        end)
        break
      end
    end
    -- Wipe the scratch "new file" placeholder we created (not a real file).
    if is_new_file then
      pcall(vim.api.nvim_buf_delete, orig_buf, { force = true })
    end
  end

  if timed_out then
    return as_text("DIFF_REJECTED")
  end

  return as_text(outcome or "DIFF_REJECTED")
end

return M
