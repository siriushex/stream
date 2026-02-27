log.set({ debug = true })

dofile("scripts/base.lua")
dofile("scripts/config.lua")
dofile("scripts/dvr.lua")

local function assert_true(value, message)
    if not value then
        error(message or "assert failed")
    end
end

local tmp = "/tmp/dvr_streams_status_fallback_unit"
os.execute("rm -rf " .. tmp .. " >/dev/null 2>&1 || true")
os.execute("mkdir -p " .. tmp)

config.init({
    data_dir = tmp,
    db_path = tmp .. "/stream.db",
})
config.set_setting("http_auth_enabled", false)

local stream_id = "dvr_status_1"
local upsert_ok, upsert_err = dvr.upsert_stream({
    stream_id = stream_id,
    name = "DVR status stream",
    source_url = "http://127.0.0.1:9060/play/" .. stream_id,
    archive_path = "/media/dvr/" .. stream_id,
    record_enabled = true,
    retention_days = 4,
    config = {
        id = stream_id,
        name = "DVR status stream",
        type = "spts",
        output = { "udp://239.1.1.1:1234" },
        dvr = {
            enabled = true,
            retention_days = 4,
            path = "/media/dvr/" .. stream_id,
        },
    },
})
assert_true(type(upsert_ok) == "table", "failed to upsert dvr stream: " .. tostring(upsert_err))

runtime = {
    list_status_lite_ids = function(_ids)
        return {}
    end,
}

local now = os.time()
local orig_list_runtime_status = dvr.list_runtime_status
local orig_get_runtime_status = dvr.get_runtime_status

dvr.list_runtime_status = function(ids)
    local out = {}
    if type(ids) ~= "table" then
        ids = { stream_id }
    end
    for _, sid in ipairs(ids) do
        if tostring(sid) == stream_id then
            out[stream_id] = {
                on_air = true,
                bitrate_kbps = 1888,
                raw_bitrate_kbps = 1910,
                cc_errors = 3,
                pes_errors = 2,
                active_input_id = 1,
                active_input_index = 0,
                active_input_url = "http://127.0.0.1:9060/play/" .. stream_id,
                uptime_sec = 77,
                updated_at = now,
            }
        end
    end
    return out
end

dvr.get_runtime_status = function(sid)
    if tostring(sid) ~= stream_id then
        return nil
    end
    return {
        on_air = true,
        bitrate_kbps = 1888,
        raw_bitrate_kbps = 1910,
        cc_errors = 3,
        pes_errors = 2,
        active_input_id = 1,
        active_input_index = 0,
        active_input_url = "http://127.0.0.1:9060/play/" .. stream_id,
        uptime_sec = 77,
        updated_at = now,
    }
end

_G.__stream_dvr = dvr
dofile("scripts/api.lua")

local sent = nil
local server = {
    send = function(_, _, payload)
        sent = payload
    end,
}
local client = {}

local function decode_sent()
    local ok, payload = pcall(json.decode, sent and sent.content or "")
    assert_true(ok and type(payload) == "table", "expected JSON response")
    return payload
end

sent = nil
api.handle_request(server, client, {
    method = "POST",
    path = "/api/v1/dvr/streams/list",
    addr = "127.0.0.1",
    headers = { ["content-type"] = "application/json" },
    query = {},
    content = json.encode({
        include_status = true,
        stream_ids = { stream_id },
    }),
})
assert_true(sent and tonumber(sent.code) == 200, "expected 200 for dvr streams list")
local list_payload = decode_sent()
assert_true(type(list_payload.items) == "table" and #list_payload.items == 1, "expected single list row")
local row = list_payload.items[1]
assert_true(row.on_air == true, "expected fallback on_air=true")
assert_true(tonumber(row.bitrate_kbps) == 1888, "expected fallback bitrate_kbps")
assert_true(tonumber(row.cc_errors) == 3, "expected fallback cc_errors")
assert_true(tonumber(row.pes_errors) == 2, "expected fallback pes_errors")
assert_true(type(row.config) == "table", "expected config in list row")
assert_true(type(row.config.output) == "table" and row.config.output[1] == "udp://239.1.1.1:1234",
    "expected preserved output in config")
assert_true(type(row.config.input) == "table" and row.config.input[1] == "http://127.0.0.1:9060/play/" .. stream_id,
    "expected normalized source_url input in config")

sent = nil
api.handle_request(server, client, {
    method = "POST",
    path = "/api/v1/dvr/streams/get",
    addr = "127.0.0.1",
    headers = { ["content-type"] = "application/json" },
    query = {},
    content = json.encode({
        stream_id = stream_id,
    }),
})
assert_true(sent and tonumber(sent.code) == 200, "expected 200 for dvr streams get")
local get_payload = decode_sent()
assert_true(type(get_payload.item) == "table", "expected get item payload")
assert_true(get_payload.item.on_air == true, "expected fallback on_air=true in get")
assert_true(tonumber(get_payload.item.bitrate_kbps) == 1888, "expected fallback bitrate in get")
assert_true(type(get_payload.item.config) == "table", "expected config in get payload")
assert_true(type(get_payload.item.config.output) == "table" and get_payload.item.config.output[1] == "udp://239.1.1.1:1234",
    "expected preserved output in get config")

dvr.list_runtime_status = orig_list_runtime_status
dvr.get_runtime_status = orig_get_runtime_status
runtime = nil
_G.__stream_dvr = nil

log.info("[unit] dvr_streams_status_fallback_unit ok")
astra.exit()
