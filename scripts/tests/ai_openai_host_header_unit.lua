local function script_path(name)
  return "scripts/" .. name
end

log.set({ debug = true })

dofile(script_path("base.lua"))
dofile(script_path("ai_openai_client.lua"))

local function assert_true(v, msg)
  if not v then
    error(msg or "assert")
  end
end

local called = false
local saw_host = false
local saw_ua = false

http_request = function(req)
  local headers = req and req.headers or {}
  for _, h in ipairs(headers) do
    if h == "Host: api.openai.com" then
      saw_host = true
    end
    if type(h) == "string" and h:lower():find("^user%-agent:") then
      saw_ua = true
    end
  end
  assert_true(saw_host, "missing Host header for OpenAI request")
  assert_true(saw_ua, "missing User-Agent header for OpenAI request")
  -- Return a deterministic 400 so client completes synchronously.
  req.callback(nil, {
    code = 400,
    headers = {},
    content = "{\"error\":{\"message\":\"bad\"}}",
  })
end

local ok, err = ai_openai_client.request_json_schema({
  api_key = "sk-test",
  api_base = "https://api.openai.com",
  model = "test-model",
  input = "hello",
  json_schema = {
    name = "test",
    strict = true,
    schema = { type = "object", additionalProperties = false, required = { "ok" }, properties = { ok = { type = "boolean" } } },
  },
  max_attempts = 1,
}, function(success, result, meta)
  called = true
end)

assert_true(ok == true, "request_json_schema should start")
assert_true(called, "callback must be called")

print("ai_openai_host_header_unit: ok")
astra.exit()

