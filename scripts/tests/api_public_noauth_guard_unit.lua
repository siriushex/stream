log.set({ debug = true })

dofile("scripts/base.lua")
dofile("scripts/config.lua")
dofile("scripts/api.lua")

local allow_public = false

config = config or {}
config.get_setting = function(key)
  if key == "http_auth_enabled" then return false end
  if key == "http_allow_public_noauth" then
    if allow_public then return true end
    return false
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
config.list_streams = function()
  return {}
end

local function assert_true(v, msg)
  if not v then error(msg or "assert") end
end

local sent = nil
local server = {
  send = function(_, _, payload)
    sent = payload
  end
}
local client = {}

local function make_request(addr)
  return {
    method = "GET",
    path = "/api/v1/streams",
    addr = addr,
    headers = {},
    query = {},
  }
end

allow_public = false
sent = nil
api.handle_request(server, client, make_request("198.51.100.10"))
assert_true(sent ~= nil, "expected response for remote request")
assert_true(tonumber(sent.code) == 403, "expected 403 for remote no-auth API")
assert_true(
  tostring(sent.content or ""):find("public API disabled without auth", 1, true) ~= nil,
  "expected public API guard message"
)

allow_public = true
sent = nil
api.handle_request(server, client, make_request("198.51.100.10"))
assert_true(sent ~= nil, "expected response when public no-auth enabled")
assert_true(tonumber(sent.code) == 200, "expected 200 when public no-auth explicitly enabled")

log.info("[unit] api_public_noauth_guard_unit ok")
astra.exit()
