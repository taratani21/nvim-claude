local M = {}

local function default_dir()
  local override = vim.env.CLAUDE_CONFIG_DIR
  if override and override ~= "" then
    return override .. "/ide"
  end
  return vim.fn.expand("~/.claude/ide")
end

local DIR = default_dir()

function M._set_dir_for_test(d) DIR = d end

local function ensure_dir()
  if vim.fn.isdirectory(DIR) == 0 then
    vim.fn.mkdir(DIR, "p", "0700")
  end
end

--- Lockfile filename uses port (not pid) per PROTOCOL.md.
function M.path_for(port)
  return DIR .. "/" .. port .. ".lock"
end

--- info: { port, pid, workspaceFolders, ideName, transport, authToken }
--- Writes everything except `port` into the file body (port = filename).
function M.write(info)
  assert(info.port, "lockfile.write requires info.port")
  ensure_dir()
  local path = M.path_for(info.port)
  local body = {
    pid = info.pid,
    workspaceFolders = info.workspaceFolders,
    ideName = info.ideName,
    transport = info.transport,
    authToken = info.authToken,
  }
  local f = assert(io.open(path, "w"))
  f:write(vim.fn.json_encode(body))
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
  pid = tonumber(pid)
  if not pid or pid <= 0 or pid ~= math.floor(pid) then
    return false
  end
  if vim.fn.has("linux") == 1 then
    return vim.fn.isdirectory("/proc/" .. pid) == 1
  end
  return os.execute("kill -0 " .. pid .. " 2>/dev/null") == 0
end

--- Reap lockfiles whose embedded pid is no longer alive.
--- (Filename is the port, so we have to read each file to find the pid.)
function M.reap_stale()
  if vim.fn.isdirectory(DIR) == 0 then return end
  for _, name in ipairs(vim.fn.readdir(DIR)) do
    if name:match("%.lock$") then
      local path = DIR .. "/" .. name
      local body = M.read(path)
      if not body or not pid_alive(body.pid) then
        M.remove(path)
      end
    end
  end
end

return M
