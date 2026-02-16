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
        enabled = true,
      },
    }
  end
  if key == "servers_import_enabled" then
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

api.handle_request(server, client, make_request("/api/v1/servers/pull-streams", {
  id = "remote-1",
}))
assert_true(sent ~= nil and tonumber(sent.code) == 410, "expected 410 for pull-streams when legacy import disabled")
local ok_pull, payload_pull = pcall(json.decode, sent.content or "")
assert_true(ok_pull and type(payload_pull) == "table", "expected json payload for pull-streams 410")
assert_true(tostring(payload_pull.error or ""):find("disabled", 1, true) ~= nil, "expected disabled message for pull-streams")

sent = nil
api.handle_request(server, client, make_request("/api/v1/servers/import", {
  id = "remote-1",
  mode = "merge",
}))
assert_true(sent ~= nil and tonumber(sent.code) == 410, "expected 410 for import when legacy import disabled")
local ok_import, payload_import = pcall(json.decode, sent.content or "")
assert_true(ok_import and type(payload_import) == "table", "expected json payload for import 410")
assert_true(tostring(payload_import.error or ""):find("disabled", 1, true) ~= nil, "expected disabled message for import")

log.info("[unit] servers_legacy_import_disabled_unit ok")
astra.exit()
