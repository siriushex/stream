local function script_path(name)
  return "scripts/" .. name
end

log.set({ debug = true })

dofile(script_path("base.lua"))
dofile(script_path("ai_openai_client.lua"))

local function assert_eq(a, b, msg)
  if a ~= b then
    error((msg or "assert") .. ": expected " .. tostring(b) .. ", got " .. tostring(a))
  end
end

local build = ai_openai_client._test and ai_openai_client._test.build_url
assert(build, "build_url missing")

local u1 = build("https://api.openai.com/v1")
assert_eq(u1.path, "/v1/responses", "strip /v1")

local u2 = build("https://api.openai.com")
assert_eq(u2.path, "/v1/responses", "base")

local u3 = build("https://api.openai.com/v1/")
assert_eq(u3.path, "/v1/responses", "strip /v1/")

local u4 = build("https://example.com/api")
assert_eq(u4.path, "/api/v1/responses", "preserve path")

print("ai_openai_url_unit: ok")
astra.exit()
