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

  if req.path == "/api/v1/auth/login" and req.method == "POST" then
    return reply(200, { token = "test-token" })
  end
  if req.path == "/api/v1/health/process" and req.method == "GET" then
    return reply(200, { process = { version = "4.4.250" } })
  end
  if req.path == "/api/v1/dvr/health" and req.method == "GET" then
    return reply(200, { ok = true, version = "4.4.250" })
  end
  if req.path == "/api/v1/dvr/streams/get" and req.method == "POST" then
    local ok, body = pcall(json.decode, req.content or "{}")
    assert_true(ok and type(body) == "table", "expected dvr get json body")
    assert_true(body.stream_id == "s1", "expected stream_id=s1 for dvr get")
    return reply(200, {
      item = {
        stream_id = "s1",
        name = "DVR Stream 1",
        source_url = "http://admin:secret@127.0.0.1:9060/play/s1",
        archive_path = "/media/dvr/s1",
        record_enabled = true,
        recording_paused = true,
        retention_days = 7,
        status = "ok",
        on_air = true,
        bitrate_kbps = 1550,
        raw_bitrate_kbps = 1620,
        cc_errors = 3,
        pes_errors = 1,
        uptime_sec = 4321,
        active_input = 1,
        active_input_url = "http://127.0.0.1:9060/play/s1",
        updated_at = 1700001234,
        last_error = "",
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

api.handle_request(server, client, make_request("/api/v1/servers/streams/get", {
  id = "dvr-v1-1",
  stream_id = "s1",
}))

assert_true(sent ~= nil and tonumber(sent.code) == 200, "expected 200 streams/get response")
local ok, payload = pcall(json.decode, sent.content or "")
assert_true(ok and type(payload) == "table", "expected json payload")
assert_true(payload.id == "s1", "expected stream id")
assert_true(payload.enabled == true, "expected enabled true")
assert_true(type(payload.config) == "table", "expected config table")
assert_true(type(payload.dvr) == "table", "expected dvr metadata")
assert_true(payload.config.dvr and payload.config.dvr.source_url == "http://127.0.0.1:9060/play/s1",
  "expected source_url credentials redacted in config")
assert_true(payload.dvr.source_url == "http://127.0.0.1:9060/play/s1",
  "expected source_url credentials redacted in dvr")
assert_true(payload.dvr.record_enabled == true, "expected dvr record_enabled=true")
assert_true(payload.dvr.recording_paused == true, "expected dvr recording_paused=true")
assert_true(tonumber(payload.dvr.retention_days) == 7, "expected dvr retention_days=7")
assert_true(payload.on_air == true, "expected on_air=true")
assert_true(tonumber(payload.bitrate_kbps) == 1550, "expected bitrate_kbps=1550")
assert_true(tonumber(payload.raw_bitrate_kbps) == 1620, "expected raw_bitrate_kbps=1620")
assert_true(tonumber(payload.cc_errors) == 3, "expected cc_errors=3")
assert_true(tonumber(payload.pes_errors) == 1, "expected pes_errors=1")
assert_true(tonumber(payload.uptime_sec) == 4321, "expected uptime_sec=4321")
assert_true(tonumber(payload.active_input) == 1, "expected active_input=1")
assert_true(payload.active_input_url == "http://127.0.0.1:9060/play/s1", "expected active_input_url")
assert_true(tonumber(payload.updated_at) == 1700001234, "expected updated_at=1700001234")

local has_dvr_get = false
for _, req in ipairs(requests) do
  if req.path == "/api/v1/dvr/streams/get" and req.method == "POST" then
    has_dvr_get = true
    break
  end
end
assert_true(has_dvr_get, "expected remote POST /api/v1/dvr/streams/get")

log.info("[unit] servers_streams_get_dvr_v1_status_fields_unit ok")
astra.exit()
