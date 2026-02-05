local function script_path(name)
  return "scripts/" .. name
end

log.set({ debug = true })

dofile(script_path("base.lua"))
dofile(script_path("ai_openai_client.lua"))

local scrub = ai_openai_client._test and ai_openai_client._test.scrub_json_body
assert(scrub, "scrub_json_body missing")

local function assert_true(v, msg)
  if not v then
    error(msg or "assert")
  end
end

local function has_ctl(s)
  return s:find("[%z\1-\31\127]") ~= nil
end

local raw = "{\"x\":\"a" .. string.char(0) .. "b" .. string.char(0x1B) .. "c\\n\"}\n"
local out, n = scrub(raw)
assert_true(type(out) == "string", "out must be string")
assert_true(type(n) == "number", "n must be number")
assert_true(n >= 3, "expected >= 3 scrubbed bytes, got " .. tostring(n))
assert_true(not has_ctl(out), "control bytes must be removed")

print("ai_openai_body_scrub_unit: ok")
astra.exit()

