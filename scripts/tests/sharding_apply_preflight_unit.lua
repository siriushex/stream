log.set({ debug = true })

dofile("scripts/base.lua")
dofile("scripts/config.lua")
dofile("scripts/sharding.lua")
dofile("scripts/api.lua")

-- Disable auth so require_admin() works via virtual admin session.
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

local sent = nil
local server = {
  send = function(_, _, payload)
    sent = payload
  end
}
local client = {}

local function make_request(path, method)
  return {
    method = method or "POST",
    path = path,
    addr = "127.0.0.1",
    headers = {},
    query = {},
  }
end

api.handle_request(server, client, make_request("/api/v1/sharding/apply", "POST"))

assert_true(sent ~= nil, "expected response")
assert_true(tonumber(sent.code) == 400, "expected 400 on preflight failure")
local decoded = nil
if type(sent.content) == "string" and sent.content ~= "" then
  local ok, data = pcall(json.decode, sent.content)
  if ok and type(data) == "table" then
    decoded = data
  end
end
local err = decoded and tostring(decoded.error or "") or tostring(sent.content or "")
assert_true(err ~= "", "expected error message")
assert_true(
  err:find("systemctl", 1, true) or err:find("systemd unit not detected", 1, true),
  "expected systemctl missing or unit not detected error"
)

log.info("[unit] sharding_apply_preflight_unit ok")
astra.exit()
