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

local calls = {
  lite_ids = 0,
  lite = 0,
  full_ids = 0,
  full = 0,
}
local last_ids = nil

runtime = runtime or {}
runtime.list_status_lite_ids = function(ids)
  calls.lite_ids = calls.lite_ids + 1
  last_ids = ids
  return {
    s1 = { on_air = true, bitrate = 1000 },
    s2 = { on_air = false, bitrate = 0 },
  }
end
runtime.list_status_lite = function()
  calls.lite = calls.lite + 1
  return {
    all = { on_air = true, bitrate = 2000 },
  }
end
runtime.list_status_ids = function(ids)
  calls.full_ids = calls.full_ids + 1
  last_ids = ids
  return {
    s9 = { on_air = true, bitrate = 9000, outputs_status = {} },
  }
end
runtime.list_status = function()
  calls.full = calls.full + 1
  return {
    all = { on_air = true, bitrate = 3000, outputs_status = {} },
  }
end

local function make_request(query)
  return {
    method = "GET",
    path = "/api/v1/stream-status",
    addr = "127.0.0.1",
    headers = {},
    query = query or {},
    content = "",
  }
end

local function decode_sent()
  local ok, payload = pcall(json.decode, sent and sent.content or "")
  assert_true(ok and type(payload) == "table", "expected json payload")
  return payload
end

api.handle_request(server, client, make_request({
  lite = "1",
  ids = "s1, s1,,s2",
}))
assert_true(sent ~= nil and tonumber(sent.code) == 200, "expected 200 for lite ids request")
local lite_payload = decode_sent()
assert_true(type(lite_payload.s1) == "table" and type(lite_payload.s2) == "table", "expected ids payload")
assert_true(calls.lite_ids == 1, "expected list_status_lite_ids call")
assert_true(calls.lite == 0, "lite all-list must not be used when ids are provided")
assert_true(type(last_ids) == "table" and #last_ids == 2, "expected deduplicated ids list")
assert_true(last_ids[1] == "s1" and last_ids[2] == "s2", "expected normalized ids order")

api.handle_request(server, client, make_request({
  ids = "s9",
}))
assert_true(sent ~= nil and tonumber(sent.code) == 200, "expected 200 for full ids request")
local full_ids_payload = decode_sent()
assert_true(type(full_ids_payload.s9) == "table", "expected s9 payload from ids fetch")
assert_true(calls.full_ids == 1, "expected list_status_ids call")
assert_true(calls.full == 0, "full all-list must not be used when ids are provided")

api.handle_request(server, client, make_request({
  lite = "1",
}))
assert_true(sent ~= nil and tonumber(sent.code) == 200, "expected 200 for lite full-list request")
local full_lite_payload = decode_sent()
assert_true(type(full_lite_payload.all) == "table", "expected full lite payload")
assert_true(calls.lite >= 1, "expected list_status_lite call for full-list request")

log.info("[unit] stream_status_ids_api_unit ok")
astra.exit()
