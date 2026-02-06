log.set({ debug = true })

dofile("scripts/base.lua")

local function assert_true(v, msg)
  if not v then
    error(msg or "assert")
  end
end

-- \uXXXX escapes (basic)
do
  local t = json.decode("{\"x\":\"a\\u0042c\"}")
  assert_true(type(t) == "table", "expected object")
  assert_true(t.x == "aBc", "expected aBc, got " .. tostring(t.x))
end

-- \uXXXX surrogate pair (U+1F600) => F0 9F 98 80
do
  local t = json.decode("{\"x\":\"\\uD83D\\uDE00\"}")
  assert_true(type(t) == "table", "expected object")
  assert_true(type(t.x) == "string", "expected string")
  assert_true(#t.x == 4, "expected 4-byte UTF-8 sequence")
  local b1, b2, b3, b4 = t.x:byte(1, 4)
  assert_true(b1 == 0xF0 and b2 == 0x9F and b3 == 0x98 and b4 == 0x80, "unexpected UTF-8 bytes")
end

-- \b / \f escapes
do
  local t = json.decode("{\"x\":\"a\\b\\f\"}")
  assert_true(type(t) == "table", "expected object")
  assert_true(type(t.x) == "string", "expected string")
  assert_true(#t.x == 3, "expected 3 bytes")
  assert_true(t.x:byte(2) == 0x08, "expected backspace (0x08)")
  assert_true(t.x:byte(3) == 0x0C, "expected formfeed (0x0C)")
end

-- Exponent numbers
do
  local t = json.decode("{\"n\":1e3,\"m\":-2.5e-2}")
  assert_true(type(t) == "table", "expected object")
  assert_true(math.abs((t.n or 0) - 1000) < 1e-9, "expected n=1000, got " .. tostring(t.n))
  assert_true(math.abs((t.m or 0) - (-0.025)) < 1e-9, "expected m=-0.025, got " .. tostring(t.m))
end

print("json_decode_unicode_unit: ok")
astra.exit()
