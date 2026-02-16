log.set({ debug = true })

dofile("scripts/base.lua")

local function assert_true(v, msg)
  if not v then
    error(msg or "assert")
  end
end

local store = {}
config = {
  db = {},
}
config.get_setting = function(key)
  if key == "http_auth_enabled" then
    return false
  end
  return store[key]
end
config.set_setting = function(key, value)
  store[key] = value
end
config.add_alert = function() end
config.with_transaction = function(fn)
  return fn()
end

dofile("scripts/api.lua")

local reload_calls = 0
runtime = {
  refresh_adapters = function() end,
  refresh = function(_force)
    reload_calls = reload_calls + 1
    return true
  end,
}

local sent = nil
local server = {
  send = function(_, _, payload)
    sent = payload
  end,
}
local client = {}

local function make_request(body)
  return {
    method = "PUT",
    path = "/api/v1/settings",
    addr = "127.0.0.1",
    headers = { ["content-type"] = "application/json" },
    query = {},
    content = json.encode(body),
  }
end

api.handle_request(server, client, make_request({
  servers = {
    { id = "r1", host = "127.0.0.1", port = 8000 },
  },
}))

assert_true(sent ~= nil and tonumber(sent.code) == 200,
  "expected 200 for metadata-only settings save, got code=" .. tostring(sent and sent.code) ..
  " body=" .. tostring(sent and sent.content))
assert_true(reload_calls == 0, "metadata-only settings patch must not call reload_runtime")

api.handle_request(server, client, make_request({
  hls_enabled = true,
}))

assert_true(sent ~= nil and tonumber(sent.code) == 200,
  "expected 200 for runtime-affecting settings save, got code=" .. tostring(sent and sent.code) ..
  " body=" .. tostring(sent and sent.content))
assert_true(reload_calls == 1, "runtime-affecting settings patch must call reload_runtime")

log.info("[unit] settings_runtime_reload_fastpath_unit ok")
astra.exit()
