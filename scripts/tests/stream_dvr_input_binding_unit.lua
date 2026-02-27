log.set({ debug = true })

dofile("scripts/base.lua")
dofile("scripts/config.lua")
dofile("scripts/dvr.lua")

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

local tmp = "/tmp/stream_dvr_input_binding_unit"
os.execute("rm -rf " .. tmp .. " >/dev/null 2>&1 || true")
os.execute("mkdir -p " .. tmp)

config.init({
    data_dir = tmp,
    db_path = tmp .. "/stream.db",
})
config.set_setting("http_auth_enabled", false)
config.set_setting("http_port", 9060)
config.set_setting("http_play_port", 0)
config.set_setting("servers", {
    {
        id = "dvr1",
        name = "DVR #1",
        host = "127.0.0.1",
        port = 9061,
        api_type = "dvr_v1",
        enabled = true,
        login = "admin",
        password = "admin",
    },
})

runtime = runtime or {}
runtime.refresh = runtime.refresh or function()
    return true
end
runtime.refresh_adapters = runtime.refresh_adapters or function() end
runtime.apply_stream_row = runtime.apply_stream_row or function()
    return true
end
runtime.streams = runtime.streams or {}

local captured = {
    upsert_calls = 0,
    upsert_items = {},
    record_calls = 0,
    record_payloads = {},
    links = {},
}

_G.__stream_remote_servers = {
    dvr_upsert_streams = function(_entry, items, callback)
        captured.upsert_calls = captured.upsert_calls + 1
        captured.upsert_items[captured.upsert_calls] = items
        callback(true, {
            ok = true,
            imported = #(items or {}),
            failed = {},
        })
    end,
    dvr_bulk_record = function(_entry, payload, callback)
        captured.record_calls = captured.record_calls + 1
        captured.record_payloads[captured.record_calls] = payload
        callback(true, {
            ok = true,
            affected = #(payload and payload.stream_ids or {}),
            errors = {},
        })
    end,
}

_G.__stream_dvr = {
    upsert_remote_link = function(row)
        captured.links[#captured.links + 1] = row
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

local function make_request(path, body)
    return {
        method = "POST",
        path = path,
        addr = "127.0.0.1",
        headers = {
            ["content-type"] = "application/json",
            ["host"] = "127.0.0.1:9060",
        },
        query = {},
        content = json.encode(body or {}),
    }
end

sent = nil
api.handle_request(server, client, make_request("/api/v1/streams", {
    id = "local_input_dvr",
    enabled = true,
    config = {
        id = "local_input_dvr",
        name = "Local Input DVR",
        type = "spts",
        input = {
            "http://127.0.0.1:9061/play/remote_existing#input_type=dvr&dvr_server_id=dvr1&dvr_stream_id=remote_existing&dvr_mode=play",
        },
    },
}))

assert_true(sent ~= nil and tonumber(sent.code) == 200, "expected 200 from stream upsert")
assert_eq(captured.upsert_calls, 1, "expected one dvr upsert call")
assert_eq(captured.record_calls, 1, "expected one dvr bulk-record call")

local upsert_item = captured.upsert_items[1] and captured.upsert_items[1][1] or nil
assert_true(type(upsert_item) == "table", "expected dvr upsert item")
assert_eq(upsert_item.stream_id, "remote_existing", "expected remote stream id from DVR input metadata")
assert_eq(upsert_item.source_url, "http://admin:admin@127.0.0.1:9060/play/local_input_dvr",
    "expected source_url built from local stream id")

local record_payload = captured.record_payloads[1] or {}
assert_true(type(record_payload.stream_ids) == "table", "expected stream_ids in bulk-record")
assert_eq(record_payload.stream_ids[1], "remote_existing", "expected remote stream id in bulk-record")
assert_eq(record_payload.record_enabled, false, "record should stay disabled until DVR archive/backup is enabled")

local row = config.get_stream("local_input_dvr")
assert_true(type(row) == "table" and type(row.config) == "table", "expected saved stream row")
assert_true(type(row.config.dvr) == "table", "expected auto-created dvr config from DVR input")
assert_eq(row.config.dvr.mode, "remote", "expected dvr mode remote")
assert_eq(row.config.dvr.remote_server_id, "dvr1", "expected remote_server_id from DVR input")
assert_eq(row.config.dvr.remote_stream_id, "remote_existing", "expected remote_stream_id from DVR input")
assert_eq(row.config.dvr.remote_channel_enabled, true, "expected remote_channel_enabled=true")

assert_true(type(captured.links[1]) == "table", "expected remote link upsert")
assert_eq(captured.links[1].stream_id, "local_input_dvr", "unexpected local stream id in remote link")
assert_eq(captured.links[1].dvr_server_id, "dvr1", "unexpected remote server id in remote link")
assert_eq(captured.links[1].dvr_stream_id, "remote_existing", "unexpected remote stream id in remote link")

log.info("[unit] stream_dvr_input_binding_unit ok")
astra.exit()
