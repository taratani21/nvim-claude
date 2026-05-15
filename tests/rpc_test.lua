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
local list_decoded = vim.json.decode(list_resp)
assert(list_decoded.id == 1)
assert(#list_decoded.result.tools == 1)
assert(list_decoded.result.tools[1].name == "echo")

-- tools/call invokes handler
local call_resp = d:dispatch(vim.json.encode({
  jsonrpc = "2.0", id = 2, method = "tools/call",
  params = { name = "echo", arguments = { msg = "hi" } },
}))
local call_decoded = vim.json.decode(call_resp)
assert(call_decoded.id == 2)
assert(call_decoded.result.content[1].text == "hi")

-- Unknown method returns JSON-RPC error
local err_resp = d:dispatch('{"jsonrpc":"2.0","id":3,"method":"bogus"}')
local err_decoded = vim.json.decode(err_resp)
assert(err_decoded.error ~= nil, "should return error envelope")
assert(err_decoded.error.code == -32601, "method not found = -32601")

print("rpc_test: PASS")
