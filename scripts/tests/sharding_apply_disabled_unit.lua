log.set({ debug = true })

dofile("scripts/base.lua")
dofile("scripts/config.lua")
dofile("scripts/sharding.lua")
dofile("scripts/api.lua")

config = config or {}
config.get_setting = function(key)
  if key == "http_auth_enabled" then return false end
  if key == "stream_sharding_enabled" then return false end
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

local sent = nil
local server = {
  send = function(_, _, payload)
    sent = payload
  end
}
local client = {}

local request = {
  method = "POST",
  path = "/api/v1/sharding/apply",
  addr = "127.0.0.1",
  headers = {},
  query = {},
}

api.handle_request(server, client, request)

assert_true(sent ~= nil, "expected response")
assert_true(tonumber(sent.code) == 200, "expected 200 on disabled sharding")

local decoded = nil
if type(sent.content) == "string" and sent.content ~= "" then
  local ok, data = pcall(json.decode, sent.content)
  if ok and type(data) == "table" then
    decoded = data
  end
end

assert_true(type(decoded) == "table", "expected json response")
assert_true(decoded.status == "disabled", "expected disabled status")
assert_true(type(decoded.message) == "string" and decoded.message ~= "", "expected disabled message")

log.info("[unit] sharding_apply_disabled_unit ok")
astra.exit()
