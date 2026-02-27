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
        id = "dvr-v1-1",
        name = "Remote DVR",
        host = "127.0.0.1",
        port = 8000,
        api_type = "dvr_v1",
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
    return reply(200, { process = { version = "4.4.250" } })
  end
  if req.path == "/api/v1/dvr/health" and req.method == "GET" then
    return reply(200, { ok = true, version = "4.4.250" })
  end
  if req.path == "/api/v1/dvr/streams/list" and req.method == "POST" then
    return reply(200, {
      items = {
        {
          stream_id = "s1",
          name = "DVR Stream 1",
          source_url = "http://admin:secret@127.0.0.1:9060/play/s1",
          archive_path = "/media/dvr/s1",
          record_enabled = true,
          recording_paused = false,
          retention_days = 5,
          status = "ok",
          on_air = true,
          bitrate_kbps = 1300,
          raw_bitrate_kbps = 1440,
          cc_errors = 4,
          pes_errors = 2,
          uptime_sec = 777,
          active_input = 1,
          active_input_url = "http://127.0.0.1:9060/play/s1",
          updated_at = 1700000001,
        },
        {
          stream_id = "s2",
          name = "DVR Stream 2",
          config = {
            id = "s2",
            name = "DVR Stream 2",
            type = "spts",
            input = { "http://admin:secret@127.0.0.1:9060/play/s2" },
            dvr = {
              source_url = "http://admin:secret@127.0.0.1:9060/play/s2",
              path = "/media/dvr/s2",
            },
          },
          record_enabled = true,
          recording_paused = false,
          retention_days = 3,
          status = "ok",
          on_air = true,
          bitrate_kbps = 1200,
          raw_bitrate_kbps = 1250,
          cc_errors = 0,
          pes_errors = 0,
          active_input = 1,
          active_input_url = "http://admin:secret@127.0.0.1:9060/play/s2",
          updated_at = 1700000002,
        },
      },
      api_type_effective = "dvr_v1",
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
  id = "dvr-v1-1",
  include_status = true,
}))

assert_true(sent ~= nil and tonumber(sent.code) == 200, "expected 200 streams/list response")
local ok, payload = pcall(json.decode, sent.content or "")
assert_true(ok and type(payload) == "table", "expected json payload")
assert_true(type(payload.items) == "table" and #payload.items == 2, "expected 2 stream items")
local item = payload.items[1]
assert_true(item.id == "s1", "expected stream id s1")
assert_true(item.on_air == true, "expected on_air true")
assert_true(tonumber(item.bitrate_kbps) == 1300, "expected bitrate_kbps")
assert_true(tonumber(item.raw_bitrate_kbps) == 1440, "expected raw_bitrate_kbps")
assert_true(tonumber(item.cc_errors) == 4, "expected cc_errors")
assert_true(tonumber(item.pes_errors) == 2, "expected pes_errors")
assert_true(tonumber(item.active_input) == 1, "expected active_input")
assert_true(item.active_input_url == "http://127.0.0.1:9060/play/s1", "expected active_input_url")
assert_true(tonumber(item.updated_at) == 1700000001, "expected updated_at")
assert_true(type(item.dvr) == "table", "expected dvr metadata")
assert_true(item.dvr.source_url == "http://127.0.0.1:9060/play/s1", "expected redacted dvr source_url")
assert_true(type(item.config) == "table", "expected config table")
assert_true(item.config.input and item.config.input[1] == "http://127.0.0.1:9060/play/s1",
  "expected redacted source_url in config input")
local item2 = payload.items[2]
assert_true(item2.id == "s2", "expected stream id s2")
assert_true(item2.active_input_url == "http://127.0.0.1:9060/play/s2", "expected redacted active_input_url for s2")
assert_true(item2.dvr and item2.dvr.source_url == "http://127.0.0.1:9060/play/s2",
  "expected redacted dvr source_url for s2")
assert_true(item2.config and item2.config.input and item2.config.input[1] == "http://127.0.0.1:9060/play/s2",
  "expected redacted config input source_url for s2")
assert_true(item2.config and item2.config.dvr and item2.config.dvr.source_url == "http://127.0.0.1:9060/play/s2",
  "expected redacted config.dvr.source_url for s2")

log.info("[unit] servers_streams_list_dvr_v1_status_fields_unit ok")
astra.exit()
