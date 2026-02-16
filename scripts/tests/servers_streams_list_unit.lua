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

-- Stub http_request to validate base_path normalization and stream list parsing.
local requests = {}
http_request = function(req)
  requests[#requests + 1] = {
    path = req and req.path or "",
    method = req and req.method or "",
  }
  local content = "{}"
  if req and req.path and req.path:find("/api/v1/streams", 1, true) then
    content = json.encode({
      make_stream = {
        { id = "s1", name = "One", type = "spts", enable = true },
        { id = "t1", name = "Trans", type = "transcode", enable = false },
      },
    })
  end
  if req and req.callback then
    req.callback(req, { code = 200, headers = {}, content = content })
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

api.handle_request(server, client, make_request("/api/v1/servers/streams", {
  id = "remote-1",
}))

assert_true(#requests > 0, "expected http_request call")
local has_streams = false
for _, req in ipairs(requests) do
  if req.path == "/base/api/v1/streams" and req.method == "GET" then
    has_streams = true
    break
  end
end
assert_true(has_streams, "expected base_path applied to streams path")
assert_true(sent ~= nil and tonumber(sent.code) == 200, "expected 200 list streams response")

local ok, payload = pcall(json.decode, sent.content or "")
assert_true(ok and type(payload) == "table", "expected json response payload")
assert_true(payload.status == "ok", "expected ok status")
assert_true(tonumber(payload.count) == 2, "expected 2 streams")
assert_true(type(payload.items) == "table" and #payload.items == 2, "expected items list")
assert_true(payload.items[1].id == "s1" and payload.items[1].enabled == true, "expected s1 enabled")
assert_true(payload.items[2].id == "t1" and payload.items[2].enabled == false, "expected t1 disabled")

log.info("[unit] servers_streams_list_unit ok")
astra.exit()
