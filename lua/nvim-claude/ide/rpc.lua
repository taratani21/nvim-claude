local M = {}

function M.new()
  local self = { tools = {} }

  function self:register_tool(spec)
    self.tools[spec.name] = spec
  end

  local function err_response(id, code, message)
    return vim.json.encode({
      jsonrpc = "2.0", id = id,
      error = { code = code, message = message },
    })
  end

  function self:dispatch(payload)
    local ok, msg = pcall(vim.json.decode, payload)
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
      return vim.json.encode({
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
      return vim.json.encode({
        jsonrpc = "2.0", id = msg.id, result = result,
      })
    end

    return err_response(msg.id, -32601, "method not found: " .. tostring(msg.method))
  end

  return self
end

return M
