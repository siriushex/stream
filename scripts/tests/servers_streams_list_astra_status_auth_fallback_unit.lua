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
        id = "legacy-auth-fallback",
        name = "Legacy Astra",
        host = "127.0.0.1/base",
        port = 8000,
        api_type = "astra_legacy",
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
  local function reply(code, payload)
    req.callback(req, {
      code = code,
      headers = {},
      content = type(payload) == "string" and payload or json.encode(payload or {}),
    })
  end

  if req.path == "/base/control/" and req.method == "POST" then
    local ok, body = pcall(json.decode, req.content or "{}")
    local cmd = ok and body and body.cmd or ""
    if cmd == "version" then
      return reply(200, { version = "4.4.1" })
    end
    if cmd == "load" then
      return reply(200, {
        make_stream = {
          { id = "a1", name = "A One", enable = true },
          { id = "b2", name = "B Two", enable = true },
        },
      })
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
        { id = "a1", name = "A One", enable = true },
        { id = "b2", name = "B Two", enable = true },
      },
    })
  end

  -- Aggregate status endpoint is blocked on this Astra variant.
  if req.path == "/base/api/stream-status?t=1" and req.method == "GET" then
    return reply(403, { error = "forbidden" })
  end
  if req.path == "/base/api/v1/stream-status?t=1" and req.method == "GET" then
    return reply(404, { error = "not found" })
  end

  -- Per-stream endpoints are still available and should be used as fallback.
  if req.path == "/base/api/stream-status/a1?t=1" and req.method == "GET" then
    return reply(200, { onair = true, bitrate = "1111Kbit/s", input_id = 1, cc_errors = 5, pes_errors = 1 })
  end
  if req.path == "/base/api/stream-status/b2?t=1" and req.method == "GET" then
    return reply(200, { onair = true, bitrate = "2.222Mbit/s", input_id = 1, cc_errors = 0, pes_errors = 0 })
  end
  if req.path == "/base/api/v1/stream-status/a1?t=1" and req.method == "GET" then
    return reply(404, { error = "not found" })
  end
  if req.path == "/base/api/v1/stream-status/b2?t=1" and req.method == "GET" then
    return reply(404, { error = "not found" })
  end

  return reply(404, { error = "not mocked", path = req.path, method = req.method })
end

local sent = nil
local server = {
  send = function(_, _, payload)
    sent = payload
  end,
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

api.handle_request(server, client, make_request("/api/v1/servers/streams/list", {
  id = "legacy-auth-fallback",
  include_status = true,
}))

assert_true(sent ~= nil and tonumber(sent.code) == 200, "expected 200 streams/list response")
local ok, payload = pcall(json.decode, sent.content or "")
assert_true(ok and type(payload) == "table", "expected json payload")
assert_true(type(payload.items) == "table" and #payload.items == 2, "expected 2 streams")

local by_id = {}
for _, item in ipairs(payload.items) do
  by_id[item.id] = item
end
assert_true(by_id.a1 and tonumber(by_id.a1.bitrate_kbps) == 1111, "expected fallback bitrate for a1")
assert_true(by_id.b2 and tonumber(by_id.b2.bitrate_kbps) == 2222, "expected fallback bitrate for b2")
assert_true(by_id.a1 and by_id.a1.on_air == true, "expected on_air true for a1")
assert_true(by_id.b2 and by_id.b2.on_air == true, "expected on_air true for b2")
assert_true(by_id.a1 and tonumber(by_id.a1.cc_errors) == 5, "expected cc_errors for a1")
assert_true(by_id.a1 and tonumber(by_id.a1.pes_errors) == 1, "expected pes_errors for a1")

log.info("[unit] servers_streams_list_astra_status_auth_fallback_unit ok")
astra.exit()
