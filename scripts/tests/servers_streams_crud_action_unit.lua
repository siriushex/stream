log.set({ debug = true })

dofile("scripts/base.lua")
dofile("scripts/config.lua")
dofile("scripts/api.lua")

config = config or {}
config.get_setting = function(key)
  if key == "http_auth_enabled" then return false end
  if key == "servers" then
    return {
      {
        id = "remote-1",
        name = "Remote",
        host = "127.0.0.1/base",
        port = 8000,
        api_type = "stream_v1",
        enabled = true,
        login = "admin",
        password = "secret",
      },
    }
  end
  if key == "rate_limit_remote_actions_per_min" then
    return 1000
  end
  if key == "rate_limit_remote_actions_window_sec" then
    return 60
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
  if not v then error(msg or "assert") end
end

local requests = {}
local put_bodies = {}
http_request = function(req)
  requests[#requests + 1] = {
    method = req and req.method or "",
    path = req and req.path or "",
    content = req and req.content or "",
  }

  local function reply(code, payload, headers)
    req.callback(req, {
      code = code,
      headers = headers or {},
      content = type(payload) == "string" and payload or json.encode(payload or {}),
    })
  end

  if req.path and req.path:find("/api/v1/auth/login", 1, true) then
    return reply(200, { token = "unit-token" })
  end

  if req.path and req.path:find("/api/v1/health/process", 1, true) then
    return reply(200, { status = "ok", version = "1.2.2" })
  end

  if req.path == "/base/api/v1/streams/ch1" and req.method == "GET" then
    return reply(200, {
      id = "ch1",
      enabled = true,
      config = {
        id = "ch1",
        name = "Channel 1",
        type = "spts",
        input = { "udp://239.1.1.1:1234" },
        output = {},
      },
    })
  end

  if req.path == "/base/api/v1/streams/ch1" and req.method == "PUT" then
    local ok, body = pcall(json.decode, req.content or "{}")
    assert_true(ok and type(body) == "table", "expected PUT body json")
    put_bodies[#put_bodies + 1] = body
    return reply(200, { status = "ok" })
  end

  if req.path == "/base/api/v1/streams/ch1" and req.method == "DELETE" then
    return reply(200, { status = "ok" })
  end

  if req.path == "/base/api/v1/streams/ch1/switch-input" and req.method == "POST" then
    local ok, body = pcall(json.decode, req.content or "{}")
    assert_true(ok and type(body) == "table", "expected switch-input body json")
    assert_true(tonumber(body.input_index) == 1, "expected input_index=1 payload on switch-input")
    return reply(200, { status = "ok", action = "switch_input", input_index = 1 })
  end

  if req.path == "/base/api/v1/streams" and req.method == "POST" then
    return reply(200, { status = "ok" })
  end

  return reply(404, { error = "not found" })
end

local sent = nil
local server = {
  send = function(_, _, payload)
    sent = payload
  end
}
local client = {}

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

api.handle_request(server, client, make_request("/api/v1/servers/streams/get", {
  id = "remote-1",
  stream_id = "ch1",
}))
assert_true(sent ~= nil and tonumber(sent.code) == 200, "expected 200 for streams/get")
local get_payload = decode_sent()
assert_true(get_payload.id == "ch1", "expected id from streams/get")
assert_true(get_payload.enabled == true, "expected enabled from streams/get")
assert_true(type(get_payload.config) == "table" and get_payload.config.name == "Channel 1", "expected config from streams/get")

sent = nil
api.handle_request(server, client, make_request("/api/v1/servers/streams/upsert", {
  id = "remote-1",
  mode = "update",
  stream = {
    id = "ch1",
    enabled = true,
    config = {
      id = "ch1",
      name = "Channel 1 Updated",
      input = { "udp://239.1.1.1:1234" },
      output = {},
    },
  },
}))
assert_true(sent ~= nil and tonumber(sent.code) == 200, "expected 200 for streams/upsert")
local upsert_payload = decode_sent()
assert_true(upsert_payload.status == "ok", "expected ok status from streams/upsert")

sent = nil
api.handle_request(server, client, make_request("/api/v1/servers/streams/action", {
  id = "remote-1",
  stream_id = "ch1",
  action = "disable",
}))
assert_true(sent ~= nil and tonumber(sent.code) == 200, "expected 200 for streams/action disable")
local action_payload = decode_sent()
assert_true(action_payload.status == "ok", "expected ok status from streams/action")
assert_true(action_payload.action == "disable", "expected disable action echo")

sent = nil
api.handle_request(server, client, make_request("/api/v1/servers/streams/action", {
  id = "remote-1",
  stream_id = "ch1",
  action = "switch_input",
  input_index = 1,
}))
assert_true(sent ~= nil and tonumber(sent.code) == 200, "expected 200 for streams/action switch_input")
local switch_payload = decode_sent()
assert_true(switch_payload.status == "ok", "expected ok status from streams/action switch_input")
assert_true(switch_payload.action == "switch_input", "expected switch_input action echo")
assert_true(tonumber(switch_payload.input_index) == 1, "expected input_index from switch_input action")

sent = nil
api.handle_request(server, client, make_request("/api/v1/servers/streams/delete", {
  id = "remote-1",
  stream_id = "ch1",
}))
assert_true(sent ~= nil and tonumber(sent.code) == 200, "expected 200 for streams/delete")
local delete_payload = decode_sent()
assert_true(delete_payload.status == "ok", "expected ok status from streams/delete")

local has_get = false
local has_put = false
local has_delete = false
local has_switch_input = false
for _, req in ipairs(requests) do
  if req.path == "/base/api/v1/streams/ch1" and req.method == "GET" then
    has_get = true
  elseif req.path == "/base/api/v1/streams/ch1" and req.method == "PUT" then
    has_put = true
  elseif req.path == "/base/api/v1/streams/ch1" and req.method == "DELETE" then
    has_delete = true
  elseif req.path == "/base/api/v1/streams/ch1/switch-input" and req.method == "POST" then
    has_switch_input = true
  end
end
assert_true(has_get, "expected remote GET /streams/ch1")
assert_true(has_put, "expected remote PUT /streams/ch1")
assert_true(has_delete, "expected remote DELETE /streams/ch1")
assert_true(has_switch_input, "expected remote POST /streams/ch1/switch-input")

assert_true(#put_bodies >= 2, "expected at least two PUT calls (upsert + disable action)")
assert_true(type(put_bodies[1].config) == "table", "expected config payload on upsert PUT")
assert_true(put_bodies[#put_bodies].enabled == false, "expected enabled=false payload on disable action PUT")

log.info("[unit] servers_streams_crud_action_unit ok")
astra.exit()
