log.set({ debug = true })

dofile("scripts/base.lua")
dofile("scripts/config.lua")
dofile("scripts/api.lua")

config = config or {}
config.get_setting = function(key)
  if key == "http_auth_enabled" then return false end
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

-- Simulate runtime where stream_v1 request path fails first and legacy adapter
-- reports generic "http_request unavailable". API should keep the more specific
-- stream_v1 error message.
http_request = nil

local sent = nil
local server = {
  send = function(_, _, payload)
    sent = payload
  end
}
local client = {}

local request = {
  method = "POST",
  path = "/api/v1/servers/test",
  addr = "127.0.0.1",
  headers = { ["content-type"] = "application/json" },
  query = {},
  content = json.encode({
    host = "127.0.0.1",
    port = 8000,
    api_type = "auto",
    login = "",
    password = "",
  }),
}

api.handle_request(server, client, request)
assert_true(sent ~= nil and tonumber(sent.code) == 502, "expected 502 server test failure")
local ok, payload = pcall(json.decode, sent.content or "")
assert_true(ok and type(payload) == "table", "expected json payload")
local text = tostring(payload.error or "")
assert_true(text:find("request failed", 1, true) ~= nil, "expected stream_v1 request failure details")
assert_true(text:find("http_request unavailable", 1, true) == nil, "must not expose generic legacy fallback error")

log.info("[unit] servers_auto_error_prefer_stream_unit ok")
astra.exit()
