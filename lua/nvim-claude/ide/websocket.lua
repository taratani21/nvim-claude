-- Derived from claudecode.nvim (Apache-2.0).
-- See NOTICE in repo root.
--
-- WebSocket frame encode/decode (RFC 6455).
-- Public API consumed by Task 0.5's server.lua:
--   encode_frame(opts)  -> binary string
--   decode_frame(buf)   -> (frame_table, remaining) | (nil, original_buf)

local M = {}

-- ---------------------------------------------------------------------------
-- Internal helpers (inlined from claudecode.nvim's utils.lua)
-- ---------------------------------------------------------------------------

---XOR lookup table for fast byte-level masking.
local xor_table = {}
for i = 0, 255 do
  xor_table[i] = {}
  for j = 0, 255 do
    local result = 0
    local a, b = i, j
    local bit_val = 1
    while a > 0 or b > 0 do
      if (a % 2) ~= (b % 2) then
        result = result + bit_val
      end
      a = math.floor(a / 2)
      b = math.floor(b / 2)
      bit_val = bit_val * 2
    end
    xor_table[i][j] = result
  end
end

---Apply (or remove) a 4-byte XOR mask to/from a payload.
---@param data string
---@param mask string  4-byte mask key
---@return string
local function apply_mask(data, mask)
  local result = {}
  local mask_bytes = { mask:byte(1, 4) }
  for i = 1, #data do
    local mi = ((i - 1) % 4) + 1
    result[i] = string.char(xor_table[data:byte(i)][mask_bytes[mi]])
  end
  return table.concat(result)
end

---Encode a 16-bit number as 2 big-endian bytes.
---@param num number
---@return string
local function uint16_to_bytes(num)
  return string.char(math.floor(num / 256), num % 256)
end

---Encode a number as 8 big-endian bytes (uint64).
---@param num number
---@return string
local function uint64_to_bytes(num)
  local bytes = {}
  for i = 8, 1, -1 do
    bytes[i] = num % 256
    num = math.floor(num / 256)
  end
  return string.char(unpack(bytes))
end

---Decode 2 big-endian bytes to a number.
---@param s string
---@return number
local function bytes_to_uint16(s)
  return s:byte(1) * 256 + s:byte(2)
end

---Decode 8 big-endian bytes to a number.
---@param s string
---@return number
local function bytes_to_uint64(s)
  local n = 0
  for i = 1, 8 do
    n = n * 256 + s:byte(i)
  end
  return n
end

-- ---------------------------------------------------------------------------
-- Public API
-- ---------------------------------------------------------------------------

---Encode a WebSocket frame.
---@param opts table  { opcode=number, payload=string, fin=boolean, mask=boolean }
---@return string  binary frame
function M.encode_frame(opts)
  local opcode  = opts.opcode  or 0x1
  local payload = opts.payload or ""
  local fin     = opts.fin ~= false   -- default true
  local do_mask = opts.mask == true   -- default false

  local parts = {}

  -- Byte 1: FIN + RSV(000) + opcode
  local byte1 = opcode
  if fin then byte1 = byte1 + 0x80 end
  parts[#parts + 1] = string.char(byte1)

  -- Byte 2 (+ extended length): MASK bit + payload length
  local plen  = #payload
  local byte2 = do_mask and 0x80 or 0x00

  if plen < 126 then
    parts[#parts + 1] = string.char(byte2 + plen)
  elseif plen < 65536 then
    parts[#parts + 1] = string.char(byte2 + 126)
    parts[#parts + 1] = uint16_to_bytes(plen)
  else
    parts[#parts + 1] = string.char(byte2 + 127)
    parts[#parts + 1] = uint64_to_bytes(plen)
  end

  -- Masking key + masked payload
  if do_mask then
    local mask = string.char(
      math.random(0, 255), math.random(0, 255),
      math.random(0, 255), math.random(0, 255))
    parts[#parts + 1] = mask
    parts[#parts + 1] = apply_mask(payload, mask)
  else
    parts[#parts + 1] = payload
  end

  return table.concat(parts)
end

---Decode one WebSocket frame from a buffer.
---@param buf string  raw bytes (may be a partial or multi-frame buffer)
---@return table|nil  frame  { opcode, payload, fin } on success; nil if incomplete
---@return string     remaining bytes after the consumed frame (or original buf on nil)
function M.decode_frame(buf)
  if type(buf) ~= "string" or #buf < 2 then
    return nil, buf
  end

  local pos   = 1
  local byte1 = buf:byte(pos)
  local byte2 = buf:byte(pos + 1)
  pos = pos + 2

  local fin    = (math.floor(byte1 / 128) == 1)
  local opcode = byte1 % 16

  local masked     = (math.floor(byte2 / 128) == 1)
  local plen_field = byte2 % 128

  -- Determine actual payload length
  local payload_len
  if plen_field < 126 then
    payload_len = plen_field
  elseif plen_field == 126 then
    if #buf < pos + 1 then return nil, buf end
    payload_len = bytes_to_uint16(buf:sub(pos, pos + 1))
    pos = pos + 2
  else -- 127
    if #buf < pos + 7 then return nil, buf end
    payload_len = bytes_to_uint64(buf:sub(pos, pos + 7))
    pos = pos + 8
  end

  -- Read mask key (4 bytes) if present
  local mask = nil
  if masked then
    if #buf < pos + 3 then return nil, buf end
    mask = buf:sub(pos, pos + 3)
    pos  = pos + 4
  end

  -- Check we have the full payload
  if #buf < pos + payload_len - 1 then
    return nil, buf
  end

  local raw_payload = buf:sub(pos, pos + payload_len - 1)
  pos = pos + payload_len

  local payload = (masked and mask) and apply_mask(raw_payload, mask) or raw_payload

  local frame = {
    fin     = fin,
    opcode  = opcode,
    payload = payload,
  }

  return frame, buf:sub(pos)
end

return M
