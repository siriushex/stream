log.set({ debug = true })

dofile("scripts/base.lua")
dofile("scripts/config.lua")
dofile("scripts/api.lua")

local reload_calls = 0

runtime = runtime or {}
runtime.refresh_adapters = function(_force)
  return true
end
runtime.refresh = function(_force)
  reload_calls = reload_calls + 1
  return true, {}
end

config = config or {}
config.get_setting = function(key)
  if key == "http_auth_enabled" then
    return true
  end
  if key == "http_csrf_enabled" then
    return true
  end
  if key == "supervisor_enabled" then
    return false
  end
  return nil
end
config.get_session = function(token)
  if token == "admin-token" then
    return { user_id = 1, token = token, expires_at = os.time() + 3600 }
  end
  if token == "user-token" then
    return { user_id = 2, token = token, expires_at = os.time() + 3600 }
  end
  return nil
end
config.get_user_by_id = function(id)
  id = tonumber(id)
  if id == 1 then
    return { id = 1, username = "admin", is_admin = 1 }
  end
  if id == 2 then
    return { id = 2, username = "viewer", is_admin = 0 }
  end
  return nil
end

local function assert_true(v, msg)
  if not v then
    error(msg or "assert")
  end
end

local sent = nil
local server = {
  send = function(_, _, payload)
    sent = payload
  end,
}
local client = {}

local function make_request(path, token, query)
  return {
    method = "POST",
    path = path,
    addr = "127.0.0.1",
    headers = {
      authorization = "Bearer " .. tostring(token or ""),
    },
    query = query or {},
    content = "{}",
  }
end

api.handle_request(server, client, make_request("/api/v1/reload", "user-token"))
assert_true(sent ~= nil and tonumber(sent.code) == 403, "reload must be admin-only")

api.handle_request(server, client, make_request("/api/v1/restart", "user-token", { mode = "hard" }))
assert_true(sent ~= nil and tonumber(sent.code) == 403, "restart must be admin-only")

api.handle_request(server, client, make_request("/api/v1/reload", "admin-token"))
assert_true(sent ~= nil and tonumber(sent.code) == 200, "admin reload must succeed")
assert_true(reload_calls == 1, "reload_runtime must be called for admin reload")

api.handle_request(server, client, make_request("/api/v1/restart", "admin-token", { mode = "hard" }))
assert_true(sent ~= nil and tonumber(sent.code) == 400, "hard restart must be blocked without supervisor")

api.handle_request(server, client, make_request("/api/v1/restart", "admin-token"))
assert_true(sent ~= nil and tonumber(sent.code) == 200, "admin soft restart must succeed")
assert_true(reload_calls == 2, "soft restart must call reload_runtime")

log.info("[unit] reload_restart_admin_unit ok")
astra.exit()
