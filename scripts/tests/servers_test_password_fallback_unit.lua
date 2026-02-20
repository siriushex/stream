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
        id = "remote-1",
        name = "Remote",
        host = "127.0.0.1",
        port = 8000,
        login = "admin",
        pass = "secretpass",
        enabled = true,
        api_type = "stream_v1",
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

local login_payload = nil
http_request = function(req)
  if not req or not req.callback then
    return
  end
  if req.path == "/api/v1/auth/login" then
    local ok, data = pcall(json.decode, req.content or "{}")
    if ok and type(data) == "table" then
      login_payload = data
    end
    req.callback(req, {
      code = 200,
      headers = {},
      content = json.encode({ token = "unit-token" }),
    })
    return
  end
  if req.path == "/api/v1/health/process" then
    req.callback(req, {
      code = 200,
      headers = {},
      content = json.encode({ status = "ok", version = "1.2.5" }),
    })
    return
  end
  req.callback(req, {
    code = 404,
    headers = {},
    content = json.encode({ error = "not found" }),
  })
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

api.handle_request(server, client, make_request("/api/v1/servers/test", {
  id = "remote-1",
  login = "admin",
  password = "",
}))

assert_true(sent ~= nil and tonumber(sent.code) == 200, "expected 200 on test")
assert_true(type(login_payload) == "table", "expected login payload captured")
assert_true(login_payload.username == "admin", "expected username")
assert_true(login_payload.password == "secretpass", "expected stored password fallback")

log.info("[unit] servers_test_password_fallback_unit ok")
astra.exit()
