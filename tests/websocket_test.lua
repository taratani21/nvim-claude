package.path = package.path .. ";./lua/?.lua;./lua/?/init.lua"
local ws = require("nvim-claude.ide.websocket")

-- Round-trip: encode then decode a small text frame.
local payload = '{"jsonrpc":"2.0","method":"ping"}'
local frame = ws.encode_frame({ opcode = 0x1, payload = payload, fin = true })
local decoded, rest = ws.decode_frame(frame)
assert(decoded ~= nil, "decode_frame returned nil")
assert(decoded.opcode == 0x1, "opcode mismatch: got " .. tostring(decoded.opcode))
assert(decoded.fin == true, "fin should be true")
assert(decoded.payload == payload, "payload mismatch")
assert(rest == "", "no remaining bytes expected, got " .. #rest)

-- Masked client→server frame should also decode.
local masked = ws.encode_frame({ opcode = 0x1, payload = payload, fin = true, mask = true })
local decoded_masked = ws.decode_frame(masked)
assert(decoded_masked.payload == payload, "masked payload mismatch")

-- Larger payload (>125 bytes triggers extended-length encoding).
local big = string.rep("x", 200)
local big_frame = ws.encode_frame({ opcode = 0x1, payload = big, fin = true })
local big_decoded = ws.decode_frame(big_frame)
assert(big_decoded.payload == big, "extended-length payload mismatch")

-- Partial frame: returns nil + leftover.
local partial, rest_partial = ws.decode_frame(string.sub(frame, 1, 3))
assert(partial == nil, "partial frame should return nil")
assert(rest_partial == string.sub(frame, 1, 3), "leftover should be untouched input")

print("websocket_test: PASS")
