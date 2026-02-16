log.set({ debug = true })

dofile("scripts/base.lua")
dofile("scripts/config.lua")
dofile("scripts/api.lua")

-- Disable auth so require_admin() works via virtual admin session.
config = config or {}
config.get_setting = function(key)
  if key == "http_auth_enabled" then return false end
  if key == "servers" then
    return {
      {
        id = "remote-1",
        name = "Remote",
        host = "127.0.0.1/wrong",
        port = 8000,
        enabled = true,
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

-- Stub http_request to validate base_path normalization.
local last_req = nil
http_request = function(req)
  last_req = req
  -- Simulate success response (health endpoint).
  if req and req.callback then
    local payload = {}
    if req.path and req.path:find("/api/v1/health/process", 1, true) then
      payload = { status = "ok", version = "1.2.2" }
    end
    req.callback(req, { code = 200, headers = {}, content = json.encode(payload) })
  end
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
  id = "remote-1",
  host = "127.0.0.1/base",
  port = 8000,
}))

assert_true(last_req ~= nil, "expected http_request call")
assert_true(last_req.path == "/base/api/v1/health/process", "expected base_path applied to health path")
assert_true(sent ~= nil and tonumber(sent.code) == 200, "expected 200 server_test response")
local ok, payload = pcall(json.decode, sent.content or "")
assert_true(ok and type(payload) == "table", "expected json payload")
assert_true(payload.api_type_effective == "stream_v1", "expected stream_v1 detection")
assert_true(payload.remote_version == "1.2.2", "expected remote version")

log.info("[unit] servers_test_normalize_unit ok")
astra.exit()
