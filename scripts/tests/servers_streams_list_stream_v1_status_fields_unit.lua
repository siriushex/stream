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
        id = "stream-v1-1",
        name = "Remote Stream",
        host = "127.0.0.1",
        port = 8000,
        api_type = "stream_v1",
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

  if req.path == "/api/v1/auth/login" and req.method == "POST" then
    return reply(200, { token = "test-token" })
  end
  if req.path == "/api/v1/health/process" and req.method == "GET" then
    return reply(200, { process = { version = "4.4.187" } })
  end
  if req.path == "/api/v1/streams" and req.method == "GET" then
    return reply(200, {
      items = {
        { id = "s1", name = "Remote S1", enabled = true, config = { id = "s1", name = "Remote S1", type = "spts", input = { "udp://239.1.1.1:1234" } } },
      },
    })
  end
  if req.path == "/api/v1/stream-status?lite=1" and req.method == "GET" then
    return reply(200, {
      s1 = {
        on_air = true,
        bitrate = 2222,
        raw_bitrate_kbps = 2350,
        cc_errors = 4,
        pes_errors = 2,
        active_input = 1,
        updated_at = 1700001000,
        transcode_state = "RUNNING",
        transcode = {
          input_bitrate_kbps = 2200,
          output_bitrate_kbps = 1800,
          output_cc_errors = 9,
          output_pes_errors = 3,
          updated_at = 1700001000,
        },
      },
    })
  end

  return reply(404, { error = "not found", path = req.path, method = req.method })
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
  id = "stream-v1-1",
  include_status = true,
}))

assert_true(sent ~= nil and tonumber(sent.code) == 200, "expected 200 streams/list response")
local ok, payload = pcall(json.decode, sent.content or "")
assert_true(ok and type(payload) == "table", "expected json payload")
assert_true(type(payload.items) == "table" and #payload.items == 1, "expected 1 stream item")
local item = payload.items[1]
assert_true(item.id == "s1", "expected stream id s1")
assert_true(item.on_air == true, "expected on_air true")
assert_true(tonumber(item.bitrate_kbps) == 2222, "expected bitrate_kbps")
assert_true(tonumber(item.raw_bitrate_kbps) == 2350, "expected raw_bitrate_kbps")
assert_true(tonumber(item.cc_errors) == 4, "expected cc_errors")
assert_true(tonumber(item.pes_errors) == 2, "expected pes_errors")
assert_true(item.transcode_state == "RUNNING", "expected transcode_state")
assert_true(type(item.transcode) == "table", "expected transcode table")
assert_true(tonumber(item.transcode.output_cc_errors) == 9, "expected transcode output_cc_errors")
assert_true(tonumber(item.transcode.output_pes_errors) == 3, "expected transcode output_pes_errors")

log.info("[unit] servers_streams_list_stream_v1_status_fields_unit ok")
astra.exit()
