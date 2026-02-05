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

-- Ensure proxy path is not used in this unit test.
os.getenv = function(_)
  return nil
end

local http_calls = 0
local timer_calls = 0

http_request = function(req)
  http_calls = http_calls + 1
  if http_calls == 1 then
    req.callback(nil, {
      code = 429,
      headers = {},
      content = "{\"error\":{\"message\":\"rate limit\",\"code\":\"rate_limit_exceeded\"}}",
    })
    return
  end
  req.callback(nil, {
    code = 400,
    headers = {},
    content = "{\"error\":{\"message\":\"bad\",\"code\":\"bad_request\"}}",
  })
end

timer = function(opts)
  timer_calls = timer_calls + 1
  -- Execute immediately so the retry path runs synchronously and would panic
  -- if schedule_retry isn't correctly scoped.
  local self = { close = function() end }
  if opts and type(opts.callback) == "function" then
    opts.callback(self)
  end
  return { close = function() end }
end

local cb_calls = 0
local ok = ai_openai_client.request_json_schema({
  api_key = "sk-test",
  api_base = "https://api.openai.com",
  model = "test-model",
  input = "hello",
  json_schema = {
    name = "test",
    strict = true,
    schema = {
      type = "object",
      additionalProperties = false,
      required = { "ok" },
      properties = { ok = { type = "boolean" } },
    },
  },
  max_attempts = 2,
  retry_schedule = { 0 },
}, function(success, result, meta)
  cb_calls = cb_calls + 1
  assert_true(success == false, "expected failure on final 400")
  assert_true(type(meta) == "table" and meta.attempts == 2, "expected attempts=2")
end)

assert_true(ok == true, "request_json_schema should start")
assert_true(http_calls == 2, "expected two http_request calls (retry)")
assert_true(timer_calls == 1, "expected one timer call for retry schedule")
assert_true(cb_calls == 1, "callback must be called exactly once")

print("ai_openai_retry_scope_unit: ok")
astra.exit()

