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

local tmp = "/tmp/stream_dvr_remote_autosync_unit"
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

local function post_stream(path, body)
    sent = nil
    api.handle_request(server, client, make_request(path, body))
    assert_true(sent ~= nil, "expected response")
    assert_eq(tonumber(sent.code), 200, "expected 200 from stream upsert")
end

post_stream("/api/v1/streams", {
    id = "dvr_remote_sync",
    enabled = true,
    config = {
        id = "dvr_remote_sync",
        name = "DVR Remote Sync",
        type = "spts",
        input = {
            "http://origin/live",
        },
        dvr = {
            mode = "remote",
            remote_server_id = "dvr1",
            remote_stream_id = "dvr_remote_target",
            remote_channel_enabled = true,
            enabled = true,
            backup_enabled = false,
            retention_days = 5,
            path = "/media/remote-dvr",
        },
    },
})

assert_eq(captured.upsert_calls, 1, "expected one remote upsert call")
assert_eq(captured.record_calls, 1, "expected one remote bulk record call")
local first_items = captured.upsert_items[1] or {}
assert_true(type(first_items[1]) == "table", "expected first upsert item")
assert_eq(first_items[1].stream_id, "dvr_remote_target", "unexpected stream id in upsert")
assert_eq(first_items[1].record_enabled, true, "remote upsert must set record_enabled=true when DVR is enabled")
assert_eq(first_items[1].archive_path, "/media/remote-dvr", "unexpected archive path in upsert")
assert_eq(first_items[1].source_url, "http://admin:admin@127.0.0.1:9060/play/dvr_remote_sync",
    "unexpected source_url in upsert")
assert_true(type(first_items[1].config) == "table", "expected remote config payload in upsert")
assert_eq(first_items[1].config.backup_type, "disabled", "remote config backup_type must be disabled")
assert_true(type(first_items[1].config.input) == "table", "remote config input must be array")
assert_eq(#first_items[1].config.input, 1, "remote config must keep exactly one source input")
assert_eq(first_items[1].config.input[1], "http://admin:admin@127.0.0.1:9060/play/dvr_remote_sync",
    "remote config input[1] must be source_url")
assert_true(type(first_items[1].config.dvr) == "table", "remote config must include dvr section")
assert_eq(first_items[1].config.dvr.mode, "local", "remote config dvr.mode must be local")
assert_eq(first_items[1].config.dvr.backup_enabled, false, "remote config dvr.backup_enabled must stay false")
assert_eq(first_items[1].config.dvr.source_url, "http://admin:admin@127.0.0.1:9060/play/dvr_remote_sync",
    "remote config dvr.source_url must match source_url")
local first_record = captured.record_payloads[1] or {}
assert_eq(first_record.record_enabled, true, "remote record should be enabled")
assert_eq(tonumber(first_record.retention_days), 5, "unexpected retention days")
assert_true(type(first_record.stream_ids) == "table" and first_record.stream_ids[1] == "dvr_remote_target",
    "unexpected remote stream id in record payload")
assert_true(type(captured.links[1]) == "table", "expected remote link upsert")
assert_eq(captured.links[1].stream_id, "dvr_remote_sync", "unexpected linked stream id")
assert_eq(captured.links[1].dvr_server_id, "dvr1", "unexpected linked server id")
assert_eq(captured.links[1].dvr_stream_id, "dvr_remote_target", "unexpected linked remote stream id")

post_stream("/api/v1/streams", {
    id = "dvr_remote_sync",
    enabled = true,
    config = {
        id = "dvr_remote_sync",
        name = "DVR Remote Sync",
        type = "spts",
        input = {
            "http://origin/live",
        },
        dvr = {
            mode = "remote",
            remote_server_id = "dvr1",
            remote_stream_id = "dvr_remote_target",
            remote_channel_enabled = false,
            enabled = true,
            backup_enabled = false,
            retention_days = 5,
            path = "/media/remote-dvr",
        },
    },
})

assert_eq(captured.upsert_calls, 1, "remote upsert must not run when remote channel is off")
assert_eq(captured.record_calls, 2, "expected second remote bulk record call")
local second_record = captured.record_payloads[2] or {}
assert_eq(second_record.record_enabled, false, "remote record should be disabled when channel is off")
assert_true(type(second_record.stream_ids) == "table" and second_record.stream_ids[1] == "dvr_remote_target",
    "unexpected remote stream id in second record payload")

log.info("[unit] stream_dvr_remote_autosync_unit ok")
astra.exit()
