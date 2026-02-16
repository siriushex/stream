log.set({ debug = true })

dofile("scripts/base.lua")
dofile("scripts/config.lua")
dofile("scripts/api.lua")

config = config or {}
config.get_setting = function(key)
  if key == "http_auth_enabled" then
    return false
  end
  return nil
end
config.get_user_by_username = function(username)
  if username == "admin" then
    return { id = 1, username = "admin", is_admin = 1 }
  end
  return nil
end
config.get_user_by_id = function(id)
  if tonumber(id) == 1 then
    return { id = 1, username = "admin", is_admin = 1 }
  end
  return nil
end

local function assert_true(v, msg)
  if not v then
    error(msg or "assert")
  end
end

local sent = nil
local server = {
  send = function(_, _, payload)
    sent = payload
  end,
}
local client = {}

local calls = {}
runtime = runtime or {}
runtime.switch_stream_input = function(id, input_index)
  calls[#calls + 1] = { id = id, input_index = input_index }
  return true
end

local function make_request(path, body)
  return {
    method = "POST",
    path = path,
    addr = "127.0.0.1",
    headers = { ["content-type"] = "application/json" },
    query = {},
    content = json.encode(body),
  }
end

local function decode_sent()
  local ok, payload = pcall(json.decode, sent and sent.content or "")
  assert_true(ok and type(payload) == "table", "expected json response")
  return payload
end

api.handle_request(server, client, make_request("/api/v1/streams/s1/switch-input", {
  input_index = 2,
}))
assert_true(sent ~= nil and tonumber(sent.code) == 200, "expected 200 for switch-input")
local payload_ok = decode_sent()
assert_true(payload_ok.status == "ok", "expected ok status")
assert_true(payload_ok.action == "switch_input", "expected switch_input action")
assert_true(tonumber(payload_ok.input_index) == 2, "expected input_index echo")
assert_true(#calls == 1, "expected one runtime switch call")
assert_true(calls[1].id == "s1" and tonumber(calls[1].input_index) == 2, "expected runtime args")

sent = nil
api.handle_request(server, client, make_request("/api/v1/streams/s1/switch-input", {}))
assert_true(sent ~= nil and tonumber(sent.code) == 400, "expected 400 for missing input_index")
local payload_missing = decode_sent()
assert_true(tostring(payload_missing.error or ""):find("input_index is required", 1, true) ~= nil, "expected required error")

runtime.switch_stream_input = function()
  return false, "stream not found"
end
sent = nil
api.handle_request(server, client, make_request("/api/v1/streams/s1/switch-input", {
  input_index = 0,
}))
assert_true(sent ~= nil and tonumber(sent.code) == 404, "expected 404 for missing stream")
local payload_not_found = decode_sent()
assert_true(tostring(payload_not_found.error or ""):find("stream not found", 1, true) ~= nil, "expected stream not found error")

runtime.switch_stream_input = function()
  return false, "switch input unsupported"
end
sent = nil
api.handle_request(server, client, make_request("/api/v1/streams/s1/switch-input", {
  input_index = 0,
}))
assert_true(sent ~= nil and tonumber(sent.code) == 400, "expected 400 for unsupported switch")
local payload_unsupported = decode_sent()
assert_true(tostring(payload_unsupported.error or ""):find("unsupported", 1, true) ~= nil, "expected unsupported error")

log.info("[unit] streams_switch_input_api_unit ok")
astra.exit()
