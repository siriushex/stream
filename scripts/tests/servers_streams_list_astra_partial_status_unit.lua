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
        id = "legacy-1",
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

local requests = {}
http_request = function(req)
  requests[#requests + 1] = {
    method = req and req.method or "",
    path = req and req.path or "",
    content = req and req.content or "",
  }

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
          { id = "c3", name = "C Three", enable = true },
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
        { id = "c3", name = "C Three", enable = true },
      },
    })
  end

  -- Partial aggregate map: only one stream has status here.
  if req.path == "/base/api/stream-status?t=1" and req.method == "GET" then
    return reply(200, {
      a1 = { onair = true, bitrate = "1111Kbit/s", input_id = 1 },
    })
  end
  if req.path == "/base/api/v1/stream-status?t=1" and req.method == "GET" then
    return reply(404, { error = "not found" })
  end

  if req.path == "/base/api/stream-status/a1?t=1" and req.method == "GET" then
    return reply(200, { onair = true, bitrate = "1111Kbit/s", input_id = 1 })
  end
  if req.path == "/base/api/stream-status/b2?t=1" and req.method == "GET" then
    return reply(200, { onair = true, bitrate = "2.222Mbit/s", input = "input #2" })
  end
  if req.path == "/base/api/stream-status/c3?t=1" and req.method == "GET" then
    return reply(200, { onair = false, bitrate = "0Kbit/s", input_id = 1 })
  end
  if req.path == "/base/api/v1/stream-status/a1?t=1" and req.method == "GET" then
    return reply(404, { error = "not found" })
  end
  if req.path == "/base/api/v1/stream-status/b2?t=1" and req.method == "GET" then
    return reply(404, { error = "not found" })
  end
  if req.path == "/base/api/v1/stream-status/c3?t=1" and req.method == "GET" then
    return reply(404, { error = "not found" })
  end

  return reply(404, { error = "not found" })
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
  id = "legacy-1",
  include_status = true,
}))

assert_true(sent ~= nil and tonumber(sent.code) == 200, "expected 200 streams/list response")
local ok, payload = pcall(json.decode, sent.content or "")
assert_true(ok and type(payload) == "table", "expected json payload")
assert_true(type(payload.items) == "table" and #payload.items == 3, "expected 3 streams")

local by_id = {}
for _, item in ipairs(payload.items) do
  by_id[item.id] = item
end
assert_true(by_id.a1 and tonumber(by_id.a1.bitrate_kbps) == 1111, "expected aggregate status for a1")
assert_true(by_id.b2 and tonumber(by_id.b2.bitrate_kbps) == 2222, "expected per-stream status enrichment for b2")
assert_true(by_id.b2 and tonumber(by_id.b2.active_input) == 2, "expected active_input parsed from string")
assert_true(by_id.c3 and by_id.c3.on_air == false, "expected per-stream on_air for c3")

local used_per_stream_b2 = false
for _, req in ipairs(requests) do
  if req.path == "/base/api/stream-status/b2?t=1" and req.method == "GET" then
    used_per_stream_b2 = true
    break
  end
end
assert_true(used_per_stream_b2, "expected per-stream status request for missing b2")

log.info("[unit] servers_streams_list_astra_partial_status_unit ok")
astra.exit()
