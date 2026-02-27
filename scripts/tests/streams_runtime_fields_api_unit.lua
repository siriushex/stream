log.set({ debug = true })

dofile("scripts/base.lua")
dofile("scripts/config.lua")

local function assert_true(value, message)
    if not value then
        error(message or "assert failed")
    end
end

local function assert_eq(actual, expected, message)
    if actual ~= expected then
        error((message or "assert eq failed") .. ": actual=" .. tostring(actual) .. " expected=" .. tostring(expected))
    end
end

local tmp = "/tmp/streams_runtime_fields_api_unit"
os.execute("rm -rf " .. tmp .. " >/dev/null 2>&1 || true")
os.execute("mkdir -p " .. tmp)

config.init({
    data_dir = tmp,
    db_path = tmp .. "/stream.db",
})
config.set_setting("http_auth_enabled", false)

config.upsert_stream("s1", true, {
    id = "s1",
    name = "Runtime stream",
    type = "spts",
    input = { "udp://239.1.1.1:1234" },
})

runtime = runtime or {}
runtime.list_status_lite_ids = function(ids)
    local map = {}
    for _, sid in ipairs(ids or {}) do
        if sid == "s1" then
            map[sid] = {
                on_air = true,
                bitrate_kbps = 1234,
                raw_bitrate_kbps = 1567,
                cc_errors = 2,
                pes_errors = 3,
                active_input_id = 1,
                active_input_url = "udp://239.1.1.1:1234",
                uptime_sec = 77,
                updated_at = 111,
            }
        end
    end
    return map
end

_G.__stream_dvr = {
    list_runtime_status = function(_)
        return {}
    end,
}

dofile("scripts/api.lua")

local sent = nil
local server = {
    send = function(_, _, payload)
        sent = payload
    end,
}
local client = {}

local function make_get(path)
    return {
        method = "GET",
        path = path,
        addr = "127.0.0.1",
        headers = {},
        query = {},
        content = "",
    }
end

local function decode_sent()
    local ok_decode, payload = pcall(json.decode, sent and sent.content or "")
    assert_true(ok_decode and type(payload) == "table", "expected JSON response")
    return payload
end

sent = nil
api.handle_request(server, client, make_get("/api/v1/streams"))
assert_true(sent and tonumber(sent.code) == 200, "expected 200 for streams list")
local list_payload = decode_sent()
assert_true(type(list_payload) == "table" and #list_payload == 1, "expected one stream in list")
local item = list_payload[1]
assert_eq(item.id, "s1", "unexpected stream id")
assert_eq(item.on_air, true, "expected on_air=true in /streams")
assert_eq(tonumber(item.bitrate_kbps), 1234, "expected bitrate_kbps in /streams")
assert_eq(tostring(item.active_input_url), "udp://239.1.1.1:1234", "expected active_input_url in /streams")
assert_eq(tonumber(item.cc_errors), 2, "expected cc_errors in /streams")
assert_eq(tonumber(item.pes_errors), 3, "expected pes_errors in /streams")

sent = nil
api.handle_request(server, client, make_get("/api/v1/streams/s1"))
assert_true(sent and tonumber(sent.code) == 200, "expected 200 for streams get")
local get_payload = decode_sent()
assert_eq(get_payload.id, "s1", "unexpected stream id in get")
assert_eq(get_payload.on_air, true, "expected on_air=true in /streams/:id")
assert_eq(tonumber(get_payload.bitrate_kbps), 1234, "expected bitrate_kbps in /streams/:id")
assert_eq(tostring(get_payload.active_input_url), "udp://239.1.1.1:1234", "expected active_input_url in /streams/:id")
assert_eq(tonumber(get_payload.cc_errors), 2, "expected cc_errors in /streams/:id")
assert_eq(tonumber(get_payload.pes_errors), 3, "expected pes_errors in /streams/:id")

_G.__stream_dvr = nil

log.info("[unit] streams_runtime_fields_api_unit ok")
astra.exit()
