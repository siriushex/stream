log.set({ debug = true })

dofile("scripts/base.lua")
dofile("scripts/config.lua")
dofile("scripts/api.lua")

config = config or {}
config.get_setting = function(key)
  if key == "http_auth_enabled" then
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

-- Keep unit deterministic and independent from sqlite availability.
local presets_cache = nil
dvb_scan_presets_store = function(payload, source_url)
  local valid, err = dvb_scan_presets_validate(payload)
  if not valid then
    return nil, err
  end
  valid.fetched_ts = os.time()
  valid.source_url = source_url or valid.source_url
  presets_cache = valid
  return valid, nil
end
dvb_scan_presets_load_cached = function()
  return presets_cache
end

local function assert_true(value, message)
  if not value then
    error(message or "assert failed")
  end
end

local sent = nil
local server = {
  send = function(_, _, payload)
    sent = payload
  end
}
local client = {}

local function make_request(method, path, body)
  return {
    method = method or "POST",
    path = path,
    addr = "127.0.0.1",
    headers = { ["content-type"] = "application/json" },
    query = {},
    content = body and json.encode(body) or "",
  }
end

local payload = {
  version = "unit-manual-v1",
  source_url = "manual-unit",
  satellites = {
    {
      id = "sat_unit",
      name = "SAT UNIT",
      transponders = {
        { tp = "11000:H:27500", frequency = 11000000, symbolrate = 27500, polarization = "H" },
      },
    },
  },
  cable = {
    { id = "c_unit", name = "C UNIT", step_mhz = 8, frequencies = { 402000000 } },
  },
  terrestrial = {
    { id = "t_unit", name = "T UNIT", step_mhz = 8, frequencies = { 586000000 } },
  },
}

api.handle_request(server, client, make_request("POST", "/api/v1/dvb-scan-presets/manual", {
  source = "manual-unit",
  payload = payload,
}))
assert_true(sent ~= nil and tonumber(sent.code) == 200, "manual presets endpoint must return 200, got: " .. tostring(sent and sent.content))
local ok_write, body_write = pcall(json.decode, sent.content or "")
assert_true(ok_write and type(body_write) == "table", "manual presets response must be json")
assert_true(body_write.version == "unit-manual-v1", "manual presets version mismatch")
assert_true(body_write.source_url == "manual-unit", "manual presets source mismatch")

api.handle_request(server, client, make_request("GET", "/api/v1/dvb-scan-presets", nil))
assert_true(sent ~= nil and tonumber(sent.code) == 200, "get presets endpoint must return 200")
local ok_read, body_read = pcall(json.decode, sent.content or "")
assert_true(ok_read and type(body_read) == "table", "get presets response must be json")
assert_true(body_read.version == "unit-manual-v1", "cached presets version mismatch")
assert_true(type(body_read.satellites) == "table" and #body_read.satellites == 1, "expected satellites list")

log.info("[unit] dvb_scan_presets_manual_unit ok")
astra.exit()
