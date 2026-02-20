log.set({ debug = true })

dofile("scripts/base.lua")

local function assert_true(v, msg)
  if not v then
    error(msg or "assert")
  end
end

local store = {}
local set_calls = 0
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
  set_calls = set_calls + 1
  store[key] = value
end
local obs_db_reinit_calls = 0
local last_obs_db_path = nil
config.init_observability_db = function(opts)
  obs_db_reinit_calls = obs_db_reinit_calls + 1
  if type(opts) == "table" then
    last_obs_db_path = opts.observability_db_path
  end
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
local obs_configure_calls = 0
local sysm_configure_calls = 0
ai_observability = {
  configure = function()
    obs_configure_calls = obs_configure_calls + 1
  end,
}
system_metrics = {
  configure = function()
    sysm_configure_calls = sysm_configure_calls + 1
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
assert_true(set_calls > 0, "expected settings writes for first metadata patch")

local prev_set_calls = set_calls
api.handle_request(server, client, make_request({
  servers = {
    { id = "r1", host = "127.0.0.1", port = 8000 },
  },
}))
assert_true(sent ~= nil and tonumber(sent.code) == 200,
  "expected 200 for no-op settings save, got code=" .. tostring(sent and sent.code) ..
  " body=" .. tostring(sent and sent.content))
local no_op_ok, no_op_payload = pcall(json.decode, sent and sent.content or "{}")
assert_true(no_op_ok and type(no_op_payload) == "table" and no_op_payload.unchanged == true,
  "expected unchanged=true for no-op settings save")
assert_true(set_calls == prev_set_calls, "no-op settings patch must not write settings")
assert_true(reload_calls == 0, "no-op settings patch must not call reload_runtime")

api.handle_request(server, client, make_request({
  hls_enabled = true,
}))

assert_true(sent ~= nil and tonumber(sent.code) == 200,
  "expected 200 for runtime-affecting settings save, got code=" .. tostring(sent and sent.code) ..
  " body=" .. tostring(sent and sent.content))
assert_true(reload_calls == 1, "runtime-affecting settings patch must call reload_runtime")

api.handle_request(server, client, make_request({
  observability_enabled = true,
  observability_db_path = "/tmp/observability-unit.db",
  observability_writer_batch_max = 400,
}))

assert_true(sent ~= nil and tonumber(sent.code) == 200,
  "expected 200 for observability-only settings save, got code=" .. tostring(sent and sent.code) ..
  " body=" .. tostring(sent and sent.content))
assert_true(reload_calls == 1, "observability-only patch must not call reload_runtime")
assert_true(obs_configure_calls >= 1, "expected ai_observability.configure call")
assert_true(sysm_configure_calls >= 1, "expected system_metrics.configure call")
assert_true(obs_db_reinit_calls >= 1, "expected observability db reinit")
assert_true(last_obs_db_path == "/tmp/observability-unit.db",
  "expected observability db path to be passed to reinit")

log.info("[unit] settings_runtime_reload_fastpath_unit ok")
astra.exit()
