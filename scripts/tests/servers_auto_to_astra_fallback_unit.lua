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
        id = "remote-auto",
        name = "Remote Auto",
        host = "127.0.0.1/base",
        port = 8000,
        api_type = "auto",
        enabled = true,
        login = "admin",
        password = "admin",
      },
    }
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

http_request = function(req)
  local function reply(code, payload, headers)
    req.callback(req, {
      code = code,
      headers = headers or {},
      content = type(payload) == "string" and payload or json.encode(payload or {}),
    })
  end

  if req.path == "/base/api/v1/auth/login" and req.method == "POST" then
    return reply(403, { error = "forbidden" })
  end
  if req.path == "/base/api/auth/login" and req.method == "POST" then
    return reply(403, { error = "forbidden" })
  end
  if req.path == "/base/control/" and req.method == "POST" then
    local ok, body = pcall(json.decode, req.content or "{}")
    local cmd = ok and body and body.cmd or ""
    if cmd == "version" then
      return reply(200, { version = "4.4.1" })
    end
    return reply(404, { error = "unknown cmd" })
  end
  if req.path == "/base/api/streams" and req.method == "GET" then
    return reply(404, { error = "not found" })
  end
  if req.path == "/base/api/v1/streams" and req.method == "GET" then
    return reply(404, { error = "not found" })
  end
  if req.path == "/base/api/stream-info" and req.method == "GET" then
    return reply(200, {
      streams = {
        { id = "x1", name = "X One", type = "spts", enable = true },
      },
    })
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

api.handle_request(server, client, make_request("/api/v1/servers/test", {
  id = "remote-auto",
}))
assert_true(sent ~= nil and tonumber(sent.code) == 200, "expected 200 server test response")
local ok_test, payload_test = pcall(json.decode, sent.content or "")
assert_true(ok_test and type(payload_test) == "table", "expected test json payload")
assert_true(payload_test.api_type_effective == "astra_legacy", "expected auto -> astra_legacy fallback")

sent = nil
api.handle_request(server, client, make_request("/api/v1/servers/streams/list", {
  id = "remote-auto",
  include_status = false,
}))
assert_true(sent ~= nil and tonumber(sent.code) == 200, "expected 200 streams/list")
local ok_list, payload_list = pcall(json.decode, sent.content or "")
assert_true(ok_list and type(payload_list) == "table", "expected list json payload")
assert_true(payload_list.api_type_effective == "astra_legacy", "expected list api_type astra_legacy")
assert_true(tonumber(payload_list.count) == 1, "expected single stream from /api/stream-info fallback")
assert_true(type(payload_list.items) == "table" and payload_list.items[1] and payload_list.items[1].id == "x1",
  "expected stream id x1")

log.info("[unit] servers_auto_to_astra_fallback_unit ok")
astra.exit()
