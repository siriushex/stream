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
          {
            id = "s1",
            name = "Stream One",
            enable = true,
            input = { "udp://239.1.1.1:1234" },
            output = { "udp://10.0.0.1:1234" },
            keep_me = "legacy",
            extra = { a = 1, b = 2 },
          },
        },
      })
    end
    return reply(404, { error = "unknown cmd" })
  end

  if req.path == "/base/api/stream-info/s1" and req.method == "GET" then
    return reply(200, {
      id = "s1",
      name = "partial",
      enable = true,
      config = { id = "s1", name = "partial" },
    })
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

api.handle_request(server, client, make_request("/api/v1/servers/streams/get", {
  id = "legacy-1",
  stream_id = "s1",
}))

assert_true(sent ~= nil and tonumber(sent.code) == 200, "expected 200 streams/get response")
local ok, payload = pcall(json.decode, sent.content or "")
assert_true(ok and type(payload) == "table", "expected json payload")
assert_true(payload.id == "s1", "expected stream id")
assert_true(type(payload.config) == "table", "expected stream config table")
assert_true(payload.config.name == "Stream One", "expected full cfg name from control load")
assert_true(type(payload.config.input) == "table" and payload.config.input[1] == "udp://239.1.1.1:1234", "expected full cfg input")
assert_true(payload.config.keep_me == "legacy", "expected unknown cfg keys preserved from load")

local used_stream_info = false
for _, req in ipairs(requests) do
  if req.path == "/base/api/stream-info/s1" and req.method == "GET" then
    used_stream_info = true
    break
  end
end
assert_true(used_stream_info == false, "expected no stream-info call when control load has stream")

log.info("[unit] servers_streams_get_astra_fullcfg_unit ok")
astra.exit()
