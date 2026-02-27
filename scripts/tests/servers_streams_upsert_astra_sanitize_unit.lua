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

local set_stream_payload = nil
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
          {
            id = "s1",
            name = "Legacy Name",
            enable = true,
            input = { "udp://239.1.1.1:1234" },
            output = { "udp://10.0.0.1:1234" },
            keep_me = "legacy",
            nested = { keep = 7, update = 1 },
            audio_fix = { enabled = false },
            transcode = { enabled = false },
            http_keep_active = -1,
            dvr = { enabled = true, retention_days = 3 },
            backup_adapter = true,
            auto_signal_search_enabled = true,
            satellite_type_flip_recovery = true,
            runtime = { marker = "x" },
            stats = { marker = "y" },
            remote = { marker = "z" },
            map = "video=214, audio=314udp://10.0.0.2:1234",
          },
        },
      })
    end
    if cmd == "set-stream" then
      set_stream_payload = body and body.stream or nil
      return reply(200, { status = "ok" })
    end
    return reply(404, { error = "unknown cmd" })
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

api.handle_request(server, client, make_request("/api/v1/servers/streams/upsert", {
  id = "legacy-1",
  mode = "update",
  stream = {
    id = "s1",
    enabled = true,
    config = {
      id = "s1",
      name = "Updated Name",
      input = { "udp://239.1.1.2:1234" },
      output = { "udp://10.0.0.2:1234" },
      nested = { update = 9 },
      audio_fix = { enabled = false },
      transcode = { enabled = false },
      http_keep_active = -1,
      backup_return_delay = 360,
      backup_return_delay_sec = 360,
      backup_initial_delay_sec = 5,
      group = "grp-1",
      auth_enabled = true,
      dvr = { enabled = true, retention_days = 7 },
      auto_signal_search_enabled = true,
      satellite_type_flip_recovery = true,
      runtime = { marker = "next" },
      stats = { marker = "next" },
      remote = { marker = "next" },
      map = "video=214, audio=314udp://10.0.0.2:1234",
    },
  },
}))

assert_true(sent ~= nil and tonumber(sent.code) == 200, "expected 200 streams/upsert response")
assert_true(type(set_stream_payload) == "table", "expected control set-stream payload")
assert_true(set_stream_payload.name == "Updated Name", "expected updated stream name")
assert_true(type(set_stream_payload.input) == "table" and set_stream_payload.input[1] == "udp://239.1.1.2:1234", "expected updated input")
assert_true(set_stream_payload.keep_me == "legacy", "expected unknown legacy key preserved")
assert_true(type(set_stream_payload.nested) == "table" and set_stream_payload.nested.keep == 7, "expected nested keep preserved")
assert_true(type(set_stream_payload.nested) == "table" and set_stream_payload.nested.update == 9, "expected nested update applied")
assert_true(set_stream_payload.audio_fix == nil, "expected stream-only key audio_fix stripped")
assert_true(set_stream_payload.transcode == nil, "expected stream-only key transcode stripped")
assert_true(set_stream_payload.http_keep_active == nil, "expected stream-only key http_keep_active stripped")
assert_true(set_stream_payload.backup_return_delay == nil, "expected stream-only key backup_return_delay stripped")
assert_true(set_stream_payload.backup_return_delay_sec == nil, "expected stream-only key backup_return_delay_sec stripped")
assert_true(set_stream_payload.backup_initial_delay_sec == nil, "expected stream-only key backup_initial_delay_sec stripped")
assert_true(set_stream_payload.group == nil, "expected stream-only key group stripped")
assert_true(set_stream_payload.auth_enabled == nil, "expected stream-only key auth_enabled stripped")
assert_true(set_stream_payload.dvr == nil, "expected stream-only key dvr stripped")
assert_true(set_stream_payload.auto_signal_search_enabled == nil, "expected stream-only key auto_signal_search_enabled stripped")
assert_true(set_stream_payload.satellite_type_flip_recovery == nil, "expected stream-only key satellite_type_flip_recovery stripped")
assert_true(set_stream_payload.runtime == nil, "expected stream-only key runtime stripped")
assert_true(set_stream_payload.stats == nil, "expected stream-only key stats stripped")
assert_true(set_stream_payload.remote == nil, "expected stream-only key remote stripped")
assert_true(set_stream_payload.map == "video=214, audio=314", "expected map value sanitized from accidental URL tail")

log.info("[unit] servers_streams_upsert_astra_sanitize_unit ok")
astra.exit()
