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
        host = "127.0.0.1/base",
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

local mode = "login_forbidden"
http_request = function(req)
  if not req or not req.callback then
    return
  end

  if mode == "login_forbidden" then
    req.callback(req, {
      code = 403,
      headers = {},
      content = json.encode({ error = "forbidden" }),
    })
    return
  end

  if req.path and req.path:find("/auth/login", 1, true) then
    req.callback(req, {
      code = 200,
      headers = { ["set-cookie"] = "stream_session=unit123; Path=/" },
      content = "{}",
    })
    return
  end

  if req.path and (req.path:find("/api/v1/streams", 1, true) or req.path:find("/api/streams", 1, true)) then
    req.callback(req, {
      code = 404,
      headers = {},
      content = json.encode({ error = "streams endpoint not found" }),
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

mode = "login_forbidden"
api.handle_request(server, client, make_request("/api/v1/servers/test", {
  id = "remote-1",
}))
assert_true(sent ~= nil and tonumber(sent.code) == 403, "expected 403 on login forbidden")
local ok1, payload1 = pcall(json.decode, sent.content or "")
assert_true(ok1 and type(payload1) == "table", "expected json payload for login forbidden")
assert_true(tostring(payload1.error or ""):find("forbidden", 1, true) ~= nil, "expected forbidden message")

mode = "streams_404"
sent = nil
api.handle_request(server, client, make_request("/api/v1/servers/streams", {
  id = "remote-1",
}))
assert_true(sent ~= nil and tonumber(sent.code) == 404, "expected 404 on missing streams endpoint")
local ok2, payload2 = pcall(json.decode, sent.content or "")
assert_true(ok2 and type(payload2) == "table", "expected json payload for streams 404")
assert_true(tostring(payload2.error or ""):find("http 404", 1, true) ~= nil, "expected http 404 in message")

log.info("[unit] servers_remote_error_unit ok")
astra.exit()
