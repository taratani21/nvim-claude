package.path = package.path .. ";./lua/?.lua;./lua/?/init.lua"
local lockfile = require("nvim-claude.ide.lockfile")

local tmp = vim.fn.tempname()
vim.fn.mkdir(tmp, "p")
lockfile._set_dir_for_test(tmp)

local info = {
  port = 53917,
  pid = vim.fn.getpid(),
  workspaceFolders = { vim.fn.getcwd() },
  ideName = "Neovim",
  transport = "ws",
  authToken = "deadbeef" .. string.rep("0", 56),
}

local path = lockfile.write(info)
assert(path:find(tmp, 1, true), "lockfile path should be under tmp dir")
assert(path:match("/53917%.lock$"), "filename should be <port>.lock, got: " .. path)
assert(vim.fn.filereadable(path) == 1, "lockfile should be readable")

local read_back = lockfile.read(path)
-- Note: 'port' is NOT in the file body — it's only in the filename
assert(read_back.pid == info.pid, "pid mismatch")
assert(read_back.authToken == info.authToken, "authToken mismatch")
assert(read_back.ideName == "Neovim", "ideName mismatch")
assert(read_back.transport == "ws", "transport mismatch")
assert(type(read_back.workspaceFolders) == "table", "workspaceFolders missing")

-- Stale reaper: write a lockfile whose embedded pid is dead, reap should remove it.
local stale_path = tmp .. "/9999.lock"
local f = io.open(stale_path, "w")
f:write(vim.fn.json_encode({ pid = 99999999, workspaceFolders = {}, ideName = "x", transport = "ws", authToken = "x" }))
f:close()
lockfile.reap_stale()
assert(vim.fn.filereadable(stale_path) == 0, "stale lockfile should be removed")
assert(vim.fn.filereadable(path) == 1, "our live lockfile should remain")

lockfile.remove(path)
assert(vim.fn.filereadable(path) == 0, "remove should delete the file")

print("lockfile_test: PASS")
